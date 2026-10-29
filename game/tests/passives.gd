extends SceneTree
## B7 cross-tree passives (03 §2.1): cutting precision and ballistics raise only the attacks
## tagged with their machine principle, whichever tree those attacks belong to.
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

func seconds(value: float) -> void:
	# Mana never runs out mid-test; upkeep is not what is measured here.
	for i in roundi(value * 60):
		arena.state.mana = arena.state.max_mana
		await step()

func release() -> void:
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)
	arena.action_time = 0

func fresh(cutting: float, ballistics: float, spot: Vector3 = Vector3(2, 0, 0)) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.passive_levels.cutting_precision = cutting
	arena.config.passive_levels.ballistics = ballistics
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	for ally in arena.allies:
		ally.node.free()
	arena.allies.clear()
	arena.spawn_enemy("t0", spot, false)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.hp = 10000.0
	await step(2)

func source(name: String) -> Dictionary:
	return arena.probe.sources.get(name, {"hits": 0, "damage": 0.0}).duplicate()

func per_hit(before: Dictionary, name: String) -> float:
	var now: Dictionary = source(name)
	return (now.damage - before.damage) / maxf(1, now.hits - before.hits)

func struck(src: String, look: String = "") -> float:
	# One fixed 10-point hit through the shared strike path.
	var before: float = arena.enemies.t0.hp
	arena.strike("t0", 10.0, false, "witch", src, look)
	return before - arena.enemies.t0.hp

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var bonus: float = 1.0 + 10 * float(arena.config.passives.cutting_precision.damage_per_level)
	check(arena.config.passive_levels.cutting_precision == 0 and arena.config.passive_levels.ballistics == 0, "both passives start unlearned")

	await fresh(10.0, 0.0)
	var cut_ok := true
	for src in ["bolt_cutter", "grinder", "chainsaw"]:
		cut_ok = cut_ok and is_equal_approx(struck(src), 10.0 * bonus)
	check(cut_ok and is_equal_approx(struck("automaton", "saw"), 10.0 * bonus), "cutting precision raises every cutting hit, the B automaton's saw included")
	var plain_ok := true
	for pair in [["staff", ""], ["automaton", ""], ["automaton_blast", ""], ["shotgun", ""], ["turret", ""]]:
		plain_ok = plain_ok and is_equal_approx(struck(pair[0], pair[1]), 10.0)
	check(plain_ok, "cutting precision leaves the staff, punches, blasts and projectiles alone")

	await fresh(0.0, 10.0)
	check(is_equal_approx(struck("shotgun"), 10.0 * bonus) and is_equal_approx(struck("turret"), 10.0 * bonus), "ballistics raises the shotgun and the turret's shots")
	plain_ok = true
	for pair in [["staff", ""], ["chainsaw", ""], ["automaton", ""], ["automaton", "saw"], ["automaton_blast", ""]]:
		plain_ok = plain_ok and is_equal_approx(struck(pair[0], pair[1]), 10.0)
	check(plain_ok, "ballistics leaves cutting, punches and blasts alone")

	# The real attack paths carry the same tags.
	await fresh(10.0, 0.0)
	arena.state = arena.rules.bind(arena.state, "r", "chainsaw")
	arena.request_slot("r", {})
	await step()
	var hp: float = arena.enemies.t0.hp
	arena.request_slot("lmb", {"enemy_id": "t0"})
	release()
	var cut: float = hp - arena.enemies.t0.hp
	check(is_equal_approx(cut, arena.rules.skills.chainsaw.attack_damage * bonus), "a real chainsaw cut gains cutting precision")
	hp = arena.enemies.t0.hp
	await seconds(arena.config.bleed.seconds + 0.2)
	check(is_equal_approx(hp - arena.enemies.t0.hp, arena.enemies.t0.max_hp * float(arena.config.bleed.ratio.normal)), "its bleed does not: bleed follows only max HP and grade")

	await fresh(0.0, 10.0, Vector3(3, 0, 0))
	hp = arena.enemies.t0.hp
	arena.request_slot("rmb", {"enemy_id": "t0"})
	release()
	check(is_equal_approx(hp - arena.enemies.t0.hp, arena.config.shot_damage * bonus), "a real shotgun blast gains ballistics")

	await fresh(10.0, 10.0, Vector3(3, 0, 0))
	var turret: Dictionary = source("turret")
	arena.spawn_ally(Vector3(1, 0, 1), false, "")
	await seconds(2.0)
	check(is_equal_approx(per_hit(turret, "turret"), arena.config.turret_damage * bonus), "the turret's real shots gain ballistics")

	for node in ["base", "B"]:
		await fresh(10.0, 10.0, Vector3(3, 0, 0))
		arena.config.automaton_node = node
		var punches: Dictionary = source("automaton")
		arena.spawn_ally(Vector3(1, 0, 0), true, "t0")
		await seconds(3.0)
		var expected: float = arena.config.summon_damage * (float(arena.config.automaton_nodes.B.damage_factor) * bonus if node == "B" else 1.0)
		check(is_equal_approx(per_hit(punches, "automaton"), expected), "the B automaton's saw cuts with the bonus" if node == "B" else "the plain automaton's punch gains neither passive")
	arena.config.automaton_node = "base"

	await fresh(0.0, 0.0)
	var key = InputEventKey.new()
	key.pressed = true
	var order: Array = []
	for code in [KEY_J, KEY_J, KEY_K, KEY_J]:
		key.physical_keycode = code
		root.push_input(key, true)
		order.append([arena.config.passive_levels.cutting_precision, arena.config.passive_levels.ballistics])
	check(order == [[5.0, 0.0], [10.0, 0.0], [10.0, 5.0], [0.0, 5.0]], "J cycles cutting precision and K ballistics, each on its own")

	arena.log_dir = OS.get_user_data_dir().path_join("passives_log_test")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-log-dir="):
			arena.log_dir = arg.trim_prefix("--test-log-dir=")
	DirAccess.make_dir_recursive_absolute(arena.log_dir)
	arena.set_a5_mode(true)
	await fresh(5.0, 10.0)
	await seconds(1.2)
	var path: String = arena.save_mana_log("manual")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	check(saved != null and saved.settings.passive_levels.cutting_precision == 5 and saved.settings.passive_levels.ballistics == 10, "the A5 log records both passive levels")
	arena.set_a5_mode(false)
	for file in DirAccess.get_files_at(arena.log_dir):
		DirAccess.remove_absolute(arena.log_dir.path_join(file))

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_passives_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
