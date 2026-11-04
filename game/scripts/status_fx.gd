extends Node3D
## Presentation only: markers for an enemy's debuffs. Each has its own place on the body, so
## several read at once without covering one another:
##   slow  - rippling rings on the ground at its feet
##   bound - cables wrapped tight round its waist
##   shred - a cracked shield on its chest, shedding flakes
##   bleed - drops of blood spurting out of its sides (more stacks, more often)
##   stun  - stars circling over its head
## The arena calls sync(enemy, dt) from its enemy update, so pause freezes it. Its own RNG keeps
## the combat RNG untouched. Effects fade in and out instead of popping.
const SHADER := preload("res://shaders/status_fx.gdshader")
const SLOW := Color(0.55, 0.86, 1.0)
const CABLE := Color(0.34, 0.28, 0.2)
const CLASP := Color(1.0, 0.82, 0.42)
const SHRED := Color(1.0, 0.56, 0.2)
const BLOOD := Color(0.6, 0.02, 0.04)
const STAR := Color(1.0, 0.86, 0.36)
const KINDS := ["slow", "bound", "shred", "bleed", "stun"]

static var _material: ShaderMaterial
static var _overlay: ShaderMaterial

var time := 0.0
## How visible each marker is now (0..1); kinds the enemy has rise, the others fade.
var presence := {"slow": 0.0, "bound": 0.0, "shred": 0.0, "bleed": 0.0, "stun": 0.0}
var drops: Array = []
var flakes: Array = []
var rng := RandomNumberGenerator.new()
## Body frame measured from the model once: feet are at 0, the rest in metres above them.
var bottom := 0.0
var top := 1.5
var radius := 0.35
var scale_factor := 1.0
var stun_height := 1.7
var _spurt := 0.0
var _flake := 0.0
var _side := 1.0
var _mesh := ArrayMesh.new()
## The chest shield draws over the body itself (no depth test), so a wide body never hides it.
var _overlay_mesh := ArrayMesh.new()
var _body: Node3D

func setup(enemy: Dictionary) -> void:
	name = "StatusFx"
	top_level = true
	_body = enemy.body
	rng.seed = hash(str(enemy.body.get_instance_id()))
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = 2
		var shader := Shader.new()
		shader.code = SHADER.code.replace("fog_disabled;", "fog_disabled, depth_test_disabled;")
		_overlay = ShaderMaterial.new()
		_overlay.shader = shader
		_overlay.render_priority = 3
	for layer in [["Markers", _mesh, _material], ["Overlay", _overlay_mesh, _overlay]]:
		var node := MeshInstance3D.new()
		node.name = layer[0]
		node.mesh = layer[1]
		node.material_override = layer[2]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	measure(enemy)

func measure(enemy: Dictionary) -> void:
	# The visible model's box relative to the feet; models without meshes keep a sized default.
	var size: float = float(enemy.size)
	scale_factor = clampf(size, 0.75, 1.7)
	top = 1.55 * size
	radius = 0.32 * size
	var box := AABB()
	var found := false
	var origin: Vector3 = enemy.body.global_position
	for node in enemy.model.find_children("*", "VisualInstance3D", true, false):
		if not (node is GeometryInstance3D) or not node.is_visible_in_tree():
			continue
		var part: AABB = node.global_transform * node.get_aabb()
		part.position -= origin
		box = part if not found else box.merge(part)
		found = true
	if found and box.size.y > 0.2:
		bottom = maxf(0.0, box.position.y)
		top = box.end.y
		radius = clampf(minf(box.size.x, box.size.z) * 0.5, 0.14, 0.9)
	# Stars go just above the head but stay under the HP bar the HUD draws at 0.35 + 1.55 * size.
	stun_height = minf(top + 0.16, 0.2 + 1.55 * size)

func active(enemy: Dictionary) -> Dictionary:
	return {"slow": float(enemy.get("slow", 0.0)) > 0, "bound": float(enemy.get("bound", 0.0)) > 0,
		"shred": float(enemy.get("shred", 0.0)) > 0, "bleed": not enemy.get("bleeds", []).is_empty(),
		"stun": float(enemy.get("stun", 0.0)) > 0}

func showing() -> Array:
	# Kinds currently drawn (fully or fading), for tests and probes.
	return KINDS.filter(func(kind): return presence[kind] > 0.001)

