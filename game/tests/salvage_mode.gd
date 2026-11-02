extends SceneTree
## Real inventory input: mode lifetime, rarity filtering, socket returns and field isolation.
var arena: Node3D
var window: PanelContainer
var checks: Array = []
var failures: Array = []
var output: String
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks.append(description)
	if not ok:
		failures.append(description)
		push_error(description)

func settle() -> void:
	await physics_frame
	await physics_frame

func at_view(name: String) -> Vector2:
	return window.find_child(name, true, false).get_global_rect().get_center()

func at_item(item: Dictionary) -> Vector2:
	var view: Control = window.find_child("Bag", true, false)
	return view.global_position + (Vector2(item.at) + Vector2(0.5, 0.5)) * window.CELL

func move_mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)

func click(at: Vector2, shift: bool = false, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	move_mouse(at)
	var event := InputEventMouseButton.new()
	event.position = at
	event.pressed = true
	event.button_index = button
	event.shift_pressed = shift
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await settle()

func add_item(rarity: String, slot: String = "ring") -> Dictionary:
	var item: Dictionary = arena.items.generate(rng, 30, rarity, slot)
	check(arena.stow(item), "test bag fits " + rarity + " " + slot)
	return item

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " GPU capture saved")

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/salvage_mode")
	DirAccess.make_dir_recursive_absolute(output)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await settle()
	window = arena.inventory_window
	window.toggle()
	rng.seed = 182
	var normal := add_item("normal")
	var magic := add_item("magic", "gloves")
	var rare := add_item("rare", "head")
	var rare_keep := add_item("rare", "outfit")
	var unique: Dictionary = arena.items.make_unique(rng, 30, "executioner_pulley")
	arena.stow(unique)
	normal.sockets = 1
	normal.pieces = ["bel"]
	magic.sockets = 2
	magic.pieces = ["rok", "sha"]
	var worn: Dictionary = arena.items.generate(rng, 30, "normal", "ring")
	arena.equipment.ring = worn
	arena.refresh_gear()
	await settle()
	var scrap: int = arena.scrap
	var pieces: Dictionary = arena.pieces.duplicate()
	var mana: float = arena.state.mana
	var coins: int = arena.coins
	var potions: Dictionary = arena.potion_stash.duplicate()
	var destination: Vector3 = arena.destination
	var ground: int = arena.ground_items.size()

	await click(at_item(normal), true)
	check(is_same(arena.held_item, normal) and arena.scrap == scrap, "Shift-click outside salvage mode still lifts an item")
	arena.return_held()
	await settle()
	await click(at_view("Salvage"), true)
	check(window.salvage_mode and arena.bag.size() == 5 and arena.scrap == scrap, "Shift-clicking the empty-hand anvil only enables the mode, never bulk salvages")
	await click(at_view("Salvage"))
	check(not window.salvage_mode, "clicking the active anvil disables the mode")
	await click(at_view("Salvage"))
	move_mouse(at_item(magic))
	check(is_same(window.hover, magic) and window.tip_text.text.contains("Shift+클릭"), "hovering a salvage target shows its item and bulk shortcut")
	await capture("active_hover")
	await click(at_item(normal), false, MOUSE_BUTTON_WHEEL_UP)
	check(arena.bag.size() == 5 and window.salvage_mode, "scrolling over an item cannot salvage it")
	var bag_view: Control = window.find_child("Bag", true, false)
	await click(bag_view.global_position + Vector2(9.5, 5.5) * window.CELL, true)
	check(arena.bag.size() == 5 and arena.scrap == scrap, "Shift-clicking an empty bag cell does nothing")
	var doll: Control = window.find_child("Doll", true, false)
	await click(doll.global_position + window.DOLL.ring.get_center(), true)
	check(is_same(arena.equipment.ring, worn) and arena.held_item == null and window.salvage_mode, "worn equipment is not lifted or salvaged in salvage mode")
	await click(at_item(rare))
	check(arena.bag_index(rare) == -1 and arena.scrap == scrap + 4 and window.salvage_mode and arena.held_item == null, "a normal click salvages only its selected rare item and keeps the mode active")
	# The clicked item may itself be rare: only normal/magic bag items are bulk targets.
	await click(at_item(rare_keep), true)
	check(arena.bag.size() == 2 and arena.bag_index(rare_keep) >= 0 and arena.bag_index(unique) >= 0, "Shift-click in the mode removes all normal/magic items and preserves rare/unique items")
	check(arena.scrap == scrap + 7 and arena.pieces.bel == pieces.bel + 1 and arena.pieces.rok == pieces.rok + 1 and arena.pieces.sha == pieces.sha + 1, "bulk salvage awards exact material and returns every socketed piece once")
	check(is_same(arena.equipment.ring, worn) and arena.coins == coins and arena.potion_stash == potions, "bulk salvage preserves worn equipment, currency and potions")
	await capture("after_bulk")
	await click(at_item(unique), true)
	check(arena.bag.size() == 2 and arena.scrap == scrap + 7 and window.salvage_mode, "repeating bulk salvage with no eligible items changes no items or rewards")
	await click(at_item(unique), false, MOUSE_BUTTON_RIGHT)
	check(not window.salvage_mode and arena.bag_index(unique) >= 0 and arena.equipment.medium == null, "right click exits salvage mode without equipping or salvaging its target")
	await click(at_item(unique))
	check(is_same(arena.held_item, unique), "ordinary click-to-hold resumes after mode cancellation")
	await click(at_view("Salvage"))
	check(arena.held_item == null and not window.salvage_mode and arena.scrap == scrap + 13, "placing a held item on the anvil still salvages it without enabling the mode")
	check(arena.ground_items.size() == ground and arena.hold.is_empty() and arena.windup.is_empty() and arena.state.mana == mana and arena.destination == destination, "all salvage mouse input stays out of field movement, attacks, casts and drops")

	await click(at_view("Salvage"))
	await click(at_view("Piece_bel"))
	check(not window.salvage_mode and arena.held_piece == "bel", "choosing a name piece leaves salvage mode for socketing")
	await click(at_view("Salvage"))
	check(window.salvage_mode and arena.held_piece == "", "enabling salvage mode puts the selected name piece back")
	var bench_button: Button
	for node in window.find_children("*", "Button", true, false):
		if node.text == "작업대":
			bench_button = node
	await click(bench_button.get_global_rect().get_center())
	check(window.mode == "bench" and not window.salvage_mode, "switching inventory tabs clears salvage mode")
	window.mode = "bag"
	window.refresh()
	await settle()
	await click(at_view("Salvage"))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_I
	key.pressed = true
	root.push_input(key, true)
	check(not window.visible and not window.salvage_mode, "closing inventory with I clears salvage mode")
	key.pressed = false
	root.push_input(key, true)
	window.toggle()
	await settle()
	check(not window.salvage_mode, "reopening inventory starts in normal item mode")
	await click(at_view("Salvage"))
	arena.reset_arena()
	check(not window.salvage_mode and arena.bag_index(rare_keep) >= 0, "restarting clears the mode while keeping surviving bag items")

	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("SALVAGE_MODE_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
