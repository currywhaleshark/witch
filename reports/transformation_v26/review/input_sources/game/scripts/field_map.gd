extends Node3D
## Field layout, navigation and sight lines.
## "flat" is the original open test arena: no navmesh, routes are straight lines, ground at y=0.
## Any other id loads res://data/maps/<id>.json: floors and stairs at their own heights, props, and
## alley edges built as rows of lots (walled houses, open shopfronts, plain walls), with a navmesh
## baked at runtime.
const Shape = preload("res://scripts/shapes.gd")
const Decoration = preload("res://scripts/alley_decoration.gd")
const Props = preload("res://scripts/alley_props.gd")
# Walls and props block bodies and sight; floors only carry feet and the navmesh.
const WORLD_LAYER = 1
const FLOOR_LAYER = 16
# Sight lines and orbs fly at chest height above the ground, so low props block feet but not shots.
const SIGHT_HEIGHT = 1.2
const FADE_ALPHA = 0.2
# Camera-side walls and shopfronts stay this see-through all the time.
const FRONT_ALPHA = 0.35
# The fixed camera looks from +x +z; walls on that side of a floor stand between it and the field.
const CAMERA_SIDE = Vector3(0.70710678, 0, 0.70710678)
# Navmesh points this far above the floor beneath them are prop tops, not walkable ground.
const PROP_TOP = 0.6
# Lot kit: garden walls stand this high above the alley; lots that would hide the field are cut to CUT_H.
# Sized for the 1.7m witch: garden walls a little over head height, 2.2m doors, 3.0m storeys.
const FENCE_H = 1.8
const CUT_H = 2.5
const STOREY = 3.0
# Utility poles stand this far out from the far walls, inside the margin walkers keep from walls.
const POLE_V = -0.26
const LOT_WIDTH = {"house": [6.0, 8.4], "shop": [4.2, 6.0], "plain": [5.0, 7.5]}
const SIGNS = ["세탁소", "철물점", "슈퍼", "미용실", "복덕방", "분식", "약국", "만화방"]
const BRICK = ["8a4a38", "7a4a3c", "96604a"]
const CEMENT = ["a59f92", "b4ab98", "8f9a8a", "a7a9a2"]
const GATES = ["3f6b55", "3d5a78", "6b4a32", "7a3a32", "4a5560"]
const WALLS = ["c9bba5", "8a5a48", "b8b2a6", "9c6b52", "a9a39a", "c2a789", "8f8577", "b9ab92", "d6cfc0"]
const ROOFS = ["4f7a5a", "5d6a70", "6d5a4a"]
const BOARDS = ["2f5d8a", "b8433a", "e0b531", "3f7a52", "efe9dc", "5a3f78"]
# Tileable CC0 surfaces (assets/textures/alley_v1/README.md), projected in world space so boxes need
# no UVs and neighbouring pieces line up. "tile" is metres per repeat; "reference" is the texture's
# average colour, so a piece keeps its palette colour on average and the texture only adds detail.
const TEXTURES = "res://assets/textures/alley_v1/%s_%s.jpg"
const SURFACES = {
	"brick": {"tile": 1.1, "reference": "9f735b", "normal": 1.0},
	"block": {"tile": 2.4, "reference": "bebebe", "normal": 1.0},
	"plaster": {"tile": 2.5, "reference": "bebebe", "normal": 0.6},
	"concrete": {"tile": 2.5, "reference": "bebebe", "normal": 0.5},
	"asphalt": {"tile": 4.0, "reference": "bebebe", "normal": 0.6},
	"metal": {"tile": 1.6, "reference": "bebebe", "normal": 0.4},
}
var id = "flat"
var data: Dictionary = {}
var bounds = Rect2(-14.25, -12.25, 28.5, 24.5)
var region: NavigationRegion3D
var built_iteration = 0
var fadeable: Array = []
var faded: Array = []
var floor_rects: Array = []
var lots: Array = []
var claimed: Array = []
var poles: Array = []
var sign_font: SystemFont
var textures: Dictionary = {}
var decorations = Decoration.new()
# The arena's own light, kept so the flat arena can return to it after a lit map.
var base_light: Dictionary = {}

func build(map_id: String) -> void:
	id = map_id
	for child in get_children():
		child.free()
	fadeable.clear()
	faded.clear()
	floor_rects.clear()
	lots.clear()
	claimed.clear()
	poles.clear()
	region = null
	data = {}
	decorations.configure(map_id)
	if map_id == "flat":
		_build_flat()
		return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % map_id))
	var b: Array = data.bounds
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	region = NavigationRegion3D.new()
	add_child(region)
	var mesh = NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = WORLD_LAYER | FLOOR_LAYER
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.25
	region.navigation_mesh = mesh
	for entry in data.floors:
		var floor_rect: Array = entry if entry is Array else entry.rect
		var top: float = 0.0 if entry is Array else float(entry.get("top", 0.0))
		var color: String = entry[4] if entry is Array else entry.color
		floor_rects.append(floor_rect)
		_skin(_solid(region, floor_rect, -0.7, top, Color(color), FLOOR_LAYER).get_child(0), "asphalt")
	for stair in data.get("stairs", []):
		_stairs(stair)
	var edges: Array = data.get("edges", [])
	for i in edges.size():
		_edge(edges[i], i)
	for entry in data.walls:
		_wall(entry)
	for mark in data.get("marks", []):
		# Flat floor paint (kerb lines, gear plates); purely visual.
		if not decorations.layout.is_empty(): continue # Replaced by the generated erosion overlays.
		var base: float = mark[5] if mark.size() > 5 else 0.0
		Shape.box(self, Vector3((mark[0] + mark[2]) / 2.0, base + 0.006, (mark[1] + mark[3]) / 2.0), Vector3(mark[2] - mark[0], 0.012, mark[3] - mark[1]), Color(mark[4]))
	var buildings: Array = data.get("buildings", [])
	for i in buildings.size():
		_building(self, buildings[i], str(i))
	decorations.floors(self)
	region.bake_navigation_mesh(false)
	# The navigation server picks the new mesh up a few physics frames later; until then
	# routes fall back to straight lines (see nav_ready).
	built_iteration = NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)

func apply_lighting(env: Environment, sun: DirectionalLight3D) -> void:
	# Time of day from the map's "lighting" block; maps without one keep the arena's default light.
	if base_light.is_empty():
		base_light = {"sun_rotation": sun.rotation_degrees, "sun_color": sun.light_color, "sun_energy": sun.light_energy,
			"ambient_color": env.ambient_light_color, "ambient_energy": env.ambient_light_energy, "background": env.background_color}
	var light: Dictionary = data.get("lighting", {})
	var pick = func(key: String):
		if not light.has(key):
			return base_light.get(key)
		var value = light[key]
		return Vector3(value[0], value[1], value[2]) if value is Array else (Color(value) if value is String else value)
	sun.rotation_degrees = pick.call("sun_rotation")
	sun.light_color = pick.call("sun_color")
	sun.light_energy = pick.call("sun_energy")
	env.ambient_light_color = pick.call("ambient_color")
	env.ambient_light_energy = pick.call("ambient_energy")
	env.background_color = pick.call("background")
	env.fog_enabled = light.has("fog_color")
	if env.fog_enabled:
		env.fog_light_color = Color(light.fog_color)
		env.fog_density = float(light.get("fog_density", 0.01))
		env.fog_sun_scatter = float(light.get("fog_sun_scatter", 0.0))
		# The void beyond the map stays its own dark colour instead of turning into haze.
		env.fog_sky_affect = 0.0
	env.glow_enabled = light.has("glow")
	if env.glow_enabled:
		env.glow_intensity = float(light.glow)
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.0

