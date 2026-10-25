extends Node3D
const Rules = preload("res://scripts/combat_rules.gd")
const Shape = preload("res://scripts/shapes.gd")
const Hud = preload("res://scripts/hud.gd")
const ManaProbe = preload("res://scripts/mana_probe.gd")
const TEAL = Color("8dd8c4")
const BRASS = Color("c69b62")
const RED = Color("ee987d")
const PICK_LAYER = 8
# Held inputs repeat only attack-like casts; toggles, summons and placement stay one per press.
const REPEAT_KINDS = ["aim", "enemy"]
var config: Dictionary
var rules: RefCounted
var state: Dictionary
var player: CharacterBody3D
var player_model: Node3D
var camera: Camera3D
var world: Node3D
var hud: Control
var hp: float
var destination: Vector3
var moving = false
var pending_cast: Dictionary = {}
var hold: Dictionary = {}
var queued_input: Dictionary = {}
var action_time = 0.0
var pointer = Vector2.ZERO
var enemies: Dictionary = {}
var allies: Array = []
var effects: Array = []
var sounds: Array[AudioStreamPlayer] = []
var sound_index = 0
var kills = 0
var paused = false
var muted = false
var help_visible = true
var message = ""
var message_time = 0.0
var fallback_time = 0.0
var hit_time = 0.0
var elapsed = 0.0
var last_events: Array = []
var hover_id = ""
var hover_ring: MeshInstance3D
var move_marker: MeshInstance3D
var tool_ring: MeshInstance3D
var tool_visual: Node3D
# A5 mana test: endless engagement, measurement and session logs.
var a5_mode = false
var probe: RefCounted
var logged_seconds = -1.0
var log_dir = ""
var last_log_path = ""
var respawns: Array = []
var spawn_serial = 0
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/trial.json"))
	rules = Rules.new(config)
	_build_field()
	_build_audio()
	var canvas = CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	hud.arena = self
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset_arena()
	if "--start-paused" in OS.get_cmdline_user_args():
		paused = true

func _build_field() -> void:
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101d25")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9d0d3")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color("ffddb0")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	world = Node3D.new()
	add_child(world)
	Shape.box(world, Vector3(0, -0.35, 0), Vector3(30, 0.7, 26), Color("334a50"))
	for x in range(-14, 15, 2):
		Shape.box(world, Vector3(x, 0.005, 0), Vector3(0.025, 0.01, 25.6), Color("40595e"))
	for z in range(-12, 13, 2):
		Shape.box(world, Vector3(0, 0.005, z), Vector3(29.6, 0.01, 0.025), Color("40595e"))
	Shape.ring(world, Vector3(0, 0.02, 0), 5.0, Color("59716d"), 0.025)
	Shape.ring(world, Vector3(0, 0.02, 0), 5.2, Color("8a795a"), 0.025)
	for data in [[Vector3(-15, 0.6, 0), Vector3(0.5, 1.2, 26)], [Vector3(15, 0.6, 0), Vector3(0.5, 1.2, 26)], [Vector3(0, 0.6, -13), Vector3(30, 1.2, 0.5)], [Vector3(0, 0.6, 13), Vector3(30, 1.2, 0.5)]]:
		var wall = StaticBody3D.new()
		wall.collision_layer = 1
		world.add_child(wall)
		wall.position = data[0]
		Shape.box(wall, Vector3.ZERO, data[1], Color("233740"))
		var collision = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = data[1]
		collision.shape = box
		wall.add_child(collision)
	for x in [-14, 14]:
		for z in [-12, -6, 0, 6, 12]:
			Shape.cylinder(world, Vector3(x, 0.65, z), 0.3, 1.3, BRASS)
			Shape.sphere(world, Vector3(x, 1.35, z), 0.15, TEAL)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	camera.far = 100
	add_child(camera)
	# 45° yaw and 30° pitch draw floor tiles as 2:1 diamonds, like a 2D quarter view.
	camera.rotation_degrees = Vector3(-30, 45, 0)
	place_camera(Vector3.ZERO)
	camera.current = true
	hover_ring = Shape.ring(world, Vector3.ZERO, 0.65, RED)
	move_marker = Shape.ring(world, Vector3.ZERO, 0.3, TEAL)
	hover_ring.visible = false
	move_marker.visible = false

