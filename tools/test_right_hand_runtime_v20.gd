extends SceneTree
var arena: Node3D
var output := ""
var failures: Array = []
var rows: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	call_deferred("run")

func run() -> void:
	arena = load("res://main.tscn").instantiate();root.add_child(arena);arena.set_physics_process(false)
	await process_frame
	var visual = arena.player_visual
	assert(visual.loaded_ok, visual.last_error)
	var contract = JSON.parse_string(FileAccess.get_file_as_string(visual.ASSET_DIR + "runtime_contract.json"))
	var left_array: Array = contract.secondary_grip.offset_bone_local
	var left_offset := Vector3(left_array[0],left_array[1],left_array[2])
	var skeleton: Skeleton3D = visual.runtime.skeleton
	var r_id := skeleton.find_bone("DEF-hand.R");var l_id := skeleton.find_bone("DEF-hand.L")
	visual.motion_duration = 1.0;visual._blend_from.clear();visual._collapse_from.clear()
	for kind in ["idle","run","attack","attack_thrust","hit_react","cast","collapse"]:
		visual._attack_clip_kind = "attack_thrust" if kind == "attack_thrust" else "attack"
		var sample_kind: String = "attack" if kind == "attack_thrust" else kind
		var length: float = visual._length(sample_kind)
		for i in 49:
			var phase := i / 48.0
			visual._collapse_elapsed = phase * length
			visual._sample(sample_kind, phase * length)
			await process_frame
			var right: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(r_id) * visual.STAFF_GRIP_OFFSET
			var left: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(l_id) * left_offset
			var axis: Vector3 = visual.staff_root.global_basis.y.normalized()
			var signed_spacing: float = (left - right).dot(axis)
			var lateral: float = ((left-right)-axis*signed_spacing).length()
			var origin_error: float = visual.staff_root.global_position.distance_to(right + axis*visual.staff_slide)
			if kind in ["idle","run","attack","attack_thrust","hit_react"]:
				if signed_spacing > -0.16: failures.append([kind,i,"right hand is not above left"])
				if lateral > 0.012: failures.append([kind,i,"support hand leaves shaft axis",lateral])
			if origin_error > 0.0002: failures.append([kind,i,"staff attachment differs from actual right grip",origin_error])
			rows.append({"kind":kind,"phase":phase,"left_axial_m":signed_spacing,"left_axis_distance_m":lateral,"attachment_error_m":origin_error,"staff_slide_m":visual.staff_slide})
	var report := {"passed":failures.is_empty(),"failures":failures,"samples":rows.size(),"rows":rows,"scope":"Actual Godot imported skeleton and rendered prop transforms; right hand above left in every two-hand clip. Full gameplay verified separately."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RIGHT_HAND_RUNTIME_V20_COMPLETE ", rows.size(), " ", failures.size())
	quit(0 if failures.is_empty() else 1)