func nav_ready() -> bool:
	return region == null or NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > built_iteration + 1

func _solid(parent: Node3D, rect: Array, bottom: float, top: float, color: Color, layer: int) -> StaticBody3D:
	# Axis-aligned block [x0, z0, x1, z1] from bottom to top, with collision on the given layer.
	var size = Vector3(rect[2] - rect[0], top - bottom, rect[3] - rect[1])
	var body = StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	body.position = Vector3((rect[0] + rect[2]) / 2.0, (bottom + top) / 2.0, (rect[1] + rect[3]) / 2.0)
	Shape.box(body, Vector3.ZERO, size, color)
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	return body

func _skin(piece: MeshInstance3D, surface: String) -> MeshInstance3D:
	# Gives a kit piece a tileable surface tinted to its palette colour.
	var spec: Dictionary = SURFACES[surface]
	var material: StandardMaterial3D = piece.material_override
	var tint: Color = material.albedo_color
	var reference = Color(spec.reference)
	material.albedo_color = Color(tint.r / reference.r, tint.g / reference.g, tint.b / reference.b)
	material.albedo_texture = _texture(surface, "color")
	material.normal_enabled = true
	material.normal_texture = _texture(surface, "normal")
	material.normal_scale = spec.normal
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 8.0
	material.uv1_scale = Vector3.ONE / float(spec.tile)
	return piece

func _texture(surface: String, kind: String) -> Texture2D:
	var key: String = TEXTURES % [surface, kind]
	if not textures.has(key):
		textures[key] = load(key)
	return textures[key]

func _stairs(stair: Dictionary) -> void:
	# Real steps between two floor heights, each rise low enough for feet and the navmesh to climb.
	var r: Array = stair.rect
	var count: int = int(stair.steps)
	var low: float = stair.from
	var rise: float = (float(stair.to) - low) / count
	for i in count:
		var t0: float = float(i) / count
		var t1: float = float(i + 1) / count
		var rect: Array
		if stair.axis == "x":
			rect = [lerpf(r[0], r[2], t0), r[1], lerpf(r[0], r[2], t1), r[3]]
		else:
			rect = [r[0], lerpf(r[1], r[3], t0), r[2], lerpf(r[1], r[3], t1)]
		floor_rects.append(rect)
		var top: float = low + rise * (i + 1)
		var tread: StaticBody3D = _solid(region, rect, -0.7, top, Color(stair.color).lightened(0.1 * (i % 2)), FLOOR_LAYER)
		_skin(tread.get_child(0), "concrete")
		# A pale nosing strip along each step's leading edge makes the flight read from above.
		var width: float = (rect[3] - rect[1]) if stair.axis == "x" else (rect[2] - rect[0])
		var edge = Vector3(rect[0] - tread.position.x + 0.06, top - tread.position.y + 0.006, 0) if stair.axis == "x" else Vector3(0, top - tread.position.y + 0.006, rect[1] - tread.position.z + 0.06)
		Shape.box(tread, edge, Vector3(0.12, 0.012, width) if stair.axis == "x" else Vector3(width, 0.012, 0.12), Color("c8c2b2"))

func _wall(entry) -> void:
	# v1 maps list walls as arrays; v2 maps name their kind (wall, prop) and base height.
	var rect: Array = entry if entry is Array else entry.rect
	var height: float = entry[4] if entry is Array else float(entry.h)
	var color: Color = Color(entry[5] if entry is Array else entry.color)
	var base: float = 0.0 if entry is Array else float(entry.get("base", 0.0))
	var kind: String = ("wall" if height > SIGHT_HEIGHT else "prop") if entry is Array else entry.get("kind", "wall")
	var body: StaticBody3D = _solid(region, rect, base, base + height, color, WORLD_LAYER)
	# Props with a model get it; the rest keep the decoration pass's dressing over their block.
	if kind == "prop" and not (entry is Dictionary and Props.build(body, entry.get("model", ""), rect, height)):
		decorations.prop(body,rect,base,base+height)
	if kind == "prop" or height <= SIGHT_HEIGHT:
		return
	_fadeable(body, rect)

func _fadeable(body: StaticBody3D, rect: Array) -> void:
	var entry_info = {"body": body, "meshes": body.find_children("*", "GeometryInstance3D", true, false), "rest": FRONT_ALPHA if _faces_camera(rect) else 1.0}
	body.set_meta("fade", true)
	fadeable.append(entry_info)
	_set_alpha(entry_info, entry_info.rest)

func _floor_top(x: float, z: float) -> float:
	# Walkable height at a point straight from the map data (usable before physics runs); -1 off the floors.
	var best := -1.0
	for entry in data.floors:
		var r: Array = entry if entry is Array else entry.rect
		if x >= r[0] and x <= r[2] and z >= r[1] and z <= r[3]:
			best = maxf(best, 0.0 if entry is Array else float(entry.get("top", 0.0)))
	for stair in data.get("stairs", []):
		var r: Array = stair.rect
		if x >= r[0] and x <= r[2] and z >= r[1] and z <= r[3]:
			var t: float = (x - r[0]) / (r[2] - r[0]) if stair.axis == "x" else (z - r[1]) / (r[3] - r[1])
			var steps: int = int(stair.steps)
			best = maxf(best, lerpf(stair.from, stair.to, minf(floorf(t * steps) + 1, steps) / steps))
	return best

# Lots are laid out in an edge frame: u runs along the edge, v runs outward from the alley face
# (negative v overhangs the alley), y is height.
func _frame(edge: Dictionary) -> Dictionary:
	var r: Array = edge.rect
	match edge.out:
		"-z": return {"along_x": true, "face": r[3], "sign": -1.0, "out": edge.out}
		"+z": return {"along_x": true, "face": r[1], "sign": 1.0, "out": edge.out}
		"-x": return {"along_x": false, "face": r[2], "sign": -1.0, "out": edge.out}
	return {"along_x": false, "face": r[0], "sign": 1.0, "out": edge.out}

func _at(f: Dictionary, u: float, v: float, y: float) -> Vector3:
	var w: float = f.face + f.sign * v
	return Vector3(u, y, w) if f.along_x else Vector3(w, y, u)

func _area(f: Dictionary, u0: float, u1: float, v0: float, v1: float) -> Array:
	var a: Vector3 = _at(f, u0, v0, 0)
	var b: Vector3 = _at(f, u1, v1, 0)
	return [minf(a.x, b.x), minf(a.z, b.z), maxf(a.x, b.x), maxf(a.z, b.z)]

