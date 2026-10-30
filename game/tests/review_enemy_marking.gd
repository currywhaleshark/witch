extends SceneTree
## Ground rings removed: normal / champion / elite enemies, one hovered (outlined), the witch and two
## summons, on the flat field and in the alley, at game scale and close up.
var output := "res://../reports/enemy_marking_v1"

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func stage(arena, map_id: String) -> void:
	if map_id != "":
		arena.load_map(map_id)
	for i in 6: await physics_frame
	for id in arena.enemies.keys():
		arena.enemies[id].body.queue_free(); arena.enemies.erase(id)
	arena.config.enemy_speed = 0.0
	arena.hud.visible = false
	var origin: Vector3 = arena.player.position
	var lineup := [["n_rag", "rag", "normal"], ["c_rag", "rag", "champion"], ["e_rag", "rag", "elite"], ["c_crow", "crow", "champion"], ["e_brute", "brute", "elite"]]
	for i in lineup.size():
		var spot: Vector3 = origin + Vector3(-1.6 + i * 1.5, 0, -2.6 + absf(i - 2) * 0.3)
		arena.spawn_enemy(lineup[i][0], spot, false, lineup[i][2], lineup[i][1])
		arena.enemies[lineup[i][0]].cooldown = 9999.0
	arena.config.summon_lifetime = 999.0
	arena.spawn_ally(arena.automaton_spawn_position(arena.free_follow_slot()), true, "")
	arena.spawn_ally(origin + Vector3(-1.4, 0, 0.4), false, "")
	for i in 20:
		await physics_frame; arena._physics_process(1.0 / 60.0)
	# The real hover path recomputes every frame; set the selection after it, as a hovered enemy would show.
	arena.dress_enemy(arena.enemies.c_rag, true)

func _init() -> void:
	root.size = Vector2i(1280, 800)
	var arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false)
	for i in 10: await process_frame
	var saved := 0
	for map_id in ["", "alley_v2"]:
		await stage(arena, map_id)
		var label: String = "flat" if map_id == "" else map_id
		for zoom in [{"name": "native", "size": 20.0 / 1.75 * arena.player_visual.MODEL_SCALE}, {"name": "close", "size": 5.5}]:
			arena.camera.size = zoom.size
			arena.place_camera(arena.player.position + Vector3(0, 0, -1.2))
			for frame in 3:
				var img := await grab()
				if frame == 2:
					assert(img.save_png(output.path_join("%s_%s.png" % [label, zoom.name])) == OK)
					saved += 1
	print("ENEMY_MARKING_REVIEW_DONE saved=%d" % saved)
	quit(0)
