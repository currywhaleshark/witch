extends PanelContainer
## Temporary grid inventory (I), in the old action-RPG way: the seven worn slots on a paper doll
## over a 10x6 bag in which every item takes cells by its slot (items.json slot_sizes).
## Click lifts an item onto the cursor and click puts it down (a single item under it swaps), on
## its own slot wears it; right-click wears or takes off at once. A name piece lifts from the
## pouch and clicks into a free socket of a worn or bag item; a click outside the window drops
## the held item at her feet. Hovering shows the item and, for a bag item, what is worn in that
## slot now. Words stay off the window: pictures, numbers and hover tips carry it. The workbench view re-rolls one option and removes
## pieces for 각인전; the potion view keeps the stash, shop and quickslots.
const ItemIcon = preload("res://scripts/item_icon.gd")
const PANEL = Color("172b34")
const EDGE = Color("526166")
const PAPER = Color("e3e9df")
const MUTED = Color("9aadaf")
const GOLD = Color("d8b77b")
const GOOD = Color("6fae7a")
const BAD = Color("c25b5b")
const CELL = 36
const POTION_CELL = 72
const POTION_COLUMNS = 5
# Where each worn slot sits on the paper doll, in pixels over the bag's width.
const DOLL = {
	"head": Rect2(144, 0, 72, 72), "brooch": Rect2(234, 18, 36, 36),
	"medium": Rect2(54, 54, 72, 108), "outfit": Rect2(144, 84, 72, 108), "ring": Rect2(234, 120, 36, 36),
	"gloves": Rect2(54, 174, 72, 72), "shoes": Rect2(234, 174, 72, 72)}

var arena: Node
var body: VBoxContainer
var mode := "bag"
var salvage_mode := false
var held_potion: Dictionary = {}
var hover = null
var hover_compare := false
var tip: PanelContainer
var tip_text: RichTextLabel
var hand: Control
var views: Array = []

func setup(owner: Node) -> void:
	arena = owner
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	add_theme_stylebox_override("panel", frame_style(0.96, 14))
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	# The hand and the tooltip float above everything and never take the mouse.
	hand = Control.new()
	hand.top_level = true
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.draw.connect(draw_hand)
	add_child(hand)
	tip = PanelContainer.new()
	tip.top_level = true
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.add_theme_stylebox_override("panel", frame_style(0.97, 8))
	tip_text = RichTextLabel.new()
	tip_text.bbcode_enabled = true
	tip_text.fit_content = true
	tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	tip_text.scroll_active = false
	tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_text.add_theme_font_size_override("normal_font_size", 13)
	tip.add_child(tip_text)
	add_child(tip)
	refresh()

func frame_style(alpha: float, margin: int) -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(PANEL, alpha)
	frame.border_color = EDGE
	frame.set_border_width_all(1)
	frame.set_content_margin_all(margin)
	return frame

func toggle() -> void:
	visible = not visible
	if not visible:
		salvage_mode = false
		clear_potion_hand()
		arena.return_held()
		set_hover(null)
	refresh()

func _process(_delta: float) -> void:
	if not visible:
		return
	hand.size = get_viewport_rect().size
	hand.position = Vector2.ZERO
	hand.queue_redraw()
	if mode == "potions":
		holding_potion()
		# Drinking with 1-4 changes counts without rebuilding the inventory.
		for view in views:
			view.queue_redraw()
	if tip.visible:
		var mouse := get_viewport().get_mouse_position()
		var spot := mouse + Vector2(18, 12)
		var screen := get_viewport_rect().size
		tip.reset_size()
		if spot.x + tip.size.x > screen.x:
			spot.x = mouse.x - tip.size.x - 12
		spot.y = clampf(spot.y, 0, maxf(0, screen.y - tip.size.y))
		tip.position = spot

func text(value: String, color: Color = PAPER, size_px: int = 14) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size_px)
	return label

func small_button(caption: String, action: Callable, enabled: bool = true, tip_line: String = "") -> Button:
	var b := Button.new()
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = tip_line
	b.pressed.connect(func():
		action.call()
		arena.refresh_build_windows())
	return b