func _piece(parent: Node3D, f: Dictionary, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, color: Color) -> MeshInstance3D:
	var pos: Vector3 = _at(f, (u0 + u1) / 2.0, (v0 + v1) / 2.0, (y0 + y1) / 2.0)
	var size = Vector3(u1 - u0, y1 - y0, v1 - v0) if f.along_x else Vector3(v1 - v0, y1 - y0, u1 - u0)
	return Shape.box(parent, pos, size, color)

func _grounds(f: Dictionary, u0: float, u1: float) -> Vector2:
	# Lowest and highest alley floor just inside the edge between u0 and u1 (0 where there is none).
	var low := INF
	var high := -INF
	var steps: int = maxi(1, ceili((u1 - u0) / 0.3))
	for i in steps + 1:
		var p: Vector3 = _at(f, lerpf(u0, u1, float(i) / steps), -0.3, 0)
		var top: float = _floor_top(p.x, p.z)
		if top >= 0.0:
			low = minf(low, top)
			high = maxf(high, top)
	return Vector2.ZERO if high == -INF else Vector2(low, high)

func _chunks(f: Dictionary, u0: float, u1: float) -> Array:
	# Level runs stay whole; runs beside stairs step in pieces that follow the floor.
	var g: Vector2 = _grounds(f, u0, u1)
	var count: int = 1 if is_equal_approx(g.x, g.y) else ceili((u1 - u0) / 1.2)
	var out: Array = []
	for i in count:
		var a: float = lerpf(u0, u1, float(i) / count)
		var b: float = lerpf(u0, u1, float(i + 1) / count)
		out.append([a, b, _grounds(f, a, b).y])
	return out

func _hides_floor(rect: Array, height: float) -> bool:
	# The camera looks down at 30 degrees, so anything this tall covers floor up to about 1.7x its
	# height behind it along the view line. Only floor a witch can stand on counts (0.6 from edges).
	var reach: float = height * 1.8
	for sx in 5:
		for sz in 5:
			var p = Vector3(lerpf(rect[0], rect[2], sx / 4.0), 0, lerpf(rect[1], rect[3], sz / 4.0))
			var d := 0.5
			while d <= reach:
				var q: Vector3 = p - CAMERA_SIDE * d
				if _on_floor(q + Vector3(0.6, 0, 0)) and _on_floor(q - Vector3(0.6, 0, 0)) and _on_floor(q + Vector3(0, 0, 0.6)) and _on_floor(q - Vector3(0, 0, 0.6)):
					return true
				d += 0.5
	return false

func _claim(rect: Array) -> bool:
	# Building footprints from neighbouring edges must not overlap; a later lot loses its building.
	for r in claimed:
		if rect[0] < r[2] and rect[2] > r[0] and rect[1] < r[3] and rect[3] > r[1]:
			return false
	claimed.append(rect)
	return true

func _edge(edge: Dictionary, index: int) -> void:
	# An alley edge as a row of lots: listed lots in order, or a seeded fill from the edge's kinds.
	# Lots without a width get a seeded one, stretched so the row exactly fills the edge.
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("%s:edge:%d" % [id, index])
	var f: Dictionary = _frame(edge)
	var r: Array = edge.rect
	var start: float = r[0] if f.along_x else r[1]
	var length: float = (r[2] - r[0]) if f.along_x else (r[3] - r[1])
	var row: Array = edge.get("lots", []).duplicate(true)
	if row.is_empty():
		var kinds: Array = edge.get("kinds", ["house", "shop"])
		for i in maxi(1, roundi(length / 6.4)):
			row.append({"kind": kinds[rng.randi() % kinds.size()]})
	var fixed := 0.0
	var free := 0.0
	for lot in row:
		if lot.has("w"):
			fixed += float(lot.w)
		else:
			lot.w = rng.randf_range(LOT_WIDTH[lot.kind][0], LOT_WIDTH[lot.kind][1])
			lot.free = true
			free += lot.w
	var stretch: float = (length - fixed) / free if free > 0 else 1.0
	var spans: Array = []
	var u: float = start
	for lot in row:
		var w: float = float(lot.w) * (stretch if lot.get("free", false) else 1.0)
		# A shopfront needs level frontage; seeded shops beside stairs become houses.
		var g: Vector2 = _grounds(f, u, u + w)
		if lot.kind == "shop" and lot.get("free", false) and not is_equal_approx(g.x, g.y):
			lot.kind = "house"
		spans.append([u, u + w])
		u += w
	var first: int = lots.size()
	for i in row.size():
		var walled_next: bool = i + 1 < row.size() and row[i + 1].kind != "shop"
		_lot(f, row[i], spans[i][0], spans[i][1], walled_next, rng, "%d:%d" % [index, i])
	# Concrete utility poles stand on the alley side of the far edges' walls, each with a street lamp
	# reaching over the alley and wires running pole to pole. Camera-side edges get none.
	if f.sign > 0:
		return
	var gap: float = float(data.get("lighting", {}).get("pole_gap", 11.0))
	var tops: Array = []
	var last := -INF
	for i in (row.size() if edge.get("poles", true) else 0):
		if row[i].kind == "shop" or spans[i][1] - spans[i][0] < 1.6:
			continue
		# Near a lot end, but never in front of the gate and its posts.
		var gate: Array = lots[first + i].get("gate_span", [])
		for at in [spans[i][1] - 0.6, spans[i][0] + 0.6]:
			var foot: Vector3 = _at(f, at, POLE_V, 0)
			var clear_of_gate: bool = gate.is_empty() or at < gate[0] - 0.65 or at > gate[1] + 0.65
			if clear_of_gate and at - last >= gap and not _hides_floor([foot.x - 0.2, foot.z - 0.2, foot.x + 0.2, foot.z + 0.2], 7.0):
				last = at
				tops.append(_pole(f, at, _grounds(f, at - 0.2, at + 0.2).y))
				break
	_clutter(f, spans, first, tops)
	for i in tops.size() - 1:
		for drop in [0.0, 0.3]:
			_wire(tops[i] - Vector3(0, drop, 0), tops[i + 1] - Vector3(0, drop, 0))
	# Each building on the edge takes its service cable from the nearest pole.
	for i in row.size():
		var drop: Vector3 = lots[first + i].get("drop", Vector3.INF)
		if drop == Vector3.INF or tops.is_empty():
			continue
		var near: Vector3 = tops[0]
		for top in tops:
			if Vector2(top.x - drop.x, top.z - drop.z).length() < Vector2(near.x - drop.x, near.z - drop.z).length():
				near = top
		if Vector2(near.x - drop.x, near.z - drop.z).length() < 10.0:
			_wire(near - Vector3(0, 0.9, 0), drop, 0.35, 2)

