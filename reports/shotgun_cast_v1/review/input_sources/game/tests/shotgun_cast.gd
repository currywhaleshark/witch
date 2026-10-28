extends SceneTree
var arena: Node3D
var output := ""
var checks := 0
var failures: Array[String]=[]
var metrics: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func fresh() -> void:
	arena.reset_arena()
	for wall in get_nodes_in_group("shotgun_test_walls"): wall.free()
	for enemy in arena.enemies.values(): enemy.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel",Vector3(18,0,18),false,"normal","brute")
	arena.player.position=Vector3.ZERO
	arena.config.enemy_speed=0.0; arena.config.mana_regen=0.0; arena.config.cast_speed_score=0.0
	arena.force_rolls={"hit":true,"crit":false}; arena.muted=true

func target(id: String, at: Vector3) -> void:
	arena.spawn_enemy(id,at,false,"normal","rag")
	arena.enemies[id].hp=1000.0; arena.enemies[id].cooldown=999.0

func start(cursor: Dictionary={"ground":[5,0,0]}) -> Node3D:
	arena.request_slot("rmb",cursor)
	var fx: Node3D=arena.shotgun_assembly
	check(is_instance_valid(fx),"shotgun windup creates floating parts")
	if is_instance_valid(fx): fx.set_process(false)
	return fx

func poses(fx: Node3D) -> Array:
	var data: Array=[]
	for part in fx.parts: data.append([part.mesh.transform,part.mesh.visible])
	return data

func release() -> void:
	if not arena.windup.is_empty(): arena.tick_windup(float(arena.windup.release)+0.0001)

func wall(at: Vector3, size: Vector3) -> void:
	var body:=StaticBody3D.new(); body.collision_layer=arena.map.WORLD_LAYER; body.collision_mask=0
	var shape:=BoxShape3D.new(); shape.size=size
	var collider:=CollisionShape3D.new(); collider.shape=shape; body.add_child(collider)
	arena.world.add_child(body); body.position=at; body.add_to_group("shotgun_test_walls")

