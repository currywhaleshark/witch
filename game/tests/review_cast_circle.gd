extends SceneTree
## Casting circles through the real slot input: shotgun (firearm), shield (drive) and automaton
## (automation), plus a turret, from the press through release and fade, on the flat field.
var output := "res://../reports/cast_circle_v1"

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
	arena.spawn_enemy("far", Vector3(3.5, 0, -3.5), false, "normal", "rag")
	arena.enemies.far.cooldown = 9999.0; arena.enemies.far.hp = 9999.0; arena.enemies.far.max_hp = 9999.0
	arena.config.enemy_speed = 0.0
	arena.hud.visible = false
	arena.player.position = Vector3.ZERO
	var shots: Array[Image] = []
	var plans := [["rmb", {"ground": [3.0, 0, -3.0]}, ""], ["r", {}, "shield"], ["w", {"ground": [2.0, 0, -1.0]}, ""], ["e", {"ground": [2.5, 0, 1.5]}, ""]]
	for plan in plans:
		if plan[2] != "":
			arena.state = arena.rules.bind(arena.state, plan[0], plan[2])
		arena.state.mana = arena.state.max_mana
		arena.state.cooldowns.clear()
		arena.action_time = 0.0
		arena.request_slot(plan[0], plan[1])
		for f in 50:
			await physics_frame; arena._physics_process(1.0 / 60.0)
			if f in [2, 10, 20, 32, 44]:
				arena.camera.size = 4.2; arena.place_camera(arena.player.position)
				var img := await grab()
				var c: Vector2 = arena.camera.unproject_position(arena.player.position + Vector3.UP * 0.4)
				shots.append(img.get_region(Rect2i(int(c.x) - 260, int(c.y) - 250, 520, 420)))
		for f in 30:
			await physics_frame; arena._physics_process(1.0 / 60.0)
	var sheet := Image.create(520 * 5, 420 * 4, false, shots[0].get_format())
	for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, 520, 420), Vector2i(520 * (i % 5), 420 * (i / 5)))
	assert(sheet.save_png(output.path_join("cast_circle_sheet.png")) == OK)
	print("CAST_CIRCLE_REVIEW_DONE")
	quit(0)
