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
	var active: bool = arena.state.active_tool != null
	var upkeep: float = arena.rules.skills.bolt_cutter.upkeep_per_second
	var status = "볼트 커터 가동  ·  MP −%s/s" % str(upkeep) if active else "공구 대기  ·  Q로 가동"
	if active and arena.state.mana < 10:
		status = "마나 소진 임박  ·  Q로 해제"
	panel(Rect2(24, 115, 300, 38), INK, GOLD if active else EDGE)
	draw_circle(Vector2(44, 134), 5, GOLD if active else MUTED)
	label_at(Vector2(61, 140), status, 14, GOLD if active else MUTED)
	label_at(Vector2(w - 230, 42), "FIELD / 001", 12, GOLD, true)
	label_at(Vector2(w - 230, 72), "남은 적  %02d" % arena.enemies.size(), 23, PAPER, true)
	label_at(Vector2(w - 230, 96), "처치 %d   ·   소환체 %d" % [arena.kills, arena.allies.size()], 14, MUTED)
	if arena.help_visible:
		panel(Rect2(w - 292, 120, 268, 151), Color("11232de8"), Color("3c5358"))
		label_at(Vector2(w - 274, 146), "현장 조작", 14, GOLD, true)
		var hints = ["좌클릭 (유지)   이동 / 적 공격", "Shift + 좌클릭   제자리 공격", "우클릭 · QWER   커서 지정 · 접근 시전", "Esc   일시정지     H   도움말"]
		for i in hints.size():
			label_at(Vector2(w - 274, 172 + i * 24), hints[i], 13, PAPER)
	for id in arena.enemies:
		var enemy: Dictionary = arena.enemies[id]
		if arena.camera.is_position_behind(enemy.body.position):
			continue
		var p: Vector2 = arena.camera.unproject_position(enemy.body.position + Vector3(0, 1.9, 0))
		if p.y > h - 180:
			continue
		var length = 64.0 if enemy.heavy else 48.0
		draw_rect(Rect2(p.x - length / 2 - 2, p.y - 2, length + 4, 9), INK)
		draw_rect(Rect2(p.x - length / 2, p.y, length * maxf(0, enemy.hp) / enemy.max_hp, 5), GOLD if enemy.heavy else RED)
		if enemy.slow > 0:
			centered(p + Vector2(0, -8), "둔화", 11, TEAL)
		elif enemy.windup > 0:
			centered(p + Vector2(0, -8), "!", 17, RED)
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
	gauge(Vector2(35, h - 135), arena.hp, arena.config.max_hp, RED, "HP")
	gauge(Vector2(w - 87, h - 135), arena.state.mana, arena.state.max_mana, TEAL, "MP")
	var start = (w - 1010) / 2
	label_at(Vector2(start, h - 125), "물약  /  비어 있음", 11, MUTED)
	for i in 4:
		var r = Rect2(start + i * 45, h - 113, 38, 65)
		panel(r, Color("14242c"), Color("35464c"))
		centered(r.position + Vector2(19, 21), str(i + 1), 13, MUTED)
		centered(r.position + Vector2(19, 49), "—", 18, EDGE)
	var names = ["기본 타격" if arena.state.bindings.lmb == "basic_attack" else "산탄", "산탄", "볼트 커터", "태엽인형", "포탑", "표적 중계"]
	var keys = ["LMB", "RMB", "Q", "W", "E", "R"]
	var sx = start + 196
	for i in 6:
		var slot: String = arena.rules.SLOTS[i]
		var skill: Dictionary = arena.rules.skills[arena.state.bindings[slot]]
		var cooldown: float = arena.state.cooldowns.get(skill.id, 0)
		var insufficient: bool = arena.state.mana < skill.mana_cost
		var color = GOLD if i == 2 and active else (Color("72888c") if insufficient else TEAL)
		if i == 0 and arena.fallback_time > 0:
			color = GOLD
		var rect = Rect2(sx + i * 100, h - 131, 91, 107)
		panel(rect, PANEL, color if i == 2 and active else EDGE)
		label_at(rect.position + Vector2(8, 17), keys[i], 11, color, true)
		icon(rect.position + Vector2(45, 45), i, color)
		centered(rect.position + Vector2(45, 80), names[i], 13, PAPER)
		var detail = "MP %d" % skill.mana_cost
		if i == 2:
			detail = "유지 %s/s" % str(upkeep)
		elif skill.id == "basic_attack":
			detail = "동작 %.2f초" % arena.attack_seconds(active)
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
	if arena.paused or arena.hp <= 0 or arena.enemies.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.055, 0.07, 0.82))
		var title = "잠시 정지" if arena.paused else ("마녀가 쓰러졌습니다" if arena.hp <= 0 else "필드 정리 완료")
		centered(Vector2(w / 2, h / 2 - 82), "MACHINERY / TEST FIELD", 13, GOLD)
		centered(Vector2(w / 2, h / 2 - 28), title, 34, PAPER)
		centered(Vector2(w / 2, h / 2 + 14), "Enter  다시 시작    ·    M  효과음 전환", 17, MUTED)
		if arena.paused:
			centered(Vector2(w / 2, h / 2 + 53), "Esc  계속하기", 16, TEAL)
			centered(Vector2(w / 2, h / 2 + 110), "시험 도구   F1 좌클릭 기본/산탄   ·   F2 마나 소진   ·   F3 마나 회복   ·   F4 공속 점수", 13, MUTED)

