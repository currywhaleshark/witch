extends RefCounted
## Temporary item pictures for the grid inventory: simple shapes drawn per base, so a rare's
## invented name still shows what it is. Replace with painted icons later; callers only pass
## the canvas, the cell rectangle and the item.
const BRASS = Color("d8b77b")
const COPPER = Color("c47a4c")
const SILVER = Color("c9d1d6")
const CLOTH = Color("8fa7b3")
const NAVY = Color("3c5a78")
const LEATHER = Color("8a5a3c")
const PAPER = Color("d9d2b8")
const INK = Color("2f5f8a")
const GLASS = Color("9fd6d2")
const DARK = Color("10181c")

static func draw(canvas: CanvasItem, rect: Rect2, item: Dictionary, items) -> void:
	var rarity := Color(items.data.rarity_colors[item.rarity])
	canvas.draw_rect(rect.grow(-1), Color(rarity, 0.16))
	canvas.draw_rect(rect.grow(-1), Color(rarity, 0.75), false, 1.0)
	var box := rect.grow(-maxf(4.0, minf(rect.size.x, rect.size.y) * 0.12))
	match item.base:
		"glass_orb":
			orb(canvas, box, GLASS)
		"crystal_core":
			crystal(canvas, box)
		"ribbon_tie":
			bow(canvas, box, Color("c25b6a"))
		"star_pin":
			star_pin(canvas, box)
		"cotton_coat":
			coat(canvas, box, CLOTH)
		"quilted_cape":
			cape(canvas, box, NAVY)
		"cotton_gloves":
			glove(canvas, box, Color("e8e2d2"))
		"work_gloves":
			glove(canvas, box, LEATHER)
		"sneakers":
			shoe(canvas, box, Color("e8e2d2"), false)
		"leather_boots":
			shoe(canvas, box, LEATHER, true)
		"brass_brooch":
			brooch(canvas, box, BRASS, false)
		"silver_brooch":
			brooch(canvas, box, SILVER, true)
		"copper_ring":
			ring(canvas, box, COPPER)
		"silver_ring":
			ring(canvas, box, SILVER)
		_:
			var family: String = items.bases[item.base].get("family", "")
			if family == "blueprint":
				blueprint(canvas, box)
			else:
				gear(canvas, box, BRASS if item.base != "part_power" else COPPER)
	sockets(canvas, rect, item, items)

static func sockets(canvas: CanvasItem, rect: Rect2, item: Dictionary, items) -> void:
	# Empty sockets as dark holes, filled ones with the piece's syllable, along the bottom edge.
	var count: int = int(item.get("sockets", 0))
	if count == 0:
		return
	var radius := minf(6.5, rect.size.x / (count * 3.2))
	var font: Font = ThemeDB.fallback_font
	for i in count:
		var center := Vector2(rect.position.x + rect.size.x * (i + 1) / (count + 1), rect.end.y - radius - 4)
		canvas.draw_circle(center, radius, DARK)
		canvas.draw_arc(center, radius, 0, TAU, 20, Color("7c8b8f"), 1.0)
		if i < item.get("pieces", []).size():
			canvas.draw_circle(center, radius - 1.5, Color("4a3a5c"))
			var syllable: String = items.glyph(item.pieces[i])
			canvas.draw_string(font, center + Vector2(-radius, radius * 0.45), syllable, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, int(radius * 1.2), Color("f0e4ff"))

static func piece(canvas: CanvasItem, rect: Rect2, syllable: String, lit: bool = true) -> void:
	# A name piece: a dark violet chip with its syllable, faded when none are left.
	var center := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.38
	var alpha := 1.0 if lit else 0.3
	canvas.draw_circle(center, radius, Color("4a3a5c", alpha))
	canvas.draw_arc(center, radius, 0, TAU, 24, Color("b9a2d8", alpha), 1.5)
	canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius * 0.42), syllable, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, int(radius * 1.1), Color("f0e4ff", alpha))

