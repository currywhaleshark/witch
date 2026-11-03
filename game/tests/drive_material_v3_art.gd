extends SceneTree
const Old = preload("res://tests/helpers/drive_tree_v2_demo.gd")
const New = preload("res://tests/helpers/drive_material_v3_demo.gd")
const World = preload("res://tests/helpers/firearm_review_world.gd")
const IDS = ["guillotine", "guillotine_saw", "guillotine_lock", "restraint_winch", "hydraulic_press", "compound_executor", "shock_frame", "broad_cutter"]
var output := ""
var count := 0
var textures: Dictionary = {}
var metrics: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
	count += 1

func run() -> void:
	var world := World.new()
	root.add_child(world)
	for id in IDS:
		var old := Old.new()
		old.configure(id)
		world.add_child(old)
		old.initialize(world)
		old.set_process(false)
		var current := New.new()
		current.configure(id)
		world.add_child(current)
		current.initialize(world)
		current.set_process(false)
		var old_mechanism: Dictionary = old.manifest.duplicate(true)
		var new_mechanism: Dictionary = current.manifest.duplicate(true)
		for field in ["materials", "texture_set"]:
			old_mechanism.erase(field)
			new_mechanism.erase(field)
		check(old_mechanism == new_mechanism, id + " mechanism metadata changed")
		check(old.parts.size() == current.parts.size(), id + " part count changed")
		for part in current.parts:
			check(part.mesh.mesh.get_surface_count() == 1, id + " extra material surfaces")
			var material: StandardMaterial3D = part.materials[0]
			check(material.albedo_texture != null, id + " missing albedo")
			check(material.normal_enabled and material.normal_texture != null, id + " missing normal")
			check(material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, id + " roughness channel")
			check(material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, id + " metallic channel")
			check(material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, id + " AO channel")
			for texture in [material.albedo_texture, material.normal_texture, material.roughness_texture, material.metallic_texture, material.ao_texture]:
				check(texture != null, id + " missing texture")
				var path: String = texture.resource_path
				check(path.begins_with("res://assets/weapons/drive_material_v3/textures/"), id + " old texture reference")
				if textures.has(path): check(textures[path] == texture, id + " duplicated texture resource")
				else: textures[path] = texture
			if current.info[part.name].surface == "core":
				check(material.emission_texture != null, id + " missing core emission")
			else: check(material.emission_texture == null, id + " emission leaking onto ordinary surfaces")
		var modes: Array = ["single", "pull", "bind"] if id == "restraint_winch" else ["single"]
		for mode_name in modes:
			old.winch_mode = mode_name
			current.winch_mode = mode_name
			for t in [0.0, .18, .28, .48, .59, .66, .8, 1.12, 1.24, 1.28, 1.40, 1.55, 1.80, 2.0, 2.45, 2.60, 2.90, 3.15, 3.40, .50]:
				old.sample_demo(t)
				current.sample_demo(t)
				for i in old.parts.size():
					check(old.parts[i].name == current.parts[i].name, id + " part naming")
					check(old.parts[i].mesh.transform.is_equal_approx(current.parts[i].mesh.transform), id + " motion changed")
					check(old.parts[i].mesh.visible == current.parts[i].mesh.visible, id + " visibility changed")
				check(old.cables.size() == current.cables.size(), id + " cable count")
				for i in old.cables.size():
					check(old.cables[i].transform.is_equal_approx(current.cables[i].transform), id + " cable motion changed")
		metrics[id] = {"parts": current.parts.size(), "motion_samples": modes.size() * 20}
		old.queue_free()
		current.queue_free()
		await process_frame
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"passed": failures.is_empty(), "checks": count, "failures": failures, "models": metrics, "shared_surface_textures": textures.keys()}, "  "))
	print("DRIVE_MATERIAL_TEST_COMPLETE ", count)
	quit(0 if failures.is_empty() else 1)
