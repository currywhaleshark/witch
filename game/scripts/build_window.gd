extends PanelContainer
## Temporary character (C) and skill tree (S) windows for the C1/C2 trial (10_ui §4).
## They only call the build; combat keeps running while they are open.
const Build = preload("res://scripts/build.gd")
const SkillIcon = preload("res://scripts/skill_icon.gd")
const PANEL = Color("172b34")
const EDGE = Color("526166")
const PAPER = Color("e3e9df")
const MUTED = Color("9aadaf")
const GOLD = Color("d8b77b")
const TREE_NAMES = {"firearm": "화기", "drive": "구동", "automation": "자동화"}
const SLOT_NAMES = {"rmb": "RMB", "q": "Q", "w": "W", "e": "E", "r": "R"}
# Every skill a slot can carry, grouped by tree; the basic attack stays on the left button.
const LOADOUT = ["shotgun", "bolt_cutter", "grinder", "chainsaw", "shield", "spring_dash", "automaton", "turret", "relay"]

# Skill tree layout: candidates from 03 in tier rows, links of related study (not prerequisites).
# Each skill is an icon; its name and effect are in the hover tip. Skills are put on keys by
# dragging an icon from the tree (or another key) onto a key box.
const NODE = Vector2(46, 46)
const PITCH = Vector2(58, 62)
const TIER_LABEL = 24
var TREE_UI: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_tree_ui.json"))

var arena: Node
var mode: String
var body: VBoxContainer
var tree_tab := "firearm"
var tip: PanelContainer
var dragged := false
var tip_label: Label

func setup(owner: Node, which: String) -> void:
	arena = owner
	mode = which
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(PANEL, 0.96)
	frame.border_color = EDGE
	frame.set_border_width_all(1)
	frame.set_content_margin_all(14)
	add_theme_stylebox_override("panel", frame)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	# A node's name and effect show only while the mouse is on it.
	tip = PanelContainer.new()
	tip.top_level = true
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	var tip_frame: StyleBoxFlat = frame.duplicate()
	tip_frame.set_content_margin_all(8)
	tip.add_theme_stylebox_override("panel", tip_frame)
	tip_label = text("", PAPER, 13)
	tip.add_child(tip_label)
	add_child(tip)
	refresh()

func _process(_delta: float) -> void:
	if not visible or not tip.visible:
		return
	var mouse := get_viewport().get_mouse_position()
	tip.reset_size()
	var spot := mouse + Vector2(18, 12)
	if spot.x + tip.size.x > get_viewport_rect().size.x:
		spot.x = mouse.x - tip.size.x - 12
	tip.position = spot

func toggle() -> void:
	visible = not visible
	tip.visible = false
	refresh()

func refresh() -> void:
	if body == null:
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	if mode == "character":
		_character()
	else:
		_skills()
	reset_size()
	if mode == "skills":
		# Keep the wider skill tree window on the right edge as its content grows.
		position.x = get_viewport_rect().size.x - size.x - 24

func text(value: String, color: Color = PAPER, size_px: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size_px)
	return label

