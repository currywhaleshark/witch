extends RefCounted
## Staff tools (03 §4): bolt cutter / grinder / chainsaw channels, focus and area tool attacks, the
## grinder sweep and per-hit tool damage. Tool state (channel, sweep, tool_upkeep, ...) stays on the
## arena. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func tool_speed(base: float) -> float:
	# Tool attacks are attacks: their motions and hit intervals follow attack speed.
	return arena.motion_seconds(base, base * arena.config.min_cast_ratio, arena.config.attack_speed_k, arena.config.attack_speed_score)

func tool_attack_plan(skill_id: String, tool) -> Dictionary:
	# The tool's own numbers for this attack, with the chosen node's factors on top.
	var skill: Dictionary = arena.rules.skills[skill_id]
	var plan: Dictionary = (skill.tools.get(tool, {}) as Dictionary).duplicate(true)
	plan.merge(skill.nodes[arena.config[skill_id + "_node"]], true)
	return plan

func tool_attack_seconds(skill_id: String, tool) -> float:
	var skill: Dictionary = arena.rules.skills[skill_id]
	return tool_speed(float(skill.enter_seconds) if skill_id == "focus_attack" else float(tool_attack_plan(skill_id, tool).seconds))

func tool_hit_damage(skill_id: String, plan: Dictionary) -> float:
	# The exoskeleton drives every tool attack harder; the skill's level and damage node add on.
	return float(plan.damage) * float(plan.get("damage_factor", 1.0)) * arena.exo_tool_factor() * arena.skill_level_factor(skill_id)

func tool_strike(id: String, tool: String, damage: float, plan: Dictionary, skill_id: String) -> String:
	# One tool hit rolls to hit like the basic attack and, on a hit, leaves the tool's own mark:
	# slow (bolt cutter), shred (grinder) or bleed (chainsaw). The debuff node lengthens slow and
	# shred and adds bleed stacks. The log keeps it apart from the tool's basic attacks under
	# "<skill>:<tool>"; damage rules still treat the tool as its source.
	var result := "miss"
	var label := skill_id + ":" + tool
	if tool == "chainsaw":
		result = arena.strike(id, damage, true, "witch", tool, "", label)
		if result != "miss":
			for i in int(plan.get("bleed_stacks", 1)):
				if arena.enemies.has(id):
					arena.add_bleed(id)
		return result
	var debuff: String = arena.rules.skills[tool].debuff
	var before: float = arena.enemies[id][debuff]
	arena.enemies[id][debuff] = maxf(before, float(arena.rules.skills[tool].debuff_seconds) * float(plan.get("debuff_factor", 1.0)))
	result = arena.strike(id, damage, true, "witch", tool, "", label)
	if result == "miss" and arena.enemies.has(id):
		arena.enemies[id][debuff] = before
	return result

func tool_hit_sound(tool: String) -> void:
	match tool:
		"bolt_cutter": arena.play_sfx("bolt_cutter_cut", 0.8)
		"grinder": arena.play_sfx("grinder_hit", 1.55)
		"chainsaw": arena.play_sfx("chainsaw_cut", 1.05)

func channel_slot(skill_id: String) -> String:
	# The key that holds the channel: the one pressed, else the first bound to it.
	var slot: String = arena.hold.get("slot", "")
	if arena.state.bindings.get(slot) != skill_id:
		slot = ""
		for key in arena.rules.SLOTS:
			if arena.state.bindings[key] == skill_id and slot == "":
				slot = key
	return slot

func start_tool_channel(tool, direction: Vector3) -> void:
	# Focus attack (03 §2): while its key is held she stands and strikes faster than her attack
	# speed, piling the tool's mark onto one enemy in front. The bolt cutter thrusts once per loop,
	# at the jaws' snap; the grinder and chainsaw hold the blade in and cut on their own clock.
	if tool == null:
		return
	var plan := tool_attack_plan("focus_attack", tool)
	var period: float = tool_speed(float(plan.interval))
	var loop: float = period if plan.has("hit_phase") else tool_speed(float(plan.loop_seconds))
	arena.moving = false
	arena.move_marker.visible = false
	arena.channel = {"skill": "focus_attack", "tool": tool, "slot": channel_slot("focus_attack"), "direction": direction,
		"time": 0.0, "period": period, "loop": loop, "fire_left": period * float(plan.get("hit_phase", 0.5)), "hits": 0, "plan": plan}
	arena.probe.channel_begin("focus_attack:" + str(tool))
	arena.player_visual.begin_focus_loop(tool, loop)

