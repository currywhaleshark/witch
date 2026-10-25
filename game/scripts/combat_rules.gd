extends RefCounted
## Engine port of combat_rules/core.py. Spatial checks are mandatory.
## Floating point resources snap within EPS of zero; no implicit regeneration.
const SLOTS = ["lmb", "rmb", "q", "w", "e", "r"]
const EPS = 0.00000001
var skills: Dictionary = {}
var basic_id: String
var policy: Dictionary

func _init(catalog: Dictionary) -> void:
	policy = catalog.policy
	assert(policy.non_mana_failure == "reject_without_moving")
	assert(policy.manual_tool_release == "free_before_checks")
	assert(policy.zero_mana_cast_order == "cast_then_release")
	assert(policy.failure_order.size() == 4)
	for key in ["target", "spatial", "cooldown", "mana"]:
		assert(policy.failure_order.count(key) == 1)
	for original in catalog.skills:
		var skill: Dictionary = original.duplicate(true)
		assert(not skills.has(skill.id))
		for key in ["mana_cost", "cooldown_seconds", "upkeep_per_second"]:
			skill[key] = float(skill[key])
			assert(is_finite(skill[key]) and skill[key] >= 0)
		assert(skill.kind in ["aim", "enemy", "ground", "mobile_summon", "self", "tool"])
		assert((skill.kind == "tool") == (skill.upkeep_per_second > 0))
		skills[skill.id] = skill
	basic_id = catalog.basic_attack_id
	# Basic attack pacing comes from attack speed outside this module, never a cooldown.
	assert(skills[basic_id].kind == "aim" and skills[basic_id].mana_cost == 0 and skills[basic_id].cooldown_seconds == 0)

func initial_state(maximum: float, mana = null) -> Dictionary:
	var current: float = maximum if mana == null else float(mana)
	assert(current >= 0 and current <= maximum)
	return {"mana": current, "max_mana": maximum, "active_tool": null,
		"bindings": {"lmb": basic_id, "rmb": null, "q": null, "w": null, "e": null, "r": null}, "cooldowns": {}}

func bind(state: Dictionary, slot: String, skill_id) -> Dictionary:
	assert(slot in SLOTS and (skill_id == null or skills.has(skill_id)))
	assert(slot != "lmb" or skill_id != null)
	var result = state.duplicate(true)
	result.bindings[slot] = skill_id
	return result

func target(skill: Dictionary, cursor: Dictionary):
	if skill.kind in ["self", "tool"]:
		return {"origin": "player"}
	if skill.kind == "ground":
		return {"origin": "cursor_ground", "position": cursor.ground} if cursor.get("ground") != null else null
	if cursor.get("enemy_id") != null:
		return {"origin": "player_adjacent" if skill.kind == "mobile_summon" else "player", "target_enemy": cursor.enemy_id}
	if cursor.get("ground") != null and skill.kind in ["aim", "mobile_summon"]:
		if skill.kind == "mobile_summon":
			return {"origin": "player_adjacent", "target_enemy": null}
		return {"origin": "player", "position": cursor.ground}
	return null

func failure(state: Dictionary, skill: Dictionary, cursor: Dictionary, spatial: Callable):
	for check in policy.failure_order:
		if check == "target" and target(skill, cursor) == null:
			return "invalid_target"
		if check == "spatial" and skill.kind not in ["self", "tool"]:
			var reason = spatial.call(skill, cursor)
			assert(reason == null or reason in ["out_of_range", "invalid_ground"])
			if reason != null:
				return reason
		if check == "cooldown" and state.cooldowns.get(skill.id, 0.0) > EPS:
			return "cooldown"
		if check == "mana" and state.mana + EPS < skill.mana_cost:
			return "insufficient_mana"
	return null

func release_at_zero(state: Dictionary, events: Array) -> void:
	if state.mana <= EPS:
		state.mana = 0.0
		if state.active_tool != null:
			events.append({"type": "tool_released", "tool": state.active_tool, "reason": "mana_empty"})
			state.active_tool = null

func press(state: Dictionary, slot: String, cursor: Dictionary, spatial: Callable, shift: bool = false) -> Dictionary:
	assert(spatial.is_valid())
	if slot not in SLOTS:
		return {"state": state, "events": [{"type": "input_ignored", "input": slot, "reason": "outside_active_slots"}]}
	if slot == "lmb" and not shift and cursor.get("enemy_id") == null:
		return {"state": state, "events": [{"type": "move_requested", "position": cursor.ground}] if cursor.get("ground") != null else [{"type": "input_failed", "reason": "invalid_ground"}]}
	var skill_id = state.bindings[slot]
	if skill_id == null:
		return {"state": state, "events": [{"type": "input_failed", "slot": slot, "reason": "empty_slot"}]}
	var skill: Dictionary = skills[skill_id]
	var next = state.duplicate(true)
	if skill.kind == "tool" and state.active_tool == skill.id:
		next.active_tool = null
		return {"state": next, "events": [{"type": "tool_released", "tool": skill.id, "reason": "manual"}]}
	var events: Array = []
	var reason = failure(state, skill, cursor, spatial)
	if reason == "insufficient_mana" and slot == "lmb":
		events.append({"type": "basic_attack_fallback", "requested_skill": skill.id, "skill": basic_id, "reason": reason})
		skill = skills[basic_id]
		reason = failure(state, skill, cursor, spatial)
	if reason != null:
		events.append({"type": "cast_failed", "slot": slot, "skill": skill.id, "reason": reason})
		return {"state": state, "events": events}
	next.mana -= skill.mana_cost
	if skill.mana_cost > 0:
		events.append({"type": "mana_spent", "amount": skill.mana_cost})
	if skill.kind == "tool":
		next.active_tool = skill.id
		events.append({"type": "tool_changed", "previous": state.active_tool, "tool": skill.id})
	var cast = {"type": "cast", "slot": slot, "skill": skill.id, "active_tool": next.active_tool}
	cast.merge(target(skill, cursor))
	events.append(cast)
	if skill.cooldown_seconds > 0:
		next.cooldowns[skill.id] = skill.cooldown_seconds
	release_at_zero(next, events)
	return {"state": next, "events": events}

func advance(state: Dictionary, seconds: float) -> Dictionary:
	assert(is_finite(seconds) and seconds >= 0)
	var next = state.duplicate(true)
	var events: Array = []
	for id in state.cooldowns:
		var remaining: float = state.cooldowns[id] - seconds
		if remaining <= EPS:
			next.cooldowns.erase(id)
		else:
			next.cooldowns[id] = remaining
	if state.active_tool != null:
		var cost: float = minf(state.mana, skills[state.active_tool].upkeep_per_second * seconds)
		next.mana -= cost
		if cost > 0:
			events.append({"type": "tool_upkeep", "tool": state.active_tool, "amount": cost})
		release_at_zero(next, events)
	return {"state": next, "events": events}

func restore_mana(state: Dictionary, amount: float) -> Dictionary:
	assert(is_finite(amount) and amount >= 0)
	var next = state.duplicate(true)
	var recovered = minf(amount, state.max_mana - state.mana)
	next.mana += recovered
	return {"state": next, "events": [{"type": "mana_restored", "amount": recovered}]}
