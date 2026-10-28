extends SceneTree
## Runtime regression of the combat-linked character, not a source-code check.
## Run with --script res://tests/player_visual.gd after the selected character assets are imported.
## Optional --capture records the same gameplay events through the real viewport.

const DT := 1.0 / 60.0
const HEAVY_HIT := 15.0
const EXPECTED_CLIPS := {
	"idle": "combat_idle_rh_v20", "run": "combat_run_rh_v21",
	"attack": "combat_heavy_swing_rh_v20", "cast": "combat_cast_rh_v20", "hit": "combat_hit_rh_v20",
}
# Authored stride, scaled with the 1.5m witch.
const EXPECTED_RUN_CYCLE_DISTANCE := 3.242813140153885 * 1.5 / 1.711
const EXPECTED_RUN_LENGTH := 4.0
var arena: Node3D
var failures: Array = []
var checks: Array = []
var observations: Dictionary = {}
var capture_enabled := false
var report_dir := ""
var captured: Array = []
var sequence_frames: Dictionary = {}
var run_phase_samples := 0
var run_loop_wraps := 0
var run_phase_max_error := 0.0
var run_rate_max_error := 0.0
var run_speed_max_error := 0.0
var run_length_max_error := 0.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture_enabled = true
		elif argument.begins_with("--output="):
			report_dir = argument.trim_prefix("--output=")
	if report_dir.is_empty():
		report_dir = ProjectSettings.globalize_path("res://").path_join("../reports/run_arm_v21/integration/gameplay").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks.append(label)
	if not condition:
		failures.append(label)
		push_error("PLAYER_VISUAL_CHECK_FAILED: " + label)
	return condition

func visual() -> Node3D:
	return arena.get("player_visual") as Node3D

func state() -> Dictionary:
	var controller := visual()
	if not is_instance_valid(controller) or not controller.has_method("debug_state"):
		return {}
	return controller.debug_state()

func animation_player() -> AnimationPlayer:
	return visual().runtime.animation_player as AnimationPlayer

func skeleton() -> Skeleton3D:
	return visual().runtime.skeleton as Skeleton3D

func clip_fraction() -> float:
	var snap := state()
	var clip: String = snap.get("clip", "")
	var player := animation_player()
	if clip.is_empty() or not player.has_animation(clip):
		return -1.0
	return player.current_animation_position / maxf(player.get_animation(clip).length, 0.00001)

func check_state(expected: String, label: String) -> void:
	var snap := state()
	check(snap.get("loaded_ok", false) and snap.get("state", "") == expected, label)
	var clip: String = snap.get("clip", "")
	check(not clip.is_empty() and animation_player().has_animation(clip), label + ": actual clip exists")
	check(clip.get_file() in ["combat_heavy_swing_rh_v20", "combat_thrust_rh_v20"] if expected == "attack" else clip.get_file() == EXPECTED_CLIPS[expected], label + ": selected authored clip matches the gameplay contract")
	if not clip.is_empty() and animation_player().has_animation(clip):
		check(animation_player().current_animation == clip, label + ": AnimationPlayer selected the clip")
	if expected == "run":
		check(absf(float(snap.get("run_cycle_distance", 0)) - EXPECTED_RUN_CYCLE_DISTANCE) < 0.000000001, label + ": selected run uses its measured cycle distance")
	observations[expected + "_clip"] = clip

func pose_snapshot() -> Array:
	var result: Array = []
	for index in skeleton().get_bone_count():
		result.append(skeleton().get_bone_global_pose(index))
	return result

