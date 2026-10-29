extends Node3D
## Presentation only: the arena owns targets, clocks, movement, hits and summon lifetime.
const NodeEffects = preload("res://scripts/automaton_node_effects.gd")
const FILES := {
	"automaton_A": "res://assets/actors/automaton_nodes_v1/automaton_a.glb",
	"automaton_B": "res://assets/actors/automaton_nodes_v1/automaton_b.glb",
	"rag": "res://assets/actors/combat_set_v1/rag_v1.glb",
	"crow": "res://assets/actors/combat_set_v1/crow_v1.glb",
	"brute": "res://assets/actors/combat_set_v1/brute_v1.glb",
	"automaton": "res://assets/actors/summons_v2/automaton_v2.glb",
	"turret": "res://assets/actors/summons_v2/turret_v2.glb",
	"latch": "res://assets/actors/boss_trial_v1/latch_v1.glb",
}
# The wind-up key turns about its own leaning shaft (collar centre towards the bow), model space.
const KEY_PIVOT := Vector3(-0.062, 0.575, 0.099)
const KEY_AXIS := Vector3(-0.0565, 0.16, 0.026)
# The turret's key and its big drive gear share one shaft out of the carriage's back.
const TURRET_KEY_PIVOT := Vector3(0.0, 0.643, 0.3)
const TURRET_KEY_AXIS := Vector3(0.0, -0.041, 1.0)
const TURRET_GEAR_RATIO := 0.4
static var _scenes: Dictionary = {}
static var _knobless: Dictionary = {}
var kind := ""
var appearance_node := "base"
var _node_effects: Node3D
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
var _strike_side := 1.0
var _key_angle := 0.0
var _key_kick := 0.0
var _bones: Dictionary = {}
var _skeleton_frame: Variant = null

static func create(parent: Node3D, actor_kind: String, node_kind: String = "base", total_life: float = 1.0) -> Node3D:
	var asset_key := actor_kind+"_"+node_kind if actor_kind=="automaton" and node_kind in ["A","B"] else actor_kind
	if not FILES.has(asset_key):
		return null
	if not _scenes.has(asset_key):
		_scenes[asset_key] = load(FILES[asset_key])
	if not _scenes[asset_key] is PackedScene:
		return null
	var script_path := "res://scripts/boss_visual.gd" if actor_kind == "latch" else "res://scripts/actor_visual.gd"
	var visual = load(script_path).new()
	visual.name = "ActorVisual"
	visual.kind = actor_kind
	visual.appearance_node = node_kind if asset_key!=actor_kind else "base"
	parent.add_child(visual)
	var model: Node = _scenes[asset_key].instantiate()
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
	if actor_kind == "automaton":
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh is ArrayMesh and mesh.skin != null:
				if not _knobless.has(mesh.mesh):
					_knobless[mesh.mesh] = _without_key_knob(mesh.mesh, mesh.skin)
				mesh.mesh = _knobless[mesh.mesh]
	if actor_kind in ["automaton", "turret", "latch"]:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.custom_aabb = AABB(Vector3(-3.5, -0.2, -3.5), Vector3(7, 4.5 if actor_kind == "latch" else 3.5, 7))
	visual.set_process(false)
	if visual.appearance_node!="base":
		visual._node_effects=NodeEffects.new()
		visual.add_child(visual._node_effects)
		visual._node_effects.initialize(visual,visual.appearance_node,total_life)
	visual.sample("idle", 0.0)
	return visual

static func _without_key_knob(source: ArrayMesh, skin: Skin) -> ArrayMesh:
	# The segmented key part also carries the small knob on the back just below it. Hand the knob's
	# triangles to the body shell so only the key turns. Runtime copy only; the GLBs stay untouched.
	var key_bind := -1
	var body_bind := -1
	for bind in skin.get_bind_count():
		if skin.get_bind_name(bind) == "part_006": key_bind = bind
		if skin.get_bind_name(bind) == "part_000": body_bind = bind
	if key_bind < 0 or body_bind < 0:
		return source
	var result := ArrayMesh.new()
	var changed := false
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var span := bones.size() / maxi(points.size(), 1)
		# Group the key's triangles into connected pieces; a piece wholly below the collar or
		# reaching back past it is the knob.
		var root := {}
		for t in range(0, indices.size(), 3):
			if bones[indices[t] * span] != key_bind:
				continue
			var a := _root_of(root, indices[t])
			for k in [1, 2]:
				var b := _root_of(root, indices[t + k])
				if a != b: root[b] = a
		var pieces := {}
		var spread := {}
		for vertex in root:
			var piece: int = _root_of(root, vertex)
			pieces[piece] = (pieces[piece] as AABB).expand(points[vertex]) if pieces.has(piece) else AABB(points[vertex], Vector3.ZERO)
			var off_collar := Vector2(points[vertex].x - KEY_PIVOT.x, points[vertex].z - KEY_PIVOT.z).length()
			spread[piece] = maxf(spread.get(piece, 0.0), off_collar)
		for vertex in root:
			var piece: int = _root_of(root, vertex)
			var box: AABB = pieces[piece]
			if box.end.y < 0.565 and (box.position.y < 0.528 or box.end.z > 0.16 or spread[piece] > 0.07):
				for j in span:
					if bones[vertex * span + j] == key_bind: bones[vertex * span + j] = body_bind
				changed = true
		arrays[Mesh.ARRAY_BONES] = bones
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if span == 8 else 0)
		result.surface_set_material(surface, source.surface_get_material(surface))
		result.surface_set_name(surface, source.surface_get_name(surface))
	return result if changed else source

