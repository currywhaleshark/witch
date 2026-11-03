extends "res://scripts/floating_gun.gd"
## Rotary cannon (firearm III): assembles during the spin-up cast, then floats ahead of the witch's
## right hip while she channels, its six-barrel rotor turning with the stream of shots. Arena owns
## aim, shots, damage and mana.
const MODEL = preload("res://assets/weapons/firearm_material_v4/gatling.glb")
const DATA = "res://assets/weapons/firearm_material_v4/gatling.json"
# Full rotor speed, in turns per second; it spins up from rest over SPIN_UP seconds.
const TURNS := 3.0
const SPIN_UP := 0.35
var rotor: Dictionary = {}
var spin := 0.0
var _speed := 0.0

func configure(_id: String) -> void:
	gun_id = "gatling"
	parts_scene = MODEL
	# The 1.2m cannon runs back from its muzzle, so the muzzle sits further ahead and lower.
	mount = Vector3(0.55, 1.0, 1.0)
	part_delays.clear()
	rotor.clear()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	for part in data.parts:
		part_delays[part.name] = float(part.delay)
		if part.group == "rotor":
			rotor[part.name] = true

func _init() -> void:
	# The floating gun's constructor calls configure, which resolves to the cannon's above.
	super._init()
	assembly_name = "GatlingGun"

func shoot(target: Vector3) -> void:
	super.shoot(target)
	# A light shudder per round instead of a matchlock's full recoil.
	_kick = 0.45

func advance(dt: float) -> void:
	super.advance(dt)
	if mode != "ready" or (is_instance_valid(_arena) and _arena.paused): return
	# The rotor turns about the barrels' common axis (local Z through the muzzle).
	_speed = minf(1.0, _speed + dt / SPIN_UP)
	spin = fposmod(spin + _speed * TURNS * TAU * dt, TAU)
	var turn := Transform3D(Basis(Vector3.BACK, spin), Vector3.ZERO)
	for part in parts:
		if rotor.has(part.name):
			part.mesh.transform = turn * part.mesh.transform

func debug_state() -> Dictionary:
	var state := super.debug_state()
	state.merge({"spin": spin, "spin_speed": _speed})
	return state
