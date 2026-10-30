extends SceneTree
## Potion glow review: each potion kind drunk in the alley, frames kept from the drink onward.
var output := "res://../reports/potion_glow_v1"

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
	for id in ["health_m", "mana_m", "rejuv_m", "speed"]:
		if not arena.config.potions.has(id):
			for key in arena.config.potions:
				if arena.config.potions[key].kind == "speed": id = key
		arena.potion_slots[0] = {"id": id, "count": 3}
		arena.potion_cooldowns.clear()
		arena.drink(0)
		for f in 30:
			await physics_frame; arena._physics_process(1.0 / 60.0)
			if f in [2, 8, 16, 26]:
				arena.camera.size = 4.0; arena.place_camera(arena.player.position)
				var img := await grab()
				var c: Vector2 = arena.camera.unproject_position(arena.player.position + Vector3.UP * 0.7)
				shots.append(img.get_region(Rect2i(int(c.x) - 200, int(c.y) - 220, 400, 400)))
		for f in 20:
			await physics_frame; arena._physics_process(1.0 / 60.0)
	var sheet := Image.create(400 * 4, 400 * 4, false, shots[0].get_format())
	for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, 400, 400), Vector2i(400 * (i % 4), 400 * (i / 4)))
	assert(sheet.save_png(output.path_join("potion_glow_sheet.png")) == OK)
	print("POTION_GLOW_REVIEW_DONE")
	quit(0)
