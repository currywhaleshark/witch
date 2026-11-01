extends Node3D
## Presentation only. The arena owns movement, resource costs, hit tests and clocks.
const Modular = preload("res://scripts/modular_character_runtime.gd")
const Shape = preload("res://scripts/shapes.gd")
const StaffVisual = preload("res://scripts/staff_visual.gd")
const StaffLocomotionBlend = preload("res://scripts/staff_locomotion_blend.gd")
const SpringJumpMotion = preload("res://scripts/spring_jump_motion.gd")
const FieldEntry = preload("res://scripts/field_entry_transformation.gd")
const HairMotion = preload("res://scripts/hair_motion.gd")
const ENTRY_DIR := "res://assets/characters/player/transformation_v26/"
const SPRING_JUMP_DIR := "res://assets/characters/player/spring_jump_v24/"
const ASSET_DIR := "res://assets/characters/player/run_arm_v21/"
const MODEL_DIR := "res://assets/characters/player/model_refinement_v28/"
# v29 replaces only the hand mesh of the v28 body (same rig, binds and clips); eyes/outfit stay v28.
const BODY_PATH := "res://assets/characters/player/hand_rebuild_v29/body_standard_v29.glb"
const PARTS := {
	"hair": {"asset": ASSET_DIR + "hair_semilong_v21.glb", "hide_body_regions": []},
	"eyes": {"asset": MODEL_DIR + "eyes_neutral_v28.glb", "hide_body_regions": []},
	"outfit": {"asset": MODEL_DIR + "outfit_civilian_v28.glb", "hide_body_regions": ["torso", "arms", "lowerlegs", "feet"]},
}
const HAIR_V27 := {"asset": "res://assets/characters/player/transformation_v27/hair_semilong_v27.glb", "hide_body_regions": [], "auxiliary_hair": true}
# The previous presentation remains available through an explicit debug override.
var use_entry_polish_v27 := bool(ProjectSettings.get_setting("debug/entry_polish_v27", true))
const CLIPS := {
	"idle": "combat_idle_rh_v20", "run": "combat_run_rh_v21",
	"attack": "combat_heavy_swing_rh_v20", "attack_thrust": "combat_thrust_rh_v23",
	"cast": "combat_cast_rh_v20", "hit_react": "combat_hit_rh_v20", "collapse": "combat_collapse_rh_v20",
	"spring_jump": "combat_spring_jump_v24",
	"entry": "combat_transform_entry_v26",
}
# Clips authored after the v21 family, exported alone onto the same rig and added to its library.
const EXTRA_CLIP_FILES := [ASSET_DIR + "combat_thrust_rh_v23.glb", SPRING_JUMP_DIR + "combat_spring_jump_v24.glb", ENTRY_DIR + "combat_transform_entry_v26.glb"]
# Authored release: swing 25/49, thrust 25/49, cast 17/33; normalized 0.5.
const AUTHORED_RELEASE := {"attack": 0.5, "cast": 0.5, "spring_jump": 0.25}
const STAFF_GRIP_OFFSET := Vector3(0.0074299751, 0.0480000079, 0.0158048961)
const STAFF_GRIP_BASIS := Basis(Vector3(0, -1, 0), Vector3(0.9106548, 0, -0.4131677), Vector3(0.4131677, 0, 0.9106548))
# Run weight ramps in and out instead of switching clips outright, eased, so a move of only a few
# frames leans a little rather than flicking the staff into the run pose and back.
const RUN_BLEND_IN_SECONDS := 0.2
const RUN_BLEND_OUT_SECONDS := 0.15
# The shown body follows the gameplay facing at this rate (180 degrees in about 0.16s).
const TURN_RATE := 20.0
# The authored model stands 1.711m to the top of the hair; the witch is a middle-schooler of 1.5m,
# so the whole asset (staff included) is scaled down and the measured stride with it.
const MODEL_HEIGHT := 1.711
const CHARACTER_HEIGHT := 1.5
const MODEL_SCALE := CHARACTER_HEIGHT / MODEL_HEIGHT
# v21 arm correction retains the selected compact run's measured stride (authored at full size).
const AUTHORED_RUN_CYCLE_DISTANCE := 3.242813140153885
const RUN_CYCLE_DISTANCE := AUTHORED_RUN_CYCLE_DISTANCE * MODEL_SCALE
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
var staff_visual: StaffVisual
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
var _idle_time := 0.0
var _run_time := 0.0
var _run_weight := 0.0
var _staff_locomotion_blend := StaffLocomotionBlend.new()
var _spring_jump := SpringJumpMotion.new()
var _turn_lag := 0.0
var _last_yaw := 0.0
var _turn_seen := false
var _clips: Dictionary = {}
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
var form := "civilian"
var _entry: FieldEntry
var _hair_motion := HairMotion.new()
var _entry_contract: Dictionary
var _transformed_scene: PackedScene
const COLLAPSE_BLEND_SECONDS := 0.18

