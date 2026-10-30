extends SceneTree
## B8: keep the same weapon, direct damage and passives; change only chainsaw level.
## Measure actual ticks and expiry, not just the planned duration returned by bleed_plan().
const DURATIONS = [4.0, 4.2, 4.4, 4.6, 4.8, 5.0, 5.2, 5.4, 5.6, 5.8]
const FIFTH_WEIGHTS = [0.35, 0.35, 0.35, 0.35, 0.48, 0.48, 0.48, 0.48, 0.48, 0.61]
const SHARES = {"normal": 0.24, "champion": 0.18, "elite": 0.12, "boss": 0.04}
const TARGET_HP = 1000.0
const HEALTH_POOL = 100000.0
var arena: Node3D
var checks: Array[String] = []
var failures: Array[String] = []
var rows: Array = []
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error(label)

func near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.00001

func fresh(level: int, grade: String = "normal") -> void:
	arena.config.chainsaw_level = level
	arena.config.bleed.growth = "B"
	arena.enemies.b8.grade = grade
	arena.enemies.b8.max_hp = TARGET_HP
	# An oversized health pool prevents death from clipping the measured full-course damage.
	arena.enemies.b8.hp = HEALTH_POOL
	arena.enemies.b8.bleeds.clear()
	arena.enemies.b8.shred = 0.0
	arena.probe = arena.ManaProbe.new()
	arena.action_time = 0.0

