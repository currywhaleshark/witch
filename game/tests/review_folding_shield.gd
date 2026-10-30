extends SceneTree
## Folding shield review through the real arena path: cast (R), assembly and opening, a blocked
## hit (block chance forced to 1 only for this capture), the duration ending, fold and scatter.
var output := "res://../reports/folding_shield_v1"
var arena
var shots: Array[Image] = []
var labels: Array[String] = []

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func film(frames: int, every: int, label: String, size: float) -> void:
	for f in frames:
		await physics_frame; arena._physics_process(1.0 / 60.0)
		if f % every == 0:
			arena.camera.size = size; arena.place_camera(arena.player.position)
			var img := await grab()
			var c: Vector2 = arena.camera.unproject_position(arena.player.position + Vector3.UP * 0.7)
			shots.append(img.get_region(Rect2i(int(c.x) - 230, int(c.y) - 230, 460, 460)))
			labels.append("%s %d" % [label, f])

func _init() -> void:
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false)
	for i in 10: await process_frame
	for id in arena.enemies.keys():
		arena.enemies[id].body.queue_free(); arena.enemies.erase(id)
	arena.spawn_enemy("far", Vector3(12, 0, 12), false, "normal", "rag")
	arena.enemies.far.cooldown = 9999.0
	arena.hud.visible = false
	arena.player.position = Vector3.ZERO
	arena.player_model.look_at(Vector3(1, 0, -1))
	for i in 4:
		await physics_frame; arena._physics_process(1.0 / 60.0)
	arena.request_slot("r", {})
	await film(36, 3, "cast", 3.2)
	var shield = arena.rules.skills.shield
	shield.block_base = 1.0; shield.block_cap = 1.0
	arena.damage_player(5.0, "normal")
	await film(18, 3, "block", 3.2)
	arena.shield_time = 0.05
	await film(48, 4, "end", 3.2)
	var cols := 6
	var sheet := Image.create(cols * 300, int(ceil(shots.size() / float(cols))) * 300, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s := shots[i]; s.convert(Image.FORMAT_RGBA8); s.resize(296, 296, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(s, Rect2i(0, 0, 296, 296), Vector2i((i % cols) * 300 + 2, int(i / cols) * 300 + 2))
	assert(sheet.save_png(output.path_join("shield_sequence.png")) == OK)
	print("FOLDING_SHIELD_REVIEW_DONE frames=%d %s" % [shots.size(), labels])
	quit(0)
