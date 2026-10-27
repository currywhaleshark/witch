extends SceneTree
const Visual = preload("res://scripts/actor_visual.gd")
var arena: Node3D
var checks: Array = []
var failures: Array = []
var inventory: Array = []
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks.append(label)
	if not value:failures.append(label);push_error(label)

func step(count: int) -> void:
	for i in count:
		await physics_frame
		arena._physics_process(1.0/60.0)

func clear_enemies() -> void:
	for e in arena.enemies.values():e.body.free()
	arena.enemies.clear()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena);arena.set_physics_process(false);arena.muted = true
	await process_frame
	for kind in Visual.FILES:
		var parent := Node3D.new();root.add_child(parent)
		var art: Node3D = Visual.create(parent, kind)
		check(art != null and art.loaded_ok, kind + " generated model and motions load")
		if art == null:continue
		inventory.append(art.debug_state())
		for clip in art.clips:
			for phase in [0.0,0.25,0.5,0.75,1.0]:
				art.sample(clip,phase)
				for index in art.skeleton.get_bone_count():
					var pose: Transform3D = art.skeleton.get_bone_global_pose(index)
					check(pose.origin.is_finite() and pose.basis.is_finite(), "%s/%s/%s bone %d finite" % [kind,clip,phase,index])
				check(parent.position == Vector3.ZERO, kind + " clip never moves the gameplay node")
			if clip in ["idle","move","charge"]:
				art.sample(clip,0)
				var first: Array = []
				for index in art.skeleton.get_bone_count():first.append(art.skeleton.get_bone_global_pose(index))
				art.sample(clip,1)
				for index in art.skeleton.get_bone_count():
					var last: Transform3D = art.skeleton.get_bone_global_pose(index)
					check(first[index].origin.distance_to(last.origin)<0.0001 and first[index].basis.is_equal_approx(last.basis),kind+"/"+clip+" seamless loop "+str(index))
		if kind == "turret":
			var base_pose: Transform3D = art.skeleton.global_transform * art.skeleton.get_bone_global_pose(art.skeleton.find_bone("root"))
			for yaw in [-PI/2,0.0,PI/2,PI]:
				parent.rotation.y=yaw
				art.sync_ally({"node":parent,"cooldown":0.2,"target":""},0.0)
				var base_now: Transform3D = art.skeleton.global_transform * art.skeleton.get_bone_global_pose(art.skeleton.find_bone("root"))
				check(base_pose.basis.is_equal_approx(base_now.basis),"turret tripod stays fixed while aiming "+str(yaw))
				var carriage: Vector3 = art.skeleton.global_transform * art.skeleton.get_bone_global_pose(art.skeleton.find_bone("carriage")).origin
				var direction: Vector3 = art.muzzle_position()-carriage;direction.y=0
				check(direction.normalized().dot(-parent.global_basis.z)>0.97,"turret muzzle faces target "+str(yaw))
		parent.free()
	for kind in ["rag","crow","brute"]:
		arena.reset_arena();clear_enemies();arena.player.position=Vector3.ZERO
		arena.spawn_enemy("art_test",Vector3(0,0,-1.5),false,"normal",kind)
		var enemy: Dictionary = arena.enemies.art_test
		enemy.cooldown=999;enemy.charge_cooldown=999
		arena.start_enemy_attack(enemy,"bolt" if kind=="crow" else "melee",0.4,Color.WHITE)
		await step(25)
		check(enemy.model.release_samples.size()==1 and is_equal_approx(enemy.model.release_samples[0],0.5),kind+" actual release uses phase 0.5")
		arena.paused=true
		var before: Dictionary = enemy.model.debug_state()
		await step(5)
		check(before==enemy.model.debug_state(),kind+" pauses the same pose timeline")
		arena.paused=false
		var art: Node3D = enemy.model
		arena.damage_enemy("art_test",9999)
		check(not arena.enemies.has("art_test"),kind+" lethal damage removes gameplay target immediately")
		check(art.get_parent()==arena.world and art.debug_state().dead,kind+" leaves a visual corpse only")
		check(art.find_children("*","CollisionObject3D",true,false).is_empty(),kind+" corpse has no collision")
		art.set_process(false);arena.paused=true;art._process(.5)
		check(is_zero_approx(art._death_time),kind+" corpse pause respected")
		arena.paused=false;art._process(1.6);await process_frame
		check(not is_instance_valid(art),kind+" corpse cleans up")
	arena.reset_arena()
	for mobile in [true,false]:
		arena.spawn_ally(Vector3.ZERO,mobile,null)
		var ally: Dictionary = arena.allies.back()
		var art: Node3D = ally.node.get_node("ActorVisual")
		check(art.loaded_ok,"actual summon has a generated visual: "+str(mobile))
		arena.damage_ally(ally,9999,"normal")
		check(not arena.allies.has(ally) and art.get_parent()==arena.world,"destroyed summon removes gameplay immediately: "+str(mobile))
	arena.reset_arena()
	check(get_nodes_in_group("actor_corpses").is_empty(),"reset removes remaining corpses")
	var result := {"passed":failures.is_empty(),"checks":checks.size(),"failures":failures,"assets":inventory}
	if output!="":FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("COMBAT_ACTORS_VALIDATION ",JSON.stringify(result))
	arena.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
