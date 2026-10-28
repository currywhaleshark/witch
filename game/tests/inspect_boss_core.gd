extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(800, 800)
	var scene := Node3D.new(); root.add_child(scene)
	var art: Node3D = load("res://scripts/actor_visual.gd").create(scene, "latch")
	art.rotation.y = PI
	var environment := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color("24323b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color.WHITE; env.ambient_light_energy = .6
	environment.environment = env; scene.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-20,0); scene.add_child(light)
	var cam := Camera3D.new(); scene.add_child(cam); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 2.6
	cam.position = Vector3(1.05,1.6,2); cam.look_at(Vector3(0,1,0));cam.current=true
	var idx: int = art.skeleton.find_bone("part_077")
	for mesh in art.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var mat: StandardMaterial3D = mesh.get_active_material(s)
			print("CORE_MATERIAL ",s," ",mat.resource_name," emission=",mat.emission_enabled," ",mat.emission," strength=",mat.emission_energy_multiplier)
	var out := ProjectSettings.globalize_path("res://../reports/boss_trial_v1/core_probe")
	DirAccess.make_dir_recursive_absolute(out)
	for i in 4:
		art.sample("idle",0)
		var at: Vector3 = art.skeleton.get_bone_pose_position(idx)
		art.skeleton.set_bone_pose_position(idx,at+Vector3(0,.10*i,0));art.skeleton.force_update_all_bone_transforms()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("shift_%d.png"%i))
	print("CORE_PROBE_DONE");scene.queue_free();await process_frame;quit(0)
