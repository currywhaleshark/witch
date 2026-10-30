extends Node3D
## Presentation only: sparks, smoke, flashes, slash arcs and trails in a brass/steam palette.
## The arena owns every combat rule. Effects draw from their own RNG and advance only through
## the arena's effect clock (sync_effect), so pause freezes them and combat RNG is untouched.
const GLOW := preload("res://shaders/vfx_glow.gdshader")
const SMOKE := preload("res://shaders/vfx_smoke.gdshader")
const HOT := Color(1.0, 0.93, 0.72)
const SPARK := Color(1.0, 0.66, 0.28)
const GOLD := Color(1.0, 0.84, 0.42)
const SOOT := Color(0.13, 0.12, 0.12)
const DUST := Color(0.55, 0.48, 0.4)
const STEAM := Color(0.74, 0.76, 0.74)
const MAX_PARTS := 320

static var _glow_material: ShaderMaterial
static var _smoke_material: ShaderMaterial

var elapsed := 0.0
## The arena's effect record; emitting more particles later extends its life.
var entry: Dictionary = {}
var camera: Camera3D
var rng := RandomNumberGenerator.new()
var _parts: Array = []
var _arcs: Array = []
var _rings: Array = []
var _line: Array = []
var _line_style: Dictionary = {}
var _blade: Array = []
var _blade_life := 0.14
var _lights: Array = []
var _last_dust := -1.0
var _glow := ArrayMesh.new()
var _smoke := ArrayMesh.new()

func setup(seed_value: int, view: Camera3D) -> void:
	top_level = true
	rng.seed = seed_value
	camera = view
	if _glow_material == null:
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = GLOW
		_glow_material.render_priority = 1
		_smoke_material = ShaderMaterial.new()
		_smoke_material.shader = SMOKE
	_layer(_smoke, "Smoke")
	_layer(_glow, "Glow")

func _layer(mesh: ArrayMesh, label: String) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _need(seconds: float) -> void:
	if not entry.is_empty():
		entry.life = maxf(float(entry.life), seconds)

# --- primitive emitters ---------------------------------------------------------------

func _part(p: Vector3, v: Vector3, life: float, size: float, color: Color, extra: Dictionary = {}) -> void:
	if _parts.size() >= MAX_PARTS:
		return
	var part := {"p": p, "v": v, "age": 0.0, "life": life, "size": size, "color": color,
		"smoke": false, "round": false, "drag": 0.0, "grav": 0.0, "floor": -INF, "grow": 0.0,
		"len": 0.0, "stretch": 0.0, "dir": Vector3.ZERO, "center": false, "hot": false, "seed": rng.randf()}
	part.merge(extra, true)
	_parts.append(part)
	_need(life)

func _cone(dir: Vector3, spread: float) -> Vector3:
	var random := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	if random.length() < 0.01:
		random = Vector3.UP
	if dir.length() < 0.01:
		return random.normalized()
	return (dir.normalized() + random.normalized() * spread).normalized()

func sparks(at: Vector3, dir: Vector3, count: int, speed: float, spread: float, color: Color, life: float = 0.35,
		width: float = 0.016, floor_y: float = -INF, grav: float = 9.0) -> void:
	for i in count:
		var v := _cone(dir, spread) * speed * rng.randf_range(0.45, 1.0)
		# Widths are authored thin; at the 1.75x quarter-view scale sparks need about double to read.
		_part(at, v, life * rng.randf_range(0.6, 1.0), width * 1.9, color,
			{"drag": 2.2, "grav": grav, "floor": floor_y, "len": 0.05, "stretch": 0.05, "hot": true})

func blobs(at: Vector3, dir: Vector3, count: int, speed: float, spread: float, color: Color, life: float, size: float, floor_y: float) -> void:
	# Dark mixed-blend chunks: debris or droplets that fall and settle.
	for i in count:
		var v := _cone(dir, spread) * speed * rng.randf_range(0.4, 1.0)
		_part(at, v, life * rng.randf_range(0.7, 1.0), size * rng.randf_range(0.6, 1.2), color,
			{"smoke": true, "drag": 1.0, "grav": 11.0, "floor": floor_y})

