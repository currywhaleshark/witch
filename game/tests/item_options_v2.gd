extends SceneTree
## 2026-11-05 item pass: recovery options (life/mana leech, on-kill), drive/firearm options (shred
## strength, stun/bind time, magazine, pierce), the explosive tag and its part, and five uniques
## (twin barrel core, bundled fuse, rusted guillotine hinge, counter hinge, iron cartilage).
## Writes a report only with --output.
const LootVisual = preload("res://scripts/ground_loot_visual.gd")
var arena: Node3D
var items
var failures: Array = []
var checks: Array = []
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
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
	for slot in arena.equipment:
		arena.equipment[slot] = null
	arena.bag.clear()
	arena.refresh_gear()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for grade in items.data.currency.drops:
		items.data.currency.drops[grade].chance = 0.0
		items.data.piece_drops[grade] = 0.0
		items.data.potion_drops.chance[grade] = 0.0
	for grade in items.data.drops:
		items.data.drops[grade].chance = 0.0
		items.data.drops[grade].erase("guaranteed_unique")
		items.data.drops[grade].erase("unique_chance")
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	# A far enemy keeps the field from counting as cleared (which would stop kegs and devices).
	enemy("anchor", Vector3(-11, 0, -9))

func enemy(id: String, at: Vector3, grade: String = "normal", hp: float = 99999.0) -> Dictionary:
	arena.spawn_enemy(id, at, false, grade, "light")
	var e: Dictionary = arena.enemies[id]
	e.cooldown = 999
	e.max_hp = maxf(hp, 1.0)
	e.hp = hp
	return e

func wear(slot: String, options: Dictionary) -> void:
	var base := ""
	for b in items.data.bases:
		if b.slot == slot and (base == "" or b.get("family", "") == ""):
			base = b.id
			if b.get("family", "") == "":
				break
	arena.bag.append({"base": base, "slot": slot, "rarity": "magic", "level": 30, "options": options, "affixes": [], "name": "시험 " + slot})
	arena.equip(arena.bag.size() - 1)

func wear_unique(id: String) -> void:
	arena.bag.append(items.make_unique(RandomNumberGenerator.new(), 30, id))
	arena.equip(arena.bag.size() - 1)

