extends SceneTree
## B6 automaton nodes (03 §5.3): no node fights then self-destructs, A blasts the moment it
## reaches its target, B never self-destructs and keeps at most three.
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
	await step(roundi(value * 60))

func fresh(node: String, spots: Array = [Vector3(4, 0, 0)]) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.automaton_node = node
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	for ally in arena.allies:
		ally.node.free()
	arena.allies.clear()
	for i in spots.size():
		arena.spawn_enemy("t%d" % i, spots[i], false)
		arena.enemies["t%d" % i].cooldown = 999
		arena.enemies["t%d" % i].hp = 10000.0
	await step(2)

func source(name: String) -> Dictionary:
	return arena.probe.sources.get(name, {"hits": 0, "damage": 0.0}).duplicate()

func gained(before: Dictionary, name: String) -> Dictionary:
	var now: Dictionary = source(name)
	return {"hits": now.hits - before.hits, "damage": now.damage - before.damage}

func summon(target: String = "t0", at: Vector3 = Vector3(1, 0, 0)) -> Dictionary:
	arena.spawn_ally(at, true, target)
	return arena.allies[-1]

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var nodes: Dictionary = arena.config.automaton_nodes
	var blast: float = arena.config.shot_damage
	check(arena.config.automaton_node == "base", "the automaton starts with no node invested")

	await fresh("base")
	var attacks: Dictionary = source("automaton")
	var blasts: Dictionary = source("automaton_blast")
	summon()
	await seconds(arena.config.summon_lifetime - 0.5)
	check(arena.allies.size() == 1 and gained(attacks, "automaton").hits >= 5, "no node: the automaton fights for its lifetime")
	await seconds(0.7)
	check(arena.allies.is_empty() and gained(blasts, "automaton_blast").hits == 1 and is_equal_approx(gained(blasts, "automaton_blast").damage, blast), "no node: it self-destructs when its time is up")

	await fresh("A")
	attacks = source("automaton")
	blasts = source("automaton_blast")
	summon()
	await seconds(1.0)
	check(arena.allies.is_empty() and gained(attacks, "automaton").hits == 0, "A: it blasts on reaching the target without a single normal attack")
	check(gained(blasts, "automaton_blast").hits == 1 and is_equal_approx(gained(blasts, "automaton_blast").damage, blast * nodes.A.blast_factor), "A: its blast is stronger than the timed one")

	await fresh("base", [Vector3(12, 0, 0)])
	var walker: Dictionary = summon()
	await seconds(0.5)
	var walked: float = walker.node.position.x - 1.0
	await fresh("A", [Vector3(12, 0, 0)])
	var runner: Dictionary = summon()
	await seconds(0.5)
	check(is_equal_approx(runner.node.position.x - 1.0, walked * nodes.A.speed_factor), "A: it runs to its target faster")

	# An enemy must stay on the field (an empty field is cleared and stops), just out of sight.
	await fresh("A", [Vector3(6, 0, 0)])
	var sight: float = arena.config.summon_detection_range
	arena.config.summon_detection_range = 1.0
	summon("")
	await seconds(arena.config.summon_lifetime + 0.2)
	check(arena.allies.is_empty(), "A: with no enemy to reach it still goes off when its time is up")
	arena.config.summon_detection_range = sight

	await fresh("B")
	attacks = source("automaton")
	blasts = source("automaton_blast")
	summon()
	await seconds(arena.config.summon_lifetime * 2)
	check(arena.allies.size() == 1 and gained(attacks, "automaton").hits >= 10, "B: it keeps fighting past the old lifetime")
	var cuts: Dictionary = gained(attacks, "automaton")
	check(is_equal_approx(cuts.damage / cuts.hits, arena.config.summon_damage * nodes.B.damage_factor) and is_equal_approx(arena.allies[0].max_hp, arena.config.automaton_hp * nodes.B.hp_factor), "B: it hits a little harder and has more HP to hold the line")
	check(gained(blasts, "automaton_blast").hits == 0, "B: it never self-destructs")

	await fresh("B")
	blasts = source("automaton_blast")
	var lost: int = arena.probe.counts.allies_lost
	var first: Dictionary = summon()
	for i in int(nodes.B.max_count):
		summon("t0", Vector3(1, 0, 0.4 * (i + 1)))
	await step()
	check(arena.allies.size() == int(nodes.B.max_count) and not arena.allies.has(first), "B: a fourth replaces the oldest, so three stay")
	check(gained(blasts, "automaton_blast").hits == 0 and arena.probe.counts.allies_lost == lost, "B: the replaced one breaks apart quietly, not as a loss or a blast")

	await fresh("base")
	var veteran: Dictionary = summon()
	arena.config.automaton_node = "B"
	await seconds(arena.config.summon_lifetime + 0.2)
	check(not arena.allies.has(veteran), "an automaton keeps the node it was summoned with")

	await fresh("base")
	var key = InputEventKey.new()
	key.physical_keycode = KEY_N
	key.pressed = true
	var order: Array = []
	for i in 3:
		root.push_input(key, true)
		order.append(arena.config.automaton_node)
	check(order == ["A", "B", "base"] and arena.config.shield_level == 1.0 and arena.config.automaton_level == 1.0, "N cycles the automaton node and nothing else")

	arena.log_dir = OS.get_user_data_dir().path_join("automaton_node_log_test")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-log-dir="):
			arena.log_dir = arg.trim_prefix("--test-log-dir=")
	DirAccess.make_dir_recursive_absolute(arena.log_dir)
	arena.set_a5_mode(true)
	await fresh("A")
	await seconds(1.2)
	var path: String = arena.save_mana_log("manual")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	check(saved != null and saved.settings.automaton_node == "A", "the A5 log records the automaton node")
	arena.set_a5_mode(false)
	for file in DirAccess.get_files_at(arena.log_dir):
		DirAccess.remove_absolute(arena.log_dir.path_join(file))

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/automaton_nodes_v1/automaton_node_art_regression/result.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