func damage() -> float:
	return float(arena.probe.sources.get("bleed", {}).get("damage", 0.0))

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await physics_frame
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	arena.config.enemy_speed = 0.0
	arena.config.mana_regen = 0.0
	arena.config.dexterity = 0.0
	arena.config.passive_levels = {"cutting_precision": 0, "ballistics": 0}
	arena.player.position = Vector3.ZERO
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("b8", Vector3(2, 0, 0), false, "normal", "rag")
	arena.enemies.b8.cooldown = 999.0
	arena.state = arena.rules.bind(arena.state, "r", "chainsaw")
	arena.request_slot("r", {})
	await physics_frame
	check(arena.config.bleed.growth == "B", "selected B growth is the initial default")

	for grade in SHARES:
		for level in range(1, 11):
			fresh(level, grade)
			var duration: float = DURATIONS[level - 1]
			var expected_tick: float = TARGET_HP * SHARES[grade] / 8.0
			var expected_total: float = TARGET_HP * SHARES[grade] * duration / 4.0
			var label := "%s Lv%d" % [grade, level]
			arena.add_bleed("b8")
			arena.tick_bleeds(0.5)
			var first_tick := damage()
			check(near(first_tick, expected_tick), label + ": first-stack half-second damage stays fixed")
			arena.tick_bleeds(duration - 0.51)
			check(arena.enemies.b8.bleeds.size() == 1, label + ": stack remains until its exact duration")
			arena.tick_bleeds(0.01)
			check(arena.enemies.b8.bleeds.is_empty(), label + ": stack expires at its exact duration")
			check(near(damage(), expected_total), label + ": total includes the proportional final tick")
			var total := damage()
			# Observe expiry with actual 60 Hz updates as a second, independent schedule.
			fresh(level, grade)
			arena.add_bleed("b8")
			var frames := 0
			while not arena.enemies.b8.bleeds.is_empty() and frames < 480:
				arena.tick_bleeds(1.0 / 60.0)
				frames += 1
			var measured_seconds := frames / 60.0
			check(near(measured_seconds, duration) and near(damage(), expected_total), label + ": 60 Hz preserves expiry and damage")
			rows.append({"grade": grade, "level": level, "duration_seconds": measured_seconds,
				"first_half_second_damage": first_tick, "one_stack_damage": total,
				"one_stack_max_hp_ratio": total / TARGET_HP, "fifth_stack_weight": arena.bleed_plan(4).weight})

	for level in range(1, 11):
		fresh(level)
		for i in 5:
			arena.add_bleed("b8")
		var sum_weights := 0.0
		for base in [1.0, 0.8, 0.6, 0.45, 0.35]:
			sum_weights += base + (1.0 - base) * (0.0 if level < 5 else (0.2 if level < 10 else 0.4))
		arena.tick_bleeds(0.5)
		check(near(damage(), 30.0 * sum_weights), "Lv%d: five-stack rate rises only at the level-5 milestones" % level)
		check(near(arena.bleed_plan(4).weight, FIFTH_WEIGHTS[level - 1]), "Lv%d: fifth-stack weight matches the selected trial profile" % level)
		arena.tick_bleeds(DURATIONS[level - 1] - 0.5)
		check(near(damage(), 60.0 * DURATIONS[level - 1] * sum_weights) and arena.enemies.b8.bleeds.is_empty(), "Lv%d: all five stacks finish independently without losing their tails" % level)

	# Use the real cast/release/strike path, keeping direct damage and every other setting fixed.
	for level in [1, 2, 4, 5, 9, 10]:
		fresh(level)
		arena.request_slot("lmb", {"enemy_id": "b8"})
		check(not arena.windup.is_empty() and arena.enemies.b8.bleeds.is_empty(), "Lv%d: windup has no early bleed" % level)
		if not arena.windup.is_empty():
			arena.windup.release = 0.0
			arena.tick_windup(0.0)
		check(near(HEALTH_POOL - arena.enemies.b8.hp, 14.0) and arena.enemies.b8.bleeds.size() == 1, "Lv%d: release keeps the same direct hit and applies exactly one bleed" % level)
		arena.tick_bleeds(DURATIONS[level - 1])
		check(near(damage(), 60.0 * DURATIONS[level - 1]), "Lv%d: the real skill receives the measured level growth" % level)

	fresh(2)
	arena.add_bleed("b8")
	arena.tick_bleeds(0.2)
	arena.config.chainsaw_level = 10
	arena.add_bleed("b8")
	arena.tick_bleeds(3.99)
	check(arena.enemies.b8.bleeds.size() == 2, "an older Lv2 stack is still alive at 4.19 seconds")
	arena.tick_bleeds(0.01)
	check(arena.enemies.b8.bleeds.size() == 1, "the older stack ends at 4.2 seconds without refreshing the new stack")
	check(near(damage(), 252.0 + 4.0 * 60.0 * 0.88), "changing level preserves old-stack rate and gives the new stack its own weight")
	arena.tick_bleeds(1.8)
	check(arena.enemies.b8.bleeds.is_empty() and near(damage(), 252.0 + 5.8 * 60.0 * 0.88), "the newer Lv10 stack ends on its own 5.8-second clock")

	for dt in [1.0 / 30.0, 0.2, 0.73, 10.0]:
		fresh(10)
		arena.add_bleed("b8")
		var elapsed := 0.0
		while not arena.enemies.b8.bleeds.is_empty() and elapsed < 12.0:
			arena.tick_bleeds(dt)
			elapsed += dt
		check(near(damage(), 348.0), "frame step %.5f preserves full-course damage" % dt)

	fresh(2)
	arena.add_bleed("b8")
	arena.tick_bleeds(4.1)
	var before_pause: Array = arena.enemies.b8.bleeds.duplicate(true)
	var before_damage := damage()
	arena.paused = true
	arena._physics_process(1.0)
	check(arena.enemies.b8.bleeds == before_pause and damage() == before_damage, "pause freezes a pending fractional final tick")
	arena.paused = false
	arena.tick_bleeds(0.1)
	check(arena.enemies.b8.bleeds.is_empty() and near(damage(), 252.0), "resume pays the fractional final tick once")
	arena.tick_bleeds(10.0)
	check(near(damage(), 252.0), "expired stacks cannot pay their final tick twice")

	fresh(2)
	for i in 5:
		arena.add_bleed("b8")
	arena.tick_bleeds(4.1)
	before_damage = damage()
	arena.add_bleed("b8")
	check(arena.enemies.b8.bleeds.size() == 5 and damage() == before_damage, "sixth application replaces only the oldest stack without paying its pending tail")
	arena.tick_bleeds(0.1)
	check(arena.enemies.b8.bleeds.size() == 1 and near(damage() - before_damage, 12.0 * 2.2), "unreplaced stacks keep their own fractional expiry")

	# A remains available for the older comparison and still lasts exactly four seconds.
	fresh(10)
	arena.config.bleed.growth = "A"
	arena.add_bleed("b8")
	arena.tick_bleeds(4.0)
	check(arena.enemies.b8.bleeds.is_empty() and near(damage(), 240.0 * 1.54), "historical growth A retains its duration and total")

	var report := {"test": "B8", "engine": Engine.get_version_info().string,
		"status": "trial_values_not_final_balance", "checks": checks, "failures": failures,
		"controlled_conditions": {"target_max_hp": TARGET_HP, "target_health_pool": HEALTH_POOL,
			"direct_chainsaw_damage": 14.0, "passive_levels": {"cutting_precision": 0, "ballistics": 0},
			"hit": true, "crit": false, "equipment": "unchanged prototype staff; no equipment system",
			"power": "unchanged fixed direct damage; no player power-stat implementation"},
		"source_sha256": {"arena": FileAccess.get_sha256("res://scripts/arena.gd"),
			"trial": FileAccess.get_sha256("res://data/trial.json"), "test": FileAccess.get_sha256("res://tests/bleed_growth.gd")},
		"measurements": rows}
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../reports/godot_bleed_growth_report.json")
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("B8_BLEED_GROWTH_COMPLETE checks=%d failures=%d" % [checks.size(), failures.size()])
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
