extends RefCounted
## Drive tree devices (03 §6): guillotines and their saw/lock nodes, the hydraulic press, the compound
## executor, restraint winches, marks and holds, and the exoskeleton passive with its visual. Device
## state (devices, winches, exo_visual, ...) stays on the arena. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func device_cursor(bound, cursor: Dictionary) -> Dictionary:
	# An execution device cast with the cursor on an enemy is set under that enemy, not on the
	# floor point the cursor ray reaches behind a tall model; while she walks into range the spot
	# keeps following it ("follow").
	if bound == null or not arena.rules.skills[bound].get("over_enemies", false) or cursor.get("enemy_id") == null or not arena.enemies.has(cursor.enemy_id):
		return cursor
	var aimed := cursor.duplicate(true)
	var at: Vector3 = arena.enemies[cursor.enemy_id].body.position
	aimed.ground = [at.x, 0, at.z]
	aimed.follow = cursor.enemy_id
	return aimed

func device_plan(skill_id: String) -> Dictionary:
	# A device's timings and numbers: its chosen node's when it has nodes.
	var skill: Dictionary = arena.rules.skills[skill_id]
	if skill_id == "restraint_winch":
		var plan: Dictionary = skill.duplicate()
		plan.merge(skill.nodes[arena.config.restraint_winch_node], true)
		# Hooks reel home once the pull is done (or soon after they bite, when they only bind).
		plan.release_at = float(plan.fly_seconds) + (float(plan.pull_seconds) if plan.pull else 0.35)
		plan.end_at = float(plan.release_at) + 0.25
		return plan
	return skill.nodes[arena.config[skill_id + "_node"]] if skill.has("nodes") else skill

func device_model(skill_id: String) -> String:
	if skill_id == "guillotine":
		return {"base": "guillotine", "saw": "guillotine_saw", "lock": "guillotine_lock"}[arena.config.guillotine_node]
	return skill_id

func begin_device_visual(skill_id: String, target: Vector3, direction: Vector3) -> Node3D:
	# Executions assemble on the spot they will strike; the winch sets down just in front of her.
	var plan := device_plan(skill_id)
	var visual = Arena.DriveDevice.new()
	visual.configure(device_model(skill_id), plan, float(plan.get("hit_radius", plan.get("trap_radius", 0.5))))
	arena.world.add_child(visual)
	if skill_id == "restraint_winch":
		visual.position = arena.map.grounded(arena.player.position + direction * float(plan.offset))
	else:
		visual.position = arena.map.grounded(target)
	visual.look_at(visual.global_position + direction, Vector3.UP)
	visual.initialize(arena)
	return visual

func place_device(skill_id: String, target: Vector3, direction: Vector3) -> void:
	var visual = arena.device_assembly
	arena.device_assembly = null
	if not is_instance_valid(visual):
		visual = begin_device_visual(skill_id, target, direction)
	visual.activate()
	var entry := {"skill": skill_id, "model": device_model(skill_id), "visual": visual, "time": 0.0, "center": visual.global_position,
		"plan": device_plan(skill_id), "fired": {}, "ticks": 0, "locked": "", "caged": [], "marked": []}
	arena.devices.append(entry)
	arena.last_device = entry
	arena.play_sfx("summon_assemble", 1.6)

func fire_once(entry: Dictionary, key: String, at_time: float) -> bool:
	if entry.fired.has(key) or float(entry.time) < at_time:
		return false
	entry.fired[key] = true
	return true

