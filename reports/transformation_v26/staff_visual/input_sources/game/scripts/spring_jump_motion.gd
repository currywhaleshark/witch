extends RefCounted
## Visual flight only. Arena's ground movement, walls, timing and damage stay authoritative.
const TAKEOFF := 0.25
const LANDING := 0.75
const HEIGHT := 0.32
const SETTLE_SECONDS := 0.12
var mode := "idle"
var progress := 0.0
var height := 0.0
var duration := 0.2
var landing_elapsed := 0.0
var landing_height := 0.0
var landing_from: Array = []
var landing_arms: Dictionary = {}

func launch(host, seconds: float) -> void:
	mode = "flight"
	progress = 0.0
	height = 0.0
	duration = maxf(seconds, 0.0001)
	landing_elapsed = 0.0
	landing_from.clear()
	landing_arms.clear()
	host.asset_wrapper.position.y = 0.0
	host._sample("spring_jump", TAKEOFF * host._length("spring_jump"))

func set_progress(value: float) -> void:
	if mode != "flight": return
	progress = clampf(value, 0.0, 1.0)
	height = HEIGHT * 4.0 * progress * (1.0 - progress)

func finish(host) -> void:
	if mode != "flight": return
	# A wall can stop the ground path early. Blend the current airborne pose down locally.
	sample_pose(host)
	landing_from.clear()
	var bones: Skeleton3D = host.runtime.skeleton
	for index in bones.get_bone_count():
		landing_from.append([bones.get_bone_pose_position(index), bones.get_bone_pose_rotation(index), bones.get_bone_pose_scale(index)])
	landing_arms = host._staff_locomotion_blend.capture(bones)
	mode = "landing"
	landing_elapsed = 0.0
	landing_height = height

func advance(host, dt: float, dead: bool, cleared: bool) -> void:
	if cleared:
		mode = "idle"
		height = 0.0
		landing_from.clear()
	elif dead and mode == "flight":
		finish(host)
	if mode == "landing":
		landing_elapsed = minf(SETTLE_SECONDS, landing_elapsed + maxf(dt, 0.0))
		height = landing_height * (1.0 - smoothstep(0.0, SETTLE_SECONDS, landing_elapsed))
		if landing_elapsed >= SETTLE_SECONDS:
			mode = "idle"
			height = 0.0
			landing_from.clear()
	host.asset_wrapper.position.y = height

func sample_pose(host) -> bool:
	if mode == "idle" or not host._motion_kind.is_empty(): return false
	var phase := TAKEOFF + (LANDING - TAKEOFF) * progress
	if mode == "landing": phase = lerpf(LANDING, 1.0, landing_elapsed / SETTLE_SECONDS)
	host._sample("spring_jump", phase * host._length("spring_jump"))
	host._state = "spring_jump" if mode == "flight" else "spring_land"
	host.playback_speed = (LANDING - TAKEOFF) * host.clip_length / duration if mode == "flight" else (1.0 - LANDING) * host.clip_length / SETTLE_SECONDS
	if mode == "landing" and not landing_from.is_empty():
		var weight := smoothstep(0.0, 0.065, landing_elapsed)
		var bones: Skeleton3D = host.runtime.skeleton
		var target_arms: Dictionary = host._staff_locomotion_blend.capture(bones)
		for index in bones.get_bone_count():
			var previous: Array = landing_from[index]
			bones.set_bone_pose_position(index, (previous[0] as Vector3).lerp(bones.get_bone_pose_position(index), weight))
			bones.set_bone_pose_rotation(index, (previous[1] as Quaternion).slerp(bones.get_bone_pose_rotation(index), weight))
			bones.set_bone_pose_scale(index, (previous[2] as Vector3).lerp(bones.get_bone_pose_scale(index), weight))
		host._staff_locomotion_blend.apply(bones, landing_arms, target_arms, weight)
		host.staff_socket.on_skeleton_update()
	return true

func debug_state() -> Dictionary:
	return {"mode":mode, "progress":progress, "height":height, "duration":duration, "landing_elapsed":landing_elapsed}
