extends Node3D
## Presentation only. The arena owns movement, resource costs, hit tests and clocks.
const Modular = preload("res://scripts/modular_character_runtime.gd")
const Shape = preload("res://scripts/shapes.gd")
const ASSET_DIR := "res://assets/characters/player/run_arm_v21/"
const BODY_PATH := ASSET_DIR + "body_standard_v21.glb"
const PARTS := {
	"hair": {"asset": ASSET_DIR + "hair_semilong_v21.glb", "hide_body_regions": []},
	"eyes": {"asset": ASSET_DIR + "eyes_neutral_v21.glb", "hide_body_regions": []},
	"outfit": {"asset": ASSET_DIR + "outfit_civilian_v21.glb", "hide_body_regions": ["torso", "arms", "lowerlegs", "feet"]},
}
const CLIPS := {
	"idle": "combat_idle_rh_v20", "run": "combat_run_rh_v21",
	"attack": "combat_heavy_swing_rh_v20", "attack_thrust": "combat_thrust_rh_v20",
	"cast": "combat_cast_rh_v20", "hit_react": "combat_hit_rh_v20", "collapse": "combat_collapse_rh_v20",
}
# Authored release: swing 25/49, thrust 13/25, cast 17/33; normalized 0.5.
const AUTHORED_RELEASE := {"attack": 0.5, "cast": 0.5}
const STAFF_GRIP_OFFSET := Vector3(0.0074299751, 0.0480000079, 0.0158048961)
const STAFF_GRIP_BASIS := Basis(Vector3(0, -1, 0), Vector3(0.9106548, 0, -0.4131677), Vector3(0.4131677, 0, 0.9106548))
const LOCOMOTION_BLEND_SECONDS := 0.10
# v21 arm correction retains the selected compact run's measured stride.
const RUN_CYCLE_DISTANCE := 3.242813140153885
const BRASS := Color("c69b62")
const STEEL := Color("a9c1d6")
const TEAL := Color("8dd8c4")

var runtime: Modular
var asset_wrapper: Node3D
var staff_socket: BoneAttachment3D
var staff_root: Node3D
var staff_head: Node3D
var tool_visuals: Dictionary = {}
var grinder_disk: MeshInstance3D
var loaded_ok := false
var last_error := ""
var motion_duration := 0.0
var motion_elapsed := 0.0
var gameplay_release_ratio := 0.5
var authored_release_ratio := 0.5
var clip_time := 0.0
var clip_length := 0.0
var playback_speed := 1.0
var is_paused := false
var is_dead := false
var is_cleared := false
var _state := "loading"
var _motion_kind := ""
var _clip := ""
var _loop_time := 0.0
var _clips: Dictionary = {}
var _blend_from: Array = []
var _blend_elapsed := 0.0
var _run_rate := 1.0
var movement_speed := 0.0
var _release_pending := false
var _release_elapsed := -1.0
var _attack_rng := RandomNumberGenerator.new()
var _attack_clip_kind := "attack"
var _collapse_elapsed := 0.0
var _collapse_from: Array = []
var _collapse_grip_from := 0.0
var staff_slide := 0.0
var _staff_slide_tracks: Dictionary = {}
const COLLAPSE_BLEND_SECONDS := 0.18

func initialize() -> bool:
	name = "PlayerVisual"
	# This private generator never consumes combat/global random numbers.
	_attack_rng.randomize()
	asset_wrapper = Node3D.new()
	asset_wrapper.name = "AssetFacing"
	# Exported character faces +Z; arena's existing look_at faces -Z.
	asset_wrapper.rotation.y = PI
	add_child(asset_wrapper)
	runtime = Modular.new()
	runtime.name = "ModularCharacter"
	asset_wrapper.add_child(runtime)
	if not runtime.initialize(BODY_PATH):
		return _fail(runtime.last_error)
	if runtime.skeleton.get_bone_count() != 107:
		return _fail("expected_v11_family_107_bones")
	if not runtime.replace_parts(PARTS):
		return _fail(runtime.last_error)
	for kind in CLIPS:
		for animation_name in runtime.animation_player.get_animation_list():
			if String(animation_name).get_file() == CLIPS[kind]:
				_clips[kind] = String(animation_name)
				break
		if not _clips.has(kind):
			return _fail("missing_clip: " + CLIPS[kind])
	if runtime.skeleton.find_bone("DEF-hand.R") < 0:
		return _fail("missing_staff_hand")
	var animator: AnimationPlayer = runtime.animation_player
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.playback_auto_capture = false
	animator.playback_default_blend_time = 0.0
	var motion_contract = JSON.parse_string(FileAccess.get_file_as_string(ASSET_DIR + "runtime_contract.json"))
	if not motion_contract is Dictionary or not motion_contract.get("staff_slide_tracks") is Dictionary:
		return _fail("missing_staff_slide_contract")
	_staff_slide_tracks = motion_contract["staff_slide_tracks"]
	for clip in CLIPS.values():
		var slide_track = _staff_slide_tracks.get(clip)
		if not slide_track is Array or slide_track.size() < 2:
			return _fail("missing_staff_slide_track: " + clip)
	_build_staff()
	loaded_ok = true
	_state = "idle"
	_sample("idle", 0.0)
	return true

