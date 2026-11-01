extends SceneTree
## C7/C8 trial: sockets and the three soot name pieces (effects by where they sit), the 「록샤」
## true name, paid removal, 각인전 and material from kills and salvage, and one-option re-rolls.
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

func fresh() -> void:
	arena.reset_arena()
	for slot in arena.equipment:
		arena.equipment[slot] = null
	arena.bag.clear()
	for id in arena.pieces:
		arena.pieces[id] = 0
	arena.coins = 0
	arena.scrap = 0
	arena.refresh_gear()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(2, 0, 0), false)
	arena.enemies.t0.cooldown = 999
	arena.spawn_enemy("far", Vector3(-9, 0, 6), false)
	arena.enemies.far.cooldown = 999
	await step(2)

func wear(slot: String, sockets: int, affixes: Array = []) -> Dictionary:
	var base: String = {"medium": "glass_orb", "head": "ribbon_tie", "outfit": "cotton_coat", "gloves": "cotton_gloves", "brooch": "brass_brooch", "ring": "copper_ring"}[slot]
	var item := {"base": base, "slot": slot, "rarity": "rare" if not affixes.is_empty() else "normal", "level": 30, "options": {}, "affixes": affixes, "name": "시험 " + slot, "sockets": sockets, "pieces": []}
	for affix in affixes:
		item.options[affix.id] = affix.value
	arena.bag.append(item)
	arena.equip(arena.bag.size() - 1)
	return item

