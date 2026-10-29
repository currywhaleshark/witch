extends "res://tests/review_staff_visual.gd"

func specimen(path: String, tool: String, parent: Node3D, position: Vector3) -> Node3D:
	var model:Node3D=load(path).instantiate()
	parent.add_child(model);model.position=position
	for group in ["bolt_cutter","grinder","chainsaw","ornament_seal"]:
		model.find_child(group,true,false).visible=group==tool
	return model

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	prepare();arena.player.visible=false;arena.hud.visible=false;arena.world.visible=false
	var studio:=Node3D.new();arena.add_child(studio)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,160,0);light.light_energy=1.7
	studio.add_child(light)
	var old_path:="res://assets/weapons/staff_transform_v2/staff_parts.glb"
	var new_path:="res://assets/weapons/staff_material_v3/staff_parts.glb"
	for i in 4:
		var tool:String="" if i==0 else Staff.TOOLS[i-1]
		var old:=specimen(old_path,tool,studio,Vector3(.44,0,0))
		var current:=specimen(new_path,tool,studio,Vector3(-.44,0,0))
		arena.camera.size=2.05;arena.camera.position=Vector3(.25,.40,-5)
		arena.camera.look_at(Vector3(0,.40,0))
		await capture("pair_%d.jpg"%i)
		if i==1:
			old.position.x=.31;current.position.x=-.31
			arena.camera.size=.96;arena.camera.position=Vector3(.10,.94,-5)
			arena.camera.look_at(Vector3(0,.94,0));await capture("cutter_detail.jpg")
		old.free();current.free()
	var models:Array=[]
	for i in 4:
		models.append(specimen(new_path,"" if i==0 else Staff.TOOLS[i-1],studio,Vector3((1.5-i)*.50,0,0)))
	arena.camera.size=2.15;arena.camera.position=Vector3(.7,.47,-6)
	arena.camera.look_at(Vector3(0,.40,0))
	await capture("lineup.jpg")
	DirAccess.make_dir_recursive_absolute(output.path_join("turntable"))
	var table_samples:Array=[]
	for frame in 61:
		var angle:float=sin(float(frame)/60.0*TAU)*.75
		for model:Node3D in models:model.rotation.y=angle
		await capture("turntable/%03d.jpg"%frame)
		table_samples.append({"seconds":frame/30.0,"angle":angle})
	sequences.append({"id":"turntable","label":"표면과 반사 · 4종 회전","frames":61,"fps":30,"samples":table_samples})
	for model in models:model.free()
	var seal:=specimen(new_path,"ornament_seal",studio,Vector3.ZERO)
	arena.camera.size=.64;arena.camera.position=Vector3(.5,.57,-3)
	arena.camera.look_at(Vector3(0,.57,0));await capture("core_seal.jpg")
	seal.free();studio.free();arena.world.visible=true
	var plans:Array=[
		{"id":"attack","label":"볼트커터 · 실제 타격","tool":"q","attack":true},
		{"id":"grinder","label":"그라인더 · 실제 타격","tool":"r","attack":true},
		{"id":"chainsaw","label":"전기톱 · 실제 타격","tool":"e","attack":true},
		{"id":"run","label":"이동 중 공구 전환","run":true},
		{"id":"native","label":"실제 게임 표시 크기","tool":"q","attack":true,"native":true}]
	for plan in plans:
		prepare()
		arena.player_visual.set_staff_appearance("seal")
		arena.spawn_enemy("target",Vector3(1.65,0,0),false,"normal","rag")
		arena.enemies.target.hp=10000.0;arena.enemies.target.max_hp=10000.0;arena.enemies.target.cooldown=999.0
		arena.player_model.look_at(Vector3(1,0,0))
		# Same swing choice in each material review, without touching combat RNG.
		var probe:=RandomNumberGenerator.new()
		for value in range(1,100):
			probe.seed=value
			if probe.randf()<.5:arena.player_visual._attack_rng.seed=value;break
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		var samples:Array=[]
		for frame in 91:
			if frame==5:
				arena.request_slot(plan.get("tool","q"),{})
				if plan.get("run",false):arena.set_destination(Vector3(-4,0,-2))
			if frame==25 and plan.get("attack",false):arena.request_slot("lmb",{"enemy_id":"target"})
			if plan.get("run",false):
				if frame==25:arena.request_slot("r",{})
				if frame==45:arena.request_slot("e",{})
				if frame==70:arena.request_slot("e",{})
			await physics_frame
			arena._physics_process(1.0/60.0)
			frame_camera(plan.get("native",false))
			if not plan.get("native",false):
				arena.camera.size=3.45
				arena.camera.position=arena.player.position+Vector3(0,1.12,0)+arena.camera.basis.z*30
			if frame%2==0:
				samples.append({"seconds":frame/60.0,"staff":arena.player_visual.staff_visual.debug_state(),
					"clip":arena.player_visual._clip,"motion":arena.player_visual._motion_kind,"hp":arena.enemies.target.hp})
				await capture(plan.id+"/%03d.jpg"%(frame/2))
		sequences.append({"id":plan.id,"label":plan.label,"frames":samples.size(),"fps":30,"samples":samples})
	var report={"passed":true,"captures":captures,"sequences":sequences,
		"scope":"Seven same-light model stills, a separate studio turntable, five actual 60Hz arena sequences captured at 30fps. World/game lighting is unchanged."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STAFF_MATERIAL_REVIEW_COMPLETE captures=",captures)
	arena.free();quit(0)
