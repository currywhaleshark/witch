extends RefCounted
## Field drops (04 §4, §8): spoils/equipment rolls, ground loot placement, drop animation, labels,
## hover and walking over to pick loot up. ground_items and the loot RNG stay on the arena.
## Presentation helpers are ground_loot.gd / ground_loot_visual.gd. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func drop_spoils(grade: String, at: Vector3) -> void:
	# Keep the existing roll order and quantities; ownership changes only on pickup.
	var drop: Dictionary = arena.items.data.currency.drops.get(grade, arena.items.data.currency.drops.normal)
	if arena.loot_rng.randf() < float(drop.chance):
		drop_resource("currency", "", arena.loot_rng.randi_range(int(drop.range[0]), int(drop.range[1])), at)
	var potions: Dictionary = arena.items.data.potion_drops
	if arena.loot_rng.randf() < float(potions.chance.get(grade, 0.0)):
		var potion: String = arena.items.weighted(arena.loot_rng, potions.weights)
		drop_resource("potion", potion, 1, at)
	if arena.loot_rng.randf() < float(arena.items.data.piece_drops.get(grade, 0.0)):
		var id: String = arena.items.data.pieces.keys()[arena.loot_rng.randi_range(0, arena.items.data.pieces.size() - 1)]
		drop_resource("piece", id, 1, at)

func drop_loot(grade: String, at: Vector3) -> void:
	# Item level is the trial character level, +1 for elites and +2 for bosses (04 §4.3).
	var level: int = arena.build.level + int(arena.items.data.grade_level_bonus.get(grade, 0))
	for item in arena.items.roll_drops(arena.loot_rng, grade, level):
		drop_item(item, at + Vector3(arena.loot_rng.randf_range(-0.5, 0.5), 0, arena.loot_rng.randf_range(-0.5, 0.5)))

func drop_item(item: Dictionary, at: Vector3) -> void:
	drop_ground_loot({"kind": "equipment", "item": item, "name": item.name, "color": Color(arena.items.data.rarity_colors[item.rarity])}, at)

func drop_resource(kind: String, id: String, amount: int, at: Vector3) -> void:
	var title: String
	var color: Color
	match kind:
		"currency":
			title = "%d %s" % [amount, arena.items.data.currency.name]
			color = Arena.GOLD_FLASH
		"piece":
			title = arena.items.data.pieces[id].name
			color = Color("c9a0dc")
		"potion":
			title = arena.config.potions[id].name
			color = Arena.Hud.POTION_COLORS[arena.config.potions[id].kind]
		_:
			return
	if amount <= 0:
		return
	if kind != "currency" and amount > 1:
		title += " × %d" % amount
	drop_ground_loot({"kind": kind, "id": id, "amount": amount, "name": title, "color": color}, at)

func drop_ground_loot(payload: Dictionary, at: Vector3) -> void:
	var spot = Arena.GroundLoot.find_position(arena.map, at, arena.ground_items)
	if spot == null:
		arena.deferred_ground_items.append({"loot": payload, "at": at})
		return
	var color: Color = payload.color
	# The pickup destination stays on the floor while only the visible mesh falls and spins.
	var node := Node3D.new()
	arena.world.add_child(node)
	var rest_height := 0.05
	var visual: Node3D
	var authored := Arena.GroundLootVisual.create(node, payload)
	if not authored.is_empty():
		visual = authored.visual
		rest_height = authored.rest_height
	else:
		match payload.kind:
			"currency":
				rest_height = 0.03
				visual = Arena.Shape.cylinder(node, Vector3.ZERO, 0.16, 0.04, color)
			"piece":
				rest_height = 0.04
				visual = Arena.Shape.box(node, Vector3.ZERO, Vector3(0.2, 0.06, 0.28), color)
			"potion":
				rest_height = 0.14
				visual = Arena.Shape.cylinder(node, Vector3.ZERO, 0.12, 0.24, color, 0.075)
				Arena.Shape.cylinder(visual, Vector3(0, 0.14, 0), 0.06, 0.04, Arena.BRASS)
			_:
				visual = Arena.Shape.cylinder(node, Vector3.ZERO, 0.17, 0.08, color)
	node.position = spot + Vector3(0, rest_height, 0)
	Arena.GroundLoot.pose_drop(visual, 0.0)
	var selection := Arena.Shape.ring(node, Vector3(0, 0.06 - rest_height, 0), 0.27, Color("fff1c4"), 0.025)
	selection.visible = false
	arena.ground_items.append(payload.merged({"node": node, "visual": visual, "selection": selection, "age": 0.0}))
	arena.loot_layout.invalidate()

