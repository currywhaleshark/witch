extends SceneTree
## C9/C10 trial: the A5 log's mana flow (casts, upkeep, regen, potions), potion drops and the
## trial shop into a stash, and quickslots refilled by hand (no automatic refill, 04 §8.2).
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
	for id in arena.potion_stash:
		arena.potion_stash[id] = 0
	arena.coins = 0
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(3, 0, 0), false)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.hp = 10000.0
	arena.spawn_enemy("far", Vector3(-9, 0, 6), false)
	arena.enemies.far.cooldown = 999
	arena.restart_probe("test")
	await step(2)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var data: Dictionary = arena.items.data

	# C9 mana flow.
	await fresh()
	arena.request_slot("rmb", {"enemy_id": "t0"})
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)
	check(is_equal_approx(arena.probe.mana_flow.casts, arena.rules.skills.shotgun.mana_cost), "a cast's mana shows up as cast spending")
	arena.action_time = 0
	arena.request_slot("q", {})
	await step(120)
	check(absf(arena.probe.mana_flow.upkeep - 2.0 * arena.rules.skills.bolt_cutter.upkeep_per_second) < 0.1, "a running tool's upkeep shows up as upkeep spending")
	arena.request_slot("q", {})
	arena.config.mana_regen = 2.0
	arena.state.mana = 0.0
	var regen: float = arena.probe.mana_flow.regen
	await step(60)
	check(absf(arena.probe.mana_flow.regen - regen - 2.0) < 0.1, "natural regen shows up as regen income")
	arena.config.mana_regen = 0
	arena.state.mana = 0.0
	arena.potion_slots[1] = {"id": "mana_m", "count": 1}
	arena.drink(1)
	await step(int(arena.config.potions.mana_m.seconds * 60) + 2)
	check(absf(arena.probe.mana_flow.potions - float(arena.config.potions.mana_m.mp)) < 0.2, "a mana potion shows up as potion income")
	check(arena.probe.to_dict().has("mana_flow"), "the A5 log carries the mana flow")

	# C10 potion supply.
	await fresh()
	data.potion_drops.chance.normal = 1.0
	arena.enemies.t0.hp = 1.0
	arena.strike("t0", 10.0, false, "witch", "staff")
	data.potion_drops.chance.normal = 0.08
	var dropped: Array = arena.ground_items.filter(func(loot): return loot.kind == "potion")
	check(dropped.size() == 1 and arena.potion_stash.values().all(func(count): return count == 0), "a defeated enemy leaves its potion on the ground until picked up")
	for loot in dropped:
		arena.player.position = loot.node.position
		arena.pick_up(loot)
	var stashed := 0
	for id in arena.potion_stash:
		stashed += arena.potion_stash[id]
	check(stashed == 1, "a picked-up potion enters its stash")
	arena.coins = 30
	var owned: int = arena.potion_stash.health_m
	check(arena.buy_potion("health_m") and arena.coins == 30 - int(data.potion_prices.health_m) and arena.potion_stash.health_m == owned + 1, "the trial shop sells a potion for 각인전")
	check(not arena.buy_potion("full_health") and not arena.buy_potion("health_m"), "full restores are drop-only and a purchase needs the 각인전")

	await fresh()
	arena.potion_stash.health_l = 4
	var old: Dictionary = arena.potion_slots[0].duplicate()
	arena.assign_quickslot(0, "health_l")
	check(arena.potion_slots[0].id == "health_l" and arena.potion_slots[0].count == 4 and arena.potion_stash.health_l == 0 and arena.potion_stash[old.id] == old.count, "picking a quickslot kind moves the whole stack in and the old one out")
	arena.potion_slots[0].count = 0
	arena.potion_stash.health_l = 2
	var hp: float = arena.hp
	arena.drink(0)
	check(arena.potion_stash.health_l == 2 and arena.potion_effects.is_empty(), "an empty quickslot never refills itself from the stash")
	arena.fill_quickslot(0)
	check(arena.potion_slots[0].count == 2 and arena.potion_stash.health_l == 0, "filling a quickslot by hand takes its kind from the stash")
	arena.potion_stash.mana_s = 3
	arena.reset_arena()
	check(arena.potion_stash.mana_s == 3 and arena.potion_slots[0].count == int(arena.config.potion_loadout[0].count), "the stash survives a restart and the loadout still restocks")

	# Window.
	arena.coins = 100
	arena.inventory_window.visible = true
	arena.inventory_window.mode = "potions"
	arena.inventory_window.refresh()
	var buy: Array = arena.inventory_window.find_children("*", "Button", true, false).filter(func(b): return b.text == "구매" and not b.disabled)
	buy[0].pressed.emit()
	check(arena.coins < 100, "the potion view's buy button spends 각인전")
	var picker: OptionButton = arena.inventory_window.find_child("Quickslot_3", true, false)
	var index: int = arena.config.potions.keys().find("mana_s")
	picker.select(index)
	picker.item_selected.emit(index)
	check(arena.potion_slots[3].id == "mana_s" and arena.potion_slots[3].count == 3, "the potion view's quickslot picker assigns a stack")
	arena.inventory_window.visible = false

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_mana_potions_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
