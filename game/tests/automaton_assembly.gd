extends SceneTree
const Visual = preload("res://scripts/actor_visual.gd")
var arena: Node3D
var output := ""
var failures: Array[String] = []
var checks := 0
var metrics: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func fresh() -> void:
	arena.reset_arena()
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel", Vector3(18,0,18), false, "normal", "brute")
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0.0; arena.config.mana_regen = 0.0
	arena.config.cast_speed_score = 0.0
	arena.muted = true

func start(cursor: Dictionary = {"ground":[4,0,0]}) -> Node3D:
	arena.request_slot("w", cursor)
	var fx: Node3D = arena.automaton_assembly
	check(is_instance_valid(fx), "cast creates assembly preview")
	fx.set_process(false)
	return fx

func poses(fx: Node3D) -> Array:
	var result: Array = []
	for p in fx.parts: result.append([p.mesh.transform, p.mesh.visible])
	return result

func check_same_pose(fx: Node3D, before: Array, label: String) -> void:
	for i in fx.parts.size():
		check(fx.parts[i].mesh.transform.is_equal_approx(before[i][0]) and fx.parts[i].mesh.visible == before[i][1], label)

func run() -> void:
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.muted = true
	await process_frame
	for score in [0.0,40.0]:
		fresh(); arena.config.cast_speed_score = score
		var fx := start()
		var origin: Vector3 = fx.global_position
		var release: float = arena.cast_seconds(arena.rules.skills.automaton) * 0.85
		var mana: float = arena.state.mana
		var rng_state: int = arena.combat_rng.state
		check(fx.parts.size()==13,"all 13 separated parts retained")
		var triangles := 0
		for p in fx.parts:
			for s in p.mesh.mesh.get_surface_count():
				triangles += p.mesh.mesh.surface_get_array_index_len(s) / 3
		check(triangles==9791,"same 9791 triangles as accepted model")
		arena.tick_windup(release * 0.48)
		check(arena.allies.is_empty(),"preview cannot act or be an enemy target")
		check(arena.state.mana==mana and arena.state.cooldowns.get("automaton",0.0)==0.0,"assembly spends nothing before release")
		check(fx.debug_state().visible_parts>0 and fx.debug_state().visible_parts<13,"parts appear in stages")
		arena.tick_windup(release * 0.51)
		check(arena.allies.is_empty(),"no premature ally at 99 percent of release")
		arena.tick_windup(release * 0.02)
		check(arena.allies.size()==1 and arena.automaton_assembly==null,"successful release creates exactly one ally")
		check(fx.mode=="complete" and fx.progress==1.0,"assembly reaches complete at existing release")
		check(arena.allies[0].node.global_position.distance_to(origin)<0.00001,"ally replaces assembly at same fixed origin")
		check(is_equal_approx(arena.state.mana,mana-arena.rules.skills.automaton.mana_cost) and arena.state.cooldowns.automaton==arena.rules.skills.automaton.cooldown_seconds,"normal cost and cooldown only once")
		check(arena.combat_rng.state==rng_state,"effect consumes no combat RNG")
		# Independently compare the completed static pieces with real skinned idle vertices.
		var art: Node3D = arena.allies[0].node.get_node("ActorVisual")
		art.sample("idle",0.0)
		var expected := {}
		for mesh in art.find_children("*","MeshInstance3D",true,false):
			if mesh.skin==null: continue
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var influences: int = bones.size()/vertices.size()
				for i in vertices.size():
					var bind: int = bones[i*influences]
					var index: int = art.skeleton.find_bone(mesh.skin.get_bind_name(bind))
					var v: Vector3 = art.skeleton.global_transform * art.skeleton.get_bone_global_pose(index) * mesh.skin.get_bind_pose(bind) * vertices[i]
					var key := Vector3i((v*10000.0).round())
					if not expected.has(key): expected[key]=[]
					expected[key].append(v)
		var unmatched := 0
		var sampled := 0
		var maximum_error := 0.0
		for p in fx.parts:
			for surface in p.mesh.mesh.get_surface_count():
				for v in p.mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					sampled += 1
					var point: Vector3 = p.mesh.global_transform*v
					var key := Vector3i((point*10000.0).round())
					var nearest := INF
					for candidate in expected.get(key,[]): nearest=minf(nearest,point.distance_to(candidate))
					if nearest>0.00002:
						for x in [-1,0,1]:
							for y in [-1,0,1]:
								for z in [-1,0,1]:
									for candidate in expected.get(key+Vector3i(x,y,z),[]): nearest=minf(nearest,point.distance_to(candidate))
					maximum_error=maxf(maximum_error,nearest)
					if nearest>0.0002: unmatched+=1
		check(unmatched==0,"assembled surface matches real idle within 0.2mm")
		metrics["fcr_%d"%score]={"release_seconds":release,"surface_samples":sampled,"unmatched":unmatched,"maximum_surface_error_m":maximum_error}
		fx.advance(0.3); await process_frame
		check(not is_instance_valid(fx),"successful preview cleans up")
	for phase in [0.15,0.5,0.85]:
		fresh(); var fx := start(); var mana: float = arena.state.mana
		arena.tick_windup(float(arena.windup.release)*phase)
		var before := poses(fx)
		var visible_count: int = fx.debug_state().visible_parts
		arena.damage_player(20.0)
		check(arena.windup.is_empty() and arena.allies.is_empty(),"hit stun cancels summon")
		check(fx.mode=="collapse" and fx.cancel_reason=="hit_stun","hit selects incomplete collapse")
		check_same_pose(fx,before,"cancel preserves exact pose and born parts")
		arena.paused = true; fx.advance(0.25)
		check_same_pose(fx,before,"pause freezes falling pieces")
		arena.paused = false
		for frame in 60: fx.advance(1.0/60.0)
		check(fx.debug_state().visible_parts==visible_count,"cancel never generates hidden parts")
		for p in fx.parts:
			if not p.mesh.visible: continue
			for corner in p.corners: check((p.mesh.global_transform*corner).y>=-0.001,"falling parts stay above floor")
		check(arena.state.mana==mana and arena.state.cooldowns.get("automaton",0)==0,"cancel spends no mana or cooldown")
		check(arena.allies.is_empty() and arena.bolts.is_empty(),"collapsed preview never attacks or explodes")
		metrics["cancel_%d"%roundi(phase*100)]={"born_parts":visible_count,"mode":fx.mode}
		fx.advance(0.8); await process_frame
		check(not is_instance_valid(fx),"cancelled debris cleans up")
	fresh(); var fx := start(); arena.tick_windup(0.1)
	arena.damage_player(1.0)
	check(fx.mode=="assembling" and not arena.windup.is_empty(),"small hit preserves casting")
	arena.shield_time=1.0; var shield: Dictionary = arena.rules.skills.shield
	var base: float = shield.block_base; var cap: float = shield.block_cap
	shield.block_base=1.0; shield.block_cap=1.0
	arena.damage_player(20.0)
	check(fx.mode=="assembling" and not arena.windup.is_empty(),"blocked hit preserves casting")
	shield.block_base=base; shield.block_cap=cap
	var before := poses(fx); arena.paused=true; arena._physics_process(0.2)
	check_same_pose(fx,before,"pause freezes assembly windup")
	arena.paused=false; arena.reset_arena(); await process_frame
	check(not is_instance_valid(fx) and get_nodes_in_group("cast_assemblies").is_empty(),"reset deletes all assembly nodes")
	for reason in ["death","binding_changed","release_failed","target_lost","field_cleared"]:
		fresh()
		if reason=="target_lost":
			arena.spawn_enemy("target",Vector3(3,0,0),false,"normal","brute")
			fx=start({"enemy_id":"target"})
		else: fx=start()
		arena.tick_windup(0.15)
		match reason:
			"death": arena.damage_player(999.0)
			"binding_changed": arena.state=arena.rules.bind(arena.state,"w","turret"); arena.tick_windup(1.0)
			"release_failed": arena.state.mana=0.0; arena.tick_windup(1.0)
			"target_lost": arena.enemies.target.body.free(); arena.enemies.erase("target"); arena.tick_windup(1.0)
			"field_cleared":
				for e in arena.enemies.values(): e.body.free()
				arena.enemies.clear(); arena._physics_process(0.0)
		check(fx.mode=="collapse" and fx.cancel_reason==reason,"cancel lifecycle: "+reason)
		check(arena.allies.is_empty() and arena.automaton_assembly==null,"no orphan preview or ally: "+reason)
	fresh(); fx=start(); arena.load_map("flat"); await process_frame
	check(not is_instance_valid(fx),"map change removes assembly")
	fresh(); fx=start(); arena.tick_windup(0.2); arena.damage_player(20.0)
	var old_debris := fx
	arena.action_time=0.0; arena.stun_time=0.0
	fx=start()
	check(fx!=old_debris and old_debris.mode=="collapse" and fx.mode=="assembling","recast is independent of old falling parts")
	arena.tick_windup(1.0)
	arena.damage_player(20.0)
	check(arena.allies.size()==1 and fx.mode=="complete","hit after release preserves the already summoned ally")
	var result: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("AUTOMATON_ASSEMBLY_COMPLETE ",JSON.stringify(result))
	arena.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