func sync(enemy: Dictionary, dt: float) -> void:
	time += dt
	global_position = enemy.body.global_position
	var on := active(enemy)
	for kind in KINDS:
		presence[kind] = move_toward(presence[kind], 1.0 if on[kind] else 0.0, dt * (7.0 if on[kind] else 4.0))
	var stacks: int = enemy.get("bleeds", []).size()
	if on.bleed:
		_spurt -= dt
		if _spurt <= 0.0:
			_spurt = maxf(0.14, 0.62 / float(stacks)) * rng.randf_range(0.8, 1.2)
			_bleed_spurt(stacks)
	if on.shred:
		_flake -= dt
		if _flake <= 0.0:
			_flake = rng.randf_range(0.28, 0.45)
			flakes.append({"p": Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3), 0) * 0.16 * scale_factor,
				"v": Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.0, 0.2), 0), "age": 0.0, "life": 0.55})
	for drop in drops:
		drop.age += dt
		drop.v.y -= 7.5 * dt
		drop.p += drop.v * dt
		if drop.p.y < 0.03 and drop.landed < 0:
			drop.p.y = 0.03
			drop.v = Vector3.ZERO
			drop.landed = drop.age
	drops = drops.filter(func(drop): return drop.landed < 0 or drop.age - drop.landed < 0.25)
	for flake in flakes:
		flake.age += dt
		flake.v.y -= 1.2 * dt
		flake.p += flake.v * dt
	flakes = flakes.filter(func(flake): return flake.age < flake.life)
	redraw()

func _bleed_spurt(stacks: int) -> void:
	# Out of one side, then the other: drops fly sideways (in screen terms) and fall.
	var view := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var toward := Vector3.BACK
	if view != null:
		right = Vector3(view.global_basis.x.x, 0, view.global_basis.x.z).normalized()
		toward = Vector3(view.global_basis.z.x, 0, view.global_basis.z.z).normalized()
	_side = -_side
	var height: float = lerpf(bottom, top, 0.5)
	var start: Vector3 = right * _side * radius * 0.95 + Vector3.UP * height + toward * radius * 0.3
	for i in 2 + mini(stacks, 3) / 2:
		var v: Vector3 = right * _side * rng.randf_range(1.0, 1.7) + Vector3.UP * rng.randf_range(0.7, 1.4) + toward * rng.randf_range(-0.3, 0.3)
		drops.append({"p": start, "v": v * sqrt(scale_factor), "age": 0.0, "landed": -1.0, "size": rng.randf_range(0.035, 0.06) * scale_factor})

func redraw() -> void:
	var batch := _Batch.new()
	var overlay := _Batch.new()
	var view := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var up := Vector3.UP
	var toward := Vector3.BACK
	if view != null:
		right = view.global_basis.x
		up = view.global_basis.y
		toward = view.global_basis.z
	var flat_toward := Vector3(toward.x, 0, toward.z).normalized() if Vector2(toward.x, toward.z).length() > 0.01 else Vector3.BACK
	if presence.slow > 0:
		_draw_slow(batch, presence.slow)
	if presence.bound > 0:
		_draw_bound(batch, presence.bound, toward, flat_toward)
	if presence.shred > 0 or not flakes.is_empty():
		_draw_shred(overlay, presence.shred, right, up, flat_toward)
	for drop in drops:
		var color := BLOOD
		if drop.landed >= 0:
			color.a = 1.0 - (drop.age - drop.landed) / 0.25
		batch.billboard(drop.p, right, up, drop.size, color, 4.0, 1.0)
	if presence.stun > 0:
		_draw_stun(batch, presence.stun, right, up)
	batch.commit(_mesh)
	overlay.commit(_overlay_mesh)

func _draw_slow(batch: _Batch, fade: float) -> void:
	# Rings well out from its feet, wavering as they spread, over a faint cold pool.
	var reach: float = maxf(radius * 1.5, 0.42 * scale_factor)
	var pool := SLOW
	pool.a = 0.22 * fade
	batch.billboard(Vector3(0, 0.025, 0), Vector3.RIGHT, Vector3.BACK, reach * 1.25, pool, 0.0, 0.5)
	for k in 3:
		var t: float = fmod(time / 1.25 + k / 3.0, 1.0)
		var ring: float = lerpf(0.45, 1.15, t) * reach
		var color := SLOW
		color.a = fade * sin(PI * t) * 0.95
		var steps := 36
		for i in steps:
			var a0 := TAU * i / steps
			var a1 := TAU * (i + 1) / steps
			var r0: float = ring * (1.0 + 0.07 * sin(5.0 * a0 + time * 3.1 + k))
			var r1: float = ring * (1.0 + 0.07 * sin(5.0 * a1 + time * 3.1 + k))
			var w: float = 0.035 * scale_factor
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var y := Vector3(0, 0.03, 0)
			batch.strip(y + d0 * (r0 - w), y + d0 * (r0 + w), y + d1 * (r1 - w), y + d1 * (r1 + w), color, 1.0, 0.55)

