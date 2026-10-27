extends SceneTree
## Compare the actual packaged-scene importer and 8-weight skinning with Blender.
## Run with the game project and -- --reference=<export reference> --report=<json>.
var parts := "res://assets/characters/player/combat_v12/"
var version := "v12"
var reference_path := ""
var report_path := ""
var character: Node3D
var cloth_samples: Dictionary = {}
var results: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--reference="): reference_path = argument.trim_prefix("--reference=")
		elif argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--parts="): parts = argument.trim_prefix("--parts=").trim_suffix("/") + "/"
		elif argument.begins_with("--version="): version = argument.trim_prefix("--version=")
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func prepare_cloth_samples(reference: Dictionary) -> bool:
	for garment: String in reference.animation.cloth_rest_samples:
		var mesh := character.find_child(garment, true, false) as MeshInstance3D
		if mesh == null or mesh.skin == null: return false
		var records: Array = []
		for sample in reference.animation.cloth_rest_samples[garment]:
			var p: Array = sample.rest_gltf
			var rest := Vector3(p[0], p[1], p[2])
			var best_distance := INF
			var best_surface := -1
			var best_vertex := -1
			for surface in mesh.mesh.get_surface_count():
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for i in vertices.size():
					var distance := vertices[i].distance_squared_to(rest)
					if distance < best_distance:
						best_distance = distance; best_surface = surface; best_vertex = i
			if best_distance >= 0.000000001: return false
			records.append({"surface": best_surface, "vertex": best_vertex})
		cloth_samples[garment] = records
	return true

func cloth_error(sample: Dictionary) -> float:
	var worst := 0.0
	for garment: String in sample.cloth_positions_gltf:
		var mesh := character.find_child(garment, true, false) as MeshInstance3D
		var posed := mesh.bake_mesh_from_current_skeleton_pose()
		if posed == null: return INF
		var to_body: Transform3D = character.body.global_transform.affine_inverse() * mesh.global_transform
		var expected: Array = sample.cloth_positions_gltf[garment]
		var records: Array = cloth_samples[garment]
		if expected.size() != records.size(): return INF
		var surfaces: Array = []
		for surface in posed.get_surface_count():
			surfaces.append(posed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
		for i in records.size():
			var record: Dictionary = records[i]
			var position: Vector3 = surfaces[record.surface][record.vertex]
			var p: Array = expected[i]
			worst = maxf(worst, (to_body * position).distance_to(Vector3(p[0], p[1], p[2])))
	return worst

func run() -> void:
	if reference_path.is_empty() or report_path.is_empty():
		fail("Missing reference/report paths"); return
	var reference = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	if not reference is Dictionary:
		fail("Invalid reference JSON"); return
	character = load("res://scripts/modular_character_runtime.gd").new()
	root.add_child(character)
	if not character.initialize(parts + "body_standard_" + version + ".glb"):
		fail(character.last_error); return
	if not character.replace_parts({
		"hair": {"asset": parts + "hair_semilong_" + version + ".glb"},
		"eyes": {"asset": parts + "eyes_neutral_" + version + ".glb"},
		"outfit": {"asset": parts + "outfit_civilian_" + version + ".glb", "hide_body_regions": ["torso", "arms", "lowerlegs", "feet"]}}):
		fail(character.last_error); return
	var player: AnimationPlayer = character.animation_player
	var skeleton: Skeleton3D = character.skeleton
	var expected_bones := int(reference.animation.shared_bones)
	if skeleton.get_bone_count() != expected_bones or not prepare_cloth_samples(reference):
		fail("Imported skeleton/rest garment mismatch"); return
	for clip in reference.animation.clips:
		if not player.has_animation(clip.name):
			fail("Missing animation " + clip.name); return
		var animation := player.get_animation(clip.name)
		if animation.get_track_count() != expected_bones * 3:
			fail("Constant rest tracks lost: " + clip.name + " tracks=" + str(animation.get_track_count())); return
		animation.loop_mode = Animation.LOOP_NONE
		var worst_bone := 0.0
		var worst_cloth := 0.0
		var worst_location := ""
		for sample in clip.samples:
			skeleton.reset_bone_poses()
			player.play(clip.name)
			player.seek((sample.frame - clip.start) / 24.0, true)
			player.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			worst_cloth = maxf(worst_cloth, cloth_error(sample))
			for bone_name: String in sample.bone_heads_gltf:
				var coordinates: Array = sample.bone_heads_gltf[bone_name]
				var expected := Vector3(coordinates[0], coordinates[1], coordinates[2])
				var index := skeleton.find_bone(bone_name)
				if index < 0:
					fail("Missing bone " + bone_name); return
				var actual: Vector3 = character.body.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(index).origin)
				var distance := actual.distance_to(expected)
				if distance > worst_bone:
					worst_bone = distance; worst_location = bone_name + " frame=" + str(sample.frame)
		if worst_bone >= .0002 or worst_cloth >= .001:
			fail(clip.name + " bone=" + str(worst_bone) + " at " + worst_location + " cloth=" + str(worst_cloth)); return
		results.append({"clip": clip.name, "samples": clip.samples.size(), "tracks": animation.get_track_count(), "maximum_bone_head_error": worst_bone, "maximum_cloth_vertex_error": worst_cloth})
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		fail("Cannot write report"); return
	file.store_string(JSON.stringify({"passed": true, "bone_count": expected_bones, "source_reference": reference_path, "pose_checks": results, "scope": "PackedScene import, all bone heads, sampled actual 8-weight garment vertices; not arbitrary pose clearance."}, "  ") + "\n")
	print("COMBAT_POSE_PARITY_V12_OK ", results.size(), " clips")
	character.queue_free()
	await process_frame
	quit(0)
