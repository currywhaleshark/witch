extends "res://tests/exoskeleton_v3_art.gd"
func run()->void:
	var player:=Player.new();root.add_child(player);check(player.initialize(),"player loads");player.set_process(false)
	var exo:=Exo.new();player.runtime.skeleton.add_child(exo);check(exo.initialize(player.runtime.skeleton),"exo loads")
	var rows:Array=[]
	for motion in ["idle","run","attack","attack_thrust","cast","hit_react","spring_jump","collapse"]:
		player._attack_clip_kind="attack_thrust" if motion=="attack_thrust" else "attack"
		var kind:String="attack" if motion=="attack_thrust" else motion
		var previous:Dictionary={};var maxima:Dictionary={};var first:Dictionary={};var min_bend:=1.0
		for sample in 241:
			player._sample(kind,player._length(kind)*sample/240.0);exo.sync_pose()
			for side in ["L","R"]:
				var s:Vector3=exo.bone("DEF-upper_arm."+side).origin;var e:Vector3=exo.bone("DEF-forearm."+side).origin;var w:Vector3=exo.bone("DEF-hand."+side).origin
				min_bend=minf(min_bend,(s-e).normalized().cross((w-e).normalized()).length())
			for role in exo.current_frames:
				var t:Transform3D=exo.current_frames[role]
				if sample==0:first[role]=t
				if previous.has(role):
					var old:Transform3D=previous[role];var angle:=rad_to_deg(old.basis.get_rotation_quaternion().angle_to(t.basis.get_rotation_quaternion()))
					if not maxima.has(role) or angle>maxima[role].degrees:maxima[role]={"degrees":angle,"phase":sample/240.0,"travel_m":old.origin.distance_to(t.origin)}
				previous[role]=t
		var seam:Dictionary={}
		if motion in ["idle","run"]:
			for role in first:
				var a:Transform3D=first[role];var b:Transform3D=previous[role]
				seam[role]={"degrees":rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())),"travel_m":a.origin.distance_to(b.origin)}
				check(seam[role].degrees<.1 and seam[role].travel_m<.0001,"loop seam "+motion+" "+role)
		for role in maxima:check(maxima[role].degrees<30,"continuous "+motion+" "+role)
		check(min_bend>.08,"sampled clips avoid straight-arm singularity")
		rows.append({"motion":motion,"frames":241,"maximum_steps":maxima,"loop_seam":seam,"minimum_bend_cross_length":min_bend})
	FileAccess.open(output.path_join("continuity.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"clips":rows},"  "))
	print("EXO_V3_CONTINUITY ",checks," failures ",failures);quit(0 if failures.is_empty() else 1)
