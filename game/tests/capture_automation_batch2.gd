extends SceneTree
## Actual-camera look at the automation batch 2 summons in the arena (needs a rendering window).
## Saves PNGs to the --output folder; checks nothing but that the frames were written.
var arena: Node3D
var out_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			out_dir = arg.trim_prefix("--output=").get_base_dir()
	call_deferred("run")

func step(count: int = 1) -> void:
	for i in count:
		await physics_frame
		arena._physics_process(1.0 / 60.0)

func capture(file: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(file))
	print("CAPTURE ", file)

func foe(id: String, at: Vector3, kind: String = "rag") -> void:
	arena.spawn_enemy(id, at, false, "normal", kind)
	arena.enemies[id].cooldown = 999
	arena.enemies[id].max_hp = 999999.0
	arena.enemies[id].hp = 999999.0

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	arena.build.change_skill("giant", 1)
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	foe("rag", Vector3(-2.5, 0, -3.5))
	foe("brute", Vector3(2.2, 0, -3.2), "brute")
	foe("crow", Vector3(0.5, 0, -5), "crow")
	var b2 = arena.batch2
	var Visual = load("res://scripts/batch2_visual.gd")
	var place := func(skill: String, node_kind: String, at: Vector3, slot: int) -> void:
		var p: Dictionary = b2.plan(skill, node_kind)
		var node := Node3D.new()
		arena.world.add_child(node)
		node.position = arena.map.grounded(at)
		Visual.create(node, skill, float(p.get("scale", 1.0)), bool(p.get("armour", false)))
		b2.register(skill, p, node, slot, "")
	place.call("giant", "base", b2.giant_anchor(0), 0)
	place.call("hound", "base", Vector3(1, 0, 0.6), 0)
	place.call("hound", "pack", Vector3(-1, 0, 0.6), 1)
	place.call("hound", "tracker", Vector3(-1.8, 0, -0.1), 5)
	place.call("beacon", "base", Vector3(-3.2, 0, 1.2), -1)
	for ally in arena.allies:
		ally.life = 999.0
	await step(1)
	await capture("batch2_lineup.png")
	# Let them go: hounds gallop out, the giant walks up and slams, the beacon rings.
	for k in 6:
		await step(12)
		await capture("batch2_action_%d.png" % k)
	print("CAPTURE_DONE")
	quit(0)
