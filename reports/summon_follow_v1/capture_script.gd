extends SceneTree
# Three automatons follow the walking witch, then gang up on one enemy; every fourth frame kept.
var arena
var shots: Array[Image] = []
var log: Array[String] = []
func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()
func film(frames: int, label: String) -> void:
	for f in frames:
		await physics_frame
		if f % 4 == 0:
			var img := await grab()
			var c: Vector2 = arena.camera.unproject_position(arena.player.position)
			shots.append(img.get_region(Rect2i(int(c.x) - 250, int(c.y) - 230, 500, 380)))
			var gaps := []
			for i in arena.allies.size():
				for j in range(i + 1, arena.allies.size()):
					var a: Vector3 = arena.allies[i].node.position; var b: Vector3 = arena.allies[j].node.position
					gaps.append(snappedf(Vector2(a.x - b.x, a.z - b.z).length(), 0.01))
			var facing := []
			for ally in arena.allies:
				facing.append(snappedf(rad_to_deg(ally.node.rotation.y), 1))
			log.append("%s f%03d gaps=%s yaw=%s" % [label, f, gaps, facing])
func _init():
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	for i in 10: await physics_frame
	for id in arena.enemies.keys():
		arena.enemies[id].body.queue_free(); arena.enemies.erase(id)
	arena.config.enemy_speed = 0.0
	arena.config.summon_lifetime = 999.0
	arena.config.automaton_node = "base"
	arena.spawn_enemy("far", Vector3(-11, 0, -11), false, "normal", "rag")
	arena.enemies.far.cooldown = 9999.0
	arena.hp = 99999.0
	for i in 3:
		arena.spawn_ally(arena.automaton_spawn_position(arena.free_follow_slot()), true, "")
	await film(20, "settle")
	arena.set_destination(Vector3(4, 0, 3))
	await film(56, "walk_a")
	arena.set_destination(Vector3(-1, 0, -2))
	await film(56, "walk_b")
	arena.spawn_enemy("foe", arena.player.position + Vector3(2.2, 0, -1.2), false, "normal", "rag")
	arena.enemies.foe.cooldown = 9999.0; arena.enemies.foe.hp = 9999.0; arena.enemies.foe.max_hp = 9999.0
	await film(72, "fight")
	var cols := 6
	var sheet := Image.create(cols * 250, int(ceil(shots.size() / float(cols))) * 190, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s := shots[i]; s.convert(Image.FORMAT_RGBA8); s.resize(250, 190, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(s, Rect2i(0, 0, 250, 190), Vector2i((i % cols) * 250, (i / cols) * 190))
	sheet.save_png("C:/Users/USER/Documents/Projects/witch/reports/summon_follow_v1/follow_and_fight_sheet.png")
	var f := FileAccess.open("C:/Users/USER/Documents/Projects/witch/reports/summon_follow_v1/follow_and_fight_log.txt", FileAccess.WRITE)
	f.store_string("\n".join(log) + "\n")
	quit()
