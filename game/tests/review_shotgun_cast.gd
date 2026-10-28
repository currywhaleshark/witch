extends SceneTree
const Shape=preload("res://scripts/shapes.gd")
var arena: Node3D
var output := ""
var sequences: Array=[]
var captures:=0

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
	for wall in get_nodes_in_group("shot_review_wall"):wall.free()
	for e in arena.enemies.values():e.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel",Vector3(18,0,18),false,"normal","brute")
	arena.player.position=Vector3.ZERO
	arena.config.enemy_speed=0.0;arena.config.mana_regen=0.0;arena.config.cast_speed_score=0.0
	arena.force_rolls={"hit":true,"crit":false}
	arena.muted=true;arena.help_visible=false;arena._physics_process(0.0)
	arena.hover_ring.visible=false;arena.move_marker.visible=false

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	var plans: Array=[
		{"id":"success_close","label":"조립 → 발사 → 소멸 · 확대","close":true},
		{"id":"success_native","label":"실제 게임 화면","close":false},
		{"id":"side","label":"옆모습 · 총구 위치와 반동","close":true,"side":true},
		{"id":"fast","label":"빠른 시전 · FCR 40","close":true,"fcr":40.0},
		{"id":"cancel","label":"시전 도중 경직 · 발사 없이 해체","close":true,"cancel":true},
		{"id":"near","label":"가까운 적 · 총구를 뒤로 보정","close":true,"distance":0.65},
		{"id":"wall","label":"벽 앞 · 탄선과 피해 차단","close":true,"wall":true}]
	for plan in plans:
		prepare();arena.config.cast_speed_score=float(plan.get("fcr",0.0))
		var target:=Vector3(float(plan.get("distance",3.4)),0,0)
		arena.spawn_enemy("target",target,false,"normal","rag")
		arena.enemies.target.hp=1000.0;arena.enemies.target.max_hp=1000.0;arena.enemies.target.cooldown=999.0
		if plan.get("wall",false):
			var wall:=StaticBody3D.new();wall.collision_layer=arena.map.WORLD_LAYER
			var shape:=BoxShape3D.new();shape.size=Vector3(.2,1.65,2.4)
			var col:=CollisionShape3D.new();col.shape=shape;wall.add_child(col)
			arena.world.add_child(wall);wall.position=Vector3(1.25,.825,0);wall.add_to_group("shot_review_wall")
			Shape.box(wall,Vector3.ZERO,shape.size,Color("657578"))
			await physics_frame
		arena.request_slot("rmb",{"enemy_id":"target"})
		var fx: Node3D=arena.shotgun_assembly
		assert(is_instance_valid(fx));fx.set_process(false)
		var release: float=arena.windup.release
		var interrupted:=false
		var samples: Array=[]
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		for frame in 49:
			if frame>0:
				await physics_frame
				if plan.get("cancel",false) and not interrupted and frame/60.0>=release*.50:
					arena.damage_player(20.0);interrupted=true
				arena._physics_process(1.0/60.0)
				if is_instance_valid(fx):fx.advance(1.0/60.0)
			arena.hud.visible=not plan.close
			arena.hover_ring.visible=false;arena.move_marker.visible=false
			if plan.close:
				arena.camera.rotation_degrees=Vector3(-18 if plan.get("side",false) else -28,160 if plan.get("side",false) else 135,0)
				arena.camera.size=4.5 if plan.get("wall",false) else 3.6
				arena.camera.position=Vector3(.75,.72,.1)+arena.camera.basis.z*30
			else:
				arena.camera.rotation_degrees=Vector3(-30,45,0)
				arena.camera.size=20.0/1.75*arena.player_visual.MODEL_SCALE
				arena.place_camera(arena.player.position)
			var sample: Dictionary={"frame":frame,"seconds":frame/60.0,"mana":arena.state.mana,
				"target_hp":arena.enemies.target.hp,"fired":not arena.last_shotgun.is_empty()}
			if is_instance_valid(fx):sample.merge(fx.debug_state())
			samples.append(sample)
			await capture(plan.id+"/%03d.jpg"%frame)
		sequences.append({"id":plan.id,"label":plan.label,"frames":49,"fps":60,"release_seconds":release,
			"cancelled":plan.get("cancel",false),"wall":plan.get("wall",false),"fcr":plan.get("fcr",0.0),"samples":samples})
	prepare();arena.player.visible=false;arena.hud.visible=false
	arena.begin_shotgun_visual(Vector3(4,0,0))
	var model: Node3D=arena.shotgun_assembly
	model.global_transform=Transform3D(Basis(Vector3.UP,deg_to_rad(-35)),Vector3.UP)
	model.sample_progress(1.0);model._light(1.0,0.0)
	arena.camera.rotation_degrees=Vector3(-20,20,0);arena.camera.size=1.4
	arena.camera.position=Vector3(0,1,.35)+arena.camera.basis.z*30
	await capture("model.jpg")
	var result: Dictionary={"passed":true,"captures":captures,"sequences":sequences,
		"scope":"Actual arena windup/release/damage/interruption at 60Hz, plus one complete model view. No retimed gameplay; slow playback is a review-page control."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SHOTGUN_REVIEW_COMPLETE captures=",captures)
	arena.queue_free();await process_frame;quit(0)
