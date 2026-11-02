extends SceneTree
## All reward kinds share ground selection; only a successful pickup changes ownership.
var arena: Node3D
var checks: Array = []
var failures: Array = []
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks.append(description)
	if not ok:
		failures.append(description)
		push_error(description)

func click(loot: Dictionary) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = arena.camera.unproject_position(loot.visual.global_position)
	for entry in arena.loot_labels():
		if is_same(entry.loot, loot):
			press.position = entry.rect.get_center()
			break
	root.push_input(press, true)
	press.pressed = false
	root.push_input(press, true)

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	arena.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " GPU capture saved")

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/ground_loot_v2/regressions/loot_resources")
	DirAccess.make_dir_recursive_absolute(output)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await physics_frame
	await physics_frame
	var data: Dictionary = arena.items.data
	data.currency.drops.normal.chance = 1.0
	data.potion_drops.chance.normal = 1.0
	data.piece_drops.normal = 1.0
	arena.loot_rng.seed = 431
	var expected := RandomNumberGenerator.new()
	expected.state = arena.loot_rng.state
	expected.randf()
	var money := expected.randi_range(int(data.currency.drops.normal.range[0]), int(data.currency.drops.normal.range[1]))
	expected.randf()
	var potion: String = arena.items.weighted(expected, data.potion_drops.weights)
	expected.randf()
	var piece: String = data.pieces.keys()[expected.randi_range(0, data.pieces.size() - 1)]
	var combat_state: int = arena.combat_rng.state
	var origin: Vector3 = arena.player.position + Vector3(1, 0, 0)
	arena.drop_spoils("normal", origin)
	check(arena.loot_rng.state == expected.state and arena.combat_rng.state == combat_state, "resource drops preserve the existing reward rolls and do not consume combat RNG")
	check(arena.ground_items.size() == 3 and arena.coins == 0 and arena.pieces[piece] == 0 and arena.potion_stash[potion] == 0, "currency, piece and potion remain unowned on the ground")
	var currency_loot: Dictionary = arena.ground_items[0]
	var potion_loot: Dictionary = arena.ground_items[1]
	var piece_loot: Dictionary = arena.ground_items[2]
	check(currency_loot.amount == money and potion_loot.id == potion and piece_loot.id == piece, "ground rewards retain the rolled amount and exact potion/piece IDs")
	check(currency_loot.name == "%d %s" % [money, data.currency.name] and potion_loot.name == arena.config.potions[potion].name and piece_loot.name == data.pieces[piece].name, "labels identify the currency amount, potion and name fragment")
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	arena.drop_item(arena.items.generate(rng, 10, "rare", "ring"), origin)
	var equipment: Dictionary = arena.ground_items[-1]
	var separate := true
	for i in arena.ground_items.size():
		for j in i:
			var a: Vector3 = arena.ground_items[i].node.position
			var b: Vector3 = arena.ground_items[j].node.position
			separate = separate and Vector2(a.x - b.x, a.z - b.z).length() >= 0.699
	check(separate and arena.loot_labels().size() == 4, "mixed equipment and resource drops share separated ground positions and labels")
	arena.tick_ground_loot(0.2)
	check(arena.ground_items.all(func(loot): return loot.visual.position.y > 0 and loot.visual.rotation.length() > 1), "every reward kind falls from waist height with rotation")
	arena.tick_ground_loot(0.2)
	check(arena.ground_items.all(func(loot): return loot.visual.position == Vector3.ZERO and loot.visual.rotation == Vector3.ZERO), "every reward kind lands flat after 0.4 seconds")
	await capture("mixed_rewards")
	var slots: Array = arena.potion_slots.duplicate(true)
	arena.player.position = currency_loot.node.position
	arena.tick_pickup()
	check(arena.coins == 0 and arena.ground_items.size() == 4, "walking over resources does not automatically collect them")
	arena.tick_ground_loot(5.0)
	check(arena.loot_labels().is_empty(), "resource labels also hide after five seconds")
	for loot in [currency_loot, potion_loot, piece_loot]:
		arena.update_loot_hover(arena.camera.unproject_position(loot.visual.global_position))
		check(arena.loot_labels().size() == 1 and is_same(arena.loot_labels()[0].loot, loot) and loot.selection.visible, "hover reveals and highlights the correct %s reward" % loot.kind)
	arena.update_loot_hover(Vector2(3, 3))
	var alt := InputEventKey.new()
	alt.physical_keycode = KEY_ALT
	alt.pressed = true
	root.push_input(alt, true)
	check(arena.loot_labels().size() == 4, "held Alt reveals all four kinds together")
	await capture("mixed_rewards_alt")
	alt.pressed = false
	root.push_input(alt, true)
	check(arena.loot_labels().is_empty(), "Alt release restores hidden resource labels immediately")
	while arena.stow(arena.items.generate(rng, 1, "normal", "ring")):
		pass
	var full_size: int = arena.bag.size()
	for loot in [currency_loot, potion_loot, piece_loot]:
		arena.player.position = loot.node.position
		click(loot)
	check(arena.coins == money and arena.potion_stash[potion] == 1 and arena.pieces[piece] == 1 and arena.ground_items.size() == 1, "clicking resources credits only their correct balances even with a full equipment bag")
	check(arena.bag.size() == full_size and arena.potion_slots == slots, "resource pickup uses no equipment cells and never refills potion quickslots")
	arena.pick_up(currency_loot)
	arena.pick_up(potion_loot)
	arena.pick_up(piece_loot)
	check(arena.coins == money and arena.potion_stash[potion] == 1 and arena.pieces[piece] == 1, "repeated pickup requests cannot award a resource twice")
	arena.player.position = equipment.node.position
	click(equipment)
	check(arena.ground_items.size() == 1 and arena.loot_target.is_empty(), "a full equipment bag still leaves equipment on the ground")
	arena.drop_resource("currency", "", 1000, origin)
	arena.reset_arena()
	check(arena.ground_items.is_empty() and arena.coins == money and arena.potion_stash[potion] == 1 and arena.pieces[piece] == 1, "restart keeps collected balances and discards only uncollected drops")

	# The final kill used to freeze movement: every newly physical reward must remain reachable.
	arena.bag.clear()
	for id in arena.enemies:
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.player.position = Vector3.ZERO
	arena.place_camera(arena.player.position)
	arena.spawn_enemy("last", Vector3(3, 0, 0), false)
	arena.enemies.last.hp = 1.0
	arena.force_rolls = {"hit": true, "crit": false}
	data.drops.normal.chance = 1.0
	var before_money: int = arena.coins
	arena.strike("last", 10.0, false, "witch", "staff")
	check(arena.field_cleared() and arena.ground_items.size() == 4 and arena.coins == before_money, "the actual final enemy drops all four reward kinds without granting them")
	check(arena.ground_items.all(func(loot): return Vector2(loot.node.position.x - 3, loot.node.position.z).length() < 2), "all rewards appear around the defeated enemy rather than the player")
	arena.tick_ground_loot(0.4)
	await capture("final_enemy_rewards")
	currency_loot = arena.ground_items.filter(func(loot): return loot.kind == "currency")[0]
	click(currency_loot)
	check(is_same(arena.loot_target, currency_loot) and arena.moving, "clicking distant final-kill currency starts pickup movement after field clear")
	var before_position: Vector3 = arena.player.position
	arena.paused = true
	await physics_frame
	arena._physics_process(1.0 / 60.0)
	check(arena.player.position == before_position and arena.coins == before_money, "pause freezes post-clear pickup movement")
	arena.paused = false
	var state: Dictionary = arena.state.duplicate(true)
	var elapsed: float = arena.elapsed
	combat_state = arena.combat_rng.state
	for i in 240:
		await physics_frame
		arena._physics_process(1.0 / 60.0)
		if not arena.ground_items.has(currency_loot):
			break
	check(arena.coins == before_money + currency_loot.amount and not arena.ground_items.has(currency_loot), "she reaches and collects a distant reward after the final kill")
	check(arena.state == state and arena.elapsed == elapsed and arena.combat_rng.state == combat_state, "post-clear pickup does not restart combat, resource clocks or combat RNG")
	var before_mp: float = arena.state.mana
	arena.request_slot("rmb", {"ground": [3, 0, 0]})
	check(arena.state.mana == before_mp and arena.windup.is_empty(), "combat skills remain disabled after field clear")
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	FileAccess.open(output.path_join("resources.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("LOOT_RESOURCES_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