func tick_devices(dt: float) -> void:
	# Each device runs its mechanism; the hits land on the frames the mechanism reaches them.
	for entry in arena.devices.duplicate():
		entry.time += dt
		var t: float = entry.time
		var plan: Dictionary = entry.plan
		match entry.model:
			"guillotine":
				if fire_once(entry, "drop", float(plan.drop_at) + float(plan.drop_seconds)):
					device_hits(entry, float(plan.hit_radius), float(plan.damage), "guillotine")
					device_thud(entry, 0.6, "bolt_cutter_cut")
			"guillotine_lock":
				if fire_once(entry, "lock", 0.0):
					entry.locked = lock_target(entry)
					catch_marks(entry, [entry.locked])
				if fire_once(entry, "drop", float(plan.drop_at) + float(plan.drop_seconds)):
					device_hits(entry, float(plan.hit_radius), float(plan.damage), "guillotine", {entry.locked: float(plan.lock_bonus)})
					release_hold([entry.locked])
					device_thud(entry, 0.6, "bolt_cutter_cut")
			"guillotine_saw":
				while entry.ticks < int(plan.ticks) and t >= float(plan.tick_from) + float(plan.tick_every) * entry.ticks:
					entry.ticks += 1
					if not device_hits(entry, float(plan.hit_radius), float(plan.tick_damage), "guillotine").is_empty():
						arena.play_sfx("chainsaw_cut", 1.05)
			"hydraulic_press":
				if fire_once(entry, "press", float(plan.press_at) + float(plan.press_seconds)):
					for id in device_hits(entry, float(plan.hit_radius), float(plan.damage), "hydraulic_press"):
						restrain(id, "stun", press_stun_seconds(float(plan.stun_seconds)))
					arena.spawn_vfx().shockwave(entry.center, float(plan.hit_radius), arena.map.ground_y(entry.center))
					device_thud(entry, 0.5, "boss_slam")
			"compound_executor":
				if fire_once(entry, "cage", float(plan.gate_at) + float(plan.gate_seconds) * 0.5):
					entry.caged = cage_enemies(entry)
					catch_marks(entry, entry.caged)
				if fire_once(entry, "press", float(plan.press_at) + float(plan.press_seconds)):
					for id in device_hits(entry, float(plan.trap_radius), float(plan.press_damage) * executor_synergy("hydraulic_press"), "compound_executor"):
						restrain(id, "stun", press_stun_seconds(float(plan.stun_seconds)))
					device_thud(entry, 0.5, "boss_slam")
				while entry.ticks < int(plan.saw_ticks) and t >= float(plan.saw_from) + float(plan.saw_every) * entry.ticks:
					entry.ticks += 1
					var sawn: Array = device_hits(entry, float(plan.trap_radius), float(plan.saw_damage) * executor_synergy("guillotine"), "compound_executor")
					if entry.ticks == 1:
						for id in sawn:
							arena.add_bleed(id)
					if not sawn.is_empty():
						arena.play_sfx("chainsaw_cut", 1.05)
				if fire_once(entry, "open", float(plan.end_at)):
					release_hold(entry.caged)
		entry.visual.work(t)
		if entry.visual.finished(t):
			release_hold(entry.caged + [entry.locked])
			entry.visual.queue_free()
			arena.devices.erase(entry)

func device_hits(entry: Dictionary, radius: float, amount: float, source: String, bonus: Dictionary = {}) -> Array:
	# Everyone under the mechanism, plus whoever it holds, takes the hit with the execution bonus.
	var struck: Array = []
	for id in arena.enemies.keys():
		var gap: Vector3 = arena.enemies[id].body.position - entry.center
		gap.y = 0.0
		if gap.length() <= radius + 0.2 * float(arena.enemies[id].size) or id in entry.caged or id == entry.locked:
			struck.append(id)
	for id in struck:
		if arena.enemies.has(id):
			var hit_amount: float = amount * execute_factor(id, id in entry.get("marked", [])) * float(bonus.get(id, 1.0))
			if source == "guillotine" and arena.gear_total("rule:guillotine_execute") > 0:
				hit_amount *= hinge_execution(id)
				if not arena.enemies.has(id):
					continue
			arena.strike(id, hit_amount, false, "witch", source)
	return struck.filter(func(id): return arena.enemies.has(id))

func hinge_execution(id: String) -> float:
	# Unique 녹슨 단두대 경첩: a falling blade beheads a weakened ordinary or champion enemy outright;
	# elites and bosses that low only take a doubled cut. Returns the factor for the normal hit.
	var rule: Dictionary = arena.items.data.rule_values
	var enemy: Dictionary = arena.enemies[id]
	if float(enemy.hp) > float(enemy.max_hp) * float(rule.execute_hp_ratio):
		return 1.0
	if enemy.grade not in rule.execute_grades or arena.config.enemy_types[enemy.kind].has("boss"):
		return float(rule.execute_tough_factor)
	var at: Vector3 = enemy.body.position
	var size: float = float(enemy.size)
	arena.probe.strike("guillotine", "crit", arena.damage_enemy(id, float(enemy.hp) + 1.0))
	arena.spawn_vfx().impact(at + Vector3.UP * 0.85 * size, Vector3.UP, "guillotine", true, arena.map.ground_y(at))
	arena.play_sfx("crit_hit", 0.55)
	return 0.0

