extends "res://scripts/summon_assembly.gd"
## Smoke launcher (firearm III): the six-tube launcher assembles on the floor at the witch's right
## during the cast, then lobs its canisters onto the aimed area and comes apart. The canisters lie
## in the smoke until it clears. Arena owns the smoke zone and what it hides; this only draws it.
const MODEL = preload("res://assets/weapons/firearm_material_v4/smoke_launcher.glb")
const DATA = "res://assets/weapons/firearm_material_v4/smoke_launcher.json"
# Each tube fires this long after the one before it.
const STAGGER := 0.06
const ARC := 1.6
var _canister: Dictionary = {}
var _flight := 0.45
var _linger := 6.0
var _landings: Array[Vector3] = []

func _init() -> void:
	assembly_name = "SmokeLauncher"
	effect_radius = 0.42; effect_height = 0.6
	parts_scene = MODEL
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for part in data.parts:
		part_delays[part.name] = float(part.delay)
		if str(part.group).begins_with("canister_"):
			_canister[part.name] = int(str(part.group).trim_prefix("canister_"))

func fire(landings: Array[Vector3], flight: float, linger: float) -> void:
	# landings: one floor point per tube, in world space. The launcher stays where it stood.
	if mode != "assembling": return
	sample_progress(1.0)
	mode = "fired"
	_end_time = 0.0
	_flight = flight
	_linger = linger
	_landings.clear()
	for point in landings: _landings.append(to_local(point))
	for part in parts:
		part.mesh.visible = true
		part.mesh.transform = part.target
		_opacity(part, 1.0, 0.0)

func advance(dt: float) -> void:
	if mode != "fired":
		super.advance(dt)
		return
	if is_instance_valid(_arena) and _arena.paused: return
	_end_time += dt
	var t := _end_time
	_light(1.0, maxf(0.0, 1.0 - t / 0.2))
	for part in parts:
		if not _canister.has(part.name):
			# The launcher itself comes apart once its tubes are empty.
			var gone := smoothstep(0.35, 0.7, t)
			part.mesh.transform = part.target
			part.mesh.position += part.outward * gone * 0.1 + Vector3.UP * gone * 0.06
			_opacity(part, 1.0 - gone, gone * 0.6)
			continue
		var index: int = _canister[part.name]
		var flown := clampf((t - index * STAGGER) / _flight, 0.0, 1.0)
		var land: Vector3 = _landings[mini(index, _landings.size() - 1)] + Vector3.UP * 0.06
		if flown < 1.0:
			# Lobbed in an arc, tumbling.
			part.mesh.position = (part.target.origin as Vector3).lerp(land, flown) + Vector3.UP * ARC * 4.0 * flown * (1.0 - flown)
			part.mesh.basis = Basis(part.axis, flown * TAU) * part.target.basis
		else:
			# Down on its side in the smoke; the cap has blown off as it vents.
			part.mesh.position = land
			part.mesh.basis = Basis(Vector3.RIGHT, PI / 2) * part.target.basis
			if str(part.name).contains("cap"): part.mesh.visible = false
		_opacity(part, 1.0 - smoothstep(_linger + _flight - 0.6, _linger + _flight, t), 0.0)
	if t >= _linger + _flight: queue_free()

func debug_state() -> Dictionary:
	var state := super.debug_state()
	state.merge({"canisters": _canister.size()})
	return state