func tick_tool_channel(dt: float) -> void:
	var skill: Dictionary = arena.rules.skills.focus_attack
	if arena.state.active_tool != arena.channel.tool:
		# Switching or losing the tool ends the stream.
		stop_channel(true)
		return
	var cost: float = float(skill.channel_mana_per_second) * dt
	if arena.state.mana + arena.rules.EPS < cost:
		stop_channel(true)
		arena.show_message("마나 부족 · 공격 중지")
		return
	arena.state.mana = maxf(0.0, arena.state.mana - cost)
	arena.probe.record([{"type": "tool_upkeep", "tool": "focus_attack", "amount": cost}])
	arena.probe.channel_time("focus_attack:" + str(arena.channel.tool), dt, cost)
	var cursor := arena.field_cursor()
	var aim = null
	if cursor.get("enemy_id") != null and arena.enemies.has(cursor.enemy_id):
		aim = arena.enemies[cursor.enemy_id].body.position
	elif cursor.get("ground") != null:
		aim = arena.map.grounded(arena.point(cursor.ground))
	if aim != null:
		var flat: Vector3 = aim - arena.player.position
		flat.y = 0.0
		if flat.length() > 0.05:
			var wanted: Vector3 = flat.normalized()
			var plan: Dictionary = arena.channel.plan
			if plan.has("turn_degrees_per_second"):
				# The chainsaw cuts slowly: she turns the blade after the cursor at a limited rate.
				var current: Vector3 = arena.channel.direction
				var turn: float = current.signed_angle_to(wanted, Vector3.UP)
				var step: float = deg_to_rad(float(plan.turn_degrees_per_second)) * dt
				arena.channel.direction = current.rotated(Vector3.UP, clampf(turn, -step, step)).normalized()
			else:
				arena.channel.direction = wanted
	var direction: Vector3 = arena.channel.direction
	arena.player_model.look_at(arena.player.position + direction)
	arena.channel.time = float(arena.channel.time) + dt
	arena.player_visual.set_focus_loop_phase(float(arena.channel.time) / float(arena.channel.loop))
	arena.channel.fire_left = float(arena.channel.fire_left) - dt
	while not arena.channel.is_empty() and arena.channel.fire_left <= 0:
		focus_hit(direction)
		arena.channel.fire_left = float(arena.channel.fire_left) + float(arena.channel.period)

func focus_hit(direction: Vector3) -> void:
	# The nearest enemy in front, in sight and in reach, takes the hit; an empty swing is silent.
	var tool: String = arena.channel.tool
	var best: String = arena.nearest_enemy(arena.player.position, float(arena.rules.skills.focus_attack.range), direction, 0.2, false, true)
	arena.channel.hits = int(arena.channel.hits) + 1
	if best == "":
		arena.last_tool_attack = {"skill": "focus_attack", "tool": tool, "target": "", "result": "miss", "hits": arena.channel.hits}
		return
	var damage := tool_hit_damage("focus_attack", arena.channel.plan)
	var result := tool_strike(best, tool, damage, arena.channel.plan, "focus_attack")
	if result != "miss":
		tool_hit_sound(tool)
		# Each landed bolt cutter thrust drags one more enemy in, like a basic attack hit.
		if tool == "bolt_cutter" and arena.gear_total("rule:chain_cut") > 0:
			arena.chain_cut(best, damage, [], "focus_attack:bolt_cutter")
	arena.last_tool_attack = {"skill": "focus_attack", "tool": tool, "target": best, "result": result, "hits": arena.channel.hits}

