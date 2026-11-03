extends "res://tests/review_drive_tree_v1.gd"
const Previous = preload("res://tests/helpers/drive_tree_v2_demo.gd")
const Current = preload("res://tests/helpers/drive_material_v3_demo.gd")
const MATERIAL_IDS = ["guillotine", "guillotine_saw", "guillotine_lock", "restraint_winch", "hydraulic_press", "compound_executor", "broad_cutter"]
var preview_only := false

func world_scene() -> Node3D:
	var world := super.world_scene()
	var environment: Environment = world.find_children("*", "WorldEnvironment", true, false)[0].environment
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("53677b")
	sky_material.sky_horizon_color = Color("b4c1c7")
	sky_material.ground_horizon_color = Color("9caaac")
	sky_material.ground_bottom_color = Color("34424b")
	sky_material.sky_energy_multiplier = .65
	sky_material.ground_energy_multiplier = .50
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	return world

func run() -> void:
	preview_only = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1440, 800)
	var world := world_scene()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var player := Player.new()
	world.add_child(player)
	assert(player.initialize())
	player.set_process(false)
	player._sample("idle", .5)
	player.hide()
	for id in MATERIAL_IDS:
		var old := Previous.new()
		old.configure(id)
		world.add_child(old)
		old.initialize(world)
		old.set_process(false)
		var revised := Current.new()
		revised.configure(id)
		world.add_child(revised)
		revised.initialize(world)
		revised.set_process(false)
		var low: Vector3 = revised.point(revised.manifest.aabb_godot.min)
		var high: Vector3 = revised.point(revised.manifest.aabb_godot.max)
		var span: float = maxf(maxf((high-low).x, (high-low).y), (high-low).z)
		var center: Vector3 = (low + high) * .5
		var offset: float = maxf(1.05, (high-low).x * .72)
		old.position.x = -offset
		revised.position.x = offset
		if id == "restraint_winch":
			span = 2.2
			center.z -= .45
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(span * 1.22, (offset * 2.0 + (high-low).x + .7) / 1.6)
		camera.position = center + Vector3(.7, 2.5, -10) * 2
		camera.look_at(center)
		old.sample_demo(.68)
		revised.sample_demo(.68)
		await capture("compare/%s.jpg" % id)
		old.position.x = offset
		revised.position.x = -offset
		camera.position = center + Vector3(-1.4, 2.0, 10) * 2
		camera.look_at(center)
		await capture("rear/%s.jpg" % id)
		old.position.x = -offset
		revised.position.x = offset
		camera.position = center + Vector3(.7, 2.5, -10) * 2
		camera.look_at(center)
		if not preview_only:
			var variants: Array = ["single", "pull", "bind"] if id == "restraint_winch" else ["base"]
			for variant in variants:
				old.winch_mode = variant
				revised.winch_mode = variant
				var seq: String = "motion_%s_%s" % [id, variant]
				for frame in 84:
					old.sample_demo(frame / 24.0)
					revised.sample_demo(frame / 24.0)
					await capture("%s/%03d.jpg" % [seq, frame])
				sequences.append({"id": seq, "asset": id, "variant": variant, "frames": 84, "fps": 24})
		old.sample_demo(.68)
		revised.sample_demo(.68)
		old.hide()
		revised.position.x = 0
		root.size = Vector2i(960, 760)
		place_camera(camera, center, span * 1.15)
		await capture("close/%s.jpg" % id)
		root.size = Vector2i(1280, 800)
		player.show()
		player.position = Vector3((high-low).x * .5 + .6, 0, 0)
		camera.rotation_degrees = Vector3(-30, 45, 0)
		camera.size = 20.0 / 1.75 * player.MODEL_SCALE
		camera.position = Vector3(.5, .55, 0) + camera.basis.z * 30
		await capture("native/%s.jpg" % id)
		player.hide()
		root.size = Vector2i(1440, 800)
		old.queue_free()
		revised.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	await shock_frames()
	FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": true, "captures": captures, "sequences": sequences, "left": "material_v3", "right": "previous_v1_v2", "same_lighting": true, "lighting": "Existing studio plus the same neutral reflection sky on both models; game lighting untouched", "native_camera": "1280x800, selected 1.75x"}, "  "))
	print("DRIVE_MATERIAL_REVIEW_COMPLETE ", captures)
	quit()

func shock_frames() -> void:
	root.size = Vector2i(1440, 800)
	var world := world_scene()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var players: Array = []
	var demos: Array = []
	for side in [-1, 1]:
		var player := Player.new()
		world.add_child(player)
		assert(player.initialize())
		player.set_process(false)
		player.position.x = side * .7
		var demo = Current.new() if side == 1 else Previous.new()
		demo.configure("shock_frame")
		world.add_child(demo)
		demo.initialize(world)
		demo.set_process(false)
		demo.reparent(player.runtime.skeleton, false)
		demo.skeleton = player.runtime.skeleton
		players.append(player)
		demos.append(demo)
	for form in ["civilian", "transformed"]:
		for i in 2:
			assert(players[i].set_form(form))
			players[i]._sample("idle", .5)
			demos[i].sample_demo(1.0)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.1
		camera.position = Vector3(1, 1.5, 8)
		camera.look_at(Vector3(0, .78, 0))
		# The rear-facing camera reverses screen left/right. Swap comparison positions.
		players[0].position.x = .7
		players[1].position.x = -.7
		await capture("compare/shock_frame_%s.jpg" % form)
		if not preview_only:
			var seq: String = "shock_frame_%s_run" % form
			for frame in 49:
				for i in 2:
					players[i]._sample("run", players[i]._length("run") * frame / 48.0)
					demos[i].sample_demo(1.0)
				await capture("%s/%03d.jpg" % [seq, frame])
			sequences.append({"id": seq, "asset": "shock_frame", "variant": form, "frames": 49, "fps": 24})
		players[0].hide()
		players[1].position.x = 0
		players[1]._sample("idle", .5)
		demos[1].sample_demo(1.0)
		root.size = Vector2i(1280, 800)
		camera.rotation_degrees = Vector3(-30, 45, 0)
		camera.size = 20.0 / 1.75 * players[1].MODEL_SCALE
		camera.position = Vector3(0, .4, 0) + camera.basis.z * 30
		await capture("native/shock_frame_%s.jpg" % form)
		players[0].show()
		root.size = Vector2i(1440, 800)
	world.queue_free()
	await process_frame