func refresh() -> void:
	if body == null:
		return
	if mode != "bag":
		salvage_mode = false
	if mode != "potions":
		clear_potion_hand()
	set_hover(null)
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	views.clear()
	var data: Dictionary = arena.items.data
	var tabs := HBoxContainer.new()
	tabs.add_child(small_button("가방", func(): select_mode("bag"), mode != "bag"))
	tabs.add_child(small_button("작업대", func(): select_mode("bench"), mode != "bench"))
	tabs.add_child(small_button("물약", func(): select_mode("potions"), mode != "potions"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	var wallet := canvas_view("Wallet", Vector2(150, 28), draw_wallet, func(_view, _event): pass)
	wallet.tooltip_text = "%s %d\n%s %d" % [data.currency.name, arena.coins, data.crafting.material_name, arena.scrap]
	tabs.add_child(wallet)
	body.add_child(tabs)
	if mode == "bench":
		body.add_child(bench())
	elif mode == "potions":
		body.add_child(potion_view())
	else:
		arena.arrange_bag()
		body.add_child(doll_view())
		body.add_child(pouch_row())
		body.add_child(bag_view())
	reset_size()
	# On the right edge, so it sits beside the character window (C) on the left.
	position = Vector2(get_viewport_rect().size.x - size.x - 24, 84)

func select_mode(next: String) -> void:
	clear_potion_hand()
	if next == "potions":
		arena.return_held()
	mode = next

func canvas_view(view_name: String, size_px: Vector2, painter: Callable, handler: Callable) -> Control:
	var view := Control.new()
	view.name = view_name
	view.custom_minimum_size = size_px
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.draw.connect(func(): painter.call(view))
	# Clicks are accepted before they are handled: handling one rebuilds the window, and a view
	# already out of the tree can no longer stop the click from reaching the field, where it
	# would attack or drop the item just lifted.
	view.gui_input.connect(func(event):
		if event is InputEventMouseButton:
			view.accept_event()
			if salvage_mode and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				set_salvage_mode(false)
				return
		handler.call(view, event))
	view.mouse_exited.connect(func():
		set_hover(null)
		view.queue_redraw())
	views.append(view)
	return view

# Paper doll.
func doll_view() -> Control:
	return canvas_view("Doll", Vector2(arena.bag_grid().x * CELL, 246), draw_doll, doll_input)

func slot_at(point: Vector2) -> String:
	for slot in DOLL:
		if DOLL[slot].has_point(point):
			return slot
	return ""

func draw_doll(view: Control) -> void:
	var mouse := view.get_local_mouse_position()
	for slot in DOLL:
		var rect: Rect2 = DOLL[slot]
		view.draw_rect(rect, Color("0d181d"))
		var edge := EDGE
		if arena.held_item != null and rect.has_point(mouse):
			edge = GOOD if arena.held_item.slot == slot else BAD
		elif arena.held_item != null and arena.held_item.slot == slot:
			edge = GOLD
		view.draw_rect(rect, edge, false, 1.0)
		var worn = arena.equipment[slot]
		if worn != null:
			ItemIcon.draw(view, rect, worn, arena.items)
		else:
			ItemIcon.silhouette(view, rect, slot)

func doll_input(view: Control, event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var slot := slot_at(event.position)
		set_hover(arena.equipment[slot] if slot != "" else null, false)
		view.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var slot := slot_at(event.position)
		if slot != "":
			click_slot(slot, event.button_index == MOUSE_BUTTON_RIGHT)

func click_slot(slot: String, right: bool = false) -> void:
	if salvage_mode:
		return
	# Left: put a held piece in, wear the held item, or lift the worn one. Right: take it off.
	var worn = arena.equipment[slot]
	if right:
		if arena.held_piece != "":
			arena.held_piece = ""
		elif arena.held_item == null and worn != null:
			arena.unequip(slot)
	elif arena.held_piece != "":
		if worn != null:
			arena.socket_into(worn, arena.held_piece)
	elif arena.held_item != null:
		if arena.held_item.slot == slot:
			arena.wear_held()
	elif worn != null:
		arena.take_worn(slot)
	set_hover(null)
	arena.refresh_build_windows()

# Bag grid.
func bag_view() -> Control:
	return canvas_view("Bag", Vector2(arena.bag_grid()) * CELL, draw_bag, bag_input)

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))

func item_at(cell: Vector2i):
	var under: Array = arena.bag_under(Rect2i(cell, Vector2i.ONE))
	return under[0] if not under.is_empty() else null

func held_origin(point: Vector2) -> Vector2i:
	# The held item is centred on the cursor, so it lands on the cells it is drawn over.
	var size: Vector2i = arena.items.size_of(arena.held_item)
	return Vector2i(roundi(point.x / CELL - size.x / 2.0), roundi(point.y / CELL - size.y / 2.0))

func draw_bag(view: Control) -> void:
	var grid: Vector2i = arena.bag_grid()
	view.draw_rect(Rect2(Vector2.ZERO, Vector2(grid) * CELL), Color("0d181d"))
	for x in grid.x + 1:
		view.draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, grid.y * CELL), Color(EDGE, 0.45))
	for y in grid.y + 1:
		view.draw_line(Vector2(0, y * CELL), Vector2(grid.x * CELL, y * CELL), Color(EDGE, 0.45))
	var mouse := view.get_local_mouse_position()
	if arena.held_item != null and Rect2(Vector2.ZERO, view.size).has_point(mouse):
		# Where it would land: green when it fits or swaps one item, red otherwise.
		var cells := Rect2i(held_origin(mouse), arena.items.size_of(arena.held_item))
		var fits: bool = Rect2i(Vector2i.ZERO, grid).encloses(cells) and arena.bag_under(cells).size() <= 1
		view.draw_rect(Rect2(Vector2(cells.position) * CELL, Vector2(cells.size) * CELL), Color(GOOD if fits else BAD, 0.3))
	for item in arena.bag:
		if item.has("at"):
			var rect := Rect2(Vector2(item.at) * CELL, Vector2(arena.items.size_of(item)) * CELL)
			ItemIcon.draw(view, rect, item, arena.items)
			if salvage_mode and is_same(item, hover):
				view.draw_rect(rect.grow(-1), Color(BAD, 0.2))
				view.draw_rect(rect.grow(-1), BAD, false, 2.0)

