extends "res://tests/helpers/drive_tree_demo.gd"
## Revised review timing. No gameplay target, resource or damage ownership.
const END_ASSEMBLY := .65
const LOCK_CLOSE_START := .30
const LOCK_CLOSED := .56
const LOCK_FRAME_START := .60
const LOCK_FRAME_END := 1.25

func configure(id: String) -> void:
	if not id.begins_with("guillotine"):
		super.configure(id)
		return
	asset_id=id
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/drive_tree_v2/%s.json"%id))
	parts_scene=load("res://assets/weapons/drive_tree_v2/%s.glb"%id)
	assembly_name="DriveV2Review_"+id;effect_radius=.65;effect_height=1.1
	for p in manifest.parts:part_delays[p.name]=float(p.delay);info[p.name]=p

func sample_demo(seconds: float) -> void:
	if not asset_id.begins_with("guillotine") and asset_id!="compound_executor":
		super.sample_demo(seconds)
		return
	mode="assembling"
	var lock_first:=asset_id=="guillotine_lock"
	var assembling_end:=LOCK_FRAME_END if lock_first else END_ASSEMBLY
	var lock_amount:=smoothstep(LOCK_CLOSE_START,LOCK_CLOSED,seconds) if lock_first else 0.0
	if lock_first:
		# Clamp pieces have their own first assembly; all frame pieces remain absent.
		sample_progress(clampf(seconds/.28,0,1) if seconds<LOCK_FRAME_START else clampf((seconds-LOCK_FRAME_START)/.65,0,1))
		for part in parts:
			var clamp:bool=info[part.name].group.begins_with("clamp_")
			if clamp and seconds>=.28:
				part.mesh.visible=true;part.mesh.transform=part.target;_opacity(part,1,0)
			if clamp:
				part.mesh.position.x-=float(info[part.name].group.trim_prefix("clamp_"))*.16*lock_amount
			elif seconds<LOCK_FRAME_START:
				part.mesh.visible=false
	else:
		sample_progress(clampf(seconds/END_ASSEMBLY,0,1))
	if seconds<assembling_end and asset_id!="compound_executor":return
	if seconds>=assembling_end:
		_light(1,0)
		for part in parts:
			part.mesh.transform=part.target
			if info[part.name].surface=="core":_opacity(part,1,1)
	if asset_id.begins_with("guillotine"):
		var start:=1.40 if lock_first else 1.0
		var end:=1.64 if lock_first else 1.24
		if asset_id=="guillotine_saw":end=2.50
		var down:=smoothstep(start,end,seconds)*float(manifest.mechanism.drop_distance)
		for part in parts:
			var group:String=info[part.name].group
			if group=="saw":part.mesh.transform=around(socket("saw_axis"),Vector3.BACK,(seconds-.65)*TAU*2)*part.target
			if group in ["drop","saw"]:part.mesh.position.y-=down
			if group.begins_with("clamp_"):part.mesh.position.x-=float(group.trim_prefix("clamp_"))*.16*lock_amount
	else:
		# Hold the compression, lift the platen, then feed the saw arms in as it clears them.
		var down:=smoothstep(1.1,1.45,seconds)*.88*(1-smoothstep(1.55,2.10,seconds))
		for part in parts:
			var group:String=info[part.name].group
			if group=="platen":part.mesh.position.y-=down
			if group=="platen_stage":part.mesh.position.y-=down*.5
			if group.begins_with("gate_"):
				var side:=float(group.trim_prefix("gate_"))
				part.mesh.transform=around(socket(group),Vector3.UP,side*1.35*(1-smoothstep(.70,1.05,seconds)))*part.mesh.transform
			if group.begins_with("arm_") or group.begins_with("saw_"):
				var side:=group.get_slice("_",1)
				# Park 0.08 rad outboard to clear the descending platen's outer edge.
				var arm:=around(socket("arm_"+side),Vector3.UP,float(side)*(-.08+smoothstep(1.92,2.45,seconds)))
				var spin:=around(socket(group),Vector3.BACK,maxf(0,seconds-1.85)*TAU*3) if group.begins_with("saw_") else Transform3D.IDENTITY
				part.mesh.transform=arm*spin*part.mesh.transform
	if seconds>2.85:
		var fade:=smoothstep(2.85,3.35,seconds)
		for part in parts:
			part.mesh.position+=part.outward*fade*.16+Vector3.UP*fade*.18
			_opacity(part,1-fade,fade*.3)