func _add_clips(path: String) -> bool:
	# The extra GLB holds only the rig (with one skinned carrier mesh) and one action, named after
	# the file; its bone tracks use the same PlayerRig_v7/Skeleton3D paths as the body.
	var scene = load(path)
	if not scene is PackedScene:
		return false
	var holder: Node = scene.instantiate()
	var players := holder.find_children("*", "AnimationPlayer", true, false)
	var found := players.size() == 1 and (players[0] as AnimationPlayer).get_animation_list().size() == 1
	if found:
		var source: AnimationPlayer = players[0]
		var library: AnimationLibrary = runtime.animation_player.get_animation_library("")
		var clip := path.get_file().get_basename()
		if not library.has_animation(clip):
			library.add_animation(clip, source.get_animation(source.get_animation_list()[0]))
	holder.free()
	return found

func initialize() -> bool:
	name = "PlayerVisual"
	# This private generator never consumes combat/global random numbers.
	_attack_rng.randomize()
	asset_wrapper = Node3D.new()
	asset_wrapper.name = "AssetFacing"
	# Exported character faces +Z; arena's existing look_at faces -Z.
	asset_wrapper.rotation.y = PI
	asset_wrapper.scale = Vector3.ONE * MODEL_SCALE
	add_child(asset_wrapper)
	runtime = Modular.new()
	runtime.name = "ModularCharacter"
	asset_wrapper.add_child(runtime)
	if not runtime.initialize(BODY_PATH):
		return _fail(runtime.last_error)
	if runtime.skeleton.get_bone_count() != 107:
		return _fail("expected_v11_family_107_bones")
	var initial_parts: Dictionary = PARTS.duplicate(true)
	if use_entry_polish_v27: initial_parts.hair = HAIR_V27
	if not runtime.replace_parts(initial_parts):
		return _fail(runtime.last_error)
	_hair_motion.initialize(runtime)
	for path in EXTRA_CLIP_FILES:
		if not _add_clips(path):
			return _fail("missing_extra_clip_file: " + path)
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
	var jump_contract = JSON.parse_string(FileAccess.get_file_as_string(SPRING_JUMP_DIR + "runtime_contract.json"))
	if not jump_contract is Dictionary or not jump_contract.get("staff_slide_tracks") is Dictionary:
		return _fail("missing_spring_jump_contract")
	_staff_slide_tracks.merge(jump_contract.staff_slide_tracks)
	var entry_data = JSON.parse_string(FileAccess.get_file_as_string(ENTRY_DIR + "runtime_contract.json"))
	if not entry_data is Dictionary or not entry_data.get("staff_slide_tracks") is Dictionary:
		return _fail("missing_field_entry_contract")
	_entry_contract = entry_data
	_staff_slide_tracks.merge(entry_data.staff_slide_tracks)
	for clip in CLIPS.values():
		var slide_track = _staff_slide_tracks.get(clip)
		if not slide_track is Array or slide_track.size() < 2:
			return _fail("missing_staff_slide_track: " + clip)
	_build_staff()
	if not staff_visual.loaded_ok:
		return _fail(staff_visual.last_error)
	_staff_locomotion_blend.initialize(runtime.skeleton, Transform3D(STAFF_GRIP_BASIS, STAFF_GRIP_OFFSET))
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
	staff_visual = StaffVisual.new()
	staff_visual.name = "StaffAppearance"
	staff_root.add_child(staff_visual)
	staff_visual.initialize()
	staff_head = staff_visual.common_root
	tool_visuals = staff_visual.tool_roots
	# Rotation is owned by StaffVisual so each mechanism respects assembly and pause.
	grinder_disk = null

func set_active_tool(tool) -> void:
	if not loaded_ok:
		return
	staff_visual.set_tool(tool)

func set_staff_appearance(profile: String) -> bool:
	return loaded_ok and staff_visual.set_appearance(profile)

func set_form(next_form: String) -> bool:
	if not loaded_ok or next_form not in ["civilian","transformed"]: return false
	if next_form == form: return true
	var part: Dictionary = PARTS.outfit.duplicate(true)
	if next_form == "transformed": part.asset = FieldEntry.OUTFIT
	if not replace_parts({"outfit":part}): return false
	form = next_form
	return true