func _fail(reason: String) -> bool:
	last_error = reason
	_state = "load_error"
	asset_wrapper.visible = false
	push_error("Player visual load failed: " + reason)
	var label := Label3D.new()
	label.text = "캐릭터 로드 실패"
	label.modulate = Color("ff6876")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.0
	add_child(label)
	return false

func _build_staff() -> void:
	staff_socket = BoneAttachment3D.new()
	staff_socket.name = "StaffSocket"
	runtime.skeleton.add_child(staff_socket)
	staff_socket.bone_name = "DEF-hand.R"
	staff_socket.override_pose = false
	staff_root = Node3D.new()
	staff_root.name = "MechanicalStaff"
	staff_socket.add_child(staff_root)
	staff_root.position = STAFF_GRIP_OFFSET
	staff_root.basis = STAFF_GRIP_BASIS
	# +Y shaft: grip at zero, 0.42m below and 0.78m above the hand.
	Shape.cylinder(staff_root, Vector3(0, 0.18, 0), 0.010, 1.20, BRASS)
	Shape.cylinder(staff_root, Vector3(0, -0.02, 0), 0.013, 0.16, Color("39474f"))
	staff_head = Node3D.new()
	staff_head.name = "StaffHead"
	staff_root.add_child(staff_head)
	Shape.box(staff_head, Vector3(0, 0.68, 0), Vector3(0.16, 0.09, 0.10), STEEL)
	var crown := Shape.ring(staff_head, Vector3(0, 0.77, 0), 0.10, TEAL, 0.018)
	crown.rotation.x = PI / 2.0
	tool_visuals = {"bolt_cutter": Node3D.new(), "grinder": Node3D.new()}
	for tool in tool_visuals:
		tool_visuals[tool].name = tool
		staff_root.add_child(tool_visuals[tool])
		tool_visuals[tool].visible = false
	for x in [-0.08, 0.08]:
		var jaw := Shape.box(tool_visuals.bolt_cutter, Vector3(x, 0.78, 0), Vector3(0.065, 0.29, 0.10), BRASS)
		jaw.rotation.z = x * 1.5
	grinder_disk = Shape.cylinder(tool_visuals.grinder, Vector3(0, 0.78, 0), 0.17, 0.045, STEEL)
	grinder_disk.rotation.z = PI / 2.0

func set_active_tool(tool) -> void:
	if not loaded_ok:
		return
	for tool_name in tool_visuals:
		tool_visuals[tool_name].visible = tool == tool_name
	staff_head.visible = tool == null

func begin_motion(kind: String, duration: float, release_ratio: float) -> void:
	if not loaded_ok or is_dead or kind not in ["attack", "cast"]:
		return
	_motion_kind = kind
	if kind == "attack":
		_attack_clip_kind = "attack" if _attack_rng.randf() < 0.5 else "attack_thrust"
	_blend_from.clear()
	_state = kind
	motion_duration = maxf(duration, 0.000001)
	motion_elapsed = 0.0
	_release_pending = false
	_release_elapsed = -1.0
	gameplay_release_ratio = clampf(release_ratio, 0.0, 1.0)
	authored_release_ratio = AUTHORED_RELEASE[kind]
	_sample(kind, 0.0)

func mark_release() -> void:
	if loaded_ok and _motion_kind in ["attack", "cast"]:
		# The arena signals the real physics frame that crosses its release clock.
		_release_pending = true

func hit_react(duration: float) -> void:
	if not loaded_ok or is_dead:
		return
	# Only the arena's actual stun branch invokes this; blocked/minor hits do not.
	_motion_kind = "hit_react"
	_blend_from.clear()
	_state = "hit"
	motion_duration = maxf(duration, 0.000001)
	motion_elapsed = 0.0
	_release_pending = false
	_release_elapsed = -1.0
	_sample("hit_react", 0.0)

