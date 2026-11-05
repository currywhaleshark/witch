extends SceneTree
## 집행자의 도르래 with the bolt cutter: the chained 60% hit follows the basic attack, every
## landed focus-attack thrust and one drag per area-attack swing (never onto an enemy that swing
## already cut). Without the unique nothing chains. Writes a report only with --output.
var arena: Node3D
var failures: Array = []
var checks: Array = []
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error(name)

func step(count: int = 1) -> void:
	for i in count:
		await physics_frame
		arena._physics_process(1.0 / 60.0)

func enemy(id: String, at: Vector3) -> void:
	arena.spawn_enemy(id, at, false, "normal", "light")
	arena.enemies[id].cooldown = 999
	arena.enemies[id].max_hp = 99999.0
	arena.enemies[id].hp = 99999.0

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func setup(worn: bool, layout: Dictionary) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	for id in layout:
		enemy(id, layout[id])
	if worn and arena.gear_total("rule:chain_cut") == 0:
		arena.bag.append(arena.items.make_unique(RandomNumberGenerator.new(), 30, "executioner_pulley"))
		arena.equip(arena.bag.size() - 1)
	arena.bind_slot("w", "bolt_cutter")
	arena.bind_slot("q", "focus_attack")
	arena.bind_slot("rmb", "area_attack")
	await step(2)
	arena.request_slot("w", {})
	await step(20)
	arena.state.mana = arena.state.max_mana

func basic() -> void:
	arena.request_slot("lmb", {"enemy_id": "a"})
	await step(60)

func focus(seconds: float) -> void:
	var at := Vector3(0, 0, 1.4)
	arena.pointer = arena.camera.unproject_position(at)
	arena.hold = {"key": KEY_Q, "slot": "q", "shift": false, "enemy_id": ""}
	arena.request_slot("q", {"ground": [at.x, 0, at.z]})
	await step(int(60 * seconds))
	arena.hold.clear()
	await step(30)

func area() -> void:
	arena.request_slot("rmb", {"ground": [0.0, 0, 1.4]})
	await step(90)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	var side := {"a": Vector3(0, 0, 1.4), "b": Vector3(2.2, 0, 1.4)}
	var factor := float(arena.items.data.rule_values.chain_cut_factor)

	# Worn equipment survives a reset, so the case without the pulley runs first.
	await setup(false, side)
	await basic()
	await focus(1.0)
	await area()
	check(lost("a") > 0 and lost("b") == 0.0, "without the pulley no bolt cutter attack chains")

	await setup(true, side)
	check(arena.state.active_tool == "bolt_cutter" and arena.gear_total("rule:chain_cut") > 0, "pulley worn with the bolt cutter active")
	await basic()
	check(lost("a") > 0 and is_equal_approx(lost("b"), lost("a") * factor), "basic attack: the side enemy takes 60% of the hit")

	await setup(true, side)
	await focus(2.0)
	var thrusts: int = int(arena.last_tool_attack.get("hits", 0))
	check(thrusts >= 2 and lost("a") > 0, "focus attack lands several thrusts on the enemy in front")
	check(is_equal_approx(lost("b"), lost("a") * factor), "focus attack: every landed thrust drags the side enemy in at 60%")
	check(arena.probe.sources.has("focus_attack:bolt_cutter"), "chained focus hits are logged under the focus attack")

	await setup(true, side)
	await area()
	var struck: Array = arena.last_tool_attack.get("struck", [])
	check(struck == ["a"], "area attack fan cuts only the enemy in front")
	check(lost("a") > 0 and is_equal_approx(lost("b"), lost("a") * factor), "area attack: one drag onto the side enemy at 60%")

	# Two enemies inside the fan and one beside: the swing drags only the outside enemy, once.
	await setup(true, {"a": Vector3(0, 0, 1.4), "c": Vector3(0, 0, 2.6), "b": Vector3(2.2, 0, 1.4)})
	await area()
	struck = arena.last_tool_attack.get("struck", [])
	check(struck.has("a") and struck.has("c") and not struck.has("b"), "wide case: the fan cuts the two enemies in line")
	check(is_equal_approx(lost("a"), lost("c")), "an enemy the swing already cut is never dragged again")
	check(is_equal_approx(lost("b"), lost("a") * factor), "wide case: exactly one drag, onto the enemy outside the fan")

	var result := {"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}
	if output != "":
		FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("PULLEY_TOOL_ATTACKS_COMPLETE ", JSON.stringify(result))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
