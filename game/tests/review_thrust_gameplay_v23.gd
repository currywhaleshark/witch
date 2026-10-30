extends SceneTree
## Real arena attack with the v23 thrust variant forced on the presentation side: the strike
## goes through the normal basic-attack path; every second frame is kept at game scale and close.
var output := "res://../reports/thrust_v23/review"

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _init() -> void:
	root.size = Vector2i(1280, 800)
	var arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false)
	for i in 10: await process_frame
	for id in arena.enemies.keys():
		arena.enemies[id].body.queue_free(); arena.enemies.erase(id)
	arena.hud.visible = false
	arena.config.enemy_speed = 0.0
	arena.player.position = Vector3.ZERO
	arena.spawn_enemy("dummy", Vector3(1.3, 0, -0.6), false, "normal", "rag")
	arena.enemies.dummy.cooldown = 9999.0; arena.enemies.dummy.hp = 9999.0; arena.enemies.dummy.max_hp = 9999.0
	for i in 6:
		await physics_frame; arena._physics_process(1.0 / 60.0)
	var v = arena.player_visual
	var shots: Array[Image] = []
	arena.request_slot("lmb", {"enemy_id": "dummy"})
	for f in 60:
		if v._motion_kind == "attack" and v._attack_clip_kind != "attack_thrust":
			v._attack_clip_kind = "attack_thrust"
		await physics_frame; arena._physics_process(1.0 / 60.0)
		if f % 2 == 0:
			arena.camera.size = 3.4; arena.place_camera(Vector3(0.6, 0.6, -0.3))
			var img := await grab()
			shots.append(img.get_region(Rect2i(390, 150, 500, 500)))
	var cols := 6
	var sheet := Image.create(cols * 300, int(ceil(shots.size() / float(cols))) * 300, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s := shots[i]; s.convert(Image.FORMAT_RGBA8); s.resize(296, 296, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(s, Rect2i(0, 0, 296, 296), Vector2i((i % cols) * 300 + 2, int(i / cols) * 300 + 2))
	assert(sheet.save_png(output.path_join("gameplay_thrust_sheet.png")) == OK)
	print("THRUST_V23_GAMEPLAY_DONE frames=%d" % shots.size())
	quit(0)
