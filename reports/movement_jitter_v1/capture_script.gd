extends SceneTree
# Real physics loop: short clicks in front of the witch, every rendered frame captured close-up.
var arena
func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()
func _init():
	var out := "C:/Users/USER/AppData/Local/Temp/claude/C--Users-USER--claude-spares-spare-NbE0Cv/9f7a8877-8b97-4b6a-8726-6dedc05ff8b6/scratchpad/poses"
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	for i in 5: await process_frame
	arena.load_map("alley_v2")
	for i in 40: await physics_frame
	for e in arena.enemies.values(): e.cooldown = 9999.0
	arena.config.enemy_speed = 0.0
	var start: Vector3 = arena.player.position
	var shots: Array[Image] = []
	var log := []
	for plan in [[Vector3(0.35, 0, 0.2), 14], [Vector3(-0.3, 0, -0.45), 14], [Vector3(1.6, 0, 1.2), 21]]:
		arena.set_destination(arena.player.position + plan[0])
		for f in plan[1]:
			await physics_frame
			var img := await grab()
			var sp: Vector2 = arena.camera.unproject_position(arena.player.position + Vector3.UP * 0.8)
			var r := Rect2i(int(sp.x) - 110, int(sp.y) - 130, 220, 260)
			shots.append(img.get_region(r))
			log.append("%s moving=%s pos=%s state=%s w=%.2f lag=%.0f" % [f, arena.moving, arena.player.position.snapped(Vector3.ONE*0.001), arena.player_visual._state, arena.player_visual._run_weight, rad_to_deg(arena.player_visual._turn_lag)])
		for i in 20: await physics_frame
	var cols := 7
	var sheet := Image.create(cols * 220, int(ceil(shots.size() / float(cols))) * 260, false, shots[0].get_format())
	for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, 220, 260), Vector2i((i % cols) * 220, (i / cols) * 260))
	sheet.save_png(out + "/jitter_frames_after.png")
	for l in log: print(l)
	quit()