func same_pose(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if not a[index].is_equal_approx(b[index]):
			return false
	return true

func step(count: int = 1, sequence: String = "") -> void:
	for frame in count:
		var previous_state := state()
		var previous_position: Vector3 = arena.player.position
		var previous_fraction := clip_fraction()
		await physics_frame
		arena._physics_process(DT)
		observe_run_step(previous_state, previous_position, previous_fraction)
		if capture_enabled and not sequence.is_empty():
			var number: int = sequence_frames.get(sequence, 0)
			sequence_frames[sequence] = number + 1
			await capture("%s_%03d" % [sequence, number])

func observe_run_step(previous: Dictionary, previous_position: Vector3, previous_fraction: float) -> void:
	var snap := state()
	# State changes reset phase deliberately; compare consecutive moving samples.
	if previous.get("state", "") != "run" or snap.get("state", "") != "run" or previous.get("frozen", false) or snap.get("frozen", false):
		return
	var distance: float = arena.player.position.distance_to(previous_position)
	var actual_fraction := clip_fraction()
	var actual_advance := fposmod(actual_fraction - previous_fraction, 1.0)
	var expected_advance := fposmod(distance / EXPECTED_RUN_CYCLE_DISTANCE, 1.0)
	var actual_length: float = animation_player().get_animation(str(snap.clip)).length
	run_phase_samples += 1
	if actual_fraction < previous_fraction and distance > 0.0:
		run_loop_wraps += 1
	run_phase_max_error = maxf(run_phase_max_error, absf(wrapf(actual_advance - expected_advance, -0.5, 0.5)))
	run_rate_max_error = maxf(run_rate_max_error, absf(float(snap.get("playback_speed", -1)) - distance / DT * actual_length / EXPECTED_RUN_CYCLE_DISTANCE))
	run_speed_max_error = maxf(run_speed_max_error, absf(float(snap.get("movement_speed", -1)) - distance / DT))
	run_length_max_error = maxf(run_length_max_error, absf(actual_length - EXPECTED_RUN_LENGTH))

func input_key(code: int) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	root.push_input(release, true)

func input_mouse(button: int, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	root.push_input(event, true)

func fresh(target := Vector3(2, 0, 0)) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.attack_speed_score = 0
	arena.config.cast_speed_score = 0
	arena.config.hit_recovery_score = 0
	arena.config.shield_level = 1
	arena.config.dexterity = 0
	arena.rules.skills.shield.block_base = 0.2
	arena.rules.skills.shield.block_cap = 0.75
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("target", target, true)
	arena.enemies.target.cooldown = 999.0
	arena.enemies.target.hp = 10000.0
	arena.enemies.target.max_hp = 10000.0
	await step(2)

func check_staff(label: String) -> void:
	await process_frame
	var socket = visual().get("staff_socket")
	var staff = visual().get("staff_root")
	if not check(socket is BoneAttachment3D and staff is Node3D, label + ": real staff and bone socket exist"):
		return
	check(socket.is_ancestor_of(staff), label + ": staff is parented below the bone attachment")
	var bone: int = skeleton().find_bone(socket.bone_name)
	if not check(bone >= 0 and "hand" in str(socket.bone_name).to_lower(), label + ": socket targets a hand bone"):
		return
	var hand := skeleton().global_transform * skeleton().get_bone_global_pose(bone)
	check(socket.global_position.distance_to(hand.origin) < 0.002, label + ": socket follows the evaluated hand within 2 mm")
	check(not staff.find_children("*", "MeshInstance3D", true, false).is_empty(), label + ": attached staff has actual mesh geometry")

func check_skin_arrays() -> void:
	var garment_count := 0
	var saw_more_than_four := false
	var maximum_sum_error := 0.0
	for node in visual().runtime.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if not str(mesh_node.name).begins_with("SourceOutfit_"):
			continue
		garment_count += 1
		check(mesh_node.skin != null, "garment has a runtime skin: " + mesh_node.name)
		for surface in mesh_node.mesh.get_surface_count():
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			if not check(not vertices.is_empty() and weights.size() == vertices.size() * 8 and bones.size() == weights.size(), "garment imports eight weight slots: %s/%d" % [mesh_node.name, surface]):
				continue
			for vertex in vertices.size():
				var total := 0.0
				var active := 0
				for slot in 8:
					var weight: float = weights[vertex * 8 + slot]
					total += weight
					if weight > 0.00000001:
						active += 1
						if bones[vertex * 8 + slot] < 0 or bones[vertex * 8 + slot] >= skeleton().get_bone_count():
							check(false, "runtime garment bone index is in the shared skeleton")
							return
				maximum_sum_error = maxf(maximum_sum_error, absf(total - 1.0))
				saw_more_than_four = saw_more_than_four or active > 4
	check(garment_count >= 4 and saw_more_than_four, "actual imported clothing retains influences beyond four")
	check(maximum_sum_error < 0.002, "runtime clothing weight sums stay normalized")
	observations.runtime_garments = garment_count
	observations.runtime_weight_max_sum_error = maximum_sum_error

func check_release_alignment(label: String) -> void:
	var snap := state()
	var duration: float = snap.get("motion_duration", 0.0)
	var gameplay_ratio: float = snap.get("gameplay_release_ratio", -1.0)
	var authored_ratio: float = snap.get("authored_release_ratio", -1.0)
	if not check(duration > 0 and gameplay_ratio > 0 and gameplay_ratio < 1 and authored_ratio > 0 and authored_ratio < 1, label + ": both release markers are available"):
		return
	# The visual latch samples authored contact on the actual gameplay release frame.
	var tolerance := 0.0001
	check(absf(clip_fraction() - authored_ratio) <= tolerance, label + ": effect and authored contact marker align")
	observations[label] = {"gameplay_release_ratio": gameplay_ratio, "authored_release_ratio": authored_ratio,
		"actual_clip_fraction_at_effect": clip_fraction(), "duration": duration, "tolerance": tolerance}

func run() -> void:
	root.size = Vector2i(1280, 800)
	Engine.time_scale = 1.0
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	if not check(is_instance_valid(visual()) and visual().has_method("debug_state"), "arena owns the real character visual controller"):
		finish()
		return
	if not check(visual().get("loaded_ok") == true, "selected v21 character assets load successfully: " + str(visual().get("last_error"))):
		finish()
		return
	await fresh()
	check(skeleton().get_bone_count() == 107, "game character uses the shared 107-bone rig")
	check_skin_arrays()
	check_state("idle", "resting player uses idle")
	var idle_pose := pose_snapshot()
	await step(12, "idle_motion")
	check(not same_pose(idle_pose, pose_snapshot()), "idle changes actual bone transforms")
	if capture_enabled:
		# Record a full idle loop plus a non-identical endpoint without changing
		# the original twelve-frame pose assertion used by headless regression.
		await step(122, "idle_motion")
	await check_staff("idle")
	await capture("idle_native")
	await capture("idle_close", true)

	# Click movement and approach both reach the visual through the arena tick.
	arena.request_slot("lmb", {"ground": [-10 if capture_enabled else -3, 0, 0]})
	var initial_position: Vector3 = arena.player.position
	await step(10, "run_motion")
	check(arena.player.position.distance_to(initial_position) > 0.3, "click move actually moves the character")
	check_state("run", "actual displacement selects run")
	if capture_enabled:
		# Keep the ten-frame movement checks, then record eighty run frames total.
		await step(70, "run_motion")
	await check_staff("run")
	await capture("run_close", true)
	for frame in 90:
		if not arena.moving:
			break
		await step()
	await step(2)
	check_state("idle", "arrival returns to idle")

	await fresh(Vector3(8, 0, 0))
	arena.request_slot("lmb", {"enemy_id": "target"})
	check(not arena.pending_cast.is_empty(), "far target enters the gameplay approach path")
	await step(8)
	check_state("run", "approach to an enemy uses run")
	for frame in 150:
		if not arena.windup.is_empty():
			break
		await step()
	check(arena.pending_cast.is_empty() and not arena.windup.is_empty(), "approach starts attack within range")
	check_state("attack", "approach arrival starts the attack clip")

	# Held pointer steering resumes after a stopped casting action.
	await fresh(Vector3(8, 0, -8))
	var ground_screen: Vector2 = arena.camera.unproject_position(Vector3(-6, 0, 0))
	input_mouse(MOUSE_BUTTON_LEFT, true, ground_screen)
	await step(6)
	check(not arena.move_hold.is_empty(), "real held mouse input creates held movement")
	check_state("run", "held movement uses run")
	var held_position: Vector3 = arena.player.position
	arena.request_slot("rmb", {"ground": [-6, 0, 0]})
	await step(3)
	check(arena.player.position.distance_to(held_position) < 0.01, "stop-cast pauses actual held movement")
	check_state("cast", "stop-cast replaces run visually")
	await step(int(ceil(arena.cast_seconds(arena.rules.skills.shotgun) / DT)) + 4)
	check(arena.player.position.distance_to(held_position) > 0.2, "held movement resumes without another click")
	check_state("run", "held movement restores run after casting")
	# Reuse the held-movement scenario to cover the new run's interrupt/reentry.
	arena.damage_player(HEAVY_HIT)
	check_state("hit", "heavy hit replaces the selected run")
	await step(int(ceil(arena.hit_recovery_seconds() / DT)) + 4)
	check_state("run", "held movement restores the selected run after hit recovery")
	input_mouse(MOUSE_BUTTON_LEFT, false, ground_screen)

	# Effects, resource spending and animation markers share the same release instant.
	for speed in [0, 40]:
		await fresh()
		arena.config.attack_speed_score = speed
		var duration: float = arena.attack_seconds()
		var full_hp: float = arena.enemies.target.hp
		arena.request_slot("lmb", {"enemy_id": "target"})
		check_state("attack", "attack begins at speed %d" % speed)
		check(is_equal_approx(float(state().get("motion_duration", 0)), duration), "attack visual follows gameplay duration at speed %d" % speed)
		var before_release := maxi(1, int(floor(duration * arena.rules.skills.basic_attack.release_ratio / DT)) - 1)
		await step(before_release, "attack_motion" if speed == 0 else "")
		check(arena.enemies.target.hp == full_hp, "attack deals no damage before release at speed %d" % speed)
		if speed == 0:
			await capture("attack_close", true)
		for frame in 4:
			if arena.enemies.target.hp < full_hp:
				break
			await step(1, "attack_motion" if speed == 0 else "")
		check(is_equal_approx(full_hp - arena.enemies.target.hp, arena.config.basic_damage), "attack releases exactly one hit at speed %d" % speed)
		check_release_alignment("attack_speed_%d" % speed)
		await check_staff("attack speed %d" % speed)
		await step(int(ceil(duration / DT)) + 2, "attack_motion" if capture_enabled and speed == 0 else "")
		check_state("idle", "attack recovery returns to idle at speed %d" % speed)

	for speed in [0, 40]:
		await fresh(Vector3(8, 0, -8))
		arena.config.cast_speed_score = speed
		var duration: float = arena.cast_seconds(arena.rules.skills.automaton)
		var initial_mana: float = arena.state.mana
		arena.request_slot("w", {"ground": [0, 0, 3]})
		check_state("cast", "summon begins cast at FCR %d" % speed)
		check(is_equal_approx(float(state().get("motion_duration", 0)), duration), "cast visual follows gameplay FCR duration %d" % speed)
		var before_release := maxi(1, int(floor(duration * arena.rules.skills.automaton.release_ratio / DT)) - 1)
		await step(before_release, "cast_motion" if speed == 0 else "")
		check(arena.allies.is_empty() and is_equal_approx(arena.state.mana, initial_mana), "summon spends nothing and creates nothing before release at FCR %d" % speed)
		if speed == 0:
			await capture("cast_close", true)
		for frame in 4:
			if not arena.allies.is_empty():
				break
			await step(1, "cast_motion" if speed == 0 else "")
		check(arena.allies.size() == 1 and is_equal_approx(initial_mana - arena.state.mana, arena.rules.skills.automaton.mana_cost), "summon appears with its cost at release at FCR %d" % speed)
		check_release_alignment("cast_fcr_%d" % speed)
		await step(int(ceil(duration / DT)) + 2, "cast_motion" if capture_enabled and speed == 0 else "")
		check_state("idle", "cast recovery returns to idle at FCR %d" % speed)

	await fresh()
	var hp_before_hit: float = arena.enemies.target.hp
	arena.request_slot("lmb", {"enemy_id": "target"})
	await step(3)
	arena.damage_player(HEAVY_HIT)
	check(arena.windup.is_empty() and arena.stun_time > 0, "heavy hit actually interrupts gameplay windup")
	check_state("hit", "heavy hit interrupts the attack animation")
	check(is_equal_approx(float(state().get("motion_duration", 0)), arena.hit_recovery_seconds()), "hit visual duration follows recovery time")
	await step(5, "hit_motion")
	await capture("hit_close", true)
	await check_staff("hit")
	await step(int(ceil(arena.hit_recovery_seconds() / DT)) + 10, "hit_motion")
	check(arena.enemies.target.hp == hp_before_hit, "interrupted attack never applies damage")
	check_state("idle", "hit recovery returns to idle")

	await fresh()
	arena.rules.skills.shield.block_base = 1.0
	arena.rules.skills.shield.block_cap = 1.0
	arena.request_slot("r", {})
	arena.request_slot("lmb", {"enemy_id": "target"})
	await step(4)
	var blocked_snap := state()
	var blocked_hp: float = arena.hp
	arena.damage_player(HEAVY_HIT)
	check(arena.hp == blocked_hp and not arena.windup.is_empty(), "blocked heavy hit preserves gameplay attack")
	check_state("attack", "blocked hit does not trigger hit animation")
	check(is_equal_approx(float(state().get("motion_elapsed", -1)), float(blocked_snap.get("motion_elapsed", -2))), "blocked hit does not restart animation time")
	await step(2)
	check(float(state().get("motion_elapsed", 0)) > float(blocked_snap.get("motion_elapsed", 0)), "attack continues after a blocked hit")
	arena.shield_time = 0
	var minor_snap := state()
	arena.damage_player(arena.config.max_hp * arena.config.hit_stun_min_ratio - 1)
	check_state("attack", "minor non-stunning damage also preserves attack animation")
	check(is_equal_approx(float(state().get("motion_elapsed", -1)), float(minor_snap.get("motion_elapsed", -2))), "minor damage does not restart animation time")

	# Pause freezes evaluated bones; incapacitation plays and then holds a fall.
	await fresh()
	arena.request_slot("lmb", {"enemy_id": "target"})
	await step(5)
	input_key(KEY_ESCAPE)
	await step()
	var pause_state := state()
	var pause_pose := pose_snapshot()
	var release_left: float = arena.windup.release
	await step(12)
	check(arena.paused and state().get("paused", false), "Escape pauses both combat and visual")
	check(is_equal_approx(float(state().get("clip_time", -1)), float(pause_state.get("clip_time", -2))) and same_pose(pause_pose, pose_snapshot()), "pause freezes clip time and all actual bones")
	check(is_equal_approx(arena.windup.release, release_left), "pause preserves the pending gameplay release time")
	input_key(KEY_ESCAPE)
	await step(2)
	check(not arena.paused and float(state().get("motion_elapsed", 0)) > float(pause_state.get("motion_elapsed", 0)), "resume continues the same action")
	check(not same_pose(pause_pose, pose_snapshot()), "resume advances actual bones again")
	arena.damage_player(arena.hp + 1)
	await step()
	var death_state := state()
	var death_pose := pose_snapshot()
	var death_position: Vector3 = arena.player.position
	await step(12, "collapse_motion")
	check(arena.hp == 0 and state().get("dead", false), "HP zero starts incapacitation")
	check(str(state().get("clip", "")).get_file() == "combat_collapse_rh_v20" and not same_pose(death_pose, pose_snapshot()), "incapacitation advances the actual collapse bones")
	var fall_time: float = state().get("clip_time", 0.0)
	var fall_pose := pose_snapshot()
	arena.paused = true
	await step(8)
	check(is_equal_approx(float(state().get("clip_time", -1)), fall_time) and same_pose(fall_pose, pose_snapshot()), "pause freezes a fall in progress")
	arena.paused = false
	await step(150, "collapse_motion")
	death_pose = pose_snapshot()
	death_state = state()
	await step(12)
	check(state().get("state", "") == "dead" and is_equal_approx(float(state().get("normalized_time", 0)), 1.0), "collapse completes and holds its final frame")
	check(same_pose(death_pose, pose_snapshot()) and state().get("clip_time") == death_state.get("clip_time"), "settled incapacitation freezes the actual bones")
	check(arena.player.position.is_equal_approx(death_position), "dead player does not move")
	var previous_visual_id := visual().get_instance_id()
	input_key(KEY_ENTER)
	await step(2)
	check(visual().get_instance_id() != previous_visual_id and visual().get("loaded_ok") == true, "Enter reset rebuilds and loads the real visual")
	check(arena.hp == arena.config.max_hp and skeleton().get_bone_count() == 107, "reset restores health and shared rig")
	check_state("idle", "reset returns to a clean idle")
	await check_staff("reset")
	finish()

func capture(label: String, closeup: bool = false) -> void:
	if not capture_enabled:
		return
	var saved_size: float = arena.camera.size
	if closeup:
		arena.camera.size = saved_size * 0.38
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := report_dir.path_join(label + ".png")
	check(picture.get_size() == Vector2i(1280, 800), "captured viewport is 1280x800: " + label)
	check(picture.save_png(path) == OK, "saved actual gameplay render: " + label)
	captured.append({"file": label + ".png", "closeup": closeup, "camera_size": arena.camera.size,
		"state": state(), "position": [arena.player.position.x, arena.player.position.y, arena.player.position.z]})
	arena.camera.size = saved_size

func finish() -> void:
	check(run_phase_samples > 0 and run_loop_wraps > 0, "actual movement exercises the run phase and a loop wrap")
	check(run_phase_max_error < 0.00001, "actual run animation phase follows displacement divided by authored cycle distance")
	check(run_rate_max_error < 0.00001 and run_speed_max_error < 0.00001, "run playback rate follows actual displacement speed")
	check(run_length_max_error < 0.00001, "selected compact run retains its denser authoring and measured cycle distance")
	observations.run_playback_contract = {"clip": EXPECTED_CLIPS.run, "cycle_distance_m": EXPECTED_RUN_CYCLE_DISTANCE,
		"authored_length_seconds": EXPECTED_RUN_LENGTH, "sample_count": run_phase_samples, "loop_wraps": run_loop_wraps,
		"max_normalized_phase_error": run_phase_max_error, "max_playback_rate_error": run_rate_max_error,
		"max_actual_speed_error_mps": run_speed_max_error, "max_clip_length_error_seconds": run_length_max_error}
	if capture_enabled:
		var strip := Image.create(1600, 200, false, Image.FORMAT_RGBA8)
		for index in 5:
			var label: String = ["idle", "run", "attack", "cast", "hit"][index]
			var picture := Image.load_from_file(report_dir.path_join(label + "_close.png"))
			if picture == null or picture.is_empty():
				check(false, "five-clip strip has actual " + label + " render")
				continue
			picture.convert(Image.FORMAT_RGBA8)
			picture.resize(320, 200, Image.INTERPOLATE_LANCZOS)
			strip.blit_rect(picture, Rect2i(0, 0, 320, 200), Vector2i(index * 320, 0))
		check(strip.save_png(report_dir.path_join("five_clips_strip.png")) == OK, "saved five-clip strip assembled only from actual game renders")
	var report := {"engine": Engine.get_version_info().string, "passed": failures.is_empty(),
		"checks": checks, "failures": failures, "observations": observations, "captures": captured,
		"scope": "Actual arena events, animation playback and imported mesh arrays. Not art approval or arbitrary-pose collision validation."}
	var file := FileAccess.open(report_dir.path_join("player_visual_validation.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write player visual validation report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("PLAYER_VISUAL_VALIDATION_COMPLETE" if failures.is_empty() else "PLAYER_VISUAL_VALIDATION_FAILED")
	print("checks=%d failures=%d report=%s" % [checks.size(), failures.size(), report_dir])
	quit(0 if failures.is_empty() else 1)
