extends SceneTree
## Open folding shield seen from the game camera with the witch facing four ways.
var output := "res://../reports/folding_shield_v1"

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
	arena.spawn_enemy("far", Vector3(12, 0, 12), false, "normal", "rag")
	arena.enemies.far.cooldown = 9999.0
	arena.hud.visible = false
	arena.player.position = Vector3.ZERO
	arena.request_slot("r", {})
	var shots: Array[Image] = []
	var tick := 0
	for direction in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, -1), Vector3(-1, 0, 1)]:
		arena.player_model.look_at(direction)
		arena.shield_time = 6.0
		for i in 40:
			await physics_frame; arena._physics_process(1.0 / 60.0)
		tick += 40
		print("facing ", direction, " t=", tick / 60.0, " shield_time=", arena.shield_time, " visual=", arena.shield_visual.debug_state() if is_instance_valid(arena.shield_visual) else "none")
		arena.camera.size = 3.2; arena.place_camera(arena.player.position)
		var img := await grab()
		var c: Vector2 = arena.camera.unproject_position(Vector3.UP * 0.7)
		shots.append(img.get_region(Rect2i(int(c.x) - 230, int(c.y) - 230, 460, 460)))
	var sheet := Image.create(460 * 3, 460 * 2, false, shots[0].get_format())
	for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, 460, 460), Vector2i(460 * (i % 3), 460 * (i / 3)))
	assert(sheet.save_png(output.path_join("shield_facings.png")) == OK)
	print("SHIELD_FACINGS_DONE")
	quit(0)