func _clutter(f: Dictionary, spans: Array, first: int, tops: Array) -> void:
	# Small heaps against the far walls, in the strip walkers keep clear of walls: planters and spent
	# briquettes by houses, crates and boxes by shops, rubble sacks by empty lots. They keep clear of
	# gates, poles, shop doors and A-frames, and of stairs.
	for i in spans.size():
		var info: Dictionary = lots[first + i]
		var u0: float = spans[i][0]
		var u1: float = spans[i][1]
		var rng = RandomNumberGenerator.new()
		rng.seed = hash("%s:clutter:%s" % [id, info.body.get_meta("lot_key")])
		var state: String = info.body.get_meta("alley_state", "open")
		var kinds: Array = {"house": ["tubs", "briquettes"], "plain": ["sacks", "briquettes", "boxes"], "shop": ["crates", "boxes"]}[info.kind]
		if state == "vacant":
			kinds = ["sacks", "boxes", "briquettes"]
		var heaps: int = 1 if info.kind == "shop" else rng.randi_range(0, 2)
		var blocked: Array = []
		if info.has("gate_span"):
			blocked.append([info.gate_span[0] - 0.35, info.gate_span[1] + 0.35])
		if info.body.has_meta("door"):
			blocked.append([info.body.get_meta("door") - 0.45, info.body.get_meta("door") + 0.45])
		if info.kind == "shop" and state == "open":
			blocked.append([u0, u0 + 0.85])
		for top in tops:
			var along: float = top.x if f.along_x else top.z
			blocked.append([along - 0.2, along + 0.2])
		var spots: Array = []
		var u: float = u0 + 1.3
		while u <= u1 - 1.3:
			var g: Vector2 = _grounds(f, u - 0.8, u + 0.8)
			var clear: bool = is_equal_approx(g.x, g.y)
			for b in blocked:
				clear = clear and (u + 0.8 < b[0] or u - 0.8 > b[1])
			if clear:
				spots.append(u)
			u += 0.5
		var placed: Array = []
		for heap in heaps:
			if spots.is_empty():
				break
			var at: float = spots[rng.randi() % spots.size()]
			spots = spots.filter(func(other): return absf(other - at) >= 2.2)
			placed.append(Props.clutter(info.body, _at(f, at, -0.25, _grounds(f, at - 0.8, at + 0.8).y), Decoration.YAW[f.out], kinds[rng.randi() % kinds.size()], rng))
		if not placed.is_empty():
			# Heaps join their lot's see-through state.
			for entry in fadeable:
				if entry.body == info.body:
					entry.meshes = info.body.find_children("*", "GeometryInstance3D", true, false)
					_set_alpha(entry, entry.rest)

func _pole(f: Dictionary, u: float, ground: float) -> Vector3:
	var foot: Vector3 = _at(f, u, POLE_V, ground)
	poles.append(foot)
	_skin(Shape.cylinder(self, foot + Vector3(0, 3.5, 0), 0.13, 7.0, Color("8d8a82"), 0.1), "concrete")
	_piece(self, f, u - 0.04, u + 0.04, -1.3, POLE_V, ground + 5.0, ground + 5.08, Color("4f504e"))
	_piece(self, f, u - 0.18, u + 0.18, -1.45, -1.1, ground + 4.86, ground + 5.0, Color("3d3f40"))
	var bulb: Color = Color(data.get("lighting", {}).get("lamp_color", "ffd59a"))
	_glow(_piece(self, f, u - 0.14, u + 0.14, -1.41, -1.14, ground + 4.82, ground + 4.86, bulb), bulb, 2.0)
	_lamp(self, _at(f, u, -1.28, ground + 4.5), bulb, float(data.get("lighting", {}).get("lamp_energy", 1.6)), 9.0)
	decorations.pole(self, f, u, ground, POLE_V - 0.14)
	return foot + Vector3(0, 6.6, 0)

func _lamp(parent: Node3D, pos: Vector3, color: Color, energy: float, reach: float) -> void:
	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	parent.add_child(light)
	light.position = pos

func _wire(a: Vector3, b: Vector3, slack: float = 0.45, strands: int = 3) -> void:
	# With the alley decorations, wires hang in a sag with strands side by side; without, one straight run.
	var segments := 12 if not decorations.layout.is_empty() else 1
	var span: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z)
	var side: Vector3 = span.cross(Vector3.UP).normalized() * 0.055 if span.length() > 0.01 else Vector3(0.055, 0, 0)
	for strand in (strands if segments > 1 else 1):
		var previous: Vector3 = a + side * strand
		for i in range(1,segments+1):
			var t: float = float(i)/segments
			var sag: float = (slack+strand*0.16)*4*t*(1-t) if segments > 1 else 0.0
			var next: Vector3 = a.lerp(b,t)+side*strand+Vector3(0,-sag,0)
			var gauge: float = 0.016 if segments > 1 else 0.025
			var wire: MeshInstance3D = Shape.box(self,(previous+next)/2,Vector3(gauge,gauge,previous.distance_to(next)),Color("1e1f22"))
			wire.look_at_from_position((previous+next)/2,next,Vector3.UP)
			previous=next

