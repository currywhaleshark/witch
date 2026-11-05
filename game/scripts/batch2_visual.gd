extends Node3D
## Presentation only for the automation tree's second batch (hound, lure beacon, giant automaton).
## The arena and batch2_summons.gd own targets, clocks, movement, hits and lifetime; this samples
## the delivered clips at the times they report. Base and armour share one clip time, and the node
## variants scale the whole wrapper (assets/actors/automation_batch2/catalog.json).
const ROOT := "res://assets/actors/automation_batch2/"
const FILES := {
	"hound": ROOT + "hound_v4/hound_v4.glb",
	"hound_armour": ROOT + "hound_armour_v3/hound_armour_v3.glb",
	"beacon": ROOT + "beacon_v1/beacon_v1.glb",
	"giant": ROOT + "giant_v2/giant_v2.glb",
	"giant_armour": ROOT + "giant_armour_v2/giant_armour_v2.glb",
}
# The clip that plays while it is being summoned, and the ground covered by one walk/run clip at
# scale 1 (hound v4: two gallops 2.754772m per 0.5s clip; giant: 3.12m per 1.2s clip).
const OPENING := {"hound": "spawn", "beacon": "deploy", "giant": "assemble"}
const STRIDE := {"hound": 2.7547715068852785, "giant": 3.12}
const MOVE := {"hound": "run", "giant": "walk"}
const ACTION := {"hound": "bite", "giant": "slam"}
const HIT_REACTION := 0.25
static var _scenes: Dictionary = {}
var kind := ""
var variant_scale := 1.0
var loaded_ok := false
var holder: Node3D
var players: Array[AnimationPlayer] = []
var skeleton: Skeleton3D
var visual_state := ""
var clip_seconds := 0.0
var opening_left := 0.0
var _clock := 0.0
var _move_phase := 0.0
var _last_position := Vector3.ZERO
var _glow: Array[StandardMaterial3D] = []
var _steam: Array[MeshInstance3D] = []
var _death_time := -1.0
var _death_clip := "death"
var _pause_source: Node

static func create(parent: Node3D, actor: String, scale_factor: float = 1.0, armour: bool = false) -> Node3D:
	var visual = load("res://scripts/batch2_visual.gd").new()
	visual.name = "ActorVisual"
	visual.kind = actor
	visual.variant_scale = scale_factor
	parent.add_child(visual)
	visual.holder = Node3D.new()
	visual.holder.name = "Variant"
	visual.holder.scale = Vector3.ONE * scale_factor
	visual.add_child(visual.holder)
	var keys: Array = [actor]
	if armour and FILES.has(actor + "_armour"):
		keys.append(actor + "_armour")
	for key in keys:
		if not _scenes.has(key):
			_scenes[key] = load(FILES[key])
		if not _scenes[key] is PackedScene:
			continue
		var model: Node3D = _scenes[key].instantiate()
		visual.holder.add_child(model)
		var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0] if not model.find_children("*", "AnimationPlayer", true, false).is_empty() else null
		if player == null:
			continue
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		visual.players.append(player)
		if key == actor:
			var found := model.find_children("*", "Skeleton3D", true, false)
			visual.skeleton = found[0] if not found.is_empty() else null
		# Skinned parts swing well outside their rest bounds (death falls, the giant's raised arms).
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.custom_aabb = AABB(Vector3(-3, -0.2, -3), Vector3(6, 4.5, 6))
			for i in mesh.mesh.get_surface_count():
				var source: Material = mesh.mesh.surface_get_material(i)
				if source is StandardMaterial3D and source.emission_enabled:
					var glow: StandardMaterial3D = source.duplicate()
					mesh.set_surface_override_material(i, glow)
					visual._glow.append(glow)
	visual.loaded_ok = not visual.players.is_empty() and visual.skeleton != null
	visual._last_position = parent.global_position
	visual.set_process(false)
	visual.opening_left = visual.clip_length(OPENING[actor])
	visual.sample(OPENING[actor], 0.0)
	return visual

func clip_length(clip: String) -> float:
	if players.is_empty() or not players[0].has_animation(clip):
		return 0.0
	return players[0].get_animation(clip).length

func sample(clip: String, seconds: float) -> void:
	if not loaded_ok:
		return
	visual_state = clip
	clip_seconds = clampf(seconds, 0.0, clip_length(clip))
	for player in players:
		if not player.has_animation(clip):
			continue
		if player.current_animation != clip:
			player.play(clip)
		player.seek(clip_seconds, true)
	_sample_glow(clip, clip_seconds)

func sample_opening(progress: float) -> void:
	# Cast preview: the summon clip runs over the cast's own (cast-speed scaled) release time.
	var length := clip_length(OPENING[kind])
	sample(OPENING[kind], length * clampf(progress, 0.0, 1.0))
	opening_left = length * (1.0 - clampf(progress, 0.0, 1.0))