func freeze_for_death() -> void:
	# Kept as the arena's compatibility hook; incapacitation now plays a fall.
	if is_dead:
		return
	is_dead = true
	_state = "collapse"
	_motion_kind = ""
	_release_pending = false
	_release_elapsed = -1.0
	_collapse_elapsed = 0.0
	_collapse_grip_from = staff_slide
	_blend_from.clear()
	if loaded_ok:
		for index in runtime.skeleton.get_bone_count():
			_collapse_from.append([runtime.skeleton.get_bone_pose_position(index), runtime.skeleton.get_bone_pose_rotation(index), runtime.skeleton.get_bone_pose_scale(index)])
		_sample("collapse", 0.0)

func sync_state(dt: float, moved: bool, action_remaining: float, paused: bool, dead: bool, cleared: bool, actual_speed: float = -1.0) -> void:
	is_paused = paused
	if dead:
		freeze_for_death()
	is_cleared = cleared
	if not loaded_ok or paused:
		return
	if is_dead:
		_collapse_elapsed = minf(_collapse_elapsed + maxf(dt, 0.0), _length("collapse"))
		_sample("collapse", _collapse_elapsed)
		_state = "dead" if _collapse_elapsed >= _length("collapse") else "collapse"
		return
	if cleared:
		if _state != "cleared":
			_motion_kind = ""
			_release_pending = false
			_release_elapsed = -1.0
			_blend_from.clear()
			_sample("idle", 0.0)
			_state = "cleared"
		return
	if not _motion_kind.is_empty():
		if action_remaining > 0 or _release_pending:
			# Use the combat clock, including FCR/IAS/FHR and same-frame interrupts.
			motion_elapsed = clampf(motion_duration - action_remaining, 0.0, motion_duration)
			var progress := motion_elapsed / motion_duration
			var normalized := progress
			if _motion_kind in ["attack", "cast"]:
				if _release_pending:
					_release_pending = false
					_release_elapsed = motion_elapsed
				if _release_elapsed >= 0.0:
					# Pin impact to the actual release frame, then finish in the unchanged
					# remaining combat time. Avoid fast recovery skipping past impact.
					var recovery := maxf(motion_duration - _release_elapsed, 0.000001)
					var recovery_progress := clampf((motion_elapsed - _release_elapsed) / recovery, 0.0, 1.0)
					normalized = lerpf(authored_release_ratio, 1.0, recovery_progress)
				else:
					normalized = map_release_progress(progress, gameplay_release_ratio, authored_release_ratio)
			_sample(_motion_kind, normalized * _length(_motion_kind))
			return
		_motion_kind = ""
		motion_elapsed = motion_duration
	var desired := "run" if moved else "idle"
	if _state != desired:
		if _state in ["idle", "run"]:
			_capture_locomotion_blend()
		_loop_time = 0.0
	_state = desired
	movement_speed = maxf(actual_speed, 0.0)
	_run_rate = actual_speed * _length("run") / RUN_CYCLE_DISTANCE if actual_speed >= 0 else 1.0
	var rate := _run_rate if desired == "run" else 1.0
	_loop_time = fposmod(_loop_time + maxf(dt, 0.0) * rate, maxf(_length(desired), 0.000001))
	_blend_elapsed += maxf(dt, 0.0)
	_sample(desired, _loop_time)

func _capture_locomotion_blend() -> void:
	_blend_from.clear()
	_blend_elapsed = 0.0
	var skeleton: Skeleton3D = runtime.skeleton
	for index in skeleton.get_bone_count():
		_blend_from.append([skeleton.get_bone_pose_position(index), skeleton.get_bone_pose_rotation(index), skeleton.get_bone_pose_scale(index)])

