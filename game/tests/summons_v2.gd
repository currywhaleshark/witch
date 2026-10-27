extends SceneTree
const Visual = preload("res://scripts/actor_visual.gd")
var arena: Node3D
var output := ""
var checks: Array = []
var failures: Array = []
var metrics: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label); push_error(label)

func parts(art: Node3D) -> Dictionary:
	var result := {}
	for i in art.skeleton.get_bone_count():
		var name: String = art.skeleton.get_bone_name(i)
		if name.begins_with("part_"): result[name] = i
	return result

func world_pose(art: Node3D, i: int) -> Transform3D:
	return art.skeleton.global_transform * art.skeleton.get_bone_global_pose(i)

func geometry(art: Node3D) -> Array:
	var result: Array = []
	for mesh in art.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / positions.size()
			for v in positions.size():
				var slot := -1
				for j in influences:
					if weights[v * influences + j] > 0.00001:
						check(slot == -1, "each runtime vertex has one rigid influence")
						slot = bones[v * influences + j]
				var bone_name: String = mesh.skin.get_bind_name(slot)
				var index: int = art.skeleton.find_bone(bone_name) if bone_name != "" else mesh.skin.get_bind_bone(slot)
				result.append({"bone": index, "local": mesh.skin.get_bind_pose(slot) * positions[v]})
	return result

func clear_field() -> void:
	arena.reset_arena()
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()

func run() -> void:
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.muted = true
	await process_frame
	for kind in ["automaton", "turret"]:
		var parent := Node3D.new(); arena.world.add_child(parent)
		var art: Node3D = Visual.create(parent, kind)
		check(art.loaded_ok, kind + " loads")
		var ids := parts(art)
		check(ids.size() == (13 if kind == "automaton" else 86), kind + " retains separated rigid pieces")
		var points := geometry(art)
		var maximum_basis_error := 0.0
		for clip in art.clips:
			for f in 25:
				art.sample(clip, f / 24.0)
				for index in ids.values():
					var pose := world_pose(art, index)
					var gram := pose.basis.transposed() * pose.basis
					for error in [gram.x.distance_to(Vector3.RIGHT),gram.y.distance_to(Vector3.UP),gram.z.distance_to(Vector3.BACK)]:
						maximum_basis_error = maxf(maximum_basis_error,error)
					check(pose.origin.is_finite() and absf(pose.basis.determinant() - 1.0) < .0001, kind + "/" + clip + " rigid transform")
		check(maximum_basis_error < .0001, kind + " no scaled or sheared part across all clips")
		art.sample("death", 1.0)
		var minimum := INF
		for point in points: minimum = minf(minimum, (world_pose(art, point.bone) * point.local).y)
		check(minimum > -.001, kind + " collapsed pieces stay above floor")
		var collapse_radius := 0.0
		for index in ids.values():
			var p := world_pose(art, index).origin
			collapse_radius = maxf(collapse_radius, Vector2(p.x, p.z).length())
		if kind == "automaton":
			art.sample("explode", .5)
			var scatter_radius := 0.0
			for index in ids.values():
				var p := world_pose(art, index).origin
				scatter_radius = maxf(scatter_radius, Vector2(p.x, p.z).length())
			check(scatter_radius > collapse_radius * 2.0, "self-destruct scatters farther than ordinary collapse")
			metrics["scatter_radius"] = scatter_radius
		else:
			var fixed: Dictionary = {}
			art.sample("idle", 0)
			for index in ids.values():
				if art.skeleton.get_bone_name(art.skeleton.get_bone_parent(index)) == "root": fixed[index] = world_pose(art, index)
			for step in 25:
				parent.rotation.y = step * TAU / 24
				art.sync_ally({"node":parent,"cooldown":.8,"target":""}, 0.0)
				var pivot: Vector3 = world_pose(art,art.skeleton.find_bone("carriage")).origin
				var direction: Vector3 = art.muzzle_position()-pivot; direction.y=0
				check(direction.normalized().dot(-parent.global_basis.z)>.97,"muzzle points at target throughout 360 degree aiming")
				for index in fixed:
					var actual := world_pose(art, index)
					check(actual.origin.distance_to(fixed[index].origin) < .0001 and actual.basis.is_equal_approx(fixed[index].basis), "base pieces stay planted through 360 degree aiming")
		metrics[kind] = {"parts":ids.size(),"maximum_rigid_basis_error":maximum_basis_error,"final_minimum_y":minimum,"collapse_radius":collapse_radius}
		parent.free()
	for mobile in [true,false]:
		for expires in [false,true]:
			clear_field(); arena.force_rolls = {"crit":false}
			arena.spawn_enemy("near",Vector3(1,0,0),false,"normal","brute")
			arena.spawn_enemy("far",Vector3(9,0,0),false,"normal","brute")
			arena.enemies.near.hp = 1000; arena.enemies.far.hp = 1000
			arena.spawn_ally(Vector3.ZERO,mobile,null)
			var ally: Dictionary = arena.allies.back()
			var art: Node3D = ally.node.get_node("ActorVisual")
			ally.node.rotation.y = 1.2
			art.preview_shot(ally); art.sample("attack", .43)
			var before := {}
			for index in parts(art).values(): before[index] = world_pose(art,index)
			if expires:
				ally.life = .001; arena._tick_allies(.01)
			else: arena.damage_ally(ally,9999,"normal")
			var expected := "explode" if mobile and expires else "death"
			check(art.debug_state().death_clip == expected, "correct destruction branch mobile="+str(mobile)+" expires="+str(expires))
			check(arena.allies.is_empty() and art.get_parent() == arena.world, "remove gameplay summon immediately")
			for index in before:
				var after := world_pose(art,index)
				check(after.origin.distance_to(before[index].origin) < .0001 and after.basis.is_equal_approx(before[index].basis), "destruction starts at the current pose")
			check(art.find_children("*","CollisionObject3D",true,false).is_empty(), "debris has no combat collision")
			check(is_equal_approx(arena.enemies.near.hp,1000.0 - (arena.config.shot_damage if mobile and expires else 0.0)), "existing explosion damage and ordinary-destruction distinction preserved")
			check(is_equal_approx(arena.enemies.far.hp,1000.0), "explosion range preserved")
			art.set_process(false);arena.paused=true;art._process(.5)
			check(is_zero_approx(art._death_time), "paused debris stays frozen")
			arena.paused=false
			var rng_state: int = arena.combat_rng.state
			for i in 30: art._process(.02)
			check(arena.combat_rng.state == rng_state, "visual debris never consumes combat RNG")
			art._process(2.0); await process_frame
			check(not is_instance_valid(art), "debris and flash clean up")
	clear_field()
	check(get_nodes_in_group("actor_corpses").is_empty(), "reset clears debris")
	var result := {"passed":failures.is_empty(),"checks":checks.size(),"failures":failures,"metrics":metrics}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SUMMONS_V2_VALIDATION ",JSON.stringify(result))
	arena.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
