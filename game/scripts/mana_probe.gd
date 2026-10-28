extends RefCounted
## A5 measurement: how often and how long mana leaves only the basic attack.
## A "skill gap" is combat time with no tool running and no mana-costing skill affordable.
var combat_seconds = 0.0
var gap_seconds = 0.0
var gap_count = 0
var longest_gap = 0.0
var current_gap = 0.0
var unaffordable_seconds: Dictionary = {}
var counts = {"mana_failures": 0, "fallback_attacks": 0, "tool_auto_releases": 0, "tool_manual_releases": 0, "deaths": 0, "kills": 0, "debug_mana_edits": 0, "hits": 0, "misses": 0, "crits": 0, "stuns": 0, "blocks": 0, "allies_lost": 0, "bleeds_applied": 0, "bleed_ticks": 0}
var casts: Dictionary = {}
var potions: Dictionary = {}
# Stage B breakdowns: direct damage dealt per source, and what each enemy grade did and suffered.
var sources: Dictionary = {}
var grades: Dictionary = {}

func strike(source: String, result: String, dealt: float) -> void:
	var row: Dictionary = sources.get_or_add(source, {"hits": 0, "misses": 0, "crits": 0, "damage": 0.0})
	match result:
		"miss":
			row.misses += 1
			counts.misses += 1
		"crit":
			row.hits += 1
			row.crits += 1
			counts.hits += 1
			counts.crits += 1
		_:
			row.hits += 1
			counts.hits += 1
	row.damage += dealt

func bleed(dealt: float) -> void:
	# Bleed ticks count as damage under their own source, never as hits or misses.
	var row: Dictionary = sources.get_or_add("bleed", {"hits": 0, "misses": 0, "crits": 0, "damage": 0.0})
	row.damage += dealt
	counts.bleed_ticks += 1

func grade(id: String) -> Dictionary:
	return grades.get_or_add(id, {"kills": 0, "hits_on_witch": 0, "damage_to_witch": 0.0, "stuns": 0, "blocked": 0,
		"hits_on_allies": 0, "damage_to_allies": 0.0, "allies_destroyed": 0})

func ally_hit(by: String, taken: float, destroyed: bool) -> void:
	var row: Dictionary = grade(by)
	row.hits_on_allies += 1
	row.damage_to_allies += taken
	if destroyed:
		row.allies_destroyed += 1
		counts.allies_lost += 1

func witch_hit(by: String, taken: float, stunned: bool, blocked: bool) -> void:
	var row: Dictionary = grade(by)
	if blocked:
		row.blocked += 1
		counts.blocks += 1
		return
	row.hits_on_witch += 1
	row.damage_to_witch += taken
	if stunned:
		row.stuns += 1
		counts.stuns += 1

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
	var by_source = sources.duplicate(true)
	for id in by_source:
		by_source[id].damage = snappedf(by_source[id].damage, 0.1)
	var by_grade = grades.duplicate(true)
	for id in by_grade:
		by_grade[id].damage_to_witch = snappedf(by_grade[id].damage_to_witch, 0.1)
		by_grade[id].damage_to_allies = snappedf(by_grade[id].damage_to_allies, 0.1)
	return {"combat_seconds": snappedf(combat_seconds, 0.01), "skill_gap": {"seconds": snappedf(gap_seconds, 0.01),
		"share": snappedf(gap_share(), 0.001), "count": gap_count, "longest_seconds": snappedf(longest_gap, 0.01)},
		"unaffordable_seconds": rounded, "counts": counts, "casts": casts, "potions": potions,
		"by_source": by_source, "by_grade": by_grade}
