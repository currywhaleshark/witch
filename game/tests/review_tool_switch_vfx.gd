extends SceneTree
## Tool switch emphasis: bolt cutter, grinder, chainsaw and back to the bare staff through the
## real slot input, every second frame from the press, at game scale in the alley.
var output := "res://../reports/tool_switch_vfx_v1"

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _init() -> void:
	root.size = Vector2i(1280, 800)
	var arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false)
	for i in 10: await process_frame
	arena.load_map("alley_v2")
	for i in 6: await physics_frame
	for id in arena.enemies.keys():
		arena.enemies[id].body.queue_free(); arena.enemies.erase(id)
	arena.spawn_enemy("far", arena.player.position + Vector3(14, 0, 0), false, "normal", "rag")
	arena.enemies.far.cooldown = 9999.0
	arena.hud.visible = false
	var shots: Array[Image] = []
	for plan in [["q", "bolt_cutter"], ["r", "grinder"], ["r", "chainsaw"], ["r", "chainsaw"]]:
		if plan[0] == "r":
			arena.state = arena.rules.bind(arena.state, "r", plan[1])
		arena.state.mana = arena.state.max_mana
		arena.action_time = 0.0
		arena.request_slot(plan[0], {})
		for f in 24:
			await physics_frame; arena._physics_process(1.0 / 60.0)
			if f in [1, 4, 8, 14, 20]:
				arena.camera.size = 20.0 / 1.75 * arena.player_visual.MODEL_SCALE * 0.55
				arena.place_camera(arena.player.position)
				var img := await grab()
				var c: Vector2 = arena.camera.unproject_position(arena.player.position + Vector3.UP * 0.8)
				shots.append(img.get_region(Rect2i(int(c.x) - 200, int(c.y) - 220, 400, 400)))
		for f in 30:
			await physics_frame; arena._physics_process(1.0 / 60.0)
	var sheet := Image.create(400 * 5, 400 * 4, false, shots[0].get_format())
	for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, 400, 400), Vector2i(400 * (i % 5), 400 * (i / 5)))
	assert(sheet.save_png(output.path_join("tool_switch_sheet.png")) == OK)
	print("TOOL_SWITCH_REVIEW_DONE")
	quit(0)
