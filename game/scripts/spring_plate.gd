extends "res://scripts/summon_assembly.gd"
## Ground-anchored cosmetic mechanism. The arena still owns every dash rule and clock.
const PARTS = preload("res://assets/props/spring_dash_v1/spring_plate.glb")
const DATA_PATH := "res://assets/props/spring_dash_v1/parts.json"
var spec: Dictionary
var roles: Dictionary = {}
var lift := 0.0
var launch_count := 0
var launch_origin := Vector3.ZERO
var _coil_mesh: ArrayMesh
var _coil_height := -1.0

func _init() -> void:
	parts_scene=PARTS;assembly_name="SpringPlate"
	effect_radius=.36;effect_height=.18
	spec=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	for record in spec.parts:
		part_delays[record.name]=float(record.delay)
		roles[record.name]=record.role

func initialize(arena: Node3D) -> void:
	# One short mechanical strike at launch, through the game's existing mute/volume pool.
	_clink_played=true
	super.initialize(arena)
	add_to_group("spring_plates")
	_ring.visible=false # The existing drive cast circle already supplies the floor symbol.
	for part in parts:
		part.start=part.target.origin+part.outward*.19+Vector3.UP*(.04+.02*(parts.find(part)%3))
		part.start_basis=Basis(part.axis,.28)*part.target.basis
		if roles[part.name]=="coil":
			for material in part.materials:material.cull_mode=BaseMaterial3D.CULL_DISABLED
	sample_progress(0.)

func sample_progress(value: float) -> void:
	if mode!="assembling":return
	super.sample_progress(value)
	lift=.045*(1.-smoothstep(.35,.90,progress))
	for part in parts:
		var arrival:=smoothstep(.08,1.,clampf((progress-float(part.delay))/.40,0.,1.))
		if roles[part.name] in ["deck","guide_top"]:part.mesh.position.y+=lift*arrival
		elif roles[part.name]=="guide_mid":part.mesh.position.y+=lift*arrival*.5
	_update_coils(float(spec.coil.closed_height)+lift)

func launch(direction: Vector3) -> void:
	if mode!="assembling":return
	if direction.length_squared()>.000001:look_at(global_position+direction,Vector3.UP)
	sample_progress(1.)
	mode="launched";_end_time=0.;launch_count=1;launch_origin=global_position
	_arena.play_sfx("spring_dash",1.65)
	_sample_launch(0.)

func _sample_launch(seconds: float) -> void:
	var extension:=smoothstep(0.,float(spec.launch_seconds),seconds)
	lift=(float(spec.coil.open_height)-float(spec.coil.closed_height))*extension
	var tilt:=deg_to_rad(-9.)*extension
	var pivot:=Vector3(0,float(spec.deck_pivot[1]),0)
	var carriage:=Transform3D(Basis(Vector3.RIGHT,tilt),pivot+Vector3.UP*lift)*Transform3D(Basis.IDENTITY,-pivot)
	var fading:=smoothstep(float(spec.launch_seconds)+float(spec.hold_seconds),_lifetime(),seconds)
	for part in parts:
		part.mesh.transform=part.target
		match str(roles[part.name]):
			"deck":part.mesh.transform=carriage*part.target
			"guide_mid":part.mesh.position.y+=lift*.5
			"guide_top":part.mesh.position.y+=lift
			"latch":
				var sign_x:=signf(part.target.origin.x)
				part.mesh.basis=Basis(Vector3.FORWARD,sign_x*deg_to_rad(38.)*extension)*part.target.basis
		part.mesh.position+=part.outward*fading*.075+Vector3.UP*fading*.055
		_opacity(part,1.-fading,fading*.20)
	_update_coils(float(spec.coil.closed_height)+lift)
	_light(1.,(1.-fading)*(.65-.25*extension))
	_ring.visible=false

func _lifetime() -> float:
	return float(spec.launch_seconds)+float(spec.hold_seconds)+float(spec.dissolve_seconds)

func cancel(reason: String="interrupted") -> void:
	if mode!="assembling":return
	mode="cancelled";cancel_reason=reason;_end_time=0.
	for part in parts:part["cancel_transform"]=part.mesh.transform

func advance(dt: float) -> void:
	if mode=="assembling" or (is_instance_valid(_arena) and _arena.paused):return
	_end_time+=maxf(dt,0.)
	if mode=="launched":
		_sample_launch(_end_time)
		if _end_time>=_lifetime():queue_free()
	elif mode=="cancelled":
		var fade:=1.-smoothstep(0.,.20,_end_time)
		for part in parts:
			if not part.mesh.visible:continue
			part.mesh.transform=part.cancel_transform
			part.mesh.position+=part.outward*(1.-fade)*.07
			_opacity(part,float(part.opacity)*fade,(1.-fade)*.5)
		_light(progress,fade*.45);_ring.visible=false
		if _end_time>=.22:queue_free()

func _update_coils(height: float) -> void:
	if absf(height-_coil_height)<.00001:return
	_coil_height=height
	var cfg:Dictionary=spec.coil
	var steps:int=int(cfg.steps);var sides:int=int(cfg.sides)
	var radius:float=float(cfg.radius);var wire:float=float(cfg.wire_radius)
	var turns:float=float(cfg.turns)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var indices:=PackedInt32Array()
	for i in steps+1:
		var angle:=TAU*turns*float(i)/steps
		var radial:=Vector3(cos(angle),0,sin(angle))
		var tangent:=Vector3(-radius*sin(angle),height/(TAU*turns),radius*cos(angle)).normalized()
		var cross:=tangent.cross(radial).normalized()
		var center:=radial*radius+Vector3.UP*height*float(i)/steps
		for j in sides:
			var phase:=TAU*j/sides
			var normal:=radial*cos(phase)+cross*sin(phase)
			vertices.append(center+normal*wire);normals.append(normal)
	for i in steps:
		for j in sides:
			var a:=i*sides+j;var b:=i*sides+(j+1)%sides
			indices.append_array([a,a+sides,b,b,a+sides,b+sides])
	for end in 2:
		var angle:=TAU*turns*end
		vertices.append(Vector3(cos(angle)*radius,height*end,sin(angle)*radius))
		normals.append(Vector3(-radius*sin(angle),height/(TAU*turns),radius*cos(angle)).normalized()*(1. if end==1 else -1.))
		for j in sides:
			var a:=end*steps*sides+j;var b:=end*steps*sides+(j+1)%sides
			indices.append_array([vertices.size()-1,a,b] if end==0 else [vertices.size()-1,b,a])
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	_coil_mesh=ArrayMesh.new();_coil_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for part in parts:
		if roles[part.name]=="coil":
			part.mesh.mesh=_coil_mesh
			part.mesh.set_surface_override_material(0,part.materials[0])

func debug_state() -> Dictionary:
	var state:=super.debug_state()
	state.merge({"lift":lift,"coil_height":_coil_height,"wire_radius":float(spec.coil.wire_radius),"launch_count":launch_count,"launch_origin":launch_origin,"lifetime":_lifetime()})
	return state
