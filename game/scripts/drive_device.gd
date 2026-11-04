extends "res://scripts/summon_assembly.gd"
## Drive-tree devices (03 §4): the guillotines, the hydraulic press, the compound executor and the
## restraint winch. Each assembles at its spot during the cast, then runs on its own clock from the
## release. Arena owns that clock, the targets and every hit; this only draws the mechanism at a
## given time after the release (work), using the timings arena passes in from trial.json.
const DIR := "res://assets/weapons/drive_material_v3/"
const IDS := ["guillotine", "guillotine_saw", "guillotine_lock", "hydraulic_press", "compound_executor", "restraint_winch"]
const PRESS_STROKE := 0.88
const CLAMP_TRAVEL := 0.16
const GATE_OPEN := 1.35
const FADE_SECONDS := 0.5
var device := ""
var manifest: Dictionary
var info: Dictionary = {}
var timing: Dictionary = {}
var cables: Array[MeshInstance3D] = []

static func model_path(id: String) -> String:
	return DIR + id + ".glb"

func configure(id: String, plan: Dictionary, radius: float) -> void:
	device = id
	timing = plan
	manifest = JSON.parse_string(FileAccess.get_file_as_string(DIR + id + ".json"))
	parts_scene = load(model_path(id))
	assembly_name = "DriveDevice_" + id
	effect_radius = radius
	effect_height = 1.1 if id != "restraint_winch" else 0.5
	for part in manifest.parts:
		part_delays[part.name] = float(part.delay)
		info[part.name] = part

func group(part: Dictionary) -> String:
	return str(info[part.name].group)

func socket(key: String) -> Vector3:
	var value: Array = manifest.sockets["Socket_" + key].position
	return Vector3(value[0], value[1], value[2])

