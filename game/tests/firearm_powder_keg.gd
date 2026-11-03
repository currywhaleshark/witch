extends SceneTree
## Firearm tree, area line (03 §3): the powder keg assembles in front of the witch, rolls along the
## floor toward the aim with its fuse burning, and bursts on the first enemy it touches, at a wall
## or where she aimed. The blast hits everyone in its radius without a hit roll. Writes no report.
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

func enemy(id: String, at: Vector3) -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", "light")
	var spawned: Dictionary = arena.enemies[id]
	spawned.cooldown = 999
	# Tough enough to outlast every blast here: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func fresh(at: Vector3 = Vector3.ZERO) -> void:
	arena.reset_arena()
	arena.player.position = at
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.bind_slot("q", "powder_keg")
	# Far off the rolling line, so the field never counts as cleared.
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)

func roll(ground: Vector3) -> void:
	arena.request_slot("q", {"ground": [ground.x, 0, ground.z]})

func until_burst(limit: float = 3.0) -> void:
	for i in int(60 * limit):
		if arena.kegs.is_empty() and not arena.last_keg.is_empty():
			return
		await step()

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	var skill: Dictionary = arena.rules.skills.powder_keg
	var damage: float = float(skill.blast_damage)

	check(skill.kind == "aim" and skill.get("targeting") == "direction" and arena.SKILL_TREES.powder_keg == "firearm", "the keg is a firearm skill aimed by direction")
	await fresh()
	var mana: float = arena.state.mana
	roll(Vector3(0, 0, 6))
	await step(3)
	var visual: Node3D = arena.keg_assembly
	check(is_instance_valid(visual) and visual.debug_state().mode == "assembling" and arena.kegs.is_empty(), "it assembles during the cast")
	check(is_instance_valid(visual) and visual.global_position.distance_to(Vector3(0, 0, float(skill.start_offset))) < 0.01, "on the floor just in front of her")
	check(is_instance_valid(visual) and visual.parts.size() == 30, "from the powder barrel's 30 parts")
	await step(int(60 * float(skill.cast_seconds) * float(skill.release_ratio)) + 2)
	check(arena.kegs.size() == 1 and arena.keg_assembly == null and visual.debug_state().mode == "rolling", "on release it sets off rolling")
	check(is_equal_approx(mana - arena.state.mana, float(skill.mana_cost)) and float(arena.state.cooldowns.get("powder_keg", 0.0)) > 0.0, "paying its mana and starting its cooldown")
	var fuse_before: int = visual.debug_state().fuse_segments
	var start: Vector3 = arena.kegs[0].position
	var stave: Dictionary = visual.parts.filter(func(part): return visual.role(part) == "stave_00")[0]
	var basis_before: Basis = stave.mesh.basis
	await step(20)
	var keg: Dictionary = arena.kegs[0]
	check(keg.position.z > start.z + 1.5 and absf(keg.position.x) < 0.01, "it rolls along the aim (%.2fm in 1/3s)" % (keg.position.z - start.z))
	check(not stave.mesh.basis.is_equal_approx(basis_before), "its staves turn as it rolls")
	check(visual.debug_state().fuse_segments < fuse_before, "its fuse burns down")
	arena.paused = true
	var held: Vector3 = keg.position
	await step(20)
	check(arena.kegs.size() == 1 and arena.kegs[0].position == held, "a paused keg stays put")
	arena.paused = false
	await until_burst()
	check(arena.last_keg.reason == "end" and absf(arena.last_keg.at.z - 6.0) < 0.05, "with nothing in its way it bursts where she aimed")
	check(visual.debug_state().mode == "burst" and visual.debug_state().fuse_segments == 0, "and flies apart")
	await step(70)
	check(not is_instance_valid(visual), "the pieces clear away")

	await fresh()
	enemy("front", Vector3(0, 0, 4))
	enemy("beside", Vector3(1.5, 0, 4.4))
	enemy("past", Vector3(0, 0, 7.2))
	roll(Vector3(0, 0, 8))
	await until_burst()
	check(arena.last_keg.reason == "enemy" and arena.last_keg.at.z < 4.0 and arena.last_keg.at.z > 3.0, "it bursts on the first enemy it rolls into (z %.2f)" % arena.last_keg.at.z)
	check(is_equal_approx(lost("front"), damage) and is_equal_approx(lost("beside"), damage), "the blast hits it and an enemy beside it for full damage")
	check(lost("past") == 0.0 and lost("anchor") == 0.0, "but not ones outside its radius")
	check(arena.probe.counts.enemy_flinches >= 2, "blasted enemies flinch")

	arena.force_rolls = {"hit": false, "crit": false}
	await fresh()
	enemy("front", Vector3(0, 0, 4))
	roll(Vector3(0, 0, 8))
	await until_burst()
	check(is_equal_approx(lost("front"), damage), "the blast needs no hit roll")
	arena.force_rolls = {"hit": true, "crit": false}

	await fresh(Vector3(8, 0, 0))
	roll(Vector3(20, 0, 0))
	await until_burst()
	var edge: float = arena.map.bounds.end.x
	check(arena.last_keg.reason == "wall" and arena.last_keg.at.x <= edge and arena.last_keg.at.x > edge - 0.3, "a wall stops it and it bursts there")

	await fresh()
	roll(Vector3(0, 0, 0.4))
	await until_burst()
	check(arena.last_keg.reason == "end" and is_equal_approx(arena.last_keg.at.z, float(skill.min_roll)), "a close aim still rolls it its shortest distance")
	await fresh()
	roll(Vector3(0, 0, -30))
	await until_burst()
	check(is_equal_approx(arena.last_keg.at.z, -float(skill.range)), "a far aim rolls it to its range")

	await fresh()
	arena.build.set_level(5)
	arena.build.change_skill("powder_keg", 2)
	enemy("front", Vector3(0, 0, 4))
	roll(Vector3(0, 0, 8))
	await until_burst()
	check(is_equal_approx(lost("front"), damage * arena.skill_level_factor("powder_keg")) and arena.skill_level_factor("powder_keg") > 1.1, "its skill level raises the blast damage")
	arena.build.reset_skills()
	arena.build.set_level(1)

	await fresh()
	roll(Vector3(0, 0, 6))
	await step(5)
	visual = arena.keg_assembly
	arena.cancel_summon_assemblies("hit_stun")
	arena.windup.clear()
	await step(40)
	check(arena.kegs.is_empty() and visual.debug_state().mode == "collapse", "an interrupted cast drops its half-built keg and rolls nothing")

	await fresh()
	roll(Vector3(0, 0, 6))
	await step(40)
	check(arena.kegs.size() == 1, "a keg is rolling")
	arena.reset_arena()
	check(arena.kegs.is_empty() and arena.get_tree().get_nodes_in_group("cast_assemblies").filter(func(node): return node.name.begins_with("PowderKeg") and not node.is_queued_for_deletion()).is_empty(), "resetting the field removes it")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