func place_camera(focus: Vector3) -> void:
	# The angle never changes; the view only slides with the witch, kept a little below center.
	var screen_up = Vector3(-camera.basis.z.x, 0, -camera.basis.z.z).normalized()
	camera.position = focus + screen_up + camera.basis.z * 30

func _build_audio() -> void:
	if not ResourceLoader.exists("res://audio/mechanical_impact.wav"):
		return
	for i in 6:
		var sound = AudioStreamPlayer.new()
		sound.stream = load("res://audio/mechanical_impact.wav")
		sound.volume_db = -15
		add_child(sound)
		sounds.append(sound)

func play_cue(pitch: float = 1.0) -> void:
	if muted or sounds.is_empty():
		return
	var sound = sounds[sound_index % sounds.size()]
	sound_index += 1
	sound.pitch_scale = pitch
	sound.play()

func reset_arena() -> void:
	for id in enemies:
		enemies[id].body.free()
	enemies.clear()
	for ally in allies:
		ally.node.free()
	allies.clear()
	for fx in effects:
		fx.node.free()
	effects.clear()
	if is_instance_valid(player):
		player.free()
	state = rules.initial_state(float(config.max_mana))
	for slot in config.bindings:
		state = rules.bind(state, slot, config.bindings[slot])
	player = Shape.body(world, Vector3(0, 0, 2), 4)
	player_model = Shape.witch(player)
	tool_visual = Node3D.new()
	player_model.add_child(tool_visual)
	for x in [-0.13, 0.13]:
		var jaw = Shape.box(tool_visual, Vector3(0.57 + x, 1.66, -0.1), Vector3(0.10, 0.43, 0.16), BRASS)
		jaw.rotation.z = x * 1.5
	Shape.ring(player, Vector3(0, 0.035, 0), 0.55, TEAL)
	tool_ring = Shape.ring(player, Vector3(0, 0.08, 0), 0.7, BRASS)
	tool_ring.visible = false
	destination = player.position
	hp = config.max_hp
	kills = 0
	elapsed = 0
	paused = false
	moving = false
	pending_cast.clear()
	hold.clear()
	queued_input.clear()
	action_time = 0
	message_time = 0
	hit_time = 0
	fallback_time = 0
	move_marker.visible = false
	probe = ManaProbe.new()
	logged_seconds = -1.0
	respawns.clear()
	rng.seed = 2510
	var positions = [Vector3(-4, 0, -4), Vector3(3, 0, -5), Vector3(6, 0, 0), Vector3(-7, 0, 3), Vector3(2, 0, -9), Vector3(-8, 0, -8)]
	for i in positions.size():
		spawn_enemy("enemy_" + str(i), positions[i], i >= 4)
	spawn_serial = positions.size()

