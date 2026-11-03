extends SceneTree
## Attack, defence and damage spread (07 §2): the witch's hits scale with an attack range from her
## base and her medium, roll inside it (dexterity leans the roll high, never all the way), and crit
## at its top. Enemy hits vary ±15% and are cut by her armour against the attacker's level; summons
## vary only ±5% and grow with their own summon options. Base stats follow item level, not rarity.
## Writes no report.
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

func item(base: String, slot: String, level: int, rarity: String = "normal") -> Dictionary:
	return {"base": base, "slot": slot, "rarity": rarity, "level": level, "options": {}, "affixes": [], "name": arena.items.bases[base].name, "sockets": 0, "pieces": []}

func wear(items: Array) -> void:
	for slot in arena.equipment:
		arena.equipment[slot] = null
	for worn in items:
		arena.equipment[worn.slot] = worn
	arena.refresh_gear()

func hit_value(amount: float) -> float:
	# One staff strike on a tough dummy, no hit roll; what it lost.
	var dummy: Dictionary = arena.enemies.dummy
	dummy.hp = 99999.0
	arena.strike("dummy", amount, false, "witch", "staff")
	return 99999.0 - float(dummy.hp)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	await step(2)
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("dummy", Vector3(0, 0, 3))
	arena.enemies.dummy.max_hp = 99999.0
	arena.config.enemy_speed = 0
	var items = arena.items
	var build: Dictionary = arena.config.build

	# Base stats on items.
	check(items.base_stats(item("glass_orb", "medium", 1)) == {"attack_min": 2, "attack_max": 4}, "a level 1 glass medium gives attack 2~4")
	var late: Dictionary = items.base_stats(item("crystal_core", "medium", 30))
	check(late.attack_min > 20 and late.attack_max > late.attack_min, "a level 30 crystal medium gives far more (%d~%d)" % [late.attack_min, late.attack_max])
	check(items.base_stats(item("bp_shotgun", "medium", 30)).attack_max < items.base_stats(item("glass_orb", "medium", 30)).attack_max, "blueprints carry less attack than plain mediums")
	check(items.base_stats(item("glass_orb", "medium", 12, "rare")) == items.base_stats(item("glass_orb", "medium", 12)), "rarity does not change base stats")
	check(items.base_stats(item("glass_orb", "medium", 20)).attack_max > items.base_stats(item("glass_orb", "medium", 5, "rare")).attack_max, "a level 20 normal medium outhits a level 5 rare one")
	check(items.base_stats(item("cotton_coat", "outfit", 1)).armor == 6 and items.base_stats(item("cotton_gloves", "gloves", 1)).armor == 3 and items.base_stats(item("sneakers", "shoes", 1)).armor == 3, "outfit, gloves and shoes carry armour")
	check(items.base_stats(item("ribbon_tie", "head", 30)).is_empty() and items.base_stats(item("copper_ring", "ring", 30)).is_empty(), "head pieces and accessories carry none")
	check(Array(items.describe(item("glass_orb", "medium", 1))).has("공격력 2~4") and Array(items.describe(item("cotton_coat", "outfit", 1))).has("방어력 6"), "tooltips show them")

	# Attack and the witch's hits.
	wear([])
	check(arena.attack_range() == Vector2(build.base_attack[0], build.base_attack[1]), "bare, she has her own attack range")
	arena.force_rolls = {"hit": true, "crit": false}
	check(is_equal_approx(hit_value(10.0), 10.0), "a middle roll at the bare range deals a skill's listed damage")
	wear([item("glass_orb", "medium", 1)])
	check(arena.attack_range() == Vector2(10, 16), "a medium adds its attack range")
	check(is_equal_approx(hit_value(10.0), 10.0 * (0.3 + 0.7 * 13.0 / 10.0)), "and her hits grow with it (10 -> %.1f)" % (10.0 * (0.3 + 0.7 * 13.0 / 10.0)))
	arena.force_rolls = {"hit": true, "crit": true}
	check(is_equal_approx(hit_value(10.0), 10.0 * (0.3 + 0.7 * 16.0 / 10.0) * float(arena.config.crit_multiplier)), "a crit hits with the top of the range")
	arena.force_rolls = {}
	arena.config.crit_base = 0.0
	arena.config.crit_per_dexterity = 0.0
	var spots: Array = []
	for i in 600:
		var dealt: float = hit_value(10.0)
		var attack: float = ((dealt / 10.0) - 0.3) / 0.7 * 10.0
		spots.append((attack - 10.0) / 6.0)
	spots.sort()
	check(spots[0] >= -0.0001 and spots[-1] <= 1.0001 and spots[-1] - spots[0] > 0.9, "unforced hits spread over the whole range")
	check(absf(spots[300] - 0.5) < 0.07, "with no dexterity the middle hit sits mid-range (%.2f)" % spots[300])
	arena.build.set_level(30)
	arena.build.change_stat("dexterity", 100)
	check(arena.attack_median() > 0.75, "dexterity leans hits toward the top (median %.2f)" % arena.attack_median())
	spots.clear()
	for i in 600:
		var dealt: float = hit_value(10.0)
		spots.append((((dealt / 10.0) - 0.3) / 0.7 * 10.0 - 10.0) / 6.0)
	spots.sort()
	check(absf(spots[300] - arena.attack_median()) < 0.07, "and the rolls follow it (%.2f)" % spots[300])
	arena.config.dexterity = 100000.0
	check(arena.attack_median() < 0.86, "no amount of dexterity makes every hit the top one")
	arena.build.reset_stats()
	arena.build.set_level(1)

	# Enemy hits and armour.
	wear([])
	arena.hp = arena.config.max_hp
	var taken: Array = []
	for i in 300:
		var before: float = arena.hp
		arena.damage_player(5.0)
		taken.append(before - arena.hp)
		arena.hp = arena.config.max_hp
	taken.sort()
	check(taken[0] >= 5.0 * (1.0 - build.enemy_spread) - 0.001 and taken[-1] <= 5.0 * (1.0 + build.enemy_spread) + 0.001 and taken[-1] - taken[0] > 1.0, "enemy hits vary ±%d%%" % roundi(100 * build.enemy_spread))
	arena.force_rolls = {"hit": true, "crit": false}
	wear([item("cotton_coat", "outfit", 20), item("cotton_gloves", "gloves", 20), item("sneakers", "shoes", 20)])
	var armour: float = arena.armor()
	check(armour > 50, "a level 20 outfit, gloves and shoes give %d armour" % armour)
	arena.set_enemy_level(20)
	var vs_strong: float = arena.armor_reduction()
	arena.set_enemy_level(1)
	var vs_weak: float = arena.armor_reduction()
	check(is_equal_approx(vs_strong, armour / (armour + build.armor_k[0] + build.armor_k[1] * 20)) and vs_strong > 0.15 and vs_strong < 0.25, "it turns away about a fifth from level 20 enemies (%d%%)" % roundi(100 * vs_strong))
	check(vs_weak > vs_strong, "and more from weaker ones (%d%%)" % roundi(100 * vs_weak))
	wear([item("cotton_coat", "outfit", 1), item("cotton_gloves", "gloves", 1), item("sneakers", "shoes", 1)])
	arena.set_enemy_level(20)
	check(arena.armor_reduction() < 0.08, "level 1 armour barely helps against level 20 enemies (%d%%)" % roundi(100 * arena.armor_reduction()))
	var before_hp: float = arena.hp
	arena.damage_player(10.0)
	check(is_equal_approx(before_hp - arena.hp, 10.0 * (1.0 - arena.armor_reduction())), "her armour cuts the hit she takes")
	arena.hp = arena.config.max_hp
	var plain: float = arena.armor()
	arena.shield_time = 3.0
	check(arena.armor() > plain, "the raised shield adds a little armour")
	arena.shield_time = 0.0
	arena.link_enemy_level()

	# Summons.
	arena.force_rolls = {}
	arena.config.summon_crit_base = 0.0
	arena.config.summon_crit_per_level = 0.0
	var summon_hits: Array = []
	for i in 200:
		var dummy: Dictionary = arena.enemies.dummy
		dummy.hp = 99999.0
		arena.strike("dummy", 10.0, false, "automaton", "automaton")
		summon_hits.append(99999.0 - float(dummy.hp))
	summon_hits.sort()
	check(summon_hits[0] >= 10.0 * (1.0 - build.summon_spread) - 0.001 and summon_hits[-1] <= 10.0 * (1.0 + build.summon_spread) + 0.001 and summon_hits[-1] > summon_hits[0], "summon hits vary only ±%d%%" % roundi(100 * build.summon_spread))
	var growth: float = arena.summon_growth("damage", "automaton")
	var life: float = arena.summon_growth("hp", "automaton")
	var charm := item("copper_ring", "ring", 10)
	charm.options = {"summon_damage_pct": 20, "summon_hp_pct": 30}
	wear([charm])
	check(is_equal_approx(arena.summon_growth("damage", "automaton"), growth * 1.2) and is_equal_approx(arena.summon_growth("hp", "automaton"), life * 1.3), "summon options raise summon damage and life")
	check(arena.items.affixes.has("summon_damage_pct") and arena.items.affixes.has("summon_hp_pct"), "they can roll on gear")
	wear([])

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