static func _root_of(root: Dictionary, vertex: int) -> int:
	if not root.has(vertex):
		root[vertex] = vertex
	while root[vertex] != vertex:
		root[vertex] = root[root[vertex]]
		vertex = root[vertex]
	return vertex

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
	var seek := fraction
	if kind == "automaton" and clip == "attack" and fraction < 0.5:
		# The clip's own reach would muddle the pull-back; it snaps in at the release instead.
		seek = fraction * 0.3
	player.seek(player.get_animation(animation).length * seek, true)
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
	if kind == "automaton" and clip not in ["death", "explode"]:
		_apply_clockwork(clip)
	elif kind == "turret" and clip != "death":
		# The clips only rock the key and gear; they turn continuously about their shaft instead.
		_spin_part(_bone("key"), TURRET_KEY_AXIS, TURRET_KEY_PIVOT, _key_angle)
		_spin_part(_bone("drive_gear"), TURRET_KEY_AXIS, TURRET_KEY_PIVOT, _key_angle * TURRET_GEAR_RATIO)
	skeleton.force_update_all_bone_transforms()
	_sample_blast(clip, fraction)
	if _node_effects!=null: _node_effects.apply_pose()

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

func _apply_clockwork(clip: String) -> void:
	# Procedural layer over the authored clips: the wind-up key keeps turning, and the attack becomes
	# a wound-up lunge punch alternating arms (B: a wide cut with its saw arm). The lunge only offsets
	# this visual; the gameplay node stays where the arena put it.
	_spin_key(_key_angle)
	var wind := 0.0
	var reach := 0.0
	if clip == "attack":
		wind = smoothstep(0.0, 0.5, fraction) if fraction < 0.5 else 0.0
		reach = 1.0 - smoothstep(0.58, 1.0, fraction) if fraction >= 0.5 else 0.0
	position = Vector3(0, -0.03 * wind + 0.2 * reach * (1.0 - reach), 0.07 * wind - 0.2 * reach)
	if wind == 0.0 and reach == 0.0:
		return
	var side := _strike_side
	var saw := appearance_node == "B"
	_turn_bone(_bone("torso"), Vector3.UP, side * (0.6 if saw else 0.4) * (reach - wind))
	_turn_bone(_bone("torso"), Vector3.RIGHT, 0.22 * wind - 0.3 * reach)
	_turn_bone(_bone("head"), Vector3.RIGHT, -0.12 * wind + 0.2 * reach)
	var arm := _bone("arm_L" if side > 0 else "arm_R")
	if saw:
		_turn_bone(arm, Vector3.RIGHT, -0.4 * wind + 0.95 * reach)
		_turn_bone(arm, Vector3.UP, side * (0.8 * reach - 0.6 * wind))
	else:
		_turn_bone(arm, Vector3.RIGHT, -0.7 * wind + 0.85 * reach)
		_turn_bone(arm, Vector3.UP, side * 0.25 * reach)
		_turn_bone(_bone("forearm_L" if side > 0 else "forearm_R"), Vector3.RIGHT, 0.5 * wind - 0.55 * reach)
	_turn_bone(_bone("arm_R" if side > 0 else "arm_L"), Vector3.RIGHT, 0.35 * wind - 0.35 * reach)

func _spin_key(angle: float) -> void:
	# Turns the key part about its shaft line. The authored clips rock the "key" bone about the
	# front-back axis through an off-shaft origin, which swings the key like a wiper; hold that bone
	# at rest so only this spin remains.
	var holder := _bone("key")
	if holder >= 0:
		skeleton.set_bone_pose(holder, skeleton.get_bone_rest(holder))
	_spin_part(_bone("part_006"), KEY_AXIS, KEY_PIVOT, angle)

