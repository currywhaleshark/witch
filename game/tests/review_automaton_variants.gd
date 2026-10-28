extends SceneTree
var arena: Node3D
var output := ""
var sequences: Array = []
var capture_count := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_jpg(output.path_join(path),0.94)==OK)
	capture_count += 1

func prepare() -> void:
	arena.reset_arena()
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel",Vector3(18,0,18),false,"normal","brute")
	arena.config.enemy_speed=0.0; arena.config.mana_regen=0.0; arena.config.cast_speed_score=0.0; arena.config.automaton_node="base"
	arena.player.position=Vector3.ZERO
	arena.muted=true; arena.hover_ring.visible=false; arena.move_marker.visible=false
	arena.help_visible=false; arena._physics_process(0.0)

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.set_process_input(false); arena.set_process_unhandled_input(false)
	await process_frame
	var plans: Array = [
		{"id":"a_assemble","label":"A 자폭형 · 조립","node":"A","cancel":-1.0,"close":true,"speed":0.0,"seconds":1.2},
		{"id":"b_assemble","label":"B 절삭형 · 조립","node":"B","cancel":-1.0,"close":true,"speed":0.0,"seconds":1.2},
		{"id":"a_cancel","label":"A 자폭형 · 시전 중단","node":"A","cancel":0.65,"close":true,"speed":0.0,"seconds":2.2},
		{"id":"b_cancel","label":"B 절삭형 · 시전 중단","node":"B","cancel":0.65,"close":true,"speed":0.0,"seconds":2.2},
		{"id":"a_attack","label":"A 자폭형 · 접근과 폭발","node":"A","cancel":-1.0,"close":true,"speed":0.0,"seconds":3.4,"fight":true},
		{"id":"b_attack","label":"B 절삭형 · 반복 공격","node":"B","cancel":-1.0,"close":true,"speed":0.0,"seconds":3.4,"fight":true},
		{"id":"a_native","label":"A 자폭형 · 실제 화면","node":"A","cancel":-1.0,"close":false,"speed":0.0,"seconds":1.2},
		{"id":"b_native","label":"B 절삭형 · 실제 화면","node":"B","cancel":-1.0,"close":false,"speed":0.0,"seconds":1.2},
		{"id":"a_fuse","label":"A 심지 소모 · 적 접근 없이 수명 경과 6배","node":"A","cancel":-1.0,"close":true,"speed":0.0,"seconds":4.0,"time_scale":6.0}]
	for plan in plans:
		prepare(); arena.config.cast_speed_score=plan.speed; arena.config.automaton_node=plan.node
		if plan.get("fight",false):
			arena.spawn_enemy("target",Vector3(3.3,0,0.6),false,"normal","rag")
			arena.enemies.target.hp=9999; arena.enemies.target.cooldown=9999
		arena.request_slot("w",{"enemy_id":"target"} if plan.get("fight",false) else {"ground":[4,0,0]})
		var fx: Node3D = arena.automaton_assembly
		assert(is_instance_valid(fx))
		var anchor: Vector3 = fx.global_position
		fx.set_process(false)
		var release: float = arena.windup.release
		var interrupted := false
		var frames: int = ceili(float(plan.seconds)*30.0)+1
		var samples: Array = []
		DirAccess.make_dir_recursive_absolute(output.path_join(plan.id))
		for frame in frames:
			if frame>0:
				await physics_frame
				if plan.cancel>=0.0 and not interrupted and frame/30.0>=release*float(plan.cancel):
					arena.damage_player(20.0); interrupted=true
				arena._physics_process(float(plan.get("time_scale",1.0))/30.0)
				if is_instance_valid(fx): fx.advance(float(plan.get("time_scale",1.0))/30.0)
				for corpse in get_nodes_in_group("actor_corpses"):
					corpse.set_process(false); corpse._process(float(plan.get("time_scale",1.0))/30.0)
			arena.hud.visible=not plan.close
			arena.hover_ring.visible=false; arena.move_marker.visible=false
			if plan.close:
				arena.camera.rotation_degrees=Vector3(-25,135,0)
				arena.camera.size=3.3 if not plan.get("fight",false) else 4.8
				arena.camera.position=Vector3(0.55 if not plan.get("fight",false) else 1.6,0.65,0.30)+arena.camera.basis.z*30.0
			else:
				arena.camera.rotation_degrees=Vector3(-30,45,0)
				arena.camera.size=20.0/1.75*arena.player_visual.MODEL_SCALE
				arena.place_camera(arena.player.position)
			var sample: Dictionary = {"frame":frame,"seconds":frame/30.0,"simulation_seconds":frame/30.0*float(plan.get("time_scale",1.0)),"allies":arena.allies.size(),"mana":arena.state.mana,"hp":arena.hp}
			if not arena.allies.is_empty():
				var ally: Dictionary = arena.allies[0]
				sample["ally_position"] = [ally.node.global_position.x, ally.node.global_position.y, ally.node.global_position.z]
				sample["anchor_drift_m"] = ally.node.global_position.distance_to(anchor)
				sample["ally_visual_state"] = ally.node.get_node("ActorVisual").visual_state
				sample["appearance"]=ally.node.get_node("ActorVisual").debug_state()
			if is_instance_valid(fx): sample.merge(fx.debug_state())
			samples.append(sample)
			await capture(plan.id+"/%03d.jpg"%frame)
		sequences.append({"id":plan.id,"label":plan.label,"frames":frames,"fps":30,"release_seconds":release,
			"cancel_at_fraction":plan.cancel,"fcr":plan.speed,"variant":plan.node,"fight":plan.get("fight",false),"time_scale":plan.get("time_scale",1.0),"samples":samples})
	prepare(); arena.player.visible=false; arena.hud.visible=false
	for entry in [["base",1.1],["A",0.0],["B",-1.1]]:
		arena.config.automaton_node=entry[0]
		arena.spawn_ally(Vector3(entry[1],0,0),true,"")
		arena.allies[-1].node.rotation.y=deg_to_rad(-25)
	for effect in arena.effects: effect.node.free()
	arena.effects.clear(); arena.hover_ring.visible=false; arena.move_marker.visible=false
	arena.camera.rotation_degrees=Vector3(-18,180,0); arena.camera.size=3.9
	arena.camera.position=Vector3(0,0.48,0)+arena.camera.basis.z*30.0
	await capture("lineup.jpg")
	var result: Dictionary = {"passed":true,"captures":capture_count,"sequences":sequences,
		"scope":"Actual arena casts/hit-stun and renderer at 30 samples/sec; preview's post-cancel clock is advanced explicitly for deterministic capture. Existing combat timing unchanged."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("AUTOMATON_VARIANTS_REVIEW_COMPLETE captures=",capture_count)
	arena.queue_free(); await process_frame; quit(0)
