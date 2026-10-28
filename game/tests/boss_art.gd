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

func check(value: bool, label: String) -> void:
	checks.append(label)
	if not value: failures.append(label); push_error(label)

func step() -> void:
	await physics_frame
	arena._physics_process(1.0 / 60.0)

func fresh() -> Dictionary:
	arena.reset_arena()
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()
	arena.player.position = Vector3(0, 0, -2.5)
	arena.config.enemy_speed = 0
	arena.spawn_enemy("art_boss", Vector3.ZERO, true, "boss", "latch")
	return arena.enemies.art_boss

func rigid_geometry(model: Node3D, skel: Skeleton3D) -> Array:
	var points: Array = []
	var valid := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var data: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = data[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = data[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / positions.size()
			for v in positions.size():
				var slot := -1
				for j in influences:
					if weights[v * influences + j] > .00001:
						valid = valid and slot == -1 and absf(weights[v * influences + j] - 1.0) < .0001
						slot = bones[v * influences + j]
				var bone_name: String = mesh.skin.get_bind_name(slot)
				var index: int = skel.find_bone(bone_name) if bone_name != "" else mesh.skin.get_bind_bone(slot)
				points.append({"bone": index, "local": mesh.skin.get_bind_pose(slot) * positions[v]})
	check(valid, "all imported vertices use exactly one full rigid weight")
	return points

func inspect_model(id: String, model: Node3D, ap: AnimationPlayer, skel: Skeleton3D, clip_map: Dictionary) -> void:
	var points := rigid_geometry(model, skel)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../reports/boss_trial_v1/build/" + id + "/pose_samples.json"))
	var max_head_error := 0.0
	var max_basis_error := 0.0
	var min_y := INF
	var sampled := 0
	var worst: Dictionary = {}
	var root_at := model.global_transform
	for clip in clip_map:
		var animation: String = clip_map[clip]
		ap.play(animation)
		var length := ap.get_animation(animation).length
		for f in 25:
			ap.seek(length * f / 24.0, true)
			skel.force_update_all_bone_transforms()
			for index in skel.get_bone_count():
				var pose := skel.global_transform * skel.get_bone_global_pose(index)
				var gram := pose.basis.transposed() * pose.basis
				max_basis_error = maxf(max_basis_error, maxf(gram.x.distance_to(Vector3.RIGHT), maxf(gram.y.distance_to(Vector3.UP), gram.z.distance_to(Vector3.BACK))))
				check(pose.origin.is_finite(), id + "/" + clip + " finite bone")
			if clip == "death" or f in [0, 12, 24]:
				for p in points: min_y = minf(min_y, (skel.global_transform * skel.get_bone_global_pose(p.bone) * p.local).y)
			if f in [0, 12, 24]:
				var expected: Dictionary = source[clip][int(f / 12)].bones
				for bone_name in expected:
					var matrix: Array = expected[bone_name]
					var want := Vector3(matrix[0][3], matrix[2][3], -matrix[1][3])
					var actual := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone_name)).origin
					var error := actual.distance_to(want)
					if error > max_head_error:
						max_head_error = error
						worst = {"clip":clip, "phase":f/24.0, "bone":bone_name, "expected":str(want), "actual":str(actual)}
				sampled += 1
		check(model.global_transform == root_at, id + "/" + clip + " never moves gameplay root")
	check(max_basis_error < .0001, id + " has no bone scale or shear")
	check(max_head_error < .0002, id + " Blender to Godot sampled bone heads agree within 0.2mm")
	check(min_y > -.001, id + " sampled vertices remain above floor within 1mm")
	metrics[id] = {"sampled_poses": sampled, "max_bone_head_error_m": max_head_error, "worst":worst, "max_basis_error": max_basis_error, "min_vertex_y_m": min_y, "vertices_checked": points.size()}

