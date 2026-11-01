extends SceneTree
const Spring = preload("res://scripts/spring_plate.gd")
var arena:Node3D
var output:=""
var checks:Array=[]
var failures:Array=[]
var cases:Array=[]
var wire_error:=0.
var anchor_error:=0.
var guide_overlap:=INF
var rendered_triangles:=0
var fps:=60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks.append(label)
	if not ok:failures.append(label)

func plates() -> Array:
	return get_nodes_in_group("spring_plates").filter(func(n):return is_instance_valid(n) and not n.is_queued_for_deletion())

func step(count:int=1) -> void:
	for i in count:
		var running:Array=[]
		for p in plates():
			p.set_process(false)
			if p.mode!="assembling":running.append(p)
		await physics_frame
		arena._physics_process(1./fps)
		for p in running:
			if is_instance_valid(p) and not p.is_queued_for_deletion():p.advance(1./fps)
		await process_frame

func fresh(rate:int=60,fcr:float=0.,at:Vector3=Vector3.ZERO) -> void:
	fps=rate;Engine.physics_ticks_per_second=fps
	arena.reset_arena();arena.player.position=arena.map.grounded(at)
	for e in arena.enemies.values():e.body.free()
	arena.enemies.clear();arena.spawn_enemy("sentinel",at+Vector3(0,0,8),false)
	arena.enemies.sentinel.cooldown=999.
	arena.config.enemy_speed=0.;arena.config.mana_regen=0.;arena.config.cast_speed_score=fcr
	arena.config.max_hp=100.;arena.hp=100.;arena.shield_time=0.;arena.muted=true
	arena.bind_slot("q","spring_dash")
	await step(2)

func request() -> Node3D:
	var origin:Vector3=arena.player.position
	arena.request_slot("q",{"ground":[origin.x+5.,0.,origin.z]})
	var p:Node3D=arena.spring_plate
	if is_instance_valid(p):p.set_process(false)
	return p

func transforms(p:Node3D) -> Array:
	return p.parts.map(func(x):return x.mesh.transform)

func measure_wire(p:Node3D) -> void:
	var cfg:Dictionary=p.spec.coil
	var arrays:Array=p._coil_mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in range(0,int(cfg.steps)+1,7):
		var angle:float=TAU*float(cfg.turns)*i/float(cfg.steps)
		var center:=Vector3(cos(angle)*float(cfg.radius),p._coil_height*i/float(cfg.steps),sin(angle)*float(cfg.radius))
		for j in int(cfg.sides):wire_error=maxf(wire_error,absf(vertices[i*int(cfg.sides)+j].distance_to(center)-float(cfg.wire_radius)))
	if p.mode=="launched" and p._end_time<=.14:
		var ranges:Dictionary={}
		for part in p.parts:
			if not str(part.name).begins_with("guide_"):continue
			var lo:=INF;var hi:=-INF
			for corner in part.corners:
				var y:float=(part.mesh.transform*corner).y
				lo=minf(lo,y);hi=maxf(hi,y)
			ranges[part.name]=Vector2(lo,hi)
		for side in ["L","R"]:
			guide_overlap=minf(guide_overlap,minf(ranges["guide_sleeve_"+side].y-ranges["guide_middle_"+side].x,ranges["guide_middle_"+side].y-ranges["guide_rod_"+side].x))

