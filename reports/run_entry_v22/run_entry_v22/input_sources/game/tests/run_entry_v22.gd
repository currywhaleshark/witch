extends "res://tests/probe_run_entry_v22.gd"
var checks: Array = []
var failures: Array = []
var metrics := {"samples":0,"max_grip_error_m":0.,"max_arm_length_error_m":0.,"max_unaffected_local_error":0.,"max_endpoint_error":0.,"max_axis_x":-1.,"min_axis_y":1.,"max_timeline_difference":0.}

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label)

func baseline():
	var source:=GDScript.new()
	source.source_code=FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../reports/run_entry_v22/player_visual_before.gd"))
	assert(source.reload()==OK)
	var v=source.new();root.add_child(v);assert(v.initialize());return v

func matrix_error(a: Transform3D,b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin),maxf(a.basis.x.distance_to(b.basis.x),maxf(a.basis.y.distance_to(b.basis.y),a.basis.z.distance_to(b.basis.z))))

func measure(v,old) -> void:
	var sk:Skeleton3D=v.runtime.skeleton
	var osk:Skeleton3D=old.runtime.skeleton
	var helper=v._staff_locomotion_blend
	var rh:Transform3D=sk.get_bone_global_pose(sk.find_bone("DEF-hand.R"))
	var lh:Transform3D=sk.get_bone_global_pose(sk.find_bone("DEF-hand.L"))
	var frame:Transform3D=rh*Transform3D(v.STAFF_GRIP_BASIS,v.STAFF_GRIP_OFFSET)
	var expected:Vector3=frame.origin-frame.basis.y*.26
	metrics.max_grip_error_m=maxf(metrics.max_grip_error_m,expected.distance_to(lh*helper.LEFT_GRIP_OFFSET))
	metrics.max_axis_x=maxf(metrics.max_axis_x,frame.basis.y.x)
	metrics.min_axis_y=minf(metrics.min_axis_y,frame.basis.y.y)
	var arm_ids:Array=[]
	for arm in helper.arms:
		arm_ids.append_array(arm.bones)
		for start in [0,3]:
			var a:Vector3=sk.get_bone_global_pose(arm.bones[start]).origin
			var b:Vector3=sk.get_bone_global_pose(arm.bones[start+3]).origin
			metrics.max_arm_length_error_m=maxf(metrics.max_arm_length_error_m,absf(a.distance_to(b)-arm.lengths[start/3]))
	for b in sk.get_bone_count():
		if b not in arm_ids:
			metrics.max_unaffected_local_error=maxf(metrics.max_unaffected_local_error,matrix_error(sk.get_bone_pose(b),osk.get_bone_pose(b)))
	metrics.samples+=1

func run() -> void:
	var v=Player.new();root.add_child(v);check(v.initialize(),"current modular character loads")
	var old=baseline()
	var pure_error:=0.
	for kind in Player.CLIPS:
		for i in 17:
			v._sample(kind,i/16.*v._length(kind));old._sample(kind,i/16.*old._length(kind))
			for b in v.runtime.skeleton.get_bone_count():pure_error=maxf(pure_error,matrix_error(v.runtime.skeleton.get_bone_pose(b),old.runtime.skeleton.get_bone_pose(b)))
	check(pure_error==0.,"all seven authored clips retain identical sampled poses")
	for ip in [0.,.25,.50,.75]:
		for rp in 16:
			for weight in [0.,.00001,.05,.15,.3,.5,.7,.85,.95,.99999,1.]:
				for actor in [v,old]:
					actor._idle_time=ip*actor._length("idle");actor._run_time=rp/16.*actor._length("run");actor._state="run"
					actor._sample_locomotion(weight)
				measure(v,old)
				if weight==.00001 or weight==.99999:
					old._sample("idle" if weight<.5 else "run",old._idle_time if weight<.5 else old._run_time)
					for arm in v._staff_locomotion_blend.arms:
						for b in arm.bones:metrics.max_endpoint_error=maxf(metrics.max_endpoint_error,matrix_error(v.runtime.skeleton.get_bone_global_pose(b),old.runtime.skeleton.get_bone_global_pose(b)))
	for fps in [30,60]:
		for speed in [1.,4.,7.5]:
			for actor in [v,old]:
				actor._state="idle";actor._run_weight=0.;actor._idle_time=0.;actor._run_time=0.;actor._motion_kind=""
			for f in fps*3:
				var t:float=float(f)/fps
				var moving:bool=(t<.08 or (t>=.20 and t<.26) or (t>=.34 and t<1.5) or t>=1.60)
				for actor in [v,old]:
					actor.rotation.y=PI*.75 if t>=1.65 else 0.
					actor.sync_state(1./fps,moving,0.,false,false,false,speed if moving else 0.)
				measure(v,old)
				metrics.max_timeline_difference=maxf(metrics.max_timeline_difference,maxf(absf(v._run_time-old._run_time),maxf(absf(v._run_weight-old._run_weight),absf(v._turn_lag-old._turn_lag))))
			var before:Array=[]
			for b in v.runtime.skeleton.get_bone_count():before.append(v.runtime.skeleton.get_bone_pose(b))
			v.sync_state(.5,true,0.,true,false,false,speed)
			var frozen:=true
			for b in before.size():frozen=frozen and before[b]==v.runtime.skeleton.get_bone_pose(b)
			check(frozen,"pause retains exact pose at %d fps speed %.1f"%[fps,speed])
	check(metrics.max_axis_x<-.45 and metrics.min_axis_y>.50,"staff remains on its authored side and points upward throughout blends/restarts")
	check(metrics.max_grip_error_m<.00020,"both hands retain the 26cm grip spacing within 0.2mm")
	check(metrics.max_arm_length_error_m<.00010,"upper/lower arms keep their lengths within 0.1mm")
	check(metrics.max_unaffected_local_error<.000001,"all other local bone tracks, including cloth/fingers, preserve the original mix")
	check(metrics.max_endpoint_error<.001,"mixed arm poses meet the unchanged pure clips at both ends")
	check(metrics.max_timeline_difference==0.,"run phase, stride speed, blend duration and turning clocks remain identical")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"pure_clip_error":pure_error,"scope":"4 idle phases x 16 run phases x 11 weights, then 30/60fps stop/restart/turn/pause at three speeds; independent held-prop/contact/length and unchanged-channel checks."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RUN_ENTRY_V22_COMPLETE checks=",checks.size()," failures=",failures.size()," metrics=",metrics)
	v.free();old.free();quit(0 if failures.is_empty() else 1)
