extends Node3D
## Burning ground left by white phosphorus or a bursting naval shell: flickering flames over the
## patch. Arena drives it through show_state, so it dies down with the fire and freezes on pause.
const FLAMES := 10
var radius := 1.5
var _flames: Array[Dictionary] = []
var _time := 0.0

func initialize(center: Vector3, patch_radius: float) -> void:
	name = "FirePatch"
	add_to_group("cast_assemblies")
	position = center
	radius = patch_radius
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 0.95, 0.7, 1), Color(1.0, 0.55, 0.15, 0.7), Color(0.8, 0.15, 0.0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient; texture.width = 64; texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5); texture.fill_to = Vector2(0.5, 0.0)
	# A fixed layout (not the combat RNG).
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in FLAMES:
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var quad := QuadMesh.new()
		quad.size = Vector2(0.7, 1.0) * rng.randf_range(0.6, 1.0) * maxf(1.0, radius / 1.5)
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		var angle := rng.randf() * TAU
		var spot := Vector3(cos(angle), 0, sin(angle)) * radius * 0.85 * sqrt(rng.randf())
		_flames.append({"node": node, "home": spot, "phase": rng.randf() * TAU})
	show_state(1.0, 1.0)

func show_state(left: float, total: float) -> void:
	# Full flames until its last second, then they die down.
	var amount := clampf(left / minf(1.0, total), 0.0, 1.0)
	for flame in _flames:
		var node: MeshInstance3D = flame.node
		var flicker: float = 0.75 + 0.25 * sin(_time * 11.0 + float(flame.phase))
		node.position = flame.home + Vector3.UP * (0.45 + 0.08 * sin(_time * 7.0 + float(flame.phase)))
		node.scale = Vector3(1.0, flicker, 1.0) * maxf(0.2, amount)
		node.material_override.albedo_color = Color(1, 1, 1, 0.85 * amount * flicker)

func advance(dt: float) -> void:
	_time += dt