func _lot(f: Dictionary, lot: Dictionary, u0: float, u1: float, walled_next: bool, rng: RandomNumberGenerator, key: String) -> void:
	# One lot: collision is a single block along the frontage; the look is assembled from kit pieces.
	var kind: String = lot.kind
	var ground: float = _grounds(f, u0, u1).y
	var strip: Array = _area(f, u0, u1, 0.0, 0.6)
	var body = StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	region.add_child(body)
	body.set_meta("alley_state",decorations.state(key,lot.get("faded",false)))
	body.set_meta("lot_key",key)
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	var top: float = ground + (CUT_H if kind == "shop" else FENCE_H)
	box.size = Vector3(strip[2] - strip[0], top, strip[3] - strip[1])
	collision.shape = box
	collision.position = Vector3((strip[0] + strip[2]) / 2.0, top / 2.0, (strip[1] + strip[3]) / 2.0)
	body.add_child(collision)
	for c in _chunks(f, u0, u1):
		# Kerb and retaining face under the frontage, down to the low ground beyond raised alleys.
		_skin(_piece(body, f, c[0], c[1], 0.0, 0.6, -0.7, c[2], Color("77736b")), "concrete")
	var info = {"kind": kind, "body": body, "cut": true, "gate": false, "piers": 0, "building": false, "sign": "", "ground": ground, "out": f.out}
	# Camera-side lots, and lots whose building would cover floor seen past it, keep only the frontage.
	var full: bool = f.sign < 0
	if kind == "shop":
		var storeys: int = int(lot.get("floors", rng.randi_range(1, 3)))
		var depth: float = rng.randf_range(5.5, 7.5)
		var foot: Array = _area(f, u0 + 0.05, u1 - 0.05, 0.0, depth)
		full = full and not _hides_floor(foot, storeys * STOREY + 0.6) and _claim(foot)
		if full:
			_ground_slab(body, f, u0, u1, depth + 0.6, ground)
			var shop_house: Node3D = _building(body, {"rect": foot, "floors": storeys, "color": WALLS[rng.randi() % WALLS.size()], "roof": ROOFS[rng.randi() % ROOFS.size()], "base": ground, "face": "z" if f.along_x else "x", "front": "store"}, key)
			info.building = true
			info.drop = shop_house.get_meta("drop")
		info.sign = _storefront(body, f, u0, u1, ground, lot, rng, not full)
		# Projecting signs and A-frames advertise this same trade, flush with the shopfront.
		body.set_meta("business", info.sign)
		body.set_meta("facade", 0.0)
		body.set_meta("full_building",full)
		decorations.shop(body, f, u0, u1, ground, lot, key)
	else:
		var palette: Array = BRICK if rng.randf() < 0.5 else CEMENT
		var color = Color(lot.get("color", palette[rng.randi() % palette.size()]))
		var coping: Color = Color("b9a48a") if palette == BRICK else color.lightened(0.18)
		var surface: String = "brick" if palette == BRICK else "block"
		var end: float = u1 + (0.1 if walled_next else -0.1)
		var runs: Array = [[u0 + 0.1, end]]
		info.piers += _pier(body, f, u0, ground, color, coping, surface)
		if not walled_next:
			info.piers += _pier(body, f, u1 - 0.32, ground, color, coping, surface)
		if kind == "house":
			var gw: float = 1.2 if rng.randf() < 0.6 else 2.4
			var at: float = rng.randf_range(u0 + 1.0, u1 - 1.0 - gw)
			runs = [[u0 + 0.1, at - 0.22], [at + gw + 0.22, end]]
			info.piers += _gate(body, f, at, gw, _grounds(f, at, at + gw).y, color, coping, surface, rng, full)
			info.gate = true
			info.gate_span = [at, at + gw]
			var setback: float = rng.randf_range(1.4, 2.4)
			body.set_meta("facade", setback)
			var depth: float = rng.randf_range(5.0, 7.0)
			var storeys: int = 2 if rng.randf() < 0.6 else 1
			var foot: Array = _area(f, u0 + 0.6, u1 - 0.6, setback, setback + depth)
			full = full and not _hides_floor(foot, storeys * STOREY + 0.6) and _claim(foot)
			if full:
				_ground_slab(body, f, u0, u1, setback + depth + 0.6, ground)
				var house: Node3D = _building(body, {"rect": foot, "floors": storeys, "color": WALLS[rng.randi() % WALLS.size()], "roof": ROOFS[rng.randi() % ROOFS.size()], "base": ground, "face": "z" if f.along_x else "x", "front": "door"}, key)
				info.building = true
				info.drop = house.get_meta("drop")
		else:
			full = full and rng.randf() < 0.5 and not _hides_floor(_area(f, u0, u1, 0.6, 2.6), 3.8)
			if full:
				# A yard tree showing over a plain wall.
				var at: Vector3 = _at(f, rng.randf_range(u0 + 1.0, u1 - 1.0), 1.5, ground)
				_ground_slab(body, f, u0, u1, 2.6, ground)
				Shape.cylinder(body, at + Vector3(0, 1.1, 0), 0.14, 2.2, Color("5a4434"))
				Shape.sphere(body, at + Vector3(0, 2.7, 0), 1.1, Color("4a6b3c"))
		for run in runs:
			if run[1] - run[0] > 0.05:
				_fence_run(body, f, run[0], run[1], color, coping, surface)
		# Choose one real fence span, so notices never float across a doorway.
		var decorated_run: Array = []
		for run in runs:
			if decorated_run.is_empty() or run[1]-run[0] > decorated_run[1]-decorated_run[0]: decorated_run=run
		if not decorated_run.is_empty():
			var mid: float = (decorated_run[0]+decorated_run[1])/2.0
			decorations.decorate_run(body, f, decorated_run[0], decorated_run[1], _grounds(f, mid-0.1, mid+0.1).y, kind, key)
	decorations.lot(body,f,u0,u1,ground,key,full and info.building)
	info.cut = not full
	lots.append(info)
	_fadeable(body, strip)

func _ground_slab(body: Node3D, f: Dictionary, u0: float, u1: float, depth: float, ground: float) -> void:
	# Yard or plot ground behind the frontage; visual only, so the navmesh and clicks never use it.
	_skin(_piece(body, f, u0, u1, 0.6, depth, -0.7, ground - 0.01, Color("5f5e56")), "concrete")

func _fence_run(body: Node3D, f: Dictionary, u0: float, u1: float, color: Color, coping: Color, surface: String) -> void:
	# Garden wall: a thin continuous panel with a dark plinth and a pale coping, no piers in between.
	for c in _chunks(f, u0, u1):
		_skin(_piece(body, f, c[0], c[1], 0.0, 0.22, c[2], c[2] + FENCE_H, color), surface)
		_skin(_piece(body, f, c[0], c[1], -0.012, 0.232, c[2], c[2] + 0.24, color.darkened(0.2)), "concrete")
		_skin(_piece(body, f, c[0] - 0.02, c[1] + 0.02, -0.04, 0.26, c[2] + FENCE_H, c[2] + FENCE_H + 0.06, coping), "concrete")

func _pier(body: Node3D, f: Dictionary, u: float, ground: float, color: Color, coping: Color, surface: String) -> int:
	_skin(_piece(body, f, u, u + 0.32, -0.05, 0.27, ground, ground + FENCE_H + 0.14, color.darkened(0.14)), surface)
	_skin(_piece(body, f, u - 0.03, u + 0.35, -0.08, 0.3, ground + FENCE_H + 0.14, ground + FENCE_H + 0.2, coping), "concrete")
	return 1

func _gate(body: Node3D, f: Dictionary, at: float, gw: float, ground: float, color: Color, coping: Color, surface: String, rng: RandomNumberGenerator, canopy: bool) -> int:
	# A closed steel gate between two posts: framed leaves, a mid rail and a handle, sometimes a small
	# tiled canopy over it. Double gates (2.4m) show a centre seam. Returns the posts it added.
	var paint = Color(GATES[rng.randi() % GATES.size()])
	_pier(body, f, at - 0.32, ground, color, coping, surface)
	_pier(body, f, at + gw, ground, color, coping, surface)
	var height: float = FENCE_H + 0.12
	_skin(_piece(body, f, at + 0.01, at + gw - 0.01, 0.06, 0.15, ground + 0.04, ground + height, paint), "metal")
	_skin(_piece(body, f, at + 0.01, at + gw - 0.01, 0.04, 0.17, ground + height - 0.08, ground + height, paint.lightened(0.22)), "metal")
	_skin(_piece(body, f, at + 0.01, at + gw - 0.01, 0.045, 0.165, ground + 0.86, ground + 0.92, paint.lightened(0.12)), "metal")
	var handle: float = at + gw / 2.0 - 0.12 if gw > 2.0 else at + gw - 0.18
	if gw > 2.0:
		_piece(body, f, at + gw / 2.0 - 0.015, at + gw / 2.0 + 0.015, 0.03, 0.17, ground + 0.04, ground + height, paint.darkened(0.35))
	_piece(body, f, handle, handle + 0.06, 0.0, 0.06, ground + 1.0, ground + 1.12, Color("c9b56a"))
	if canopy and rng.randf() < 0.5:
		_piece(body, f, at - 0.5, at + gw + 0.5, -0.45, 0.4, ground + height + 0.5, ground + height + 0.62, Color("4b5257"))
		_piece(body, f, at - 0.5, at + gw + 0.5, -0.47, -0.43, ground + height + 0.42, ground + height + 0.62, Color("3b4045"))
		for side in [at - 0.3, at + gw + 0.24]:
			_piece(body, f, side, side + 0.06, 0.1, 0.16, ground + height, ground + height + 0.5, Color("3b4045"))
	return 2

