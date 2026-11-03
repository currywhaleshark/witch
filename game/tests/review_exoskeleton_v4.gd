extends "res://tests/review_drive_tree_v1.gd"
const Equipment=preload("res://tests/helpers/exoskeleton_v4.gd")
func run()->void:
	root.size=Vector2i(1100,850)
	var world:=world_scene();var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	var player:=Player.new();world.add_child(player);assert(player.initialize());player.set_process(false);player.motion_duration=1
	var exo:=Equipment.new();player.runtime.skeleton.add_child(exo);assert(exo.initialize(player.runtime.skeleton))
	var probe:bool="--probe" in OS.get_cmdline_user_args()
	var probe_phase:=.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):probe_phase=clampf(float(arg.trim_prefix("--phase=")),0,1)
	for form in ["civilian","transformed"]:
		assert(exo.fit_form(player,form))
		for motion in ["idle","run","attack","attack_thrust","cast","hit_react","spring_jump","collapse"]:
			player._attack_clip_kind="attack_thrust" if motion=="attack_thrust" else "attack"
			var kind:String="attack" if motion=="attack_thrust" else motion
			for view in ["front","back"]:
				var seq:String="%s_%s_%s"%[form,motion,view]
				camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.05
				camera.position=Vector3(2.4,1.35,3.2 if view=="back" else -3.2)*3;camera.look_at(Vector3(0,.76,0))
				for frame in (1 if probe else 49):
					var phase:=probe_phase if probe else float(frame)/48
					player._sample(kind,player._length(kind)*phase);exo.sync_pose_for_motion(motion,phase)
					await capture("%s/%03d.jpg"%[seq,frame])
				sequences.append({"id":seq,"form":form,"motion":motion,"view":view,"frames":1 if probe else 49,"fps":48.0/maxf(player._length(kind),.01)})
		player._sample("idle",.5);exo.sync_pose_for_motion("idle",.25)
		camera.position=Vector3(4,.95,.1);camera.look_at(Vector3(0,.80,0));camera.size=1.95
		await capture("models/%s_side.jpg"%form)
		root.size=Vector2i(1280,800);camera.rotation_degrees=Vector3(-30,45,0);camera.size=20.0/1.75*player.MODEL_SCALE;camera.position=Vector3(0,.4,0)+camera.basis.z*30
		await capture("models/%s_native.jpg"%form);root.size=Vector2i(1100,850)
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"captures":captures,"sequences":sequences,"probe":probe,"scope":"Current player, both forms, 8 clips with auxiliary rigid equipment. No active skill."},"  "))
	print("EXO_V4_REVIEW_DONE ",captures);quit()
