extends Node3D
## The smoke launcher's cloud: soft grey puffs over the zone. Arena drives it through show_state, so
## it forms when the canisters land, holds, thins out at the end and freezes while paused.
const PUFFS := 18
const DENSITY := 0.62
const FORM := 0.4
const THIN := 1.0
var radius := 2.6
var _puffs: Array[Dictionary] = []
var _time := 0.0

func initialize(center: Vector3, zone_radius: float) -> void:
	name = "SmokeCloud"
	# Reset clears it together with the casts' leftovers.
	add_to_group("cast_assemblies")
	position = center
	radius = zone_radius
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient; texture.width = 64; texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5); texture.fill_to = Vector2(0.5, 0.0)
	# A fixed layout (not the combat RNG): the same cloud every time.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in PUFFS:
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = Color(0.66, 0.69, 0.68, 0.0)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * radius * rng.randf_range(0.75, 1.15)
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		var angle := rng.randf() * TAU
		var spot := Vector3(cos(angle), 0, sin(angle)) * radius * 0.8 * sqrt(rng.randf())
		spot.y = rng.randf_range(0.35, 1.5)
		_puffs.append({"node": node, "home": spot, "phase": rng.randf() * TAU, "speed": rng.randf_range(0.25, 0.5)})
	show_state(1.0, 1.0, 1.0)

func show_state(wait: float, left: float, total: float) -> void:
	# Hidden before the canisters land, then it billows up, holds and thins in its last second.
	var amount := 0.0
	if wait <= 0.0:
		amount = minf(1.0, (total - left) / FORM) * clampf(left / THIN, 0.0, 1.0)
	for puff in _puffs:
		var node: MeshInstance3D = puff.node
		node.visible = amount > 0.001
		var drift: float = _time * float(puff.speed) + float(puff.phase)
		node.position = puff.home * (0.6 + 0.4 * minf(1.0, amount * 1.5)) + Vector3(cos(drift), 0.3 * sin(drift * 1.3), sin(drift)) * 0.18
		node.material_override.albedo_color.a = DENSITY * amount

func advance(dt: float) -> void:
	_time += dt

func density() -> float:
	return 0.0 if _puffs.is_empty() else float(_puffs[0].node.material_override.albedo_color.a) / DENSITY
