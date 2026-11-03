extends "res://tests/helpers/exoskeleton_v3.gd"
## Fitted review derivative: stable shoulder swing, rigid upper slides, fitted cuffs.
const V4_DIR:="res://assets/equipment/exoskeleton_v4/"
var upper_lengths:Dictionary={}
var clearance_curves:Dictionary={}
var motion_name:=""
var motion_phase:=0.0
func initialize(character:Skeleton3D)->bool:
	body=character
	manifest=JSON.parse_string(FileAccess.get_file_as_string(V4_DIR+"parts.json"))
	if not FileAccess.file_exists(V4_DIR+"clearance_curves.json"):
		push_error("Exoskeleton v4 requires its fitted motion curves");return false
	var decoded:Variant=JSON.parse_string(FileAccess.get_file_as_string(V4_DIR+"clearance_curves.json"))
	if not decoded is Dictionary:return false
	clearance_curves=decoded
	var packed:PackedScene=load(V4_DIR+"exoskeleton_v4.glb")
	var asset:=packed.instantiate();add_child(asset);rig=find_rig(asset)
	if rig==null:return false
	for role in manifest.mechanism_rest_godot:rest[role]=matrix(manifest.mechanism_rest_godot[role])
	for i in body.get_bone_count():body_rest[body.get_bone_name(i)]=body.get_bone_global_rest(i)
	return true
func fit_form(player:Node3D,form:String)->bool:
	if not player.set_form(form):return false
	var part:Dictionary=player.PARTS.outfit.duplicate(true)
	part.asset=V4_DIR+"outfit_"+form+"_fit_v4.glb"
	var ok:bool=player.replace_parts({"outfit":part})
	if not ok:push_error("Exoskeleton fitted outfit: "+player.last_error)
	return ok
func sync_pose_for_motion(motion:String,phase:float)->void:
	motion_name=motion;motion_phase=clampf(phase,0,1);sync_pose()
func arm_corrective(side:String)->Dictionary:
	var zero:Dictionary={"angle":0.0,"shift":[0.0,0.0,0.0]}
	if not clearance_curves.has(motion_name):return zero
	var keys:Array=clearance_curves[motion_name][side]
	for i in range(1,keys.size()):
		if motion_phase>float(keys[i].phase):continue
		var a:Dictionary=keys[i-1];var b:Dictionary=keys[i]
		var t:float=clampf((motion_phase-float(a.phase))/maxf(float(b.phase)-float(a.phase),.00001),0,1)
		return {"angle":lerpf(float(a.angle),float(b.angle),t),"shift":[lerpf(a.shift[0],b.shift[0],t),lerpf(a.shift[1],b.shift[1],t),lerpf(a.shift[2],b.shift[2],t)]}
	return keys[-1] if not keys.is_empty() else zero
func sync_pose()->void:
	var cfg:Dictionary=manifest.config
	var chest:Transform3D=bone("DEF-chest")*body_rest["DEF-chest"].affine_inverse()
	var poses:Dictionary={}
	for role in ["back_power","back_link_L","back_link_R"]:poses[role]=chest*rest[role]
	for side in ["L","R"]:
		var sign_value:=1.0 if side=="L" else -1.0
		var upper:String="DEF-upper_arm."+side;var fore:String="DEF-forearm."+side;var shin:String="DEF-shin."+side
		var s:=bone(upper).origin;var e:=bone(fore).origin;var w:=bone("DEF-hand."+side).origin
		var n:=(s-e).normalized().cross((w-e).normalized())*sign_value
		if n.length()<.08:n=(bone(upper)*body_rest[upper].affine_inverse()).basis*vec(manifest.anchors[side].hinge_rest)
		n=n.normalized()
		var corrective:=arm_corrective(side)
		n=Quaternion((w-e).normalized(),deg_to_rad(float(corrective.angle)))*n
		var a:Array=corrective.shift
		var shift:Vector3=chest.basis*Vector3(a[0],a[1],a[2])
		var ee:Vector3=e+n*cfg.arm_offset_elbow+shift;var ww:Vector3=w+n*cfg.arm_offset_wrist+shift
		var ry:Vector3=(body_rest[fore].origin-body_rest[upper].origin).normalized();ry=chest.basis*ry
		var swing:=Quaternion.IDENTITY.slerp(Quaternion(ry.normalized(),(e-s).normalized()),float(cfg.shoulder_swing_weight))
		var offset:=vec([sign_value*cfg.shoulder_offset[0],cfg.shoulder_offset[1],cfg.shoulder_offset[2]])
		var ss:Vector3=s+swing*(chest.basis*offset)
		poses["shoulder_"+side]=frame(ss,swing*ry,swing*(chest.basis*Vector3(sign_value,0,0)))
		var upper_frame:=frame(ss,ee-ss,n);var upper_axis:=upper_frame.basis.y;var upper_length:=ss.distance_to(ee);upper_lengths[side]=upper_length
		poses["upper_"+side]=upper_frame;poses["upper_prox_"+side]=upper_frame
		var distal:=upper_frame;distal.origin+=upper_axis*(upper_length-float(manifest.anchors[side].upper_length));poses["upper_dist_"+side]=distal
		var slide:Dictionary=manifest.upper_slide[side]
		var slide_start:=ss+upper_axis*float(slide.start_offset);var travel:=upper_length-float(slide.start_offset)-float(slide.end_offset)
		for i in int(slide.segments):poses["upper_slide_%s_%d"%[side,i]]=frame(slide_start+upper_axis*(travel-float(slide.segment_length))*i/(int(slide.segments)-1.0),upper_axis,n)
		for role in ["elbow_","forearm_","wrist_"]:poses[role+side]=frame(ee,ww-ee,n)
		var leg:Transform3D=bone(shin)*body_rest[shin].affine_inverse()
		for role in ["knee_","shin_","calf_cuff_upper_","calf_cuff_lower_"]:poses[role+side]=leg*rest[role+side]
		var spec:Dictionary=manifest.bridge[side]
		var start:Vector3=chest*vec(spec.start);var axis:Vector3=(ss-start).normalized();var length:=start.distance_to(ss);bridge_lengths[side]=length
		for i in int(spec.segments):poses["bridge_%s_%d"%[side,i]]=frame(start+axis*(length-float(spec.segment_length))*i/(int(spec.segments)-1.0),axis,chest.basis*Vector3.UP)
		poses["mount_"+side]=chest*rest["mount_"+side]
	for role in poses:
		var i:=rig.find_bone("EXO-"+role)
		if i<0:continue # upper_* are mechanism frames; only rigid sections deform meshes.
		var movement:Transform3D=poses[role]*rest[role].affine_inverse()
		rig.set_bone_global_pose(i,movement*rig.get_bone_global_rest(i))
	current_frames=poses