func device_thud(entry: Dictionary, shake: float, cue: String) -> void:
	arena.shake_time = maxf(arena.shake_time, 0.12 * shake)
	arena.play_sfx(cue, 0.7)

func execute_factor(id: String, marked: bool = false) -> float:
	# Executions (03 §4) hit harder the more HP the enemy has lost, and once more if a tool has
	# marked it (slow, shred or bleed: one is enough, since switching tools is costly) or the winch
	# holds it. The devices' own stun and bind never count, so the bonus rewards setting it up first.
	# marked: a caged or clamped enemy keeps the mark it had when it was caught.
	var enemy: Dictionary = arena.enemies[id]
	var plan: Dictionary = arena.config.execution
	var lost: float = clampf(1.0 - float(enemy.hp) / maxf(1.0, float(enemy.max_hp)), 0.0, 1.0)
	return 1.0 + float(plan.low_hp_bonus) * lost + (float(plan.debuff_bonus) if marked or tool_marked(enemy) else 0.0)

func tool_marked(enemy: Dictionary) -> bool:
	for key in arena.config.execution.tool_debuffs:
		if key == "bleed" and not enemy.bleeds.is_empty():
			return true
		if key != "bleed" and float(enemy.get(key, 0.0)) > 0:
			return true
	return false

func catch_marks(entry: Dictionary, ids: Array) -> void:
	# Remember who carried a tool mark when the device caught them, for the rest of its run.
	for id in ids:
		if arena.enemies.has(id) and tool_marked(arena.enemies[id]) and id not in entry.marked:
			entry.marked.append(id)

func restrain(id: String, kind: String, seconds: float) -> bool:
	# Stun (press) or bind (winch, cage, lock): it stops, loses its windup and its charge.
	# Bosses keep their patterns and are never held.
	if not arena.enemies.has(id):
		return false
	var enemy: Dictionary = arena.enemies[id]
	if arena.config.enemy_types[enemy.kind].has("boss"):
		return false
	# Stun and bind options lengthen every hold she sets (devices release their cages themselves).
	seconds *= 1.0 + arena.gear_total("control_pct") / 100.0
	enemy[kind] = maxf(float(enemy.get(kind, 0.0)), seconds)
	enemy.charging = 0.0
	arena.interrupt_attack(enemy)
	return true

func release_hold(ids: Array) -> void:
	for id in ids:
		if arena.enemies.has(id):
			arena.enemies[id].bound = 0.0

func haul(id: String, to: Vector3, seconds: float, share: float = 1.0) -> void:
	# Drags the enemy along the floor toward a point (the knockback slide, pointed the other way).
	var enemy: Dictionary = arena.enemies[id]
	var gap: Vector3 = to - enemy.body.position
	gap.y = 0.0
	var distance: float = gap.length() * share
	if distance < 0.05:
		return
	enemy.knockback_dir = gap.normalized()
	enemy.knockback_left = distance
	enemy.knockback_speed = distance / maxf(0.05, seconds)

func press_stun_seconds(base: float) -> float:
	return base + float(arena.rules.skills.hydraulic_press.stun_per_level) * (float(arena.config.hydraulic_press_level) - 1.0)

func executor_synergy(part: String) -> float:
	# The executor's press and saw grow with the press and guillotine the witch has studied.
	return 1.0 + float(arena.rules.skills.compound_executor.synergy_per_level) * maxf(0.0, float(arena.config[part + "_level"]) - 1.0)

func lock_target(entry: Dictionary) -> String:
	# The lock clamps close on the nearest enemy that can be held and drag it under the blade.
	var plan: Dictionary = entry.plan
	var best := ""
	var near := float(plan.lock_radius)
	for id in arena.enemies:
		var gap: Vector3 = arena.enemies[id].body.position - entry.center
		gap.y = 0.0
		if gap.length() <= near and not arena.config.enemy_types[arena.enemies[id].kind].has("boss"):
			near = gap.length()
			best = id
	if best != "":
		restrain(best, "bound", float(plan.drop_at) + float(plan.drop_seconds) + 0.2)
		haul(best, entry.center, float(plan.clamp_seconds))
	return best

