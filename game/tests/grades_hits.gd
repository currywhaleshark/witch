extends SceneTree
## Stage B start: enemy grades, hit rolls for direct attacks and per-enemy crit rolls.
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
	# Fast-forward the started motion to its release point.
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
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	for i in spots.size():
		arena.spawn_enemy("t%d" % i, spots[i], false, grade)
		arena.enemies["t%d" % i].cooldown = 999
	await step(2)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)

	var grades: Array = []
	for id in arena.enemies:
		grades.append(arena.enemies[id].grade)
	check("champion" in grades and "elite" in grades and "boss" not in grades, "the field mixes normal, champion and elite enemies")
	var elite: Dictionary = arena.enemies.enemy_5
	check(elite.max_hp == arena.config.heavy_hp * arena.config.grades.elite.hp and elite.size > 1.15, "an elite has more HP and a bigger body")

	await fresh([Vector3(2, 0, 0)], "normal")
	var normal_hit: float = arena.hit_chance("t0")
	check(is_equal_approx(normal_hit, arena.config.hit_base), "a normal enemy is hit at the base chance")
	await fresh([Vector3(2, 0, 0)], "boss")
	check(arena.hit_chance("t0") < normal_hit, "grade evasion lowers the hit chance")
	arena.config.dexterity = 100
	check(arena.hit_chance("t0") > normal_hit - arena.config.grades.boss.evasion and arena.hit_chance("t0") <= arena.config.hit_cap, "dexterity raises the hit chance up to its cap")
	check(arena.crit_chance("witch") > arena.crit_chance("automaton") and is_equal_approx(arena.crit_chance("automaton"), arena.config.summon_crit_base), "dexterity raises the witch's crit chance but not her summons'")
	var boss_summon_hit: float = arena.hit_chance("t0", "turret")
	check(is_equal_approx(boss_summon_hit, arena.config.summon_hit_base - arena.config.grades.boss.evasion), "a summon's hit chance ignores dexterity and still meets grade evasion")
	arena.config.turret_level = 10.0
	arena.config.automaton_level = 10.0
	check(arena.hit_chance("t0", "turret") > boss_summon_hit and arena.crit_chance("automaton") > arena.config.summon_crit_base, "summon skill level raises its hit and crit chances")
	arena.config.turret_level = 1.0
	arena.config.automaton_level = 1.0

	await fresh()
	var lv_key = InputEventKey.new()
	lv_key.physical_keycode = KEY_F10
	lv_key.pressed = true
	lv_key.shift_pressed = true
	root.push_input(lv_key, true)
	check(arena.config.automaton_level == arena.config.summon_level_steps[1] and arena.config.shield_level == 1, "Shift+F10 cycles the automaton level, not the shield")
	lv_key.shift_pressed = false
	lv_key.ctrl_pressed = true
	root.push_input(lv_key, true)
	check(arena.config.turret_level == arena.config.summon_level_steps[1], "Ctrl+F10 cycles the turret level")
	arena.config.automaton_level = 1.0
	arena.config.turret_level = 1.0

	await fresh()
	arena.force_rolls = {"hit": false, "crit": false}
	var untouched: float = arena.enemies.t0.hp
	arena.spawn_ally(Vector3(3, 0, 1), false, "t0")
	await step(int(arena.config.turret_attack_cooldown * 60) + 30)
	check(arena.enemies.t0.hp == untouched and arena.probe.sources.turret.misses > 0, "summon attacks can miss now that they roll to hit")
	arena.force_rolls = {"hit": true, "crit": false}

	await fresh()
	arena.force_rolls = {"hit": false, "crit": false}
	var full: float = arena.enemies.t0.hp
	arena.request_slot("r", {})
	arena.state = arena.rules.bind(arena.state, "r", "grinder")
	arena.request_slot("r", {})
	arena.request_slot("lmb", {"enemy_id": "t0"})
	release()
	check(arena.enemies.t0.hp == full and arena.enemies.t0.shred == 0 and arena.probe.counts.misses == 1, "a missed swing deals nothing and leaves no debuff")
	arena.state.cooldowns.clear()
	arena.request_slot("rmb", {"enemy_id": "t0"})
	release()
	check(arena.enemies.t0.hp < full, "area attacks skip the hit roll")

	await fresh()
	arena.force_rolls = {"hit": true, "crit": true}
	full = arena.enemies.t0.hp
	arena.request_slot("lmb", {"enemy_id": "t0"})
	release()
	check(is_equal_approx(full - arena.enemies.t0.hp, arena.config.basic_damage * arena.config.crit_multiplier) and arena.probe.counts.crits == 1 and arena.shake_time > 0, "a crit multiplies damage and shakes the view")

	await fresh([Vector3(3, 0, -0.4), Vector3(3, 0, 0.4)])
	arena.force_rolls = {}
	arena.combat_rng.seed = 7
	arena.config.crit_base = 0.5
	var split = 0
	for i in 30:
		arena.enemies.t0.hp = 1000.0
		arena.enemies.t1.hp = 1000.0
		arena.state.cooldowns.clear()
		arena.state.mana = arena.state.max_mana
		arena.request_slot("rmb", {"enemy_id": "t0"})
		release()
		if arena.enemies.t0.hp != arena.enemies.t1.hp:
			split += 1
	check(split > 0 and split < 30, "one shotgun blast rolls crit separately for each enemy")
	arena.config.crit_base = 0.05

	await fresh([Vector3(1, 0, 0)], "elite")
	arena.enemies.t0.cooldown = 0
	for i in 120:
		if arena.hp < arena.config.max_hp:
			break
		await step()
	check(is_equal_approx(arena.config.max_hp - arena.hp, arena.config.enemy_damage * arena.config.grades.elite.damage), "graded enemies hit harder")

	await fresh()
	arena.set_a5_mode(true)
	arena.force_rolls = {"hit": true, "crit": false}
	var key = InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	root.push_input(key, true)
	var boss_id = ""
	for id in arena.enemies:
		if arena.enemies[id].grade == "boss":
			boss_id = id
	check(boss_id != "" and arena.enemies[boss_id].max_hp == arena.config.heavy_hp * arena.config.grades.boss.hp, "B brings in a heavy boss with boss HP")
	var respawning: int = arena.respawns.size()
	arena.damage_enemy(boss_id, 100000)
	check(arena.respawns.size() == respawning, "a test boss does not respawn in A5 mode")
	arena.set_a5_mode(false)

	arena.log_dir = OS.get_user_data_dir().path_join("grade_log_test")
	DirAccess.make_dir_recursive_absolute(arena.log_dir)
	# A5 mode rebuilds the field, so turn it on before placing the test enemy.
	arena.set_a5_mode(true)
	await fresh([Vector3(2, 0, 0)], "champion")
	await step(70)
	arena.force_rolls = {"hit": false, "crit": false}
	arena.request_slot("lmb", {"enemy_id": "t0"})
	release()
	arena.force_rolls = {"hit": true, "crit": true}
	arena.request_slot("lmb", {"enemy_id": "t0"})
	release()
	arena.state.cooldowns.clear()
	arena.request_slot("rmb", {"enemy_id": "t0"})
	release()
	arena.damage_player(12, "champion")
	arena.damage_player(5, "normal")
	arena.stun_time = 0
	arena.action_time = 0
	arena.damage_enemy("t0", 100000)
	var path: String = arena.save_mana_log("manual")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	check(saved != null and saved.metrics.by_source.staff.misses == 1 and saved.metrics.by_source.staff.crits == 1 and saved.metrics.by_source.shotgun.hits == 1, "the log splits hits, misses and crits by source")
	check(saved != null and saved.metrics.by_source.staff.damage > 0 and saved.metrics.counts.misses == 1, "the log keeps damage per source and the old totals")
	check(saved != null and saved.metrics.by_grade.champion.stuns == 1 and saved.metrics.by_grade.champion.damage_to_witch == 12 and saved.metrics.by_grade.normal.stuns == 0 and saved.metrics.counts.stuns == 1, "the log counts damage taken and stuns by attacker grade")
	check(saved != null and saved.metrics.by_grade.champion.kills == 1, "the log counts kills by grade")
	arena.set_a5_mode(false)
	for file in DirAccess.get_files_at(arena.log_dir):
		DirAccess.remove_absolute(arena.log_dir.path_join(file))

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_grades_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