func begin_field_entry() -> void:
	if not loaded_ok: return
	if is_instance_valid(_entry):
		_entry.cancel()
		_entry.free()
	if not set_form("civilian"): return
	# Warm the selected outfit before the timed swap, retaining the currently
	# visible civilian garment until replace_parts commits the whole replacement.
	_transformed_scene = ResourceLoader.load(FieldEntry.OUTFIT) as PackedScene
	_entry = FieldEntry.new()
	_entry.name = "FieldEntryTransformation"
	asset_wrapper.add_child(_entry)
	_entry.initialize(self,_entry_contract)
	_entry.begin()
	_hair_motion.reset()

func field_entry_active() -> bool:
	return is_instance_valid(_entry) and _entry.active

func consume_entry_cues() -> Array:
	if not is_instance_valid(_entry): return []
	var pending: Array = _entry.cues.duplicate()
	_entry.cues.clear()
	return pending

func begin_motion(kind: String, duration: float, release_ratio: float) -> void:
	if not loaded_ok or is_dead or kind not in ["attack", "cast", "spring_jump"]:
		return
	_motion_kind = kind
	if kind == "attack":
		_attack_clip_kind = "attack" if _attack_rng.randf() < 0.5 else "attack_thrust"
	_state = kind
	motion_duration = maxf(duration, 0.000001)
	motion_elapsed = 0.0
	_release_pending = false
	_release_elapsed = -1.0
	gameplay_release_ratio = clampf(release_ratio, 0.0, 1.0)
	authored_release_ratio = AUTHORED_RELEASE[kind]
	_sample(kind, 0.0)

func mark_release() -> void:
	if loaded_ok and _motion_kind in ["attack", "cast", "spring_jump"]:
		if _motion_kind == "attack":
			staff_visual.finish_assembly()
		# The arena signals the real physics frame that crosses its release clock.
		_release_pending = true

func launch_spring_jump(duration: float) -> void:
	if not loaded_ok or is_dead: return
	_motion_kind = ""
	_release_pending = false
	_release_elapsed = -1.0
	_spring_jump.launch(self, duration)

func update_spring_jump(progress: float) -> void:
	_spring_jump.set_progress(progress)

func land_spring_jump() -> void:
	if loaded_ok: _spring_jump.finish(self)

func cancel_spring_preparation() -> void:
	if _motion_kind != "spring_jump": return
	_motion_kind = ""
	_release_pending = false
	_release_elapsed = -1.0

func hit_react(duration: float) -> void:
	if not loaded_ok or is_dead:
		return
	# Only the arena's actual stun branch invokes this; blocked/minor hits do not.
	_motion_kind = "hit_react"
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
	if field_entry_active(): _entry.cancel()
	is_dead = true
	_state = "collapse"
	_motion_kind = ""
	_release_pending = false
	_release_elapsed = -1.0
	_collapse_elapsed = 0.0
	_collapse_grip_from = staff_slide
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
	if field_entry_active():
		_entry.advance(dt)
		_hair_motion.advance(dt, _entry.elapsed)
		return
	_spring_jump.advance(self, dt, is_dead, cleared)
	var staff_release := -1.0
	if _motion_kind == "attack" and _release_elapsed < 0.0:
		staff_release = maxf(0.0, action_remaining - motion_duration * (1.0-gameplay_release_ratio))
	_sync_pose(dt, moved, action_remaining, cleared, actual_speed)
	_hair_motion.advance(dt, -1.0, _state == "dead" or cleared)
	# Use the pose just sampled, including the real release latch. The former order
	# drove the jaws with last frame's phase and reopened them on the impact frame.
	staff_visual.advance(dt, is_dead or cleared,
		clip_time / maxf(clip_length,.000001) if _motion_kind == "attack" else -1.0, staff_release)

func _sync_pose(dt: float, moved: bool, action_remaining: float, cleared: bool, actual_speed: float) -> void:
	_settle_turn(dt)
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
			_run_weight = 0.0
			_sample("idle", 0.0)
			_state = "cleared"
		return
	if _spring_jump.sample_pose(self):
		return
	if not _motion_kind.is_empty():
		if action_remaining > 0 or _release_pending:
			# Use the combat clock, including FCR/IAS/FHR and same-frame interrupts.
			motion_elapsed = clampf(motion_duration - action_remaining, 0.0, motion_duration)
			var progress := motion_elapsed / motion_duration
			var normalized := progress
			if _motion_kind in ["attack", "cast", "spring_jump"]:
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
	var step := maxf(dt, 0.0)
	if _state not in ["idle", "run"]:
		# Leaving an action (or loading) goes straight to the matching clip, as before.
		_run_weight = 1.0 if moved else 0.0
		_run_time = 0.0
	elif moved and _run_weight <= 0.0:
		_run_time = 0.0
	_state = "run" if moved else "idle"
	movement_speed = maxf(actual_speed, 0.0)
	_run_rate = actual_speed * _length("run") / RUN_CYCLE_DISTANCE if actual_speed >= 0 else 1.0
	_run_weight = clampf(_run_weight + (step / RUN_BLEND_IN_SECONDS if moved else -step / RUN_BLEND_OUT_SECONDS), 0.0, 1.0)
	# Idle keeps its own phase so stopping never restarts it; a stopped run holds its last stride.
	_idle_time = fposmod(_idle_time + step, maxf(_length("idle"), 0.000001))
	if moved:
		_run_time = fposmod(_run_time + step * _run_rate, maxf(_length("run"), 0.000001))
	_sample_locomotion(smoothstep(0.0, 1.0, _run_weight))

