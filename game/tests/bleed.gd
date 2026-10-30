extends SceneTree
## Chainsaw bleed trial (07 §2.2-2.3): max-HP share by grade, five independent stacks with fading
## weights, no crit or defence, and the A/B skill-level growth switch.
var arena: Node3D
var failures: Array = []
var checks: Array = []

func _initialize() -> void:
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

func release() -> void:
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)
	arena.action_time = 0

func fresh(spots: Array = [Vector3(2, 0, 0)], grade: String = "normal") -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.dexterity = 0
	arena.config.chainsaw_level = 1.0
	arena.config.bleed.growth = "A"
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	for i in spots.size():
		arena.spawn_enemy("t%d" % i, spots[i], false, grade)
		arena.enemies["t%d" % i].cooldown = 999
		# Plenty of HP so bleeds run their full course.
		arena.enemies["t%d" % i].hp = 10000.0
	arena.state = arena.rules.bind(arena.state, "r", "chainsaw")
	arena.request_slot("r", {})
	await step(2)

func swing(target: String = "t0") -> void:
	arena.request_slot("lmb", {"enemy_id": target})
	release()

func seconds(value: float) -> void:
	# Mana never runs out mid-test; the tool upkeep is not what is measured here.
	for i in roundi(value * 60):
		arena.state.mana = arena.state.max_mana
		await step()

