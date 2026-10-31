extends "res://tests/spring_plate_v1.gd"
var bone_error := 0.0
var grip_error := 0.0
var arc_error := 0.0
var floor_error := 0.0
var left_offset := Vector3.ZERO

func measure_hands() -> void:
	var v=arena.player_visual
	var bones:Skeleton3D=v.runtime.skeleton
	var right:Vector3=bones.global_transform*bones.get_bone_global_pose(bones.find_bone("DEF-hand.R"))*v.STAFF_GRIP_OFFSET
	var left:Vector3=bones.global_transform*bones.get_bone_global_pose(bones.find_bone("DEF-hand.L"))*left_offset
	var axis:Vector3=v.staff_root.global_basis.y.normalized()
	grip_error=maxf(grip_error,(left-right+axis*.26*v.MODEL_SCALE).length())

func run() -> void:
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat")
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../reports/spring_jump_v24/pose_fixture.json").simplify_path()))
	left_offset=Vector3(fixture.left_offset[0],fixture.left_offset[1],fixture.left_offset[2])
	await fresh()
	check(arena.player_visual.loaded_ok,"new jump clip loads on the unchanged 107-bone character")
	var v=arena.player_visual
	for sample in fixture.samples:
		v._sample("spring_jump",float(sample.seconds))
		var bones:Skeleton3D=v.runtime.skeleton
		for name in sample.bones:
			var p:Array=sample.bones[name]
			var actual:Vector3=v.asset_wrapper.global_transform.affine_inverse()*bones.global_transform*bones.get_bone_global_pose(bones.find_bone(name)).origin
			bone_error=maxf(bone_error,actual.distance_to(Vector3(p[0],p[1],p[2])))
		measure_hands()
	check(bone_error<.0003,"17 imported poses match the reopened Blender skeleton within 0.3mm")
	for rate in [30,60,120]:
		for fcr in [0.,40.]:
			await fresh(rate,fcr);v=arena.player_visual
			var start:Vector3=arena.player.position;var mana:float=arena.state.mana
			var p:Node3D=request();var release:float=arena.windup.release
			check(v._motion_kind=="spring_jump","spring preparation uses the user's adapted jump")
			var count:=0;var max_height:=0.;var airborne_frames:=0;var bad_run:=false
			while p.mode=="assembling" and count<20:
				await step();count+=1
			check(count==int(ceil(release*rate-.00001)),"jump does not delay the existing release at %d fps / FCR %d"%[rate,fcr])
			check(is_equal_approx(mana-arena.state.mana,8.),"successful jump retains one dash mana cost")
			for i in range(rate):
				var state:Dictionary=v._spring_jump.debug_state()
				if state.mode=="flight":
					airborne_frames+=1
					var expected:float=.32*4.*state.progress*(1.-state.progress)
					arc_error=maxf(arc_error,absf(v.asset_wrapper.position.y-expected))
					max_height=maxf(max_height,v.asset_wrapper.position.y)
					bad_run=bad_run or v._clip.get_file()!="combat_spring_jump_v24"
					measure_hands()
				floor_error=maxf(floor_error,absf(arena.player.position.y-arena.map.ground_y(arena.player.position)))
				await step()
			check(airborne_frames>0 and not bad_run,"flight keeps the jump pose instead of locomotion")
			check(max_height>.30 and max_height<=.32001,"flight makes the intended low arc")
			check(v._spring_jump.mode=="idle" and is_zero_approx(v.asset_wrapper.position.y),"landing settles back to zero visual height")
			check(v._state=="idle" and arena.dash.is_empty(),"landing restores the idle motion without a residual dash")
			check(absf(arena.player.position.distance_to(start)-4.8)<.001,"ground movement retains the existing unobstructed dash distance")
			cases.append({"fps":rate,"fcr":fcr,"release_frame":count,"peak_height":max_height,"airborne_frames":airborne_frames})
	await fresh();request();await step(7);v=arena.player_visual
	var pause_state:Dictionary=v.debug_snapshot();var position:Vector3=arena.player.position
	arena.paused=true;await step(8)
	check(v.debug_snapshot().spring_jump==pause_state.spring_jump and v.clip_time==pause_state.clip_time and arena.player.position==position,"pause freezes jump pose, arc and movement")
	arena.paused=false;await step(40)
	check(is_zero_approx(v.asset_wrapper.position.y),"resumed jump lands cleanly")
	for reason in ["hit","cost","binding"]:
		await fresh();request();await step();v=arena.player_visual
		if reason=="hit":arena.damage_player(20.,"normal")
		elif reason=="cost":arena.state.mana=0.
		else:arena.bind_slot("q","shotgun")
		await step(35)
		check(arena.dash.is_empty() and v._spring_jump.mode=="idle" and is_zero_approx(v.asset_wrapper.position.y),reason+" before release never launches the character")
	await fresh();request();await step(7);v=arena.player_visual
	var height:float=v.asset_wrapper.position.y
	# Exercise the exact presentation path used when a wall truncates tick_dash.
	v.land_spring_jump();arena.dash.clear()
	await step()
	check(v.asset_wrapper.position.y<=height and v.asset_wrapper.position.y>0.,"early wall stop begins a local descent without a height snap")
	await step(18)
	check(is_zero_approx(v.asset_wrapper.position.y) and v._spring_jump.mode=="idle","early stop removes the arc and finishes landing")
	await fresh();request();await step(7);v=arena.player_visual
	arena.damage_player(1000.,"normal");await step(40)
	check(v.is_dead and is_zero_approx(v.asset_wrapper.position.y),"death during flight descends and keeps the collapse state")
	await fresh();request();await step(7);arena.reset_arena();await step(2)
	check(is_zero_approx(arena.player_visual.asset_wrapper.position.y) and arena.player_visual._spring_jump.mode=="idle","reset removes every jump visual state")
	await fresh();request();await step(7);arena.load_map("alley_v2");await step(2)
	check(is_zero_approx(arena.player_visual.asset_wrapper.position.y),"map change removes the airborne offset")
	await fresh(60,0.,Vector3(33,0,0));request();await step(7);v=arena.player_visual
	check(arena.player.position.y>1.19 and v.asset_wrapper.position.y>0.2,"jump rises relative to the raised floor")
	await step(35);check(is_zero_approx(v.asset_wrapper.position.y),"raised-floor jump returns to its floor")
	await fresh();request();await step(7);v=arena.player_visual
	# Visual recovery must never create a new gameplay lock or delay a legal next action.
	arena.action_time=.6;v.begin_motion("attack",.6,.5);await step()
	check(v._motion_kind=="attack","a later combat motion can replace the jump pose")
	await step(30);check(is_zero_approx(v.asset_wrapper.position.y),"a later action cannot strand the airborne offset")
	check(arc_error<.000001,"actual visual height matches the parabola across frame rates")
	check(floor_error<.000001,"combat body and collision remain on their existing ground path")
	check(grip_error<.003,"jump and landing keep the right-above-left two-hand grip within 3mm")
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,"bone_error_m":bone_error,"grip_error_m":grip_error,"arc_error_m":arc_error,"ground_body_error_m":floor_error}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SPRING_JUMP_TEST_COMPLETE ",checks.size()," failures=",failures)
	arena.free();quit(0 if failures.is_empty() else 1)