func run() -> void:
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat")
	for rate in [30,60]:
		for fcr in [0.,40.]:
			await fresh(rate,fcr)
			var start:Vector3=arena.player.position
			var mana:float=arena.state.mana
			var sound_before:int=arena.sound_index
			var p:Node3D=request()
			check(is_instance_valid(p),"%d fps FCR %d starts a plate with windup"%[rate,fcr])
			if not is_instance_valid(p):continue
			var origin:Vector3=p.global_position
			var release:float=arena.windup.release
			check(p.parts.size()==29 and p.launch_count==0,"29 independent parts exist before release")
			var frame:=0
			while p.mode=="assembling" and frame<20:
				await step();frame+=1
				anchor_error=maxf(anchor_error,p.global_position.distance_to(origin));measure_wire(p)
				if p.mode=="assembling":check(arena.dash.is_empty() and is_equal_approx(arena.state.mana,mana),"assembly does not move or spend before release")
			check(p.mode=="launched" and p.launch_count==1,"successful release launches once")
			check(frame==int(ceil(release*rate-.000001)),"visual introduces no release delay")
			check(p.debug_state().visible_parts==29 and p.lift==0.,"release has a complete compressed mechanism")
			rendered_triangles=0
			for part in p.parts:
				for surface in part.mesh.mesh.get_surface_count():
					var mesh_arrays:Array=part.mesh.mesh.surface_get_arrays(surface)
					rendered_triangles+=mesh_arrays[Mesh.ARRAY_INDEX].size()/3 if mesh_arrays[Mesh.ARRAY_INDEX]!=null else mesh_arrays[Mesh.ARRAY_VERTEX].size()/3
			check(is_equal_approx(mana-arena.state.mana,arena.rules.skills.spring_dash.mana_cost),"dash mana cost stays owned by the arena")
			check(arena.state.cooldowns.get("spring_dash",0.)>0.,"dash cooldown still starts on release")
			var max_lift:=0.
			for i in int(1.1*rate):
				await step()
				if is_instance_valid(p):
					max_lift=maxf(max_lift,p.lift);measure_wire(p)
					anchor_error=maxf(anchor_error,p.global_position.distance_to(origin))
			check(not is_instance_valid(p) and plates().is_empty(),"launched plate completely cleans up")
			check(max_lift>.18,"spring reaches its visible extended stroke")
			check(arena.player.position.x-start.x>4.7 and arena.dash.is_empty(),"the existing 5m dash completes")
			check(arena.sound_index==sound_before,"mute suppresses the mechanism cue")
			cases.append({"fps":rate,"fcr":fcr,"release_seconds":release,"release_frame":frame,"max_lift":max_lift,"distance":arena.player.position.distance_to(start),"origin":[origin.x,origin.y,origin.z]})
	await fresh()
	var p:Node3D=request();await step()
	var before:Array=transforms(p);var progress:float=p.progress;var at:Vector3=arena.player.position
	arena.paused=true;await step(5)
	check(transforms(p)==before and p.progress==progress and arena.player.position==at,"pause freezes incomplete assembly and player")
	arena.paused=false;await step(5)
	before=transforms(p);var elapsed:float=p._end_time
	arena.paused=true;await step(8)
	check(transforms(p)==before and p._end_time==elapsed,"pause freezes spring recoil and dissolve")
	arena.paused=false;await step(70)
	check(plates().is_empty(),"resume finishes cleanup")
	for reason in ["hit","cost","binding","death"]:
		await fresh();var mana:float=arena.state.mana
		p=request();await step()
		match reason:
			"hit":arena.damage_player(20.,"normal")
			"cost":arena.state.mana=0.
			"binding":arena.state.bindings.q="grinder"
			"death":arena.damage_player(200.,"normal")
		# Cost/binding are rechecked at release; assembly may continue until that check.
		while p.mode=="assembling":await step()
		var visible:int=p.debug_state().visible_parts
		await step(4)
		check(p.mode=="cancelled" and p.launch_count==0 and arena.dash.is_empty(),reason+" cancels without spring actuation")
		check(p.debug_state().visible_parts<=visible,reason+" creates no additional parts after cancellation")
		if reason!="cost":check(is_equal_approx(arena.state.mana,mana),reason+" spends no dash mana")
		await step(20);check(not is_instance_valid(p),reason+" removes cancelled fragments")
	await fresh();p=request();await step();arena.damage_player(1.,"normal");await step(5)
	check(is_instance_valid(p) and p.mode=="launched","minor hits retain the existing cast continuation")
	await fresh();arena.state.mana=0.;arena.request_slot("q",{"ground":[5,0,0]})
	check(plates().is_empty(),"failed availability creates no plate")
	await fresh();p=request();await step();arena.reset_arena()
	check(not is_instance_valid(p) and plates().is_empty(),"reset clears incomplete mechanisms")
	await fresh();p=request();await step(6);arena.load_map("alley_v2")
	check(not is_instance_valid(p) and plates().is_empty(),"map changes clear released mechanisms")
	await fresh(60,0.,Vector3(33,0,0));p=request()
	check(absf(p.global_position.y-1.2)<.0001,"plate anchors to the raised floor height")
	await step(80)
	check(plates().is_empty(),"raised-floor cast completes cleanup")
	arena.load_map("flat");await fresh();arena.muted=false
	var sound_before:int=arena.sound_index
	var sfx_before:int=arena.sfx.history.count("spring_dash") if arena.sfx else 0
	arena.start_dash(Vector3(3,0,0),Vector3.RIGHT,false)
	p=plates()[0];p.set_process(false)
	check(p.mode=="launched" and p.launch_count==1 and p.progress==1. and not arena.dash.is_empty(),"immediate release path needs no extra visual windup")
	# The named spring cue replaces the old pitched impact when its file is present.
	var sfx_heard:int=(arena.sfx.history.count("spring_dash") if arena.sfx else 0)-sfx_before
	check(sfx_heard+arena.sound_index-sound_before==1,"one existing mechanical cue plays on launch")
	var first_origin:Vector3=p.global_position
	arena.player.position=Vector3(2,0,0);arena.start_dash(Vector3(4,0,0),Vector3.RIGHT,false)
	check(plates().size()==2 and p.global_position==first_origin,"multiple launched plates retain independent origins")
	arena.reset_arena();check(plates().is_empty(),"reset clears every simultaneous plate")
	check(wire_error<.000002,"spring compression preserves circular wire radius within 0.002mm")
	check(anchor_error<.000001,"assembly/recoil stays at the captured launch origin")
	check(guide_overlap>.004,"telescopic guide sections retain at least 4mm overlap during the stroke")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,"wire_radius_max_error_m":wire_error,"anchor_max_error_m":anchor_error,"minimum_guide_overlap_m":guide_overlap,"runtime_part_triangles":rendered_triangles}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SPRING_PLATE_TEST_COMPLETE checks=",checks.size()," failures=",failures," wire_error=",wire_error)
	arena.free();quit(0 if failures.is_empty() else 1)
