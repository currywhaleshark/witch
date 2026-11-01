extends PanelContainer
## Temporary inventory (I) for the C4-C6 item trial: the seven worn slots and the bag.
## Click a bag item to wear it (the worn one goes back to the bag), a worn item to take it off.
## Hovering shows its options and, for a bag item, what is worn in that slot now.
## The workbench view (C7/C8) socket name pieces into worn items, removes them for 각인전,
## re-rolls one option, and the bag view salvages items into material.
const PANEL = Color("172b34")
const EDGE = Color("526166")
const PAPER = Color("e3e9df")
const MUTED = Color("9aadaf")
const GOLD = Color("d8b77b")

var arena: Node
var body: VBoxContainer
var mode := "bag"

func setup(owner: Node) -> void:
	arena = owner
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(PANEL, 0.96)
	frame.border_color = EDGE
	frame.set_border_width_all(1)
	frame.set_content_margin_all(14)
	add_theme_stylebox_override("panel", frame)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	refresh()

func toggle() -> void:
	visible = not visible
	refresh()

func text(value: String, color: Color = PAPER, size_px: int = 14) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size_px)
	return label

func small_button(caption: String, action: Callable, enabled: bool = true, tip: String = "") -> Button:
	var b := Button.new()
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = tip
	b.pressed.connect(func():
		action.call()
		arena.refresh_build_windows())
	return b

func item_button(item: Dictionary, action: Callable, compare: bool) -> Button:
	var b := Button.new()
	b.text = item.name
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = 230
	b.add_theme_color_override("font_color", Color(arena.items.data.rarity_colors[item.rarity]))
	var tip: PackedStringArray = arena.items.describe(item)
	var worn = arena.equipment[item.slot]
	if compare and worn != null:
		tip.append("")
		tip.append("— 지금 착용 —")
		tip.append_array(arena.items.describe(worn))
	b.tooltip_text = "\n".join(tip)
	b.pressed.connect(func():
		action.call()
		arena.refresh_build_windows())
	return b

func refresh() -> void:
	if body == null:
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var data: Dictionary = arena.items.data
	body.add_child(text("인벤토리  (I)   ·   G 아이템 · Shift+G 고유 · Ctrl+G 조각·각인전 (시험용)", PAPER, 17))
	body.add_child(HBoxContainer.new())
	body.get_child(-1).add_child(small_button("가방", func(): mode = "bag", mode != "bag"))
	body.get_child(-1).add_child(small_button("작업대", func(): mode = "bench", mode != "bench"))
	body.get_child(-1).add_child(text("   %s %d · %s %d" % [data.currency.name, arena.coins, data.crafting.material_name, arena.scrap], GOLD))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)

	var worn_list := VBoxContainer.new()
	worn_list.add_child(text("장비 (누르면 벗기)", MUTED))
	for slot in data.slots:
		var line := HBoxContainer.new()
		var name_label := text(data.slot_names[slot], MUTED, 13)
		name_label.custom_minimum_size.x = 84
		line.add_child(name_label)
		var item = arena.equipment[slot]
		if item == null:
			line.add_child(text("—", MUTED))
		else:
			line.add_child(item_button(item, func(): arena.unequip(slot), false))
		worn_list.add_child(line)
	columns.add_child(worn_list)

	if mode == "bench":
		columns.add_child(bench())
		reset_size()
		position = Vector2(get_viewport_rect().size.x - size.x - 24, 84)
		return
	var bag_column := VBoxContainer.new()
	bag_column.add_child(text("가방 %d/%d (누르면 착용)" % [arena.bag.size(), int(data.bag_size)], MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bag_list := VBoxContainer.new()
	for index in arena.bag.size():
		var line := HBoxContainer.new()
		line.add_child(item_button(arena.bag[index], func(): arena.equip(index), true))
		var drop := Button.new()
		drop.text = "버림"
		drop.focus_mode = Control.FOCUS_NONE
		drop.pressed.connect(func():
			arena.discard(index)
			arena.refresh_build_windows())
		line.add_child(drop)
		var gain: int = int(data.crafting.salvage[arena.bag[index].rarity])
		line.add_child(small_button("분해", func(): arena.salvage(index), true, "%s +%d" % [data.crafting.material_name, gain]))
		bag_list.add_child(line)
	scroll.add_child(bag_list)
	bag_column.add_child(scroll)
	columns.add_child(bag_column)
	reset_size()
	# On the right edge, so it sits beside the character window (C) on the left.
	position = Vector2(get_viewport_rect().size.x - size.x - 24, 84)

func bench() -> ScrollContainer:
	var data: Dictionary = arena.items.data
	var craft: Dictionary = data.crafting
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	var held := HBoxContainer.new()
	held.add_child(text("이름 조각", MUTED))
	for id in data.pieces:
		var label := text("%s ×%d" % [data.pieces[id].name, arena.pieces[id]])
		label.tooltip_text = "\n".join(arena.items.describe_piece(id))
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		held.add_child(label)
	list.add_child(held)
	list.add_child(text("재굴림 %d전 + %s %d · 조각 빼기 %d전" % [int(craft.reroll_coins), craft.material_name, int(craft.reroll_material), int(craft.unsocket_coins)], MUTED, 12))
	for slot in data.slots:
		var item = arena.equipment[slot]
		if item == null:
			continue
		var head := HBoxContainer.new()
		var name := text("%s: %s" % [data.slot_names[slot], item.name], Color(data.rarity_colors[item.rarity]))
		name.tooltip_text = "\n".join(arena.items.describe(item))
		name.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(name)
		list.add_child(head)
		if int(item.get("sockets", 0)) > 0:
			var sockets := HBoxContainer.new()
			sockets.add_child(text("  소켓 %d/%d" % [item.pieces.size(), int(item.sockets)], MUTED, 13))
			var free: bool = item.pieces.size() < int(item.sockets)
			for id in data.pieces:
				sockets.add_child(small_button(data.pieces[id].name, func(): arena.socket_piece(slot, id), free and arena.pieces[id] > 0))
			sockets.add_child(small_button("빼기", func(): arena.unsocket(slot), not item.pieces.is_empty() and arena.coins >= int(craft.unsocket_coins)))
			list.add_child(sockets)
		var can_pay: bool = arena.coins >= int(craft.reroll_coins) and arena.scrap >= int(craft.reroll_material)
		for index in item.affixes.size():
			var affix: Dictionary = item.affixes[index]
			var caption: String = "  ↻ %s %s" % [["I", "II", "III"][affix.tier], arena.items.option_text(affix.id, affix.value)]
			list.add_child(small_button(caption, func(): arena.reroll(slot, index), can_pay, "같은 접두/접미·같은 자리 풀에서 다시 굴림"))
	scroll.add_child(list)
	return scroll