func puff(at: Vector3, v: Vector3, size: float, grow: float, color: Color, life: float, rise: float = 0.4) -> void:
	color.a = minf(1.0, color.a * 1.35)
	_part(at, v, life, size * 1.4, color, {"smoke": true, "drag": 3.0, "grav": -rise, "grow": grow * 1.3})

func flash(at: Vector3, size: float, color: Color, life: float, grow: float = 0.0) -> void:
	_part(at, Vector3.ZERO, life * 1.3, size * 1.4, color, {"round": true, "grow": grow})

func rays(at: Vector3, count: int, length: float, width: float, color: Color, life: float) -> void:
	# A star glint drawn in the screen plane.
	var base := rng.randf() * PI
	for i in count:
		var angle := base + PI * i / count
		_part(at, Vector3.ZERO, life, width, color, {"len": length, "center": true, "screen_angle": angle})

func streak(from: Vector3, to: Vector3, width: float, color: Color, life: float) -> void:
	# A still line from `from` (dim tail) to `to` (bright head).
	_part(to, Vector3.ZERO, life, width, color, {"len": from.distance_to(to), "dir": to - from})

func arc(center: Vector3, u: Vector3, w: Vector3, radius: float, thickness: float, from_angle: float, to_angle: float,
		sweep: float, life: float, color: Color) -> void:
	# A slash ribbon sweeping from from_angle to to_angle in the plane spanned by u (0) and w (PI/2).
	_arcs.append({"c": center, "u": u.normalized(), "w": w.normalized(), "r": radius, "t": thickness,
		"a0": from_angle, "a1": to_angle, "sweep": maxf(sweep, 0.001), "age": 0.0, "life": life, "color": color})
	_need(life)

func ground_ring(center: Vector3, r0: float, r1: float, width: float, color: Color, life: float) -> void:
	_rings.append({"c": center + Vector3(0, 0.05, 0), "r0": r0, "r1": r1, "w": width, "age": 0.0, "life": life, "color": color})
	_need(life)

func trail_point(p: Vector3, width: float, color: Color, life: float = 0.16) -> void:
	_line_style = {"w": width, "color": color, "life": life}
	_line.append({"p": p, "age": 0.0})
	_need(life)

func blade_point(base: Vector3, tip: Vector3, color: Color, life: float = 0.14) -> void:
	_blade_life = life
	_blade.append({"a": base, "b": tip, "age": 0.0, "color": color})
	_need(life)

func clear_trails() -> void:
	_blade.clear()
	_line.clear()

func bolt_trail(p: Vector3, color: Color) -> void:
	# Wire-crow orb: an electric streak behind it with a few stray sparks.
	trail_point(p, 0.13, color, 0.22)
	if rng.randf() < 0.6:
		sparks(p, Vector3.ZERO, 1, 1.8, 1.0, color, 0.2, 0.01, -INF, 0.0)

func burst(at: Vector3, color: Color, floor_y: float) -> void:
	flash(at, 0.45, color, 0.1, 1.5)
	sparks(at, Vector3.UP, 12, 4.0, 1.0, color, 0.35, 0.014, floor_y)

func dust_trail(at: Vector3, interval: float = 0.05) -> void:
	if _last_dust >= 0.0 and elapsed - _last_dust < interval:
		return
	_last_dust = elapsed
	for i in 2:
		var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		puff(at + side * 0.25 + Vector3(0, 0.12, 0), side * 0.8 + Vector3.UP * 0.4, 0.2, 0.9, Color(DUST, 0.42), 0.7, 0.2)

# --- recipes ----------------------------------------------------------------------------