func run() -> void:
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.muted = true
	await process_frame
	var holder := Node3D.new(); root.add_child(holder)
	var model: Node3D = Visual.create(holder, "latch")
	check(model.loaded_ok and model.clips.size() == 8, "latch loads all eight motion clips")
	inspect_model("latch", model, model.player, model.skeleton, model.clips)
	holder.free()
	for id in ["door", "stake"]:
		var node: Node3D = load("res://assets/actors/boss_trial_v1/" + id + "_v1.glb").instantiate()
		root.add_child(node)
		var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var skel: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0]
		var clips := {}
		for name in ap.get_animation_list():
			for key in ["idle", "open", "close"]:
				if name == key or name.ends_with("|" + key): clips[key] = name
		inspect_model(id, node, ap, skel, clips)
		if id == "stake":
			var maximum := 0.0
			for p in rigid_geometry(node, skel):
				var v: Vector3 = skel.global_transform * skel.get_bone_global_pose(p.bone) * p.local
				maximum = maxf(maximum, maxf(absf(v.x), absf(v.z)))
			check(maximum <= .48, "stake fits the unchanged 0.96m map collider")
			metrics.stake.footprint_half_extent_m = maximum
		node.free()
	var plan: Dictionary = arena.config.enemy_types.latch.boss
	for pattern in ["sweep", "slam", "frames", "shockwave"]:
		var enemy := fresh()
		enemy.pattern_dir = Vector3.FORWARD
		if pattern == "frames": arena.begin_frames(enemy, plan, arena.player.position)
		else: arena.begin_boss(enemy, pattern, plan[pattern].windup)
		var art: Node3D = enemy.model
		for i in int(float(plan[pattern].windup) * 30): await step()
		arena.paused = true
		var before: Dictionary = art.debug_state()
		var doors: Array = []
		for fx in arena.effects:
			if fx.node.has_method("sync_effect"): doors.append({"node":fx.node, "elapsed":fx.node.elapsed})
		for i in 3: await step()
		check(before == art.debug_state(), pattern + " windup freezes when paused")
		for door in doors: check(door.elapsed == door.node.elapsed, "door membrane and hinge freeze when paused")
		arena.paused = false
		for i in int(float(plan[pattern].windup) * 60) + 3:
			await step()
			if not art.release_events.is_empty(): break
		check(art.visual_state == pattern and is_equal_approx(art.fraction, .5), pattern + " actual effect tick displays contact at 0.5")
		check(art.release_events.size() == 1 and art.release_events[0].pattern == pattern, pattern + " records the correct released motion")
		if pattern == "sweep":
			check(enemy.attack == "slam", "sweep contact is retained even while arena begins slam")
			await step()
			check(art.visual_state == "slam" and art.fraction < .03, "chained slam begins on next update")
		if pattern == "frames":
			check(doors.size() == 2 and arena.bolts.size() == 2, "two modelled doors emit the existing two projectiles")
			for door in doors: check(door.node.open_fraction == 1.0, "door is fully open before its shot")
			for i in 24: await step()
			for door in doors: check(not is_instance_valid(door.node), "door and membrane expire with the original effect")
	var enemy := fresh()
	var art: Node3D = enemy.model
	art.sample("slam", .3)
	var pose_before: Array[Transform3D] = []
	for i in art.skeleton.get_bone_count(): pose_before.append(art.skeleton.get_bone_pose(i))
	var rng_before: int = arena.combat_rng.state
	arena.damage_enemy("art_boss", 99999)
	check(not arena.enemies.has("art_boss") and art.get_parent() == arena.world, "death immediately removes boss target and retains only visual debris")
	for i in art.skeleton.get_bone_count(): check(pose_before[i].is_equal_approx(art.skeleton.get_bone_pose(i)), "death begins in the current attack pose")
	check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "dead boss pieces have no gameplay collision")
	art.set_process(false); arena.paused = true; art._process(.6)
	check(is_zero_approx(art._death_time), "boss debris pauses")
	arena.paused = false; art._process(1.0)
	check(arena.combat_rng.state == rng_before, "debris never consumes combat random numbers")
	art._process(1.3); await process_frame
	check(not is_instance_valid(art), "boss debris cleans up after its clip")
	arena.reset_arena()
	check(get_nodes_in_group("actor_corpses").is_empty(), "restart clears all boss debris")
	var result := {"passed": failures.is_empty(), "checks":checks.size(), "failures":failures, "metrics":metrics, "scope":"Imported skins and sampled bone heads; actual combat release, pause, cleanup. Rendering reviewed separately."}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("BOSS_ART_COMPLETE ", JSON.stringify(result))
	arena.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
