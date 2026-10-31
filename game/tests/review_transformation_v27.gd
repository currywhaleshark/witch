extends "res://tests/review_staff_visual.gd"

func run() -> void:
	ProjectSettings.set_setting("debug/entry_polish_v27", true)
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate()
	arena.field_entry_mode=1
	root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("alley_v2")
	for plan in [{"id":"front","label":"입장 변신 · 앞쪽"},{"id":"native","label":"실제 게임 크기","native":true},{"id":"back","label":"의상 교체 · 뒷쪽","back":true},{"id":"pause","label":"조립 중 일시정지·재개","pause":true}]:
		arena.load_map("alley_v2" if plan.get("native",false) else "flat")
		arena.reset_arena();arena.muted=true;arena.help_visible=false
		arena.config.enemy_speed=0.0
		var origin:Vector3=arena.player.position
		if not plan.get("native",false): arena.player_model.look_at(origin+Vector3.RIGHT)
		var rows:Array=[]
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		var count:int=118 if plan.get("pause",false) else 100
		for frame in count:
			arena.paused=plan.get("pause",false) and frame>=27 and frame<45
			if frame>0:
				for tick in 2:
					await physics_frame
					arena._physics_process(1.0/60.0)
			if plan.get("native",false): frame_camera(true)
			else:
				arena.hud.visible=false
				var focus:Vector3=origin+Vector3(0,.85,0)
				arena.camera.size=2.65
				arena.camera.position=focus+(Vector3(-7,2,3) if plan.get("back",false) else Vector3(8,2,-4))
				arena.camera.look_at(focus)
			arena.move_marker.visible=false;arena.hover_ring.visible=false
			await capture(plan.id+"/%03d.jpg"%frame)
			rows.append({"seconds":frame/30.0,"visual":arena.player_visual.debug_snapshot(),"paused":arena.paused})
		sequences.append({"id":plan.id,"label":plan.label,"fps":30,"frames":rows.size(),"samples":rows})
	# Actual post-entry combat in the transformed outfit, at the same current lighting.
	arena.load_map("flat")
	for action in ["run","attack","cast","hit","jump"]:
		prepare();arena.player_model.look_at(arena.player.position+Vector3.RIGHT)
		for tick in 180: arena._physics_process(1.0/60.0)
		if action=="attack":
			arena.spawn_enemy("target",Vector3(1.1,0,0),false)
			arena.enemies.target.cooldown=999.0;arena.enemies.target.hp=10000.0
			arena.enemies.target.model.visible=false
		arena.bind_slot("q","spring_dash")
		if action=="run":arena.destination=Vector3(8,0,0);arena.moving=true
		elif action=="attack":arena.request_slot("lmb",{"enemy_id":"target","ground":[1.1,0,0]})
		elif action=="cast":arena.request_slot("w",{"ground":[3,0,0]})
		elif action=="hit":arena.damage_player(20.0,"normal")
		else:arena.request_slot("q",{"ground":[5,0,0]})
		DirAccess.make_dir_recursive_absolute(output.path_join(action))
		var rows:Array=[]
		for frame in 49:
			for tick in 2:
				await physics_frame
				arena._physics_process(1.0/60.0)
			arena.hud.visible=false
			var focus:Vector3=arena.player.position+Vector3(0,.85,0)
			arena.camera.size=2.9
			arena.camera.position=focus+Vector3(8,2,-4);arena.camera.look_at(focus)
			await capture(action+"/%03d.jpg"%frame)
			rows.append({"seconds":frame/30.0,"visual":arena.player_visual.debug_snapshot(),"paused":false})
		sequences.append({"id":action,"label":{"run":"변신 후 · 달리기","attack":"변신 후 · 타격","cast":"변신 후 · 캐스팅","hit":"변신 후 · 경직","jump":"변신 후 · 스프링 도약"}[action],"fps":30,"frames":rows.size(),"samples":rows})
	var result:Dictionary={"passed":true,"captures":captures,"sequences":sequences,"scope":"Actual arena 60Hz ticks captured at 30fps. Four entry views and five post-entry actions. Native entry uses the alley; detail views use the flat arena with its game lighting. No added studio lights. The attack target model alone is hidden for outfit visibility; targeting and hit logic remain live. Audio is muted for captures."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("TRANSFORMATION_V27_REVIEW_COMPLETE captures=",captures)
	arena.free();quit(0)