func spawn_enemy(id: String, pos: Vector3, heavy: bool = false) -> void:
	var body = Shape.body(world, pos, 2)
	body.set_meta("enemy_id", id)
	var model = Shape.enemy(body, heavy)
	var size = 1.15 if heavy else 1.0
	var pick = Shape.pick_volume(body, 0.7 * size, 1.65 * size, PICK_LAYER)
	pick.set_meta("enemy_id", id)
	var maximum: float = config.heavy_hp if heavy else config.enemy_hp
	enemies[id] = {"body": body, "model": model, "hp": maximum, "max_hp": maximum, "heavy": heavy, "cooldown": 1.0, "windup": 0.0, "slow": 0.0, "flash": 0.0}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				paused = not paused
				return
			KEY_ENTER:
				if hp <= 0 or field_cleared() or paused:
					save_mana_log("restart")
					reset_arena()
				return
			KEY_M:
				muted = not muted
				for sound in sounds:
					sound.stop()
				return
			KEY_H:
				help_visible = not help_visible
				return
	if event is InputEventMouse:
		pointer = event.position
	if event is InputEventMouseButton and not event.pressed and hold.get("button") == event.button_index:
		hold.clear()
	if event is InputEventKey and not event.pressed and hold.get("key") == event.physical_keycode:
		hold.clear()
	if paused or hp <= 0:
		return
	var slot = ""
	var shift = false
	var source = {}
	if event is InputEventMouseButton and event.pressed:
		shift = event.shift_pressed
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot = "lmb"
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot = "rmb"
		source = {"button": event.button_index}
	elif event is InputEventKey and event.pressed and not event.echo:
		shift = event.shift_pressed
		slot = {KEY_Q: "q", KEY_W: "w", KEY_E: "e", KEY_R: "r"}.get(event.physical_keycode, "")
		source = {"key": event.physical_keycode}
		if event.physical_keycode == KEY_F4:
			var steps: Array = config.attack_speed_steps
			config.attack_speed_score = steps[(steps.find(config.attack_speed_score) + 1) % steps.size()]
			restart_probe("settings_changed")
			show_message("공속 점수 %d · 기본 공격 %.2f초" % [config.attack_speed_score, attack_seconds(false)])
			return
		if event.physical_keycode == KEY_F1:
			cancel_pending_cast()
			state = rules.bind(state, "lmb", "shotgun" if state.bindings.lmb == "basic_attack" else "basic_attack")
			restart_probe("settings_changed")
			return
		if event.physical_keycode == KEY_F2:
			state.mana = 0.0
			var events: Array = []
			rules.release_at_zero(state, events)
			probe.counts.debug_mana_edits += 1
			return
		if event.physical_keycode == KEY_F3:
			state = rules.restore_mana(state, state.max_mana).state
			probe.counts.debug_mana_edits += 1
			return
		if event.physical_keycode == KEY_F5:
			set_a5_mode(not a5_mode)
			return
		if event.physical_keycode == KEY_F6:
			var path = save_mana_log("manual")
			show_message("기록 저장: " + path.get_file() if path != "" else "저장할 교전 기록이 없습니다")
			return
		if event.physical_keycode == KEY_F7:
			var regen_steps: Array = config.mana_regen_steps
			config.mana_regen = regen_steps[(regen_steps.find(config.mana_regen) + 1) % regen_steps.size()]
			restart_probe("settings_changed")
			show_message("마나 회복 %s/s" % str(config.mana_regen))
			return
	if slot != "" and (pointer_over_field() or event is InputEventKey):
		var cursor = field_cursor()
		# Pressing on an enemy locks it for the whole hold; otherwise the hold follows the cursor.
		hold = source.merged({"slot": slot, "shift": shift, "enemy_id": cursor.get("enemy_id", "")})
		request_slot(slot, cursor, shift)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		hold.clear()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_mana_log("quit")

func field_cleared() -> bool:
	return enemies.is_empty() and not a5_mode

func set_a5_mode(enabled: bool) -> void:
	save_mana_log("mode_off" if a5_mode else "mode_on")
	a5_mode = enabled
	reset_arena()
	show_message("A5 마나 시험 시작 · 연속 교전" if enabled else "A5 마나 시험 종료")

func restart_probe(reason: String) -> void:
	# Settings changes split the measurement so one log never mixes two configurations.
	if a5_mode:
		save_mana_log(reason)
	probe = ManaProbe.new()
	logged_seconds = -1.0

func unaffordable_skills() -> Array:
	var result: Array = []
	for slot in rules.SLOTS:
		var id = state.bindings[slot]
		if id != null and rules.skills[id].mana_cost > 0 and state.mana + rules.EPS < rules.skills[id].mana_cost and id not in result:
			result.append(id)
	return result

func skill_gap() -> bool:
	# Only the basic attack is left: no tool running and every mana-costing slot unaffordable.
	if state.active_tool != null:
		return false
	var unaffordable = unaffordable_skills()
	for slot in rules.SLOTS:
		var id = state.bindings[slot]
		if id != null and rules.skills[id].mana_cost > 0 and id not in unaffordable:
			return false
	return true

func save_mana_log(reason: String) -> String:
	if not a5_mode or probe.combat_seconds < 1.0 or probe.combat_seconds == logged_seconds:
		return ""
	var directory = log_dir if log_dir != "" else ProjectSettings.globalize_path("res://").path_join("../reports/playtest").simplify_path()
	DirAccess.make_dir_recursive_absolute(directory)
	var now = Time.get_datetime_dict_from_system()
	var stamp = "%04d%02d%02d_%02d%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	var path = directory.path_join("a5_mana_%s_%s.json" % [stamp, reason])
	var skills: Array = []
	for id in rules.skills:
		var skill: Dictionary = rules.skills[id]
		skills.append({"id": id, "mana_cost": skill.mana_cost, "cooldown_seconds": skill.cooldown_seconds, "upkeep_per_second": skill.upkeep_per_second})
	var report = {"test": "A5", "status": config.status, "saved_at": Time.get_datetime_string_from_system(), "end_reason": reason,
		"engine": Engine.get_version_info().string, "player_hp": hp, "metrics": probe.to_dict(),
		"settings": {"max_mana": state.max_mana, "mana_regen": config.mana_regen, "attack_speed_score": config.attack_speed_score,
			"respawn_seconds": config.a5_respawn_seconds, "bindings": state.bindings, "skills": skills}}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		show_message("기록을 저장하지 못했습니다")
		return ""
	file.store_string(JSON.stringify(report, "  ") + "\n")
	logged_seconds = probe.combat_seconds
	last_log_path = path
	return path