func _storefront(body: Node3D, f: Dictionary, u0: float, u1: float, ground: float, lot: Dictionary, rng: RandomNumberGenerator, cut: bool) -> String:
	# Ground-floor shopfront right on the alley: a rolled-down shutter or a glass front with a door,
	# then a sign board (and sometimes an awning). Cut lots keep a wall stub up to CUT_H instead.
	var shutter: bool = lot.get("front", "shutter" if rng.randf() < 0.45 else "glass") == "shutter"
	if cut:
		_skin(_piece(body, f, u0 + 0.05, u1 - 0.05, 0.0, 0.5, ground, ground + CUT_H - 0.08, Color(WALLS[rng.randi() % WALLS.size()])), "plaster")
		_piece(body, f, u0 + 0.05, u1 - 0.05, 0.0, 0.5, ground + CUT_H - 0.08, ground + CUT_H, Color("4a4844"))
	if shutter:
		_skin(_piece(body, f, u0 + 0.35, u1 - 0.35, -0.05, 0.0, ground, ground + 2.25, Color("9aa3a6")), "metal")
		for k in 8:
			var y: float = ground + 0.2 + 0.26 * k
			_piece(body, f, u0 + 0.35, u1 - 0.35, -0.065, -0.05, y, y + 0.03, Color("7f878a"))
		_skin(_piece(body, f, u0 + 0.3, u1 - 0.3, -0.16, 0.0, ground + 2.25, ground + 2.4, Color("8b9295")), "metal")
	else:
		var lit: bool = rng.randf() < float(data.get("lighting", {}).get("lit_shops", 0.3))
		if body.get_meta("alley_state","original") in ["closed","vacant"]: lit=false
		var door: float = rng.randf_range(u0 + 0.9, u1 - 0.9)
		body.set_meta("door", door)
		_piece(body, f, u0 + 0.3, u1 - 0.3, -0.04, 0.0, ground, ground + 2.4, Color("d8d2c4"))
		var pane: MeshInstance3D = _piece(body, f, u0 + 0.4, u1 - 0.4, -0.07, -0.04, ground + 0.35, ground + 2.3, Color("2a3a44"))
		if lit:
			_glow(pane, Color("f2dca0"), 1.1)
		var m: float = u0 + 1.4
		while m < u1 - 0.8:
			_piece(body, f, m - 0.03, m + 0.03, -0.08, -0.04, ground + 0.35, ground + 2.3, Color("d8d2c4"))
			m += 1.3
		_piece(body, f, door - 0.45, door + 0.45, -0.09, -0.05, ground + 0.02, ground + 2.25, Color("3a4a52"))
		_piece(body, f, door + 0.3, door + 0.34, -0.12, -0.09, ground + 0.9, ground + 1.2, Color("c9c2b0"))
	if cut:
		return lot.get("sign", "")
	if lot.has("tube"):
		var tube = Color(lot.tube)
		var fixture := _piece(body,f,u0+0.8,u1-0.8,-0.32,-0.24,ground+2.48,ground+2.54,tube.darkened(0.35))
		if body.get_meta("alley_state","original") in ["original","open"]:
			_glow(fixture,tube,1.6)
			_lamp(body,_at(f,(u0+u1)/2.0,-0.6,ground+2.3),tube,0.9,5.0)
	var text: String = lot.get("sign", SIGNS[rng.randi() % SIGNS.size()])
	var board = Color(lot.get("board", BOARDS[rng.randi() % BOARDS.size()]))
	var ink = Color("2a2a2a") if board.get_luminance() > 0.55 else Color("f4efe4")
	if lot.get("faded", false):
		board = board.lerp(Color("8f8b84"), 0.55)
		ink = ink.lerp(Color("8f8b84"), 0.45)
	_piece(body, f, u0 + 0.2, u1 - 0.2, -0.16, 0.0, ground + 2.58, ground + 3.18, board)
	if not shutter and rng.randf() < 0.5:
		var cloth = Color(["b8433a", "2f5d8a", "3f7a52"][rng.randi() % 3])
		_piece(body, f, u0 + 0.3, u1 - 0.3, -0.9, 0.0, ground + 2.44, ground + 2.5, cloth)
		_piece(body, f, u0 + 0.3, u1 - 0.3, -0.92, -0.88, ground + 2.26, ground + 2.5, cloth.lightened(0.3))
	if decorations.sign(body, f, text, lot.get("faded",false), (u0+u1)/2.0, ground+2.88, u1-u0-0.4):
		return text
	if sign_font == null:
		sign_font = SystemFont.new()
		sign_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
		sign_font.font_weight = 700
	var label = Label3D.new()
	label.text = text
	label.font = sign_font
	label.font_size = 72
	label.pixel_size = 0.005
	label.modulate = ink
	label.outline_size = 0
	label.shaded = false
	body.add_child(label)
	label.position = _at(f, (u0 + u1) / 2.0, -0.175, ground + 2.88)
	label.rotation_degrees.y = {"-z": 0.0, "-x": 90.0, "+z": 180.0, "+x": -90.0}[f.out]
	return text

func _faces_camera(rect: Array) -> bool:
	# A wall whose camera side is open air but whose far side is floor hides that floor.
	var center = Vector3((rect[0] + rect[2]) / 2.0, 0, (rect[1] + rect[3]) / 2.0)
	var reach: float = minf(rect[2] - rect[0], rect[3] - rect[1]) / 2.0 + 0.6
	return _on_floor(center - CAMERA_SIDE * reach) and not _on_floor(center + CAMERA_SIDE * reach)

func _on_floor(at: Vector3) -> bool:
	for r in floor_rects:
		if at.x >= r[0] and at.x <= r[2] and at.z >= r[1] and at.z <= r[3]:
			return true
	return false