func impact(at: Vector3, dir: Vector3, source: String, crit: bool, floor_y: float) -> void:
	var out := Vector3(dir.x, 0, dir.z).normalized() + Vector3.UP * 0.35
	match source:
		"grinder":
			sparks(at, out, 24, 7.5, 0.35, Color(1.0, 0.6, 0.24), 0.5, 0.015, floor_y)
			flash(at, 0.3, HOT, 0.07)
		"chainsaw":
			sparks(at, out, 14, 5.5, 0.55, SPARK, 0.4, 0.016, floor_y)
			blobs(at, out, 9, 3.2, 0.6, Color(0.42, 0.06, 0.05, 0.9), 0.6, 0.045, floor_y)
			flash(at, 0.28, Color(1.0, 0.55, 0.4), 0.07)
		"bolt_cutter":
			rays(at, 2, 0.6, 0.03, HOT, 0.09)
			sparks(at, out, 12, 5.0, 0.6, Color(1.0, 0.78, 0.45), 0.35, 0.016, floor_y)
			flash(at, 0.3, Color(1.0, 0.85, 0.55), 0.07)
		"shotgun":
			sparks(at, out, 6, 4.0, 0.7, SPARK, 0.25, 0.014, floor_y)
			flash(at, 0.22, HOT, 0.06)
		"turret":
			sparks(at, out, 8, 4.5, 0.6, Color(1.0, 0.76, 0.42), 0.3, 0.014, floor_y)
			flash(at, 0.26, HOT, 0.06)
		"automaton":
			sparks(at, out, 8, 4.0, 0.7, Color(0.6, 1.0, 0.88), 0.3, 0.014, floor_y)
			flash(at, 0.28, Color(0.7, 1.0, 0.92), 0.07)
		"saw":
			# B node's rotating saw: a grinder-like spray, slightly shorter.
			sparks(at, out, 16, 6.0, 0.4, Color(1.0, 0.62, 0.26), 0.4, 0.014, floor_y)
			flash(at, 0.24, HOT, 0.06)
		"automaton_blast":
			# The blast itself carries the spectacle; each caught enemy only flickers.
			flash(at, 0.3, Color(1.0, 0.7, 0.4), 0.08)
		"staff":
			flash(at, 0.42, Color(0.75, 1.0, 0.92), 0.09, 2.0)
			sparks(at, out, 10, 4.5, 0.7, Color(1.0, 0.8, 0.48), 0.35, 0.016, floor_y)
			puff(at, out * 0.6, 0.12, 0.7, Color(STEAM, 0.3), 0.5)
		_:
			sparks(at, out, 7, 4.0, 0.7, Color(0.65, 1.0, 0.9), 0.3, 0.014, floor_y)
			flash(at, 0.22, Color(0.7, 1.0, 0.92), 0.06)
	if crit:
		rays(at, 3, 1.15, 0.05, GOLD, 0.15)
		flash(at, 0.75, GOLD, 0.12, 1.5)
		sparks(at, out, 16, 7.0, 0.8, GOLD, 0.45, 0.018, floor_y)
		ground_ring(Vector3(at.x, floor_y, at.z), 0.2, 1.1, 0.07, GOLD, 0.26)

func muzzle(origin: Vector3, ends: Array, blocked: Array, floor_y: float) -> void:
	var forward := Vector3.ZERO
	for end in ends:
		forward += (end - origin).normalized()
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	for i in ends.size():
		var end: Vector3 = ends[i]
		var dir: Vector3 = (end - origin).normalized()
		var dist: float = origin.distance_to(end)
		streak(origin, end, 0.012, Color(1.0, 0.82, 0.55, 0.55), 0.07)
		# A short hot slug runs the trace ahead of the fading line.
		_part(origin, dir * 95.0, maxf(dist / 95.0, 0.01), 0.022, HOT, {"len": 0.55})
		if blocked[i]:
			sparks(end, -dir + Vector3.UP * 0.4, 5, 3.0, 0.8, SPARK, 0.3, 0.013, floor_y)
			puff(end, -dir * 0.3, 0.08, 0.5, Color(DUST, 0.35), 0.45)
	sparks(origin, forward, 9, 9.0, 0.22, HOT, 0.14, 0.016, floor_y, 2.0)
	for i in 4:
		puff(origin + forward * 0.1 * i, forward * rng.randf_range(0.6, 1.8) + Vector3.UP * 0.25, 0.1, 0.55, Color(STEAM, 0.32), rng.randf_range(0.6, 0.9))

func summon_shot(origin: Vector3, to: Vector3, color: Color, floor_y: float) -> void:
	# Turret bolt / automaton pulse: muzzle flash, a fast slug over a fading trace, a wisp of steam.
	var dir := (to - origin).normalized()
	var dist := origin.distance_to(to)
	flash(origin, 0.32, color.lightened(0.4), 0.07)
	streak(origin, to, 0.03, Color(color, 0.6), 0.09)
	_part(origin, dir * 60.0, maxf(dist / 60.0, 0.01), 0.05, color.lightened(0.3), {"len": 0.6})
	sparks(origin, dir, 4, 5.0, 0.35, color, 0.14, 0.012, floor_y, 2.0)
	puff(origin, dir * 0.4 + Vector3.UP * 0.2, 0.06, 0.4, Color(STEAM, 0.28), 0.45)

