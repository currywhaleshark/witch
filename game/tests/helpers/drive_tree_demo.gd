extends "res://scripts/summon_assembly.gd"
## Prepared-asset presentation examples. No active skill, damage, input or collision rules.
var asset_id := ""
var manifest: Dictionary
var info: Dictionary = {}
var winch_mode := "single"
var skeleton: Skeleton3D
var cables: Array[MeshInstance3D] = []

func configure(id: String) -> void:
	asset_id=id
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/drive_tree_v1/%s.json"%id))
	parts_scene=load("res://assets/weapons/drive_tree_v1/%s.glb"%id)
	assembly_name="DriveReview_"+id
	effect_radius=.65;effect_height=1.1
	for p in manifest.parts:part_delays[p.name]=float(p.delay);info[p.name]=p

func point(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func socket(key: String) -> Vector3:
	return point(manifest.sockets["Socket_"+key].position)

func around(p: Vector3,axis: Vector3,angle: float) -> Transform3D:
	var b:=Basis(axis,angle)
	return Transform3D(b,p-b*p)

func _light(phase: float,strength: float) -> void:
	super._light(phase,strength)
	_ring.visible=strength>.001;_core.visible=strength>.001
	for mote in _motes:mote.visible=strength>.001

func add_cables() -> void:
	for i in 3:
		var line:=MeshInstance3D.new();var mesh:=CylinderMesh.new()
		mesh.top_radius=.009;mesh.bottom_radius=.009;mesh.height=1;mesh.radial_segments=8;mesh.rings=1
		line.mesh=mesh;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("59696a");mat.metallic=.65;mat.roughness=.5;line.material_override=mat
		add_child(line);cables.append(line)

func sample_demo(seconds: float) -> void:
	mode="assembling";sample_progress(clampf(seconds/.65,0,1))
	if seconds<.65:
		if is_instance_valid(skeleton):
			for part in parts:
				var bone:=skeleton.find_bone(info[part.name].attach_bone)
				assert(bone>=0,"Missing equipment attachment bone")
				part.mesh.transform=skeleton.get_bone_global_pose(bone)*skeleton.get_bone_global_rest(bone).affine_inverse()*part.mesh.transform
		for c in cables:c.visible=false
		return
	_light(1,0)
	for part in parts:
		part.mesh.transform=part.target
		if info[part.name].surface=="core":_opacity(part,1,1)
	if asset_id.begins_with("guillotine"):
		var down:=smoothstep(1.0,1.24,seconds)*1.02
		if asset_id=="guillotine_saw":down=smoothstep(1.0,2.5,seconds)*.72
		for part in parts:
			var group:String=info[part.name].group
			if group=="drop" or group=="saw":part.mesh.position.y-=down
			if group=="saw":
				part.mesh.transform=around(socket("saw_axis"),Vector3.BACK,(seconds-.65)*TAU*2)*part.target
				part.mesh.position.y-=down
			if group.begins_with("clamp_"):part.mesh.position.x-=float(group.trim_prefix("clamp_"))*.16*smoothstep(.7,.95,seconds)
	elif asset_id in ["hydraulic_press","compound_executor"]:
		var down:=smoothstep(1.1,1.45,seconds)*.88
		for part in parts:
			var group:String=info[part.name].group
			if group=="platen":part.mesh.position.y-=down
			if group=="platen_stage":part.mesh.position.y-=down*.5
			if asset_id!="compound_executor":continue
			if group.begins_with("gate_"):
				var side:=float(group.trim_prefix("gate_"));part.mesh.transform=around(socket(group),Vector3.UP,side*1.35*(1-smoothstep(.70,1.05,seconds)))*part.target
			if group.begins_with("arm_") or group.begins_with("saw_"):
				var side:=group.get_slice("_",1);var arm:=around(socket("arm_"+side),Vector3.UP,float(side)*.92*smoothstep(1.65,2.15,seconds))
				var spin:=Transform3D.IDENTITY
				if group.begins_with("saw_"):spin=around(socket(group),Vector3.BACK,maxf(0,seconds-1.45)*TAU*3)
				part.mesh.transform=arm*spin*part.target
	elif asset_id=="restraint_winch":
		if cables.is_empty():add_cables()
		var deploy:=smoothstep(.70,1.12,seconds)
		var retract:=smoothstep(1.35,2.3,seconds) if winch_mode!="bind" else 0.0
		var extension:=1.6*deploy*(1-.78*retract)
		for part in parts:
			var group:String=info[part.name].group
			if group=="drum":part.mesh.transform=around(socket("drum_axis"),Vector3.RIGHT,-extension/.17)*part.target
			if group.begins_with("cable_"):part.mesh.visible=false
			if group.begins_with("hook_"):
				var i:=int(group.trim_prefix("hook_"));part.mesh.visible=i==0 or winch_mode!="single"
				part.mesh.position+=Vector3((i-1)*.45*deploy if i>0 else 0,0,-extension)
		for i in 3:
			var a:=socket("cable_%s"%i);var b:=socket("hook_%s"%i)+Vector3((i-1)*.45*deploy if i>0 else 0,0,-extension)
			var direction:=b-a;var basis:=Basis(Quaternion(Vector3.UP,direction.normalized()))
			cables[i].transform=Transform3D(basis.scaled_local(Vector3(1,direction.length(),1)),(a+b)*.5)
			cables[i].visible=i==0 or winch_mode!="single"
	elif asset_id=="broad_cutter":
		var opening:=.63*(1-smoothstep(1.18,1.29,seconds))+.12*smoothstep(1.75,2.05,seconds)
		for part in parts:
			var group:String=info[part.name].group
			if group.begins_with("jaw_"):part.mesh.transform=around(socket(group),Vector3.BACK,-float(group.trim_prefix("jaw_"))*opening)*part.target
			if group.begins_with("link_"):
				var side:=float(group.trim_prefix("link_"));var j:=socket("jaw_%s"%int(side));var old_end:=socket("jaw_pin_%s"%int(side));var old_start:=Vector3(side*.04,.77,-.09)
				var end:=around(j,Vector3.BACK,-side*opening)*old_end
				var length:=old_end.distance_to(old_start);var start:=Vector3(side*.04,end.y-sqrt(maxf(.00001,length*length-pow(end.x-side*.04,2))),-.09)
				var basis:=Basis(Quaternion((old_end-old_start).normalized(),(end-start).normalized()))
				part.mesh.transform=Transform3D(basis,start-basis*old_start)*part.target
	elif is_instance_valid(skeleton):
		for part in parts:
			var bone:=skeleton.find_bone(info[part.name].attach_bone)
			part.mesh.transform=skeleton.get_bone_global_pose(bone)*skeleton.get_bone_global_rest(bone).affine_inverse()*part.target
	if seconds>2.85:
		var fade:=smoothstep(2.85,3.35,seconds)
		for part in parts:
			part.mesh.position+=part.outward*fade*.16+Vector3.UP*fade*.18
			_opacity(part,1-fade,fade*.3)
		for c in cables:c.visible=seconds<3.2
