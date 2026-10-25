extends RefCounted
## A5 measurement: how often and how long mana leaves only the basic attack.
## A "skill gap" is combat time with no tool running and no mana-costing skill affordable.
var combat_seconds = 0.0
var gap_seconds = 0.0
var gap_count = 0
var longest_gap = 0.0
var current_gap = 0.0
var unaffordable_seconds: Dictionary = {}
var counts = {"mana_failures": 0, "fallback_attacks": 0, "tool_auto_releases": 0, "tool_manual_releases": 0, "deaths": 0, "kills": 0, "debug_mana_edits": 0}
var casts: Dictionary = {}

func tick(dt: float, gap: bool, unaffordable: Array) -> void:
	combat_seconds += dt
	for id in unaffordable:
		unaffordable_seconds[id] = unaffordable_seconds.get(id, 0.0) + dt
	if gap:
		if current_gap == 0:
			gap_count += 1
		current_gap += dt
		gap_seconds += dt
		longest_gap = maxf(longest_gap, current_gap)
	else:
		current_gap = 0.0

func record(events: Array) -> void:
	for event in events:
		match event.type:
			"cast": casts[event.skill] = casts.get(event.skill, 0) + 1
			"cast_failed":
				if event.reason == "insufficient_mana":
					counts.mana_failures += 1
			"basic_attack_fallback": counts.fallback_attacks += 1
			"tool_released":
				counts["tool_auto_releases" if event.reason == "mana_empty" else "tool_manual_releases"] += 1

func gap_share() -> float:
	return gap_seconds / combat_seconds if combat_seconds > 0 else 0.0

func to_dict() -> Dictionary:
	var rounded = {}
	for id in unaffordable_seconds:
		rounded[id] = snappedf(unaffordable_seconds[id], 0.01)
	return {"combat_seconds": snappedf(combat_seconds, 0.01), "skill_gap": {"seconds": snappedf(gap_seconds, 0.01),
		"share": snappedf(gap_share(), 0.001), "count": gap_count, "longest_seconds": snappedf(longest_gap, 0.01)},
		"unaffordable_seconds": rounded, "counts": counts, "casts": casts}