func summon_punch(fist: Vector3, toward: Vector3, color: Color, floor_y: float) -> void:
	# Automaton piston punch: a short knock flash at the fist, a forward spray, exhaust steam behind.
	var dir := Vector3(toward.x, 0, toward.z).normalized()
	flash(fist, 0.34, color.lightened(0.45), 0.07, 1.5)
	rays(fist, 5, 0.22, 0.03, color.lightened(0.3), 0.08)
	sparks(fist, dir, 7, 4.5, 0.6, color, 0.2, 0.013, floor_y, 3.0)
	for side in [-1.0, 1.0]:
		var out: Vector3 = dir.cross(Vector3.UP) * side
		puff(fist - dir * 0.25, out * 0.7 + Vector3.UP * 0.35 - dir * 0.3, 0.07, 0.6, Color(STEAM, 0.32), 0.45)

func blast(at: Vector3, radius: float, floor_y: float, big: bool) -> void:
	# Automaton self-destruct: brass fireball, shock ring at the damage radius, smoke column, debris.
	var base := Vector3(at.x, floor_y, at.z)
	var boost := 1.35 if big else 1.0
	flash(base + Vector3.UP * 0.5, radius * 0.5 * boost, Color(1.0, 0.66, 0.34), 0.16, 1.2)
	flash(base + Vector3.UP * 0.5, radius * 0.25 * boost, HOT, 0.1, 1.5)
	ground_ring(base, 0.2, radius, 0.26, Color(1.0, 0.6, 0.32), 0.4)
	ground_ring(base, 0.1, radius * 0.7, 0.1, HOT, 0.28)
	sparks(base + Vector3.UP * 0.4, Vector3.UP, int(28 * boost), 7.5, 0.95, SPARK, 0.65, 0.018, floor_y)
	blobs(base + Vector3.UP * 0.4, Vector3.UP, int(12 * boost), 5.5, 1.0, Color(0.22, 0.18, 0.14), 1.0, 0.06, floor_y)
	for i in int(8 * boost):
		var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.4
		puff(base + Vector3.UP * 0.4 + side, side + Vector3.UP * rng.randf_range(0.8, 1.6), 0.26, 0.9, Color(SOOT, 0.5), rng.randf_range(1.0, 1.4), 1.0)
	for i in 14:
		var a := TAU * i / 14.0
		var dir := Vector3(cos(a), 0, sin(a))
		puff(base + dir * 0.3 + Vector3(0, 0.12, 0), dir * radius * 2.0, 0.2, 0.9, Color(DUST, 0.45), rng.randf_range(0.7, 0.95), 0.1)

func glow_light(at: Vector3, color: Color, energy: float, reach: float, life: float) -> void:
	# A short real light that lights the surroundings in the effect colour, then fades out.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at
	_lights.append({"node": light, "energy": energy, "age": 0.0, "life": life})
	_need(life)

func potion_glow(at: Vector3, color: Color, floor_y: float) -> void:
	# Potion drunk: a soft light in the potion colour, a glow at the chest and motes that spiral
	# up around the body. The colour tells which potion it was.
	var chest := Vector3(at.x, floor_y + 0.85, at.z)
	glow_light(chest, color, 2.6, 2.4, 0.7)
	flash(chest, 0.42, color.lightened(0.35), 0.28, 0.8)
	for i in 16:
		var angle := TAU * i / 16.0 + rng.randf_range(-0.2, 0.2)
		var radius := rng.randf_range(0.28, 0.42)
		var p := Vector3(at.x + cos(angle) * radius, floor_y + rng.randf_range(0.05, 0.7), at.z + sin(angle) * radius)
		var swirl := Vector3(-sin(angle), 0, cos(angle)) * rng.randf_range(0.4, 0.8)
		_part(p, swirl + Vector3.UP * rng.randf_range(0.7, 1.3), rng.randf_range(0.55, 0.85), rng.randf_range(0.035, 0.06),
			color.lightened(0.25), {"round": true, "drag": 1.2})
	for i in 5:
		var p := Vector3(at.x + rng.randf_range(-0.2, 0.2), floor_y + 0.15, at.z + rng.randf_range(-0.2, 0.2))
		_part(p, Vector3.UP * rng.randf_range(1.6, 2.4), 0.45, 0.02, color, {"len": 0.35, "drag": 0.5})

