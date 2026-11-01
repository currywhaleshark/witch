extends RefCounted
## Skill pictures shared by the HUD action bar and the skill tree window. Shapes are drawn around
## p and span about 36px; draw() scales them for smaller boxes. Skills without a picture of their
## own (03 candidates not built yet) get a plain gear.
const GOLD = Color("d8b77b")
const KINDS = {"basic_attack": 0, "shotgun": 1, "bolt_cutter": 2, "automaton": 3, "turret": 4, "relay": 5, "grinder": 6, "shield": 7, "chainsaw": 8, "spring_dash": 9,
	"ballistics": 10, "cutting_precision": 11, "production_efficiency": 12}
const PLAIN = 13

static func draw(canvas: CanvasItem, p: Vector2, id: String, color: Color, scale: float = 1.0) -> void:
	canvas.draw_set_transform(p, 0.0, Vector2(scale, scale))
	shape(canvas, Vector2.ZERO, KINDS.get(id, PLAIN), color)
	canvas.draw_set_transform(Vector2.ZERO)

static func shape(canvas: CanvasItem, p: Vector2, kind: int, color: Color) -> void:
	match kind:
		0:
			canvas.draw_line(p + Vector2(-12, 14), p + Vector2(12, -13), color, 3)
			canvas.draw_arc(p + Vector2(8, -8), 10, -2.6, 0.7, 16, color, 2)
		1:
			for a in [-0.5, 0, 0.5]:
				canvas.draw_line(p + Vector2(-16, 0), p + Vector2(16, 0).rotated(a), color, 2)
		2:
			for sign_x in [-1, 1]:
				canvas.draw_line(p + Vector2(sign_x * 12, 16), p + Vector2(-sign_x * 8, -9), color, 3)
				canvas.draw_line(p + Vector2(-sign_x * 8, -9), p + Vector2(-sign_x * 8, -16), color, 3)
			canvas.draw_circle(p, 3, GOLD)
		3:
			canvas.draw_rect(Rect2(p - Vector2(13, 11), Vector2(26, 22)), color, false, 2)
			canvas.draw_circle(p + Vector2(-5, -3), 2, color)
			canvas.draw_circle(p + Vector2(5, -3), 2, color)
			canvas.draw_line(p + Vector2(0, -11), p + Vector2(0, -18), color, 2)
			for x in [-9, 9]:
				canvas.draw_line(p + Vector2(x, 11), p + Vector2(x, 16), color, 3)
		4:
			canvas.draw_line(p + Vector2(-17, 15), p + Vector2(17, 15), color, 3)
			canvas.draw_line(p + Vector2(0, 15), p + Vector2(0, -5), color, 4)
			canvas.draw_rect(Rect2(p + Vector2(-10, -12), Vector2(23, 12)), color, false, 2)
			canvas.draw_line(p + Vector2(12, -6), p + Vector2(21, -6), color, 3)
		5:
			canvas.draw_arc(p, 13, 0, TAU, 32, color, 2)
			canvas.draw_circle(p, 3, color)
			for angle in [0, PI / 2, PI, 3 * PI / 2]:
				canvas.draw_line(p + Vector2(9, 0).rotated(angle), p + Vector2(20, 0).rotated(angle), color, 2)
		6:
			# Toothed cutting disc on a short handle.
			canvas.draw_line(p + Vector2(-14, 15), p + Vector2(-3, 3), color, 3)
			canvas.draw_arc(p + Vector2(4, -4), 11, 0, TAU, 24, color, 2)
			for k in 8:
				var angle = k * TAU / 8
				canvas.draw_line(p + Vector2(4, -4) + Vector2(11, 0).rotated(angle), p + Vector2(4, -4) + Vector2(15, 0).rotated(angle + 0.25), color, 2)
			canvas.draw_circle(p + Vector2(4, -4), 3, GOLD)
		7:
			# Folding shield plate.
			var plate = PackedVector2Array([p + Vector2(-14, -15), p + Vector2(14, -15), p + Vector2(14, 2), p + Vector2(0, 17), p + Vector2(-14, 2), p + Vector2(-14, -15)])
			canvas.draw_polyline(plate, color, 2)
			canvas.draw_line(p + Vector2(0, -15), p + Vector2(0, 17), color, 2)
		9:
			# Spring dash: a coiled spring behind a forward arrow.
			var coil := PackedVector2Array()
			for k in 9:
				coil.append(p + Vector2(-16 + k * 2.5, 6 if k % 2 == 0 else -6))
			canvas.draw_polyline(coil, color, 2)
			canvas.draw_line(p + Vector2(4, 0), p + Vector2(16, 0), color, 3)
			canvas.draw_line(p + Vector2(16, 0), p + Vector2(10, -6), color, 3)
			canvas.draw_line(p + Vector2(16, 0), p + Vector2(10, 6), color, 3)
		8:
			# Chainsaw bar with teeth along its edge.
			canvas.draw_line(p + Vector2(-16, 14), p + Vector2(-7, 5), color, 4)
			var bar = PackedVector2Array([p + Vector2(-9, 3), p + Vector2(9, -15), p + Vector2(15, -9), p + Vector2(-3, 9), p + Vector2(-9, 3)])
			canvas.draw_polyline(bar, color, 2)
			for k in 4:
				var at: Vector2 = p + Vector2(-5, 1) + Vector2(4.5, -4.5) * k
				canvas.draw_line(at, at + Vector2(-3, -3), color, 2)
		10:
			# Ballistics: a sight ring over a falling arc.
			canvas.draw_arc(p, 12, 0, TAU, 28, color, 2)
			for angle in [0, PI / 2, PI, 3 * PI / 2]:
				canvas.draw_line(p + Vector2(7, 0).rotated(angle), p + Vector2(16, 0).rotated(angle), color, 2)
			canvas.draw_arc(p + Vector2(-2, 14), 15, PI + 0.4, TAU - 0.4, 16, GOLD, 1.5)
		11:
			# Cutting precision: a fine blade with a glint on its edge.
			canvas.draw_line(p + Vector2(-15, 15), p + Vector2(13, -13), color, 3)
			canvas.draw_line(p + Vector2(-15, 15), p + Vector2(-7, 15), color, 3)
			for angle in [0, PI / 2, PI / 4, 3 * PI / 4]:
				canvas.draw_line(p + Vector2(5, -5) + Vector2(6, 0).rotated(angle), p + Vector2(5, -5) - Vector2(6, 0).rotated(angle), GOLD, 1.5)
		12:
			# Production efficiency: a gear with a turning arrow.
			canvas.draw_arc(p, 9, 0, TAU, 20, color, 3)
			for k in 6:
				canvas.draw_line(p + Vector2(9, 0).rotated(k * TAU / 6), p + Vector2(14, 0).rotated(k * TAU / 6), color, 4)
			canvas.draw_arc(p, 18, -2.2, 0.6, 16, GOLD, 2)
			canvas.draw_line(p + Vector2(18, 0).rotated(0.6), p + Vector2(18, 0).rotated(0.6) + Vector2(-6, -1), GOLD, 2)
		_:
			canvas.draw_arc(p, 8, 0, TAU, 20, color, 2)
			for k in 8:
				canvas.draw_line(p + Vector2(8, 0).rotated(k * TAU / 8), p + Vector2(12, 0).rotated(k * TAU / 8), color, 3)
