extends SceneTree
const Player = preload("res://scripts/player_visual.gd")
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func arr(v: Vector3) -> Array: return [v.x,v.y,v.z]

func pose(v: Node3D) -> Dictionary:
	var sk: Skeleton3D=v.runtime.skeleton
	var hand: Transform3D=sk.get_bone_global_pose(sk.find_bone("DEF-hand.R"))
	var staff: Transform3D=hand*Transform3D(v.STAFF_GRIP_BASIS,v.STAFF_GRIP_OFFSET+v.STAFF_GRIP_BASIS.y*v.staff_slide)
	var row := {"tip":arr(staff*Vector3(0,.828,0)),"axis":arr(staff.basis.y),"grip":arr(staff.origin),"weight":v._run_weight,"run_time":v._run_time,"idle_time":v._idle_time}
	for side in ["R","L"]:
		for name in ["upper_arm","forearm","hand"]:
			row[name+"."+side]=arr(sk.get_bone_global_pose(sk.find_bone("DEF-"+name+"."+side)).origin)
	return row

func run() -> void:
	var v=Player.new();root.add_child(v)
	if not v.initialize():push_error(v.last_error);quit(1);return
	var result := {"clips":{},"fixed_blend":[],"start":[],"bones":[]}
	var sk: Skeleton3D=v.runtime.skeleton
	v._sample("idle",0.)
	var idle:Array=[]
	for b in sk.get_bone_count(): idle.append([sk.get_bone_pose_rotation(b),sk.get_bone_global_pose(b),sk.get_bone_pose_position(b)])
	v._sample("run",0.)
	for b in sk.get_bone_count():
		var name:=sk.get_bone_name(b)
		if "upper_arm" not in name and "forearm" not in name and "hand." not in name: continue
		result.bones.append({"name":name,"parent":sk.get_bone_name(sk.get_bone_parent(b)),"local_angle":rad_to_deg(idle[b][0].angle_to(sk.get_bone_pose_rotation(b))),"global_angle":rad_to_deg(idle[b][1].basis.get_rotation_quaternion().angle_to(sk.get_bone_global_pose(b).basis.get_rotation_quaternion())),"idle_pos":arr(idle[b][1].origin),"run_pos":arr(sk.get_bone_global_pose(b).origin),"idle_local_pos":arr(idle[b][2]),"run_local_pos":arr(sk.get_bone_pose_position(b))})
	for kind in ["idle","run"]:
		var rows:Array=[]
		for i in 25:
			v._sample(kind,float(i)/24.0*v._length(kind));rows.append(pose(v))
		result.clips[kind]=rows
	v._idle_time=0.;v._run_time=0.;v._state="run"
	for i in 21:
		v._run_weight=i/20.0;v._sample_locomotion(i/20.0);result.fixed_blend.append(pose(v))
	v._run_weight=0.;v._state="idle";v._run_time=0.;v._idle_time=0.;v._sample("idle",0.)
	result.start.append(pose(v))
	for i in 60:
		v.sync_state(1./60.,true,0.,false,false,false,4.0);result.start.append(pose(v))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("RUN_ENTRY_PROBE_COMPLETE")
	v.free();quit(0)
