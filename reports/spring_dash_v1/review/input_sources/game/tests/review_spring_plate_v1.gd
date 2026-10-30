extends "res://tests/review_staff_visual.gd"
const Spring = preload("res://scripts/spring_plate.gd")

func plate_state(p) -> Dictionary:
	if not is_instance_valid(p):return {"mode":"gone","visible_parts":0}
	var state:Dictionary=p.debug_state()
	state.origin=[p.global_position.x,p.global_position.y,p.global_position.z]
	return state

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat");prepare()
	arena.player.visible=false;arena.hud.visible=false
	var p=Spring.new();arena.world.add_child(p);p.initialize(arena);p.set_process(false)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-42,135,0);light.light_energy=1.15;arena.add_child(light)
	arena.camera.size=1.32;arena.camera.position=Vector3(1.25,.72,-1.8);arena.camera.look_at(Vector3(0,.16,0))
	DirAccess.make_dir_recursive_absolute(output.path_join("mechanism"))
	var rows:Array=[]
	for frame in 121:
		var t:=frame/240.
		if is_instance_valid(p):
			if t<.06:p.sample_progress(t/.06)
			elif p.mode=="assembling":p.launch(Vector3.FORWARD)
			else:p.advance(1./240.)
		await capture("mechanism/%03d.jpg"%frame)
		rows.append({"seconds":t,"plate":plate_state(p)})
	sequences.append({"id":"mechanism","label":"기구 확대 · 240Hz 세부 샘플","fps":240,"frames":rows.size(),"samples":rows})
	light.free()
	for plan in [
		{"id":"dash","label":"실제 돌진 · 확대","fcr":0.},
		{"id":"native","label":"실제 게임 표시 크기","fcr":0.,"native":true},
		{"id":"fast","label":"시전 속도 40 · 더 빠른 조립","fcr":40.},
		{"id":"cancel","label":"발동 직전 경직 · 조립 취소","fcr":0.,"cancel":true},
		{"id":"pause","label":"작동 중 정지와 재개","fcr":0.,"pause":true},
		{"id":"raised","label":"높은 바닥에서 출발","fcr":0.,"raised":true}]:
		if plan.get("raised",false):arena.load_map("alley_v2")
		prepare();arena.bind_slot("q","spring_dash");arena.config.cast_speed_score=plan.fcr
		if plan.get("raised",false):arena.player.position=arena.map.grounded(Vector3(33,0,0))
		var origin:Vector3=arena.player.position
		arena.player_model.look_at(origin+Vector3.RIGHT)
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		rows=[];p=null
		for frame in 61:
			if frame==8:
				arena.request_slot("q",{"ground":[origin.x+5.,0.,origin.z]});p=arena.spring_plate
				if is_instance_valid(p):p.set_process(false)
			if frame==9 and plan.get("cancel",false):arena.damage_player(20.,"normal")
			arena.paused=plan.get("pause",false) and frame>=15 and frame<28
			var ending:bool=is_instance_valid(p) and p.mode!="assembling"
			await physics_frame
			arena._physics_process(1./60.)
			if ending and is_instance_valid(p):p.advance(1./60.)
			if plan.get("native",false):frame_camera(true)
			else:
				arena.hud.visible=false;arena.move_marker.visible=false;arena.hover_ring.visible=false
				var focus:Vector3=origin+Vector3(1.8,.65,0)
				if plan.get("cancel",false):focus=origin+Vector3(0,.65,0)
				arena.camera.size=4.6 if not plan.get("cancel",false) else 2.7
				arena.camera.position=focus+Vector3(0,6,-9);arena.camera.look_at(focus)
			await capture(plan.id+"/%03d.jpg"%frame)
			rows.append({"seconds":frame/60.,"plate":plate_state(p),"position":[arena.player.position.x,arena.player.position.y,arena.player.position.z],"dash_active":not arena.dash.is_empty(),"paused":arena.paused,"mana":arena.state.mana})
		sequences.append({"id":plan.id,"label":plan.label,"fps":60,"frames":rows.size(),"samples":rows})
	var report:Dictionary={"passed":true,"captures":captures,"sequences":sequences,"scope":"One separately lit mechanism inspection at 240Hz; six actual 60Hz arena cases in normal game lighting. Captures use manual visual advancement to avoid render-time variation; arena movement/release/cost logic runs normally."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SPRING_REVIEW_COMPLETE captures=",captures)
	arena.free();quit(0)