func tick_respawns(dt: float) -> void:
	for entry in respawns.duplicate():
		entry.time -= dt
		if entry.time > 0:
			continue
		respawns.erase(entry)
		# Re-enter from a field edge away from the witch to keep a steady engagement.
		var pos = Vector3.ZERO
		for attempt in 12:
			var along = rng.randf_range(-1, 1)
			pos = [Vector3(13, 0, along * 11), Vector3(-13, 0, along * 11), Vector3(along * 13, 0, 11), Vector3(along * 13, 0, -11)][rng.randi() % 4]
			if pos.distance_to(player.position) >= 8:
				break
		spawn_enemy("enemy_" + str(spawn_serial), pos, entry.heavy)
		spawn_serial += 1

func pointer_over_field() -> bool:
	return pointer.y < get_viewport().get_visible_rect().size.y - 155

func field_cursor() -> Dictionary:
	return pick_cursor(pointer) if pointer_over_field() else {}

func pick_cursor(screen: Vector2) -> Dictionary:
	var origin = camera.project_ray_origin(screen)
	var direction = camera.project_ray_normal(screen)
	var point = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	var cursor: Dictionary = {}
	if point != null and absf(point.x) < 14.25 and absf(point.z) < 12.25:
		cursor.ground = [point.x, 0, point.z]
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 100, PICK_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("enemy_id"):
		var id: String = hit.collider.get_meta("enemy_id")
		if enemies.has(id):
			cursor.enemy_id = id
	return cursor

func spatial_check(skill: Dictionary, cursor: Dictionary):
	if skill.kind == "ground":
		if cursor.get("ground") == null:
			return "invalid_ground"
		var pos = point(cursor.ground)
		if absf(pos.x) >= 14.25 or absf(pos.z) >= 12.25:
			return "invalid_ground"
		if pos.distance_to(player.position) < 0.9:
			return "invalid_ground"
		for id in enemies:
			if enemies[id].body.position.distance_to(pos) < 0.9:
				return "invalid_ground"
		for ally in allies:
			if ally.node.position.distance_to(pos) < 0.9:
				return "invalid_ground"
		return "out_of_range" if player.position.distance_to(pos) > float(skill.range) else null
	if skill.get("targeting") == "direction":
		# Direction skills fire toward the cursor at once; range only limits their reach.
		return null
	if cursor.get("enemy_id") != null:
		if not enemies.has(cursor.enemy_id):
			return "out_of_range"
		if player.position.distance_to(enemies[cursor.enemy_id].body.position) > float(skill.range):
			return "out_of_range"
	elif skill.kind == "aim" and cursor.get("ground") != null and player.position.distance_to(point(cursor.ground)) > float(skill.range):
		return "out_of_range"
	return null

func stationary_spatial_check(skill: Dictionary, cursor: Dictionary):
	# Shift-ground attacks choose a direction, but never travel toward it.
	if skill.kind == "aim" and cursor.get("enemy_id") == null and cursor.get("ground") != null:
		return null
	return spatial_check(skill, cursor)

func spatial_without_range(skill: Dictionary, cursor: Dictionary):
	var reason = spatial_check(skill, cursor)
	return null if reason == "out_of_range" else reason

func cancel_pending_cast() -> void:
	if not pending_cast.is_empty():
		moving = false
		player.velocity = Vector3.ZERO
		move_marker.visible = false
	pending_cast.clear()

func cast_event(result: Dictionary) -> Dictionary:
	for event in result.events:
		if event.type == "cast":
			return event
	return {}