func cage_enemies(entry: Dictionary) -> Array:
	# The gates shut on everyone inside; each is held near the middle until the gates reopen.
	var plan: Dictionary = entry.plan
	var caged: Array = []
	for id in arena.enemies:
		var gap: Vector3 = arena.enemies[id].body.position - entry.center
		gap.y = 0.0
		if gap.length() <= float(plan.trap_radius) and restrain(id, "bound", float(plan.end_at)):
			caged.append(id)
			if gap.length() > float(plan.hold_radius):
				haul(id, entry.center + gap.normalized() * float(plan.hold_radius), float(plan.gate_seconds))
	return caged

func fire_winch(event: Dictionary, direction: Vector3) -> void:
	# Restraint winch (03 drive II): hooks bite the target (and, with the multi-strand nodes, those
	# around it), then reel them in to her or bind them where they stand.
	var plan := device_plan("restraint_winch")
	var first = event.get("target_enemy")
	if first == null or not arena.enemies.has(first):
		arena.cancel_summon_assemblies("target_lost")
		return
	var targets: Array = [first]
	if int(plan.targets) > 1:
		var around_first: Vector3 = arena.enemies[first].body.position
		var others: Array = arena.enemies.keys().filter(func(id): return id != first and arena.enemies[id].body.position.distance_to(around_first) <= float(plan.gather_radius))
		others.sort_custom(func(a, b): return arena.enemies[a].body.position.distance_to(around_first) < arena.enemies[b].body.position.distance_to(around_first))
		targets.append_array(others.slice(0, int(plan.targets) - 1))
	var visual = arena.device_assembly
	arena.device_assembly = null
	if not is_instance_valid(visual):
		visual = begin_device_visual("restraint_winch", arena.cast_target(event), direction)
	visual.activate()
	var spots := {}
	for id in targets:
		spots[id] = arena.enemies[id].body.position
	var entry := {"visual": visual, "targets": targets, "spots": spots, "time": 0.0, "plan": plan, "fired": {}, "direction": direction}
	arena.winches.append(entry)
	arena.last_device = entry
	arena.play_sfx("staff_swing", 0.8)

func tick_winches(dt: float) -> void:
	for entry in arena.winches.duplicate():
		entry.time += dt
		var plan: Dictionary = entry.plan
		if fire_once(entry, "hook", float(plan.fly_seconds)):
			hook_targets(entry)
		var points: Array = []
		for id in entry.targets:
			if arena.enemies.has(id):
				entry.spots[id] = arena.enemies[id].body.position
			points.append(entry.spots[id])
		entry.visual.work(entry.time, points)
		if entry.visual.finished(entry.time):
			entry.visual.queue_free()
			arena.winches.erase(entry)

func hook_targets(entry: Dictionary) -> void:
	var plan: Dictionary = entry.plan
	var bind: float = float(plan.bind_seconds) + float(plan.bind_per_level) * (float(arena.config.restraint_winch_level) - 1.0)
	var count: int = entry.targets.size()
	var across: Vector3 = Vector3(entry.direction).cross(Vector3.UP)
	for i in count:
		var id: String = entry.targets[i]
		if not arena.enemies.has(id):
			continue
		arena.strike(id, float(plan.hook_damage), false, "witch", "restraint_winch")
		if not arena.enemies.has(id):
			continue
		var enemy: Dictionary = arena.enemies[id]
		if arena.config.enemy_types[enemy.kind].has("boss"):
			# A boss is too heavy to drag or tie down; the line only slows it.
			enemy.slow = maxf(float(enemy.slow), float(plan.boss_slow_seconds))
			continue
		if plan.pull:
			restrain(id, "bound", float(plan.pull_seconds) + bind)
			# The winch's bind is a setup for the executions, unlike the devices' own holds.
			enemy.winched = float(plan.pull_seconds) + bind
			var landing: Vector3 = arena.player.position + Vector3(entry.direction) * float(plan.stop_distance) + across * (i - (count - 1) / 2.0) * 0.8
			haul(id, landing, float(plan.pull_seconds), float(plan.heavy_pull) if enemy.heavy else 1.0)
		else:
			restrain(id, "bound", bind)
			enemy.winched = bind
	arena.play_sfx("staff_hit", 0.8)

