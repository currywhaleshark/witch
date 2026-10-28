extends Node3D
## Presentation only: the arena owns targets, clocks, movement, hits and summon lifetime.
const FILES := {
	"rag": "res://assets/actors/combat_set_v1/rag_v1.glb",
	"crow": "res://assets/actors/combat_set_v1/crow_v1.glb",
	"brute": "res://assets/actors/combat_set_v1/brute_v1.glb",
	"automaton": "res://assets/actors/summons_v2/automaton_v2.glb",
	"turret": "res://assets/actors/summons_v2/turret_v2.glb",
	"latch": "res://assets/actors/boss_trial_v1/latch_v1.glb",
}
static var _scenes: Dictionary = {}
var kind := ""
var loaded_ok := false
var player: AnimationPlayer
var skeleton: Skeleton3D
var clips: Dictionary = {}
var visual_state := "idle"
var fraction := 0.0
var release_samples: Array[float] = []
var _clock := 0.0
var _move_clock := 0.0
var _last_position := Vector3.ZERO
var _last_flash := 0.0
var _last_cooldown := 0.2
var _reaction := 0.0
var _pending_release := false
var _attack_total := 0.0
var _recovery := -1.0
var _death_time := -1.0
var _pause_source: Node
var _turret_yaw := 0.0
var _death_clip := "death"
var _death_duration := 1.25
var _death_start_pose: Array[Transform3D] = []
var _blast_flash: MeshInstance3D
var _blast_sparks: Array[MeshInstance3D] = []

static func create(parent: Node3D, actor_kind: String) -> Node3D:
	if not FILES.has(actor_kind):
		return null
	if not _scenes.has(actor_kind):
		_scenes[actor_kind] = load(FILES[actor_kind])
	if not _scenes[actor_kind] is PackedScene:
		return null
	var script_path := "res://scripts/boss_visual.gd" if actor_kind == "latch" else "res://scripts/actor_visual.gd"
	var visual = load(script_path).new()
	visual.name = "ActorVisual"
	visual.kind = actor_kind
	parent.add_child(visual)
	var model: Node = _scenes[actor_kind].instantiate()
	visual.add_child(model)
	visual.player = visual._find_node(model, "AnimationPlayer")
	visual.skeleton = visual._find_node(model, "Skeleton3D")
	if visual.player == null or visual.skeleton == null:
		visual.queue_free()
		return null
	visual.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for animation in visual.player.get_animation_list():
		for canonical in ["idle", "move", "attack", "charge", "hit", "death", "explode", "sweep", "slam", "frames", "shockwave"]:
			if animation == canonical or animation.ends_with("|" + canonical) or animation.ends_with("/" + canonical):
				visual.clips[canonical] = animation
	var required := ["idle", "move", "sweep", "slam", "frames", "shockwave", "hit", "death"] if actor_kind == "latch" else ["idle", "attack", "hit", "death"]
	visual.loaded_ok = visual.clips.has_all(required)
	visual._last_position = parent.global_position
	if actor_kind in ["automaton", "turret", "latch"]:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.custom_aabb = AABB(Vector3(-3.5, -0.2, -3.5), Vector3(7, 4.5 if actor_kind == "latch" else 3.5, 7))
	visual.set_process(false)
	visual.sample("idle", 0.0)
	return visual

func _find_node(node: Node, class_name_: String) -> Node:
	if node.is_class(class_name_):
		return node
	for child in node.get_children():
		var found := _find_node(child, class_name_)
		if found != null:
			return found
	return null

func sample(clip: String, phase: float) -> void:
	if not loaded_ok or not clips.has(clip):
		return
	visual_state = clip
	fraction = clampf(phase, 0.0, 1.0)
	var animation: String = clips[clip]
	if player.current_animation != animation:
		player.play(animation)
	player.seek(player.get_animation(animation).length * fraction, true)
	# Keep the tripod planted while the upper carriage follows the arena's aim.
	if kind == "turret":
		var index := skeleton.find_bone("carriage")
		if index >= 0:
			# The segmented rig has a different root rest basis than v1. Convert
			# world-up through the full rest chain, not only the carriage's local rest.
			var rest := skeleton.get_bone_global_rest(index).basis
			var up := (rest.inverse() * skeleton.global_basis.inverse() * Vector3.UP).normalized()
			var yaw := Basis(up, _turret_yaw)
			skeleton.set_bone_pose_rotation(index, yaw.get_rotation_quaternion() * skeleton.get_bone_pose_rotation(index))
	skeleton.force_update_all_bone_transforms()
	_sample_blast(clip, fraction)

func _sample_blast(clip: String, phase: float) -> void:
	if kind != "automaton":
		return
	if clip == "explode" and _blast_flash == null:
		var flash_material := StandardMaterial3D.new()
		flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash_material.albedo_color = Color(0.8, 1.0, 0.85, 1.0)
		var orb := SphereMesh.new()
		orb.radius = 0.12; orb.height = 0.24
		orb.radial_segments = 12; orb.rings = 6
		_blast_flash = MeshInstance3D.new()
		_blast_flash.mesh = orb; _blast_flash.material_override = flash_material
		_blast_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_blast_flash)
		for i in 10:
			var spark := MeshInstance3D.new()
			spark.mesh = orb; spark.material_override = flash_material
			spark.scale = Vector3.ONE * 0.13
			spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(spark); _blast_sparks.append(spark)
	if _blast_flash == null:
		return
	var seconds := phase * 2.0
	_blast_flash.visible = clip == "explode" and seconds < 0.18
	_blast_flash.position = Vector3(0, 0.40, 0)
	_blast_flash.scale = Vector3.ONE * (1.0 + 3.5 * sin(clampf(seconds / 0.18, 0.0, 1.0) * PI))
	var material: StandardMaterial3D = _blast_flash.material_override
	material.albedo_color.a = maxf(0.0, 1.0 - seconds / 0.45)
	for i in _blast_sparks.size():
		var spark := _blast_sparks[i]
		spark.visible = clip == "explode" and seconds < 0.45
		var angle := float(i) * TAU / 10.0
		var velocity := Vector3(cos(angle) * 3.2, 1.4 + (i % 3) * 0.5, sin(angle) * 3.2)
		spark.position = Vector3(0, 0.4, 0) + velocity * seconds + Vector3.DOWN * 3.25 * seconds * seconds

