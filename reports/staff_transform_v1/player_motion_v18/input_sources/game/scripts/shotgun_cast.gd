extends "res://scripts/summon_assembly.gd"
## Transient floating cannon. Arena owns release, cone damage and resource use.
const PARTS = preload("res://assets/actors/shotgun_cast_v1/shotgun_parts.glb")
var _flash: MeshInstance3D
var _fired_origin := Vector3.ZERO
var _fired_direction := Vector3.FORWARD

func _init() -> void:
	parts_scene=PARTS; assembly_name="ShotgunCast"
	effect_radius=0.35; effect_height=0.25
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/shotgun_cast_v1/parts.json"))
	for part in data.parts: part_delays[part.name]=float(part.delay)

func initialize(arena: Node3D) -> void:
	super.initialize(arena)
	_ring.position=Vector3(0,-0.10,0.32)
	_core.position=Vector3(0,0.02,0.32)
	_flash=_glow(0.32); _flash.position=Vector3(0,0,-0.035)
	var material: StandardMaterial3D=_flash.material_override
	var texture: GradientTexture2D=material.albedo_texture
	texture.gradient.colors=PackedColorArray([Color(1,0.98,0.8,1),Color(1,0.67,0.18,0.8),Color(1,0.34,0.03,0.15),Color(0,0,0,0)])
	material.albedo_color=Color(1,1,1,0)
	_flash.visible=false

func _light(phase: float, strength: float) -> void:
	super._light(phase,strength)
	for mote in _motes: mote.position.z+=0.3

func fire(frame: Transform3D) -> void:
	if mode!="assembling": return
	global_transform=frame
	sample_progress(1.0)
	mode="fired"; _end_time=0.0
	_fired_origin=global_position; _fired_direction=-global_basis.z
	_flash.visible=true
	_flash.material_override.albedo_color.a=1.0

func cancel(reason: String="interrupted") -> void:
	if mode!="assembling": return
	mode="dissolving"; cancel_reason=reason; _end_time=0.0
	# Incomplete airborne machinery unravels from the current pose; no shot is emitted.
	for part in parts: part["cancel_transform"]=part.mesh.transform

func advance(dt: float) -> void:
	if mode=="assembling" or (is_instance_valid(_arena) and _arena.paused): return
	_end_time+=dt
	var fired := mode=="fired"
	var fade := 1.0-smoothstep(0.12 if fired else 0.0,0.43 if fired else 0.30,_end_time)
	for part in parts:
		if not part.mesh.visible: continue
		var rest: Transform3D=part.target if fired else part.cancel_transform
		part.mesh.transform=rest
		if fired:
			part.mesh.position.z+=0.075*sin(clampf(_end_time/0.16,0,1)*PI)
		part.mesh.position+=part.outward*smoothstep(0.12,0.43,_end_time)*0.09
		part.mesh.position.y+=smoothstep(0.12,0.43,_end_time)*0.10
		_opacity(part,fade*(1.0 if fired else float(part.opacity)),(1.0-fade)*0.7)
	_light(progress,fade*0.5)
	_flash.visible=fired and _end_time<0.085
	_flash.material_override.albedo_color.a=maxf(0.0,1.0-_end_time/0.085)
	if _end_time>=(0.45 if fired else 0.32): queue_free()

func debug_state() -> Dictionary:
	var state:=super.debug_state()
	state.merge({"fired_origin":_fired_origin,"fired_direction":_fired_direction,
		"flash":_flash!=null and _flash.visible})
	return state
