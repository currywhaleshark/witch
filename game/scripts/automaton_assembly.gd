extends Node3D
## Cosmetic cast preview. Only arena's successful release may create a living ally.
const PARTS = preload("res://assets/actors/automaton_assembly_v1/automaton_parts.glb")
const Shape = preload("res://scripts/shapes.gd")
const DELAY := {"part_003":0.0,"part_005":0.0,"part_008_L":0.06,"part_008_R":0.06,
	"part_000":0.13,"part_009":0.22,"part_010":0.22,"part_001":0.31,"part_004":0.31,
	"part_013":0.37,"part_011":0.42,"part_002":0.46,"part_006":0.52}
const TEAL := Color("8dd8c4")
var parts: Array[Dictionary] = []
var progress := 0.0
var mode := "assembling"
var cancel_reason := ""
var _arena: Node3D
var _ring: MeshInstance3D
var _core: MeshInstance3D
var _motes: Array[MeshInstance3D] = []
var _end_time := 0.0
var _accumulator := 0.0
var _clink_played := false
var _fall_sound_played := false

func initialize(arena: Node3D) -> void:
	_arena = arena
	name = "AutomatonAssembly"
	add_to_group("cast_assemblies")
	var model: Node3D = PARTS.instantiate()
	add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	meshes.sort_custom(func(a, b): return str(a.name) < str(b.name))
	for i in meshes.size():
		var mesh: MeshInstance3D = meshes[i]
		var part_name := str(mesh.name)
		var target: Transform3D = global_transform.affine_inverse() * mesh.global_transform
		mesh.reparent(self, true)
		var material: StandardMaterial3D = mesh.get_active_material(0).duplicate()
		mesh.material_override = material
		material.emission_enabled = true
		material.emission = TEAL
		var angle := float(i) * 2.399963
		var outward := Vector3(cos(angle), 0, sin(angle))
		var start := target.origin + outward * (0.42 + 0.04 * (i % 3)) + Vector3.UP * (0.24 + 0.1 * (i % 3))
		var axis := Vector3(sin(angle), 0.7, cos(angle)).normalized()
		var rotation_start := Basis(axis, 0.6 + 0.15 * (i % 4)) * target.basis
		var box := mesh.mesh.get_aabb()
		var corners: Array[Vector3] = []
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]: corners.append(Vector3(x, y, z))
		parts.append({"name":part_name,"mesh":mesh,"material":material,"target":target,
			"start":start,"start_basis":rotation_start,"delay":float(DELAY.get(part_name,0.3)),
			"axis":axis,"outward":outward,"corners":corners,"opacity":0.0,
			"velocity":Vector3.ZERO,"spin":0.0})
	model.queue_free()
	_ring = Shape.ring(self, Vector3(0, 0.015, 0), 0.60, TEAL, 0.018)
	var ring_material: StandardMaterial3D = _ring.material_override.duplicate()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_material
	_core = _glow(0.70)
	_core.position = Vector3(0, 0.40, 0)
	for i in 20:
		var mote := _glow(0.055 + 0.015 * (i % 3))
		_motes.append(mote)
	sample_progress(0.0)

