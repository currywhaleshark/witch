extends "res://scripts/summon_assembly.gd"
## Powder keg (firearm area I): it assembles in front of the witch during the cast, rolls along
## the floor with its fuse burning down, then bursts into its parts. Arena owns the roll path,
## the contact check and the blast; this only draws them.
const MODEL = preload("res://assets/weapons/firearm_material_v4/powder_barrel.glb")
const DATA = "res://assets/weapons/firearm_material_v4/powder_barrel.json"
# Drum radius: rolling this far turns the staves one radian about the roll axis.
const RADIUS := 0.248
const BURST_SECONDS := 0.9
var _pivot: Vector3
var _roles: Dictionary = {}
var _fuse_origins: Array[Vector3] = []
var _roll := Transform3D.IDENTITY

func _init() -> void:
	assembly_name = "PowderKeg"
	effect_radius = 0.42; effect_height = 0.5
	parts_scene = MODEL
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_pivot = _point(data.sockets.Socket_roll_axis.position)
	for part in data.parts:
		part_delays[part.name] = float(part.delay)
		_roles[part.name] = part.role
	# Fuse segments run from the drum's socket (00) out to the tip (07); the ember burns inward.
	for i in 8:
		for part in data.parts:
			if part.role == "fuse_%02d" % i:
				_fuse_origins.append(_point(part.origin))

func _point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func role(part: Dictionary) -> String:
	return str(_roles.get(part.name, ""))

func launch() -> void:
	# The cast released: the finished keg sets off, solid, from where it assembled.
	if mode != "assembling": return
	sample_progress(1.0)
	mode = "rolling"
	_end_time = 0.0
	for part in parts:
		part.mesh.visible = true
		part.mesh.transform = part.target
		_opacity(part, 1.0, 0.0)
	roll_to(global_position, 0.0, 1.0)

func roll_to(at: Vector3, rolled: float, fuse_left: float) -> void:
	# fuse_left is the unburnt share of the fuse, 1 at launch and 0 as it bursts.
	if mode != "rolling": return
	global_position = at
	var turn := Basis(Vector3.RIGHT, -rolled / RADIUS)
	_roll = Transform3D(turn, _pivot - turn * _pivot)
	var burning: float = clampf(fuse_left, 0.0, 1.0) * 8.0
	for part in parts:
		part.mesh.transform = _roll * part.target
		var id := role(part)
		if id == "fuse_ember":
			# The ember sits on the last unburnt segment, moving tip -> socket.
			var seg := clampi(int(ceil(burning)) - 1, 0, 7)
			part.mesh.visible = burning > 0.0
			part.mesh.position = _roll * _fuse_origins[seg]
		elif id.begins_with("fuse_") and id.trim_prefix("fuse_").is_valid_int():
			part.mesh.visible = float(id.trim_prefix("fuse_").to_int()) < burning
	_light(1.0, 0.0)

func burst() -> void:
	# Blown apart: the staves and hoops fly out from the drum and fade on the floor.
	if mode == "assembling":
		cancel("burst")
		return
	if mode != "rolling": return
	mode = "burst"
	_end_time = 0.0
	for part in parts:
		part.target = part.mesh.transform
		if role(part).begins_with("fuse"): part.mesh.visible = false

func dismiss() -> void:
	# Taken off the field without a blast (the field was cleared).
	if mode == "assembling":
		cancel("dismissed")
	elif mode == "rolling":
		mode = "complete"
		_end_time = 0.0
		for part in parts: part.mesh.visible = false

func advance(dt: float) -> void:
	if mode == "rolling" or (is_instance_valid(_arena) and _arena.paused): return
	if mode != "burst":
		super.advance(dt)
		return
	_end_time += dt
	var t := _end_time
	for i in parts.size():
		var part: Dictionary = parts[i]
		if not part.mesh.visible: continue
		var outward: Vector3 = (part.target.origin - _pivot)
		outward.y = 0.0
		outward = outward.normalized() if outward.length() > 0.01 else part.outward
		part.mesh.transform = part.target
		part.mesh.position += outward * t * 1.6 + Vector3.UP * (1.8 * t - 3.2 * t * t)
		part.mesh.basis = Basis(part.axis, t * (2.0 + i % 3)) * part.mesh.basis
		# Cosmetic floor clamp only: the pieces have no collision.
		var low := INF
		for corner in part.corners: low = minf(low, (part.mesh.transform * corner).y)
		if low < 0.0: part.mesh.position.y -= low
		_opacity(part, 1.0 - smoothstep(0.45, BURST_SECONDS, t), 0.0)
	if t >= BURST_SECONDS: queue_free()

func debug_state() -> Dictionary:
	var state := super.debug_state()
	var fuse := 0
	for part in parts:
		if part.mesh.visible and role(part).begins_with("fuse_") and role(part) != "fuse_ember": fuse += 1
	state.merge({"fuse_segments": fuse})
	return state
