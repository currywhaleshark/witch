extends SceneTree
## Drive tree executions and control (03 §4): the guillotine (and its saw and lock nodes), the
## hydraulic press, the compound executor, the restraint winch (and its multi-strand nodes) and the
## exoskeleton. Devices assemble on their spot during the cast, run on their own afterwards, and hit
## harder on wounded or debuffed enemies. Writes no report.
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

func enemy(id: String, at: Vector3, kind: String = "light") -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", kind)
	var spawned: Dictionary = arena.enemies[id]
	spawned.cooldown = 999
	# Tough enough to outlast every hit here: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func fresh(skill: String) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.bind_slot("q", skill)
	# Far off every device, so the field never counts as cleared.
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)

func cast_at(ground: Vector3) -> void:
	arena.request_slot("q", {"ground": [ground.x, 0, ground.z]})

func cast_on(id: String) -> void:
	var at: Vector3 = arena.enemies[id].body.position
	arena.request_slot("q", {"enemy_id": id, "ground": [at.x, 0, at.z]})

func release(skill: String) -> void:
	var data: Dictionary = arena.rules.skills[skill]
	await step(int(60 * float(data.cast_seconds) * float(data.release_ratio)) + 2)

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func until_done(limit: float = 4.0) -> void:
	for i in int(60 * limit):
		if arena.devices.is_empty() and arena.winches.is_empty():
			return
		await step()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	var skills: Dictionary = arena.rules.skills
	for id in ["guillotine", "hydraulic_press", "compound_executor", "restraint_winch", "exoskeleton"]:
		check(arena.SKILL_TREES.get(id) == "drive" and arena.build.learned(id), "%s is a learned drive skill" % id)

	# --- the guillotine -----------------------------------------------------------------------
	await fresh("guillotine")
	var plan: Dictionary = skills.guillotine.nodes.base
	var victim := enemy("victim", Vector3(0, 0, 4))
	var aside := enemy("aside", Vector3(2.2, 0, 4))
	check(arena.spatial_check(skills.guillotine, {"ground": [0, 0, 4]}) == null, "it can be set right over an enemy")
	var mana: float = arena.state.mana
	cast_at(Vector3(0, 0, 4))
	await step(3)
	var visual: Node3D = arena.device_assembly
	check(is_instance_valid(visual) and visual.debug_state().mode == "assembling" and arena.devices.is_empty(), "it assembles during the cast")
	check(is_instance_valid(visual) and Vector2(visual.global_position.x, visual.global_position.z).distance_to(Vector2(0, 4)) < 0.01, "on the spot she picked")
	await release("guillotine")
	check(arena.devices.size() == 1 and arena.device_assembly == null and visual.debug_state().mode == "working", "on release it starts working on its own")
	check(is_equal_approx(mana - arena.state.mana, float(skills.guillotine.mana_cost)) and float(arena.state.cooldowns.get("guillotine", 0.0)) > 0.0, "paying its mana and starting its cooldown")
	check(lost("victim") == 0.0, "the blade is still up right after the release")
	var blade: Dictionary = visual.parts.filter(func(part): return visual.group(part) == "drop")[0]
	var top: float = blade.mesh.position.y
	await step(int(60 * (float(plan.drop_at) + float(plan.drop_seconds))) + 2)
	check(blade.mesh.position.y < top - 1.0, "the blade comes down its guide (%.2fm)" % (top - blade.mesh.position.y))
	check(is_equal_approx(lost("victim"), float(plan.damage)), "and cuts the enemy under it (%.1f)" % lost("victim"))
	check(lost("aside") == 0.0, "but not one beside the frame")
	await until_done()
	await step(2)
	check(arena.devices.is_empty() and not is_instance_valid(visual), "it comes apart afterwards")

	# Execution bonus: more for HP lost, and once more if any tool debuff is on it. A device's own
	# stun or bind is no tool mark.
	var bonus: Dictionary = arena.config.execution
	await fresh("guillotine")
	victim = enemy("victim", Vector3(0, 0, 4))
	victim.hp = 99999.0 * 0.5
	victim.stun = 5.0
	var expected: float = float(plan.damage) * (1.0 + float(bonus.low_hp_bonus) * 0.5)
	cast_at(Vector3(0, 0, 4))
	await release("guillotine")
	await step(int(60 * (float(plan.drop_at) + float(plan.drop_seconds))) + 2)
	check(absf((99999.0 * 0.5 - victim.hp) - expected) < 0.5, "a half-dead enemy takes more, but a stun is no tool mark (%.1f / %.1f)" % [99999.0 * 0.5 - victim.hp, expected])
	for marks in [["slow"], ["slow", "shred"], ["winched", "bound"]]:
		await fresh("guillotine")
		victim = enemy("victim", Vector3(0, 0, 4))
		victim.hp = 99999.0 * 0.5
		for mark in marks:
			victim[mark] = 5.0
		# Shred also raises the damage taken on its own.
		expected = float(plan.damage) * (1.0 + float(bonus.low_hp_bonus) * 0.5 + float(bonus.debuff_bonus)) * (float(arena.config.shred_damage_taken) if "shred" in marks else 1.0)
		cast_at(Vector3(0, 0, 4))
		await release("guillotine")
		await step(int(60 * (float(plan.drop_at) + float(plan.drop_seconds))) + 2)
		check(absf((99999.0 * 0.5 - victim.hp) - expected) < 0.5, "marks %s give the bonus once (%.1f / %.1f)" % [str(marks), 99999.0 * 0.5 - victim.hp, expected])

	# Saw node: a slow spinning descent that cuts again and again.
	arena.build.set_skill_node("guillotine", "saw")
	check(arena.config.guillotine_node == "saw", "the saw node can be picked")
	await fresh("guillotine")
	plan = skills.guillotine.nodes.saw
	victim = enemy("victim", Vector3(0, 0, 4))
	cast_at(Vector3(0, 0, 4))
	await release("guillotine")
	check(arena.devices[0].model == "guillotine_saw", "it builds the saw guillotine")
	await step(int(60 * float(plan.tick_from)) + 2)
	var first_cut: float = lost("victim")
	await until_done()
	check(first_cut > 0.0 and first_cut < float(plan.tick_damage) * 1.5, "the saw starts cutting partway down")
	check(lost("victim") > float(plan.tick_damage) * float(plan.ticks) * 0.99, "and keeps cutting %d times (%.1f)" % [int(plan.ticks), lost("victim")])

	# Lock node: the nearest enemy is clamped, dragged under the blade and cut much harder.
	arena.build.set_skill_node("guillotine", "lock")
	await fresh("guillotine")
	plan = skills.guillotine.nodes.lock
	victim = enemy("victim", Vector3(1.2, 0, 4))
	var other := enemy("other", Vector3(-1.4, 0, 4.0))
	cast_at(Vector3(0, 0, 4))
	await release("guillotine")
	await step(3)
	check(arena.devices[0].locked == "victim" and float(victim.bound) > 0.0, "the lock takes the nearest enemy and holds it")
	await step(int(60 * float(plan.clamp_seconds)) + 4)
	var gap: Vector3 = victim.body.position - Vector3(0, victim.body.position.y, 4)
	check(Vector2(gap.x, gap.z).length() < 0.3, "pulled under the blade (%.2fm off)" % Vector2(gap.x, gap.z).length())
	await step(int(60 * (float(plan.drop_at) + float(plan.drop_seconds) - float(plan.clamp_seconds))) + 2)
	check(lost("victim") > float(plan.damage) * float(plan.lock_bonus) * 0.99, "the locked enemy takes ×%.1f (%.1f)" % [float(plan.lock_bonus), lost("victim")])
	check(float(other.get("bound", 0.0)) == 0.0, "the lock holds only the nearest")
	check(float(victim.bound) <= 0.0, "and lets go after the cut")
	arena.build.set_skill_node("guillotine", "base")

	# --- the hydraulic press --------------------------------------------------------------------
	await fresh("hydraulic_press")
	var press: Dictionary = skills.hydraulic_press
	var under := enemy("under", Vector3(0, 0, 4))
	var edge := enemy("edge", Vector3(1.1, 0, 4))
	var outside := enemy("outside", Vector3(3.0, 0, 4))
	edge.windup = 5.0
	edge.attack = "melee"
	cast_at(Vector3(0, 0, 4))
	await release("hydraulic_press")
	await step(int(60 * (float(press.press_at) + float(press.press_seconds))) + 2)
	check(is_equal_approx(lost("under"), float(press.damage)) and lost("edge") > 0.0 and lost("outside") == 0.0, "the press hits its wide platen (%.1f / %.1f / %.1f)" % [lost("under"), lost("edge"), lost("outside")])
	check(float(under.stun) > 1.0 and float(edge.stun) > 1.0 and float(outside.get("stun", 0.0)) == 0.0, "and stuns those it hit (%.2fs)" % float(under.stun))
	check(edge.windup == 0.0 and edge.attack == "", "breaking off an attack being wound up")
	arena.config.enemy_speed = 3.0
	var held: Vector3 = under.body.position
	await step(30)
	check(under.body.position.distance_to(held) < 0.01, "a stunned enemy does not move")
	arena.config.enemy_speed = 0

	# --- the compound executor ---------------------------------------------------------------------
	arena.build.change_skill("hydraulic_press", 2)
	await fresh("compound_executor")
	var cage: Dictionary = skills.compound_executor
	var a := enemy("a", Vector3(0.7, 0, 4))
	var b := enemy("b", Vector3(-0.6, 0, 4.3))
	# A short slow, still on when the gates shut, gone by the time the press lands.
	a.slow = 1.0
	var free := enemy("free", Vector3(3.0, 0, 4))
	cast_at(Vector3(0, 0, 4))
	await release("compound_executor")
	await step(int(60 * float(cage.gate_seconds)) + 2)
	check(arena.devices[0].caged.size() == 2 and float(a.bound) > 0.0 and float(b.bound) > 0.0, "its gates trap the two inside")
	check(float(free.get("bound", 0.0)) == 0.0, "but not one outside")
	await step(int(60 * (float(cage.press_at) + float(cage.press_seconds) - float(cage.gate_seconds))) + 2)
	var pressed: float = lost("a")
	var synergy: float = 1.0 + float(cage.synergy_per_level) * 2.0
	check(float(a.slow) <= 0.0 and absf(pressed - float(cage.press_damage) * synergy * (1.0 + float(bonus.debuff_bonus))) < 0.5, "the press lands, raised by the press's level and the slow the enemy was caught with (%.1f)" % pressed)
	check(absf(lost("b") - float(cage.press_damage) * synergy) < 0.5, "while the cage's own bind and an unmarked enemy add nothing (%.1f)" % lost("b"))
	check(float(a.stun) > 0.0, "and stuns")
	await until_done()
	check(lost("a") > pressed + float(cage.saw_damage) * float(cage.saw_ticks), "then the saw arms cut %d times (%.1f)" % [int(cage.saw_ticks), lost("a") - pressed])
	check(arena.probe.counts.bleeds_applied >= 2, "leaving them bleeding")
	check(float(a.bound) <= 0.0, "and the gates let them go")

	# --- the restraint winch ---------------------------------------------------------------------
	await fresh("restraint_winch")
	var winch: Dictionary = skills.restraint_winch
	var crow := enemy("crow", Vector3(0, 0, 6.5), "crow")
	cast_on("crow")
	await step(3)
	check(is_instance_valid(arena.device_assembly) and arena.device_assembly.global_position.distance_to(Vector3(0, 0, float(winch.offset))) < 0.05, "the winch sets down in front of her")
	await release("restraint_winch")
	await step(int(60 * (float(winch.fly_seconds) + float(winch.pull_seconds))) + 6)
	check(crow.body.position.distance_to(Vector3(0, crow.body.position.y, float(winch.stop_distance))) < 0.35, "and reels the enemy in front of her (%.2fm)" % crow.body.position.z)
	check(float(crow.bound) > 1.5 and lost("crow") > 0.0, "binding it after a small hit")
	check(float(crow.winched) > 1.5 and arena.tool_marked(crow), "and the winch's bind marks it for the executions")
	await until_done()
	check(arena.winches.is_empty(), "the hooks come home")

	await fresh("restraint_winch")
	var brute := enemy("brute", Vector3(0, 0, 6.5), "brute")
	cast_on("brute")
	await release("restraint_winch")
	await step(int(60 * (float(winch.fly_seconds) + float(winch.pull_seconds))) + 6)
	check(brute.body.position.z > 3.0 and brute.body.position.z < 5.5, "a heavy enemy comes only half way (%.2fm)" % brute.body.position.z)

	arena.build.set_skill_node("restraint_winch", "multi_pull")
	await fresh("restraint_winch")
	var group := [enemy("g0", Vector3(0, 0, 6.5)), enemy("g1", Vector3(1.4, 0, 6.8)), enemy("g2", Vector3(-1.4, 0, 6.6)), enemy("g3", Vector3(0, 0, 10))]
	cast_on("g0")
	await release("restraint_winch")
	await step(int(60 * (float(winch.fly_seconds) + float(winch.pull_seconds))) + 6)
	check(group[0].body.position.z < 3.0 and group[1].body.position.z < 3.0 and group[2].body.position.z < 3.0, "several lines reel the group in together")
	check(group[3].body.position.z > 9.0, "but only those near the target")

	arena.build.set_skill_node("restraint_winch", "multi_bind")
	await fresh("restraint_winch")
	group = [enemy("g0", Vector3(0, 0, 6.5)), enemy("g1", Vector3(1.4, 0, 6.8))]
	cast_on("g0")
	await release("restraint_winch")
	await step(int(60 * float(winch.fly_seconds)) + 4)
	check(group[0].body.position.z > 6.0 and float(group[0].bound) > 2.5 and float(group[1].bound) > 2.5, "the bind node ties them down where they stand")
	arena.build.set_skill_node("restraint_winch", "base")

	# --- the exoskeleton ----------------------------------------------------------------------------
	await fresh("exoskeleton")
	var frame: Dictionary = skills.exoskeleton
	var bare_armor: float = arena.armor()
	var bare_stun: float = arena.hit_recovery_seconds()
	arena.request_slot("q", {"ground": [0, 0, 2]})
	await release("exoskeleton")
	check(arena.exo_time > 7.0 and is_equal_approx(arena.armor() - bare_armor, float(frame.armor_base) + float(frame.armor_per_level) * (arena.config.exoskeleton_level - 1)), "the exoskeleton adds armour while worn")
	check(is_equal_approx(arena.exo_tool_factor(), 1.0 + float(frame.tool_damage) + float(frame.tool_damage_per_level) * (arena.config.exoskeleton_level - 1)), "and drives the tool attacks harder")
	check(is_equal_approx(arena.hit_recovery_seconds(), bare_stun), "its first levels leave the stagger alone")
	arena.config.exoskeleton_level = 10
	check(absf(arena.hit_recovery_seconds() - bare_stun * (1.0 - 2.0 * float(frame.stun_cut))) < 0.0001, "every fifth level cuts the stagger (Lv10 −%d%%)" % roundi(200 * float(frame.stun_cut)))
	arena.config.exoskeleton_level = 1
	await step(20)
	check(is_instance_valid(arena.exo_visual) and arena.exo_visual.shown > 0.99 and arena.exo_visual.get_parent() == arena.player_visual.runtime.skeleton, "the fitted frame is worn on her skeleton")
	arena.exo_time = 0.05
	await step(30)
	check(arena.exo_visual == null and is_equal_approx(arena.armor(), bare_armor), "and comes off when it runs out")

	# --- the shock-absorbing frame passive -------------------------------------------------------
	var absorb: Dictionary = arena.config.passives.shock_frame
	arena.build.change_skill("shock_frame", 4)
	check(arena.shock_level() == 4.0, "the shock-absorbing frame is a passive with levels")
	arena.exo_time = 5.0
	var exo_armor: float = arena.armor()
	arena.config.passive_levels.shock_frame = 0
	check(is_equal_approx(exo_armor - arena.armor(), 4.0 * float(absorb.exo_armor_per_level)), "it reinforces the exoskeleton's armour")
	var plain_stagger: float = arena.hit_recovery_seconds()
	arena.config.passive_levels.shock_frame = 4
	check(absf(arena.hit_recovery_seconds() - plain_stagger * (1.0 - 4.0 * float(absorb.exo_stagger_cut_per_level))) < 0.0001, "and shortens the stagger while it is worn")
	arena.exo_time = 0.0
	arena.shield_time = 3.0
	var shield_armor: float = arena.armor()
	arena.config.passive_levels.shock_frame = 0
	check(is_equal_approx(shield_armor - arena.armor(), 4.0 * float(absorb.shield_armor_per_level)), "the raised shield gains armour too")
	arena.shield_time = 0.0
	arena.config.passive_levels.shock_frame = 4
	arena.force_rolls = {"hit": true, "crit": false}
	arena.spawn_ally(Vector3(2, 0, 2), false, "")
	var turret: Dictionary = arena.allies[-1]
	var before: float = turret.hp
	arena.damage_ally(turret, 10.0, "normal")
	check(is_equal_approx(before - turret.hp, 10.0 * (1.0 - 4.0 * float(absorb.summon_guard_per_level))), "and the summons shrug off part of each hit (%.2f)" % (before - turret.hp))
	arena.build.change_skill("shock_frame", -4)

	# --- pause, field clear and reset -------------------------------------------------------------
	await fresh("guillotine")
	victim = enemy("victim", Vector3(0, 0, 4))
	cast_at(Vector3(0, 0, 4))
	await release("guillotine")
	arena.paused = true
	await step(60)
	check(lost("victim") == 0.0 and float(arena.devices[0].time) < 0.1, "a pause holds the device")
	arena.paused = false
	arena.reset_arena()
	await step(2)
	check(arena.devices.is_empty() and arena.winches.is_empty() and arena.device_assembly == null, "a reset clears every device")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