func _spin_part(index: int, model_axis: Vector3, model_pivot: Vector3, angle: float) -> void:
	# Sets a part to its rest pose turned by angle about a shaft line given in model space. Expressed
	# in the parent's rest frame, so the part still follows whatever its parent does.
	if index < 0:
		return
	var parent_rest := skeleton.get_bone_global_rest(skeleton.get_bone_parent(index))
	var axis := (parent_rest.basis.inverse() * model_axis).normalized()
	var pivot := parent_rest.affine_inverse() * model_pivot
	var turn := Basis(axis, angle)
	var pose := Transform3D(turn, pivot - turn * pivot) * skeleton.get_bone_rest(index)
	skeleton.set_bone_pose_position(index, pose.origin)
	skeleton.set_bone_pose_rotation(index, pose.basis.get_rotation_quaternion())

func _bone(bone_name: String) -> int:
	if not _bones.has(bone_name):
		_bones[bone_name] = skeleton.find_bone(bone_name)
	return _bones[bone_name]

func _turn_bone(index: int, axis: Vector3, angle: float) -> void:
	# Turns a bone about an axis of this actor's own frame (forward -Z) on top of its clip pose.
	if index < 0 or is_zero_approx(angle):
		return
	if _skeleton_frame == null:
		var frame := Basis()
		var node: Node = skeleton
		while node != self and node is Node3D:
			frame = (node as Node3D).basis * frame
			node = node.get_parent()
		_skeleton_frame = frame
	skeleton.force_update_all_bone_transforms()
	var parent := skeleton.get_bone_parent(index)
	var parent_frame: Basis = _skeleton_frame * (skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis())
	var local := (parent_frame.inverse() * axis).normalized()
	skeleton.set_bone_pose_rotation(index, Quaternion(local, angle) * skeleton.get_bone_pose_rotation(index))

func strike_point() -> Vector3:
	# The fist (or saw hand) of the striking arm, where the punch lands visually.
	var muzzle := _bone("muzzle")
	var forearm := _bone("forearm_L" if _strike_side > 0 else "forearm_R")
	if muzzle < 0 or forearm < 0:
		return muzzle_position()
	var point := skeleton.get_bone_global_rest(muzzle).origin
	if _strike_side < 0:
		point.x = -point.x
	var local := skeleton.get_bone_global_rest(forearm).affine_inverse() * point
	return skeleton.global_transform * skeleton.get_bone_global_pose(forearm) * local

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

func sync_ally(ally: Dictionary, dt: float, target_distance: float = INF) -> void:
	if _node_effects!=null: _node_effects.sync(ally,dt,target_distance)
	var distance: float = ally.node.global_position.distance_to(_last_position)
	_last_position = ally.node.global_position
	_clock += dt
	_move_clock += minf(distance / 0.65, dt * 3.0)
	if kind == "turret":
		_turret_yaw = ally.node.rotation.y
		rotation.y = -_turret_yaw
	var fired := float(ally.cooldown) > _last_cooldown + 0.01
	# The key unwinds slowly while it works. The automaton cranks it hard during its wind-up; the
	# turret's key whirs up into each shot and spins down through the recoil.
	_key_kick = 1.0 if fired else maxf(0.0, _key_kick - dt * 2.5)
	var winding := visual_state == "attack" and fraction < 0.5
	var rate := 1.5 + (5.0 if winding else 0.0) + 26.0 * _key_kick * _key_kick
	if kind == "automaton":
		rate = 24.0 if winding else 1.5
	# Five turns keep the slower geared parts continuous across the wrap.
	_key_angle = fposmod(_key_angle + dt * rate, TAU * 5.0)
	# Automatons wind up longer and may still be shuffling into reach; turrets only aim in place.
	var window := 0.3 if kind == "automaton" else 0.18
	var in_reach := distance < 0.0001 or (kind == "automaton" and target_distance <= float(ally.get("reach", 1.6)) + 0.3)
	_last_cooldown = ally.cooldown
	if fired:
		_recovery = 0.0
		sample("attack", 0.5)
		release_samples.append(fraction)
		if release_samples.size() > 16: release_samples.pop_front()
	elif _recover(dt):
		pass
	elif ally.target != "" and float(ally.cooldown) < window and in_reach:
		sample("attack", clampf((window - float(ally.cooldown)) / window, 0.0, 1.0) * 0.5)
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
		if kind == "automaton" and appearance_node != "B":
			_strike_side = -_strike_side
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
	if _node_effects!=null: _node_effects.apply_pose()

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
	return {"kind": kind, "appearance_node":appearance_node, "node_effects":_node_effects.debug_state() if _node_effects!=null else {}, "loaded": loaded_ok, "state": visual_state, "fraction": fraction,
		"clips": clips.keys(), "bones": skeleton.get_bone_count() if skeleton else 0,
		"release_samples": release_samples.duplicate(), "dead": _death_time >= 0,
		"death_clip": _death_clip, "death_duration": _death_duration}