func summon_arrive(at: Vector3, color: Color, floor_y: float) -> void:
	# The assembled summon settles: a vent of steam at its feet and a brief ring.
	var base := Vector3(at.x, floor_y, at.z)
	ground_ring(base, 0.15, 0.85, 0.06, color, 0.35)
	sparks(base + Vector3.UP * 0.3, Vector3.UP, 8, 3.0, 0.9, Color(1.0, 0.78, 0.45), 0.35, 0.013, floor_y)
	for i in 6:
		var a := TAU * i / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		puff(base + dir * 0.3 + Vector3(0, 0.1, 0), dir * 1.1 + Vector3.UP * 0.2, 0.12, 0.7, Color(STEAM, 0.35), 0.65, 0.5)

func shutdown(at: Vector3, floor_y: float) -> void:
	# Turret lifetime ends: it hisses out without a blast.
	for i in 4:
		puff(at + Vector3(rng.randf_range(-0.2, 0.2), 0.6, rng.randf_range(-0.2, 0.2)), Vector3.UP * rng.randf_range(0.5, 1.0), 0.1, 0.8, Color(STEAM, 0.4), 0.9, 0.8)
	sparks(at + Vector3.UP * 0.6, Vector3.UP, 5, 2.5, 1.0, Color(1.0, 0.78, 0.45), 0.3, 0.012, floor_y)

func summon_hit(at: Vector3, floor_y: float) -> void:
	sparks(at, Vector3.ZERO, 9, 3.8, 1.0, Color(0.78, 0.9, 1.0), 0.3, 0.014, floor_y)
	flash(at, 0.26, Color(1.0, 0.5, 0.36), 0.07)

func summon_break(at: Vector3, floor_y: float) -> void:
	# Destroyed (not self-destructed): sparks and soot only, so it never reads as a blast.
	flash(at, 0.4, Color(1.0, 0.7, 0.4), 0.09)
	sparks(at, Vector3.UP, 16, 4.5, 0.9, SPARK, 0.45, 0.015, floor_y)
	for i in 3:
		puff(at + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), Vector3.UP * 0.6, 0.16, 0.8, Color(SOOT, 0.45), 0.9, 0.7)

func relay(target: Vector3, sources: Array, floor_y: float) -> void:
	# Target relay: a signal ring on the target and a brief link from each summon that takes it.
	var color := Color(0.55, 1.0, 0.88)
	ground_ring(Vector3(target.x, floor_y, target.z), 0.2, 1.0, 0.06, color, 0.35)
	rays(target + Vector3.UP * 1.3, 2, 0.8, 0.03, color, 0.25)
	for source in sources:
		streak(source + Vector3.UP * 0.9, target + Vector3.UP * 1.0, 0.018, Color(color, 0.75), 0.25)

func hurt(at: Vector3, floor_y: float) -> void:
	sparks(at, Vector3.ZERO, 12, 4.0, 1.0, Color(1.0, 0.46, 0.32), 0.35, 0.016, floor_y)
	flash(at, 0.5, Color(1.0, 0.4, 0.3), 0.08, 1.0)
	for i in 2:
		puff(at, Vector3(rng.randf_range(-0.5, 0.5), 0.2, rng.randf_range(-0.5, 0.5)), 0.14, 0.6, Color(SOOT, 0.4), 0.55)

func block(at: Vector3, floor_y: float) -> void:
	rays(at, 2, 0.75, 0.035, Color(0.78, 0.92, 1.0), 0.1)
	flash(at, 0.8, Color(0.55, 0.75, 1.0, 0.45), 0.12, 2.0)
	sparks(at, Vector3.ZERO, 10, 5.0, 1.0, Color(0.75, 0.88, 1.0), 0.3, 0.014, floor_y)

func tell(at: Vector3, color: Color, size: float) -> void:
	# Wind-up glint: reads as "about to strike" without hiding the warning on the ground.
	rays(at, 2, 0.55 * size, 0.028, color.lightened(0.35), 0.22)
	flash(at, 0.32 * size, color, 0.2)