func lost(id: String, from: float = 99999.0) -> float:
	return from - float(arena.enemies[id].hp) if arena.enemies.has(id) else from

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	items = arena.items

	# Data: every new option has a label, every unique a describable line.
	for id in ["life_leech_pct", "mana_leech_pct", "life_on_kill", "mana_on_kill", "shred_pct", "control_pct", "magazine", "pierce"]:
		check(items.affixes.has(id) and items.option_text(id, 3).length() > 0, "option %s is defined with a label" % id)
	check(items.bases.has("part_explosive") and items.option_text("tag:explosive", 15).contains("폭발"), "the explosive part carries the explosive tag")
	for id in ["twin_barrel_core", "bundled_fuse", "rusted_guillotine_hinge", "counter_hinge", "iron_cartilage"]:
		var unique: Dictionary = items.make_unique(RandomNumberGenerator.new(), 30, id)
		check(items.describe(unique).size() >= 3 and arena.config.attack_tags.get("powder_keg") == "explosive", "unique %s builds and describes" % id)
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 600:
		for affix in items.generate(rng, 30, "rare").affixes:
			seen[affix.id] = true
	check(seen.has("life_leech_pct") and seen.has("mana_on_kill") and seen.has("pierce") and seen.has("control_pct"), "new options appear on dropped rares")

	# Life and mana leech: a share of her own direct damage, never a summon's.
	await fresh()
	enemy("t0", Vector3(0, 0, 2))
	wear("medium", {"life_leech_pct": 5, "mana_leech_pct": 4})
	arena.hp = 40.0
	arena.state.mana = 10.0
	var before: float = arena.enemies.t0.hp
	arena.strike("t0", 20.0, false, "witch", "staff")
	var dealt: float = before - arena.enemies.t0.hp
	check(dealt > 0 and is_equal_approx(arena.hp, 40.0 + dealt * 0.05) and is_equal_approx(arena.state.mana, 10.0 + dealt * 0.04), "leech returns life and mana from her hit")
	var hp_now: float = arena.hp
	arena.strike("t0", 20.0, false, "turret", "turret")
	arena.damage_enemy("t0", 20.0, false)
	check(is_equal_approx(arena.hp, hp_now), "summon hits and bleed/burn damage never leech")

	# On-kill recovery.
	await fresh()
	enemy("t0", Vector3(0, 0, 2), "normal", 5.0)
	wear("gloves", {"life_on_kill": 6})
	wear("ring", {"mana_on_kill": 4})
	arena.hp = 40.0
	arena.state.mana = 10.0
	arena.strike("t0", 50.0, false, "witch", "staff")
	check(not arena.enemies.has("t0") and is_equal_approx(arena.hp, 46.0) and is_equal_approx(arena.state.mana, 14.0), "a kill restores life and mana")

	# Shred strength grows only the shred's extra share.
	await fresh()
	var e: Dictionary = enemy("t0", Vector3(0, 0, 2))
	e.shred = 3.0
	var plain: float = arena.damage_enemy("t0", 100.0)
	wear("gloves", {"shred_pct": 20})
	var sharper: float = arena.damage_enemy("t0", 100.0)
	check(is_equal_approx(plain, 100.0 * arena.config.shred_damage_taken) and is_equal_approx(sharper, 100.0 * (1.0 + (arena.config.shred_damage_taken - 1.0) * 1.2)), "shred strength raises shredded damage taken")

	# Stun and bind time.
	await fresh()
	enemy("t0", Vector3(0, 0, 2))
	arena.restrain("t0", "stun", 1.0)
	var base_stun: float = arena.enemies.t0.stun
	arena.enemies.t0.stun = 0.0
	wear("head", {"control_pct": 20})
	arena.restrain("t0", "stun", 1.0)
	arena.restrain("t0", "bound", 2.0)
	check(is_equal_approx(base_stun, 1.0) and is_equal_approx(arena.enemies.t0.stun, 1.2) and is_equal_approx(arena.enemies.t0.bound, 2.4), "stun and bind time options lengthen holds")

	# Magazine and pierce on the matchlock.
	await fresh()
	enemy("a", Vector3(0, 0, 2))
	enemy("b", Vector3(0, 0, 4))
	arena.equip_gun("matchlock")
	var magazine: int = arena.gun_magazine("matchlock")
	arena.fire_gun({"target_enemy": "a"}, Vector3(0, 0, 1))
	check(lost("a") > 0 and lost("b") == 0.0, "without pierce a matchlock round stops at its target")
	arena.enemies.a.hp = 99999.0
	wear("medium", {"magazine": 2, "pierce": 1})
	check(arena.gun_magazine("matchlock") == magazine + 2, "magazine option adds rounds")
	arena.fire_gun({"target_enemy": "a"}, Vector3(0, 0, 1))
	check(lost("a") > 0 and is_equal_approx(lost("b"), lost("a")), "pierce carries the round into the enemy behind at full damage")

	# Explosive tag and part.
	await fresh()
	enemy("t0", Vector3(0, 0, 2))
	before = arena.enemies.t0.hp
	arena.strike("t0", 10.0, false, "witch", "powder_keg")
	var keg_plain: float = before - arena.enemies.t0.hp
	arena.gear["tag:explosive"] = 20.0
	before = arena.enemies.t0.hp
	arena.strike("t0", 10.0, false, "witch", "powder_keg")
	check(is_equal_approx(before - arena.enemies.t0.hp, keg_plain * 1.2), "explosive tag raises the powder keg's damage")

	# Twin barrel core: two narrower volleys at 60%.
	await fresh()
	enemy("front", Vector3(0, 0, 3))
	enemy("edge", Vector3(3.0 * sin(deg_to_rad(27.0)), 0, 3.0 * cos(deg_to_rad(27.0))))
	wear_unique("twin_barrel_core")
	arena.gear["rule:twin_barrels"] = 0.0
	arena.fire_shotgun(Vector3(0, 0, 3), true)
	var full: float = lost("front")
	var edge_full: float = lost("edge")
	arena.enemies.front.hp = 99999.0
	arena.enemies.edge.hp = 99999.0
	arena.gear["rule:twin_barrels"] = 1.0
	arena.fire_shotgun(Vector3(0, 0, 3), true)
	var first: float = lost("front")
	await step(12)
	check(edge_full > 0 and lost("edge") == 0.0, "twin volleys use a narrower cone")
	check(is_equal_approx(first, full * 0.6) and is_equal_approx(lost("front"), full * 1.2), "twin core fires two 60% volleys 0.15s apart")

	# Bundled fuse: fire along the roll, a weaker blast.
	await fresh()
	enemy("t0", Vector3(0, 0, 6.5))
	wear_unique("bundled_fuse")
	var probe = arena.probe
	var blasts := func() -> float: return float(probe.sources.get("powder_keg", {}).get("damage", 0.0))
	arena.gear["rule:fuse_trail"] = 0.0
	var start: float = blasts.call()
	arena.roll_keg(Vector3(0, 0, 8), Vector3(0, 0, 1))
	for i in 120:
		if arena.kegs.is_empty():
			break
		await step()
	var blast_plain: float = blasts.call() - start
	check(arena.fires.is_empty(), "without the fuse the keg leaves no fire")
	arena.enemies.t0.hp = 99999.0
	arena.gear["rule:fuse_trail"] = 1.0
	start = blasts.call()
	arena.roll_keg(Vector3(0, 0, 8), Vector3(0, 0, 1))
	for i in 120:
		if arena.kegs.is_empty():
			break
		await step()
	check(arena.fires.size() >= 3, "the lit fuse leaves fires along the roll (%d)" % arena.fires.size())
	check(blast_plain > 0 and is_equal_approx(blasts.call() - start, blast_plain * 0.7), "the fuse keg's blast is 30% weaker")

	# Rusted guillotine hinge: weak ordinary enemies are executed, weak elites take double.
	await fresh()
	enemy("low", Vector3(0, 0, 3), "normal", 1000.0)
	arena.enemies.low.max_hp = 10000.0
	wear_unique("rusted_guillotine_hinge")
	arena.place_device("guillotine", Vector3(0, 0, 3), Vector3(0, 0, 1))
	await step(90)
	check(not arena.enemies.has("low"), "a weakened ordinary enemy is beheaded outright")
	enemy("elite", Vector3(0, 0, 3), "elite", 1000.0)
	arena.enemies.elite.max_hp = 10000.0
	arena.gear["rule:guillotine_execute"] = 0.0
	arena.place_device("guillotine", Vector3(0, 0, 3), Vector3(0, 0, 1))
	await step(90)
	var elite_plain: float = lost("elite", 1000.0)
	arena.enemies.elite.hp = 1000.0
	arena.gear["rule:guillotine_execute"] = 1.0
	arena.place_device("guillotine", Vector3(0, 0, 3), Vector3(0, 0, 1))
	await step(90)
	check(elite_plain > 0 and is_equal_approx(lost("elite", 1000.0), elite_plain * 2.0), "a weakened elite takes a doubled cut instead")

	# Counter hinge: blocks mend and shove, at most once a second.
	await fresh()
	enemy("t0", Vector3(0, 0, 1.2))
	wear_unique("counter_hinge")
	var shield: Dictionary = arena.rules.skills.shield
	var keep := [shield.block_base, shield.block_cap]
	shield.block_base = 1.0
	shield.block_cap = 1.0
	arena.shield_time = 5.0
	arena.hp = 40.0
	arena.state.mana = 10.0
	arena.damage_player(10.0)
	var pushed: float = float(arena.enemies.t0.get("knockback_left", 0.0))
	arena.enemies.t0.knockback_left = 0.0
	arena.damage_player(10.0)
	check(is_equal_approx(arena.hp, 48.0) and is_equal_approx(arena.state.mana, 14.0), "each block restores 4 life and 2 mana")
	check(pushed > 0 and float(arena.enemies.t0.get("knockback_left", 0.0)) == 0.0, "the shove fires once per second")
	shield.block_base = keep[0]
	shield.block_cap = keep[1]

	# Iron cartilage: blows taken while the exoskeleton is worn refill mana.
	await fresh()
	wear_unique("iron_cartilage")
	arena.config.exoskeleton_level = 1
	arena.state.mana = 10.0
	arena.hp = 80.0
	arena.damage_player(20.0)
	check(is_equal_approx(arena.state.mana, 10.0), "no mana while the exoskeleton is not worn")
	arena.state.active_tool = "bolt_cutter"
	var hp_before: float = arena.hp
	arena.damage_player(20.0)
	check(arena.exo_active() and is_equal_approx(arena.state.mana, 10.0 + (hp_before - arena.hp) * 0.25), "a quarter of the blow returns as mana while worn")
	arena.config.exoskeleton_level = 0
	arena.state.active_tool = null

	# Loot models: new uniques show their base, the explosive part the power part.
	var holder := Node3D.new()
	root.add_child(holder)
	var twin: Dictionary = LootVisual.create(holder, {"kind": "equipment", "item": items.make_unique(RandomNumberGenerator.new(), 30, "twin_barrel_core")})
	var part: Dictionary = LootVisual.create(holder, {"kind": "equipment", "item": items.generate(RandomNumberGenerator.new(), 30, "normal", "medium").merged({"base": "part_explosive"}, true)})
	check(not twin.is_empty() and twin.visual.get_meta("loot_model") == "bp_shotgun", "a new unique drops with its base model")
	check(not part.is_empty() and part.visual.get_meta("loot_model") == "part_power", "the explosive part borrows the power part model")
	holder.queue_free()

	var result := {"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}
	if output != "":
		FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("ITEM_OPTIONS_V2_COMPLETE ", JSON.stringify(result))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