func _sample_locomotion(weight: float) -> void:
	# Presentation-only mix of the idle and run poses; no root motion or gameplay clock is used.
	if weight <= 0.0:
		_sample("idle", _idle_time)
		return
	if weight >= 1.0:
		_sample("run", _run_time)
		return
	# Sample the other clip first so the selected clip, its time and playback rate stay those of the
	# current state; then mix towards the other pose by its share.
	var running := _state == "run"
	var share := 1.0 - weight if running else weight
	if running:
		_sample("idle", _idle_time)
	else:
		_sample("run", _run_time)
	var skeleton: Skeleton3D = runtime.skeleton
	var other_arms := _staff_locomotion_blend.capture(skeleton)
	var other_pose: Array = []
	for index in skeleton.get_bone_count():
		other_pose.append([skeleton.get_bone_pose_position(index), skeleton.get_bone_pose_rotation(index), skeleton.get_bone_pose_scale(index)])
	var other_slide := staff_slide
	if running:
		_sample("run", _run_time)
	else:
		_sample("idle", _idle_time)
	var selected_arms := _staff_locomotion_blend.capture(skeleton)
	for index in skeleton.get_bone_count():
		var other: Array = other_pose[index]
		skeleton.set_bone_pose_position(index, skeleton.get_bone_pose_position(index).lerp(other[0], share))
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index).slerp(other[1], share))
		skeleton.set_bone_pose_scale(index, skeleton.get_bone_pose_scale(index).lerp(other[2], share))
	_staff_locomotion_blend.apply(skeleton, selected_arms, other_arms, share)
	staff_socket.on_skeleton_update()
	staff_slide = lerpf(staff_slide, other_slide, share)
	staff_root.position = STAFF_GRIP_OFFSET + STAFF_GRIP_BASIS.y * staff_slide
	_hair_motion.sync_anchors()

func _settle_turn(dt: float) -> void:
	# The gameplay facing (this node) turns at once; only the shown body eases after it. Actions
	# face their target immediately, as before.
	var yaw := rotation.y
	if _turn_seen:
		_turn_lag = wrapf(_turn_lag - wrapf(yaw - _last_yaw, -PI, PI), -PI, PI)
	_turn_seen = true
	_last_yaw = yaw
	if not _motion_kind.is_empty() or is_dead:
		_turn_lag = 0.0
	else:
		_turn_lag = move_toward(_turn_lag, 0.0, maxf(dt, 0.0) * TURN_RATE)
	asset_wrapper.rotation.y = PI + _turn_lag

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
	staff_socket.on_skeleton_update()
	staff_slide = _sample_staff_slide(_clip.get_file(), clip_time / maxf(clip_length, 0.000001))
	if kind == "collapse":
		staff_slide = lerpf(_collapse_grip_from, staff_slide, clampf(_collapse_elapsed / COLLAPSE_BLEND_SECONDS, 0.0, 1.0))
	staff_root.position = STAFF_GRIP_OFFSET + STAFF_GRIP_BASIS.y * staff_slide
	_hair_motion.sync_anchors()
	playback_speed = _run_rate if kind == "run" else 1.0
	if kind in ["attack", "cast", "hit_react"] or (kind == "spring_jump" and _motion_kind == "spring_jump"):
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
	if ok: _hair_motion.sync_anchors()
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
		"spring_jump": _spring_jump.debug_state(),
		"form": form, "field_entry": _entry.debug_state() if is_instance_valid(_entry) else {},
		"hair": _hair_motion.debug_state(),
		"movement_speed": movement_speed, "run_cycle_distance": RUN_CYCLE_DISTANCE,
		"locomotion_blending": _state in ["idle", "run"] and _run_weight > 0.0 and _run_weight < 1.0, "run_weight": _run_weight, "turn_lag": _turn_lag,
		"bone_count": runtime.skeleton.get_bone_count() if loaded_ok else 0,
		"staff_attached": is_instance_valid(staff_socket) and staff_socket.bone_name == "DEF-hand.R"}

func debug_state() -> Dictionary:
	return debug_snapshot()
