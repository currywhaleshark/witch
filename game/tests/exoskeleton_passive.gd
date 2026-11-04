extends SceneTree
## The exoskeleton as a passive (2026-11-05): learned after the shield, worn only while a tool is
## transformed, no key and no mana of its own. Its frame node (1 point) leans it to defence (guard:
## the old shock-absorbing frame's shield and summon reinforcement) or to attack (drive: tool
## damage and upkeep), each keeping a weaker share of the other side. Writes no report.
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

func fresh() -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("anchor", Vector3(-11, 0, -9), false)
	arena.enemies.anchor.cooldown = 999
	arena.bind_slot("q", "bolt_cutter")
	await step(2)

func tool_on(on: bool) -> void:
	if (arena.state.active_tool != null) != on:
		arena.request_slot("q", {})
	await step(20)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	var frame: Dictionary = arena.rules.skills.exoskeleton
	var build = arena.build
	await fresh()

	# A passive in the drive tree after the shield; it takes no key.
	check(arena.SKILL_TREES.get("exoskeleton") == "drive" and not build.learned("exoskeleton"), "the exoskeleton starts unlearned in the drive tree")
	check(arena.skill_window.drag_data("exoskeleton", "") == null, "it cannot be put on a key")
	check(not build.passives.has("shock_frame") and not arena.config.passives.has("shock_frame"), "the shock-absorbing frame passive is gone")
	var points: int = build.skill_points()
	check(build.change_skill("exoskeleton", 1) and build.learned("exoskeleton") and build.skill_points() == points - 1, "one point learns it")

	# Worn only while a tool runs.
	var bare_armor: float = arena.armor()
	var bare_stun: float = arena.hit_recovery_seconds()
	check(not arena.exo_active() and is_equal_approx(arena.exo_tool_factor(), 1.0), "on the bare staff it does nothing")
	var mana: float = arena.state.mana
	await tool_on(true)
	check(arena.exo_active(), "a transformed tool puts it on")
	check(is_equal_approx(arena.armor() - bare_armor, float(frame.armor_base)), "it adds armour (Lv1 +%s)" % str(frame.armor_base))
	check(is_equal_approx(arena.exo_tool_factor(), 1.0 + float(frame.tool_damage)), "and drives the tool attacks harder (Lv1 +%d%%)" % roundi(100 * float(frame.tool_damage)))
	check(is_equal_approx(arena.hit_recovery_seconds(), bare_stun), "its first levels leave the stagger alone")
	var upkeep: float = float(arena.rules.skills.bolt_cutter.upkeep_per_second) * 20.0 / 60.0
	check(mana - arena.state.mana < upkeep + 0.05, "it costs no mana beyond the tool's upkeep")
	await step(20)
	check(is_instance_valid(arena.exo_visual) and arena.exo_visual.shown > 0.99 and arena.exo_visual.get_parent() == arena.player_visual.runtime.skeleton, "the fitted frame is worn on her skeleton")
	build.change_skill("exoskeleton", 9)
	check(absf(arena.hit_recovery_seconds() - bare_stun * (1.0 - 2.0 * float(frame.stun_cut))) < 0.0001, "every fifth level cuts the stagger (Lv10 −%d%%)" % roundi(200 * float(frame.stun_cut)))
	var base_armor: float = arena.exo_armor()
	var base_bonus: float = arena.exo_tool_bonus()
	check(is_equal_approx(base_armor, float(frame.armor_base) + 9.0 * float(frame.armor_per_level)) and is_equal_approx(base_bonus, float(frame.tool_damage) + 9.0 * float(frame.tool_damage_per_level)), "its armour and damage grow per level")
	await tool_on(false)
	await step(30)
	check(not arena.exo_active() and arena.exo_visual == null and is_equal_approx(arena.armor(), bare_armor), "putting the tool away takes it off")

	# Guard frame: twice the defence, half the damage, and the old shock frame's reinforcement.
	var guard: Dictionary = frame.nodes.guard
	points = build.skill_points()
	check(build.set_skill_node("exoskeleton", "guard") and build.skill_points() == points - 1, "a frame node costs one point")
	await tool_on(true)
	check(is_equal_approx(arena.exo_armor(), base_armor * float(guard.armor_factor)) and is_equal_approx(arena.exo_tool_bonus(), base_bonus * float(guard.damage_factor)), "the guard frame doubles the armour and keeps half the damage bonus")
	check(arena.exo_tool_bonus() > 0.0, "the damage bonus is weakened, not removed")
	check(absf(arena.hit_recovery_seconds() - bare_stun * (1.0 - 2.0 * float(frame.stun_cut) * float(guard.stun_cut_factor))) < 0.0001, "and cuts the stagger further")
	await tool_on(false)
	arena.shield_time = 3.0
	var shield_armor: float = arena.armor()
	build.set_skill_node("exoskeleton", "base")
	check(is_equal_approx(shield_armor - arena.armor(), 10.0 * float(guard.shield_armor_per_level)), "it reinforces the raised shield too, tool or not")
	arena.shield_time = 0.0
	build.set_skill_node("exoskeleton", "guard")
	arena.spawn_ally(Vector3(2, 0, 2), false, "")
	var turret: Dictionary = arena.allies[-1]
	var before: float = turret.hp
	arena.damage_ally(turret, 10.0, "normal")
	check(is_equal_approx(before - turret.hp, 10.0 * (1.0 - 10.0 * float(guard.summon_guard_per_level))), "and the summons shrug off part of each hit (%.2f)" % (before - turret.hp))

	# Drive frame: twice the damage, cheaper tools, half the defence.
	var drive: Dictionary = frame.nodes.drive
	build.set_skill_node("exoskeleton", "drive")
	var base_upkeep: float = float(arena.tool_upkeep.bolt_cutter) * (1.0 - minf(0.9, arena.gear_total("upkeep_pct") / 100.0))
	check(is_equal_approx(float(arena.rules.skills.bolt_cutter.upkeep_per_second), base_upkeep * (1.0 - float(drive.upkeep_cut))), "the drive frame trims the tools' upkeep")
	await tool_on(true)
	check(is_equal_approx(arena.exo_tool_bonus(), base_bonus * float(drive.damage_factor)) and is_equal_approx(arena.exo_armor(), base_armor * float(drive.armor_factor)), "it doubles the damage bonus and keeps half the armour")
	check(arena.exo_armor() > 0.0 and arena.summon_guard() == 0.0, "the armour is weakened, not removed; no summon reinforcement")
	await tool_on(false)
	build.set_skill_node("exoskeleton", "base")
	check(is_equal_approx(float(arena.rules.skills.bolt_cutter.upkeep_per_second), base_upkeep), "leaving the node restores the upkeep")

	# A skill reset unlearns it and refunds its node.
	build.set_skill_node("exoskeleton", "guard")
	build.reset_skills()
	check(not build.learned("exoskeleton") and arena.config.exoskeleton_node == "base" and arena.summon_guard() == 0.0, "a skill reset takes it and its node back")
	await tool_on(true)
	check(not arena.exo_active(), "and an unlearned exoskeleton is never worn")

	print("EXOSKELETON_PASSIVE ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