func request_slot(slot: String, cursor: Dictionary, shift: bool = false) -> void:
	if paused or hp <= 0 or field_cleared():
		return
	if slot not in rules.SLOTS:
		return
	if action_time > 0:
		# An attack motion finishes first; the latest input runs right after it.
		queued_input = {"slot": slot, "cursor": cursor.duplicate(true), "shift": shift}
		return
	cancel_pending_cast()
	var stationary = shift and slot == "lmb"
	if stationary:
		moving = false
		player.velocity = Vector3.ZERO
		move_marker.visible = false
	var checker: Callable = stationary_spatial_check if stationary else spatial_check
	var result: Dictionary = rules.press(state, slot, cursor, checker, shift)
	var final_event: Dictionary = result.events[-1]
	if not stationary and final_event.type == "cast_failed" and final_event.reason == "out_of_range":
		# Dry-run availability/fallback checks; discard its resource/cooldown state.
		var probe: Dictionary = rules.press(state, slot, cursor, spatial_without_range, shift)
		var cast = cast_event(probe)
		if cast.is_empty():
			apply_transition(probe)
			return
		var snapshot = cursor.duplicate(true)
		if rules.skills[cast.skill].kind == "ground":
			snapshot.erase("enemy_id")
		pending_cast = {"slot": slot, "binding": state.bindings[slot], "cursor": snapshot,
			"previous_position": player.position, "stalled_seconds": 0.0}
		last_events = [{"type": "approach_started", "slot": slot, "skill": cast.skill}]
		message_time = 0
		tick_pending_cast(0)
		return
	apply_transition(result)

func tick_hold() -> void:
	if hold.is_empty():
		return
	var slot: String = hold.slot
	var locked: String = hold.enemy_id
	if locked != "" and not enemies.has(locked):
		hold.clear()
		return
	var cursor = field_cursor()
	if slot == "lmb" and not hold.shift and locked == "":
		# A held ground click steers movement; sweeping over enemies never starts an attack.
		if cursor.get("ground") != null and queued_input.is_empty():
			set_destination(point(cursor.ground))
		return
	if action_time > 0 or not pending_cast.is_empty() or not queued_input.is_empty():
		return
	if locked != "":
		cursor = {"enemy_id": locked}
	elif cursor.get("ground") != null:
		cursor = {"ground": cursor.ground}
	else:
		return
	# Repeat only when the cast is available now; cooldown or mana gaps wait silently.
	var cast = cast_event(rules.press(state, slot, cursor, spatial_without_range, true))
	if not cast.is_empty() and rules.skills[cast.skill].kind in REPEAT_KINDS:
		request_slot(slot, cursor, hold.shift)

func attack_seconds(tool: bool) -> float:
	# Soft-cap shape proposed in 04 §4.1; every constant is a trial value.
	var base: float = config.tool_attack_seconds if tool else config.basic_attack_seconds
	var minimum: float = config.min_attack_seconds
	return minimum + (base - minimum) / (1.0 + config.attack_speed_k * config.attack_speed_score)

func set_destination(pos: Vector3) -> void:
	destination = pos
	moving = true
	move_marker.position = pos + Vector3(0, 0.04, 0)
	move_marker.visible = true

func tick_pending_cast(dt: float) -> void:
	if pending_cast.is_empty():
		return
	var slot: String = pending_cast.slot
	var cursor: Dictionary = pending_cast.cursor
	if state.bindings[slot] != pending_cast.binding:
		cancel_pending_cast()
		return
	if cursor.get("enemy_id") != null and not enemies.has(cursor.enemy_id):
		cancel_pending_cast()
		show_message("대상이 사라졌습니다")
		return
	# Recheck resources and fallback range while tracking the original target.
	# This is already a cast command, even when its captured ground target
	# belongs to LMB. Do not reinterpret it as a new ground-move click.
	var probe: Dictionary = rules.press(state, slot, cursor, spatial_without_range, true)
	var cast = cast_event(probe)
	if cast.is_empty():
		cancel_pending_cast()
		apply_transition(probe)
		return
	var skill: Dictionary = rules.skills[cast.skill]
	if spatial_check(skill, cursor) == null:
		cancel_pending_cast()
		apply_transition(rules.press(state, slot, cursor, spatial_check, true))
		return
	var target: Vector3 = enemies[cursor.enemy_id].body.position if cursor.get("enemy_id") != null else point(cursor.ground)
	var direction: Vector3 = (target - player.position).normalized()
	# Stop just inside the range boundary; never walk into the target collider.
	destination = target - direction * maxf(0.1, float(skill.range) - 0.1)
	moving = true
	move_marker.position = destination + Vector3(0, 0.04, 0)
	move_marker.visible = true
	if player.position.distance_to(pending_cast.previous_position) < 0.005:
		pending_cast.stalled_seconds += dt
	else:
		pending_cast.stalled_seconds = 0.0
	pending_cast.previous_position = player.position
	if pending_cast.stalled_seconds >= 1.5:
		cancel_pending_cast()
		show_message("접근할 수 없습니다")