func claw(origin: Vector3, facing: Vector3, reach: float, color: Color, heavy: bool, floor_y: float) -> void:
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var side := f.cross(Vector3.UP)
	var center := origin + Vector3.UP * 0.95
	var w := (f + Vector3.DOWN * 0.3).normalized()
	var radius := maxf(reach, 0.6) * 0.8
	if heavy:
		arc(center, side, w, radius, 0.32, 0.25, PI - 0.25, 0.11, 0.3, color)
		for i in 3:
			puff(origin + f * radius * (0.6 + 0.2 * i) + Vector3(0, 0.1, 0), f * 0.8, 0.18, 0.9, Color(DUST, 0.4), 0.7, 0.15)
	else:
		for i in 3:
			var lift := Vector3.UP * (0.12 * (i - 1))
			arc(center + lift, side, (w + Vector3.UP * 0.25).normalized(), radius * (1.0 - 0.1 * i), 0.07, 0.35, PI - 0.35, 0.09, 0.24, color)
	sparks(center + f * radius * 0.8, f, 4, 2.5, 0.8, color, 0.25, 0.012, floor_y, 3.0)

func fan_slash(origin: Vector3, facing: Vector3, reach: float, angle_degrees: float, floor_y: float) -> void:
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var side := f.cross(Vector3.UP)
	var half := deg_to_rad(angle_degrees) / 2.0
	var center := origin + Vector3.UP * 0.85
	arc(center, side, f, reach * 0.8, 1.3, PI / 2 + half, PI / 2 - half, 0.14, 0.42, Color(1.0, 0.55, 0.3))
	arc(center + Vector3.UP * 0.12, side, f, reach * 0.62, 0.6, PI / 2 + half, PI / 2 - half, 0.12, 0.34, HOT)
	for i in 9:
		var a := PI / 2 + half - 2.0 * half * i / 8.0
		var dir := side * cos(a) + f * sin(a)
		puff(Vector3(origin.x, floor_y, origin.z) + dir * reach * rng.randf_range(0.45, 0.95) + Vector3(0, 0.12, 0),
			dir * 1.2, 0.24, 1.0, Color(DUST, 0.45), rng.randf_range(0.7, 1.0), 0.15)

func slam(origin: Vector3, facing: Vector3, length: float, width: float, floor_y: float) -> void:
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var side := f.cross(Vector3.UP)
	var base := Vector3(origin.x, floor_y + 0.06, origin.z)
	var head := base + f * length * 0.55
	flash(head + Vector3.UP * 0.3, 1.0, Color(1.0, 0.6, 0.35), 0.12, 1.0)
	streak(base, base + f * length, 0.18, Color(1.0, 0.52, 0.26), 0.3)
	sparks(head + Vector3.UP * 0.2, Vector3.UP, 20, 6.0, 0.8, SPARK, 0.5, 0.016, floor_y)
	blobs(head + Vector3.UP * 0.2, Vector3.UP, 14, 4.5, 0.9, Color(0.2, 0.17, 0.15), 0.8, 0.07, floor_y)
	for i in 10:
		var along := length * (i + 0.5) / 10.0
		for s in [-1.0, 1.0]:
			puff(base + f * along + side * s * width * 0.35 + Vector3(0, 0.1, 0), side * s * 1.4 + Vector3.UP * 0.3,
				0.24, 1.0, Color(DUST, 0.5), rng.randf_range(0.8, 1.15), 0.12)

func shockwave(origin: Vector3, radius: float, floor_y: float) -> void:
	var base := Vector3(origin.x, floor_y, origin.z)
	ground_ring(base, 0.3, radius, 0.28, Color(1.0, 0.58, 0.32), 0.42)
	ground_ring(base, 0.2, radius * 0.75, 0.12, HOT, 0.3)
	flash(base + Vector3.UP * 0.5, 1.3, Color(1.0, 0.6, 0.35), 0.14, 1.5)
	for i in 24:
		var a := TAU * i / 24.0 + rng.randf_range(-0.1, 0.1)
		var dir := Vector3(cos(a), 0, sin(a))
		puff(base + dir * 0.5 + Vector3(0, 0.15, 0), dir * radius * 2.4, 0.26, 1.1, Color(DUST, 0.5), rng.randf_range(0.8, 1.1), 0.1)
	blobs(base + Vector3.UP * 0.3, Vector3.UP, 16, 5.0, 1.0, Color(0.2, 0.17, 0.15), 0.9, 0.07, floor_y)

