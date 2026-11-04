extends SceneTree
## Drive tree tool attacks (03 §2): the focus attack (held channel: rapid hits on one enemy in
## front, piling the tool's mark) and the area attack (one motion per tool: the bolt cutter's
## enlarged-blade fan, the grinder's half circle, the chainsaw's full turn), both played with the
## v32 drive motions. They work only through a transformed tool. Writes no report.
const Build = preload("res://scripts/build.gd")
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

func settle(seconds: float) -> void:
	await step(int(60 * seconds))

func enemy(id: String, at: Vector3) -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", "light")
	var spawned: Dictionary = arena.enemies[id]
	spawned.cooldown = 999
	# Tough enough to outlast every hit here: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func point_at(pos: Vector3) -> void:
	arena.pointer = arena.camera.unproject_position(pos)

func fresh(tool, skill: String = "focus_attack", node: String = "base") -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.attack_speed_score = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.build.set_skill_node(skill, node)
	arena.bind_slot("q", skill)
	arena.bind_slot("w", tool if tool != null else "bolt_cutter")
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)
	if tool != null:
		arena.request_slot("w", {})
		await step(20)

func hold_q(at: Vector3) -> void:
	# What holding Q does: the hold is recorded, then the slot pressed.
	point_at(at)
	arena.hold = {"key": KEY_Q, "slot": "q", "shift": false, "enemy_id": ""}
	arena.request_slot("q", {"ground": [at.x, 0, at.z]})

func press_q(at: Vector3) -> void:
	point_at(at)
	arena.request_slot("q", {"ground": [at.x, 0, at.z]})