func _glow(size: float) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color(0.8,1.0,0.88,0.65),Color(0.35,0.85,0.72,0.38),Color(0.15,0.65,0.57,0.09),Color(0,0,0,0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient; texture.width = 64; texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5); texture.fill_to = Vector2(0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new(); quad.size = Vector2.ONE * size
	var node := MeshInstance3D.new(); node.mesh = quad; node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _opacity(part: Dictionary, amount: float, energy: float) -> void:
	var material: StandardMaterial3D = part.material
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if amount < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.albedo_color.a = amount
	material.emission_energy_multiplier = energy

func sample_progress(value: float) -> void:
	if mode != "assembling": return
	progress = clampf(value, 0.0, 1.0)
	for part in parts:
		var mesh: MeshInstance3D = part.mesh
		var t := clampf((progress - float(part.delay)) / 0.40, 0.0, 1.0)
		var arrival := smoothstep(0.08, 1.0, t)
		mesh.visible = progress > float(part.delay)
		mesh.position = (part.start as Vector3).lerp(part.target.origin, arrival)
		mesh.position.y += sin(arrival * PI) * 0.12
		mesh.basis = Basis((part.start_basis as Basis).get_rotation_quaternion().slerp((part.target as Transform3D).basis.get_rotation_quaternion(), arrival))
		part.opacity = smoothstep(0.0, 0.20, t)
		_opacity(part, part.opacity, (1.0 - smoothstep(0.25, 1.0, t)) * 0.8)
	_light(progress, 1.0)
	if progress >= 0.50 and not _clink_played:
		_clink_played = true
		_arena.play_cue(2.1, -10.0)

func _light(phase: float, strength: float) -> void:
	var ring_material: StandardMaterial3D = _ring.material_override
	ring_material.albedo_color.a = strength * (0.18 + 0.35 * sin(phase * PI))
	_ring.rotation.y = phase * 3.0
	_ring.scale = Vector3.ONE * (0.75 + 0.25 * sin(phase * PI))
	var core_material: StandardMaterial3D = _core.material_override
	core_material.albedo_color.a = strength * (0.35 + 0.4 * sin(phase * PI))
	for i in _motes.size():
		var angle := i * 2.399963 + phase * 7.0
		var radius := 0.28 + 0.28 * (1.0 - phase) + 0.06 * sin(i * 1.5)
		_motes[i].position = Vector3(cos(angle) * radius, 0.08 + fposmod(i * 0.117 + phase * 0.9, 0.86), sin(angle) * radius)
		var material: StandardMaterial3D = _motes[i].material_override
		material.albedo_color.a = strength * (0.45 + 0.45 * sin(phase * PI))

func complete() -> void:
	if mode != "assembling": return
	sample_progress(1.0)
	mode = "complete"
	_end_time = 0.0
	for part in parts: part.mesh.visible = false

func cancel(reason: String = "interrupted") -> void:
	if mode != "assembling": return
	mode = "collapse"; cancel_reason = reason
	_end_time = 0.0; _accumulator = 0.0
	# Capture the current transforms. Hidden pieces stay hidden; no completed-pose snap.
	for i in parts.size():
		var part := parts[i]
		part.velocity = part.outward * (0.12 + 0.025 * (i % 3))
		part.spin = 1.0 + 0.25 * (i % 4)

func _process(dt: float) -> void:
	advance(dt)

func advance(dt: float) -> void:
	if mode == "assembling" or (is_instance_valid(_arena) and _arena.paused): return
	_end_time += dt
	if mode == "complete":
		_light(1.0, maxf(0.0, 1.0 - _end_time / 0.22))
		if _end_time >= 0.24: queue_free()
		return
	_accumulator += dt
	while _accumulator >= 1.0 / 120.0:
		_fall_step(1.0 / 120.0)
		_accumulator -= 1.0 / 120.0
	_light(progress, maxf(0.0, 1.0 - _end_time / 0.18))
	var fade := 1.0 - smoothstep(1.05, 1.65, _end_time)
	for part in parts:
		if part.mesh.visible: _opacity(part, float(part.opacity) * fade, 0.0)
	if _end_time >= 1.7: queue_free()

func _fall_step(dt: float) -> void:
	for part in parts:
		var mesh: MeshInstance3D = part.mesh
		if not mesh.visible: continue
		part.velocity += Vector3.DOWN * 6.5 * dt
		mesh.position += part.velocity * dt
		mesh.basis = Basis(part.axis, float(part.spin) * dt) * mesh.basis
		var low := INF
		for corner in part.corners: low = minf(low, (mesh.basis * corner).y)
		var floor_y: float = _arena.map.ground_y(mesh.global_position) - global_position.y
		if mesh.position.y + low < floor_y + 0.004:
			mesh.position.y = floor_y - low + 0.004
			part.velocity.y = maxf(0.0, -float(part.velocity.y) * 0.10) if part.velocity.y < -0.5 else 0.0
			part.velocity.x *= exp(-12.0 * dt); part.velocity.z *= exp(-12.0 * dt)
			part.spin *= exp(-14.0 * dt)
			if not _fall_sound_played and _end_time > 0.06:
				_fall_sound_played = true
				_arena.play_cue(1.25, -8.0)

func debug_state() -> Dictionary:
	var visible_parts := 0
	for part in parts:
		if part.mesh.visible: visible_parts += 1
	return {"mode":mode,"progress":progress,"visible_parts":visible_parts,"part_count":parts.size(),
		"cancel_reason":cancel_reason,"elapsed_after_end":_end_time,"origin":global_position}