static func silhouette(canvas: CanvasItem, rect: Rect2, slot: String) -> void:
	# A faint outline of what goes in an empty worn slot, in place of its name.
	var faint := Color(1, 1, 1, 0.07)
	var box := rect.grow(-maxf(6.0, minf(rect.size.x, rect.size.y) * 0.18))
	match slot:
		"head":
			bow(canvas, box, faint)
		"brooch":
			canvas.draw_circle(box.get_center(), box.size.x * 0.4, faint)
		"medium":
			poly(canvas, box, [[0.5, 0.05], [0.78, 0.35], [0.62, 0.95], [0.38, 0.95], [0.22, 0.35]], faint)
		"outfit":
			cape(canvas, box, faint)
		"ring":
			canvas.draw_arc(box.get_center(), box.size.x * 0.32, 0, TAU, 24, faint, maxf(2.0, box.size.x * 0.12))
		"gloves":
			glove(canvas, box, faint)
		"shoes":
			shoe(canvas, box, faint, true)

static func anvil(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	# The salvage box: a small anvil.
	var fit := Rect2(box.get_center() - Vector2(box.size.y, box.size.y) * 0.6, Vector2(box.size.y, box.size.y) * 1.2)
	poly(canvas, fit, [[0.05, 0.2], [0.9, 0.2], [0.9, 0.42], [0.66, 0.5], [0.62, 0.72], [0.8, 0.9], [0.2, 0.9], [0.38, 0.72], [0.34, 0.5], [0.05, 0.38]], color)

static func at(box: Rect2, x: float, y: float) -> Vector2:
	return box.position + Vector2(box.size.x * x, box.size.y * y)

static func poly(canvas: CanvasItem, box: Rect2, points: Array, color: Color) -> void:
	var shape := PackedVector2Array()
	for p in points:
		shape.append(at(box, p[0], p[1]))
	canvas.draw_colored_polygon(shape, color)
	shape.append(shape[0])
	canvas.draw_polyline(shape, color.darkened(0.45), 1.0)

static func orb(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	var center := at(box, 0.5, 0.42)
	var radius := box.size.x * 0.36
	poly(canvas, box, [[0.3, 0.95], [0.7, 0.95], [0.62, 0.72], [0.38, 0.72]], BRASS)
	canvas.draw_circle(center, radius, Color(color, 0.85))
	canvas.draw_arc(center, radius, 0, TAU, 28, color.darkened(0.4), 1.0)
	canvas.draw_circle(center + Vector2(-radius * 0.35, -radius * 0.35), radius * 0.22, Color(1, 1, 1, 0.7))

static func crystal(canvas: CanvasItem, box: Rect2) -> void:
	poly(canvas, box, [[0.3, 0.95], [0.7, 0.95], [0.62, 0.78], [0.38, 0.78]], BRASS)
	poly(canvas, box, [[0.5, 0.05], [0.78, 0.35], [0.66, 0.78], [0.34, 0.78], [0.22, 0.35]], Color("8fc6e8"))
	poly(canvas, box, [[0.5, 0.05], [0.58, 0.4], [0.5, 0.78], [0.42, 0.4]], Color("cfeaf7"))

static func bow(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	poly(canvas, box, [[0.08, 0.25], [0.46, 0.45], [0.08, 0.7]], color)
	poly(canvas, box, [[0.92, 0.25], [0.54, 0.45], [0.92, 0.7]], color)
	poly(canvas, box, [[0.44, 0.5], [0.3, 0.95], [0.4, 0.95], [0.5, 0.6], [0.6, 0.95], [0.7, 0.95], [0.56, 0.5]], color.darkened(0.15))
	canvas.draw_circle(at(box, 0.5, 0.47), box.size.x * 0.09, color.lightened(0.2))

static func star_pin(canvas: CanvasItem, box: Rect2) -> void:
	canvas.draw_line(at(box, 0.35, 0.6), at(box, 0.9, 0.95), SILVER, 2.0)
	var points: Array = []
	for i in 10:
		var radius := 0.32 if i % 2 == 0 else 0.14
		var angle := -PI / 2 + i * TAU / 10
		points.append([0.38 + cos(angle) * radius, 0.4 + sin(angle) * radius])
	poly(canvas, box, points, BRASS)

static func coat(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	poly(canvas, box, [[0.32, 0.05], [0.68, 0.05], [0.95, 0.25], [0.88, 0.55], [0.76, 0.5], [0.78, 0.97], [0.22, 0.97], [0.24, 0.5], [0.12, 0.55], [0.05, 0.25]], color)
	canvas.draw_line(at(box, 0.5, 0.12), at(box, 0.5, 0.97), color.darkened(0.4), 1.0)
	for y in [0.35, 0.55, 0.75]:
		canvas.draw_circle(at(box, 0.56, y), 2.0, BRASS)

static func cape(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	poly(canvas, box, [[0.38, 0.05], [0.62, 0.05], [0.95, 0.95], [0.05, 0.95]], color)
	poly(canvas, box, [[0.3, 0.05], [0.7, 0.05], [0.72, 0.2], [0.28, 0.2]], color.lightened(0.25))
	for x in [0.3, 0.5, 0.7]:
		canvas.draw_line(at(box, x, 0.3), at(box, x + (x - 0.5) * 0.4, 0.92), color.darkened(0.35), 1.0)

static func glove(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	poly(canvas, box, [[0.3, 0.95], [0.3, 0.45], [0.12, 0.32], [0.18, 0.22], [0.34, 0.3], [0.36, 0.08], [0.72, 0.08], [0.78, 0.6], [0.7, 0.95]], color)
	canvas.draw_line(at(box, 0.3, 0.8), at(box, 0.7, 0.8), color.darkened(0.35), 1.5)

static func shoe(canvas: CanvasItem, box: Rect2, color: Color, boot: bool) -> void:
	var top := 0.08 if boot else 0.42
	poly(canvas, box, [[0.18, top], [0.5, top], [0.52, 0.62], [0.92, 0.72], [0.92, 0.88], [0.12, 0.88]], color)
	canvas.draw_rect(Rect2(at(box, 0.12, 0.86), Vector2(box.size.x * 0.8, box.size.y * 0.07)), color.darkened(0.5))

static func brooch(canvas: CanvasItem, box: Rect2, metal: Color, ornate: bool) -> void:
	var center := at(box, 0.5, 0.5)
	var radius := box.size.x * 0.4
	if ornate:
		for i in 8:
			var angle := i * TAU / 8
			canvas.draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.85, radius * 0.25, metal)
	canvas.draw_circle(center, radius * 0.75, metal)
	canvas.draw_circle(center, radius * 0.42, Color("5aa6a0"))

static func ring(canvas: CanvasItem, box: Rect2, metal: Color) -> void:
	var center := at(box, 0.5, 0.58)
	canvas.draw_arc(center, box.size.x * 0.3, 0, TAU, 28, metal, maxf(2.0, box.size.x * 0.1))
	canvas.draw_circle(at(box, 0.5, 0.22), box.size.x * 0.13, Color("d06a6a"))

static func blueprint(canvas: CanvasItem, box: Rect2) -> void:
	poly(canvas, box, [[0.12, 0.08], [0.88, 0.08], [0.88, 0.92], [0.12, 0.92]], Color("355f86"))
	for y in [0.25, 0.4, 0.55, 0.7]:
		canvas.draw_line(at(box, 0.2, y), at(box, 0.8, y), Color(PAPER, 0.35), 1.0)
	gear(canvas, Rect2(at(box, 0.25, 0.3), box.size * 0.5), PAPER)

static func gear(canvas: CanvasItem, box: Rect2, color: Color) -> void:
	var points: Array = []
	for i in 16:
		var radius := 0.46 if i % 2 == 0 else 0.34
		var angle := i * TAU / 16
		points.append([0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius])
	poly(canvas, box, points, color)
	canvas.draw_circle(at(box, 0.5, 0.5), box.size.x * 0.13, DARK)