# --- simulation and drawing ---------------------------------------------------------------

func sync_effect(dt: float, _life: float) -> void:
	elapsed += dt
	for part in _parts:
		part.age += dt
		if part.drag > 0.0:
			part.v *= maxf(0.0, 1.0 - part.drag * dt)
		part.v.y -= part.grav * dt
		part.p += part.v * dt
		if part.p.y < part.floor:
			# Bounce once or twice off the ground, then settle.
			part.p.y = part.floor
			part.v = Vector3(part.v.x * 0.55, -part.v.y * 0.32, part.v.z * 0.55)
		part.size += part.grow * dt * (part.size if part.round else 1.0)
	_parts = _parts.filter(func(part): return part.age < part.life)
	for item in _arcs + _rings + _line + _blade:
		item.age += dt
	_arcs = _arcs.filter(func(item): return item.age < item.life)
	_rings = _rings.filter(func(item): return item.age < item.life)
	_line = _line.filter(func(item): return item.age < _line_style.get("life", 0.0))
	_blade = _blade.filter(func(item): return item.age < _blade_life)
	for light in _lights:
		light.age += dt
		light.node.light_energy = light.energy * pow(maxf(0.0, 1.0 - light.age / light.life), 2.0)
		if light.age >= light.life:
			light.node.queue_free()
	_lights = _lights.filter(func(light): return light.age < light.life)
	redraw()

func redraw() -> void:
	var view := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if view == null:
		return
	var right := view.global_basis.x
	var up := view.global_basis.y
	var toward := view.global_basis.z
	var glow := _Batch.new()
	var smoke := _Batch.new()
	for part in _parts:
		var t: float = part.age / part.life
		var color: Color = part.color
		if part.hot:
			color = HOT.lerp(color, minf(1.0, t * 3.0))
		if part.smoke:
			color.a *= (1.0 - t) * minf(1.0, part.age * 12.0 + 0.3)
			smoke.billboard(part.p, right, up, part.size, color, part.seed)
		elif part.round:
			color.a *= pow(1.0 - t, 1.5)
			glow.billboard(part.p, right, up, part.size, color, 1.0)
		else:
			color.a *= 1.0 - t
			var axis: Vector3 = part.v if part.v.length() > 0.01 else part.dir
			var length: float = part.len + part.v.length() * part.stretch
			if part.has("screen_angle"):
				axis = right * cos(part.screen_angle) + up * sin(part.screen_angle)
			if axis.length() < 0.0001:
				continue
			axis = axis.normalized()
			var head: Vector3 = part.p + axis * (length / 2.0 if part.center else 0.0)
			var tail: Vector3 = head - axis * length
			if part.center:
				# Glints are bright in the middle: draw as two halves pointing outwards.
				glow.streak(head, part.p, toward, part.size, color)
				glow.streak(part.p - axis * length / 2.0, part.p, toward, part.size, color)
			else:
				glow.streak(tail, head, toward, part.size, color)
	for item in _arcs:
		_draw_arc(glow, item)
	for item in _rings:
		_draw_ring(glow, item)
	if _line.size() > 1:
		for i in _line.size() - 1:
			var a: Dictionary = _line[i]
			var b: Dictionary = _line[i + 1]
			var life: float = _line_style.life
			var color: Color = _line_style.color
			var fade_a: float = 1.0 - a.age / life
			var fade_b: float = 1.0 - b.age / life
			glow.ribbon(a.p, b.p, toward, _line_style.w, color, fade_a, fade_b)
	if _blade.size() > 1:
		for i in _blade.size() - 1:
			var a: Dictionary = _blade[i]
			var b: Dictionary = _blade[i + 1]
			glow.blade(a.a, a.b, b.a, b.b, b.color, 1.0 - a.age / _blade_life, 1.0 - b.age / _blade_life)
	glow.commit(_glow, _glow_material)
	smoke.commit(_smoke, _smoke_material)

