extends "res://tests/review_staff_visual.gd"

func select_variant(kind: String) -> void:
	var rng:=RandomNumberGenerator.new()
	for value in range(1,100):
		rng.seed=value
		if ("attack" if rng.randf()<.5 else "attack_thrust")==kind:
			arena.player_visual._attack_rng.seed=value
			return

func caption(parent: Node3D, text: String, point: Vector3) -> Label3D:
	var label:=Label3D.new()
	label.text=text
	label.font_size=36
	label.pixel_size=.0012
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.position=point
	parent.add_child(label)
	return label

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.set_process_input(false)
	arena.set_process_unhandled_input(false)
	await process_frame
	prepare()
	arena.player.visible=false
	arena.hud.visible=false
	arena.world.visible=false
	var studio:=Node3D.new()
	arena.add_child(studio)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-30,160,0)
	light.light_energy=1.7
	studio.add_child(light)
	var old:Node3D=load("res://assets/weapons/staff_transform_v1/staff_parts.glb").instantiate()
	studio.add_child(old)
	old.position.x=.68
	for group in ["grinder","chainsaw","ornament_seal"]:old.find_child(group,true,false).visible=false
	for tag in ["l","r"]:
		var jaw:Node3D=old.find_child("cutter_jaw_"+tag,true,false)
		jaw.rotate_z(.08 if tag=="l" else -.08)
	var closed:=Staff.new()
	studio.add_child(closed)
	assert(closed.initialize())
	closed.set_tool("bolt_cutter");closed.finish_assembly();closed.advance(.5,false,.5)
	var opened:=Staff.new()
	studio.add_child(opened)
	assert(opened.initialize())
	opened.position.x=-.68
	opened.set_tool("bolt_cutter");opened.finish_assembly();opened.advance(.5,false,.30)
	var labels:Array=[]
	labels.append(caption(studio,"V1  /  PREVIOUS",Vector3(.68,.49,-.12)))
	labels.append(caption(studio,"V2  /  CLOSED",Vector3(0,.49,-.12)))
	labels.append(caption(studio,"V2  /  OPEN 64 deg",Vector3(-.68,.49,-.12)))
	arena.camera.size=1.5
	arena.camera.position=Vector3(0,.89,-5)
	arena.camera.look_at(Vector3(0,.89,0))
	await capture("comparison.jpg")
	old.visible=false;opened.visible=false
	for label in labels:label.visible=false
	arena.camera.size=.78
	arena.camera.position=Vector3(0,.94,-4)
	arena.camera.look_at(Vector3(0,.94,0))
	await capture("closed.jpg")
	closed.advance(.01,false,.30)
	await capture("open.jpg")
	arena.camera.position=Vector3(1.6,1.05,-3)
	arena.camera.look_at(Vector3(0,.94,0))
	await capture("bevel.jpg")
	closed.advance(.5,false,-1.0)
	arena.camera.size=1.85
	arena.camera.position=Vector3(.6,.5,-4)
	arena.camera.look_at(Vector3(0,.35,0))
	await capture("staff.jpg")
	studio.free()
	arena.world.visible=true
	var plans:Array=[
		{"id":"swing","label":"휘두르기 · 타격 순간 닫힘","variant":"attack"},
		{"id":"swing_side","label":"휘두르기 · 반대 각도","variant":"attack","side":true},
		{"id":"thrust","label":"찌르기 · 같은 타격 시점","variant":"attack_thrust"},
		{"id":"head","label":"날 확대 · 실제 타격 60fps","variant":"attack","head":true},
		{"id":"fast","label":"빠른 공격 · IAS 40","variant":"attack","ias":40},
		{"id":"native","label":"실제 게임 표시 크기","variant":"attack","native":true},
		{"id":"assembly","label":"부품 생성 · 조립","assembly":true}]
	for plan in plans:
		prepare()
		arena.world.visible=true
		arena.camera.cull_mask=1
		if plan.get("head",false):
			# Inspect the real attached meshes without the struck enemy / hit flash
			# obscuring the closing edges. Combat and animation still run normally.
			for geometry in arena.player_visual.staff_visual.find_children("*","GeometryInstance3D",true,false):
				geometry.layers=2
			arena.camera.cull_mask=2
			var inspection_light:=DirectionalLight3D.new()
			inspection_light.layers=2
			inspection_light.light_cull_mask=2
			inspection_light.rotation_degrees=Vector3(-30,160,0)
			inspection_light.light_energy=1.2
			arena.player_visual.staff_visual.add_child(inspection_light)
		arena.config.attack_speed_score=plan.get("ias",0)
		arena.spawn_enemy("target",Vector3(1.65,0,0),false,"normal","rag")
		arena.enemies.target.hp=10000.0;arena.enemies.target.max_hp=10000.0
		arena.enemies.target.cooldown=999.0
		arena.player_model.look_at(Vector3(1,0,0))
		var frames:int=61 if plan.get("assembly",false) else 91
		var every:int=1 if plan.get("head",false) else 2
		var samples:Array=[]
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		for frame in frames:
			if frame==5:arena.request_slot("q",{})
			if frame==25 and not plan.get("assembly",false):
				select_variant(plan.variant)
				arena.request_slot("lmb",{"enemy_id":"target"})
			await physics_frame
			arena._physics_process(1.0/60.0)
			await process_frame
			frame_camera(plan.get("native",false))
			if not plan.get("native",false):
				# Include the raised extended blades during the whole windup.
				arena.camera.size=3.45
				arena.camera.position=arena.player.position+Vector3(0,1.12,0)+arena.camera.basis.z*30
			if plan.get("side",false):
				arena.camera.rotation_degrees=Vector3(-12,65,0)
				arena.camera.position=arena.player.position+Vector3(0,1.12,0)+arena.camera.basis.z*30
			if plan.get("head",false):
				var staff:Node3D=arena.player_visual.staff_visual
				arena.camera.size=.82*arena.player_visual.MODEL_SCALE
				arena.camera.position=staff.to_global(Vector3(.35,.94,-3))
				arena.camera.look_at(staff.to_global(Vector3(0,.94,0)),staff.global_basis.y.normalized())
			if frame%every==0:
				samples.append({"seconds":frame/60.0,"staff":arena.player_visual.staff_visual.debug_state(),
					"phase":arena.player_visual.clip_time/maxf(arena.player_visual.clip_length,.000001),
					"clip":arena.player_visual._clip,"motion":arena.player_visual._motion_kind,"hp":arena.enemies.target.hp})
				await capture(plan.id+"/%03d.jpg"%(frame/every))
		sequences.append({"id":plan.id,"label":plan.label,"frames":samples.size(),"fps":60/every,"samples":samples})
	var report={"passed":true,"captures":captures,"sequences":sequences,
		"scope":"Actual arena simulation at 60 Hz. Head inspection follows the actual attached staff on a camera-only layer with extra light; enemies and hit FX are excluded from that view. Five independent model stills. No simulation retiming."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CUTTER_REVIEW_COMPLETE captures=",captures)
	arena.free()
	quit(0)
