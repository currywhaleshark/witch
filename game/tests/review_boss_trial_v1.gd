extends SceneTree
const Shape = preload("res://scripts/shapes.gd")
var arena: Node3D
var output := ""
var records: Array = []
var events: Array = []
var saved := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func capture(path: String, square: bool = false) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if square:
		img = img.get_region(Rect2i(240, 0, 800, 800)); img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	assert(img.save_png(output.path_join(path)) == OK)
	saved += 1

func clear_actors() -> void:
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()
	for fx in arena.effects: fx.node.free()
	arena.effects.clear()
	for bolt in arena.bolts: bolt.node.free()
	arena.bolts.clear()

func suppress_hud() -> void:
	arena.hud.visible = false; arena.hover_ring.visible = false; arena.shield_ring.visible = false; arena.move_marker.visible = false
	for ring in arena.tool_rings.values(): ring.visible = false

func run() -> void:
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.set_process_input(false); arena.set_process_unhandled_input(false); arena.muted = true
	await process_frame
	arena.load_map("alley_v2")
	for i in 8: await physics_frame
	clear_actors(); arena.boss_spawned = true
	arena.player.position = arena.map.grounded(Vector3(71.2, 0, 3.7))
	arena.player_model.rotation.y = PI
	arena.spawn_enemy("review_boss", Vector3(76.3, 0, -1.0), true, "boss", "latch")
	var enemy: Dictionary = arena.enemies.review_boss
	var art: Node3D = enemy.model
	art.scale = Vector3.ONE * enemy.size
	art.look_at(arena.player.position)
	art.sample("idle", .25)
	arena.place_camera(Vector3(73, 1.2, 1))
	arena.help_visible = false; arena.hud.queue_redraw()
	await capture("gameplay_native.png")
	suppress_hud()
	art.rotation.y = PI
	var portal: Node3D = Shape.door_frame(arena.world, arena.map.grounded(Vector3(70.2, 0, -3.8)), Color.WHITE)
	portal.rotation.y = PI; portal.configure(1.7); portal.sync_effect(.6, 1.45)
	await capture("native_assets.png")
	portal.free()
	# Actual arena updates on the clear flat field show the full sweep -> slam transition.
	arena.load_map("flat"); clear_actors(); suppress_hud()
	arena.player.position = Vector3(0, 0, 2.7); arena.player_model.rotation.y = 0
	arena.config.enemy_speed = 0; arena.config.mana_regen = 0
	arena.spawn_enemy("review_boss", Vector3.ZERO, true, "boss", "latch")
	enemy = arena.enemies.review_boss; art = enemy.model
	arena.place_camera(Vector3(0, 0, .5))
	DirAccess.make_dir_recursive_absolute(output.path_join("combat_chain"))
	for f in 135:
		await physics_frame
		arena._physics_process(1.0 / 30.0)
		if f % 2 == 0:
			await capture("combat_chain/%03d.png" % int(f / 2))
			events.append({"time":(f+1)/30.0,"attack":enemy.attack,"windup":enemy.windup,"visual":art.visual_state,"fraction":art.fraction,"hp":arena.hp})
	records.append({"actor":"combat", "clip":"sweep_slam", "folder":"combat_chain", "frames":68, "seconds":4.5, "native":true})
	clear_actors(); suppress_hud()
	arena.player.position = Vector3(0, 0, 5)
	arena.spawn_enemy("review_boss", Vector3.ZERO, true, "boss", "latch")
	enemy = arena.enemies.review_boss; enemy.pattern_dir = Vector3.BACK
	arena.begin_frames(enemy, arena.config.enemy_types.latch.boss, arena.player.position)
	for f in 56:
		await physics_frame
		arena._physics_process(1.0 / 30.0)
		if f in [5, 24, 50, 53]:
			arena.place_camera(Vector3(0, 0, 4))
			await capture("crossfire_%02d.png" % f)
	clear_actors(); suppress_hud(); arena.player.visible = false
	arena.spawn_enemy("review_boss", Vector3.ZERO, true, "boss", "latch")
	enemy = arena.enemies.review_boss; art = enemy.model
	art.scale = Vector3.ONE * enemy.size; art.rotation.y = PI
	var target := Vector3(0, 2.25, 0)
	arena.camera.size = 8.2; arena.camera.position = target + Vector3(2.4, 1.3, 4.5)
	arena.camera.look_at(target)
	for clip in ["idle", "move", "sweep", "slam", "frames", "shockwave", "hit", "death"]:
		var folder: String = "latch_" + clip
		DirAccess.make_dir_recursive_absolute(output.path_join(folder))
		for f in 25:
			art.sample(clip, f / 24.0)
			await capture(folder + "/%03d.png" % f, true)
		records.append({"actor":"latch", "clip":clip, "folder":folder, "frames":25, "seconds":art.player.get_animation(art.clips[clip]).length, "native":false})
	clear_actors()
	for id in ["door", "stake"]:
		var node: Node3D = load("res://assets/actors/boss_trial_v1/" + id + "_v1.glb").instantiate()
		arena.world.add_child(node); node.rotation.y = PI
		target = Vector3(0, 1.2, 0)
		arena.camera.size = 3.4; arena.camera.position = target + Vector3(1.7, 1, 4.5); arena.camera.look_at(target)
		var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in (["open", "close"] if id == "door" else ["idle"]):
			var folder: String = id + "_" + clip
			DirAccess.make_dir_recursive_absolute(output.path_join(folder))
			ap.play(clip)
			for f in 17:
				ap.seek(ap.get_animation(clip).length * f / 16.0, true)
				await capture(folder + "/%03d.png" % f, true)
			records.append({"actor":id, "clip":clip, "folder":folder, "frames":17, "seconds":ap.get_animation(clip).length, "native":false})
		node.free()
	var result := {"passed":true,"captures":saved,"sequences":records,"combat_samples":events,"native_camera_size":20.0/1.75,"viewport":[1280,800],"scope":"Actual Godot renderer and imported assets. combat_chain executes arena updates; closeup clips are manually sampled."}
	FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("BOSS_REVIEW_COMPLETE captures=", saved)
	arena.queue_free(); await process_frame; quit(0)
