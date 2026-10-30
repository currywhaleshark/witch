extends MeshInstance3D
## Casting circle under the witch's feet. Presentation only: the arena owns casting and release.
## It grows in and spins up while a cast charges, flares on release and then fades; instant
## casts pop it briefly. The shape carries the skill tree (see cast_circle.gdshader).
const SHADER = preload("res://shaders/cast_circle.gdshader")
const TREES := {"firearm": 0, "drive": 1, "automation": 2}
const COLORS := {"firearm": Color(1.0, 0.42, 0.14), "drive": Color(1.0, 0.70, 0.22), "automation": Color(0.30, 0.95, 0.82)}
const RADIUS := 1.05
const FADE_SECONDS := 0.45

var tree := ""
var charging := true
var progress := 0.0
var _age := 0.0
var _clock := 0.0
var _flare := 0.0
var _fade := -1.0
var _material: ShaderMaterial

func setup(tree_name: String, instant: bool) -> void:
	tree = tree_name
	name = "CastCircle"
	top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * RADIUS * 2.0
	mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tree", TREES[tree_name])
	_material.set_shader_parameter("color", COLORS[tree_name])
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if instant:
		progress = 1.0
		flare()
	_apply()

func flare() -> void:
	# The cast went off: a bright pulse, then the circle fades.
	_flare = 1.0
	charging = false
	if _fade < 0.0:
		_fade = 0.0

func sync(dt: float, at: Vector3, still_charging: bool, charge: float) -> bool:
	# Called on the arena's pausable clock. Returns false once fully faded.
	_age += dt
	if charging and still_charging:
		progress = clampf(charge, 0.0, 1.0)
	elif charging:
		# Cancelled or released without a flare yet: just fade.
		charging = false
		_fade = 0.0
	_clock += dt * (0.5 + 2.2 * progress + 3.0 * _flare)
	_flare = maxf(0.0, _flare - dt / 0.3)
	if _fade >= 0.0:
		_fade += dt
	global_position = at + Vector3.UP * 0.03
	_apply()
	return _fade < FADE_SECONDS

func _apply() -> void:
	var appear := smoothstep(0.0, 0.14, _age) if charging else 1.0
	var fade := 1.0 - smoothstep(0.1, FADE_SECONDS, _fade) if _fade >= 0.0 else 1.0
	scale = Vector3.ONE * (0.72 + 0.28 * smoothstep(0.0, 0.14, _age) + 0.12 * _flare)
	_material.set_shader_parameter("appear", maxf(appear, progress))
	_material.set_shader_parameter("strength", (0.45 + 0.55 * progress) * (1.0 + 0.9 * _flare) * fade)
	_material.set_shader_parameter("clock", _clock)

func debug_state() -> Dictionary:
	return {"tree": tree, "charging": charging, "progress": progress, "fading": _fade >= 0.0}
