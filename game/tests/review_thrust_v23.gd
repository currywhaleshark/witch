extends SceneTree
## Thrust v23 review: the previous v20 thrust and the new one sampled at the same phases on the
## real player visual, from the game camera, the side and the front. Writes contact strips.
var output := "res://../reports/thrust_v23/review"
const PHASES := [0.0, 0.12, 0.24, 0.36, 0.42, 0.46, 0.5, 0.56, 0.64, 0.76, 0.88, 1.0]

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	var arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false)
	for i in 10: await process_frame
	# Pausing keeps the arena from resampling the idle pose over the one under review.
	arena.paused = true
	arena.hud.visible = false
	for id in arena.enemies.keys(): arena.enemies[id].body.visible = false
	var v = arena.player_visual
	arena.player.position = Vector3.ZERO
	v.rotation = Vector3.ZERO
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; root.add_child(cam)
	var views := {"game": null, "side": Vector3(-4, 0.85, 0), "front": Vector3(0, 0.85, -4)}
	var new_clip: String = v._clips.attack_thrust
	var saved := 0
	for version in ["v20", "v23"]:
		v._clips.attack_thrust = "combat_thrust_rh_v20" if version == "v20" else new_clip
		v._attack_clip_kind = "attack_thrust"
		for view in views:
			var row: Array[Image] = []
			if views[view] == null:
				cam.current = false; arena.camera.current = true
				arena.camera.size = 5.0; arena.place_camera(Vector3(0, 0.8, 0))
			else:
				arena.camera.current = false; cam.current = true; cam.size = 2.4
				cam.look_at_from_position(views[view], Vector3(0, 0.8, -0.3))
			for phase in PHASES:
				v._sample("attack", phase * v._length("attack"))
				var img := await grab()
				var c := Vector2(640, 400)
				if views[view] == null: c = arena.camera.unproject_position(Vector3(0, 0.7, 0))
				row.append(img.get_region(Rect2i(int(c.x) - 210, int(c.y) - 250, 420, 420)))
			var sheet := Image.create(420 * 6, 420 * 2, false, row[0].get_format())
			for i in row.size(): sheet.blit_rect(row[i], Rect2i(0, 0, 420, 420), Vector2i(420 * (i % 6), 420 * (i / 6)))
			assert(sheet.save_png(output.path_join("%s_%s.png" % [version, view])) == OK)
			saved += 1
	v._clips.attack_thrust = new_clip
	print("THRUST_V23_REVIEW_DONE saved=%d" % saved)
	quit(0)