func apply_transition(result: Dictionary) -> void:
	state = result.state
	last_events = result.events
	probe.record(last_events)
	for event in last_events:
		match event.type:
			"move_requested": set_destination(point(event.position))
			"cast":
				# Every successful stationary cast cancels previous click movement.
				moving = false
				move_marker.visible = false
				execute_cast(event)
			"cast_failed", "input_failed":
				show_message({"invalid_target": "대상이 없습니다", "out_of_range": "너무 멉니다", "invalid_ground": "설치할 수 없습니다", "cooldown": "아직 준비 중입니다", "insufficient_mana": "마나가 부족합니다", "empty_slot": "빈 슬롯입니다"}.get(event.reason, "사용할 수 없습니다"))
			"basic_attack_fallback": fallback_time = 0.7
			"tool_changed": play_cue(1.65)

func execute_cast(event: Dictionary) -> void:
	var target = player.position - player_model.basis.z
	if event.get("target_enemy") != null and enemies.has(event.target_enemy):
		target = enemies[event.target_enemy].body.position
	elif event.get("position") != null:
		target = point(event.position)
	var direction: Vector3 = (target - player.position).normalized()
	if direction.length() < 0.01:
		direction = Vector3.FORWARD
	player_model.look_at(player.position + direction)
	match event.skill:
		"basic_attack":
			var tool: bool = event.active_tool != null
			var damage: float = config.tool_damage if tool else config.basic_damage
			var best = nearest_enemy(player.position, rules.skills.basic_attack.range, direction, 0.2)
			if event.get("target_enemy") != null and enemies.has(event.target_enemy):
				best = event.target_enemy
			if best != "":
				if tool:
					enemies[best].slow = config.tool_slow_seconds
					damage_enemy(best, damage)
				else:
					damage_enemy(best, damage)
			action_time = attack_seconds(tool)
			beam(player.position + Vector3.UP, player.position + direction * 2.3 + Vector3.UP, BRASS if tool else TEAL, 0.12)
			play_cue(0.8 if tool else 1.2)
		"shotgun":
			for id in enemies.keys():
				var delta: Vector3 = enemies[id].body.position - player.position
				if delta.length() <= rules.skills.shotgun.range and delta.normalized().dot(direction) > 0.86:
					damage_enemy(id, config.shot_damage)
			for angle in [-0.34, -0.17, 0, 0.17, 0.34]:
				beam(player.position + Vector3.UP, player.position + direction.rotated(Vector3.UP, angle) * rules.skills.shotgun.range + Vector3.UP, BRASS)
			play_cue(0.65)
		"bolt_cutter": pulse(player.position, BRASS, 0.8)
		"automaton":
			var pos = player.position + Vector3(1, 0, 0.6)
			pos.x = clampf(pos.x, -14, 14)
			pos.z = clampf(pos.z, -12, 12)
			spawn_ally(pos, true, event.get("target_enemy", ""))
		"turret": spawn_ally(point(event.position), false, "")
		"relay":
			for ally in allies:
				if eligible(ally, event.target_enemy):
					ally.target = event.target_enemy
			pulse(target, TEAL, 0.8)

func point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func nearest_enemy(pos: Vector3, distance: float, direction: Vector3 = Vector3.ZERO, dot_min: float = -1.0, visible_only: bool = false) -> String:
	var best = ""
	for id in enemies:
		var delta: Vector3 = enemies[id].body.position - pos
		if delta.length() < distance and (direction == Vector3.ZERO or delta.normalized().dot(direction) >= dot_min):
			if visible_only and not on_screen(enemies[id].body.position):
				continue
			distance = delta.length()
			best = id
	return best

