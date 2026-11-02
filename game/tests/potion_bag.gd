extends SceneTree
## Actual inventory clicks, stack conservation, field isolation and bounded bag ownership.
var arena: Node3D
var window: PanelContainer
var checks: Array = []
var failures: Array = []
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error(label)

func settle() -> void:
	await physics_frame
	await physics_frame

func click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await settle()

func cell(quick: bool, index: int) -> Vector2:
	return window.find_child(("Quickslot_" if quick else "PotionCell_") + str(index), true, false).get_global_rect().get_center()

func bag(id: String) -> Vector2:
	return cell(false, arena.potion_cells.find(id))

func tab(caption: String) -> void:
	for node in window.find_children("*", "Button", true, false):
		if node.text == caption:
			await click(node.get_global_rect().get_center())
			return

func totals() -> Dictionary:
	var all: Dictionary = arena.potion_stash.duplicate()
	for slot in arena.potion_slots:
		all[slot.id] = int(all.get(slot.id, 0)) + slot.count
	return all

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	window.set_hover(null)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " GPU capture saved")

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/potion_bag")
	DirAccess.make_dir_recursive_absolute(output)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await settle()
	window = arena.inventory_window
	window.toggle()
	arena.store_potion("health_s", 7)
	arena.store_potion("mana_l", 11)
	arena.store_potion("full_rejuv", 2)
	arena.coins = 300
	await settle()
	await tab("물약")
	var grid: Control = window.find_child("PotionBag", true, false)
	var slots: Control = window.find_child("PotionQuickslots", true, false)
	check(window.mode == "potions" and grid.get_child_count() == 15 and slots.get_child_count() == 4, "the potion tab shows fifteen bag cells and four quickslots")
	check(slots.global_position.y >= grid.get_global_rect().end.y and grid.columns == 5, "the four slots sit below a five-column three-row bag")
	await capture("bag_and_slots")
	var owned := totals()
	var hp: float = arena.hp
	var mana: float = arena.state.mana
	var destination: Vector3 = arena.destination
	await click(bag("health_s"))
	check(window.holding_potion() and arena.potion_stash.health_s == 7, "lifting a bag stack reserves its source without losing ownership")
	await click(cell(true, 0))
	check(not window.holding_potion() and arena.potion_slots[0] == {"id": "health_s", "count": 7} and arena.potion_stash.health_m == 5 and arena.potion_stash.health_s == 0, "placing a bag stack into a quickslot moves all seven and returns the old five")
	await click(bag("mana_l"))
	await click(cell(false, 14))
	check(arena.potion_cells[14] == "mana_l" and arena.potion_stash.mana_l == 11, "a stack can move to the fifteenth cell")
	var full_cell: int = arena.potion_cells.find("full_rejuv")
	await click(cell(false, 14))
	await click(cell(false, full_cell))
	check(arena.potion_cells[14] == "full_rejuv" and arena.potion_cells[full_cell] == "mana_l", "occupied bag cells swap positions without changing counts")
	await click(cell(true, 0))
	await click(cell(false, 13))
	check(arena.potion_slots[0].count == 0 and arena.potion_cells[13] == "health_s" and arena.potion_stash.health_s == 7, "a quickslot stack returns to the chosen empty bag cell")
	await click(bag("health_s"))
	await click(cell(true, 1))
	await click(cell(true, 1))
	await click(cell(true, 0))
	check(arena.potion_slots[0].count == 7 and arena.potion_slots[1].count == 0 and arena.potion_stash.mana_m == 5, "moving between same-kind quickslots merges without restocking the source")
	await click(cell(true, 0))
	await click(cell(true, 3))
	check(arena.potion_slots[0].id == "speed" and arena.potion_slots[3].id == "health_s", "different quickslot kinds swap with their full counts")
	await click(cell(true, 3))
	await click(bag("full_rejuv"))
	check(arena.potion_slots[3] == {"id": "full_rejuv", "count": 2} and arena.potion_stash.health_s == 7 and arena.potion_cells[14] == "health_s", "a quickslot dropped onto a different bag stack exchanges both stacks")
	check(totals() == owned, "all bag and quickslot moves conserve every potion kind")
	await capture("rearranged")

	await click(bag("mana_l"))
	await click(cell(true, 2), MOUSE_BUTTON_RIGHT)
	check(not window.holding_potion() and totals() == owned, "right click cancels the hand without consuming or transferring potions")
	await click(bag("mana_l"))
	await click(Vector2(60, 420))
	check(not window.holding_potion() and totals() == owned and arena.ground_items.is_empty(), "clicking outside cancels the potion hand without dropping anything")
	await click(bag("mana_l"))
	await tab("가방")
	check(not window.holding_potion() and window.mode == "bag" and totals() == owned, "switching tabs cancels a potion selection without loss")
	await tab("물약")
	await click(bag("mana_l"))
	window.toggle()
	window.toggle()
	await settle()
	check(not window.holding_potion() and totals() == owned, "closing and reopening the window cannot lose a selected stack")
	check(arena.hp == hp and arena.state.mana == mana and arena.potion_effects.is_empty() and arena.hold.is_empty() and arena.windup.is_empty() and arena.destination == destination, "inventory clicks never drink, attack, cast or move on the field")

	var buy: Array = window.find_children("*", "Button", true, false).filter(func(b): return b.text == "구매" and not b.disabled)
	var money: int = arena.coins
	await click(buy[0].get_global_rect().get_center())
	check(arena.coins == money - 10 and arena.potion_stash.health_s == 8, "the retained trial shop buys into the existing bag stack")
	check(not arena.buy_potion("full_rejuv"), "drop-only full restore potions remain unavailable to buy")
	await click(bag("health_s"))
	await click(cell(true, 1))
	arena.store_potion("health_s", 3)
	arena.refresh_build_windows()
	await settle()
	await click(bag("health_s"))
	await click(cell(true, 1))
	check(arena.potion_slots[1].count == 11 and arena.potion_stash.health_s == 0, "placing the same kind in a loaded slot merges its stacks")
	# The source can change during combat: use the current quantity, never the lifted copy.
	await click(cell(true, 3))
	arena.drink(3)
	await click(cell(false, 12))
	check(arena.potion_stash.full_rejuv == 1 and arena.potion_slots[3].count == 0, "drinking while a slot is selected transfers only the remaining quantity")
	await click(bag("full_rejuv"))
	await click(cell(true, 3))
	arena.potion_cooldowns.clear()
	await click(cell(true, 3))
	arena.drink(3)
	await settle()
	check(not window.holding_potion(), "consuming the last selected potion clears the hand")
	arena.store_potion("full_rejuv", 2)
	arena.drink(3)
	check(arena.potion_slots[3].count == 0 and arena.potion_stash.full_rejuv == 2, "an empty slot never automatically refills from the bag")
	await click(bag("mana_l"))
	var stash: Dictionary = arena.potion_stash.duplicate()
	var positions: Array = arena.potion_cells.duplicate()
	arena.reset_arena()
	check(not window.holding_potion() and arena.potion_stash == stash and arena.potion_cells == positions, "restart cancels the hand and preserves the bag's quantities and positions")

	# Fill all fifteen kinds with test-only definitions to exercise the capacity boundary.
	for id in arena.potion_stash:
		arena.potion_stash[id] = 0
	for i in 3:
		var id := "capacity_test_%d" % i
		arena.config.potions[id] = arena.config.potions.health_s.duplicate()
		arena.potion_stash[id] = 0
		arena.items.data.potion_prices[id] = 10
	var ids: Array = arena.config.potions.keys()
	for i in 15:
		check(arena.store_potion(ids[i], 1), "capacity cell %d accepts one kind" % (i + 1))
	check(arena.store_potion(ids[0], 999) and arena.potion_stash[ids[0]] == 1000, "a full bag still accepts an unlimited existing-kind stack")
	money = arena.coins
	check(not arena.buy_potion(ids[15]) and arena.coins == money, "a new sixteenth kind cannot be bought or charged when the bag is full")
	arena.drop_resource("potion", ids[15], 1, arena.player.position)
	var loot: Dictionary = arena.ground_items[-1]
	arena.player.position = loot.node.position
	arena.pick_up(loot)
	check(arena.ground_items.has(loot) and arena.potion_stash[ids[15]] == 0, "a potion that cannot fit stays on the ground")
	# A swap at capacity frees its source cell, so it must still return the old quickslot kind.
	arena.potion_slots[0] = {"id": ids[15], "count": 4}
	check(arena.assign_quickslot(0, ids[0]) and arena.potion_slots[0].count == 1000 and arena.potion_stash[ids[15]] == 4, "assigning from a full bag swaps in the old slot kind without loss")
	arena.pick_up(loot)
	check(not arena.ground_items.has(loot) and arena.potion_stash[ids[15]] == 5, "ground pickup merges into an existing stack even with all fifteen cells occupied")

	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("POTION_BAG_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