func clear_devices() -> void:
	for entry in arena.devices:
		release_hold(entry.caged + [entry.locked])
		if is_instance_valid(entry.visual):
			entry.visual.dismiss()
	arena.devices.clear()
	for entry in arena.winches:
		if is_instance_valid(entry.visual):
			entry.visual.dismiss()
	arena.winches.clear()

func exo_level() -> float:
	return float(arena.config.exoskeleton_level)

func exo_plan() -> Dictionary:
	# The frame node (1 point, one of): guard doubles the defence and halves the damage bonus,
	# drive doubles the damage bonus, trims tool upkeep and halves the defence.
	return arena.rules.skills.exoskeleton.nodes[arena.config.exoskeleton_node]

func exo_active() -> bool:
	# A passive since 2026-11-05: once learned it is worn while a tool is transformed, never on
	# the bare staff, and costs nothing beyond the tool's own upkeep.
	return exo_level() >= 1 and not arena.state.is_empty() and arena.state.active_tool != null and arena.hp > 0

func exo_tool_bonus() -> float:
	var frame: Dictionary = arena.rules.skills.exoskeleton
	return (float(frame.tool_damage) + float(frame.tool_damage_per_level) * (exo_level() - 1.0)) * float(exo_plan().get("damage_factor", 1.0))

func exo_armor() -> float:
	var frame: Dictionary = arena.rules.skills.exoskeleton
	return (float(frame.armor_base) + float(frame.armor_per_level) * (exo_level() - 1.0)) * float(exo_plan().get("armor_factor", 1.0))

func exo_stun_cut() -> float:
	# Every fifth level cuts the witch's hit stagger once more while it is worn.
	var frame: Dictionary = arena.rules.skills.exoskeleton
	return float(frame.stun_cut) * floorf(exo_level() / float(frame.stun_cut_every)) * float(exo_plan().get("stun_cut_factor", 1.0))

func exo_upkeep_cut() -> float:
	return float(exo_plan().get("upkeep_cut", 0.0)) if exo_level() >= 1 else 0.0

func exo_tool_factor() -> float:
	return 1.0 + exo_tool_bonus() if exo_active() else 1.0

func exo_stun_factor() -> float:
	return maxf(0.2, 1.0 - exo_stun_cut()) if exo_active() else 1.0

func show_exo_visual() -> void:
	# The frame goes on with the tool and stays while it runs.
	if not arena.player_visual.loaded_ok:
		return
	if not is_instance_valid(arena.exo_visual):
		arena.exo_visual = Arena.ExoVisual.new()
		arena.player_visual.runtime.skeleton.add_child(arena.exo_visual)
		if not arena.exo_visual.initialize(arena.player_visual.runtime.skeleton):
			arena.exo_visual.queue_free()
			arena.exo_visual = null
			return
		arena.exo_visual.prepare()
		arena.exo_visual.wear(arena.player_visual)

func sync_exo_visual(dt: float) -> void:
	# After the body pose: the frame fades in with the tool, out when it is put away, and follows
	# the current motion.
	if exo_active() and not is_instance_valid(arena.exo_visual):
		show_exo_visual()
	if not is_instance_valid(arena.exo_visual):
		return
	var target := 1.0 if exo_active() else 0.0
	arena.exo_visual.set_shown(move_toward(arena.exo_visual.shown, target, dt / Arena.ExoVisual.FADE_SECONDS))
	var phase: float = arena.player_visual.clip_time / maxf(arena.player_visual.clip_length, 0.000001)
	arena.exo_visual.sync_pose_for_motion(Arena.ExoVisual.motion_for(arena.player_visual), phase)
	if arena.exo_visual.shown <= 0.0 and target <= 0.0:
		arena.exo_visual.take_off(arena.player_visual)
		arena.exo_visual.queue_free()
		arena.exo_visual = null
