extends SceneTree
## Summons grow with their own skill level: automaton and turret HP and damage (hits and the
## self-destruct blast) rise per level, blueprint levels included, on top of the node factors.
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

func fresh(level: float, node: String = "base") -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	arena.config.automaton_level = level
	arena.config.turret_level = level
	arena.config.automaton_node = node
	for ally in arena.allies.duplicate():
		arena.dismantle_ally(ally)
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(3, 0, 0), false)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.hp = 10000.0
	await step(2)

func growth(kind: String, level: float) -> float:
	return 1.0 + float(arena.config["summon_%s_per_level" % kind]) * (level - 1.0)

func first_hit(mobile: bool) -> float:
	# Steps until the summon lands its first blow on the target and returns the damage.
	var before: float = arena.enemies.t0.hp
	for i in 600:
		await step()
		if arena.enemies.t0.hp < before:
			return before - arena.enemies.t0.hp
	return 0.0

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var config: Dictionary = arena.config

	await fresh(1.0)
	arena.spawn_ally(Vector3(1, 0, 0), true, "t0")
	arena.spawn_ally(Vector3(-1, 0, 0), false, "t0")
	check(is_equal_approx(arena.allies[0].max_hp, config.automaton_hp) and is_equal_approx(arena.allies[1].max_hp, config.turret_hp), "Lv1 summons keep their trial HP")

	await fresh(10.0)
	arena.spawn_ally(Vector3(2, 0, 0), true, "t0")
	check(is_equal_approx(arena.allies[0].max_hp, config.automaton_hp * growth("hp", 10)), "an automaton's HP grows with its skill level")
	var dealt: float = await first_hit(true)
	check(is_equal_approx(dealt, config.summon_damage * growth("damage", 10)), "an automaton's hits grow with its skill level (%.2f)" % dealt)

	await fresh(10.0)
	arena.spawn_ally(Vector3(1, 0, 0), false, "t0")
	check(is_equal_approx(arena.allies[0].max_hp, config.turret_hp * growth("hp", 10)), "a turret's HP grows with its skill level")
	dealt = await first_hit(false)
	check(is_equal_approx(dealt, config.turret_damage * growth("damage", 10)), "a turret's shots grow with its skill level (%.2f)" % dealt)

	await fresh(12.0, "A")
	arena.spawn_ally(Vector3(2.5, 0, 0), true, "t0")
	var before: float = arena.enemies.t0.hp
	arena.expire_ally(arena.allies[0])
	dealt = before - arena.enemies.t0.hp
	check(is_equal_approx(dealt, config.shot_damage * float(config.automaton_nodes.A.blast_factor) * growth("damage", 12)), "the A blast grows with the level, blueprint levels past 10 included (%.2f)" % dealt)

	await fresh(10.0, "B")
	arena.spawn_ally(Vector3(2, 0, 0), true, "t0")
	check(is_equal_approx(arena.allies[0].max_hp, config.automaton_hp * float(config.automaton_nodes.B.hp_factor) * growth("hp", 10)), "the B node's sturdiness multiplies on top of the level")
	dealt = await first_hit(true)
	check(is_equal_approx(dealt, config.summon_damage * float(config.automaton_nodes.B.damage_factor) * growth("damage", 10)), "the B node's damage factor multiplies on top of the level (%.2f)" % dealt)

	# The skill tree shows the growth next to accuracy and crit.
	arena.build.skills.automaton = 10
	arena.build.apply()
	arena.skill_window.visible = true
	arena.refresh_build_windows()
	var notes: Array = arena.skill_window.find_children("*", "Label", true, false).filter(func(l): return l.text.begins_with("체력 ×%.2f · 피해 ×%.2f" % [growth("hp", 10), growth("damage", 10)]))
	check(notes.size() >= 1, "the skill tree shows the summon's HP and damage growth")
	arena.skill_window.visible = false

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_summon_growth_report.json").simplify_path()
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
