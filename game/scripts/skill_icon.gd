extends RefCounted
## Skill pictures shared by the HUD action bar and the skill tree window. Shapes are drawn around
## p and span about 36px; draw() scales them for smaller boxes. Skills without a picture of their
## own (03 candidates not built yet) get a plain gear.
const GOLD = Color("d8b77b")
const KINDS = {"basic_attack": 0, "shotgun": 1, "bolt_cutter": 2, "automaton": 3, "turret": 4, "relay": 5, "grinder": 6, "shield": 7, "chainsaw": 8, "spring_dash": 9,
	"ballistics": 10, "cutting_precision": 11, "production_efficiency": 12, "matchlock": 14, "reload": 15, "rifle": 16, "powder_keg": 17, "gatling": 18, "smoke_launcher": 19, "recoil_leap": 20, "artillery": 21, "naval_gun": 22, "recoil_control": 23,
	"guillotine": 24, "hydraulic_press": 25, "compound_executor": 26, "restraint_winch": 27, "exoskeleton": 28, "shock_frame": 29}
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
		14:
			# Matchlock: a long barrel and stock with the glowing match at the lock.
			canvas.draw_line(p + Vector2(-16, 6), p + Vector2(17, -8), color, 3)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(-16, 6), p + Vector2(-17, 13), p + Vector2(-8, 11), p + Vector2(-3, 2)]), color, 2)
			canvas.draw_line(p + Vector2(-4, 1), p + Vector2(-7, -8), color, 2)
			canvas.draw_circle(p + Vector2(-7, -10), 2.5, GOLD)
		16:
			# Rifled long gun: a long barrel with rifling marks and a scope.
			canvas.draw_line(p + Vector2(-17, 8), p + Vector2(18, -10), color, 3)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(-17, 8), p + Vector2(-17, 15), p + Vector2(-9, 11)]), color, 2)
			canvas.draw_rect(Rect2(p + Vector2(-4, -10), Vector2(10, 4)), GOLD)
			for k in 3:
				var at: Vector2 = p + Vector2(6 + k * 4, -3 - k * 2)
				canvas.draw_line(at, at + Vector2(1, 3), GOLD, 1.5)
		23:
			# Recoil control: a barrel braced by a spring.
			canvas.draw_line(p + Vector2(-16, -6), p + Vector2(12, -6), color, 3)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(-10, 0), p + Vector2(-6, 8), p + Vector2(-2, 0), p + Vector2(2, 8), p + Vector2(6, 0), p + Vector2(10, 8)]), GOLD, 2)
			canvas.draw_line(p + Vector2(-14, 12), p + Vector2(14, 12), color, 2)
		21:
			# Rocket barrage: several shells falling onto a ring.
			canvas.draw_arc(p + Vector2(0, 10), 13, 0, TAU, 18, color, 2)
			for k in 3:
				var top: Vector2 = p + Vector2(-12 + k * 9, -16 + (k % 2) * 5)
				canvas.draw_line(top, top + Vector2(5, 12), color, 2)
				canvas.draw_circle(top + Vector2(5, 12), 2.5, GOLD)
		22:
			# Heavy naval gun: one large shell over a burst.
			canvas.draw_line(p + Vector2(-12, -16), p + Vector2(2, 2), color, 5)
			canvas.draw_circle(p + Vector2(4, 4), 3.5, GOLD)
			for a in 6:
				var ray: Vector2 = Vector2(1, 0).rotated(TAU * a / 6.0)
				canvas.draw_line(p + Vector2(6, 8) + ray * 6, p + Vector2(6, 8) + ray * 11, color, 2)
		20:
			# Recoil leap: a blast to the right, the witch's arc thrown back to the left.
			for a in [-0.45, 0, 0.45]:
				canvas.draw_line(p + Vector2(4, 4), p + Vector2(4, 4) + Vector2(13, 0).rotated(a), GOLD, 2)
			canvas.draw_arc(p + Vector2(-6, 8), 10, PI, TAU, 12, color, 2)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(-13, 4), p + Vector2(-16, 9), p + Vector2(-11, 9)]), color, 2)
		19:
			# Smoke launcher: a short tube bank lobbing a canister into a cloud.
			canvas.draw_rect(Rect2(p + Vector2(-17, 4), Vector2(14, 10)), color, false, 2)
			canvas.draw_line(p + Vector2(-12, 4), p + Vector2(-6, -4), color, 2)
			for c in [Vector2(6, -6), Vector2(12, -9), Vector2(14, -2), Vector2(8, 1)]:
				canvas.draw_circle(p + c, 5, Color(color, 0.35))
				canvas.draw_arc(p + c, 5, 0, TAU, 12, color, 1.5)
		18:
			# Rotary cannon: a cluster of barrels around a hub, with a spin arc.
			for k in 3:
				canvas.draw_line(p + Vector2(-16, -5 + k * 5), p + Vector2(12, -5 + k * 5), color, 2)
			canvas.draw_rect(Rect2(p + Vector2(10, -9), Vector2(6, 18)), color, false, 2)
			canvas.draw_arc(p + Vector2(-16, 0), 9, 1.9, 4.4, 10, GOLD, 2)
		17:
			# Powder keg: a hooped drum on its side with a lit fuse.
			canvas.draw_rect(Rect2(p + Vector2(-14, -7), Vector2(22, 18)), color, false, 2)
			for x in [-8, 2]:
				canvas.draw_line(p + Vector2(x, -7), p + Vector2(x, 11), color, 2)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(8, -3), p + Vector2(12, -9), p + Vector2(15, -12)]), color, 2)
			canvas.draw_circle(p + Vector2(16, -13), 2.5, GOLD)
		24:
			# Guillotine: two posts, a crossbar and a slanted blade above the floor line.
			for x in [-11, 11]:
				canvas.draw_line(p + Vector2(x, 16), p + Vector2(x, -15), color, 3)
			canvas.draw_line(p + Vector2(-14, -15), p + Vector2(14, -15), color, 3)
			canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-9, -6), p + Vector2(9, -10), p + Vector2(9, -3), p + Vector2(-9, -1)]), GOLD)
			canvas.draw_line(p + Vector2(-17, 16), p + Vector2(17, 16), color, 2)
		25:
			# Hydraulic press: a piston over a wide platen, with impact lines.
			canvas.draw_rect(Rect2(p + Vector2(-5, -17), Vector2(10, 12)), color, false, 2)
			canvas.draw_line(p + Vector2(0, -5), p + Vector2(0, 3), color, 4)
			canvas.draw_rect(Rect2(p + Vector2(-15, 3), Vector2(30, 6)), GOLD)
			for x in [-14, 14]:
				canvas.draw_line(p + Vector2(x, 13), p + Vector2(x * 1.25, 17), color, 2)
		26:
			# Compound executor: a cage with a saw disk inside.
			canvas.draw_rect(Rect2(p - Vector2(15, 14), Vector2(30, 28)), color, false, 2)
			for x in [-5, 5]:
				canvas.draw_line(p + Vector2(x, -14), p + Vector2(x, 14), color, 1.5)
			canvas.draw_arc(p + Vector2(0, 4), 7, 0, TAU, 14, GOLD, 2)
			for k in 6:
				canvas.draw_line(p + Vector2(0, 4) + Vector2(7, 0).rotated(k * TAU / 6), p + Vector2(0, 4) + Vector2(10, 0).rotated(k * TAU / 6 + 0.3), GOLD, 2)
		27:
			# Restraint winch: a drum with a line running out to a hook.
			canvas.draw_arc(p + Vector2(-9, 6), 8, 0, TAU, 16, color, 2)
			canvas.draw_line(p + Vector2(-9, -2), p + Vector2(13, -10), color, 1.5)
			canvas.draw_arc(p + Vector2(13, -5), 5, -PI * 0.5, PI * 0.9, 10, GOLD, 2.5)
		28:
			# Exoskeleton: a spine with ribs and jointed arm braces.
			canvas.draw_line(p + Vector2(0, -16), p + Vector2(0, 14), color, 3)
			for y in [-10, -3, 4]:
				canvas.draw_line(p + Vector2(-7, y), p + Vector2(7, y), color, 2)
			for sx in [-1, 1]:
				canvas.draw_polyline(PackedVector2Array([p + Vector2(sx * 8, -12), p + Vector2(sx * 15, -2), p + Vector2(sx * 13, 10)]), GOLD, 2)
				canvas.draw_circle(p + Vector2(sx * 15, -2), 2.5, GOLD)
		29:
			# Shock-absorbing frame: a coil spring between two plates.
			canvas.draw_line(p + Vector2(-14, -14), p + Vector2(14, -14), color, 3)
			canvas.draw_line(p + Vector2(-14, 14), p + Vector2(14, 14), color, 3)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(0, -14), p + Vector2(-8, -9), p + Vector2(8, -4), p + Vector2(-8, 1), p + Vector2(8, 6), p + Vector2(-8, 10), p + Vector2(0, 14)]), GOLD, 2)
		15:
			# Reload mechanism: rounds feeding into a gear.
			canvas.draw_arc(p + Vector2(5, 3), 8, 0, TAU, 18, color, 2)
			for k in 6:
				canvas.draw_line(p + Vector2(5, 3) + Vector2(8, 0).rotated(k * TAU / 6), p + Vector2(5, 3) + Vector2(12, 0).rotated(k * TAU / 6), color, 3)
			for k in 3:
				canvas.draw_rect(Rect2(p + Vector2(-17 + k * 6, -15 + k * 4), Vector2(4, 8)), GOLD)
		_:
			canvas.draw_arc(p, 8, 0, TAU, 20, color, 2)
			for k in 8:
				canvas.draw_line(p + Vector2(8, 0).rotated(k * TAU / 8), p + Vector2(12, 0).rotated(k * TAU / 8), color, 3)