func sync_ally(ally: Dictionary, dt: float, _target_distance: float = INF) -> void:
	var moved: Vector3 = ally.node.global_position - _last_position
	moved.y = 0.0
	_last_position = ally.node.global_position
	_clock += dt
	if opening_left > 0.0 and String(ally.get("action", "")) == "":
		opening_left = maxf(0.0, opening_left - dt)
		sample(OPENING[kind], clip_length(OPENING[kind]) - opening_left)
		return
	opening_left = 0.0
	if ACTION.has(kind) and String(ally.get("action", "")) != "":
		sample(ACTION[kind], float(ally.action_time))
		return
	if float(ally.get("hurt", 0.0)) > 0.0:
		sample("hit", clip_length("hit") * (1.0 - float(ally.hurt) / HIT_REACTION))
		return
	if kind == "beacon":
		# The hammer strikes the bell at 0s of the loop, the moment the arena sends the signal.
		sample("pulse", fposmod(float(ally.get("pulse_clock", 0.0)), clip_length("pulse")))
		return
	var distance := moved.length()
	if distance > 0.0005:
		# Feet keep to the ground: the clip advances by distance, a whole stride per loop at this scale.
		_move_phase = fposmod(_move_phase + distance / (STRIDE[kind] * variant_scale), 1.0)
		sample(MOVE[kind], _move_phase * clip_length(MOVE[kind]))
	else:
		sample("idle", fposmod(_clock, clip_length("idle")))

func playback_speed(ground_speed: float) -> float:
	# The same rate as speed_scale = ground speed / (stride / clip seconds * scale), for checks.
	return ground_speed / (STRIDE[kind] / clip_length(MOVE[kind]) * variant_scale)

func socket_position(socket: String) -> Vector3:
	if skeleton == null or skeleton.find_bone(socket) < 0:
		return global_position + Vector3.UP * 0.6 * variant_scale
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(socket)).origin

func strike_point() -> Vector3:
	return socket_position("Socket_attack")

func muzzle_position() -> Vector3:
	return socket_position("Socket_signal" if kind == "beacon" else "Socket_attack")

func preview_shot(_ally: Dictionary) -> void:
	pass

func detach_for_death(world: Node3D, pause_source: Node, _self_destruct: bool = false, closing: String = "death") -> void:
	# Broken or wound down: the baked part collapse (or the beacon's shutdown) plays out on the
	# floor with no collision, target or damage, then frees itself. Armour falls on its own clip.
	if _death_time >= 0:
		return
	_death_clip = closing if clip_length(closing) > 0.0 else "death"
	reparent(world, true)
	name = "ActorCorpse"
	add_to_group("actor_corpses")
	_death_time = 0.0
	_pause_source = pause_source
	sample(_death_clip, 0.0)
	set_process(true)

func _process(dt: float) -> void:
	if _death_time < 0 or (is_instance_valid(_pause_source) and _pause_source.paused):
		return
	_death_time += dt
	sample(_death_clip, _death_time)
	if _death_time >= clip_length(_death_clip) + 0.25:
		queue_free()

func _sample_glow(clip: String, seconds: float) -> void:
	# Lamps and visors light up at the end of the summon clip and go out as it breaks or shuts down
	# (the art delivery's prepared presentation contract); the giant's stacks puff steam.
	var energy := 1.3
	if kind == "beacon":
		if clip == "deploy": energy *= smoothstep(0.35, 0.5, seconds)
		elif clip == "shutdown": energy *= 1.0 - smoothstep(0.0, 0.12, seconds)
		elif clip == "death": energy *= 1.0 - smoothstep(0.02, 0.08, seconds)
	elif kind == "giant":
		if clip == "assemble": energy *= smoothstep(1.1, 1.2, seconds)
		elif clip == "death": energy *= 1.0 - smoothstep(0.18, 0.35, seconds)
	for material in _glow:
		material.emission_energy_multiplier = energy
	if kind == "giant":
		_sample_steam(clip)

func _sample_steam(clip: String) -> void:
	if _steam.is_empty():
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 64
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1, 0.5)
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		for i in 6:
			var puff := MeshInstance3D.new()
			puff.mesh = quad
			puff.name = "Steam" + str(i)
			var material := StandardMaterial3D.new()
			material.albedo_texture = texture
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			puff.material_override = material
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(puff)
			_steam.append(puff)
	for i in _steam.size():
		var puff := _steam[i]
		puff.visible = clip in ["idle", "walk", "slam", "hit"]
		if not puff.visible:
			continue
		var socket := skeleton.find_bone("Socket_exhaust." + ("L" if i < 3 else "R"))
		if socket < 0:
			puff.visible = false
			continue
		var source := holder.to_local(skeleton.to_global(skeleton.get_bone_global_pose(socket).origin))
		var age := fposmod(_clock + float(i % 3) / 3.0, 1.0)
		puff.position = source + Vector3(0.035 * sin(age * 4.0 + i), age * 0.46, 0)
		puff.scale = Vector3.ONE * lerpf(0.1, 0.28, age)
		var material: StandardMaterial3D = puff.material_override
		material.albedo_color = Color(0.67, 0.79, 0.79, smoothstep(0.0, 0.13, age) * (1.0 - smoothstep(0.55, 1.0, age)))

func debug_state() -> Dictionary:
	return {"kind": kind, "loaded": loaded_ok, "state": visual_state, "seconds": clip_seconds, "scale": variant_scale,
		"models": players.size(), "opening_left": opening_left, "dead": _death_time >= 0, "death_clip": _death_clip}