func _building(parent: Node3D, entry: Dictionary, key: String) -> Node3D:
	# House assembled from kit pieces: storey blocks, floor bands, framed windows, a ground-floor
	# door or shop shutter, a roof parapet and rooftop clutter. No collision.
	# A per-building seed varies the pieces so neighbours do not repeat. "face" names the alley face
	# (z or x) that gets the entrance; "front": "store" leaves its ground floor to the shopfront kit.
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("%s:%s" % [id, key])
	var r: Array = entry.rect
	var base: float = entry.get("base", 0.0)
	var storeys: int = int(entry.floors)
	var storey: float = STOREY
	var wall: Color = Color(entry.color)
	var size = Vector3(r[2] - r[0], storey, r[3] - r[1])
	var cx: float = (r[0] + r[2]) / 2.0
	var cz: float = (r[1] + r[3]) / 2.0
	var alley: String = entry.get("face", "")
	var front: String = entry.get("front", "any")
	var house = Node3D.new()
	parent.add_child(house)
	house.set_meta("lot_key",key)
	house.set_meta("alley_state",parent.get_meta("alley_state",decorations.state(key)))
	# Upper-floor windows that can carry an outdoor AC unit underneath.
	var slots: Array = []
	for level in storeys:
		var y0: float = base + level * storey
		_skin(Shape.box(house, Vector3(cx, y0 + storey / 2.0, cz), size, wall.darkened(0.04 * (level % 2))), "plaster")
		_skin(Shape.box(house, Vector3(cx, y0 + storey - 0.05, cz), size + Vector3(0.12, 0.1, 0.12), wall.darkened(0.2)), "concrete")
		# Windows on the two faces the camera sees (+z and +x).
		for face in ["z", "x"]:
			var span: float = size.x if face == "z" else size.z
			var count: int = maxi(1, int(span / 2.3))
			for i in count:
				var t: float = -span / 2.0 + span * (i + 0.5) / count
				if level == 0 and (alley == "" or alley == face):
					if front == "store":
						continue
					if i == count / 2:
						_door(house, face, cx, cz, size, y0, t, rng, front == "any")
						continue
				_window(house, face, cx, cz, size, y0 + 1.6, t, rng)
				if level > 0:
					slots.append([face, t, y0])
	var roof_y: float = base + storeys * storey
	for side in [[0, size.z / 2.0, size.x + 0.2, 0.2], [0, -size.z / 2.0, size.x + 0.2, 0.2], [size.x / 2.0, 0, 0.2, size.z], [-size.x / 2.0, 0, 0.2, size.z]]:
		_skin(Shape.box(house, Vector3(cx + side[0], roof_y + 0.3, cz + side[1]), Vector3(side[2], 0.6, side[3]), wall.darkened(0.25)), "plaster")
	_skin(Shape.box(house, Vector3(cx, roof_y + 0.02, cz), Vector3(size.x - 0.2, 0.04, size.z - 0.2), Color(entry.get("roof", "4f7a5a"))), "concrete")
	if rng.randf() < 0.7:
		Shape.cylinder(house, Vector3(cx + rng.randf_range(-size.x, size.x) * 0.25, roof_y + 0.7, cz - size.z * 0.2), 0.55, 1.2, Color("c9c2b0"))
	# Outdoor AC units hang on brackets under upper-floor windows, never over entrances or signs;
	# single-storey buildings keep theirs on the roof.
	for i in rng.randi_range(1, 2):
		if slots.is_empty():
			_ac(house, Vector3(cx + rng.randf_range(-0.25, 0.25) * size.x, roof_y + 0.04, cz - size.z * 0.15), 0.0, true)
			break
		var slot: Array = slots.pop_at(rng.randi() % slots.size())
		var wall_at = Vector3(cx + slot[1], slot[2] + 0.55, cz + size.z / 2.0) if slot[0] == "z" else Vector3(cx + size.x / 2.0, slot[2] + 0.55, cz + slot[1])
		_ac(house, wall_at, 0.0 if slot[0] == "z" else 90.0, false)
	# Gas riser and meters on the alley face; "drop" is where the overhead service cable lands.
	# Shops keep their alley face for the shopfront kit, so their fittings go on the other seen face.
	var fitted: String = alley if alley != "" else "z"
	if front == "store":
		fitted = "x" if fitted == "z" else "z"
	house.set_meta("drop", decorations.fixtures(house, r, base, storeys, storey, fitted))
	return house

func _ac(house: Node3D, at: Vector3, yaw: float, roof: bool) -> void:
	# An outdoor AC unit: casing, fan grille and refrigerant pipe. On a wall it sits on two brackets
	# with its back at "at"; on a roof it stands on a low frame with its base at "at".
	var unit = Node3D.new()
	house.add_child(unit)
	unit.position = at
	unit.rotation_degrees.y = yaw
	unit.set_meta("ac_bottom", at.y + (0.1 if roof else -0.26))
	var y: float = 0.36 if roof else 0.0
	Shape.box(unit, Vector3(0, y, 0.16), Vector3(0.78, 0.52, 0.3), Color("d9d6cc"))
	var fan: MeshInstance3D = Shape.cylinder(unit, Vector3(0.1, y, 0.315), 0.17, 0.02, Color("54575a"))
	fan.rotation_degrees.x = 90
	Shape.box(unit, Vector3(-0.42, y + 0.05, 0.08), Vector3(0.04, 0.04, 0.16), Color("e8e4da"))
	for x in [-0.3, 0.3]:
		if roof:
			Shape.box(unit, Vector3(x, 0.05, 0.16), Vector3(0.05, 0.1, 0.34), Color("4a4c4e"))
		else:
			Shape.box(unit, Vector3(x, -0.28, 0.18), Vector3(0.04, 0.04, 0.36), Color("4a4c4e"))
			Shape.box(unit, Vector3(x, -0.4, 0.02), Vector3(0.04, 0.24, 0.04), Color("4a4c4e"))

func _window(house: Node3D, face: String, cx: float, cz: float, size: Vector3, y: float, t: float, rng: RandomNumberGenerator) -> void:
	# Some windows are lit from inside; at dusk they glow.
	var lit: bool = rng.randf() < float(data.get("lighting", {}).get("lit_windows", 0.18))
	if house.get_meta("alley_state","original") in ["closed","vacant"]: lit=false
	if face == "z":
		Shape.box(house, Vector3(cx + t, y, cz + size.z / 2.0 + 0.03), Vector3(1.15, 1.2, 0.05), Color("d8d2c4"))
		_glass(house, Vector3(cx + t, y, cz + size.z / 2.0 + 0.06), Vector3(0.95, 1.0, 0.04), lit)
	else:
		Shape.box(house, Vector3(cx + size.x / 2.0 + 0.03, y, cz + t), Vector3(0.05, 1.2, 1.15), Color("d8d2c4"))
		_glass(house, Vector3(cx + size.x / 2.0 + 0.06, y, cz + t), Vector3(0.04, 1.0, 0.95), lit)
	decorations.window(house,face,cx,cz,size,y,t)

func _glass(parent: Node3D, pos: Vector3, size: Vector3, lit: bool) -> MeshInstance3D:
	var geometry = BoxMesh.new()
	geometry.size = size
	var pane: MeshInstance3D = Shape.mesh(parent, geometry, pos, Color("f0c878") if lit else Color("23303a"))
	if lit:
		_glow(pane, Color("f0c878"), 1.4)
	return pane

func _glow(piece: MeshInstance3D, color: Color, energy: float) -> void:
	# Light sources (lit windows, lamps) are emissive so they read in the dusk light and bloom.
	var material: StandardMaterial3D = Shape.material(color, true)
	material.emission_energy_multiplier = energy
	piece.material_override = material