func tool_area(tool, direction: Vector3) -> void:
	# Area attack (03 §2): the bolt cutter's enlarged blade cuts a long, narrow fan at once; the
	# grinder's half circle and the chainsaw's full turn strike each enemy as the blade passes it.
	if tool == null:
		return
	var plan := tool_attack_plan("area_attack", tool)
	var reach: float = float(plan.reach) * float(plan.get("reach_factor", 1.0))
	arena.play_sfx("staff_swing", 0.8)
	if plan.has("sweep"):
		arena.sweep = {"tool": tool, "plan": plan, "direction": direction, "phase": float(plan.release_ratio),
			"total": tool_attack_seconds("area_attack", tool), "reach": reach, "struck": []}
		arena.last_tool_attack = {"skill": "area_attack", "tool": tool, "struck": [], "results": {}}
		tick_sweep(0.0)
		return
	var half: float = deg_to_rad(float(plan.half_angle_degrees))
	var struck: Array = []
	for id in arena.enemies.keys():
		var delta: Vector3 = arena.enemies[id].body.position - arena.player.position
		delta.y = 0.0
		if delta.length() <= reach + 0.3 * float(arena.enemies[id].size) and absf(direction.signed_angle_to(delta, Vector3.UP)) <= half and arena.map.sees(arena.player.position, arena.enemies[id].body.position):
			struck.append(id)
	var results := {}
	var damage := tool_hit_damage("area_attack", plan)
	for id in struck:
		if arena.enemies.has(id):
			results[id] = tool_strike(id, tool, damage, plan, "area_attack")
	if results.values().has("hit") or results.values().has("crit"):
		tool_hit_sound(tool)
		if tool == "bolt_cutter" and arena.gear_total("rule:chain_cut") > 0:
			# One drag per swing: from the nearest enemy it cut to the nearest one it did not.
			var first := ""
			for id in struck:
				if results.get(id, "miss") != "miss" and arena.enemies.has(id) and (first == "" or arena.player.position.distance_to(arena.enemies[id].body.position) < arena.player.position.distance_to(arena.enemies[first].body.position)):
					first = id
			arena.chain_cut(first, damage, struck, "area_attack:bolt_cutter")
	arena.spawn_vfx().fan_slash(arena.player.position, direction, reach, rad_to_deg(half) * 2.0, arena.map.ground_y(arena.player.position))
	arena.last_tool_attack = {"skill": "area_attack", "tool": tool, "struck": struck, "results": results}

func sweep_angle(keys: Array, phase: float) -> float:
	# Staff-tip bearing of the playing clip (degrees, right positive), sampled from the v32 motion.
	if phase <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if phase <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(float(a[1]), float(b[1]), (phase - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.000001))
	return float(keys[-1][1])

func tick_sweep(dt: float) -> void:
	if arena.sweep.is_empty():
		return
	var keys: Array = arena.sweep.plan.sweep
	var before := sweep_angle(keys, float(arena.sweep.phase))
	arena.sweep.phase = float(arena.sweep.phase) + dt / maxf(float(arena.sweep.total), 0.000001)
	var now := sweep_angle(keys, float(arena.sweep.phase))
	var facing: Vector3 = arena.sweep.direction
	var right: Vector3 = facing.cross(Vector3.UP)
	var damage := tool_hit_damage("area_attack", arena.sweep.plan)
	var cut := false
	for id in arena.enemies.keys():
		if id in arena.sweep.struck:
			continue
		var delta: Vector3 = arena.enemies[id].body.position - arena.player.position
		delta.y = 0.0
		if delta.length() > float(arena.sweep.reach) + 0.3 * float(arena.enemies[id].size):
			continue
		var bearing := rad_to_deg(atan2(delta.dot(right), delta.dot(facing)))
		var passed := false
		for turn in range(-2, 3):
			var angle := bearing + 360.0 * turn
			if angle >= now - 0.001 and angle <= before + 0.001:
				passed = true
		if passed and arena.map.sees(arena.player.position, arena.enemies[id].body.position):
			arena.sweep.struck.append(id)
			var result := tool_strike(id, arena.sweep.tool, damage, arena.sweep.plan, "area_attack")
			arena.last_tool_attack.struck.append(id)
			arena.last_tool_attack.results[id] = result
			cut = cut or result != "miss"
	if cut:
		tool_hit_sound(arena.sweep.tool)
	if float(arena.sweep.phase) >= float(keys[-1][0]):
		arena.sweep.clear()

