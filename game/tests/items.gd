extends SceneTree
## C4-C6 trial items: rolls follow 04 §4.2-§4.3, drops and pickup on the field, the seven worn
## slots, every option's effect, blueprints/parts, the two uniques and the inventory window.
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

func seconds(value: float) -> void:
	for i in roundi(value * 60):
		arena.state.mana = arena.state.max_mana
		await step()

func fresh(spot: Vector3 = Vector3(2, 0, 0)) -> void:
	arena.reset_arena()
	for slot in arena.equipment:
		arena.equipment[slot] = null
	arena.bag.clear()
	arena.refresh_gear()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	for ally in arena.allies:
		ally.node.free()
	arena.allies.clear()
	arena.spawn_enemy("t0", spot, false)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.hp = 10000.0
	await step(2)

func base_for(slot: String, family: String = "") -> String:
	for base in arena.items.data.bases:
		if base.slot == slot and (family == "" or base.get("family", "") == family):
			return base.id
	return ""

func wear(slot: String, options: Dictionary, family: String = "") -> void:
	arena.bag.append({"base": base_for(slot, family), "slot": slot, "rarity": "magic", "level": 30, "options": options, "affixes": [], "name": "시험 " + slot})
	arena.equip(arena.bag.size() - 1)

func struck(source: String, roller: String = "witch") -> float:
	var before: float = arena.enemies.t0.hp
	arena.strike("t0", 10.0, false, roller, source)
	return before - arena.enemies.t0.hp

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var items = arena.items
	var data: Dictionary = items.data
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Rolls.
	var ok_counts := true
	var ok_slots := true
	var ok_tiers := true
	var ok_names := true
	var ok_bases := true
	for rarity in ["normal", "magic", "rare"]:
		for level in [1, 12, 30]:
			for i in 150:
				var item: Dictionary = items.generate(rng, level, rarity)
				var counts: Array = data.affix_counts[rarity]
				var kinds := {"prefix": 0, "suffix": 0}
				var seen := {}
				for affix in item.affixes:
					kinds[affix.kind] += 1
					ok_slots = ok_slots and item.slot in items.affixes[affix.id].slots and not seen.has(affix.id)
					seen[affix.id] = true
					var span: Array = items.affixes[affix.id].tiers[affix.tier]
					ok_tiers = ok_tiers and affix.tier <= items.tier_for(level) and affix.value >= span[0] and affix.value <= span[1]
				var pool: int = data.affixes.filter(func(a): return item.slot in a.slots).size()
				ok_counts = ok_counts and item.affixes.size() <= int(counts[1]) and (item.affixes.size() >= mini(int(counts[0]), pool) or rarity == "rare") and kinds.prefix <= int(counts[2]) and kinds.suffix <= int(counts[2])
				ok_bases = ok_bases and level >= int(items.bases[item.base].min_level)
				if rarity == "normal":
					ok_names = ok_names and item.name == items.bases[item.base].name and item.affixes.is_empty()
				elif rarity == "magic":
					ok_names = ok_names and item.name.ends_with(items.bases[item.base].name)
	check(ok_counts, "normal has no options, magic 1-2 with one prefix/suffix at most, rare up to 5 with three of a kind at most")
	check(ok_slots, "options only roll where 04 lets them and never twice on one item")
	check(ok_tiers and items.tier_for(11) == 0 and items.tier_for(12) == 1 and items.tier_for(24) == 2, "option tiers open at item levels 1/12/24 and values stay in their tier's range")
	check(ok_names and ok_bases, "magic names read '[suffix] [prefix] [base]', normal keeps the base name, late bases need level 24")
	var blueprint: Dictionary = {}
	for i in 200:
		var item: Dictionary = items.generate(rng, 30, "magic", "medium")
		if item.base == "bp_chainsaw":
			blueprint = item
			break
	check(not blueprint.is_empty() and blueprint.options["skill:chainsaw"] == 2, "a blueprint always carries its skill level, +2 at item level 24 and up")

	# Drops.
	var drops := 0
	for i in 2000:
		drops += items.roll_drops(rng, "normal", 5).size()
	check(absf(drops / 2000.0 - float(data.drops.normal.chance)) < 0.03, "normal enemies drop at their trial rate")
	check(items.roll_drops(rng, "boss", 5).any(func(item): return item.rarity == "unique"), "a boss always leaves a unique")

	await fresh(Vector3(1.5, 0, 0))
	# Another enemy keeps the field from counting as cleared once t0 falls.
	arena.spawn_enemy("far", Vector3(-9, 0, 6), false)
	arena.enemies.far.cooldown = 999
	arena.build.set_level(7)
	arena.items.data.drops.normal.chance = 1.0
	arena.enemies.t0.hp = 1.0
	arena.strike("t0", 10.0, false, "witch", "staff")
	arena.items.data.drops.normal.chance = 0.1
	check(arena.ground_items.size() == 1 and arena.ground_items[0].item.level == 7, "a defeated enemy drops loot at the trial level")
	arena.player.position = arena.ground_items[0].node.position
	await step(2)
	check(arena.ground_items.is_empty() and arena.bag.size() == 1, "walking over loot picks it up")
	for i in int(data.bag_size):
		arena.bag.append(items.generate(rng, 1, "normal"))
	arena.drop_item(items.generate(rng, 1, "normal"), arena.player.position)
	await step(2)
	check(arena.ground_items.size() == 1, "a full bag leaves loot on the ground")
	arena.reset_arena()
	check(arena.ground_items.is_empty() and arena.bag.size() == int(data.bag_size) + 1, "a restart clears the field but keeps the bag")

	# Worn options.
	await fresh()
	wear("gloves", {"damage_pct": 20})
	check(is_equal_approx(struck("staff"), 12.0) and is_equal_approx(struck("automaton", "automaton"), 10.0), "damage +% raises her own hits, not her summons'")
	var crit: float = arena.crit_chance()
	var hit: float = arena.hit_chance("t0")
	wear("brooch", {"crit_pct": 5})
	wear("head", {"hit_pct": 20, "mana": 20, "damage_reduction": 5})
	check(is_equal_approx(arena.crit_chance(), crit + 0.05) and arena.hit_chance("t0") > hit, "crit and hit options feed the existing rolls")
	check(is_equal_approx(arena.state.max_mana, 80.0), "max mana options raise the pool")
	var hp: float = arena.hp
	arena.damage_player(20.0)
	check(is_equal_approx(hp - arena.hp, 19.0), "damage reduction trims a hit by its points")
	var attack: float = arena.attack_seconds()
	var recovery: float = arena.hit_recovery_seconds()
	wear("ring", {"cast_speed": 20, "life": 30, "mana_regen_pct": 50})
	wear("outfit", {"hit_recovery": 20})
	arena.unequip("gloves")
	wear("gloves", {"attack_speed": 20})
	check(arena.config.cast_speed_score == 20 and arena.attack_seconds() < attack and arena.hit_recovery_seconds() < recovery, "cast, attack and hit recovery speed options fill their own scores")
	check(is_equal_approx(arena.config.max_hp, 130.0), "life options raise max HP")
	arena.config.mana_regen = 2.0
	arena.state.mana = 0.0
	for i in 60:
		await step()
	check(absf(arena.state.mana - 3.0) < 0.1, "mana regeneration options speed natural regen")
	arena.config.mana_regen = 0
	wear("brooch", {"upkeep_pct": 20})
	check(is_equal_approx(arena.rules.skills.chainsaw.upkeep_per_second, float(arena.tool_upkeep.chainsaw) * 0.8), "toggle upkeep options trim every tool's drain")
	wear("medium", {"slow_pct": 20, "bleed_pct": 25})
	check(is_equal_approx(arena.slow_factor(), 1.0 - (1.0 - arena.config.slow_speed_factor) * 1.2) and is_equal_approx(arena.bleed_plan(0).seconds, float(arena.config.bleed.seconds) * 1.25), "slow strength and bleed duration options work on their effects")
	wear("shoes", {"move_speed": 10})
	arena.set_destination(Vector3(-6, 0, 0))
	var start: float = arena.player.position.x
	await step(30)
	check(absf((start - arena.player.position.x) - arena.config.player_speed * 1.1 * 0.5) < 0.15, "move speed options make her walk faster")

	# Mediums: blueprints and parts.
	await fresh()
	wear("medium", {"skill:chainsaw": 2}, "blueprint")
	check(arena.config.chainsaw_level == 3 and arena.build.skill_points() == arena.build.level, "a blueprint adds skill levels without spending points")
	arena.unequip("medium")
	wear("medium", {"skill:shotgun": 2}, "blueprint")
	check(is_equal_approx(struck("shotgun"), 10.0 * (1.0 + 2 * float(data.skill_level_damage.shotgun))), "shotgun levels from its blueprint raise its damage")
	arena.unequip("medium")
	wear("medium", {"tag:cutting": 15}, "part")
	check(is_equal_approx(struck("chainsaw"), 11.5) and is_equal_approx(struck("shotgun"), 10.0), "a part strengthens its own principle's attacks only")

	# Uniques.
	await fresh(Vector3(1.5, 0, 0))
	arena.spawn_enemy("t1", Vector3(2.5, 0, 0.8), false)
	arena.enemies.t1.cooldown = 999
	arena.enemies.t1.hp = 10000.0
	arena.bag.append(items.make_unique(rng, 30, "executioner_pulley"))
	arena.equip(arena.bag.size() - 1)
	arena.request_slot("q", {})
	arena.request_slot("lmb", {"enemy_id": "t0"})
	arena.windup.release = 0.0
	arena.tick_windup(0.0)
	check(arena.enemies.t1.hp < 10000.0, "the executioner's pulley drags a second enemy into a bolt cutter hit")
	arena.request_slot("q", {})

	await fresh(Vector3(6, 0, 0))
	arena.bag.append(items.make_unique(rng, 30, "self_replicating_spring"))
	arena.equip(arena.bag.size() - 1)
	check(arena.config.automaton_level == 2, "the self-replicating spring also raises the automaton level")
	arena.config.summon_detection_range = 1.0
	arena.spawn_ally(Vector3(1, 0, 0), true, "")
	arena.allies[0].life = 0.1
	await step(10)
	check(arena.allies.size() == 1 and arena.allies[0].get("replica", false), "a self-destructing automaton leaves one replica")
	arena.allies[0].life = 0.1
	await step(10)
	check(arena.allies.is_empty(), "the replica does not copy itself again")
	arena.config.summon_detection_range = 12

	# Window, keys and log.
	await fresh()
	var key = InputEventKey.new()
	key.physical_keycode = KEY_I
	key.pressed = true
	root.push_input(key, true)
	check(arena.inventory_window.visible, "I opens the inventory")
	arena.bag.append({"base": "copper_ring", "slot": "ring", "rarity": "magic", "level": 30, "options": {"life": 10}, "affixes": [{"id": "life", "kind": "suffix", "tier": 0, "value": 10}], "name": "튼튼함의 구리 반지"})
	wear("ring", {"life": 20})
	arena.inventory_window.refresh()
	var bag_button: Button = arena.inventory_window.find_children("*", "Button", true, false).filter(func(b): return b.text == "튼튼함의 구리 반지")[0]
	check(bag_button.tooltip_text.contains("지금 착용"), "a bag item's tooltip compares with what is worn")
	bag_button.pressed.emit()
	check(arena.equipment.ring.name == "튼튼함의 구리 반지" and arena.bag.any(func(item): return item.name == "시험 ring"), "clicking a bag item wears it and returns the old one")
	root.push_input(key, true)
	key.physical_keycode = KEY_G
	var before: int = arena.ground_items.size()
	root.push_input(key, true)
	key.shift_pressed = true
	root.push_input(key, true)
	check(arena.ground_items.size() == before + 2 and arena.ground_items[-1].item.rarity == "unique", "G drops a test item and Shift+G a unique")
	var score: float = arena.config.attack_speed_score
	key.shift_pressed = false
	for code in [KEY_F4, KEY_F12]:
		key.physical_keycode = code
		root.push_input(key, true)
	check(arena.config.attack_speed_score == score, "F4 and F12 no longer step speed scores; items do")
	check(arena.build.snapshot().equipment.ring.name == "튼튼함의 구리 반지", "the build snapshot for the A5 log lists the worn items")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_items_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