func run() -> void:
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	for score in [0.0,40.0]:
		fresh();arena.config.cast_speed_score=score;target("target",Vector3(4,0,0))
		var mana: float=arena.state.mana
		var fx:=start({"enemy_id":"target"})
		var time: float=arena.windup.release
		check(is_equal_approx(time,arena.cast_seconds(arena.rules.skills.shotgun)*0.5),"original release fraction retained")
		check(fx.parts.size()==40,"40 actual independent cannon parts")
		var triangles:=0
		for part in fx.parts:
			for surface in part.mesh.mesh.get_surface_count(): triangles+=part.mesh.mesh.surface_get_array_index_len(surface)/3
		check(triangles==8732,"derivative keeps 8732 source triangles")
		arena.tick_windup(time*.24)
		check(fx.debug_state().visible_parts>0 and fx.debug_state().visible_parts<40,"receiver and barrel appear in stages")
		check(arena.state.mana==mana and arena.last_shotgun.is_empty() and not fx.debug_state().flash,"no costs or muzzle flash before release")
		arena.tick_windup(time*.75)
		check(arena.enemies.target.hp==1000.0 and arena.last_shotgun.is_empty(),"no damage at 99 percent")
		release()
		check(fx.mode=="fired" and fx.progress==1.0 and arena.shotgun_assembly==null,"successful release completes and detaches one transient gun")
		check(arena.state.mana==mana-10.0 and is_equal_approx(arena.state.cooldowns.shotgun,1.2),"normal cost and cooldown exactly once")
		check(arena.enemies.target.hp==1000.0-arena.config.shot_damage,"unchanged area damage")
		check(fx.global_position.distance_to(arena.last_shotgun.origin)<1e-6,"same world muzzle for model and damage/traces")
		check(fx.debug_state().flash and arena.last_shotgun.ends.size()==7,"release flash and seven fan rays")
		for end in arena.last_shotgun.ends:
			check(Vector2(end.x-arena.player.position.x,end.z-arena.player.position.z).length()<=8.0001,"forward muzzle does not extend 8m range")
		var before:=poses(fx)
		fx.advance(.04)
		check(not fx.parts[0].mesh.transform.is_equal_approx(before[0][0]),"gun recoils after its shot")
		before=poses(fx);arena.paused=true;fx.advance(.5)
		for i in fx.parts.size():check(fx.parts[i].mesh.transform.is_equal_approx(before[i][0]),"pause freezes recoil and dissolve")
		arena.paused=false;fx.advance(.3)
		check(fx.parts[0].materials[0].albedo_color.a<1.0,"spent gun fades")
		fx.advance(.2);await process_frame
		check(not is_instance_valid(fx),"spent gun cleans itself up")
		metrics["fcr_%d"%score]={"release_seconds":time,"origin":arena.last_shotgun.origin,"triangles":triangles}
	for fraction in [.15,.50,.85]:
		fresh();var fx:=start();arena.tick_windup(arena.windup.release*fraction)
		var before:=poses(fx);var mana: float=arena.state.mana
		arena.damage_player(20.0)
		check(fx.mode=="dissolving" and arena.shotgun_assembly==null,"hit stun dissolves unfinished gun")
		for i in fx.parts.size():check(fx.parts[i].mesh.transform.is_equal_approx(before[i][0]) and fx.parts[i].mesh.visible==before[i][1],"cancel preserves current born parts and pose")
		check(arena.state.mana==mana and arena.last_shotgun.is_empty() and not fx.debug_state().flash,"interrupted cast never fires or spends")
		fx.advance(.34);await process_frame
		check(not is_instance_valid(fx),"cancelled airborne parts clean up")
	fresh();var fx:=start();arena.damage_player(1.0)
	check(fx.mode=="assembling" and not arena.windup.is_empty(),"minor hit retains assembly")
	release();check(not arena.last_shotgun.is_empty(),"minor hit still releases")
	fresh();fx=start();arena.state.mana=0.0;release()
	check(fx.mode=="dissolving" and arena.last_shotgun.is_empty(),"failed resource recheck dissolves without firing")
	fresh();fx=start();arena.state=arena.rules.bind(arena.state,"rmb","automaton");release()
	check(fx.mode=="dissolving" and arena.last_shotgun.is_empty(),"changed slot cancels preview")
	fresh();target("target",Vector3(4,0,0));fx=start({"enemy_id":"target"})
	arena.enemies.target.body.position=Vector3(3,0,2);arena.tick_windup(.03)
	var tracked: Transform3D=fx.global_transform
	release();check(fx.global_transform.is_equal_approx(tracked),"moving target muzzle tracks through release without a snap")
	fresh();target("target",Vector3(4,0,0));fx=start({"enemy_id":"target"})
	arena.enemies.target.body.free();arena.enemies.erase("target");release()
	check(fx.mode=="fired" and not arena.last_shotgun.is_empty(),"direction shot keeps last target spot after target dies")
	for distance in [.25,.50,1.0,1.5,4.0,7.99,8.1]:
		fresh();target("target",Vector3(distance,0,0));fx=start();release()
		check((arena.enemies.target.hp<1000.0)==(distance<=8.0),"close targets remain hittable and range is player-relative: %.2f"%distance)
	for angle in [0.0,PI/2,PI,-PI/2]:
		fresh();var direction:=Vector3.RIGHT.rotated(Vector3.UP,angle)
		target("target",direction*4.0);fx=start({"enemy_id":"target"});release()
		check(arena.enemies.target.hp<1000.0,"muzzle follows all four facing directions")
	fresh();wall(Vector3(.9,1.5,0),Vector3(.2,3.0,8.0));target("target",Vector3(3,0,0));await physics_frame
	fx=start({"enemy_id":"target"});release()
	check(arena.enemies.target.hp==1000.0,"wall between muzzle and enemy blocks damage")
	for end in arena.last_shotgun.ends:check(end.x<=.8001,"traces stop at the same front wall")
	fresh();wall(Vector3(0,1.5,.32),Vector3(4,3.0,.1));target("target",Vector3(4,0,0));await physics_frame
	fx=start({"enemy_id":"target"});release()
	check(arena.last_shotgun.origin.z<0.0,"blocked right shoulder uses the clear left side")
	check(arena.enemies.target.hp<1000.0,"safe side placement still hits aim point")
	fresh();fx=start();release();var previous:=fx
	arena.action_time=0.0;arena.state.cooldowns.clear();fx=start()
	check(fx!=previous and previous.mode=="fired" and fx.mode=="assembling","new cast independent of spent gun")
	arena.reset_arena();await process_frame
	check(not is_instance_valid(fx) and not is_instance_valid(previous) and arena.shotgun_assembly==null,"reset removes both active and spent guns")
	var result: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SHOTGUN_CAST_COMPLETE ",JSON.stringify(result))
	arena.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