func clip() -> String:
	return String(arena.player_visual._clip).get_file()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	var focus: Dictionary = arena.rules.skills.focus_attack
	var area: Dictionary = arena.rules.skills.area_attack
	for id in ["focus_attack", "area_attack"]:
		check(arena.SKILL_TREES.get(id) == "drive" and arena.build.learned(id) and arena.rules.skills[id].get("tool_attack") == true, "%s is a learned drive tool attack" % id)
		check(Build.SKILL_NODE_NAMES.has(id) and Build.SKILL_NODE_NAMES[id].size() == 3, "%s has its two specialisation nodes" % id)
	var visual: Node3D = arena.player_visual
	for name in ["drive_bolt_enter_v32", "drive_bolt_loop_v32", "drive_bolt_exit_v32", "drive_chainsaw_cut_enter_v32", "drive_chainsaw_cut_loop_v32",
			"drive_chainsaw_cut_exit_v32", "drive_grinder_sweep_v32", "drive_chainsaw_spin_v32"]:
		check(arena.player_visual._staff_slide_tracks.has(name) and arena.player_visual.runtime.animation_player.has_animation(arena.player_visual._clips.values().filter(func(c): return String(c).get_file() == name)[0]), "the game loads the v32 clip %s with its staff slide" % name)

	# --- the bare staff cannot use them -----------------------------------------------------------
	await fresh(null)
	enemy("front", Vector3(0, 0, 1.5))
	var mana: float = arena.state.mana
	hold_q(Vector3(0, 0, 1.5))
	await step(3)
	check(arena.windup.is_empty() and arena.channel.is_empty() and arena.message == "공구를 전개해야 쓸 수 있습니다" and is_equal_approx(mana, arena.state.mana), "without a tool the key only says a tool is needed")
	arena.hold.clear()

	# --- focus attack: bolt cutter --------------------------------------------------------------
	await fresh("bolt_cutter")
	check(arena.state.active_tool == "bolt_cutter", "the bolt cutter is out")
	enemy("front", Vector3(0, 0, 1.5))
	mana = arena.state.mana
	hold_q(Vector3(0, 0, 1.5))
	await step(3)
	check(not arena.windup.is_empty() and arena.player_visual._state == "focus_enter" and clip() == "drive_bolt_enter_v32", "it starts with the bolt thrust's enter motion")
	await settle(float(focus.enter_seconds))
	var plan: Dictionary = focus.tools.bolt_cutter
	check(arena.channel.get("skill") == "focus_attack" and arena.channel.tool == "bolt_cutter" and arena.player_visual._state == "focus_loop" and clip() == "drive_bolt_loop_v32", "then holds the thrust loop")
	check(mana - arena.state.mana >= float(focus.mana_cost), "the start pays its mana")
	mana = arena.state.mana
	var hits: int = arena.channel.hits
	await settle(1.8)
	var landed: int = arena.channel.hits - hits
	check(absi(landed - roundi(1.8 / float(plan.interval))) <= 1, "it thrusts once per %.2fs loop (%d in 1.8s)" % [float(plan.interval), landed])
	check(float(plan.interval) < arena.attack_seconds("bolt_cutter") * 0.6, "faster than the bolt cutter's own attack")
	check(lost("front") > 0 and fmod(lost("front"), float(plan.damage)) < 0.01, "each thrust deals the focus damage (%.1f)" % lost("front"))
	check(float(arena.enemies.front.slow) > 0.0, "and keeps the bolt cutter's slow on it")
	var drained: float = mana - arena.state.mana
	check(absf(drained - 1.8 * (float(focus.channel_mana_per_second) + float(arena.rules.skills.bolt_cutter.upkeep_per_second))) < 0.4, "mana drains by the second on top of the tool's upkeep (%.2f)" % drained)
	check(absf(fposmod(arena.channel.time / arena.channel.loop, 1.0) - arena.player_visual._loop_phase) < 0.001, "the loop pose follows the channel clock")

	# She turns after the cursor and keeps her spot.
	enemy("side", Vector3(1.5, 0, 0))
	point_at(Vector3(1.5, 0, 0))
	var spot: Vector3 = arena.player.position
	var side_before := lost("side")
	await settle(1.0)
	check(lost("side") > side_before and (-arena.player_model.global_basis.z).dot(Vector3.RIGHT) > 0.95, "the thrusts follow the cursor to another enemy")
	arena.move_hold = {"button": MOUSE_BUTTON_LEFT}
	arena.request_slot("lmb", {"ground": [-4, 0, 0]})
	await settle(0.3)
	check(arena.player.position.distance_to(spot) < 0.01 and not arena.channel.is_empty(), "a ground click does not move her while she channels")
	arena.move_hold.clear()

	arena.paused = true
	hits = arena.channel.hits
	await settle(0.6)
	check(arena.channel.hits == hits, "pausing stops the thrusts")
	arena.paused = false

	arena.hold.clear()
	await step(2)
	check(arena.channel.is_empty() and arena.player_visual._state == "focus_exit" and clip() == "drive_bolt_exit_v32" and arena.action_time > 0.0, "releasing the key plays the exit motion")
	await settle(float(focus.exit_seconds) + 0.05)
	check(arena.player_visual._state == "idle" and arena.action_time == 0.0, "then she is back in her guard")

	# --- focus attack: grinder and chainsaw (the sustained cut) -------------------------------
	await fresh("grinder")
	enemy("front", Vector3(0, 0, 1.5))
	hold_q(Vector3(0, 0, 1.5))
	await step(3)
	check(clip() == "drive_chainsaw_cut_enter_v32", "the grinder presses in with the sustained cut's enter motion")
	await settle(float(focus.enter_seconds))
	check(clip() == "drive_chainsaw_cut_loop_v32", "and holds the cut loop")
	hits = arena.channel.hits
	await settle(1.0)
	landed = arena.channel.hits - hits
	check(absi(landed - roundi(1.0 / float(focus.tools.grinder.interval))) <= 1, "it grinds %d times a second" % landed)
	check(float(arena.enemies.front.shred) > 0.0, "and shreds the enemy's armour")
	check(fmod(lost("front"), float(focus.tools.grinder.damage) * float(arena.config.shred_damage_taken)) < 0.05, "every grind lands on the shredded armour (%.2f)" % lost("front"))
	arena.hold.clear()
	await settle(0.5)

	await fresh("chainsaw")
	enemy("front", Vector3(0, 0, 1.5))
	hold_q(Vector3(0, 0, 1.5))
	await settle(float(focus.enter_seconds) + 0.6)
	check(clip() == "drive_chainsaw_cut_loop_v32" and arena.enemies.front.bleeds.size() >= 2, "the chainsaw saws in and piles up bleed stacks (%d)" % arena.enemies.front.bleeds.size())
	var before: Vector3 = -arena.player_model.global_basis.z
	point_at(Vector3(4, 0, 0))
	await settle(0.3)
	var turned: float = rad_to_deg(before.angle_to(-arena.player_model.global_basis.z))
	check(turned > 15.0 and turned < 60.0, "the chainsaw turns slowly after the cursor (%.0f degrees in 0.3s)" % turned)
	arena.request_slot("w", {})
	await step(2)
	check(arena.channel.is_empty(), "putting the tool away ends the stream")
	arena.hold.clear()
	await settle(0.5)

	# --- focus nodes ------------------------------------------------------------------------------
	await fresh("bolt_cutter", "focus_attack", "power")
	enemy("front", Vector3(0, 0, 1.5))
	hold_q(Vector3(0, 0, 1.5))
	await settle(float(focus.enter_seconds) + 1.0)
	check(lost("front") > 0 and fmod(lost("front"), float(plan.damage) * float(focus.nodes.power.damage_factor)) < 0.05, "the focus damage node hits harder (%.1f)" % lost("front"))
	arena.hold.clear()
	await settle(0.5)
	await fresh("bolt_cutter", "focus_attack", "debuff")
	enemy("front", Vector3(0, 0, 1.5))
	hold_q(Vector3(0, 0, 1.5))
	await settle(float(focus.enter_seconds) + 0.3)
	check(float(arena.enemies.front.slow) > float(arena.rules.skills.bolt_cutter.debuff_seconds) + 0.3, "the debuff node lengthens the slow (%.2fs)" % float(arena.enemies.front.slow))
	arena.hold.clear()
	await settle(0.5)
	await fresh("chainsaw", "focus_attack", "debuff")
	enemy("front", Vector3(0, 0, 1.5))
	hold_q(Vector3(0, 0, 1.5))
	await settle(float(focus.enter_seconds) + 0.2)
	check(arena.enemies.front.bleeds.size() >= 2 and arena.channel.hits <= 1, "and doubles the chainsaw's bleed stacks per hit")
	arena.hold.clear()
	await settle(0.5)

	# A heavy hit interrupts the stream without the exit motion.
	await fresh("bolt_cutter")
	enemy("front", Vector3(0, 0, 1.5))
	hold_q(Vector3(0, 0, 1.5))
	await settle(float(focus.enter_seconds) + 0.3)
	arena.damage_player(arena.config.max_hp * 0.5, "normal")
	await step(2)
	check(arena.channel.is_empty() and arena.player_visual._state == "hit", "a heavy hit breaks the stream into the hit reaction")
	arena.hold.clear()
	await settle(1.0)
	arena.hp = arena.config.max_hp

	# --- area attack: bolt cutter --------------------------------------------------------------
	await fresh("bolt_cutter", "area_attack")
	var cut: Dictionary = area.tools.bolt_cutter
	enemy("near", Vector3(0, 0, 1.5))
	enemy("far", Vector3(0.3, 0, 3.2))
	enemy("wide", Vector3(2.0, 0, 2.0))
	enemy("out", Vector3(0, 0, 5.0))
	mana = arena.state.mana
	press_q(Vector3(0, 0, 3))
	await step(3)
	check(arena.player_visual._state == "area" and clip() == "combat_heavy_swing_rh_v20", "the bolt cutter's area cut swings the heavy swing")
	var seconds: float = arena.tool_attack_seconds("area_attack", "bolt_cutter")
	await settle(seconds * float(cut.release_ratio) - 0.1)
	check(lost("near") == 0.0 and arena.player_visual.blade_scale > 1.5, "the blade grows for the swing (x%.2f)" % arena.player_visual.blade_scale)
	await settle(0.15)
	check(lost("near") > 0 and lost("far") > 0 and lost("wide") == 0.0 and lost("out") == 0.0, "it cuts a long narrow fan at the swing's impact")
	check(is_equal_approx(lost("near"), float(cut.damage)) and float(arena.enemies.near.slow) > 0.0, "each for the area damage, with the slow")
	check(is_equal_approx(mana - arena.state.mana, float(area.mana_cost)) or mana - arena.state.mana > float(area.mana_cost), "paying its mana")
	await settle(seconds)
	check(is_equal_approx(arena.player_visual.blade_scale, 1.0) and arena.player_visual._state == "idle", "the blade shrinks back afterwards")

	# --- area attack: grinder half circle ------------------------------------------------------
	await fresh("grinder", "area_attack")
	enemy("right", Vector3(-1.6, 0, 0.3))
	enemy("front", Vector3(0, 0, 1.8))
	enemy("left", Vector3(1.6, 0, 0.3))
	enemy("behind", Vector3(0, 0, -1.6))
	# Facing +Z the witch's right is -X.
	press_q(Vector3(0, 0, 3))
	await step(3)
	check(clip() == "drive_grinder_sweep_v32", "the grinder sweeps with its half-circle motion")
	var order: Array = []
	for i in 120:
		await step()
		for id in ["right", "front", "left", "behind"]:
			if lost(id) > 0 and id not in order:
				order.append(id)
	check(order == ["right", "front", "left"], "the grinder cuts right to left as the blade passes (%s)" % str(order))
	check(lost("behind") == 0.0 and float(arena.enemies.front.shred) > 0.0, "nothing behind her, and it shreds")
	check(arena.last_tool_attack.struck.size() == 3, "each enemy once")

	# --- area attack: chainsaw full turn -------------------------------------------------------
	await fresh("chainsaw", "area_attack")
	for i in 6:
		var a := TAU * i / 6.0
		enemy("ring%d" % i, Vector3(sin(a) * 1.8, 0, cos(a) * 1.8))
	enemy("outside", Vector3(0, 0, 4.0))
	press_q(Vector3(0, 0, 3))
	await step(3)
	check(clip() == "drive_chainsaw_spin_v32", "the chainsaw turns a full circle")
	await settle(arena.tool_attack_seconds("area_attack", "chainsaw") + 0.1)
	var ring_hit := true
	for i in 6:
		ring_hit = ring_hit and lost("ring%d" % i) > 0 and arena.enemies["ring%d" % i].bleeds.size() == 1
	check(ring_hit and lost("outside") == 0.0, "every enemy around her bleeds once, none beyond its reach")
	check(arena.sweep.is_empty(), "and the sweep ends with the motion")

	# A heavy hit during the sweep stops it.
	await fresh("chainsaw", "area_attack")
	enemy("front", Vector3(0, 0, 1.8))
	enemy("behind", Vector3(0, 0, -1.8))
	press_q(Vector3(0, 0, 3))
	await settle(arena.tool_attack_seconds("area_attack", "chainsaw") * 0.42)
	arena.damage_player(arena.config.max_hp * 0.5, "normal")
	await settle(1.6)
	check(lost("front") > 0 and lost("behind") == 0.0 and arena.sweep.is_empty(), "a heavy hit stops the turn halfway")
	arena.hp = arena.config.max_hp

	# Attack speed shortens the motions and intervals.
	await fresh("bolt_cutter")
	var slow_interval: float = arena.tool_speed(float(plan.interval))
	arena.config.attack_speed_score = 40
	check(arena.tool_speed(float(plan.interval)) < slow_interval and arena.tool_attack_seconds("area_attack", "grinder") < arena.tool_speed(float(area.tools.grinder.seconds)) + 0.001, "attack speed quickens the tool attacks")

	print("TOOL_ATTACKS %d checks, %d failures" % [checks.size(), failures.size()])
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if failures.size() > 0 else 0)
