extends RefCounted
## C1/C2 trial build: a trial character level hands out stat and skill points, the character (C)
## and skill tree (S) windows spend them, and both pools reset for free (07 §1, 03 §1.1).
## The build writes into the same config fields the combat code already reads.
const STATS = ["power", "dexterity", "vitality", "will"]
const STAT_NAMES = {"power": "위력", "dexterity": "기교", "vitality": "활력", "will": "의지"}
const NODE_NAMES = {"base": "노드 없음", "A": "A 자폭 특화", "B": "B 지속공격 특화"}

var arena: Node
var rules: Dictionary
var level: int
var stats: Dictionary = {}
var skills: Dictionary = {}
var passives: Dictionary = {}
var node: String
var base_hp: float
var base_mana: float

func _init(owner: Node) -> void:
	arena = owner
	var config: Dictionary = arena.config
	rules = config.build
	level = int(rules.level)
	for id in STATS:
		stats[id] = 0
	for id in skill_ids():
		skills[id] = int(config[id + "_level"])
	for id in config.passives:
		passives[id] = int(config.passive_levels[id])
	node = config.automaton_node
	base_hp = float(config.max_hp)
	base_mana = float(config.max_mana)

func skill_ids() -> Array:
	var result: Array = []
	for tree in rules.skill_tree:
		for entry in tree.entries:
			if entry.kind == "skill":
				result.append(entry.id)
	return result

func stat_points() -> int:
	var spent := 0
	for id in STATS:
		spent += stats[id]
	return level * int(rules.stat_points_per_level) - spent

func skill_points() -> int:
	# Skills start at Lv1 for free; every level above it, every passive level and a node cost points.
	var spent := 0
	for id in skills:
		spent += skills[id] - 1
	for id in passives:
		spent += passives[id]
	if node != "base":
		spent += int(rules.node_cost)
	return level * int(rules.skill_points_per_level) - spent

func set_level(value: int) -> void:
	arena.split_build_log()
	level = clampi(value, 1, int(rules.max_level))
	# A lower trial level refunds whichever pool no longer fits.
	if stat_points() < 0:
		reset_stats()
	if skill_points() < 0:
		reset_skills()
	apply()

func step_level(delta: int) -> bool:
	if level + delta < 1 or level + delta > int(rules.max_level):
		return false
	set_level(level + delta)
	return true

func change_stat(id: String, delta: int) -> bool:
	var value: int = stats[id] + delta
	if value < 0 or (delta > 0 and stat_points() < delta):
		return false
	arena.split_build_log()
	stats[id] = value
	apply()
	return true

func change_skill(id: String, delta: int) -> bool:
	var pool: Dictionary = skills if skills.has(id) else passives
	var floor_level: int = 1 if pool == skills else 0
	var value: int = pool[id] + delta
	if value < floor_level or value > int(rules.skill_max_level) or (delta > 0 and skill_points() < delta):
		return false
	arena.split_build_log()
	pool[id] = value
	apply()
	return true

func set_node(value: String) -> bool:
	# A and B exclude each other; switching between them costs nothing extra.
	var cost: int = int(rules.node_cost)
	var extra: int = (cost if value != "base" else 0) - (cost if node != "base" else 0)
	if extra > 0 and skill_points() < extra:
		return false
	arena.split_build_log()
	node = value
	apply()
	return true

func stat(id: String) -> float:
	# Allocated points only; items carry no base stat options in this trial.
	return float(stats[id])

func cast_speed_parts() -> Dictionary:
	# Gear FCR and the production efficiency passive add up before the soft cap (04 §4.1).
	var passive: float = float(arena.config.passives.production_efficiency.cast_speed_per_level) * passives.production_efficiency
	return {"gear": arena.gear_total("cast_speed"), "passive": passive}

func reset_stats() -> void:
	arena.split_build_log()
	for id in STATS:
		stats[id] = 0
	apply()

func reset_skills() -> void:
	arena.split_build_log()
	for id in skills:
		skills[id] = 1
	for id in passives:
		passives[id] = 0
	node = "base"
	apply()

func apply() -> void:
	var config: Dictionary = arena.config
	var effects: Dictionary = rules.stat_effects
	config.dexterity = stat("dexterity")
	var cast_speed: Dictionary = cast_speed_parts()
	config.cast_speed_score = cast_speed.gear + cast_speed.passive
	config.attack_speed_score = arena.gear_total("attack_speed")
	config.hit_recovery_score = arena.gear_total("hit_recovery")
	for id in skills:
		# Blueprints add skill levels on top of the points, past Lv10 if need be.
		config[id + "_level"] = float(skills[id]) + arena.gear_total("skill:" + id)
	for id in passives:
		config.passive_levels[id] = float(passives[id])
	config.automaton_node = node
	arena.sync_automaton_cost()
	arena.sync_tool_upkeep()
	# Vitality and will move the maximums; current HP and mana follow a rise and are clipped by a fall.
	var hp_max: float = base_hp + float(effects.vitality) * stat("vitality") + arena.gear_total("life")
	arena.hp = clampf(arena.hp + hp_max - float(config.max_hp), 0.0, hp_max) if arena.hp > 0 else arena.hp
	config.max_hp = hp_max
	var mana_max: float = base_mana + float(effects.will) * stat("will") + arena.gear_total("mana")
	arena.state.mana = clampf(arena.state.mana + mana_max - float(arena.state.max_mana), 0.0, mana_max)
	arena.state.max_mana = mana_max
	config.max_mana = mana_max

func power_factor() -> float:
	# Power raises the witch's own direct hits only: never bleed (07 §2.3) and never summons,
	# whose strength comes from their skill level (07 §2.1).
	return 1.0 + float(rules.stat_effects.power) * stat("power")

func snapshot() -> Dictionary:
	return {"level": level, "stats": stats.duplicate(), "skills": skills.duplicate(), "passives": passives.duplicate(), "node": node, "equipment": arena.equipment_summary(),
		"stat_points_left": stat_points(), "skill_points_left": skill_points()}