func damage_enemy(id: String, amount: float) -> void:
	if not enemies.has(id):
		return
	var enemy: Dictionary = enemies[id]
	enemy.hp -= amount
	enemy.flash = 0.16
	if enemy.hp <= 0:
		pulse(enemy.body.position, RED, 0.6)
		enemy.body.queue_free()
		enemies.erase(id)
		kills += 1
		probe.counts.kills += 1
		if a5_mode:
			respawns.append({"time": float(config.a5_respawn_seconds), "heavy": enemy.heavy})
		if pending_cast.get("cursor", {}).get("enemy_id") == id:
			cancel_pending_cast()
			show_message("대상이 사라졌습니다")
		if queued_input.get("cursor", {}).get("enemy_id") == id:
			queued_input.clear()
		if hold.get("enemy_id") == id:
			hold.clear()
		if enemies.is_empty():
			cancel_pending_cast()

func damage_player(amount: float) -> void:
	if hp <= 0:
		return
	hp = maxf(0, hp - amount)
	hit_time = 0.25
	pulse(player.position, RED, 0.55)
	play_cue(0.75)
	if hp == 0:
		probe.counts.deaths += 1
		save_mana_log("death")
		cancel_pending_cast()
		hold.clear()
		queued_input.clear()
		moving = false
		state.active_tool = null
		move_marker.visible = false

func spawn_ally(pos: Vector3, mobile: bool, target_id) -> void:
	var node = Node3D.new()
	world.add_child(node)
	node.position = pos
	Shape.cylinder(node, Vector3(0, 0.25, 0), 0.33, 0.5, BRASS)
	Shape.box(node, Vector3(0, 0.65, 0), Vector3(0.5, 0.4, 0.48), Color("719b98"))
	if mobile:
		Shape.sphere(node, Vector3(0, 0.98, 0), 0.18, TEAL)
	else:
		Shape.box(node, Vector3(0, 0.75, -0.35), Vector3(0.16, 0.16, 0.75), BRASS)
	Shape.ring(node, Vector3(0, 0.04, 0), 0.43, TEAL)
	allies.append({"node": node, "mobile": mobile, "target": target_id if target_id != null else "", "cooldown": 0.2, "life": config.summon_lifetime if mobile else config.turret_lifetime})
	pulse(pos, TEAL, 0.65)
	play_cue(1.8)

func on_screen(pos: Vector3) -> bool:
	if camera.is_position_behind(pos):
		return false
	var screen = camera.unproject_position(pos)
	var rect = get_viewport().get_visible_rect()
	rect.size.y -= 155
	return rect.has_point(screen)

func eligible(ally: Dictionary, id: String) -> bool:
	return enemies.has(id) and on_screen(enemies[id].body.position) and ally.node.position.distance_to(enemies[id].body.position) <= (config.summon_detection_range if ally.mobile else config.turret_detection_range)

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player):
		return
	if not paused and hp > 0 and not field_cleared():
		elapsed += dt
		var advanced: Dictionary = rules.advance(state, dt)
		state = advanced.state
		probe.record(advanced.events)
		for event in advanced.events:
			if event.type == "tool_released":
				show_message("마나 소진 · 공구 해제")
		state = rules.restore_mana(state, config.mana_regen * dt).state
		if a5_mode:
			probe.tick(dt, skill_gap(), unaffordable_skills())
			tick_respawns(dt)
		if action_time > 0:
			action_time = maxf(0, action_time - dt)
			if action_time == 0 and not queued_input.is_empty():
				var queued = queued_input
				queued_input = {}
				request_slot(queued.slot, queued.cursor, queued.shift)
		tick_hold()
		tick_pending_cast(dt)
		# The witch stands still for the attack motion; held steering resumes afterwards.
		if moving and action_time <= 0:
			var delta: Vector3 = destination - player.position
			if delta.length() < (0.01 if not pending_cast.is_empty() else 0.15):
				moving = false
				move_marker.visible = false
			else:
				player.velocity = delta.normalized() * minf(config.player_speed, delta.length() / dt)
				player.move_and_slide()
				player_model.look_at(player.position + delta.normalized())
		for id in enemies.keys():
			_tick_enemy(enemies[id], dt)
		_tick_allies(dt)
	tool_ring.visible = state.active_tool != null
	tool_visual.visible = state.active_tool != null
	player_model.rotation.z = sin(elapsed * 26) * 0.08 if hit_time > 0 else 0.0
	place_camera(player.position)
	var hovered = pick_cursor(get_viewport().get_mouse_position())
	hover_id = hovered.get("enemy_id", "")
	hover_ring.visible = enemies.has(hover_id)
	if hover_ring.visible:
		hover_ring.position = enemies[hover_id].body.position + Vector3(0, 0.04, 0)
	if not paused:
		message_time = maxf(0, message_time - dt)
		fallback_time = maxf(0, fallback_time - dt)
		hit_time = maxf(0, hit_time - dt)
		for fx in effects.duplicate():
			fx.life -= dt
			if fx.life <= 0:
				fx.node.queue_free()
				effects.erase(fx)
			elif fx.grow:
				fx.node.scale += Vector3.ONE * dt * 2
	hud.queue_redraw()