func around(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var turn := Basis(axis, angle)
	return Transform3D(turn, pivot - turn * pivot)

func at(key: String, fallback: float = 0.0) -> float:
	return float(timing.get(key, fallback))

func sample_progress(value: float) -> void:
	super.sample_progress(value)
	if mode != "assembling":
		return
	# The executor's cage assembles with its gates open; the winch keeps its cables reeled in.
	for part in parts:
		var role := group(part)
		if role.begins_with("gate_"):
			part.mesh.transform = around(socket(role), Vector3.UP, float(role.trim_prefix("gate_")) * GATE_OPEN) * part.mesh.transform
		elif role.begins_with("cable_"):
			part.mesh.visible = false

func activate() -> void:
	# The cast released: the finished device stands solid and starts its own clock at zero.
	if mode != "assembling":
		return
	sample_progress(1.0)
	mode = "working"
	_end_time = 0.0
	_light(1.0, 0.0)
	work(0.0)

func work(t: float, hooks: Array = []) -> void:
	# The mechanism at t seconds after the release; hooks are the winch's targets in world space.
	if mode != "working":
		return
	for part in parts:
		part.mesh.visible = not group(part).begins_with("cable_")
		part.mesh.transform = part.target
		_opacity(part, 1.0, 1.0 if str(info[part.name].surface) == "core" else 0.0)
	match device:
		"guillotine", "guillotine_lock":
			_drop(smoothstep(at("drop_at"), at("drop_at") + at("drop_seconds"), t), t)
		"guillotine_saw":
			_drop(smoothstep(at("saw_at"), at("saw_at") + at("saw_seconds"), t), t)
		"hydraulic_press":
			_press(t)
		"compound_executor":
			_press(t)
			_cage(t)
		"restraint_winch":
			_winch(t, hooks)
	var fade := smoothstep(at("end_at"), at("end_at") + FADE_SECONDS, t)
	if fade > 0.0:
		for part in parts:
			part.mesh.position += part.outward * fade * 0.16 + Vector3.UP * fade * 0.18
			_opacity(part, 1.0 - fade, fade * 0.3)
		for cable in cables:
			cable.visible = false

func finished(t: float) -> bool:
	return t >= at("end_at") + FADE_SECONDS

func dismiss() -> void:
	# Taken off the field mid-run (the field was cleared): it simply goes.
	if mode == "assembling":
		cancel("dismissed")
	elif mode == "working":
		mode = "complete"
		_end_time = 0.0
		for part in parts: part.mesh.visible = false
		for cable in cables: cable.visible = false

func advance(dt: float) -> void:
	# A working device moves only by arena's clock (work), so it holds still while paused.
	if mode != "working":
		super.advance(dt)

func _drop(amount: float, t: float) -> void:
	var down: float = amount * float(manifest.mechanism.drop_distance)
	var lock := smoothstep(0.0, at("clamp_seconds", 0.26), t)
	for part in parts:
		var role := group(part)
		if role == "saw":
			part.mesh.transform = around(socket("saw_axis"), Vector3.BACK, t * TAU * 2.0) * part.target
		if role in ["drop", "saw"]:
			part.mesh.position.y -= down
		if role.begins_with("clamp_"):
			part.mesh.position.x -= float(role.trim_prefix("clamp_")) * CLAMP_TRAVEL * lock

func _press(t: float) -> void:
	# Down onto the floor, a short hold, then back up (so the executor's saws can come in).
	var down: float = smoothstep(at("press_at"), at("press_at") + at("press_seconds"), t) * PRESS_STROKE \
		* (1.0 - smoothstep(at("lift_at"), at("lift_at") + at("lift_seconds"), t))
	for part in parts:
		var role := group(part)
		if role == "platen":
			part.mesh.position.y -= down
		elif role == "platen_stage":
			part.mesh.position.y -= down * 0.5

func _cage(t: float) -> void:
	var closing := smoothstep(at("gate_at"), at("gate_at") + at("gate_seconds"), t)
	var feed := smoothstep(at("saw_at"), at("saw_at") + at("saw_seconds"), t)
	for part in parts:
		var role := group(part)
		if role.begins_with("gate_"):
			part.mesh.transform = around(socket(role), Vector3.UP, float(role.trim_prefix("gate_")) * GATE_OPEN * (1.0 - closing)) * part.mesh.transform
		elif role.begins_with("arm_") or role.begins_with("saw_"):
			var side := role.get_slice("_", 1)
			# The arms wait 0.08 rad outboard, clear of the platen, and swing in once it lifts.
			var arm := around(socket("arm_" + side), Vector3.UP, float(side) * (-0.08 + feed))
			var spin := around(socket(role), Vector3.BACK, maxf(0.0, t - at("saw_at") + 0.1) * TAU * 3.0) if role.begins_with("saw_") else Transform3D.IDENTITY
			part.mesh.transform = arm * spin * part.mesh.transform

func _winch(t: float, hooks: Array) -> void:
	# Hooks fly out to their targets, ride with them while they are reeled in, then come home.
	var out := smoothstep(0.0, at("fly_seconds"), t)
	var home := smoothstep(at("release_at"), at("release_at") + 0.2, t)
	if cables.is_empty():
		for i in 3:
			var line := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.009; mesh.bottom_radius = 0.009; mesh.height = 1.0
			mesh.radial_segments = 8; mesh.rings = 1
			line.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("59696a"); material.metallic = 0.65; material.roughness = 0.5
			line.material_override = material
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(line)
			cables.append(line)
	var reach := 0.0
	for i in 3:
		var used := i < hooks.size()
		var rest := socket("hook_%d" % i)
		var tip := rest
		if used:
			var aim: Vector3 = to_local(hooks[i]) + Vector3.UP * 0.6
			tip = rest.lerp(aim, out * (1.0 - home))
			reach = maxf(reach, rest.distance_to(tip))
		for part in parts:
			if group(part) == "hook_%d" % i:
				part.mesh.visible = used or i == 0
				part.mesh.position += tip - rest
		var from := socket("cable_%d" % i)
		var span := tip - from
		cables[i].visible = used and span.length() > 0.05
		if cables[i].visible:
			var turn := Basis(Quaternion(Vector3.UP, span.normalized()))
			cables[i].transform = Transform3D(turn.scaled_local(Vector3(1, span.length(), 1)), (from + tip) * 0.5)
	for part in parts:
		if group(part) == "drum":
			part.mesh.transform = around(socket("drum_axis"), Vector3.RIGHT, -reach / 0.17) * part.target

func debug_state() -> Dictionary:
	var state := super.debug_state()
	state.merge({"device": device})
	return state
