extends PanelContainer
## Temporary character (C) and skill tree (S) windows for the C1/C2 trial (10_ui §4).
## They only call the build; combat keeps running while they are open.
const Build = preload("res://scripts/build.gd")
const PANEL = Color("172b34")
const EDGE = Color("526166")
const PAPER = Color("e3e9df")
const MUTED = Color("9aadaf")
const GOLD = Color("d8b77b")
const TREE_NAMES = {"firearm": "화기", "drive": "구동", "automation": "자동화"}
const SLOT_NAMES = {"rmb": "우클릭", "q": "Q", "w": "W", "e": "E", "r": "R"}
# Every skill a slot can carry, grouped by tree; the basic attack stays on the left button.
const LOADOUT = ["shotgun", "bolt_cutter", "grinder", "chainsaw", "shield", "spring_dash", "automaton", "turret", "relay"]

var arena: Node
var mode: String
var body: VBoxContainer

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
	refresh()

func toggle() -> void:
	visible = not visible
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
	body.add_child(text("캐릭터  (C)", PAPER, 18))
	body.add_child(stepper("시험 레벨", "Lv %d" % build.level, func(): return build.step_level(-1), func(): return build.step_level(1),
		build.level > 1, build.level < int(build.rules.max_level), "레벨당 스탯 %d · 스킬 %d" % [build.rules.stat_points_per_level, build.rules.skill_points_per_level]))
	body.add_child(text("남은 스탯 포인트  %d" % build.stat_points(), GOLD))
	var effects: Dictionary = build.rules.stat_effects
	var notes := {
		"power": "직접 피해 +%d%%" % roundi(100 * float(effects.power) * build.stats.power),
		"dexterity": "명중 %d%% · 치명 %d%%" % [roundi(100 * clampf(arena.config.hit_base + arena.config.hit_per_dexterity * arena.config.dexterity, arena.config.hit_min, arena.config.hit_cap)), roundi(100 * arena.crit_chance())],
		"vitality": "최대 HP %d" % roundi(arena.config.max_hp),
		"will": "최대 MP %d" % roundi(arena.state.max_mana)}
	for id in Build.STATS:
		body.add_child(stepper(Build.STAT_NAMES[id], str(build.stats[id]), func(): return build.change_stat(id, -1), func(): return build.change_stat(id, 1),
			build.stats[id] > 0, build.stat_points() > 0, notes[id]))
	body.add_child(text("명중은 회피 없는 일반 적 기준. 위력은 소환체·출혈에 적용되지 않음", MUTED, 12))
	body.add_child(text("Ctrl+클릭 ×5 · Shift+클릭 ×10", MUTED, 12))
	body.add_child(row([button("스탯 초기화 (무료)", func(): build.reset_stats(), build.stat_points() < build.level * int(build.rules.stat_points_per_level))]))

func _skills() -> void:
	var build = arena.build
	body.add_child(text("스킬트리  (S)", PAPER, 18))
	body.add_child(text("남은 스킬 포인트  %d   ·   시험 레벨 Lv %d" % [build.skill_points(), build.level], GOLD))
	var max_level: int = int(build.rules.skill_max_level)
	for tree in build.rules.skill_tree:
		body.add_child(text(TREE_NAMES[tree.tree], MUTED, 14))
		for entry in tree.entries:
			var id: String = entry.id
			var is_skill: bool = entry.kind == "skill"
			var value: int = build.skills[id] if is_skill else build.passives[id]
			var label: String = arena.rules.skills[id].name if is_skill else arena.config.passives[id].name
			body.add_child(stepper(label, "Lv %d/%d" % [value, max_level], func(): return build.change_skill(id, -1), func(): return build.change_skill(id, 1),
				value > (1 if is_skill else 0), value < max_level and build.skill_points() > 0, effect_note(id)))
			if entry.get("nodes", false):
				var choices: Array = []
				for choice in ["base", "A", "B"]:
					var pick := button(("● " if build.node == choice else "") + Build.NODE_NAMES[choice], func(): build.set_node(choice),
						build.node != choice and (choice == "base" or build.node != "base" or build.skill_points() >= int(build.rules.node_cost)))
					choices.append(pick)
				var line := row([text("  특화 (%d점)" % build.rules.node_cost, MUTED, 13)] + choices)
				body.add_child(line)
	body.add_child(text("다른 스킬은 시험판에서 레벨 효과가 없어 목록에서 뺐음 · Ctrl+클릭 ×5 · Shift+클릭 ×10", MUTED, 12))
	body.add_child(row([button("스킬 초기화 (무료)", func(): build.reset_skills(), build.skill_points() < build.level * int(build.rules.skill_points_per_level))]))
	body.add_child(text("슬롯 등록", MUTED, 14))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	for slot in SLOT_NAMES:
		slots.add_child(slot_picker(slot))
	body.add_child(slots)

func slot_picker(slot: String) -> VBoxContainer:
	# Any skill on any of RMB/Q/W/E/R, so a build can carry e.g. the chainsaw and the shield together.
	var column := VBoxContainer.new()
	column.add_child(text(SLOT_NAMES[slot], GOLD, 13))
	var picker := OptionButton.new()
	picker.name = "Slot_" + slot
	picker.focus_mode = Control.FOCUS_NONE
	picker.fit_to_longest_item = false
	for id in LOADOUT:
		picker.add_item(arena.rules.skills[id].name)
	picker.select(LOADOUT.find(arena.state.bindings[slot]))
	picker.item_selected.connect(func(index: int):
		arena.bind_slot(slot, LOADOUT[index])
		arena.refresh_build_windows())
	column.add_child(picker)
	return column

func effect_note(id: String) -> String:
	var config: Dictionary = arena.config
	match id:
		"shield":
			return "막기 %d%% · %.1f초" % [roundi(100 * arena.block_chance()), arena.shield_duration()]
		"chainsaw":
			return "출혈 %.1f초" % arena.bleed_plan(0).seconds
		"automaton", "turret":
			return "명중 %d%% · 치명 %d%%" % [roundi(100 * clampf(config.summon_hit_base + config.summon_hit_per_level * (config[id + "_level"] - 1), config.hit_min, config.hit_cap)), roundi(100 * arena.crit_chance(id))]
		_:
			var passive: Dictionary = config.passives[id]
			return "%s 피해 +%d%%" % [passive.tag_name, roundi(100 * float(passive.damage_per_level) * config.passive_levels[id])]
