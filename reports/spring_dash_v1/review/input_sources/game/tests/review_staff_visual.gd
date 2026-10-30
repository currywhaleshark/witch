extends SceneTree
const Staff = preload("res://scripts/staff_visual.gd")
var arena: Node3D
var output := ""
var captures := 0
var sequences: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_jpg(output.path_join(path),.94)==OK)
	captures+=1

func prepare() -> void:
	arena.reset_arena()
	for enemy in arena.enemies.values():enemy.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel",Vector3(18,0,18),false,"normal","brute")
	arena.player.position=Vector3.ZERO
	arena.config.enemy_speed=0.0
	arena.config.mana_regen=0.0
	arena.config.attack_speed_score=0.0
	arena.config.cast_speed_score=0.0
	arena.state.mana=999.0
	arena.state=arena.rules.bind(arena.state,"r","grinder")
	arena.state=arena.rules.bind(arena.state,"e","chainsaw")
	arena.force_rolls={"hit":true,"crit":false}
	arena.muted=true
	arena.help_visible=false
	arena._physics_process(0.0)
	arena.hover_ring.visible=false
	arena.move_marker.visible=false

func frame_camera(native: bool) -> void:
	arena.hud.visible=native
	arena.hover_ring.visible=false
	arena.move_marker.visible=false
	if native:
		arena.camera.rotation_degrees=Vector3(-30,45,0)
		arena.camera.size=20.0/1.75*arena.player_visual.MODEL_SCALE
		arena.place_camera(arena.player.position)
	else:
		arena.camera.rotation_degrees=Vector3(-18,155,0)
		arena.camera.size=2.5
		arena.camera.position=arena.player.position+Vector3(0,.85,0)+arena.camera.basis.z*30

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
	var preview:=Node3D.new()
	arena.add_child(preview)
	var studio:=DirectionalLight3D.new()
	studio.rotation_degrees=Vector3(-30,160,0)
	studio.light_energy=1.7
	preview.add_child(studio)
	var models: Array=[]
	var labels: Array=[]
	for i in 4:
		var model:=Staff.new()
		preview.add_child(model)
		assert(model.initialize())
		model.position=Vector3((1.5-i)*.54,.50,0)
		model.set_tool(null if i==0 else Staff.TOOLS[i-1])
		model.finish_assembly()
		model.advance(.5,false)
		models.append(model)
		var label:=Label3D.new()
		label.text=["BASE","BOLT CUTTER","GRINDER","CHAINSAW"][i]
		label.font_size=32
		label.pixel_size=.0015
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.position=model.position+Vector3(0,-.51,0)
		preview.add_child(label)
		labels.append(label)
	arena.camera.size=2.9
	arena.camera.position=Vector3(1.5,1.25,-7)
	arena.camera.look_at(Vector3(0,.77,0))
	await capture("lineup.jpg")
	for i in 4:
		for j in 4:models[j].visible=i==j;labels[j].visible=false
		var model:Node3D=models[i]
		model.position=Vector3(0,.50,0)
		arena.camera.size=1.68
		arena.camera.position=Vector3(.7,1.15,-4)
		arena.camera.look_at(Vector3(0,.83,0))
		await capture("model_%d.jpg"%i)
	models[3].visible=false
	models[0].visible=true
	models[0].set_appearance("seal")
	arena.camera.size=.62
	arena.camera.position=Vector3(.45,1.15,-3)
	arena.camera.look_at(Vector3(0,1.10,0))
	await capture("ornament.jpg")
	for node in models+labels:node.free()
	preview.free()
	arena.world.visible=true
	var plans: Array=[
		{"id":"cutter","label":"볼트커터 · 부품 생성과 조립","tool":"q"},
		{"id":"grinder","label":"그라인더 · 구동부와 원판","tool":"r"},
		{"id":"chainsaw","label":"전기톱 · 가이드와 체인","tool":"e"},
		{"id":"rapid","label":"공구 연속 전환 · 장식 유지","rapid":true},
		{"id":"run","label":"이동 중 전개와 해제","run":true},
		{"id":"run_side","label":"달리기 · 다른 각도","run":true,"side":true},
		{"id":"attack","label":"볼트커터 · 실제 타격","attack":true},
		{"id":"attack_grinder","label":"그라인더 · 실제 타격","attack":true,"tool":"r"},
		{"id":"attack_chainsaw","label":"전기톱 · 실제 타격","attack":true,"tool":"e"},
		{"id":"native","label":"실제 게임 크기 · 전개와 타격","attack":true,"native":true},
		{"id":"cast_hit","label":"한 손 시전과 피격 · 장식 유지","cast_hit":true}]
	for plan in plans:
		prepare()
		arena.player_visual.set_staff_appearance("seal" if plan.id in ["rapid","cast_hit"] else "basic")
		arena.spawn_enemy("target",Vector3(1.65,0,0),false,"normal","rag")
		arena.enemies.target.hp=10000.0
		arena.enemies.target.max_hp=10000.0
		arena.enemies.target.cooldown=999.0
		arena.player_model.look_at(Vector3(1,0,0))
		var frames:int=91 if plan.get("attack",false) or plan.get("run",false) or plan.id in ["rapid","cast_hit"] else 46
		var samples:Array=[]
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		for frame in frames:
			if frame==5:
				arena.request_slot(plan.get("tool","q"),{})
				if plan.get("run",false):arena.set_destination(Vector3(-4,0,-2))
			if plan.get("rapid",false):
				if frame==10:arena.request_slot("r",{})
				if frame==15:arena.request_slot("e",{})
				if frame==20:arena.request_slot("q",{})
				if frame==55:arena.request_slot("q",{})
			if plan.get("run",false):
				if frame==25:arena.request_slot("r",{})
				if frame==45:arena.request_slot("e",{})
				if frame==70:arena.request_slot("e",{})
			if plan.get("attack",false):
				if frame==15:arena.request_slot("lmb",{"enemy_id":"target"})
			if plan.get("cast_hit",false):
				if frame==20:arena.request_slot("rmb",{"enemy_id":"target"})
				if frame==45:arena.damage_player(20.0)
				if frame==70:arena.state.mana=0.0
			await physics_frame
			arena._physics_process(1.0/60.0)
			frame_camera(plan.get("native",false))
			if plan.get("side",false):
				arena.camera.rotation_degrees=Vector3(-12,65,0)
				arena.camera.position=arena.player.position+Vector3(0,.85,0)+arena.camera.basis.z*30
			if frame%2==0:
				samples.append({"seconds":frame/60.0,"staff":arena.player_visual.staff_visual.debug_state(),
					"clip":arena.player_visual._clip,"motion":arena.player_visual._motion_kind,"hp":arena.enemies.target.hp})
				await capture(plan.id+"/%03d.jpg"%(frame/2))
		sequences.append({"id":plan.id,"label":plan.label,"frames":samples.size(),"fps":30,"samples":samples})
	var report={"passed":true,"captures":captures,"sequences":sequences,
		"scope":"Actual arena at 60 Hz, captured every second frame at 30 fps. No simulation time scaling. Separate model stills."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STAFF_REVIEW_COMPLETE captures=",captures)
	arena.free()
	quit(0)