func _draw_bound(batch: _Batch, fade: float, toward: Vector3, flat_toward: Vector3) -> void:
	# Three cable loops round the waist that snap tight as the bind takes hold. The body hides
	# their back halves, so they read as wrapped round it.
	var waist: float = lerpf(bottom, top, 0.4)
	var span: float = (top - bottom) * 0.09
	var tight: float = 1.0 + 0.55 * (1.0 - fade) * (1.0 - fade)
	var color := CABLE
	color.a = fade
	for k in 3:
		var height: float = waist + (k - 1) * span
		var tilt: float = (k - 1) * 0.16
		var r: float = radius * (0.96 - 0.06 * absf(k - 1)) * tight * (1.0 - 0.025 * sin(time * 8.0 + k))
		var steps := 30
		var points: Array[Vector3] = []
		for i in steps + 1:
			var a := TAU * i / steps
			points.append(Vector3(cos(a) * r, height + sin(a) * r * tilt, sin(a) * r))
		for i in steps:
			var side := (points[i + 1] - points[i]).cross(toward)
			if side.length() < 0.000001:
				continue
			side = side.normalized() * 0.03 * scale_factor
			batch.strip(points[i] - side, points[i] + side, points[i + 1] - side, points[i + 1] + side, color, 1.7, 1.0)
	# A brass clasp where the cables cross, facing the camera.
	var clasp := CLASP
	clasp.a = fade * (0.75 + 0.25 * sin(time * 6.0))
	var view := get_viewport().get_camera_3d()
	if view != null:
		batch.billboard(flat_toward * radius * 0.96 * tight + Vector3.UP * waist, view.global_basis.x, view.global_basis.y, 0.06 * scale_factor, clasp, 0.0, 0.5)

func _draw_shred(batch: _Batch, fade: float, right: Vector3, up: Vector3, flat_toward: Vector3) -> void:
	# A shield on its chest, split by a crack that keeps working open; flakes drop off it.
	var chest: Vector3 = Vector3.UP * lerpf(bottom, top, 0.66) + flat_toward * radius * 1.1
	var size: float = 0.15 * scale_factor * (0.7 + 0.3 * fade)
	var split: float = clampf(0.12 + 0.08 * sin(time * 3.4), 0.0, 0.9)
	var color := SHRED
	color.a = fade * (0.85 + 0.15 * sin(time * 5.0))
	if fade > 0:
		batch.billboard(chest, right, up, size, color, 3.0 + split, 0.6)
	for flake in flakes:
		var bit := SHRED
		bit.a = 1.0 - flake.age / flake.life
		batch.billboard(chest + right * flake.p.x + Vector3.UP * flake.p.y, right, up, 0.022 * scale_factor, bit, 0.0, 0.5)

func _draw_stun(batch: _Batch, fade: float, right: Vector3, up: Vector3) -> void:
	# Three stars wheeling round over its head on a faint path.
	var orbit: float = 0.26 * scale_factor
	var center := Vector3(0, stun_height + 0.02 * sin(time * 4.0), 0)
	var path := STAR
	path.a = 0.22 * fade
	var steps := 28
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var w := 0.01 * scale_factor
		var d0 := Vector3(cos(a0), 0, sin(a0)) * orbit
		var d1 := Vector3(cos(a1), 0, sin(a1)) * orbit
		batch.strip(center + d0 - Vector3(0, w, 0), center + d0 + Vector3(0, w, 0), center + d1 - Vector3(0, w, 0), center + d1 + Vector3(0, w, 0), path, 1.0, 0.5)
	for k in 3:
		var a: float = time * 4.2 + TAU * k / 3.0
		var spot: Vector3 = center + Vector3(cos(a), 0, sin(a)) * orbit
		var color := STAR
		color.a = fade
		batch.billboard(spot, right, up, 0.1 * scale_factor * (0.85 + 0.15 * sin(time * 9.0 + k)), color, 2.0, 0.6)

class _Batch:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()

	func _vertex(p: Vector3, color: Color, uv: Vector2, uv2: Vector2) -> void:
		verts.append(p)
		colors.append(color)
		uvs.append(uv)
		uv2s.append(uv2)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, uv2: Vector2) -> void:
		_vertex(a, color, uva, uv2); _vertex(b, color, uvb, uv2); _vertex(c, color, uvc, uv2)
		_vertex(a, color, uva, uv2); _vertex(c, color, uvc, uv2); _vertex(d, color, uvd, uv2)

	func billboard(p: Vector3, right: Vector3, up: Vector3, size: float, color: Color, shape: float, cover: float) -> void:
		var r := right * size
		var u := up * size
		quad(p - r - u, p + r - u, p + r + u, p - r + u, color,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(shape, cover))

	func strip(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, color: Color, shape: float, cover: float) -> void:
		# One segment of a band: a = one edge, b = the other (UV.y runs across it).
		quad(a0, b0, b1, a1, color, Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(shape, cover))

	func commit(mesh: ArrayMesh) -> void:
		mesh.clear_surfaces()
		if verts.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