func bag_input(view: Control, event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		set_hover(item_at(cell_at(event.position)), true)
		view.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
		var cell: Vector2i = held_origin(event.position) if arena.held_item != null and not right else cell_at(event.position)
		click_bag(cell, right, event.shift_pressed)

func click_bag(cell: Vector2i, right: bool = false, bulk: bool = false) -> void:
	# With an item held, cell is where its top-left corner goes; otherwise the cell clicked.
	var item = item_at(cell)
	if salvage_mode:
		if right:
			set_salvage_mode(false)
		elif item != null:
			if bulk:
				arena.salvage_below_rare()
			else:
				arena.salvage(arena.bag_index(item))
		return
	if right:
		if arena.held_piece != "":
			arena.held_piece = ""
		elif arena.held_item == null and item != null:
			arena.equip(arena.bag_index(item))
	elif arena.held_piece != "":
		if item != null:
			arena.socket_into(item, arena.held_piece)
	elif arena.held_item != null:
		arena.put_in_bag(cell)
	elif item != null:
		arena.take_from_bag(item)
	set_hover(null)
	arena.refresh_build_windows()

# Name pieces and the salvage anvil.
func pouch_row() -> HBoxContainer:
	var data: Dictionary = arena.items.data
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	for id in data.pieces:
		var chip := canvas_view("Piece_" + id, Vector2(CELL + 22, CELL), func(view): draw_piece(view, id),
			func(view, event): piece_input(view, event, id))
		chip.tooltip_text = "\n".join(arena.items.describe_piece(id))
		line.add_child(chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(gap)
	var gain: Dictionary = data.crafting.salvage
	var salvage := canvas_view("Salvage", Vector2(CELL * 1.5, CELL), draw_salvage, salvage_input)
	salvage.tooltip_text = "분해 → %s %d·%d·%d·%d" % [data.crafting.material_name,
		int(gain.normal), int(gain.magic), int(gain.rare), int(gain.unique)]
	salvage.tooltip_text += "\n클릭: 분해 모드 %s\n든 아이템을 놓으면 분해\n분해 모드에서 아이템 Shift+클릭: 일반·마법 일괄 분해" % ("종료" if salvage_mode else "시작")
	line.add_child(salvage)
	return line

func draw_piece(view: Control, id: String) -> void:
	var count: int = arena.pieces[id]
	var rect := Rect2(Vector2.ZERO, Vector2(CELL, CELL))
	view.draw_rect(rect, Color("0d181d"))
	view.draw_rect(rect, GOLD if arena.held_piece == id else EDGE, false, 1.0)
	ItemIcon.piece(view, rect, arena.items.glyph(id), count > 0)
	view.draw_string(get_theme_default_font(), Vector2(CELL + 3, CELL * 0.65), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PAPER if count > 0 else MUTED)

func piece_input(view: Control, event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		click_piece(id)

func click_piece(id: String) -> void:
	# Lifts one kind of piece (clicking it again puts it back); an item in the hand blocks it.
	if arena.held_item != null:
		return
	salvage_mode = false
	arena.held_piece = "" if arena.held_piece == id or arena.pieces[id] <= 0 else id
	arena.refresh_build_windows()

func draw_salvage(view: Control) -> void:
	var rect := Rect2(Vector2.ZERO, view.size)
	var active: bool = arena.held_item != null
	view.draw_rect(rect, Color(BAD, 0.2) if salvage_mode else Color("0d181d"))
	var edge := BAD if salvage_mode else (GOLD if active and rect.has_point(view.get_local_mouse_position()) else EDGE)
	view.draw_rect(rect, edge, false, 2.0 if salvage_mode else 1.0)
	ItemIcon.anvil(view, rect.grow(-6), BAD if salvage_mode else (PAPER if active else MUTED))

func set_salvage_mode(enabled: bool) -> void:
	salvage_mode = enabled
	if enabled:
		arena.held_piece = ""
	refresh()

func salvage_input(view: Control, event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		view.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if arena.held_item != null:
			arena.salvage_held()
		else:
			set_salvage_mode(not salvage_mode)

func draw_wallet(view: Control) -> void:
	# 각인전 as a coin and material as a gear, numbers only; the names are in the hover tip.
	var font := get_theme_default_font()
	var y := view.size.y / 2
	view.draw_circle(Vector2(10, y), 7, GOLD)
	view.draw_arc(Vector2(10, y), 4, 0, TAU, 12, Color(PANEL, 0.8), 1.5)
	view.draw_string(font, Vector2(22, y + 5), str(arena.coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
	ItemIcon.gear(view, Rect2(Vector2(78, y - 8), Vector2(16, 16)), MUTED)
	view.draw_string(font, Vector2(98, y + 5), str(arena.scrap), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PAPER)

# Hand and tooltip.
func draw_hand() -> void:
	var mouse := get_viewport().get_mouse_position()
	if holding_potion():
		var stack := potion_stack(held_potion.quick, held_potion.index)
		if stack.count > 0 and stack.id == held_potion.id:
			ItemIcon.potion(hand, Rect2(mouse - Vector2.ONE * POTION_CELL / 2, Vector2.ONE * POTION_CELL), arena.config.potions[stack.id], stack.count, 1.0, stack.id)
	elif arena.held_item != null:
		var size := Vector2(arena.items.size_of(arena.held_item)) * CELL
		ItemIcon.draw(hand, Rect2(mouse - size / 2, size), arena.held_item, arena.items)
	elif arena.held_piece != "":
		ItemIcon.piece(hand, Rect2(mouse - Vector2(CELL, CELL) / 2, Vector2(CELL, CELL)), arena.items.glyph(arena.held_piece))
	elif salvage_mode and get_global_rect().has_point(mouse):
		ItemIcon.anvil(hand, Rect2(mouse + Vector2(10, 10), Vector2(20, 20)), BAD)

func set_hover(item, compare: bool = false) -> void:
	if item == null or arena.held_item != null:
		hover = null
		tip.visible = false
		return
	if is_same(item, hover) and compare == hover_compare:
		return
	hover = item
	hover_compare = compare
	tip_text.text = tooltip_bbcode(item, compare)
	tip.visible = true

func tooltip_lines(item: Dictionary, compare: bool) -> PackedStringArray:
	var lines: PackedStringArray = arena.items.describe(item)
	var worn = arena.equipment[item.slot]
	if compare and worn != null:
		lines.append("")
		lines.append("— 지금 착용 —")
		lines.append_array(arena.items.describe(worn))
	return lines

func tooltip_bbcode(item: Dictionary, compare: bool) -> String:
	# Item names in their rarity colour, the true name block in violet.
	var lines := tooltip_lines(item, compare)
	var worn = arena.equipment[item.slot]
	var out: PackedStringArray = []
	var names := [arena.items.display_name(item)]
	var colors := [Color(arena.items.data.rarity_colors[item.rarity])]
	if worn != null:
		names.append(arena.items.display_name(worn))
		colors.append(Color(arena.items.data.rarity_colors[worn.rarity]))
	var name_index := 0
	for line in lines:
		var safe: String = line.replace("[", "[lb]")
		if name_index < names.size() and line == names[name_index] and (name_index == 0 or compare):
			out.append("[color=#%s][b]%s[/b][/color]" % [colors[name_index].to_html(false), safe])
			name_index += 1
		elif line.begins_with("진명") or line.begins_with("— "):
			out.append("[color=#c9b2ea]%s[/color]" % safe)
		else:
			out.append(safe)
	if salvage_mode and compare:
		out.append("[color=#%s]클릭: 분해\nShift+클릭: 일반·마법 일괄 분해\n우클릭: 분해 모드 종료[/color]" % BAD.to_html(false))
	return "\n".join(out)

func potion_view() -> VBoxContainer:
	# Fifteen stacked bag cells, four physical quickslots, then the existing trial shop.
	arena.arrange_potions()
	var potions: Dictionary = arena.config.potions
	var prices: Dictionary = arena.items.data.potion_prices
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 10)
	var bag_grid := GridContainer.new()
	bag_grid.name = "PotionBag"
	bag_grid.columns = POTION_COLUMNS
	bag_grid.add_theme_constant_override("h_separation", 0)
	bag_grid.add_theme_constant_override("v_separation", 0)
	for index in arena.POTION_BAG_CAPACITY:
		bag_grid.add_child(potion_cell(false, index))
	view.add_child(bag_grid)
	var centered := CenterContainer.new()
	var slots := HBoxContainer.new()
	slots.name = "PotionQuickslots"
	slots.add_theme_constant_override("separation", 6)
	for index in arena.potion_slots.size():
		slots.add_child(potion_cell(true, index))
	centered.add_child(slots)
	view.add_child(centered)
	view.add_child(HSeparator.new())
	var shop := ScrollContainer.new()
	shop.name = "PotionShop"
	shop.custom_minimum_size = Vector2(POTION_COLUMNS * POTION_CELL, 170)
	shop.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in potions:
		grid.add_child(text("%s ×%d" % [potions[id].name, arena.potion_stash[id]]))
		var price: int = int(prices.get(id, 0))
		grid.add_child(text("%d전" % price if price > 0 else "—", MUTED, 13))
		grid.add_child(small_button("구매", func(): arena.buy_potion(id), price > 0 and arena.coins >= price))
	shop.add_child(grid)
	view.add_child(shop)
	return view

func holding_potion() -> bool:
	if held_potion.is_empty():
		return false
	var stack := potion_stack(held_potion.quick, held_potion.index)
	if stack.count <= 0 or stack.id != held_potion.id:
		clear_potion_hand()
		return false
	return true

func clear_potion_hand() -> void:
	held_potion.clear()
	if is_instance_valid(tip):
		tip.visible = false

func potion_stack(quick: bool, index: int) -> Dictionary:
	if quick:
		return arena.potion_slots[index]
	var id: String = arena.potion_cells[index]
	return {"id": id, "count": int(arena.potion_stash.get(id, 0))}

func potion_cell(quick: bool, index: int) -> Control:
	return canvas_view(("Quickslot_" if quick else "PotionCell_") + str(index), Vector2.ONE * POTION_CELL,
		func(view): draw_potion_cell(view, quick, index),
		func(view, event): potion_input(view, event, quick, index))

func draw_potion_cell(view: Control, quick: bool, index: int) -> void:
	var rect := Rect2(Vector2.ZERO, Vector2.ONE * POTION_CELL).grow(-1)
	var stack := potion_stack(quick, index)
	var selected: bool = holding_potion() and held_potion.quick == quick and held_potion.index == index
	var under_mouse := rect.has_point(view.get_local_mouse_position())
	view.draw_rect(rect, Color("0d181d"))
	view.draw_rect(rect, GOLD if selected or under_mouse else EDGE, false, 2.0 if selected else 1.0)
	if stack.count > 0:
		ItemIcon.potion(view, rect, arena.config.potions[stack.id], stack.count, 0.3 if selected else 1.0, stack.id)
	if quick:
		view.draw_string(get_theme_default_font(), Vector2(6, 16), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)

func potion_input(view: Control, event: InputEvent, quick: bool, index: int) -> void:
	if event is InputEventMouseMotion:
		var stack := potion_stack(quick, index)
		set_hover(null)
		if not holding_potion():
			var lines := "%d번 물약 슬롯" % (index + 1) if quick else "물약 가방"
			if stack.count > 0:
				lines = "%s ×%d\n클릭: 묶음 집기" % [arena.config.potions[stack.id].name, stack.count]
			else:
				lines += "\n물약 묶음을 집어 여기에 놓기"
			tip_text.text = lines
			tip.visible = true
		view.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			clear_potion_hand()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			click_potion(quick, index)

func click_potion(quick: bool, index: int) -> void:
	if arena.held_item != null or arena.held_piece != "":
		return
	if not holding_potion():
		var stack := potion_stack(quick, index)
		if stack.count > 0:
			# Reserve a source, not a second owned stack; cancel/close cannot lose a potion.
			held_potion = {"quick": quick, "index": index, "id": stack.id}
			tip.visible = false
		return
	var source := held_potion.duplicate()
	var stack := potion_stack(source.quick, source.index)
	clear_potion_hand()
	if stack.count <= 0 or stack.id != source.id:
		return
	if quick:
		if source.quick:
			arena.move_potion_quickslot(source.index, index)
		else:
			arena.assign_quickslot(index, source.id)
	elif source.quick:
		arena.put_quickslot_in_bag(source.index, index)
	else:
		arena.move_potion_cell(source.index, index)

func bench() -> ScrollContainer:
	# Worn items only: re-roll one option, or pay to take the last piece back out.
	var data: Dictionary = arena.items.data
	var craft: Dictionary = data.crafting
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(arena.bag_grid().x * CELL, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	var reroll_cost := "%d전 + %s %d" % [int(craft.reroll_coins), craft.material_name, int(craft.reroll_material)]
	for slot in data.slots:
		var item = arena.equipment[slot]
		if item == null:
			continue
		var head := HBoxContainer.new()
		var name := text(arena.items.display_name(item), Color(data.rarity_colors[item.rarity]))
		name.tooltip_text = "\n".join(arena.items.describe(item))
		name.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(name)
		if int(item.get("sockets", 0)) > 0:
			head.add_child(small_button("빼기", func(): arena.unsocket(slot), not item.pieces.is_empty() and arena.coins >= int(craft.unsocket_coins), "마지막 조각 빼기 · %d전" % int(craft.unsocket_coins)))
		list.add_child(head)
		var can_pay: bool = arena.coins >= int(craft.reroll_coins) and arena.scrap >= int(craft.reroll_material)
		for index in item.affixes.size():
			var affix: Dictionary = item.affixes[index]
			var caption: String = "  ↻ %s %s" % [["I", "II", "III"][affix.tier], arena.items.option_text(affix.id, affix.value)]
			list.add_child(small_button(caption, func(): arena.reroll(slot, index), can_pay, "다시 굴림 · " + reroll_cost))
	scroll.add_child(list)
	return scroll