func start_channel(target: Vector3, direction: Vector3) -> void:
	# Rotary cannon (03 §3, firearm III): after the spin-up cast it fires for as long as its key is
	# held, turning after the cursor, while she stands still. Mana drains by the second.
	var visual: Node3D = arena.gatling_assembly
	arena.gatling_assembly = null
	if not is_instance_valid(visual):
		visual = Arena.GatlingGun.new()
		arena.world.add_child(visual)
		visual.initialize(arena)
	visual.ready_to_fire()
	arena.moving = false
	arena.move_marker.visible = false
	var slot: String = channel_slot("gatling")
	arena.channel = {"skill": "gatling", "slot": slot, "visual": visual, "fire_left": 0.0, "shots": 0,
		"aim": target, "direction": direction, "focus": "", "focus_hits": 0}
	arena.probe.channel_begin("gatling")

func channel_held() -> bool:
	return not arena.channel.is_empty() and arena.hold.get("slot") == arena.channel.slot and arena.state.bindings.get(arena.channel.slot) == arena.channel.skill

func stop_channel(exit: bool = false) -> void:
	# exit: the focus attack lets go with its exit motion (a short recovery); interrupts, death
	# and field clear end it without one.
	if arena.channel.is_empty():
		return
	if arena.channel.skill == "focus_attack":
		arena.player_visual.end_focus_loop()
		if exit and arena.hp > 0 and not arena.field_cleared():
			var seconds: float = tool_speed(float(arena.rules.skills.focus_attack.exit_seconds))
			arena.action_time = maxf(arena.action_time, seconds)
			arena.player_visual.begin_tool_motion("focus_exit", arena.channel.tool, seconds, 1.0)
	elif is_instance_valid(arena.channel.visual):
		arena.channel.visual.dismiss()
	arena.channel.clear()

func tick_channel(dt: float) -> void:
	if arena.channel.is_empty():
		return
	if not channel_held():
		stop_channel(true)
		return
	if arena.channel.skill == "focus_attack":
		tick_tool_channel(dt)
		return
	var skill: Dictionary = arena.rules.skills.gatling
	var cost: float = float(skill.channel_mana_per_second) * dt
	if arena.state.mana + arena.rules.EPS < cost:
		stop_channel()
		arena.show_message("마나 부족 · 사격 중지")
		return
	arena.state.mana = maxf(0.0, arena.state.mana - cost)
	arena.probe.record([{"type": "tool_upkeep", "tool": "gatling", "amount": cost}])
	arena.probe.channel_time("gatling", dt, cost)
	# The stream follows the cursor: an enemy under it, else the floor point.
	var cursor := arena.field_cursor()
	if cursor.get("enemy_id") != null and arena.enemies.has(cursor.enemy_id):
		arena.channel.aim = arena.enemies[cursor.enemy_id].body.position
	elif cursor.get("ground") != null:
		arena.channel.aim = arena.map.grounded(arena.point(cursor.ground))
	var flat: Vector3 = arena.channel.aim - arena.player.position
	flat.y = 0.0
	if flat.length() > 0.05:
		arena.channel.direction = flat.normalized()
	var direction: Vector3 = arena.channel.direction
	arena.player_model.look_at(arena.player.position + direction)
	if is_instance_valid(arena.channel.visual):
		arena.channel.visual.aim_at(arena.player.position + direction * float(skill.range) + Vector3.UP)
	arena.channel.fire_left = float(arena.channel.fire_left) - dt
	while not arena.channel.is_empty() and arena.channel.fire_left <= 0:
		arena.fire_gatling(direction)
		arena.channel.fire_left = float(arena.channel.fire_left) + arena.gatling_interval()
