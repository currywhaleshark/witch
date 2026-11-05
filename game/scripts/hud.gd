extends Control
var arena: Node3D
var font = SystemFont.new()
var bold = SystemFont.new()
const INK = Color("0d1b24")
const PANEL = Color("172b34")
const EDGE = Color("526166")
const PAPER = Color("e3e9df")
const MUTED = Color("9aadaf")
const GOLD = Color("d8b77b")
const TEAL = Color("8dd8c4")
const RED = Color("ee987d")
const KEYS = ["LMB", "RMB", "Q", "W", "E", "R"]
const POTION_COLORS = {"hp": Color("ee987d"), "mp": Color("8dd8c4"), "both": Color("c9a0dc"), "speed": Color("a8d672")}
# Slot icons follow the bound skill, not the slot position.
const SkillIcon = preload("res://scripts/skill_icon.gd")
const ItemIcon = preload("res://scripts/item_icon.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	bold.font_names = font.font_names
	bold.font_weight = 700

func label_at(pos: Vector2, text: String, size_px: int = 16, color: Color = PAPER, strong: bool = false) -> void:
	draw_string(bold if strong else font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func centered(pos: Vector2, text: String, size_px: int = 16, color: Color = PAPER) -> void:
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	label_at(pos - Vector2(width / 2, 0), text, size_px, color)

func panel(rect: Rect2, color: Color = PANEL, border: Color = EDGE) -> void:
	draw_rect(rect, color)
	draw_rect(rect, border, false, 1)

func _draw() -> void:
	if arena == null or arena.state.is_empty():
		return
	var w = size.x
	var h = size.y
	panel(Rect2(24, 22, 300, 85), Color("14262fee"), Color("50625f"))
	label_at(Vector2(42, 45), "WITCH  /  COMBAT STUDY 01", 12, GOLD, true)
	label_at(Vector2(42, 76), "기계장치의 마녀", 23, PAPER, true)
	label_at(Vector2(43, 96), "단일 전투 필드 · 도형 시안", 12, MUTED)
	var tool = arena.state.active_tool
	var active: bool = tool != null
	var tool_keys: Array = []
	for i in 6:
		var bound = arena.state.bindings[arena.rules.SLOTS[i]]
		if bound != null and arena.rules.skills[bound].kind == "tool":
			tool_keys.append(KEYS[i])
	var status = "공구 대기  ·  %s로 가동" % "·".join(tool_keys)
	if active:
		status = "%s 가동  ·  MP −%s/s" % [arena.rules.skills[tool].name, str(arena.rules.skills[tool].upkeep_per_second)]
	if active and arena.state.mana < 10:
		status = "마나 소진 임박  ·  같은 키로 해제"
	var gun: Dictionary = arena.gun
	if not gun.is_empty():
		active = true
		status = "%s  ·  탄 %d/%d  ·  같은 키로 해제" % [arena.rules.skills[gun.id].name, gun.ammo, arena.gun_magazine(gun.id)]
		if int(gun.ammo) < arena.gun_magazine(gun.id):
			status = "%s  ·  탄 %d/%d  ·  장전 %.1f초" % [arena.rules.skills[gun.id].name, gun.ammo, arena.gun_magazine(gun.id), maxf(0.0, float(gun.reload_left))]
	if not arena.channel.is_empty():
		active = true
		var stream: Dictionary = arena.rules.skills[arena.channel.skill]
		status = "%s %s  ·  MP −%s/s  ·  떼면 중지" % [stream.name, "사격" if arena.channel.skill == "gatling" else "중", str(stream.channel_mana_per_second)]
	panel(Rect2(24, 115, 300, 38), INK, GOLD if active else EDGE)
	draw_circle(Vector2(44, 134), 5, GOLD if active else MUTED)
	label_at(Vector2(61, 140), status, 14, GOLD if active else MUTED)
	target_panel(w)
	var zone: String = "FIELD / 001"
	if arena.map.id != "flat":
		zone = arena.map.zone_at(arena.player.position).get("name", arena.map.data.get("name", ""))
	label_at(Vector2(w - 230, 42), zone, 12, GOLD, true)
	label_at(Vector2(w - 230, 72), "남은 적  %02d" % arena.enemies.size(), 23, PAPER, true)
	label_at(Vector2(w - 230, 96), "처치 %d   ·   소환체 %d" % [arena.kills, arena.allies.size()], 14, MUTED)
	if arena.help_visible:
		panel(Rect2(w - 292, 120, 268, 175), Color("11232de8"), Color("3c5358"))
		label_at(Vector2(w - 274, 146), "현장 조작", 14, GOLD, true)
		var hints = ["좌클릭 (유지)   이동 / 적 공격", "Shift + 좌클릭   제자리 공격", "우클릭 · QWER   커서 지정 · 이동 유지", "1 ~ 4   물약", "Esc   일시정지     H   도움말"]
		for i in hints.size():
			label_at(Vector2(w - 274, 172 + i * 24), hints[i], 13, PAPER)
	for id in arena.enemies:
		var enemy: Dictionary = arena.enemies[id]
		if arena.camera.is_position_behind(enemy.body.position):
			continue
		var p: Vector2 = arena.camera.unproject_position(enemy.body.position + Vector3(0, 0.35 + 1.55 * enemy.size, 0))
		if p.y > h - 180:
			continue
		# Bar width follows body size, so a rag-ghoul pack reads smaller than a brute.
		var length: float = 48.0 * clampf(enemy.size, 0.75, 1.6)
		draw_rect(Rect2(p.x - length / 2 - 2, p.y - 2, length + 4, 9), INK)
		var rank: Dictionary = arena.config.grades[enemy.grade]
		var bar = Color(rank.color) if rank.has("color") else (GOLD if enemy.heavy else RED)
		draw_rect(Rect2(p.x - length / 2, p.y, length * maxf(0, enemy.hp) / enemy.max_hp, 5), bar)
		var debuffs: Array = []
		if enemy.slow > 0:
			debuffs.append("둔화")
		if enemy.shred > 0:
			debuffs.append("방깎")
		if not enemy.bleeds.is_empty():
			debuffs.append("출혈 %d" % enemy.bleeds.size())
		if not debuffs.is_empty():
			centered(p + Vector2(0, -8), " · ".join(debuffs), 11, TEAL)
		elif enemy.windup > 0:
			centered(p + Vector2(0, -8), "!", 17, RED)
	# Drawing and clicks use the same separated rectangles, including when the camera moves.
	for entry in arena.loot_labels():
		var loot: Dictionary = entry.loot
		var rect: Rect2 = entry.rect
		var loot_active := is_same(loot, arena.hovered_loot)
		var color: Color = loot.color
		panel(rect, Color("304548f5") if loot_active else Color("0d1b24e8"), Color("fff1c4") if loot_active else Color(color, 0.5))
		if loot_active:
			draw_rect(rect, Color("fff1c4"), false, 2.0)
		label_at(rect.position + Vector2(7, 4 + font.get_ascent(13)), loot.name, 13, color.lerp(Color.WHITE, 0.3) if loot_active else color)
	for ally in arena.allies:
		# Summon durability: a thin teal bar only once it has been hit.
		if ally.hp >= ally.max_hp or arena.camera.is_position_behind(ally.node.position):
			continue
		var q: Vector2 = arena.camera.unproject_position(ally.node.position + Vector3(0, float(ally.get("bar_height", 1.45)), 0))
		draw_rect(Rect2(q.x - 19, q.y - 1, 38, 6), INK)
		draw_rect(Rect2(q.x - 18, q.y, 36 * maxf(0, ally.hp) / ally.max_hp, 4), TEAL)
	if arena.message_time > 0:
		var p: Vector2 = arena.camera.unproject_position(arena.player.position + Vector3(0, 2.6, 0))
		var text_width = font.get_string_size(arena.message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		panel(Rect2(p.x - text_width / 2 - 12, p.y - 22, text_width + 24, 32), INK, GOLD)
		centered(p, arena.message, 16, PAPER)
	# Vertical glass resource gauges bracket the complete bottom bar.
	draw_rect(Rect2(0, h - 155, w, 155), Color("0c1821f5"))
	draw_line(Vector2(24, h - 155), Vector2(w - 24, h - 155), GOLD, 1)
	label_at(Vector2(32, h - 168), "PROTOTYPE   /   수치·피해·회복은 시험값", 12, MUTED)
	label_at(Vector2(w - 307, h - 168), "M  " + ("효과음 꺼짐" if arena.muted else "효과음 켜짐") + "    ·    H  도움말", 12, MUTED)
	gauge(Vector2(35, h - 135), arena.hp, arena.config.max_hp, RED, "HP", arena.pending_fill("hp_rate"))
	gauge(Vector2(w - 87, h - 135), arena.state.mana, arena.state.max_mana, TEAL, "MP", arena.pending_fill("mp_rate"))
	var start = (w - 1010) / 2
	label_at(Vector2(start, h - 125), "물약", 11, MUTED)
	for i in 4:
		var r = Rect2(start + i * 45, h - 113, 38, 65)
		var slot: Dictionary = arena.potion_slots[i]
		var potion: Dictionary = arena.config.potions[slot.id]
		var tint: Color = POTION_COLORS[potion.kind]
		panel(r, Color("14242c"), Color("35464c"))
		label_at(r.position + Vector2(4, 13), str(i + 1), 11, MUTED, true)
		if slot.count <= 0:
			# An empty stack stays empty until restocked by hand.
			centered(r.position + Vector2(19, 41), "—", 18, EDGE)
			continue
		if not ItemIcon.draw_art(self, Rect2(r.position + Vector2(4, 16), Vector2(30, 32)), slot.id):
			draw_rect(Rect2(r.position + Vector2(13, 17), Vector2(12, 5)), EDGE)
			draw_rect(Rect2(r.position + Vector2(9, 22), Vector2(20, 24)), tint.darkened(0.25))
		label_at(r.position + Vector2(23, 13), potion.mark, 10, PAPER)
		centered(r.position + Vector2(19, 60), "×%d" % slot.count, 12, PAPER)
		var cooldown: float = arena.potion_cooldown(slot.id)
		if cooldown > 0:
			draw_rect(Rect2(r.position + Vector2(1, 15), Vector2(36, 33)), Color(0.02, 0.05, 0.07, 0.8))
			centered(r.position + Vector2(19, 37), "%.0f" % ceilf(cooldown), 15, GOLD)
	var sx = start + 196
	for i in 6:
		var slot: String = arena.rules.SLOTS[i]
		if arena.state.bindings[slot] == null:
			# A key emptied when its skill was unlearned.
			var empty = Rect2(sx + i * 100, h - 131, 91, 107)
			panel(empty, PANEL, EDGE)
			label_at(empty.position + Vector2(8, 17), KEYS[i], 11, MUTED, true)
			continue
		var skill: Dictionary = arena.rules.skills[arena.state.bindings[slot]]
		var cooldown: float = arena.state.cooldowns.get(skill.id, 0)
		var insufficient: bool = arena.state.mana < skill.mana_cost
		var running: bool = (skill.kind == "tool" and tool == skill.id) or arena.gun.get("id") == skill.id or arena.channel.get("skill") == skill.id
		var color = GOLD if running else (Color("72888c") if insufficient else TEAL)
		if i == 0 and arena.fallback_time > 0:
			color = GOLD
		var rect = Rect2(sx + i * 100, h - 131, 91, 107)
		panel(rect, PANEL, color if running else EDGE)
		label_at(rect.position + Vector2(8, 17), KEYS[i], 11, color, true)
		icon(rect.position + Vector2(45, 45), skill.id, color)
		var title: String = skill.name
		if skill.id == "basic_attack" and not gun.is_empty():
			title = "사격"
		if arena.config.has(skill.id + "_level"):
			# Trial skill levels exist only for the shield and the summons so far.
			title += " Lv%d" % arena.config[skill.id + "_level"]
		centered(rect.position + Vector2(45, 80), title, 13, PAPER)
		var detail = "MP %d" % skill.mana_cost
		if skill.kind == "tool":
			detail = "유지 %s · %.2f초" % [str(skill.upkeep_per_second), arena.attack_seconds(skill.id)]
		elif skill.id == "basic_attack" and not gun.is_empty():
			detail = "탄 %d/%d · %.2f초" % [gun.ammo, arena.gun_magazine(gun.id), arena.attack_seconds(gun.id)]
		elif skill.id == "basic_attack":
			detail = "동작 %.2f초" % arena.attack_seconds(tool)
		elif skill.id in ["gatling", "focus_attack"]:
			detail = "MP %d · −%s/s" % [skill.mana_cost, str(skill.channel_mana_per_second)]
		elif skill.id in arena.GUNS:
			detail = "탄 %d/%d" % [gun.ammo, arena.gun_magazine(skill.id)] if gun.get("id") == skill.id else "MP %d · %d발" % [skill.mana_cost, arena.gun_magazine(skill.id)]

		elif skill.id == "shield":
			detail = "막기 %d%%" % roundi(100 * arena.block_chance())
			if arena.shield_time > 0:
				detail += " · %.1f초" % arena.shield_time
		elif skill.get("cast_seconds", 0.0) > 0:
			detail = "MP %d · %.2f초" % [skill.mana_cost, arena.cast_seconds(skill)]
		centered(rect.position + Vector2(45, 98), detail, 11, MUTED)
		if cooldown > 0:
			draw_rect(Rect2(rect.position + Vector2(1, 23), Vector2(89, 42)), Color(0.02, 0.05, 0.07, 0.85))
			centered(rect.position + Vector2(45, 53), "%.1f" % cooldown, 21, GOLD)
		elif insufficient:
			centered(rect.position + Vector2(45, 63), "부족", 11, RED)
	label_at(Vector2(sx + 615, h - 109), "ESC", 12, GOLD, true)
	label_at(Vector2(sx + 615, h - 88), "일시정지", 13, MUTED)
	label_at(Vector2(sx + 615, h - 59), "M", 12, GOLD, true)
	label_at(Vector2(sx + 615, h - 38), "효과음", 13, MUTED)
	if arena.hit_time > 0:
		draw_rect(Rect2(3, 3, w - 6, h - 6), Color(0.93, 0.35, 0.22, arena.hit_time * 2), false, 6)
	if arena.speed_buff > 0:
		panel(Rect2(24, 159, 300, 26), INK, Color("a8d672"))
		label_at(Vector2(40, 177), "버프  ·  이동 속도 +%d%%  ·  %d초" % [roundi(100 * arena.config.potions.speed.speed_bonus), ceili(arena.speed_buff)], 13, Color("a8d672"))
	if arena.a5_mode:
		a5_panel(Vector2(24, 193))
	if arena.field_cleared() and not arena.ground_items.is_empty() and not arena.paused and arena.hp > 0:
		panel(Rect2(w / 2 - 180, 22, 360, 62), INK, GOLD)
		centered(Vector2(w / 2, 47), "필드 정리 완료", 20, PAPER)
		centered(Vector2(w / 2, 69), "전리품 클릭하여 줍기  ·  Enter 다시 시작", 13, MUTED)
	elif arena.paused or arena.hp <= 0 or arena.field_cleared():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.055, 0.07, 0.82))
		var title = "잠시 정지" if arena.paused else ("마녀가 쓰러졌습니다" if arena.hp <= 0 else "필드 정리 완료")
		centered(Vector2(w / 2, h / 2 - 82), "MACHINERY / TEST FIELD", 13, GOLD)
		centered(Vector2(w / 2, h / 2 - 28), title, 34, PAPER)
		centered(Vector2(w / 2, h / 2 + 14), "Enter  다시 시작    ·    M  효과음 전환", 17, MUTED)
		if arena.paused:
			centered(Vector2(w / 2, h / 2 + 53), "Esc  계속하기", 16, TEAL)
			centered(Vector2(w / 2, h / 2 + 110), "시험 도구   F1 좌클릭 기본/산탄   ·   F2 마나 소진   ·   F3 마나 회복   ·   F4 공속 점수   ·   F8 시전 속도 점수", 13, MUTED)
			centered(Vector2(w / 2, h / 2 + 158), "F9 R 방패/그라인더/중계   ·   F10 방패 레벨   ·   F11 기교   ·   F12 타격 회복 점수", 13, MUTED)
			centered(Vector2(w / 2, h / 2 + 182), "Shift+1~4 물약 종류   ·   B 보스 소환   ·   Shift/Ctrl+F10 태엽인형/포탑 레벨   ·   N 태엽인형 노드   ·   J/K 절삭 정밀화/탄도 계산", 13, MUTED)
			centered(Vector2(w / 2, h / 2 + 134), "A5 마나 시험   F5 연속 교전 켜기/끄기   ·   F6 기록 저장   ·   F7 마나 회복량", 13, MUTED)

func a5_panel(pos: Vector2) -> void:
	# Live A5 readout; the saved JSON log holds the same numbers plus per-skill detail.
	var probe = arena.probe
	var gap_now: bool = probe.current_gap > 0
	panel(Rect2(pos, Vector2(300, 150)), Color("14262fee"), RED if gap_now else Color("50625f"))
	label_at(pos + Vector2(18, 23), "A5 마나 시험  ·  연속 교전", 12, GOLD, true)
	label_at(pos + Vector2(18, 46), "교전 %d초  ·  회복 %s/s  ·  공구 유지 %s/s" % [probe.combat_seconds, str(arena.config.mana_regen), str(arena.rules.skills[arena.state.active_tool].upkeep_per_second if arena.state.active_tool != null else 0)], 12, MUTED)
	label_at(pos + Vector2(18, 72), "기술 공백 %.1f초 (%d%%) · %d회" % [probe.gap_seconds, roundi(probe.gap_share() * 100), probe.gap_count], 14, PAPER)
	label_at(pos + Vector2(18, 95), ("지금 공백 %.1f초" % probe.current_gap if gap_now else "지금 쓸 수 있는 기술 있음") + "  ·  최장 %.1f초" % probe.longest_gap, 13, RED if gap_now else TEAL)
	label_at(pos + Vector2(18, 118), "마나 부족 %d  ·  대체 공격 %d  ·  공구 해제 %d" % [probe.counts.mana_failures, probe.counts.fallback_attacks, probe.counts.tool_auto_releases], 12, MUTED)
	label_at(pos + Vector2(18, 139), "F6 기록 저장   ·   F7 회복량   ·   F5 종료", 11, MUTED)

func target_panel(w: float) -> void:
	# Top-centre target: the hovered enemy, otherwise a living boss. Grade shows by name and colour.
	var id: String = arena.hover_id if arena.enemies.has(arena.hover_id) else ""
	if id == "":
		for other in arena.enemies:
			if arena.enemies[other].grade == "boss":
				id = other
				break
	if id == "":
		return
	var enemy: Dictionary = arena.enemies[id]
	var rank: Dictionary = arena.config.grades[enemy.grade]
	var tint = Color(rank.color) if rank.has("color") else PAPER
	panel(Rect2(w / 2 - 160, 24, 320, 48), Color("14262fee"), tint if rank.has("color") else EDGE)
	centered(Vector2(w / 2, 45), arena.enemy_name(id), 15, tint)
	draw_rect(Rect2(w / 2 - 140, 54, 280, 8), INK)
	draw_rect(Rect2(w / 2 - 140, 54, 280 * maxf(0, enemy.hp) / enemy.max_hp, 8), tint.darkened(0.15) if rank.has("color") else RED)

func gauge(pos: Vector2, value: float, maximum: float, color: Color, title: String, pending: float = 0.0) -> void:
	panel(Rect2(pos, Vector2(52, 100)), INK, GOLD)
	var amount = clampf(value / maximum, 0, 1) * 86
	# Pale layer: what running potions will still pour in.
	var coming = clampf((value + pending) / maximum, 0, 1) * 86
	if coming > amount:
		draw_rect(Rect2(pos + Vector2(8, 93 - coming), Vector2(36, coming - amount)), Color(color, 0.3))
	draw_rect(Rect2(pos + Vector2(8, 93 - amount), Vector2(36, amount)), color.darkened(0.35))
	draw_rect(Rect2(pos + Vector2(11, 93 - amount), Vector2(5, amount)), color)
	for i in 5:
		draw_line(pos + Vector2(35, 10 + i * 19), pos + Vector2(43, 10 + i * 19), GOLD, 1)
	draw_line(pos + Vector2(-4, 0), pos + Vector2(56, 0), GOLD, 4)
	draw_line(pos + Vector2(-4, 100), pos + Vector2(56, 100), GOLD, 4)
	centered(pos + Vector2(26, 119), "%s %d" % [title, ceili(value)], 14, color)

func icon(p: Vector2, id: String, color: Color) -> void:
	SkillIcon.draw(self, p, id, color)