static func map_release_progress(progress: float, gameplay_ratio: float, authored_ratio: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	var g := clampf(gameplay_ratio, 0.0, 1.0)
	var a := clampf(authored_ratio, 0.0, 1.0)
	if p < g and g > 0.0:
		return p / g * a
	if g < 1.0:
		return a + (p - g) / (1.0 - g) * (1.0 - a)
	return a

func _length(kind: String) -> float:
	return runtime.animation_player.get_animation(_clips[_attack_clip_kind if kind == "attack" else kind]).length

func _sample_staff_slide(clip: String, phase: float) -> float:
	var values: Array = _staff_slide_tracks.get(clip, [0.0])
	var x := clampf(phase, 0.0, 1.0) * (values.size() - 1)
	var lo := int(floorf(x))
	return lerpf(float(values[lo]), float(values[mini(lo + 1, values.size() - 1)]), x - lo)

func _sample(kind: String, time: float) -> void:
	var animator: AnimationPlayer = runtime.animation_player
	var next_clip: String = _clips[_attack_clip_kind if kind == "attack" else kind]
	clip_length = _length(kind)
	clip_time = clampf(time, 0.0, clip_length)
	# Explicit rest reset is a second guard against imported constant-track removal.
	runtime.skeleton.reset_bone_poses()
	if _clip != next_clip:
		animator.play(next_clip, 0.0)
		_clip = next_clip
	animator.seek(clip_time, true)
	if kind == "collapse" and not _collapse_from.is_empty():
		var weight := clampf(_collapse_elapsed / COLLAPSE_BLEND_SECONDS, 0.0, 1.0)
		var bones: Skeleton3D = runtime.skeleton
		for index in bones.get_bone_count():
			var previous: Array = _collapse_from[index]
			bones.set_bone_pose_position(index, (previous[0] as Vector3).lerp(bones.get_bone_pose_position(index), weight))
			bones.set_bone_pose_rotation(index, (previous[1] as Quaternion).slerp(bones.get_bone_pose_rotation(index), weight))
			bones.set_bone_pose_scale(index, (previous[2] as Vector3).lerp(bones.get_bone_pose_scale(index), weight))
		if weight >= 1.0:
			_collapse_from.clear()
	if kind in ["idle", "run"] and not _blend_from.is_empty():
		var weight := clampf(_blend_elapsed / LOCOMOTION_BLEND_SECONDS, 0.0, 1.0)
		# Blend only the presentation pose. No root motion or gameplay clock is used.
		var skeleton: Skeleton3D = runtime.skeleton
		for index in skeleton.get_bone_count():
			var previous: Array = _blend_from[index]
			skeleton.set_bone_pose_position(index, (previous[0] as Vector3).lerp(skeleton.get_bone_pose_position(index), weight))
			skeleton.set_bone_pose_rotation(index, (previous[1] as Quaternion).slerp(skeleton.get_bone_pose_rotation(index), weight))
			skeleton.set_bone_pose_scale(index, (previous[2] as Vector3).lerp(skeleton.get_bone_pose_scale(index), weight))
		if weight >= 1.0:
			_blend_from.clear()
	staff_socket.on_skeleton_update()
	staff_slide = _sample_staff_slide(_clip.get_file(), clip_time / maxf(clip_length, 0.000001))
	if kind == "collapse":
		staff_slide = lerpf(_collapse_grip_from, staff_slide, clampf(_collapse_elapsed / COLLAPSE_BLEND_SECONDS, 0.0, 1.0))
	staff_root.position = STAFF_GRIP_OFFSET + STAFF_GRIP_BASIS.y * staff_slide
	playback_speed = _run_rate if kind == "run" else 1.0
	if kind in ["attack", "cast", "hit_react"]:
		playback_speed = clip_length / motion_duration
		if kind != "hit_react":
			if _release_elapsed >= 0.0:
				playback_speed = clip_length * (1.0 - authored_release_ratio) / maxf(motion_duration - _release_elapsed, 0.000001)
			elif motion_elapsed / motion_duration < gameplay_release_ratio and gameplay_release_ratio > 0:
				playback_speed *= authored_release_ratio / gameplay_release_ratio
			elif gameplay_release_ratio < 1:
				playback_speed *= (1.0 - authored_release_ratio) / (1.0 - gameplay_release_ratio)

func replace_parts(request: Dictionary) -> bool:
	if not loaded_ok:
		return false
	var ok: bool = runtime.replace_parts(request)
	last_error = runtime.last_error
	return ok

func debug_snapshot() -> Dictionary:
	return {"ready": loaded_ok, "loaded_ok": loaded_ok, "last_error": last_error,
		"state": _state, "clip": _clip, "position": clip_time, "clip_time": clip_time,
		"length": clip_length, "normalized_time": clip_time / maxf(clip_length, 0.000001),
		"playback_speed": playback_speed, "action_duration": motion_duration, "motion_duration": motion_duration,
		"motion_elapsed": motion_elapsed, "release_ratio": gameplay_release_ratio,
		"release_elapsed": _release_elapsed,
		"gameplay_release_ratio": gameplay_release_ratio, "authored_release_ratio": authored_release_ratio,
		"paused": is_paused, "dead": is_dead, "field_cleared": is_cleared,
		"frozen": is_paused or _state == "dead" or is_cleared,
		"attack_variant": _attack_clip_kind, "staff_slide_m": staff_slide,
		"collapse_elapsed": _collapse_elapsed,
		"movement_speed": movement_speed, "run_cycle_distance": RUN_CYCLE_DISTANCE,
		"locomotion_blending": not _blend_from.is_empty(),
		"bone_count": runtime.skeleton.get_bone_count() if loaded_ok else 0,
		"staff_attached": is_instance_valid(staff_socket) and staff_socket.bone_name == "DEF-hand.R"}

func debug_state() -> Dictionary:
	return debug_snapshot()