func gauge(pos: Vector2, value: float, maximum: float, color: Color, title: String) -> void:
	panel(Rect2(pos, Vector2(52, 100)), INK, GOLD)
	var amount = clampf(value / maximum, 0, 1) * 86
	draw_rect(Rect2(pos + Vector2(8, 93 - amount), Vector2(36, amount)), color.darkened(0.35))
	draw_rect(Rect2(pos + Vector2(11, 93 - amount), Vector2(5, amount)), color)
	for i in 5:
		draw_line(pos + Vector2(35, 10 + i * 19), pos + Vector2(43, 10 + i * 19), GOLD, 1)
	draw_line(pos + Vector2(-4, 0), pos + Vector2(56, 0), GOLD, 4)
	draw_line(pos + Vector2(-4, 100), pos + Vector2(56, 100), GOLD, 4)
	centered(pos + Vector2(26, 119), "%s %d" % [title, ceili(value)], 14, color)

func icon(p: Vector2, kind: int, color: Color) -> void:
	match kind:
		0:
			draw_line(p + Vector2(-12, 14), p + Vector2(12, -13), color, 3)
			draw_arc(p + Vector2(8, -8), 10, -2.6, 0.7, 16, color, 2)
		1:
			for a in [-0.5, 0, 0.5]:
				draw_line(p + Vector2(-16, 0), p + Vector2(16, 0).rotated(a), color, 2)
		2:
			for sign_x in [-1, 1]:
				draw_line(p + Vector2(sign_x * 12, 16), p + Vector2(-sign_x * 8, -9), color, 3)
				draw_line(p + Vector2(-sign_x * 8, -9), p + Vector2(-sign_x * 8, -16), color, 3)
			draw_circle(p, 3, GOLD)
		3:
			draw_rect(Rect2(p - Vector2(13, 11), Vector2(26, 22)), color, false, 2)
			draw_circle(p + Vector2(-5, -3), 2, color)
			draw_circle(p + Vector2(5, -3), 2, color)
			draw_line(p + Vector2(0, -11), p + Vector2(0, -18), color, 2)
			for x in [-9, 9]:
				draw_line(p + Vector2(x, 11), p + Vector2(x, 16), color, 3)
		4:
			draw_line(p + Vector2(-17, 15), p + Vector2(17, 15), color, 3)
			draw_line(p + Vector2(0, 15), p + Vector2(0, -5), color, 4)
			draw_rect(Rect2(p + Vector2(-10, -12), Vector2(23, 12)), color, false, 2)
			draw_line(p + Vector2(12, -6), p + Vector2(21, -6), color, 3)
		5:
			draw_arc(p, 13, 0, TAU, 32, color, 2)
			draw_circle(p, 3, color)
			for angle in [0, PI / 2, PI, 3 * PI / 2]:
				draw_line(p + Vector2(9, 0).rotated(angle), p + Vector2(20, 0).rotated(angle), color, 2)
