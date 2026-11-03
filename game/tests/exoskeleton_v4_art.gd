extends SceneTree
const Player=preload("res://scripts/player_visual.gd")
const Exo=preload("res://tests/helpers/exoskeleton_v4.gd")
var output:="res://../reports/exoskeleton_v4"
var checks:=0
var failures:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func matrix(t:Transform3D)->Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]
func _initialize()->void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
	call_deferred("run")
func run()->void:
	var player:=Player.new();root.add_child(player);check(player.initialize(),"player loads");player.set_process(false);player.motion_duration=1
	var exo:=Exo.new();player.runtime.skeleton.add_child(exo);check(exo.initialize(player.runtime.skeleton),"exo loads")
	check(exo.rig.get_bone_count()==int(exo.manifest.rig_bones),"expected independent mechanical bones")
	var rest_record:Dictionary={}
	for i in player.runtime.skeleton.get_bone_count():rest_record[player.runtime.skeleton.get_bone_name(i)]=matrix(player.runtime.skeleton.get_bone_global_rest(i))
	FileAccess.open(output.path_join("body_rest.json"),FileAccess.WRITE).store_string(JSON.stringify(rest_record))
	var records:Array=[];var max_joint_error:=0.0;var shortest:=999.0;var longest:=0.0
	var bake:bool="--bake" in OS.get_cmdline_user_args()
	var hair_rest:Dictionary={}
	var hair_rig:Skeleton3D=player._hair_motion._rig
	for i in hair_rig.get_bone_count():hair_rest[hair_rig.get_bone_name(i)]=matrix(hair_rig.get_bone_global_rest(i))
	FileAccess.open(output.path_join("hair_rest.json"),FileAccess.WRITE).store_string(JSON.stringify(hair_rest))
	for form in ["civilian","transformed"]:
		check(exo.fit_form(player,form),"fitted form loads")
		for motion in ["idle","run","attack","attack_thrust","cast","hit_react","spring_jump","collapse"]:
			player._attack_clip_kind="attack_thrust" if motion=="attack_thrust" else "attack"
			var kind:String="attack" if motion=="attack_thrust" else motion
			var intervals:int=ceili(player._length(kind)*24) if bake else 24
			for sample in intervals+1:
				var phase:=float(sample)/intervals;player._sample(kind,player._length(kind)*phase);exo.sync_pose_for_motion(motion,phase)
				var record:Dictionary={"form":form,"motion":motion,"phase":phase,"clip_length":player._length(kind),"bones":{},"mechanism":{},"exo_bones":{},"hair_bones":{}}
				for i in player.runtime.skeleton.get_bone_count():record.bones[player.runtime.skeleton.get_bone_name(i)]=matrix(player.runtime.skeleton.get_bone_global_pose(i))
				for role in exo.current_frames:
					var t:Transform3D=exo.current_frames[role];check(t.is_finite(),"finite "+role);check(absf(t.basis.determinant()-1)<.0001,"rigid "+role)
					record.mechanism[role]=matrix(t)
				for i in exo.rig.get_bone_count():record.exo_bones[exo.rig.get_bone_name(i)]=matrix(exo.rig.get_bone_global_pose(i))
				var hair:Skeleton3D=player._hair_motion._rig
				if is_instance_valid(hair):
					for i in hair.get_bone_count():record.hair_bones[hair.get_bone_name(i)]=matrix(hair.get_bone_global_pose(i))
				for side in ["L","R"]:
					var u:Transform3D=exo.current_frames["upper_"+side];var f:Transform3D=exo.current_frames["forearm_"+side]
					var expected:Vector3=u*Vector3(0,exo.upper_lengths[side],0)
					var error:=expected.distance_to(f.origin);max_joint_error=maxf(max_joint_error,error)
					check(error<.0005,"shared elbow pivot stays connected")
					var upper_spec:Dictionary=exo.manifest.upper_slide[side]
					var upper_gap:float=exo.upper_lengths[side]-float(upper_spec.start_offset)-float(upper_spec.end_offset)
					check(upper_gap>float(upper_spec.segment_length) and upper_gap<float(upper_spec.segment_length)*int(upper_spec.segments),"upper slide travel")
					shortest=minf(shortest,exo.bridge_lengths[side]);longest=maxf(longest,exo.bridge_lengths[side])
					var link:Dictionary=exo.manifest.bridge[side]
					check(exo.bridge_lengths[side]>float(link.segment_length) and exo.bridge_lengths[side]<float(link.segment_length)*int(link.segments),"telescope travel")
				records.append(record)
	FileAccess.open(output.path_join("bake_poses.json" if bake else "poses.json"),FileAccess.WRITE).store_string(JSON.stringify(records))
	FileAccess.open(output.path_join("bake_test.json" if bake else "art_test.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"poses":records.size(),"max_elbow_gap_m":max_joint_error,"bridge_length_range_m":[shortest,longest]},"  "))
	print("EXO_V4_ART_DONE ",checks," ",records.size()," failures ",failures.size()," elbow ",max_joint_error," bridge ",shortest," ",longest);quit(0 if failures.is_empty() else 1)
