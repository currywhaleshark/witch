extends "res://scripts/summon_assembly.gd"
## A firearm skill's gun: it assembles beside the witch during the cast, then floats at her
## shoulder until dismissed, recoiling on each shot. Arena owns ammo, damage and mana; the model
## is the shotgun cast's airborne gun as a stand-in until the guns get models of their own.
const PARTS = preload("res://assets/actors/shotgun_cast_v1/shotgun_parts.glb")
# Muzzle placement: the barrel runs back from it, so the gun's body sits by her right shoulder.
const SIDE := 0.5
const HEIGHT := 1.3
const FORWARD := 0.45
var gun_id := ""
var _flash: MeshInstance3D
var _kick := 0.0
var _bob := 0.0
var _aim := Vector3.ZERO

func _init() -> void:
	parts_scene = PARTS; assembly_name = "FloatingGun"
	effect_radius = 0.35; effect_height = 0.25
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/shotgun_cast_v1/parts.json"))
	for part in data.parts: part_delays[part.name] = float(part.delay)

func initialize(arena: Node3D) -> void:
	super.initialize(arena)
	_ring.position = Vector3(0, -0.10, 0.32)
	_core.position = Vector3(0, 0.02, 0.32)
	_flash = _glow(0.28); _flash.position = Vector3(0, 0, -0.035)
	var material: StandardMaterial3D = _flash.material_override
	var texture: GradientTexture2D = material.albedo_texture
	texture.gradient.colors = PackedColorArray([Color(1,0.98,0.8,1),Color(1,0.67,0.18,0.8),Color(1,0.34,0.03,0.15),Color(0,0,0,0)])
	material.albedo_color = Color(1, 1, 1, 0)
	_flash.visible = false
	follow(0.0)

func aim_at(target: Vector3) -> void:
	_aim = target

func follow(dt: float) -> void:
	# Float over her right shoulder and point where she last aimed (her facing otherwise).
	var player: Node3D = _arena.player
	var facing: Vector3 = -_arena.player_model.global_basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	var right := facing.cross(Vector3.UP).normalized()
	_bob += dt
	var origin: Vector3 = player.position + Vector3.UP * (HEIGHT + 0.03 * sin(_bob * 2.4)) + right * SIDE + facing * FORWARD
	var target: Vector3 = _aim if _aim != Vector3.ZERO else origin + facing
	var axis: Vector3 = target - origin
	axis.y = clampf(axis.y, -0.3 * axis.length(), 0.3 * axis.length())
	if Vector2(axis.x, axis.z).length() < 0.05:
		axis = facing
	global_transform = Transform3D(Basis.looking_at(axis.normalized(), Vector3.UP), origin)

func ready_to_fire() -> void:
	# The cast released: the assembled gun stays, solid, instead of fading like a summon preview.
	if mode != "assembling": return
	sample_progress(1.0)
	mode = "ready"
	_end_time = 0.0
	for part in parts:
		part.mesh.visible = true
		part.mesh.transform = part.target
		_opacity(part, 1.0, 0.0)
	_light(1.0, 0.0)

func shoot(target: Vector3) -> void:
	if mode != "ready": return
	aim_at(target)
	follow(0.0)
	_kick = 1.0
	_flash.visible = true

func muzzle() -> Vector3:
	return global_position

func dismiss() -> void:
	# Taken apart: the pieces drift out and fade, like the shotgun after its shot.
	if mode == "assembling":
		cancel("dismissed")
	elif mode == "ready":
		mode = "dismissed"
		_end_time = 0.0

func advance(dt: float) -> void:
	if is_instance_valid(_arena) and _arena.paused: return
	if mode == "assembling":
		follow(dt)
		return
	if mode == "ready":
		follow(dt)
		_kick = maxf(0.0, _kick - dt / 0.16)
		for part in parts:
			part.mesh.transform = part.target
			part.mesh.position.z += 0.07 * sin(_kick * PI) * _kick
		_flash.visible = _kick > 0.45
		_flash.material_override.albedo_color.a = clampf((_kick - 0.45) / 0.55, 0.0, 1.0)
		return
	if mode == "dismissed":
		_end_time += dt
		follow(dt)
		var fade := 1.0 - smoothstep(0.0, 0.3, _end_time)
		for part in parts:
			part.mesh.transform = part.target
			part.mesh.position += part.outward * smoothstep(0.0, 0.3, _end_time) * 0.09
			part.mesh.position.y += smoothstep(0.0, 0.3, _end_time) * 0.10
			_opacity(part, fade, (1.0 - fade) * 0.7)
		_light(1.0, fade * 0.4)
		_flash.visible = false
		if _end_time >= 0.32: queue_free()
		return
	super.advance(dt)

func debug_state() -> Dictionary:
	var state := super.debug_state()
	state.merge({"gun": gun_id, "flash": _flash != null and _flash.visible})
	return state