func _tick_enemy(enemy: Dictionary, dt: float) -> void:
	var delta: Vector3 = player.position - enemy.body.position
	enemy.slow = maxf(0, enemy.slow - dt)
	enemy.flash = maxf(0, enemy.flash - dt)
	enemy.model.scale = Vector3.ONE * (1.15 if enemy.heavy else 1.0) * (1.08 if enemy.flash > 0 else 1.0)
	if enemy.windup > 0:
		enemy.windup -= dt
		enemy.model.rotation.z = sin(enemy.windup * 35) * 0.12
		if enemy.windup <= 0:
			if delta.length() < 1.65:
				damage_player(config.enemy_damage * (1.7 if enemy.heavy else 1.0))
			enemy.cooldown = config.enemy_cooldown
			enemy.model.rotation.z = 0
		return
	enemy.cooldown = maxf(0, enemy.cooldown - dt)
	if delta.length() > 11:
		return
	if delta.length() > 1.2:
		enemy.body.velocity = delta.normalized() * config.enemy_speed * (0.65 if enemy.heavy else 1) * (0.45 if enemy.slow > 0 else 1)
		enemy.body.move_and_slide()
		enemy.model.look_at(player.position)
	elif enemy.cooldown <= 0:
		enemy.windup = config.enemy_windup
		pulse(enemy.body.position, RED, 0.55)

func _tick_allies(dt: float) -> void:
	for ally in allies.duplicate():
		ally.life -= dt
		if ally.life <= 0:
			if ally.mobile:
				for id in enemies.keys():
					if ally.node.position.distance_to(enemies[id].body.position) < config.summon_explosion_range:
						damage_enemy(id, config.shot_damage)
				pulse(ally.node.position, BRASS, config.summon_explosion_range)
			ally.node.queue_free()
			allies.erase(ally)
			continue
		if ally.mobile and not on_screen(ally.node.position):
			ally.target = ""
			ally.node.position = ally.node.position.move_toward(player.position + Vector3(0.8, 0, 0.8), dt * 7)
			continue
		if not eligible(ally, ally.target):
			ally.target = nearest_enemy(ally.node.position, config.summon_detection_range if ally.mobile else config.turret_detection_range, Vector3.ZERO, -1, true)
		if ally.target == "":
			if ally.mobile:
				ally.node.position = ally.node.position.move_toward(player.position + Vector3(0.8, 0, 0.8), dt * 4)
			continue
		var target: Vector3 = enemies[ally.target].body.position
		ally.node.look_at(target)
		if ally.mobile and ally.node.position.distance_to(target) > 1.6:
			ally.node.position = ally.node.position.move_toward(target, dt * 4)
		ally.cooldown -= dt
		if ally.cooldown <= 0 and (not ally.mobile or ally.node.position.distance_to(target) <= 1.8):
			beam(ally.node.position + Vector3.UP * 0.8, target + Vector3.UP * 0.8, TEAL, 0.065)
			damage_enemy(ally.target, config.summon_damage if ally.mobile else config.turret_damage)
			ally.cooldown = config.summon_attack_cooldown if ally.mobile else config.turret_attack_cooldown

func show_message(value: String) -> void:
	if value == message and message_time > 0.3:
		return
	message = value
	message_time = 1.1

func beam(from: Vector3, to: Vector3, color: Color, width: float = 0.045) -> void:
	var length = from.distance_to(to)
	if length < 0.01:
		return
	var node = Shape.box(world, (from + to) / 2, Vector3(width, width, length), color)
	node.look_at(to)
	effects.append({"node": node, "life": 0.13, "grow": false})

func pulse(pos: Vector3, color: Color, radius: float) -> void:
	var node = Shape.ring(world, pos + Vector3(0, 0.06, 0), radius, color)
	effects.append({"node": node, "life": 0.32, "grow": true})