func begin_attack(_attack: String, windup: float) -> void:
	_attack_total = maxf(windup, 0.0001)
	_pending_release = true
	_recovery = -1.0

func sync_enemy(enemy: Dictionary, dt: float) -> void:
	var distance: float = enemy.body.global_position.distance_to(_last_position)
	_last_position = enemy.body.global_position
	_clock += dt
	_move_clock += minf(distance / (0.9 if kind == "brute" else 1.0), dt * 3.5)
	_reaction = maxf(0, _reaction - dt)
	if float(enemy.flash) > _last_flash + 0.02:
		_reaction = 0.26
	_last_flash = enemy.flash
	if _pending_release:
		if enemy.windup > 0:
			sample("attack", 0.5 * (1.0 - float(enemy.windup) / _attack_total))
		else:
			_pending_release = false
			_recovery = 0.0
			sample("attack", 0.5)
			release_samples.append(fraction)
			if release_samples.size() > 16: release_samples.pop_front()
		return
	if float(enemy.get("charging", 0)) > 0 and clips.has("charge"):
		sample("charge", fposmod(_move_clock, 1.0))
		return
	if _recover(dt):
		return
	if _reaction > 0:
		sample("hit", 1.0 - _reaction / 0.26)
	elif distance > 0.0001 and clips.has("move"):
		sample("move", fposmod(_move_clock, 1.0))
	else:
		sample("idle", fposmod(_clock / 2.0, 1.0))

func sync_ally(ally: Dictionary, dt: float) -> void:
	var distance: float = ally.node.global_position.distance_to(_last_position)
	_last_position = ally.node.global_position
	_clock += dt
	_move_clock += minf(distance / 0.65, dt * 3.0)
	if kind == "turret":
		_turret_yaw = ally.node.rotation.y
		rotation.y = -_turret_yaw
	var fired := float(ally.cooldown) > _last_cooldown + 0.01
	_last_cooldown = ally.cooldown
	if fired:
		_recovery = 0.0
		sample("attack", 0.5)
		release_samples.append(fraction)
		if release_samples.size() > 16: release_samples.pop_front()
	elif _recover(dt):
		pass
	elif ally.target != "" and float(ally.cooldown) < 0.18 and distance < 0.0001:
		sample("attack", clampf((0.18 - float(ally.cooldown)) / 0.18, 0.0, 1.0) * 0.5)
	elif distance > 0.0001 and clips.has("move"):
		sample("move", fposmod(_move_clock, 1.0))
	else:
		sample("idle", fposmod(_clock / 2.0, 1.0))

func _recover(dt: float) -> bool:
	if _recovery < 0:
		return false
	_recovery += dt
	if _recovery >= 0.3:
		_recovery = -1.0
		return false
	sample("attack", 0.5 + 0.5 * _recovery / 0.3)
	return true

func detach_for_death(world: Node3D, pause_source: Node, self_destruct: bool = false) -> void:
	if _death_time >= 0:
		return
	_death_clip = "explode" if self_destruct and clips.has("explode") else "death"
	_death_duration = player.get_animation(clips[_death_clip]).length
	_death_start_pose.clear()
	if kind in ["automaton", "turret", "latch"]:
		for index in skeleton.get_bone_count():
			_death_start_pose.append(skeleton.get_bone_pose(index))
	reparent(world, true)
	name = "ActorCorpse"
	add_to_group("actor_corpses")
	_death_time = 0.0
	_pause_source = pause_source
	# The actor has no collision, targets or damage after this point.
	sample(_death_clip, 0.0)
	_blend_death_start()
	set_process(true)

func _blend_death_start() -> void:
	# Begin at the actual aimed/attacking pose; a killed machine must not snap upright.
	var amount := smoothstep(0.0, 0.12, _death_time)
	if amount >= 1.0:
		return
	for index in _death_start_pose.size():
		skeleton.set_bone_pose(index, _death_start_pose[index].interpolate_with(skeleton.get_bone_pose(index), amount))
	skeleton.force_update_all_bone_transforms()

func _process(dt: float) -> void:
	if _death_time < 0 or (is_instance_valid(_pause_source) and _pause_source.paused):
		return
	_death_time += dt
	sample(_death_clip, minf(1.0, _death_time / _death_duration))
	_blend_death_start()
	if _death_time >= _death_duration + 0.25:
		queue_free()

func muzzle_position() -> Vector3:
	var index := skeleton.find_bone("muzzle")
	if index < 0:
		return global_position + Vector3.UP * 0.8
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin

func preview_shot(ally: Dictionary) -> void:
	if kind == "turret":
		_turret_yaw = ally.node.rotation.y
		rotation.y = -_turret_yaw
	sample("attack", 0.5)

func debug_state() -> Dictionary:
	return {"kind": kind, "loaded": loaded_ok, "state": visual_state, "fraction": fraction,
		"clips": clips.keys(), "bones": skeleton.get_bone_count() if skeleton else 0,
		"release_samples": release_samples.duplicate(), "dead": _death_time >= 0,
		"death_clip": _death_clip, "death_duration": _death_duration}