func _draw_arc(glow: _Batch, item: Dictionary) -> void:
	var progress: float = clampf(item.age / item.sweep, 0.0, 1.0)
	var fade: float = 1.0 - clampf((item.age - item.sweep) / maxf(item.life - item.sweep, 0.001), 0.0, 1.0)
	var head_angle: float = lerpf(item.a0, item.a1, progress)
	var span: float = item.a1 - item.a0
	var tail_angle: float = lerpf(item.a0, item.a1, maxf(0.0, progress - 0.75))
	var steps := 14
	var color: Color = item.color
	color.a *= fade
	var previous := {}
	for i in steps + 1:
		var s := float(i) / steps
		var angle: float = lerpf(tail_angle, head_angle, s)
		var radial: Vector3 = item.u * cos(angle) + item.w * sin(angle)
		var half: float = item.t * 0.5 * (0.25 + 0.75 * s)
		# The cross-section also rises, so a flat sweep still reads from the 30-degree camera.
		var inner: Vector3 = item.c + radial * (item.r - half) + Vector3.DOWN * half * 0.5
		var outer: Vector3 = item.c + radial * (item.r + half) + Vector3.UP * half * 0.5
		# Most of the visible arc stays bright; only the far tail thins out.
		var strength := 0.2 + 0.8 * sqrt(s)
		if not previous.is_empty() and absf(span) > 0.001:
			glow.blade(previous.inner, previous.outer, inner, outer, color, previous.strength, strength)
		previous = {"inner": inner, "outer": outer, "strength": strength}

func _draw_ring(glow: _Batch, item: Dictionary) -> void:
	var t: float = item.age / item.life
	var radius: float = lerpf(item.r0, item.r1, 1.0 - pow(1.0 - t, 2.0))
	var color: Color = item.color
	color.a *= 1.0 - t
	var steps := 40
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		glow.blade(item.c + d0 * (radius - item.w), item.c + d0 * (radius + item.w * 0.3),
			item.c + d1 * (radius - item.w), item.c + d1 * (radius + item.w * 0.3), color, 1.0, 1.0, true)

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

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, uv2: Vector2) -> void:
		# a-b along the tail edge, d-c along the head edge.
		_vertex(a, ca, uva, uv2); _vertex(b, ca, uvb, uv2); _vertex(c, cb, uvc, uv2)
		_vertex(a, ca, uva, uv2); _vertex(c, cb, uvc, uv2); _vertex(d, cb, uvd, uv2)

	func billboard(p: Vector3, right: Vector3, up: Vector3, size: float, color: Color, mode: float, seed_value: float = 0.0) -> void:
		var r := right * size
		var u := up * size
		quad(p - r - u, p + r - u, p + r + u, p - r + u, color, color,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(mode, seed_value))

	func streak(tail: Vector3, head: Vector3, toward: Vector3, width: float, color: Color) -> void:
		var side := (head - tail).cross(toward)
		if side.length() < 0.000001:
			return
		side = side.normalized() * width
		quad(tail - side, tail + side, head + side, head - side, color, color,
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2.ZERO)

	func ribbon(a: Vector3, b: Vector3, toward: Vector3, width: float, color: Color, fade_a: float, fade_b: float) -> void:
		var side := (b - a).cross(toward)
		if side.length() < 0.000001:
			return
		side = side.normalized() * width
		var ca := color
		ca.a *= maxf(fade_a, 0.0)
		var cb := color
		cb.a *= maxf(fade_b, 0.0)
		quad(a - side * fade_a, a + side * fade_a, b + side * fade_b, b - side * fade_b, ca, cb,
			Vector2(fade_a, 0), Vector2(fade_a, 1), Vector2(fade_b, 1), Vector2(fade_b, 0), Vector2.ZERO)

	func blade(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, color: Color, s0: float, s1: float, flat: bool = false) -> void:
		# A ribbon segment between two cross-sections (a = inner edge, b = outer edge).
		# s0/s1 fade along the ribbon through UV.x only, which the shader already applies.
		var x0 := 1.0 if flat else clampf(s0, 0.0, 1.0)
		var x1 := 1.0 if flat else clampf(s1, 0.0, 1.0)
		quad(a0, b0, b1, a1, color, color, Vector2(x0, 0), Vector2(x0, 1), Vector2(x1, 1), Vector2(x1, 0), Vector2.ZERO)

	func commit(mesh: ArrayMesh, material: Material) -> void:
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
		mesh.surface_set_material(0, material)