func button(caption: String, action: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = caption
	# Keyboard focus would swallow Space/Enter and skill keys; the windows are mouse-only.
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.pressed.connect(func():
		action.call()
		arena.refresh_build_windows())
	return b

func row(children: Array) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	for child in children:
		line.add_child(child)
	return line

func step_size() -> int:
	# Ctrl+click spends 5 at once and Shift+click 10, as far as points and caps allow.
	if Input.is_key_pressed(KEY_SHIFT):
		return 10
	if Input.is_key_pressed(KEY_CTRL):
		return 5
	return 1

func repeated(single: Callable) -> Callable:
	# single returns false once it can go no further, which ends the run early.
	return func():
		for i in step_size():
			if not single.call():
				break

func stepper(label: String, value: String, minus: Callable, plus: Callable, can_minus: bool, can_plus: bool, note: String = "") -> HBoxContainer:
	var name_label := text(label)
	name_label.custom_minimum_size.x = 118
	var value_label := text(value, GOLD)
	value_label.custom_minimum_size.x = 64
	var line := row([name_label, value_label, button("−", repeated(minus), can_minus), button("+", repeated(plus), can_plus)])
	if note != "":
		line.add_child(text(note, MUTED, 13))
	return line

func _character() -> void:
	var build = arena.build
	body.add_child(stepper("시험 레벨", "Lv %d" % build.level, func(): return build.step_level(-1), func(): return build.step_level(1),
		build.level > 1, build.level < int(build.rules.max_level), "레벨당 스탯 %d · 스킬 %d" % [build.rules.stat_points_per_level, build.rules.skill_points_per_level]))
	var rules: Dictionary = build.rules
	body.add_child(stepper("적 레벨", "Lv %d" % arena.enemy_level, func(): return arena.step_enemy_level(-1), func(): return arena.step_enemy_level(1),
		arena.enemy_level > 1, arena.enemy_level < int(rules.max_level), "HP ×%.2f · 피해 ×%.2f%s" % [arena.enemy_level_factor("hp", arena.enemy_level),
		arena.enemy_level_factor("damage", arena.enemy_level), " · 시험 레벨 따라감" if arena.enemy_level_linked else ""]))
	if not arena.enemy_level_linked:
		body.add_child(row([button("적 레벨을 시험 레벨에 맞춤", func(): arena.link_enemy_level())]))
	body.add_child(text("남은 스탯 포인트  %d" % build.stat_points(), GOLD))
	var effects: Dictionary = build.rules.stat_effects
	var notes := {
		"power": "직접 피해 +%d%%" % roundi(100 * float(effects.power) * build.stat("power")),
		"dexterity": "명중 %d%% · 치명 %d%%" % [roundi(100 * clampf(arena.config.hit_base + arena.config.hit_per_dexterity * arena.config.dexterity, arena.config.hit_min, arena.config.hit_cap)), roundi(100 * arena.crit_chance())],
		"vitality": "최대 HP %d" % roundi(arena.config.max_hp),
		"will": "최대 MP %d" % roundi(arena.state.max_mana)}
	for id in Build.STATS:
		body.add_child(stepper(Build.STAT_NAMES[id], str(build.stats[id]), func(): return build.change_stat(id, -1), func(): return build.change_stat(id, 1),
			build.stats[id] > 0, build.stat_points() > 0, notes[id]))
	var cast_speed: Dictionary = build.cast_speed_parts()
	body.add_child(text("시전 속도 %d (장비 %d + 생산 효율 %d) · 태엽인형 %.2f초 · 산탄 %.2f초 · 장비는 I 창" % [arena.config.cast_speed_score, cast_speed.gear, cast_speed.passive,
		arena.cast_seconds(arena.rules.skills.automaton), arena.cast_seconds(arena.rules.skills.shotgun)], GOLD, 13))
	body.add_child(row([button("초기화", func(): build.reset_stats(), build.stat_points() < build.level * int(build.rules.stat_points_per_level))]))

func _skills() -> void:
	# One tree at a time in tiers I-IV as 03 lays out its candidates; the lines show related study,
	# not prerequisites. Implemented skills are lit, and only those with level effects take points.
	var build = arena.build
	var tabs: Array = []
	for tree in TREE_NAMES:
		tabs.append(button(TREE_NAMES[tree], func(): tree_tab = tree, tree_tab != tree))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.append(gap)
	var points := text(str(build.skill_points()), GOLD, 17)
	points.tooltip_text = "남은 스킬 포인트"
	points.mouse_filter = Control.MOUSE_FILTER_STOP
	tabs.append(points)
	tabs.append(button("초기화", func(): build.reset_skills(), build.skill_points() < build.level * int(build.rules.skill_points_per_level)))
	body.add_child(row(tabs))
	var layout: Dictionary = tree_layout()
	var canvas := Control.new()
	canvas.name = "Tree"
	canvas.custom_minimum_size = Vector2(TIER_LABEL + int(TREE_UI.columns) * PITCH.x, 5 * PITCH.y)
	canvas.draw.connect(func(): draw_tree(canvas, layout))
	for node in layout.nodes + layout.passives:
		var box := node_box(node)
		box.position = node_spot(node)
		canvas.add_child(box)
	body.add_child(canvas)
	if tree_tab == "automation":
		var choices: Array = []
		for choice in ["base", "A", "B"]:
			var pick := button(("● " if build.node == choice else "") + Build.NODE_NAMES[choice], func(): build.set_node(choice),
				build.node != choice and (choice == "base" or build.node != "base" or build.skill_points() >= int(build.rules.node_cost)))
			pick.tooltip_text = "태엽인형 특화 · %d점" % build.rules.node_cost
			choices.append(pick)
		body.add_child(row(choices))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	for slot in SLOT_NAMES:
		slots.add_child(slot_box(slot))
	body.add_child(slots)

func tree_layout() -> Dictionary:
	for tree in TREE_UI.trees:
		if tree.tree == tree_tab:
			return tree
	return TREE_UI.trees[0]

func node_spot(node: Dictionary) -> Vector2:
	# Passives take a fifth row under tier IV, left to right.
	if node.has("tier"):
		return Vector2(TIER_LABEL + int(node.col) * PITCH.x, (int(node.tier) - 1) * PITCH.y)
	return Vector2(TIER_LABEL + tree_layout().passives.find(node) * PITCH.x, 4 * PITCH.y + 6)

func node_state(node: Dictionary) -> String:
	# "levels" takes points, "fixed" works but has no level effect yet, "missing" is not built.
	var id: String = node.get("id", "")
	if id == "":
		return "missing"
	return "levels" if arena.build.skills.has(id) or arena.build.passives.has(id) else "fixed"

func node_level(id: String) -> int:
	return arena.build.skills[id] if arena.build.skills.has(id) else arena.build.passives[id]

func draw_tree(canvas: Control, layout: Dictionary) -> void:
	var font: Font = get_theme_default_font()
	for tier in 4:
		canvas.draw_string(font, Vector2(0, tier * PITCH.y + NODE.y / 2 + 5), ["I", "II", "III", "IV"][tier], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	canvas.draw_line(Vector2(TIER_LABEL, 4 * PITCH.y - 6), Vector2(canvas.size.x, 4 * PITCH.y - 6), Color(EDGE, 0.6))
	var by_name := {}
	for node in layout.nodes:
		by_name[node.name] = node
	for link in layout.links:
		var a: Dictionary = by_name[link[0]]
		var b: Dictionary = by_name[link[1]]
		var start: Vector2 = node_spot(a) + Vector2(NODE.x / 2, NODE.y)
		var finish: Vector2 = node_spot(b) + Vector2(NODE.x / 2, 0)
		if int(a.tier) == int(b.tier):
			start = node_spot(a) + Vector2(NODE.x, NODE.y / 2)
			finish = node_spot(b) + Vector2(0, NODE.y / 2)
		var lit: bool = node_state(a) != "missing" and node_state(b) != "missing"
		canvas.draw_line(start, finish, Color(GOLD, 0.75) if lit else Color(EDGE, 0.8), 2.0 if lit else 1.0)

func node_box(node: Dictionary) -> Control:
	var state := node_state(node)
	var id: String = node.get("id", "")
	var box := Control.new()
	box.name = "Node_" + (id if id != "" else str(node.name))
	box.size = NODE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.draw.connect(func(): draw_node(box, node, state))
	box.mouse_entered.connect(func(): show_detail(id if id != "" else str(node.name)))
	box.mouse_exited.connect(func(): tip.visible = false)
	# Points go in on release, so pressing to drag the icon onto a key does not spend one.
	box.gui_input.connect(func(event):
		if not event is InputEventMouseButton or not event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
		# Accepted first: click_node rebuilds the window, and a box already out of the tree can
		# no longer stop the click from reaching the field.
		box.accept_event()
		if event.pressed:
			dragged = false
		elif state == "levels" and not dragged:
			click_node(id, 1 if event.button_index == MOUSE_BUTTON_LEFT else -1))
	box.set_drag_forwarding(func(_at): return start_drag(id, ""), func(_at, _data): return false, func(_at, _data): pass)
	return box

func draw_node(box: Control, node: Dictionary, state: String) -> void:
	var rect := Rect2(Vector2.ZERO, NODE)
	var missing := state == "missing"
	box.draw_rect(rect, Color("0d181d") if missing else Color("213a45"))
	box.draw_rect(rect, Color(EDGE, 0.5) if missing else (GOLD if state == "levels" else PAPER), false, 1.0 if missing else 1.5)
	# The skill's picture, its level in the corner where points go; grey boxes are not built yet.
	var font: Font = get_theme_default_font()
	var id: String = node.get("id", "")
	SkillIcon.draw(box, NODE / 2, id, Color(MUTED, 0.35) if missing else PAPER, 0.78)
	if state == "levels":
		var level := str(node_level(id))
		var badge := Rect2(NODE - Vector2(8 + 7 * level.length(), 16), Vector2(8 + 7 * level.length(), 16))
		box.draw_rect(badge, Color("0d181d"))
		box.draw_string(font, badge.position + Vector2(0, 13), level, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 12, GOLD)
	var key := bound_key(id)
	if key != "":
		box.draw_string(font, Vector2(NODE.x - 24, 12), key, HORIZONTAL_ALIGNMENT_RIGHT, 21, 10, GOLD)

func click_node(id: String, direction: int) -> void:
	# Left raises and right lowers, by 1/5/10 like the steppers.
	repeated(func(): return arena.build.change_skill(id, direction)).call()
	arena.refresh_build_windows()
	show_detail(id)

func bound_key(id: String) -> String:
	if id == "":
		return ""
	for slot in SLOT_NAMES:
		if arena.state.bindings[slot] == id:
			return SLOT_NAMES[slot]
	return ""

func find_node(key: String):
	if key == "":
		return null
	for tree in TREE_UI.trees:
		for node in tree.nodes + tree.passives:
			if node.get("id", "") == key or node.name == key:
				return node
	return null

func node_info(node: Dictionary) -> PackedStringArray:
	var state := node_state(node)
	var lines := PackedStringArray([node.name])
	if state == "missing":
		lines.append("미구현")
		return lines
	var id: String = node.id
	if state == "levels":
		lines.append("Lv %d/%d" % [node_level(id), int(arena.build.rules.skill_max_level)])
		lines.append(effect_note(id))
	else:
		lines.append("레벨 효과 없음")
	var key := bound_key(id)
	if key != "":
		lines.append("슬롯 " + key)
	return lines

func show_detail(key: String) -> void:
	var node = find_node(key)
	if node == null:
		tip.visible = false
		return
	tip_label.text = "\n".join(node_info(node))
	tip.visible = true

func slot_box(slot: String) -> Control:
	# A key with the icon of the skill on it; a skill icon dropped here takes the key.
	var box := Control.new()
	box.name = "Slot_" + slot
	box.custom_minimum_size = Vector2(NODE.x + 8, NODE.y + 8)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.draw.connect(func(): draw_slot(box, slot))
	box.mouse_entered.connect(func(): show_detail(arena.state.bindings[slot]))
	box.mouse_exited.connect(func(): tip.visible = false)
	box.set_drag_forwarding(func(_at): return start_drag(arena.state.bindings[slot], slot),
		func(_at, data): return can_take(data), func(_at, data): drop_skill(slot, data))
	return box

func draw_slot(box: Control, slot: String) -> void:
	var rect := Rect2(Vector2.ZERO, box.custom_minimum_size)
	box.draw_rect(rect, Color("213a45"))
	box.draw_rect(rect, GOLD, false, 1.5)
	SkillIcon.draw(box, rect.get_center() + Vector2(0, 3), arena.state.bindings[slot], PAPER, 0.8)
	box.draw_string(get_theme_default_font(), Vector2(4, 12), SLOT_NAMES[slot], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GOLD)

func start_drag(id: String, from: String):
	# Only skills a key can carry lift off the tree; the icon follows the cursor.
	var data = drag_data(id, from)
	if data == null:
		return null
	dragged = true
	tip.visible = false
	var preview := Control.new()
	preview.draw.connect(func(): SkillIcon.draw(preview, Vector2.ZERO, id, GOLD, 0.8))
	set_drag_preview(preview)
	return data

func drag_data(id: String, from: String):
	return {"skill": id, "from": from} if id in LOADOUT else null

func can_take(data) -> bool:
	return data is Dictionary and data.has("skill")

func drop_skill(slot: String, data: Dictionary) -> void:
	# A skill already on another key swaps places with the one it lands on.
	var id: String = data.skill
	var old: String = arena.state.bindings[slot]
	if id == old:
		return
	for other in SLOT_NAMES:
		if other != slot and arena.state.bindings[other] == id:
			arena.bind_slot(other, old)
	arena.bind_slot(slot, id)
	arena.refresh_build_windows()

func effect_note(id: String) -> String:
	var config: Dictionary = arena.config
	match id:
		"shield":
			return "막기 %d%% · %.1f초" % [roundi(100 * arena.block_chance()), arena.shield_duration()]
		"chainsaw":
			return "출혈 %.1f초" % arena.bleed_plan(0).seconds
		"shotgun":
			var knock: float = float(arena.rules.skills.shotgun.knockback_level)
			return "피해 +%d%% · %s" % [roundi(100 * (arena.skill_level_factor("shotgun") - 1.0)), "넉백" if arena.config.shotgun_level >= knock else "Lv%d 넉백" % knock]
		"automaton", "turret":
			return "체력 ×%.2f · 피해 ×%.2f · 명중 %d%% · 치명 %d%%" % [arena.summon_growth("hp", id), arena.summon_growth("damage", id),
				roundi(100 * clampf(config.summon_hit_base + config.summon_hit_per_level * (config[id + "_level"] - 1), config.hit_min, config.hit_cap)), roundi(100 * arena.crit_chance(id))]
		"production_efficiency":
			return "시전 속도 +%d" % roundi(arena.build.cast_speed_parts().passive)
		_:
			var passive: Dictionary = config.passives[id]
			return "%s 피해 +%d%%" % [passive.tag_name, roundi(100 * float(passive.damage_per_level) * config.passive_levels[id])]
