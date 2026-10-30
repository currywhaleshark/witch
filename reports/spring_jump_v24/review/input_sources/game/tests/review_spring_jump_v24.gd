extends "res://tests/review_staff_visual.gd"

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat")
	for plan in [
		{"id":"side","label":"도약 · 측면","fcr":0.},
		{"id":"front","label":"양손 지팡이 · 앞쪽","fcr":0.,"front":true},
		{"id":"native","label":"실제 게임 표시 크기","fcr":0.,"native":true},
		{"id":"fast","label":"시전 속도 40","fcr":40.},
		{"id":"short","label":"짧은 거리 도약","fcr":0.,"short":true},
		{"id":"cancel","label":"이륙 전 경직 · 취소","fcr":0.,"cancel":true},
		{"id":"pause","label":"공중에서 정지 · 재개","fcr":0.,"pause":true},
		{"id":"raised","label":"높은 지면에서 도약","fcr":0.,"raised":true}]:
		if plan.get("raised",false):arena.load_map("alley_v2")
		prepare();arena.bind_slot("q","spring_dash");arena.config.cast_speed_score=plan.fcr
		if plan.get("raised",false):arena.player.position=arena.map.grounded(Vector3(33,0,0))
		var origin:Vector3=arena.player.position
		arena.player_model.look_at(origin+Vector3.RIGHT)
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		var rows:Array=[];var p:Node3D=null
		for frame in 61:
			if frame==8:
				arena.request_slot("q",{"ground":[origin.x+(1.5 if plan.get("short",false) else 5.),0.,origin.z]});p=arena.spring_plate
				if is_instance_valid(p):p.set_process(false)
			if frame==9 and plan.get("cancel",false):arena.damage_player(20.,"normal")
			arena.paused=plan.get("pause",false) and frame>=16 and frame<29
			var ending:bool=is_instance_valid(p) and p.mode!="assembling"
			await physics_frame
			arena._physics_process(1./60.)
			if ending and is_instance_valid(p):p.advance(1./60.)
			if plan.get("native",false):frame_camera(true)
			else:
				arena.hud.visible=false;arena.move_marker.visible=false;arena.hover_ring.visible=false
				var focus:Vector3=origin+Vector3(2.4,.85,0)
				if plan.get("raised",false):focus.y=arena.player.position.y+.85
				if plan.get("cancel",false) or plan.get("short",false):focus=origin+Vector3(.6,.85,0)
				arena.camera.size=4.3 if not plan.get("cancel",false) else 2.8
				arena.camera.position=focus+Vector3(0,2,-9);arena.camera.look_at(focus)
				if plan.get("front",false):
					focus=arena.player.position+Vector3(0,.95,0)
					arena.camera.size=2.6;arena.camera.position=focus+Vector3(8,2,-1);arena.camera.look_at(focus)
			await capture(plan.id+"/%03d.jpg"%frame)
			var v=arena.player_visual
			rows.append({"seconds":frame/60.,"visual":v.debug_snapshot(),"position":[arena.player.position.x,arena.player.position.y,arena.player.position.z],"dash_active":not arena.dash.is_empty(),"paused":arena.paused,"plate_mode":p.mode if is_instance_valid(p) else "gone"})
		sequences.append({"id":plan.id,"label":plan.label,"fps":60,"frames":rows.size(),"samples":rows})
	var result:Dictionary={"passed":true,"captures":captures,"sequences":sequences,"scope":"Eight actual arena sequences at 60Hz, current game lighting. Manual advancement avoids render-clock variation; release, motion and ground dash run through arena."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SPRING_JUMP_REVIEW_COMPLETE captures=",captures)
	arena.free();quit(0)
