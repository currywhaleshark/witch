extends Node3D
## Imported PackedScene adapter for one compatible modular character family.
## All replacement assets are staged and checked before changing visible parts.
## References: Godot Skin, Skeleton3D and GLTFDocument class documentation.

var body: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var slots: Dictionary = {}
var hidden_regions_by_slot: Dictionary = {}
var last_error := ""
var _texture_cache: Dictionary = {}

func _load_gltf(path: String) -> Node3D:
	if not ResourceLoader.exists(path, "PackedScene"):
		last_error = "asset_missing: " + path
		return null
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		last_error = "invalid_imported_scene: " + path
		return null
	# Keep Godot's imported mesh arrays (including 8 bone influences) intact.
	# This also works from an exported PCK, where raw GLB file I/O may not.
	return packed.instantiate() as Node3D

func initialize(body_path: String) -> bool:
	if body != null:
		last_error = "body_already_initialized"
		return false
	var candidate := _load_gltf(body_path)
	if candidate == null:
		return false
	var rigs := candidate.find_children("*", "Skeleton3D", true, false)
	var players := candidate.find_children("*", "AnimationPlayer", true, false)
	if rigs.size() != 1 or players.size() != 1:
		candidate.free()
		last_error = "body_requires_one_skeleton_and_animation_player"
		return false
	body = candidate
	add_child(body)
	skeleton = rigs[0]
	animation_player = players[0]
	_share_textures(body)
	return true

func _share_textures(root_node: Node) -> void:
	for mesh in root_node.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var material = mesh.get_active_material(index)
			if material is StandardMaterial3D and material.albedo_texture != null:
				var texture: Texture2D = material.albedo_texture
				var pixels := texture.get_image()
				var hasher := HashingContext.new()
				hasher.start(HashingContext.HASH_SHA256)
				hasher.update(pixels.get_data())
				var key := str(pixels.get_size()) + ":" + str(pixels.get_format()) + ":" + hasher.finish().hex_encode()
				if _texture_cache.has(key):
					material.albedo_texture = _texture_cache[key]
				else:
					_texture_cache[key] = texture

func _compatible(other: Skeleton3D) -> bool:
	if other.get_bone_count() != skeleton.get_bone_count():
		last_error = "bone_count_mismatch"
		return false
	for index in other.get_bone_count():
		var bone_name := other.get_bone_name(index)
		var existing := skeleton.find_bone(bone_name)
		if existing < 0:
			last_error = "missing_bone: " + bone_name
			return false
		var parent := other.get_bone_parent(index)
		var expected_parent := skeleton.get_bone_parent(existing)
		if (parent == -1) != (expected_parent == -1):
			last_error = "parent_mismatch: " + bone_name
			return false
		if parent >= 0 and other.get_bone_name(parent) != skeleton.get_bone_name(expected_parent):
			last_error = "parent_mismatch: " + bone_name
			return false
		if not other.get_bone_global_rest(index).is_equal_approx(skeleton.get_bone_global_rest(existing)):
			last_error = "rest_pose_mismatch: " + bone_name
			return false
	return true

func _stage_part(path: String, slot: String, auxiliary_hair: bool = false) -> Node3D:
	var donor := _load_gltf(path)
	if donor == null:
		return null
	donor.visible = false
	add_child(donor)
	var rigs := donor.find_children("*", "Skeleton3D", true, false)
	var meshes := donor.find_children("*", "MeshInstance3D", true, false)
	if rigs.size() != 1 or meshes.is_empty():
		last_error = "part_requires_one_skeleton_and_meshes"
		donor.free()
		return null
	var other: Skeleton3D = rigs[0]
	if auxiliary_hair:
		# Optional per-hairstyle bones live in their own skeleton. Only the two
		# explicit anchor rests must match; ordinary body/eye/outfit checks stay strict.
		var valid := slot == "hair" and other.get_bone_count() == 8
		for anchor in ["DEF-head", "DEF-chest"]:
			var index := other.find_bone(anchor)
			var shared := skeleton.find_bone(anchor)
			valid = valid and index >= 0 and shared >= 0
			if index >= 0 and shared >= 0:
				valid = valid and other.get_bone_global_rest(index).is_equal_approx(skeleton.get_bone_global_rest(shared))
		var expected := ["DEF-head","DEF-chest","DEF-hair.01.L","DEF-hair.02.L","DEF-hair.01.R","DEF-hair.02.R","DEF-hair.01.Back","DEF-hair.02.Back"]
		var parents := {"DEF-head":"","DEF-chest":"","DEF-hair.01.L":"DEF-head","DEF-hair.02.L":"DEF-hair.01.L","DEF-hair.01.R":"DEF-head","DEF-hair.02.R":"DEF-hair.01.R","DEF-hair.01.Back":"DEF-head","DEF-hair.02.Back":"DEF-hair.01.Back"}
		for index in other.get_bone_count():
			var name := String(other.get_bone_name(index))
			valid = valid and name in expected
			var parent := other.get_bone_parent(index)
			var parent_name := String(other.get_bone_name(parent)) if parent >= 0 else ""
			valid = valid and parents.get(name,"invalid") == parent_name
		for mesh: MeshInstance3D in meshes:
			valid = valid and mesh.skin != null
			if mesh.skin == null: continue
			for bind in mesh.skin.get_bind_count():
				var name := mesh.skin.get_bind_name(bind)
				var index := other.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)
				valid = valid and index >= 0 and index < other.get_bone_count()
				if index >= 0 and index < other.get_bone_count():
					valid = valid and mesh.skin.get_bind_pose(bind).is_equal_approx(other.get_bone_global_rest(index).affine_inverse())
		if not valid:
			last_error = "invalid_auxiliary_hair_rig"
			donor.free()
			return null
		donor.name = "Slot_hair"
		donor.set_meta("auxiliary_hair", true)
		_share_textures(donor)
		return donor
	if not _compatible(other):
		donor.free()
		return null
	var staged := Node3D.new()
	staged.name = "Slot_" + slot
	staged.visible = false
	body.add_child(staged)
	for mesh: MeshInstance3D in meshes:
		if mesh.skin == null:
			last_error = "unskinned_part_mesh: " + mesh.name
			staged.free()
			donor.free()
			return null
		var skin: Skin = mesh.skin.duplicate()
		for bind in skin.get_bind_count():
			var bone_name := skin.get_bind_name(bind)
			if bone_name.is_empty():
				var old_index := skin.get_bind_bone(bind)
				if old_index < 0 or old_index >= other.get_bone_count():
					last_error = "invalid_skin_binding"
					staged.free()
					donor.free()
					return null
				bone_name = other.get_bone_name(old_index)
			var index := skeleton.find_bone(bone_name)
			if index < 0 or not skin.get_bind_pose(bind).is_equal_approx(other.get_bone_global_rest(other.find_bone(bone_name)).affine_inverse()):
				last_error = "bind_matrix_mismatch: " + bone_name
				staged.free()
				donor.free()
				return null
			skin.set_bind_name(bind, bone_name)
			skin.set_bind_bone(bind, index)
		var relative := donor.global_transform.affine_inverse() * mesh.global_transform
		mesh.get_parent().remove_child(mesh)
		staged.add_child(mesh)
		mesh.transform = relative
		mesh.skin = skin
		mesh.skeleton = mesh.get_path_to(skeleton)
		mesh.visible = true
		mesh.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 2.6, 2.4))
	donor.free()
	_share_textures(staged)
	return staged