func give(piece: String, count: int = 1) -> void:
	arena.pieces[piece] += count

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var items = arena.items
	var data: Dictionary = items.data
	var craft: Dictionary = data.crafting
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	# Sockets on drop.
	var ok := true
	var seen := {}
	for i in 600:
		var item: Dictionary = items.generate(rng, 30, ["normal", "magic", "rare"][i % 3])
		var top: int = int(items.bases[item.base].get("socket_max", 0))
		ok = ok and item.sockets >= 0 and item.sockets <= top and item.pieces.is_empty()
		seen[item.sockets] = true
	check(ok and seen.has(0) and seen.has(2), "sockets roll 0 up to the base's maximum")
	check(items.make_unique(rng, 30).sockets == 0, "uniques carry no sockets")

	# Pieces work by where they sit.
	await fresh()
	give("bel", 3)
	wear("medium", 1)
	wear("shoes" if false else "head", 1)
	wear("ring", 1)
	arena.socket_piece("medium", "bel")
	arena.socket_piece("head", "bel")
	arena.socket_piece("ring", "bel")
	check(arena.config.attack_speed_score == 10 and arena.gear_total("move_speed") == 5 and arena.gear_total("mana_regen_pct") == 15, "「벨」 gives attack speed in the medium, move speed on armour, mana regen on an accessory")
	await fresh()
	give("sha", 3)
	wear("medium", 1)
	wear("outfit", 1)
	wear("brooch", 1)
	for slot in ["medium", "outfit", "brooch"]:
		arena.socket_piece(slot, "sha")
	check(arena.config.cast_speed_score == 10 and arena.gear_total("damage_reduction") == 2, "「샤」 gives cast speed in the medium, damage reduction on armour")
	check(is_equal_approx(arena.rules.skills.shotgun.mana_cost, 10.0 * 0.92), "「샤」 on an accessory trims skill mana costs")
	await fresh()
	give("rok", 3)
	wear("medium", 1)
	wear("gloves", 1)
	wear("ring", 1)
	var hp_max: float = arena.config.max_hp
	for slot in ["medium", "gloves", "ring"]:
		arena.socket_piece(slot, "rok")
	check(is_equal_approx(arena.config.max_hp, hp_max + 15) and is_equal_approx(arena.potion_factor(), 1.15), "「록」 gives life on armour and potion strength on an accessory")
	arena.hp = 50.0
	arena.enemies.t0.hp = 1.0
	arena.strike("t0", 10.0, false, "witch", "staff")
	check(is_equal_approx(arena.hp, 53.0), "「록」 in the medium mends a little on each kill")

	# The 「록샤」 true name.
	await fresh()
	give("rok", 2)
	give("sha", 2)
	var coat: Dictionary = wear("outfit", 2)
	var life: float = arena.config.max_hp
	arena.socket_piece("outfit", "rok")
	arena.socket_piece("outfit", "sha")
	var word: Dictionary = data.true_names[0]
	check(items.true_name(coat) != null and is_equal_approx(arena.config.max_hp, life + 15 + word.bonus.life) and arena.config.cast_speed_score == word.bonus.cast_speed, "록 then 샤 in a two-socket outfit wakes 「록샤」 on top of the pieces")
	check(not arena.socket_piece("outfit", "rok"), "a full item takes no more pieces")
	arena.coins = 100
	check(arena.unsocket("outfit") and arena.coins == 100 - int(craft.unsocket_coins) and arena.pieces.sha == 2 and items.true_name(coat) == null, "paid removal returns the last piece and the true name fades")
	arena.coins = 0
	check(not arena.unsocket("outfit"), "removal needs 각인전")
	await fresh()
	give("rok")
	give("sha")
	var gloves: Dictionary = wear("gloves", 2)
	arena.socket_piece("gloves", "rok")
	arena.socket_piece("gloves", "sha")
	var hat: Dictionary = wear("head", 2)
	give("rok")
	give("sha")
	arena.socket_piece("head", "sha")
	arena.socket_piece("head", "rok")
	check(items.true_name(gloves) == null and items.true_name(hat) == null, "the true name needs its slot and its order")

	# Salvage and re-roll.
	await fresh()
	arena.bag.append({"base": "ribbon_tie", "slot": "head", "rarity": "rare", "level": 30, "options": {}, "affixes": [], "name": "부수기", "sockets": 1, "pieces": ["bel"]})
	arena.salvage(0)
	check(arena.scrap == int(craft.salvage.rare) and arena.pieces.bel == 1 and arena.bag.is_empty(), "salvage gives material by rarity and returns socketed pieces")
	var ring: Dictionary = wear("ring", 0, [{"id": "damage_pct", "kind": "prefix", "tier": 2, "value": 25}, {"id": "life", "kind": "suffix", "tier": 2, "value": 30}])
	check(not arena.reroll("ring", 0), "a re-roll needs 각인전 and material")
	arena.coins = 3000
	arena.scrap = 200
	var ok_reroll := true
	for i in 60:
		arena.reroll("ring", 1)
		var affix: Dictionary = ring.affixes[1]
		var span: Array = items.affixes[affix.id].tiers[affix.tier]
		ok_reroll = ok_reroll and affix.kind == "suffix" and "ring" in items.affixes[affix.id].slots and affix.id != "damage_pct" and affix.value >= span[0] and affix.value <= span[1] and ring.options.get(affix.id) == affix.value and ring.options.size() == 2
	check(ok_reroll and ring.affixes[0].value == 25, "re-rolls stay on the suffix side of the ring's pool and leave the other option alone")
	check(arena.coins == 3000 - 60 * int(craft.reroll_coins) and arena.scrap == 200 - 60 * int(craft.reroll_material), "each re-roll costs its 각인전 and material")

	# Spoils.
	await fresh()
	data.currency.drops.normal.chance = 1.0
	data.piece_drops.normal = 1.0
	arena.enemies.t0.hp = 1.0
	arena.strike("t0", 10.0, false, "witch", "staff")
	data.currency.drops.normal.chance = 0.4
	data.piece_drops.normal = 0.03
	var total_pieces := 0
	for id in arena.pieces:
		total_pieces += arena.pieces[id]
	check(arena.coins >= int(data.currency.drops.normal.range[0]) and total_pieces == 1, "kills pay 각인전 and sometimes a name piece")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.ctrl_pressed = true
	key.pressed = true
	var coins: int = arena.coins
	root.push_input(key, true)
	check(arena.coins == coins + 200 and arena.pieces.bel >= 1 and arena.pieces.rok >= 1 and arena.pieces.sha >= 1, "Ctrl+G hands out test pieces, 각인전 and material")

	# Window and log.
	wear("outfit", 2)
	arena.inventory_window.visible = true
	arena.inventory_window.mode = "bench"
	arena.inventory_window.refresh()
	var buttons: Array = arena.inventory_window.find_children("*", "Button", true, false).filter(func(b): return b.text == "「록」 조각" and not b.disabled)
	buttons[0].pressed.emit()
	check(arena.equipment.outfit.pieces == ["rok"], "the workbench sockets a piece into a worn item")
	arena.inventory_window.visible = false
	check(arena.build.snapshot().equipment.outfit.pieces == ["rok"], "the A5 build snapshot lists socketed pieces")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_sockets_crafting_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