func share(grade: String) -> float:
	return float(arena.config.bleed.ratio[grade])

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var bleed: Dictionary = arena.config.bleed
	check(bleed.growth == "B", "the chosen growth B is the default")

	check(arena.config.r_slot_options.has("chainsaw") and arena.rules.skills.chainsaw.kind == "tool", "the chainsaw is a tool the R slot can carry")
	await fresh()
	check(arena.state.active_tool == "chainsaw", "pressing R runs the chainsaw")
	var max_hp: float = arena.enemies.t0.max_hp
	swing()
	var after_cut: float = arena.enemies.t0.hp
	check(is_equal_approx(10000.0 - after_cut, arena.rules.skills.chainsaw.attack_damage) and arena.enemies.t0.bleeds.size() == 1, "a chainsaw hit deals its direct damage and starts one bleed")
	await seconds(bleed.seconds + 0.2)
	check(is_equal_approx(after_cut - arena.enemies.t0.hp, max_hp * share("normal")) and arena.enemies.t0.bleeds.is_empty(), "one bleed takes the normal grade's share of max HP over its run, then ends")
	check(arena.probe.counts.bleed_ticks == roundi(bleed.seconds / bleed.tick_seconds), "the bleed ticks every half second")

	await fresh()
	arena.force_rolls = {"hit": false, "crit": false}
	swing()
	check(arena.enemies.t0.bleeds.is_empty() and arena.enemies.t0.hp == 10000.0, "a missed cut leaves no bleed")

	await fresh()
	arena.force_rolls = {"hit": true, "crit": true}
	arena.enemies.t0.shred = 99.0
	swing()
	after_cut = arena.enemies.t0.hp
	await seconds(bleed.seconds + 0.2)
	check(is_equal_approx(after_cut - arena.enemies.t0.hp, max_hp * share("normal")), "bleed ignores crits and shred; only the cut itself is boosted")

	for grade in ["champion", "elite", "boss"]:
		await fresh([Vector3(2, 0, 0)], grade)
		max_hp = arena.enemies.t0.max_hp
		swing()
		after_cut = arena.enemies.t0.hp
		await seconds(bleed.seconds + 0.2)
		check(is_equal_approx(after_cut - arena.enemies.t0.hp, max_hp * share(grade)), "a %s takes its own lower share of max HP" % grade)

	await fresh([Vector3(2, 0, -0.5), Vector3(2, 0, 0.5), Vector3(-2, 0, 0)])
	swing()
	check(arena.enemies.t0.bleeds.size() == 1 and arena.enemies.t1.bleeds.size() == 1 and arena.enemies.t2.bleeds.is_empty(), "one cut bleeds every enemy in its small forward fan, not those behind")

	await fresh()
	max_hp = arena.enemies.t0.max_hp
	for i in 6:
		swing()
	var stacks: Array = arena.enemies.t0.bleeds
	var totals: Array = stacks.map(func(stack): return stack.per_tick * stack.left)
	var weights: Array = bleed.weights
	check(stacks.size() == int(bleed.max_stacks), "bleeds stack to five")
	check(is_equal_approx(totals[0], max_hp * share("normal") * weights[1]) and is_equal_approx(totals[3], max_hp * share("normal") * weights[4]), "later stacks add less: each keeps the weight it was applied with")
	check(is_equal_approx(totals[4], max_hp * share("normal") * weights[4]), "a sixth bleed replaces the oldest stack")

	await fresh()
	swing()
	await seconds(2.0)
	swing()
	await seconds(2.2)
	check(arena.enemies.t0.bleeds.size() == 1 and arena.enemies.t0.bleeds[0].left == 4, "each stack runs its own timer; a new bleed never refreshes the old one")

	await fresh()
	swing()
	var held: float = arena.enemies.t0.hp
	arena.paused = true
	await seconds(1.0)
	check(arena.enemies.t0.hp == held, "pause freezes bleeding")
	arena.paused = false

	await fresh()
	arena.enemies.t0.hp = 1.0
	arena.enemies.t0.bleeds.append({"left": 1, "per_tick": 5.0, "clock": 0.0, "tick_seconds": 0.5, "last_seconds": 0.5})
	var kills: int = arena.kills
	await seconds(0.6)
	check(not arena.enemies.has("t0") and arena.kills == kills + 1, "bleed can finish an enemy")

	await fresh()
	var base_plan: Dictionary = arena.bleed_plan(0)
	arena.config.chainsaw_level = 10.0
	var plan_a: Dictionary = arena.bleed_plan(4)
	check(is_equal_approx(plan_a.ratio, 1.0 + bleed.a_ratio_per_level * 9) and plan_a.seconds == base_plan.seconds and plan_a.weight == weights[4], "growth A: level raises the share of max HP only")
	arena.config.bleed.growth = "B"
	var plan_b: Dictionary = arena.bleed_plan(4)
	check(plan_b.seconds > base_plan.seconds and is_equal_approx(plan_b.ratio, plan_b.seconds / bleed.seconds) and plan_b.weight > weights[4], "growth B: level lengthens the bleed at the same rate and lets later stacks keep more")
	arena.config.chainsaw_level = 4.0
	var plan_b4: Dictionary = arena.bleed_plan(4)
	arena.config.chainsaw_level = 5.0
	var plan_b5: Dictionary = arena.bleed_plan(4)
	arena.config.chainsaw_level = 9.0
	var plan_b9: Dictionary = arena.bleed_plan(4)
	check(plan_b4.weight == weights[4] and plan_b5.weight > weights[4] and plan_b9.weight == plan_b5.weight and plan_b5.weight < plan_b.weight, "growth B: later stacks gain weight only at every fifth level")
	check(plan_b5.seconds > plan_b4.seconds and plan_b9.seconds > plan_b5.seconds, "growth B: every level lengthens the bleed")

	await fresh()
	var key = InputEventKey.new()
	key.physical_keycode = KEY_F9
	key.pressed = true
	key.shift_pressed = true
	var r_binding: String = arena.state.bindings.r
	root.push_input(key, true)
	check(arena.config.chainsaw_level == arena.config.chainsaw_level_steps[1] and arena.state.bindings.r == r_binding, "Shift+F9 cycles the chainsaw level and keeps the R slot")
	key.shift_pressed = false
	key.ctrl_pressed = true
	root.push_input(key, true)
	check(arena.config.bleed.growth == "B", "Ctrl+F9 switches the bleed growth between A and B")

	arena.log_dir = OS.get_user_data_dir().path_join("bleed_log_test")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-log-dir="):
			arena.log_dir = arg.trim_prefix("--test-log-dir=")
	DirAccess.make_dir_recursive_absolute(arena.log_dir)
	arena.set_a5_mode(true)
	await fresh()
	await seconds(1.2)
	swing()
	await seconds(bleed.seconds + 0.2)
	var path: String = arena.save_mana_log("manual")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	check(saved != null and saved.metrics.by_source.bleed.damage > 0 and saved.metrics.by_source.bleed.hits == 0 and saved.metrics.by_source.chainsaw.hits == 1, "the log keeps bleed damage as its own source, apart from the cut")
	check(saved != null and saved.metrics.counts.bleeds_applied == 1 and saved.settings.chainsaw_level == 1 and saved.settings.bleed_growth == "A", "the log records bleeds applied, the chainsaw level and the growth")
	arena.set_a5_mode(false)
	for file in DirAccess.get_files_at(arena.log_dir):
		DirAccess.remove_absolute(arena.log_dir.path_join(file))

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_bleed_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