func replace_parts(request: Dictionary) -> bool:
	last_error = ""
	if body == null:
		last_error = "body_not_initialized"
		return false
	var staged: Dictionary = {}
	for slot in request:
		if slot not in ["hair", "eyes", "outfit"] or not request[slot] is Dictionary:
			last_error = "invalid_slot"
			break
		var regions = request[slot].get("hide_body_regions", [])
		if not request[slot].get("asset", "") is String or not regions is Array or not request[slot].get("auxiliary_hair",false) is bool:
			last_error = "invalid_part_contract"
			break
		for region in regions:
			if region not in ["torso","arms","hands","pelvis","upperlegs","lowerlegs","feet"]:
				last_error = "unknown_body_region"
				break
		if not last_error.is_empty(): break
		var path: String = request[slot].get("asset", "")
		if path.is_empty():
			staged[slot] = null
		else:
			staged[slot] = _stage_part(path, slot, request[slot].get("auxiliary_hair", false))
			if staged[slot] == null:
				break
	if not last_error.is_empty():
		for part in staged.values():
			if is_instance_valid(part):
				part.free()
		return false
	# One synchronous commit. Skeleton, body, player, timeline and caller state
	# retain the same instances; no animation restart is performed here.
	for slot in staged:
		if slots.has(slot) and is_instance_valid(slots[slot]):
			slots[slot].free()
		slots[slot] = staged[slot]
		# Removal always reveals this slot's body regions, even when a caller
		# reuses an old request dictionary that still contains its hide list.
		hidden_regions_by_slot[slot] = request[slot].get("hide_body_regions", []).duplicate() if staged[slot] != null else []
		if staged[slot] != null:
			staged[slot].visible = true
	_apply_region_visibility()
	return true

func _apply_region_visibility() -> void:
	var hidden: Array = []
	for regions in hidden_regions_by_slot.values():
		hidden.append_array(regions)
	for mesh in body.find_children("Body_*", "MeshInstance3D", true, false):
		var region: String = str(mesh.name).trim_prefix("Body_").trim_suffix("_v7").to_lower()
		mesh.visible = region not in hidden

func tint_part(slot: String, tint: Color) -> bool:
	# Low-level multiplier; WHITE preserves the authored texture exactly.
	if not slots.has(slot) or not is_instance_valid(slots[slot]):
		return false
	for mesh in slots[slot].find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var original = mesh.get_active_material(index)
			if original is StandardMaterial3D:
				var material: StandardMaterial3D = original.duplicate()
				material.albedo_color = tint
				mesh.set_surface_override_material(index, material)
	return true

func apply_appearance_colors(hair_hex: String, iris_hex: String) -> bool:
	# Public appearance values are absolute swatches. Convert relative to the
	# approved default swatches so loading the default does not darken the atlas.
	if not Color.html_is_valid(hair_hex) or not Color.html_is_valid(iris_hex):
		last_error = "invalid_appearance_color"
		return false
	if not is_instance_valid(slots.get("hair")) or not is_instance_valid(slots.get("eyes")):
		last_error = "color_slots_not_loaded"
		return false
	var hair_color := Color(hair_hex).srgb_to_linear()
	var iris_color := Color(iris_hex).srgb_to_linear()
	var hair_reference := Color("#282630").srgb_to_linear()
	var iris_reference := Color("#72707A").srgb_to_linear()
	var hair_multiplier := Color(hair_color.r/hair_reference.r, hair_color.g/hair_reference.g, hair_color.b/hair_reference.b)
	var iris_multiplier := Color(iris_color.r/iris_reference.r, iris_color.g/iris_reference.g, iris_color.b/iris_reference.b)
	return tint_part("hair", hair_multiplier) and tint_part("eyes", iris_multiplier)