func _door(house: Node3D, face: String, cx: float, cz: float, size: Vector3, y0: float, t: float, rng: RandomNumberGenerator, shutters: bool) -> void:
	# Either a front door or a rolled-down shop shutter, the usual ground floor of a 2000s alley.
	var shutter: bool = shutters and rng.randf() < 0.5
	var piece = Vector3(1.8, 2.2, 0.06) if shutter else Vector3(0.95, 2.2, 0.06)
	var color = Color("9aa3a6") if shutter else Color("5b3e2e")
	var leaf: MeshInstance3D
	if face == "z":
		leaf = Shape.box(house, Vector3(cx + t, y0 + 1.1, cz + size.z / 2.0 + 0.04), piece, color)
	else:
		leaf = Shape.box(house, Vector3(cx + size.x / 2.0 + 0.04, y0 + 1.1, cz + t), Vector3(piece.z, piece.y, piece.x), color)
	_skin(leaf, "metal")

func _build_flat() -> void:
	bounds = Rect2(-14.25, -12.25, 28.5, 24.5)
	Shape.box(self, Vector3(0, -0.35, 0), Vector3(30, 0.7, 26), Color("334a50"))
	for x in range(-14, 15, 2):
		Shape.box(self, Vector3(x, 0.005, 0), Vector3(0.025, 0.01, 25.6), Color("40595e"))
	for z in range(-12, 13, 2):
		Shape.box(self, Vector3(0, 0.005, z), Vector3(29.6, 0.01, 0.025), Color("40595e"))
	Shape.ring(self, Vector3(0, 0.02, 0), 5.0, Color("59716d"), 0.025)
	Shape.ring(self, Vector3(0, 0.02, 0), 5.2, Color("8a795a"), 0.025)
	for wall in [[-15.25, -13, -14.75, 13], [14.75, -13, 15.25, 13], [-15, -13.25, 15, -12.75], [-15, 12.75, 15, 13.25]]:
		_solid(self, wall, 0.0, 1.2, Color("233740"), WORLD_LAYER)
	for x in [-14, 14]:
		for z in [-12, -6, 0, 6, 12]:
			Shape.cylinder(self, Vector3(x, 0.65, z), 0.3, 1.3, Color("c69b62"))
			Shape.sphere(self, Vector3(x, 1.35, z), 0.15, Color("8dd8c4"))

func ground_y(pos: Vector3) -> float:
	# Height of the floor or step under a point; the flat arena is always at zero.
	if region == null:
		return 0.0
	var query = PhysicsRayQueryParameters3D.create(Vector3(pos.x, 30, pos.z), Vector3(pos.x, -5, pos.z), FLOOR_LAYER)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return pos.y if hit.is_empty() else hit.position.y

func grounded(pos: Vector3) -> Vector3:
	return Vector3(pos.x, ground_y(pos), pos.z)

func start_point() -> Vector3:
	return Vector3(0, 0, 2) if data.is_empty() else grounded(Vector3(data.start[0], 0, data.start[1]))

func pick_floor(origin: Vector3, direction: Vector3):
	# Cursor ray onto floors and steps; null where it meets no floor (the flat arena uses a plane).
	if region == null:
		return null
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 200, FLOOR_LAYER)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return null if hit.is_empty() else hit.position

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	# Waypoints from one point to another; a straight line where there is no navmesh.
	if region == null or not nav_ready():
		return PackedVector3Array([to])
	var points = NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
	return points if not points.is_empty() else PackedVector3Array([to])

func _nav_floor(near: Vector3) -> bool:
	# Navmesh islands on top of props sit well above the floor beneath them.
	return near.y - ground_y(near) < PROP_TOP

func snap(pos: Vector3) -> Vector3:
	# Nearest walkable point: clicks on walls or the void move to their edge.
	if region == null or not nav_ready():
		return pos
	var near: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, pos)
	return grounded(near) if _nav_floor(near) else pos

func walkable(pos: Vector3) -> bool:
	if not bounds.has_point(Vector2(pos.x, pos.z)):
		return false
	if region == null or not nav_ready():
		return true
	var near: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, pos)
	return _nav_floor(near) and Vector2(near.x - pos.x, near.z - pos.z).length() < 0.35

func clear(a: Vector3, b: Vector3) -> bool:
	# Raw segment test against walls and props (orbs in flight use their own height).
	var query = PhysicsRayQueryParameters3D.create(a, b, WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func sees(a: Vector3, b: Vector3) -> bool:
	# Chest-height sight line above each end's ground; tall walls and props block it, low ones do not.
	return clear(Vector3(a.x, a.y + SIGHT_HEIGHT, a.z), Vector3(b.x, b.y + SIGHT_HEIGHT, b.z))

func zone_at(pos: Vector3) -> Dictionary:
	for zone in data.get("zones", []):
		var r: Array = zone.rect
		if pos.x >= r[0] and pos.x <= r[2] and pos.z >= r[1] and pos.z <= r[3]:
			return zone
	return {}

func respawn_point(witch: Vector3, rng: RandomNumberGenerator) -> Vector3:
	# A5 re-entry away from the witch: field edges on the flat arena, listed spots on a map.
	if data.is_empty():
		var pos = Vector3.ZERO
		for attempt in 12:
			var along = rng.randf_range(-1, 1)
			pos = [Vector3(13, 0, along * 11), Vector3(-13, 0, along * 11), Vector3(along * 13, 0, 11), Vector3(along * 13, 0, -11)][rng.randi() % 4]
			if pos.distance_to(witch) >= 8:
				break
		return pos
	var far: Array = []
	for spot in data.respawns:
		var at = grounded(Vector3(spot[0], 0, spot[1]))
		if Vector2(at.x - witch.x, at.z - witch.z).length() >= 10:
			far.append(at)
	if far.is_empty():
		far = data.respawns.map(func(spot): return grounded(Vector3(spot[0], 0, spot[1])))
	return far[rng.randi() % far.size()]

func _set_alpha(entry: Dictionary, alpha: float) -> void:
	for mesh in entry.meshes:
		if mesh is Label3D:
			mesh.modulate.a = alpha
			continue
		var material: StandardMaterial3D = mesh.material_override
		var has_decal: bool = mesh.has_meta("decal_base_alpha")
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 or has_decal else BaseMaterial3D.TRANSPARENCY_DISABLED
		material.albedo_color = Color(material.albedo_color, alpha * float(mesh.get_meta("decal_base_alpha",1.0)))

func fade_between(eye: Vector3, target: Vector3) -> void:
	# Tall walls between the camera and the witch turn see-through; the rest go back to their resting look.
	var hits: Array = []
	var exclude: Array[RID] = []
	var space = get_world_3d().direct_space_state
	for attempt in 4:
		var query = PhysicsRayQueryParameters3D.create(eye, target, WORLD_LAYER, exclude)
		var hit = space.intersect_ray(query)
		if hit.is_empty():
			break
		exclude.append(hit.rid)
		if hit.collider.has_meta("fade"):
			hits.append(hit.collider)
	for entry in fadeable:
		var want: bool = hits.has(entry.body)
		if want and not faded.has(entry.body):
			_set_alpha(entry, FADE_ALPHA)
			faded.append(entry.body)
		elif not want and faded.has(entry.body):
			_set_alpha(entry, entry.rest)
			faded.erase(entry.body)