func tick_ground_loot(dt: float) -> void:
	if arena.paused:
		return
	var moved := false
	for loot in arena.ground_items:
		var before: float = loot.age
		loot.age = minf(Arena.GroundLoot.LABEL_SECONDS, before + dt)
		if before < Arena.GroundLoot.DROP_SECONDS:
			Arena.GroundLoot.pose_drop(loot.visual, loot.age)
			moved = true
	if moved:
		arena.loot_layout.invalidate()

func loot_labels() -> Array:
	var shown: Array = []
	for loot in arena.ground_items:
		if arena.show_all_loot_labels or loot.age < Arena.GroundLoot.LABEL_SECONDS or is_same(loot, arena.hovered_loot):
			shown.append(loot.node.get_instance_id())
	var focused: int = 0 if arena.hovered_loot.is_empty() else arena.hovered_loot.node.get_instance_id()
	return arena.loot_layout.labels(arena.ground_items, arena.camera, arena.hud.font, arena.get_viewport().get_visible_rect().size, shown, focused)

func loot_pointer_available(screen: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, arena.get_viewport().get_visible_rect().size - Vector2(0, 155)).has_point(screen):
		return false
	for window in [arena.inventory_window, arena.character_window, arena.skill_window]:
		if is_instance_valid(window) and window.is_visible_in_tree() and window.get_global_rect().has_point(screen):
			return false
	return true

func loot_at(screen: Vector2) -> Dictionary:
	return Arena.GroundLoot.pick(screen, loot_labels(), arena.ground_items, arena.camera) if loot_pointer_available(screen) else {}

func update_loot_hover(screen: Vector2) -> void:
	arena.loot_pointer = screen
	var next: Dictionary = {}
	if not arena.loading and not arena.paused and arena.hp > 0 and not arena.player_visual.field_entry_active() and arena.held_item == null and arena.held_piece == "" and not arena.inventory_window.holding_potion():
		next = loot_at(screen)
	set_hovered_loot(next)

func set_hovered_loot(next: Dictionary) -> void:
	if is_same(next, arena.hovered_loot):
		return
	for loot in [arena.hovered_loot, next]:
		if loot.is_empty() or not is_instance_valid(loot.node):
			continue
		var active := is_same(loot, next)
		var color: Color = loot.color
		Arena.GroundLootVisual.highlight(loot.visual, active, color)
		loot.selection.visible = active
	arena.hovered_loot = next

func pick_up(loot: Dictionary) -> void:
	# A click on loot walks her over to it; walking past loot never picks it up.
	arena.loot_target = loot
	tick_pickup()
	if not arena.loot_target.is_empty():
		arena.set_destination(loot.node.position)

func tick_pickup() -> void:
	if arena.loot_target.is_empty():
		return
	var loot: Dictionary = arena.loot_target
	var index: int = -1
	for i in arena.ground_items.size():
		if is_same(arena.ground_items[i], loot):
			index = i
	if index < 0:
		arena.loot_target = {}
		return
	var flat: Vector3 = loot.node.position - arena.player.position
	flat.y = 0.0
	if flat.length() > float(arena.items.data.pickup_radius):
		return
	arena.loot_target = {}
	arena.moving = false
	arena.move_marker.visible = false
	match loot.kind:
		"equipment":
			# With the inventory open it comes up on the cursor, ready to be placed or worn.
			if arena.held_item == null and is_instance_valid(arena.inventory_window) and arena.inventory_window.is_visible_in_tree():
				loot.item.erase("at")
				arena.held_item = loot.item
				arena.refresh_build_windows()
			elif not arena.stow(loot.item):
				arena.show_message("가방에 자리가 없습니다")
				return
		"currency":
			arena.coins += int(loot.amount)
		"piece":
			arena.pieces[loot.id] += int(loot.amount)
		"potion":
			if not arena.store_potion(loot.id, int(loot.amount)):
				arena.show_message("물약 가방에 자리가 없습니다")
				return
	loot.node.queue_free()
	arena.ground_items.remove_at(index)
	if is_same(arena.hovered_loot, loot):
		arena.hovered_loot = {}
	arena.loot_layout.invalidate()
	var waiting := arena.deferred_ground_items.duplicate()
	arena.deferred_ground_items.clear()
	for entry in waiting:
		drop_ground_loot(entry.loot, entry.at)
	arena.show_message(arena.items.display_name(loot.item) if loot.kind == "equipment" else loot.name + " 획득")
	arena.refresh_build_windows()
