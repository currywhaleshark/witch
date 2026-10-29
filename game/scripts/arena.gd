extends Node3D
const Rules = preload("res://scripts/combat_rules.gd")
const Shape = preload("res://scripts/shapes.gd")
const Hud = preload("res://scripts/hud.gd")
const ManaProbe = preload("res://scripts/mana_probe.gd")
const FieldMap = preload("res://scripts/field_map.gd")
const PlayerVisual = preload("res://scripts/player_visual.gd")
const ActorVisual = preload("res://scripts/actor_visual.gd")
const AutomatonAssembly = preload("res://scripts/automaton_assembly.gd")
const TurretAssembly = preload("res://scripts/turret_assembly.gd")
const ShotgunCast = preload("res://scripts/shotgun_cast.gd")
const ShotgunGeometry = preload("res://scripts/shotgun_geometry.gd")
const CombatVfx = preload("res://scripts/combat_vfx.gd")
const WARNING_SHADER = preload("res://shaders/warning_zone.gdshader")
const TEAL = Color("8dd8c4")
const BRASS = Color("c69b62")
const RED = Color("ee987d")
const STEEL = Color("a9c1d6")
const GOLD_FLASH = Color("ffe08a")
const BOLT_GLOW = Color(0.62, 0.86, 1.0)
# Ground warnings: dark area plus a bright fill that reaches the edge at impact.
const WARN = Color("7a3a32")
const WARN_FILL = Color("e8604c")
# Each tool keeps its own colour on the witch, its ring and its swings.
const BLEED_RED = Color("c8463c")
const TOOL_COLORS = {"bolt_cutter": BRASS, "grinder": STEEL, "chainsaw": BLEED_RED}
const PICK_LAYER = 8
# Held inputs repeat only attack-like casts; toggles, summons and placement stay one per press.
const REPEAT_KINDS = ["aim", "enemy"]
var config: Dictionary
var rules: RefCounted
# The automaton skill's own cost, which nodes A and B keep; no node swaps in a cheaper, quicker one.
var automaton_cost: Dictionary
var state: Dictionary
var player: CharacterBody3D
var player_model: Node3D
var player_visual: PlayerVisual
var camera: Camera3D
var world: Node3D
# The map sets its own time of day on these (see FieldMap.apply_lighting).
var env: Environment
var sun: DirectionalLight3D
var hud: Control
var hp: float
var destination: Vector3
var moving = false
var pending_cast: Dictionary = {}
# A started motion waits here until its release point fires the effect.
var windup: Dictionary = {}
var automaton_assembly: Node3D
var turret_assembly: Node3D
var shotgun_assembly: Node3D
var last_shotgun: Dictionary = {}
var hold: Dictionary = {}
# A held ground click keeps steering on its own, so skill presses never replace it.
var move_hold: Dictionary = {}
var queued_input: Dictionary = {}
var action_time = 0.0
var pointer = Vector2.ZERO
var enemies: Dictionary = {}
var allies: Array = []
var ally_serial = 0
var effects: Array = []
# Wire-crow orbs in flight; each hits the witch at most once.
var bolts: Array = []
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
# Hit recovery: an unblocked hit stuns the witch and cancels what she was doing.
var stun_time = 0.0
var shield_time = 0.0
var shield_ring: MeshInstance3D
# Potion quickslots 1-4: refills over time, cooldowns shared per group, no auto-restock.
var potion_slots: Array = []
var potion_cooldowns: Dictionary = {}
var potion_effects: Array = []
var speed_buff = 0.0
var elapsed = 0.0
var last_events: Array = []
var hover_id = ""
var hover_ring: MeshInstance3D
var move_marker: MeshInstance3D
var tool_rings: Dictionary = {}
var tool_visuals: Dictionary = {}
var grinder_disk: MeshInstance3D
# A5 mana test: endless engagement, measurement and session logs.
var a5_mode = false
var probe: RefCounted
var logged_seconds = -1.0
var log_dir = ""
var last_log_path = ""
var respawns: Array = []
var spawn_serial = 0
var rng = RandomNumberGenerator.new()
# Block rolls use their own stream so they never shift A5 respawn positions.
var block_rng = RandomNumberGenerator.new()
# Hit and crit rolls; tests pin outcomes with force_rolls {"hit": bool, "crit": bool}.
var combat_rng = RandomNumberGenerator.new()
var force_rolls: Dictionary = {}
# Effect jitter only; never read by combat, so rolls match with or without VFX.
var vfx_rng = RandomNumberGenerator.new()
var staff_trail: Node3D
var staff_tip_last = null
var shake_time = 0.0
var boss_serial = 0
# Field layout and routes. Test harnesses start on the flat arena their checks assume.
var map: Node3D
var player_route: Dictionary = {}
var boss_spawned = false

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/trial.json"))
	rules = Rules.new(config)
	automaton_cost = {"mana_cost": rules.skills.automaton.mana_cost, "cooldown_seconds": rules.skills.automaton.cooldown_seconds}
	sync_automaton_cost()
	block_rng.randomize()
	combat_rng.randomize()
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
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101d25")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9d0d3")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color("ffddb0")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	world = Node3D.new()
	add_child(world)
	map = FieldMap.new()
	world.add_child(map)
	map.build("flat" if get_tree().get_script() != null else config.get("map", "flat"))
	map.apply_lighting(env, sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# The user-selected 1.75x framing (about 111px) was set for a 1.711m model; zoom by the same
	# factor the witch shrank to 1.5m so she keeps that on-screen size.
	camera.size = 20.0 / 1.75 * PlayerVisual.MODEL_SCALE
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

func play_cue(pitch: float = 1.0, gain_db: float = 0.0) -> void:
	if muted or sounds.is_empty():
		return
	var sound = sounds[sound_index % sounds.size()]
	sound_index += 1
	sound.pitch_scale = pitch
	sound.volume_db = -15.0 + gain_db
	sound.play()

func reset_arena() -> void:
	for child in world.get_children():
		if child.is_in_group("actor_corpses") or child.is_in_group("cast_assemblies"):
			child.free()
	automaton_assembly = null
	turret_assembly = null
	shotgun_assembly = null
	last_shotgun.clear()
	for id in enemies:
		enemies[id].body.free()
	enemies.clear()
	for ally in allies:
		ally.node.free()
	allies.clear()
	for fx in effects:
		fx.node.free()
	effects.clear()
	for bolt in bolts:
		bolt.node.free()
	bolts.clear()
	if is_instance_valid(player):
		player.free()
	state = rules.initial_state(float(config.max_mana))
	for slot in config.bindings:
		state = rules.bind(state, slot, config.bindings[slot])
	player = Shape.body(world, map.start_point(), 4)
	player_route = {}
	boss_spawned = false
	player_visual = PlayerVisual.new()
	player.add_child(player_visual)
	player_visual.initialize()
	player_model = player_visual
	tool_visuals = player_visual.tool_visuals
	grinder_disk = player_visual.grinder_disk
	for id in TOOL_COLORS:
		tool_rings[id] = Shape.ring(player, Vector3(0, 0.08, 0), 0.7, TOOL_COLORS[id])
	Shape.ring(player, Vector3(0, 0.035, 0), 0.55, TEAL)
	shield_ring = Shape.ring(player, Vector3(0, 1.0, 0), 0.85, STEEL, 0.06)
	if not is_instance_valid(staff_trail):
		staff_trail = CombatVfx.new()
		world.add_child(staff_trail)
		staff_trail.setup(0, camera)
	staff_trail.clear_trails()
	staff_tip_last = null
	vfx_rng.seed = 1031
	destination = player.position
	hp = config.max_hp
	kills = 0
	elapsed = 0
	paused = false
	moving = false
	pending_cast.clear()
	windup.clear()
	hold.clear()
	move_hold.clear()
	queued_input.clear()
	action_time = 0
	message_time = 0
	hit_time = 0
	stun_time = 0
	shield_time = 0
	potion_slots = []
	for entry in config.potion_loadout:
		potion_slots.append({"id": entry.id, "count": int(entry.count)})
	potion_cooldowns.clear()
	potion_effects.clear()
	speed_buff = 0
	fallback_time = 0
	move_marker.visible = false
	probe = ManaProbe.new()
	logged_seconds = -1.0
	respawns.clear()
	rng.seed = 2510
	# Trial field from 08 §6.2: a rag-ghoul pack, two wire crows and an iron-door brute.
	var field: Array = config.field if map.data.is_empty() else map.data.spawns
	for i in field.size():
		var entry: Dictionary = field[i]
		spawn_enemy("enemy_" + str(i), point(entry.pos), false, entry.grade, entry.kind)
	spawn_serial = field.size()
	if not player_visual.loaded_ok:
		show_message("캐릭터 자산을 불러오지 못했습니다")

func spawn_enemy(id: String, pos: Vector3, heavy: bool = false, grade: String = "normal", kind: String = "") -> void:
	# kind picks an enemy type; without one, heavy keeps the original light/heavy test dummies.
	if kind == "":
		kind = "heavy" if heavy else "light"
	var type: Dictionary = config.enemy_types[kind]
	var rank: Dictionary = config.grades[grade]
	pos = map.grounded(pos)
	var body = Shape.body(world, pos, 2)
	body.set_meta("enemy_id", id)
	var model = Shape.enemy(body, kind)
	var size: float = type.scale * rank.scale
	if rank.has("color"):
		# Graded enemies wear their grade colour as a ground ring and a head band.
		Shape.ring(body, Vector3(0, 0.05, 0), 0.75 * size, Color(rank.color), 0.06)
		if kind != "latch":
			Shape.box(model, Vector3(0, 1.45, 0), Vector3(0.62, 0.1, 0.5), Color(rank.color))
	var pick = Shape.pick_volume(body, 0.7 * size, 1.65 * size, PICK_LAYER)
	pick.set_meta("enemy_id", id)
	var maximum: float = type.hp * rank.hp
	enemies[id] = {"body": body, "model": model, "hp": maximum, "max_hp": maximum, "heavy": type.get("heavy", false), "kind": kind,
		"grade": grade, "size": size, "cooldown": 1.0, "windup": 0.0, "attack": "", "charge_cooldown": 1.0, "charging": 0.0,
		"charge_dir": Vector3.ZERO, "charge_hit": false, "target": "", "retarget": 0.0, "slow": 0.0, "shred": 0.0, "bleeds": [], "flash": 0.0,
		"respawn": true, "timers": {}, "phases_done": [], "pattern_dir": Vector3.ZERO, "frames": [], "route": {}}

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
	if event is InputEventMouseButton and not event.pressed:
		if hold.get("button") == event.button_index:
			hold.clear()
		if move_hold.get("button") == event.button_index:
			move_hold.clear()
	if event is InputEventKey and not event.pressed and hold.get("key") == event.physical_keycode:
		hold.clear()
	if paused or hp <= 0:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
		var index: int = [KEY_1, KEY_2, KEY_3, KEY_4].find(event.physical_keycode)
		if event.shift_pressed:
			cycle_potion(index)
		else:
			drink(index)
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
			# Close the running log before the change so it keeps the settings it measured.
			restart_probe("settings_changed")
			var steps: Array = config.attack_speed_steps
			config.attack_speed_score = steps[(steps.find(config.attack_speed_score) + 1) % steps.size()]
			show_message("공속 점수 %d · 기본 공격 %.2f초" % [config.attack_speed_score, attack_seconds()])
			return
		if event.physical_keycode == KEY_F8:
			restart_probe("settings_changed")
			var cast_steps: Array = config.cast_speed_steps
			config.cast_speed_score = cast_steps[(cast_steps.find(config.cast_speed_score) + 1) % cast_steps.size()]
			show_message("시전 속도 점수 %d · 산탄 %.2f초 · 태엽인형 %.2f초" % [config.cast_speed_score, cast_seconds(rules.skills.shotgun), cast_seconds(rules.skills.automaton)])
			return
		if event.physical_keycode == KEY_F1:
			cancel_pending_cast()
			restart_probe("settings_changed")
			state = rules.bind(state, "lmb", "shotgun" if state.bindings.lmb == "basic_attack" else "basic_attack")
			return
		if event.physical_keycode == KEY_F9 and (event.shift_pressed or event.ctrl_pressed):
			# Shift+F9: chainsaw skill level; Ctrl+F9: which bleed growth (A rate / B upkeep) the level drives.
			restart_probe("settings_changed")
			if event.shift_pressed:
				var levels: Array = config.chainsaw_level_steps
				config.chainsaw_level = levels[(levels.find(config.chainsaw_level) + 1) % levels.size()]
			else:
				var growths: Array = config.bleed.growth_steps
				config.bleed.growth = growths[(growths.find(config.bleed.growth) + 1) % growths.size()]
			var plan: Dictionary = bleed_plan(0)
			show_message("전기톱 Lv %d · 출혈 성장 %s안 · %.1f초 · 일반 %d%%" % [config.chainsaw_level, config.bleed.growth, plan.seconds, roundi(100 * plan.ratio * float(config.bleed.ratio.normal))])
			return
		if event.physical_keycode == KEY_F9:
			cancel_pending_cast()
			restart_probe("settings_changed")
			var options: Array = config.r_slot_options
			state = rules.bind(state, "r", options[(options.find(state.bindings.r) + 1) % options.size()])
			show_message("R 슬롯: " + rules.skills[state.bindings.r].name)
			return
		if event.physical_keycode == KEY_N:
			# N: automaton node, no node -> A (blast on reach) -> B (keeps fighting).
			restart_probe("settings_changed")
			var nodes: Array = config.automaton_node_steps
			config.automaton_node = nodes[(nodes.find(config.automaton_node) + 1) % nodes.size()]
			sync_automaton_cost()
			show_message("태엽인형 " + {"base": "기본형 · 싸게 많이 · 싸우다 자폭", "A": "A 자폭 특화 · 닿으면 자폭", "B": "B 지속공격 특화 · 자폭 없음 · 최대 %d기" % config.automaton_nodes.B.max_count}[config.automaton_node])
			return
		if event.physical_keycode in [KEY_F10, KEY_F11, KEY_F12]:
			var key: String = {KEY_F10: "shield_level", KEY_F11: "dexterity", KEY_F12: "hit_recovery_score"}[event.physical_keycode]
			if event.physical_keycode == KEY_F10 and (event.shift_pressed or event.ctrl_pressed):
				# Shift/Ctrl+F10: automaton/turret skill level for summon accuracy and crit.
				key = "automaton_level" if event.shift_pressed else "turret_level"
				restart_probe("settings_changed")
				var levels: Array = config.summon_level_steps
				config[key] = levels[(levels.find(config[key]) + 1) % levels.size()]
				var roller: String = key.trim_suffix("_level")
				show_message("%s Lv %d · 명중 %d%% · 치명 %d%%" % [rules.skills[roller].name, config[key], roundi(100 * clampf(config.summon_hit_base + config.summon_hit_per_level * (config[key] - 1), config.hit_min, config.hit_cap)), roundi(100 * crit_chance(roller))])
				return
			restart_probe("settings_changed")
			var options: Array = config[key + "_steps"]
			config[key] = options[(options.find(config[key]) + 1) % options.size()]
			show_message("방패 Lv %d · 기교 %d · 막기 %d%% · 경직 %.2f초" % [config.shield_level, config.dexterity, roundi(100 * block_chance()), hit_recovery_seconds()])
			return
		if event.physical_keycode == KEY_B:
			# Test tool: a boss walks in from a field edge.
			spawn_enemy("boss_" + str(boss_serial), edge_point(), true, "boss", "latch")
			boss_serial += 1
			show_message("보스 등장")
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
			if event.shift_pressed:
				# Test tool: swap between the alley trial map and the flat arena.
				load_map("flat" if map.id != "flat" else config.get("map", "alley_v1"))
				return
			set_a5_mode(not a5_mode)
			return
		if event.physical_keycode == KEY_F6:
			var path = save_mana_log("manual")
			show_message("기록 저장: " + path.get_file() if path != "" else "저장할 교전 기록이 없습니다")
			return
		if event.physical_keycode == KEY_F7:
			restart_probe("settings_changed")
			var regen_steps: Array = config.mana_regen_steps
			config.mana_regen = regen_steps[(regen_steps.find(config.mana_regen) + 1) % regen_steps.size()]
			show_message("마나 회복 %s/s" % str(config.mana_regen))
			return
	if slot != "" and (pointer_over_field() or event is InputEventKey):
		var cursor = field_cursor()
		if slot == "lmb" and not shift and cursor.get("enemy_id") == null:
			move_hold = source
		else:
			# Pressing on an enemy locks it for the whole hold; otherwise the hold follows the cursor.
			hold = source.merged({"slot": slot, "shift": shift, "enemy_id": cursor.get("enemy_id", "")})
		request_slot(slot, cursor, shift)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		hold.clear()
		move_hold.clear()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_mana_log("quit")

func field_cleared() -> bool:
	# A map with a boss arena is only cleared once its boss has come out and fallen.
	return enemies.is_empty() and not a5_mode and (not map.data.has("boss") or boss_spawned)

func load_map(map_id: String) -> void:
	restart_probe("settings_changed")
	map.build(map_id)
	map.apply_lighting(env, sun)
	reset_arena()
	show_message(map.data.get("name", "평지 시험 경기장"))

func follow(route: Dictionary, from: Vector3, goal: Vector3, every: float, dt: float) -> Vector3:
	# Next waypoint toward goal; re-plans when the goal moves or the plan gets old.
	route.age = route.get("age", INF) + dt
	var last: Vector3 = route.get("goal", Vector3(INF, 0, INF))
	if route.age >= every or Vector2(goal.x - last.x, goal.z - last.z).length() > 0.4 or route.get("points", PackedVector3Array()).is_empty():
		route.points = map.route(from, goal)
		route.goal = goal
		route.age = 0.0
		route.index = 0
	var points: PackedVector3Array = route.points
	while route.index < points.size() - 1 and Vector2(points[route.index].x - from.x, points[route.index].z - from.z).length() < 0.25:
		route.index += 1
	var next: Vector3 = points[mini(route.index, points.size() - 1)]
	return Vector3(next.x, from.y, next.z)

func tick_boss_trigger() -> void:
	# Entering the arena zone calls the map's boss once per run.
	if boss_spawned or not map.data.has("boss"):
		return
	var r: Array = map.data.boss.trigger
	if player.position.x >= r[0] and player.position.x <= r[2] and player.position.z >= r[1] and player.position.z <= r[3]:
		boss_spawned = true
		spawn_enemy("boss_field", Vector3(map.data.boss.pos[0], 0, map.data.boss.pos[1]), true, "boss", "latch")
		show_message("보스 등장")

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

func build_stamp() -> Dictionary:
	# Tells logs from different builds apart: the commit, plus content hashes that also catch
	# uncommitted edits to the trial values or the game scripts.
	var scripts: PackedStringArray = []
	for file in DirAccess.get_files_at("res://scripts"):
		if file.ends_with(".gd"):
			scripts.append(file)
	scripts.sort()
	var digests = ""
	for file in scripts:
		digests += file + ":" + FileAccess.get_md5("res://scripts/" + file) + "\n"
	return {"git_commit": git_commit(), "trial_md5": FileAccess.get_md5("res://data/trial.json"), "scripts_md5": digests.md5_text()}

func git_commit() -> String:
	# Short hash of the checked-out commit when run from the repository; "unknown" elsewhere.
	var git_dir = ProjectSettings.globalize_path("res://").path_join("../.git").simplify_path()
	var head = FileAccess.get_file_as_string(git_dir.path_join("HEAD")).strip_edges()
	if not head.begins_with("ref: "):
		return head.left(7) if head.length() >= 7 else "unknown"
	var ref = head.trim_prefix("ref: ")
	var hash = FileAccess.get_file_as_string(git_dir.path_join(ref)).strip_edges()
	if hash.is_empty():
		for line in FileAccess.get_file_as_string(git_dir.path_join("packed-refs")).split("\n"):
			if line.ends_with(" " + ref):
				hash = line.get_slice(" ", 0)
	return hash.left(7) if hash.length() >= 7 else "unknown"

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
		skills.append({"id": id, "mana_cost": skill.mana_cost, "cooldown_seconds": skill.cooldown_seconds, "upkeep_per_second": skill.upkeep_per_second,
			"while_moving": skill.get("while_moving", false), "cast_seconds": cast_seconds(skill)})
	var report = {"test": "A5", "status": config.status, "saved_at": Time.get_datetime_string_from_system(), "end_reason": reason,
		"engine": Engine.get_version_info().string, "build": build_stamp(), "player_hp": hp, "metrics": probe.to_dict(),
		"settings": {"max_mana": state.max_mana, "mana_regen": config.mana_regen, "attack_speed_score": config.attack_speed_score, "cast_speed_score": config.cast_speed_score,
			"hit_recovery_score": config.hit_recovery_score, "shield_level": config.shield_level, "dexterity": config.dexterity,
			"automaton_level": config.automaton_level, "turret_level": config.turret_level, "map": map.id,
			"automaton_node": config.automaton_node,
			"chainsaw_level": config.chainsaw_level, "bleed_growth": config.bleed.growth,
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
		spawn_enemy("enemy_" + str(spawn_serial), edge_point(), false, entry.grade, entry.kind)
		spawn_serial += 1

func edge_point() -> Vector3:
	# Enter away from the witch to keep a steady engagement: field edges, or the map's listed spots.
	return map.respawn_point(player.position, rng)

func pointer_over_field() -> bool:
	return pointer.y < get_viewport().get_visible_rect().size.y - 155

func field_cursor() -> Dictionary:
	return pick_cursor(pointer) if pointer_over_field() else {}

func pick_cursor(screen: Vector2) -> Dictionary:
	var origin = camera.project_ray_origin(screen)
	var direction = camera.project_ray_normal(screen)
	# Floors and steps first; the flat arena (and the void off a map) falls back to the ground plane.
	var point = map.pick_floor(origin, direction)
	if point == null:
		point = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	var cursor: Dictionary = {}
	if point != null and map.bounds.has_point(Vector2(point.x, point.z)):
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
		if not map.walkable(pos):
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
		# Behind a wall counts as out of reach, so the witch walks around to a clear line.
		if not map.sees(player.position, enemies[cursor.enemy_id].body.position):
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

func sync_automaton_cost() -> void:
	# No node is the cheap one to summon in numbers; A and B pay the skill's full cost and cooldown.
	var cost: Dictionary = config.automaton_nodes.base if config.automaton_node == "base" else automaton_cost
	rules.skills.automaton.mana_cost = float(cost.mana_cost)
	rules.skills.automaton.cooldown_seconds = float(cost.cooldown_seconds)

func request_slot(slot: String, cursor: Dictionary, shift: bool = false) -> void:
	sync_automaton_cost()
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
	begin_cast(slot, cursor, shift, stationary, result)

func begin_cast(slot: String, cursor: Dictionary, shift: bool, stationary: bool, result: Dictionary) -> void:
	var cast = cast_event(result)
	var skill: Dictionary = {} if cast.is_empty() else rules.skills[cast.skill]
	var seconds = 0.0
	if cast.get("skill") == rules.basic_id:
		seconds = attack_seconds(cast.active_tool)
	elif not skill.is_empty() and not skill.get("while_moving", false):
		seconds = cast_seconds(skill)
	if seconds <= 0:
		apply_transition(result)
		return
	# The motion starts now; checks, costs, cooldown and the effect wait for its release point.
	var snapshot = cursor.duplicate(true)
	if skill.kind == "ground":
		snapshot.erase("enemy_id")
	elif skill.get("targeting") == "direction" and snapshot.get("enemy_id") != null:
		# Keep aiming at the enemy, but still fire toward its last spot if it dies first.
		var aim: Vector3 = enemies[snapshot.enemy_id].body.position
		snapshot.ground = [aim.x, 0, aim.z]
	if slot == "lmb":
		moving = false
		move_marker.visible = false
	action_time = seconds
	windup = {"slot": slot, "binding": state.bindings[slot], "cursor": snapshot, "shift": shift, "stationary": stationary,
		"skill": cast.skill, "release": seconds * float(skill.get("release_ratio", 1.0))}
	if cast.skill == "automaton":
		windup.visual_duration = windup.release
		automaton_assembly = AutomatonAssembly.new()
		automaton_assembly.configure(str(config.automaton_node))
		world.add_child(automaton_assembly)
		automaton_assembly.position = map.grounded(automaton_spawn_position())
		automaton_assembly.initialize(self)
	elif cast.skill == "turret":
		windup.visual_duration = windup.release
		turret_assembly = TurretAssembly.new()
		world.add_child(turret_assembly)
		turret_assembly.position = map.grounded(point(snapshot.ground))
		turret_assembly.initialize(self)
	elif cast.skill == "shotgun":
		windup.visual_duration = windup.release
		begin_shotgun_visual(cast_target(cast))
	player_model.look_at(player.position + cast_direction(cast))
	player_visual.begin_motion("attack" if cast.skill == rules.basic_id else "cast", seconds, float(skill.get("release_ratio", 1.0)))
	last_events = [{"type": "windup_started", "slot": slot, "skill": cast.skill}]

func tick_windup(dt: float) -> void:
	if windup.is_empty():
		return
	windup.release -= dt
	if is_instance_valid(automaton_assembly):
		# The debug node selector can change mid-windup; match the actual release selection.
		if automaton_assembly.appearance_node!=str(config.automaton_node):
			var origin: Vector3=automaton_assembly.position
			automaton_assembly.queue_free()
			automaton_assembly=AutomatonAssembly.new()
			automaton_assembly.configure(str(config.automaton_node))
			world.add_child(automaton_assembly)
			automaton_assembly.position=origin
			automaton_assembly.initialize(self)
		automaton_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(turret_assembly):
		turret_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(shotgun_assembly):
		var aim := {"target_enemy":windup.cursor.get("enemy_id"),"position":windup.cursor.get("ground")}
		shotgun_assembly.global_transform = ShotgunGeometry.frame(self,cast_target(aim))
		shotgun_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if windup.release > 0:
		return
	var started: Dictionary = windup
	windup = {}
	player_visual.mark_release()
	if state.bindings[started.slot] != started.binding:
		cancel_summon_assemblies("binding_changed")
		return
	var cursor: Dictionary = started.cursor
	if cursor.get("enemy_id") != null and not enemies.has(cursor.enemy_id):
		if rules.skills[started.skill].get("targeting") != "direction":
			cancel_summon_assemblies("target_lost")
			show_message("대상이 사라졌습니다")
			return
		cursor.erase("enemy_id")
	# Everything is checked again at release; a failed release spends nothing.
	var checker: Callable = stationary_spatial_check if started.stationary else spatial_check
	var result: Dictionary = rules.press(state, started.slot, cursor, checker, started.shift)
	if result.events[-1].get("reason") == "out_of_range":
		# A whiff stays silent; the missing hit sound and effect tell it apart.
		last_events = result.events
		probe.record(last_events)
		cancel_summon_assemblies("out_of_range")
		return
	apply_transition(result)
	# A failed recheck or LMB fallback must collapse its preview too.
	cancel_summon_assemblies("release_failed")

func automaton_spawn_position() -> Vector3:
	# Casting and idle following share this anchor to avoid a step on release.
	var pos := player.position + Vector3(1, 0, 0.6)
	pos.x = clampf(pos.x, map.bounds.position.x + 0.25, map.bounds.end.x - 0.25)
	pos.z = clampf(pos.z, map.bounds.position.y + 0.25, map.bounds.end.y - 0.25)
	return map.snap(pos) if not map.walkable(pos) else pos

func cancel_summon_assemblies(reason: String) -> void:
	if is_instance_valid(automaton_assembly):
		automaton_assembly.cancel(reason)
	automaton_assembly = null
	if is_instance_valid(turret_assembly):
		turret_assembly.cancel(reason)
	turret_assembly = null
	if is_instance_valid(shotgun_assembly):
		shotgun_assembly.cancel(reason)
	shotgun_assembly = null

func begin_shotgun_visual(target: Vector3) -> void:
	shotgun_assembly=ShotgunCast.new()
	world.add_child(shotgun_assembly)
	shotgun_assembly.initialize(self)
	shotgun_assembly.global_transform=ShotgunGeometry.frame(self,target)

func fire_shotgun(target: Vector3) -> void:
	var shot: Transform3D=ShotgunGeometry.frame(self,target)
	if not is_instance_valid(shotgun_assembly): begin_shotgun_visual(target)
	shotgun_assembly.fire(shot)
	shotgun_assembly=null
	var struck: Array[String]=[]
	for id in enemies.keys():
		if ShotgunGeometry.contains(self,shot,enemies[id].body):
			struck.append(id)
			strike(id,config.shot_damage,false,"witch","shotgun")
	var endpoints: Array[Vector3]=ShotgunGeometry.traces(self,shot)
	# Unblocked traces end on the 8m circle around the witch; shorter ones hit a wall or floor.
	var blocked: Array[bool]=[]
	for end in endpoints:
		var flat: Vector3=end-player.position; flat.y=0.0
		blocked.append(flat.length()<float(rules.skills.shotgun.range)-0.05)
	spawn_vfx().muzzle(shot.origin,endpoints,blocked,map.ground_y(shot.origin))
	last_shotgun={"frame":shot,"origin":shot.origin,"direction":-shot.basis.z,"ends":endpoints,"struck":struck}
	play_cue(0.65)

func tick_move_hold() -> void:
	# A held ground click steers movement; sweeping over enemies never starts an attack.
	# An approach-cast or queued input takes over until it finishes, then steering resumes.
	if move_hold.is_empty() or not pending_cast.is_empty() or not queued_input.is_empty():
		return
	var cursor = field_cursor()
	if cursor.get("ground") != null:
		set_destination(point(cursor.ground))

func tick_hold() -> void:
	tick_move_hold()
	if hold.is_empty():
		return
	var slot: String = hold.slot
	var locked: String = hold.enemy_id
	if locked != "" and not enemies.has(locked):
		hold.clear()
		return
	var cursor = field_cursor()
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

func motion_seconds(base: float, minimum: float, k: float, score: float) -> float:
	# Soft-cap shape proposed in 04 §4.1; every constant is a trial value.
	return minimum + (base - minimum) / (1.0 + k * score)

func attack_seconds(tool = null) -> float:
	# Each tool swaps in its own attack motion; null is the bare staff.
	var base: float = rules.skills[tool].attack_seconds if tool != null else config.basic_attack_seconds
	return motion_seconds(base, config.min_attack_seconds, config.attack_speed_k, config.attack_speed_score)

func cast_seconds(skill: Dictionary) -> float:
	# The cast motion is the stop time; cast rate (FCR) is its own axis, apart from attack speed.
	var base: float = skill.get("cast_seconds", 0.0)
	return motion_seconds(base, base * config.min_cast_ratio, config.cast_speed_k, config.cast_speed_score)

func set_destination(pos: Vector3) -> void:
	destination = map.snap(pos)
	moving = true
	move_marker.position = destination + Vector3(0, 0.04, 0)
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
		begin_cast(slot, cursor, true, false, rules.press(state, slot, cursor, spatial_check, true))
		return
	var target: Vector3 = enemies[cursor.enemy_id].body.position if cursor.get("enemy_id") != null else point(cursor.ground)
	# Walk the route toward the target; the cast fires as soon as range and sight line allow.
	destination = map.snap(target) if cursor.get("enemy_id") == null else target
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
				if event.slot == "lmb":
					# A left-click cast is a new LMB command and replaces click movement.
					moving = false
					move_marker.visible = false
				execute_cast(event)
			"cast_failed", "input_failed":
				show_message({"invalid_target": "대상이 없습니다", "out_of_range": "너무 멉니다", "invalid_ground": "설치할 수 없습니다", "cooldown": "아직 준비 중입니다", "insufficient_mana": "마나가 부족합니다", "empty_slot": "빈 슬롯입니다"}.get(event.reason, "사용할 수 없습니다"))
			"basic_attack_fallback": fallback_time = 0.7
			"tool_changed": play_cue(1.65)

func cast_target(event: Dictionary) -> Vector3:
	if event.get("target_enemy") != null and enemies.has(event.target_enemy):
		return enemies[event.target_enemy].body.position
	if event.get("position") != null:
		# Ground clicks arrive at height 0; lift them onto the floor actually under the cursor.
		return map.grounded(point(event.position))
	return player.position - player_model.basis.z

func cast_direction(event: Dictionary) -> Vector3:
	# Aim and facing stay level. Ground clicks are stored at height 0, so on stairs or a raised
	# floor the raw vector would tip the witch and her shots down into the ground.
	var direction: Vector3 = cast_target(event) - player.position
	direction.y = 0.0
	return direction.normalized() if direction.length() >= 0.01 else Vector3.FORWARD

func execute_cast(event: Dictionary) -> void:
	var target = cast_target(event)
	var direction = cast_direction(event)
	player_model.look_at(player.position + direction)
	match event.skill:
		"basic_attack":
			var tool = event.active_tool
			var damage: float = rules.skills[tool].attack_damage if tool != null else config.basic_damage
			var best = nearest_enemy(player.position, rules.skills.basic_attack.range, direction, 0.2, false, true)
			if event.get("target_enemy") != null and enemies.has(event.target_enemy):
				best = event.target_enemy
			# The swing itself is drawn by the staff trail (tick_staff_trail).
			# A miss swings silently: no hit sound, no flash, no debuff.
			if tool == "chainsaw":
				# A small forward fan: every enemy in it is struck on its own roll, and each hit bleeds.
				var struck: Array = []
				for id in enemies.keys():
					var delta: Vector3 = enemies[id].body.position - player.position
					if id == best or (delta.length() <= rules.skills.basic_attack.range and delta.normalized().dot(direction) >= float(rules.skills.chainsaw.fan_dot) and map.sees(player.position, enemies[id].body.position)):
						struck.append(id)
				var cut := false
				for id in struck:
					if enemies.has(id) and strike(id, damage, true, "witch", tool) != "miss":
						cut = true
						if enemies.has(id):
							add_bleed(id)
				if cut:
					play_cue(1.05)
			elif best != "" and tool != null:
				var debuff: String = rules.skills[tool].debuff
				var before: float = enemies[best][debuff]
				# Debuffs of different tools coexist; switching tools never clears them.
				enemies[best][debuff] = float(rules.skills[tool].debuff_seconds)
				if strike(best, damage, true, "witch", tool) == "miss":
					enemies[best][debuff] = before
				else:
					play_cue({"bolt_cutter": 0.8, "grinder": 1.55}[tool])
			elif best != "" and strike(best, damage, true, "witch", "staff") != "miss":
				play_cue(1.2)
		"shotgun":
			fire_shotgun(target)
		"bolt_cutter", "grinder", "chainsaw": pulse(player.position, TOOL_COLORS[event.skill], 0.8)
		"shield":
			shield_time = float(rules.skills.shield.duration_seconds)
			pulse(player.position + Vector3.UP, STEEL, 0.9)
		"automaton":
			var pos := automaton_spawn_position()
			if is_instance_valid(automaton_assembly):
				pos = automaton_assembly.position
				automaton_assembly.complete()
				automaton_assembly = null
			spawn_ally(pos, true, event.get("target_enemy", ""))
		"turret":
			var pos := point(event.position)
			if is_instance_valid(turret_assembly):
				pos = turret_assembly.position
				turret_assembly.complete()
				turret_assembly = null
			spawn_ally(pos, false, "")
		"relay":
			var linked: Array = []
			for ally in allies:
				if eligible(ally, event.target_enemy):
					ally.target = event.target_enemy
					linked.append(ally.node.position)
			spawn_vfx().relay(target, linked, map.ground_y(target))

func point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func nearest_enemy(pos: Vector3, distance: float, direction: Vector3 = Vector3.ZERO, dot_min: float = -1.0, visible_only: bool = false, need_sight: bool = false) -> String:
	var best = ""
	for id in enemies:
		var delta: Vector3 = enemies[id].body.position - pos
		if delta.length() < distance and (direction == Vector3.ZERO or delta.normalized().dot(direction) >= dot_min):
			if visible_only and not on_screen(enemies[id].body.position):
				continue
			if need_sight and not map.sees(pos, enemies[id].body.position):
				continue
			distance = delta.length()
			best = id
	return best

func enemy_name(id: String) -> String:
	var enemy: Dictionary = enemies[id]
	return config.grades[enemy.grade].name + " " + config.enemy_types[enemy.kind].name

func summon_level(roller: String) -> int:
	return int(config[roller + "_level"])

func hit_chance(id: String, roller: String = "witch") -> float:
	# Trial accuracy against the target's grade evasion. The witch's comes from dexterity;
	# a summon's comes from the level of the skill that built it, never from her stats (07 §2.1).
	var chance: float = config.hit_base + config.hit_per_dexterity * config.dexterity
	if roller != "witch":
		chance = config.summon_hit_base + config.summon_hit_per_level * (summon_level(roller) - 1)
	return clampf(chance - config.grades[enemies[id].grade].evasion, config.hit_min, config.hit_cap)

func crit_chance(roller: String = "witch") -> float:
	if roller != "witch":
		return minf(config.crit_cap, config.summon_crit_base + config.summon_crit_per_level * (summon_level(roller) - 1))
	return minf(config.crit_cap, config.crit_base + config.crit_per_dexterity * config.dexterity)

func strike(id: String, amount: float, accuracy_roll: bool, roller: String, source: String, look: String = "") -> String:
	# roller is "witch" or the summon skill ("automaton", "turret") whose level drives the rolls.
	# One direct damage event: optional hit roll, then its own crit roll (area attacks call this per enemy).
	if not enemies.has(id):
		return "miss"
	if accuracy_roll and not force_rolls.get("hit", combat_rng.randf() < hit_chance(id, roller)):
		probe.strike(source, "miss", 0.0)
		return "miss"
	var crit: bool = force_rolls.get("crit", combat_rng.randf() < crit_chance(roller))
	var at: Vector3 = enemies[id].body.position
	var size: float = enemies[id].size
	var dealt: float = damage_enemy(id, amount * (config.crit_multiplier if crit else 1.0))
	probe.strike(source, "crit" if crit else "hit", dealt)
	# Burst on the near surface: toward the witch and the camera, never buried inside the model.
	var toward: Vector3 = player.position - at
	toward.y = 0
	var surface: Vector3 = at + Vector3.UP * 0.85 * size + toward.normalized() * 0.3 * size + camera.global_basis.z * 0.6 * size
	# look only picks the impact style (the B saw); source stays the logged damage source.
	spawn_vfx().impact(surface, -toward, look if look != "" else source, crit, map.ground_y(at))
	if crit:
		play_cue(0.55)
		shake_time = 0.12
	return "crit" if crit else "hit"

func damage_enemy(id: String, amount: float, direct: bool = true) -> float:
	# Returns the HP actually removed, for the A5 log. Bleed ticks pass direct = false.
	if not enemies.has(id):
		return 0.0
	var enemy: Dictionary = enemies[id]
	# Trial shred: no armour formula exists yet, so shredded enemies take more direct damage.
	# Bleed ignores defence, so shred never raises it (07 §2.2).
	var taken: float = amount * (config.shred_damage_taken if enemy.shred > 0 and direct else 1.0)
	var dealt: float = minf(maxf(enemy.hp, 0.0), taken)
	enemy.hp -= taken
	if direct:
		enemy.flash = 0.16
	if enemy.hp <= 0:
		pulse(enemy.body.position, RED, 0.6)
		if enemy.model.has_method("detach_for_death"):
			enemy.model.detach_for_death(world, self)
		enemy.body.queue_free()
		enemies.erase(id)
		kills += 1
		probe.counts.kills += 1
		probe.grade(enemy.grade).kills += 1
		# A test boss is a one-off; everything else keeps the A5 field topped up.
		if a5_mode and enemy.grade != "boss" and enemy.respawn:
			respawns.append({"time": float(config.a5_respawn_seconds), "kind": enemy.kind, "grade": enemy.grade})
		if pending_cast.get("cursor", {}).get("enemy_id") == id:
			cancel_pending_cast()
			show_message("대상이 사라졌습니다")
		if queued_input.get("cursor", {}).get("enemy_id") == id:
			queued_input.clear()
		if hold.get("enemy_id") == id:
			hold.clear()
		if enemies.is_empty():
			cancel_pending_cast()
	return dealt

func bleed_plan(stacks: int) -> Dictionary:
	# What a new bleed gets at the chainsaw's level. Growth A raises the share of max HP; growth B
	# (chosen) lengthens the bleed at the same rate per second every level, and at every fifth level
	# lets later stacks keep more of their weight.
	var bleed: Dictionary = config.bleed
	var level: int = int(config.chainsaw_level) - 1
	var weights: Array = bleed.weights
	var weight: float = float(weights[mini(stacks, weights.size() - 1)])
	var ratio := 1.0
	var seconds: float = float(bleed.seconds)
	if bleed.growth == "A":
		ratio += float(bleed.a_ratio_per_level) * level
	else:
		seconds += float(bleed.b_seconds_per_level) * level
		var milestones: int = floori(float(config.chainsaw_level) / float(bleed.b_weight_every))
		weight += (1.0 - weight) * minf(1.0, float(bleed.b_weight_per_milestone) * milestones)
	return {"ratio": ratio * seconds / float(bleed.seconds), "seconds": seconds, "weight": weight}

func add_bleed(id: String) -> void:
	# Up to five independent stacks per enemy, each with its own timer. A stack's total is
	# max HP x grade share x its weight, fixed when applied by how many stacks were already running;
	# a sixth bleed replaces the oldest (trial rule).
	var enemy: Dictionary = enemies[id]
	var stacks: Array = enemy.bleeds
	if stacks.size() >= int(config.bleed.max_stacks):
		stacks.pop_front()
	var plan: Dictionary = bleed_plan(stacks.size())
	var total: float = enemy.max_hp * float(config.bleed.ratio[enemy.grade]) * plan.ratio * plan.weight
	var ticks: int = maxi(1, roundi(plan.seconds / float(config.bleed.tick_seconds)))
	stacks.append({"left": ticks, "per_tick": total / ticks, "clock": 0.0})
	probe.counts.bleeds_applied += 1

func tick_bleeds(dt: float) -> void:
	# Bleed is its own non-critical damage event: no hit roll, no crit, no defence, no stun.
	var step: float = float(config.bleed.tick_seconds)
	for id in enemies.keys():
		if not enemies.has(id):
			continue
		var stacks: Array = enemies[id].bleeds
		var amount := 0.0
		for stack in stacks:
			stack.clock += dt
			while stack.clock >= step and stack.left > 0:
				stack.clock -= step
				stack.left -= 1
				amount += stack.per_tick
		enemies[id].bleeds = stacks.filter(func(stack): return stack.left > 0)
		if amount > 0:
			probe.bleed(damage_enemy(id, amount, false))

func potion_cooldown(id: String) -> float:
	var longest = 0.0
	for group in config.potions[id].groups:
		longest = maxf(longest, potion_cooldowns.get(group, 0.0))
	return longest

func drink(index: int) -> void:
	# Drinking is instant and never waits for or cancels a motion, approach or hit recovery.
	var slot: Dictionary = potion_slots[index]
	if slot.count <= 0:
		return
	var potion: Dictionary = config.potions[slot.id]
	if potion_cooldown(slot.id) > 0:
		show_message("물약 준비 중입니다")
		return
	slot.count -= 1
	for group in potion.groups:
		potion_cooldowns[group] = float(potion.cooldown_seconds)
	var seconds: float = potion.seconds
	if potion.kind == "speed":
		speed_buff = seconds
	else:
		var full: bool = potion.get("full", false)
		potion_effects.append({"time": seconds,
			"hp_rate": (config.max_hp if full else potion.get("hp", 0.0)) / seconds if potion.kind != "mp" else 0.0,
			"mp_rate": (state.max_mana if full else potion.get("mp", 0.0)) / seconds if potion.kind != "hp" else 0.0})
	probe.potions[slot.id] = probe.potions.get(slot.id, 0) + 1
	pulse(player.position + Vector3.UP * 0.5, {"hp": RED, "mp": TEAL, "both": Color("c9a0dc"), "speed": Color("a8d672")}[potion.kind], 0.5)
	play_cue(1.4)

func cycle_potion(index: int) -> void:
	# Test tool: Shift+1-4 swaps that slot's potion type and restocks it.
	var ids: Array = config.potions.keys()
	var slot: Dictionary = potion_slots[index]
	slot.id = ids[(ids.find(slot.id) + 1) % ids.size()]
	slot.count = int(config.potion_test_count)
	show_message("%d번: %s ×%d" % [index + 1, config.potions[slot.id].name, slot.count])

func tick_potions(dt: float) -> void:
	for group in potion_cooldowns.keys():
		potion_cooldowns[group] = maxf(0, potion_cooldowns[group] - dt)
	speed_buff = maxf(0, speed_buff - dt)
	for effect in potion_effects.duplicate():
		var spent: float = minf(dt, effect.time)
		hp = minf(config.max_hp, hp + effect.hp_rate * spent)
		state = rules.restore_mana(state, effect.mp_rate * spent).state
		effect.time -= spent
		if effect.time <= 0:
			potion_effects.erase(effect)

func pending_fill(key: String) -> float:
	# What running potions will still add; the HUD shows it as a pale layer.
	var total = 0.0
	for effect in potion_effects:
		total += effect[key] * effect.time
	return total

func block_chance() -> float:
	# Trial formula from shield level and dexterity; it only applies while the shield is up.
	var shield: Dictionary = rules.skills.shield
	var chance: float = shield.block_base + shield.block_per_level * (config.shield_level - 1) + shield.block_per_dexterity * config.dexterity
	return clampf(chance, 0.0, shield.block_cap)

func hit_recovery_seconds() -> float:
	return motion_seconds(config.hit_recovery_seconds, config.min_hit_recovery_seconds, config.hit_recovery_k, config.hit_recovery_score)

func damage_player(amount: float, by_grade: String = "unknown") -> void:
	# by_grade names the attacker's grade for the A5 log; direct test calls leave it unknown.
	if hp <= 0:
		return
	if shield_time > 0 and block_rng.randf() < block_chance():
		# A blocked hit deals nothing and never interrupts; sound and flash tell it apart.
		spawn_vfx().block(player.position + Vector3.UP * 0.9, map.ground_y(player.position))
		play_cue(2.2)
		probe.witch_hit(by_grade, 0.0, false, true)
		return
	# Only a heavy enough hit that leaves her standing stuns.
	var stunned: bool = hp - amount > 0 and amount >= config.max_hp * config.hit_stun_min_ratio
	probe.witch_hit(by_grade, minf(hp, amount), stunned, false)
	hp = maxf(0, hp - amount)
	hit_time = 0.25
	spawn_vfx().hurt(player.position + Vector3.UP * 0.85, map.ground_y(player.position))
	play_cue(0.75)
	if stunned:
		# Hit recovery cancels the motion, approach, click move and queued input; nothing was spent yet.
		cancel_summon_assemblies("hit_stun")
		windup.clear()
		cancel_pending_cast()
		queued_input.clear()
		moving = false
		move_marker.visible = false
		stun_time = hit_recovery_seconds()
		action_time = stun_time
		player_visual.hit_react(stun_time)
	if hp == 0:
		cancel_summon_assemblies("death")
		probe.counts.deaths += 1
		save_mana_log("death")
		cancel_pending_cast()
		windup.clear()
		hold.clear()
		move_hold.clear()
		queued_input.clear()
		moving = false
		state.active_tool = null
		move_marker.visible = false
		player_visual.freeze_for_death()

func spawn_ally(pos: Vector3, mobile: bool, target_id) -> void:
	var node = Node3D.new()
	world.add_child(node)
	node.position = map.grounded(pos)
	ActorVisual.create(node, "automaton" if mobile else "turret", str(config.automaton_node) if mobile else "base", float(config.summon_lifetime))
	Shape.ring(node, Vector3(0, 0.04, 0), 0.43, TEAL)
	var durability: float = config.automaton_hp if mobile else config.turret_hp
	# The automaton keeps the node it was summoned with; B never times out but only so many stay.
	var kind: String = config.automaton_node if mobile else ""
	var life: float = config.summon_lifetime if mobile else config.turret_lifetime
	if kind == "B":
		# The lasting B automaton is a tank: a little harder hitting and sturdier.
		life = INF
		durability *= float(config.automaton_nodes.B.hp_factor)
		var kept: Array = allies.filter(func(other): return other.node_kind == "B")
		if kept.size() >= int(config.automaton_nodes.B.max_count):
			dismantle_ally(kept[0])
	allies.append({"id": "ally_%d" % ally_serial, "node": node, "mobile": mobile, "node_kind": kind, "route": {}, "target": target_id if target_id != null else "", "cooldown": 0.2,
		"life": life, "hp": durability, "max_hp": durability, "reach": 1.6})
	ally_serial += 1
	spawn_vfx().summon_arrive(node.position, TEAL, map.ground_y(node.position))
	play_cue(1.8)

func automaton_reach(id: String) -> float:
	# Automatons stop at arm's length from the target's body, so small foes get punched rather than
	# stared at from 1.6m. The boss keeps the old distance: its body is a whole door frame.
	var enemy: Dictionary = enemies[id]
	return 1.6 if enemy.kind == "latch" else 0.45 + 0.5 * float(enemy.size)

func dismantle_ally(ally: Dictionary) -> void:
	# The oldest B automaton makes room for a new one: it breaks apart with no blast.
	var art: Node = ally.node.get_node_or_null("ActorVisual")
	if art != null:
		art.detach_for_death(world, self)
	spawn_vfx().shutdown(ally.node.position, map.ground_y(ally.node.position))
	ally.node.queue_free()
	allies.erase(ally)

func expire_ally(ally: Dictionary) -> void:
	# End of life: automatons self-destruct, turrets just shut down. An A automaton also lands
	# here the moment it reaches its target, trading its repeated attacks for a bigger blast.
	if ally.mobile:
		var damage: float = config.shot_damage * (float(config.automaton_nodes.A.blast_factor) if ally.node_kind == "A" else 1.0)
		for id in enemies.keys():
			if enemies.has(id) and ally.node.position.distance_to(enemies[id].body.position) < config.summon_explosion_range:
				strike(id, damage, false, "automaton", "automaton_blast")
		spawn_vfx().blast(ally.node.position, float(config.summon_explosion_range), map.ground_y(ally.node.position), ally.node_kind == "A")
		shake_time = maxf(shake_time, 0.14 if ally.node_kind == "A" else 0.1)
	else:
		spawn_vfx().shutdown(ally.node.position, map.ground_y(ally.node.position))
	var art: Node = ally.node.get_node_or_null("ActorVisual")
	if art != null:
		art.detach_for_death(world, self, ally.mobile)
	play_cue(0.65 if ally.mobile else 1.15)
	ally.node.queue_free()
	allies.erase(ally)

func on_screen(pos: Vector3) -> bool:
	if camera.is_position_behind(pos):
		return false
	var screen = camera.unproject_position(pos)
	var rect = get_viewport().get_visible_rect()
	rect.size.y -= 155
	return rect.has_point(screen)

func eligible(ally: Dictionary, id: String) -> bool:
	return enemies.has(id) and on_screen(enemies[id].body.position) and ally.node.position.distance_to(enemies[id].body.position) <= (config.summon_detection_range if ally.mobile else config.turret_detection_range) and map.sees(ally.node.position, enemies[id].body.position)

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player):
		return
	sync_automaton_cost()
	if not paused and field_cleared():
		cancel_summon_assemblies("field_cleared")
	var visual_start_position := player.position
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
		tick_potions(dt)
		tick_bolts(dt)
		tick_bleeds(dt)
		tick_boss_trigger()
		tick_windup(dt)
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
				var speed: float = config.player_speed * (1.0 + (config.potions.speed.speed_bonus if speed_buff > 0 else 0.0))
				var step: Vector3 = follow(player_route, player.position, destination, 0.5, dt) - player.position
				step.y = 0
				if step.length() < 0.001:
					step = delta
				player.velocity = step.normalized() * minf(speed, step.length() / dt)
				player.move_and_slide()
				player_model.look_at(player.position + step.normalized())
		# Feet follow the floor: bodies only collide with walls, so steps lift them here.
		player.position.y = map.ground_y(player.position)
		for id in enemies.keys():
			_tick_enemy(enemies[id], dt)
			if enemies.has(id):
				enemies[id].body.position.y = map.ground_y(enemies[id].body.position)
			if enemies.has(id) and enemies[id].model.has_method("sync_enemy"):
				enemies[id].model.sync_enemy(enemies[id], dt)
		_tick_allies(dt)
		for ally in allies:
			ally.node.position.y = map.ground_y(ally.node.position)
			var art: Node = ally.node.get_node_or_null("ActorVisual")
			if art != null:
				art.sync_ally(ally, dt, ally.node.position.distance_to(enemies[ally.target].body.position) if enemies.has(ally.target) else INF)
	player_visual.set_active_tool(state.active_tool)
	for id in tool_rings:
		tool_rings[id].visible = state.active_tool == id
	if is_instance_valid(grinder_disk) and state.active_tool == "grinder" and not paused and hp > 0 and not field_cleared():
		grinder_disk.rotate_object_local(Vector3.UP, dt * 18)
	var visual_distance := player.position.distance_to(visual_start_position)
	player_visual.sync_state(dt, visual_distance > 0.0001, action_time, paused, hp <= 0, field_cleared(), visual_distance / maxf(dt, 0.000001))
	tick_staff_trail(dt)
	shield_ring.visible = shield_time > 0
	place_camera(player.position)
	map.fade_between(camera.global_position, player.position + Vector3.UP)
	if shake_time > 0:
		# Short crit or boss-impact jolt; the camera angle never changes, only a small offset.
		shake_time = maxf(0, shake_time - dt)
		camera.position += Vector3(sin(elapsed * 90), 0, cos(elapsed * 77)) * 0.06
	var hovered = pick_cursor(get_viewport().get_mouse_position())
	hover_id = hovered.get("enemy_id", "")
	hover_ring.visible = enemies.has(hover_id)
	if hover_ring.visible:
		hover_ring.position = enemies[hover_id].body.position + Vector3(0, 0.04, 0)
	if not paused:
		message_time = maxf(0, message_time - dt)
		fallback_time = maxf(0, fallback_time - dt)
		hit_time = maxf(0, hit_time - dt)
		stun_time = maxf(0, stun_time - dt)
		shield_time = maxf(0, shield_time - dt)
		for fx in effects.duplicate():
			fx.life -= dt
			if fx.life <= 0:
				fx.node.queue_free()
				effects.erase(fx)
			elif fx.node.has_method("sync_effect"):
				fx.node.sync_effect(dt, fx.life)
			elif fx.grow:
				fx.node.scale += Vector3.ONE * dt * 2
			elif fx.has("fill"):
				# Warning fill: reaches the edge exactly when the attack lands.
				var done: float = clampf(1.0 - fx.life / fx.fill, 0.02, 1.0)
				fx.node.scale = Vector3(done, 1, done) if fx.axis == "radial" else Vector3(1, 1, done)
	hud.queue_redraw()

func ally_by_id(id: String) -> Dictionary:
	for ally in allies:
		if ally.id == id:
			return ally
	return {}

func foe_position(target: String) -> Vector3:
	# "" is the witch; anything else is a summon or turret id.
	var ally: Dictionary = ally_by_id(target)
	return player.position if ally.is_empty() else ally.node.position

func aggro_distance(enemy: Dictionary, target: String) -> float:
	# The witch counts a little closer than she is, so summons don't soak every hit.
	if target == "":
		return INF if hp <= 0 else enemy.body.position.distance_to(player.position) - config.aggro_witch_bias
	var ally: Dictionary = ally_by_id(target)
	return INF if ally.is_empty() else enemy.body.position.distance_to(ally.node.position)

func nearest_foe(enemy: Dictionary) -> String:
	# Aggro goes to whatever is closest, so summons and turrets can draw enemies off the witch.
	var best = ""
	var best_distance: float = aggro_distance(enemy, "")
	for ally in allies:
		var d: float = aggro_distance(enemy, ally.id)
		if d < best_distance:
			best_distance = d
			best = ally.id
	# Sticky target: switch only when the new one is clearly closer, so an enemy standing
	# between two targets doesn't flip back and forth.
	var current: float = aggro_distance(enemy, enemy.target)
	if best != enemy.target and current < INF and best_distance > current - config.aggro_switch_margin:
		return enemy.target
	return best

func hit_foe(target: String, amount: float, grade: String) -> void:
	var ally: Dictionary = ally_by_id(target)
	if ally.is_empty():
		damage_player(amount, grade)
	else:
		damage_ally(ally, amount, grade)

func damage_ally(ally: Dictionary, amount: float, grade: String) -> void:
	ally.hp -= amount
	probe.ally_hit(grade, minf(amount, maxf(ally.hp + amount, 0.0)), ally.hp <= 0)
	var floor_y: float = map.ground_y(ally.node.position)
	spawn_vfx().summon_hit(ally.node.position + Vector3.UP * 0.6 + camera.global_basis.z * 0.4, floor_y)
	if ally.hp <= 0:
		# Destroyed summons break apart without the end-of-life self-destruct blast.
		spawn_vfx().summon_break(ally.node.position + Vector3.UP * 0.5, floor_y)
		play_cue(1.15)
		var art: Node = ally.node.get_node_or_null("ActorVisual")
		if art != null:
			art.detach_for_death(world, self)
		ally.node.queue_free()
		allies.erase(ally)

func foe_in_reach(at: Vector3, reach: float) -> String:
	# First thing within reach of a moving hit (orb or charge): the witch, else the nearest summon.
	var flat: Vector3 = player.position - at
	flat.y = 0
	if hp > 0 and flat.length() < reach:
		return ""
	for ally in allies:
		flat = ally.node.position - at
		flat.y = 0
		if flat.length() < reach:
			return ally.id
	return "none"

func _tick_enemy(enemy: Dictionary, dt: float) -> void:
	if enemy.target != "" and ally_by_id(enemy.target).is_empty():
		enemy.target = ""
		enemy.retarget = 0.0
	var aim: Vector3 = foe_position(enemy.target)
	var delta: Vector3 = aim - enemy.body.position
	enemy.slow = maxf(0, enemy.slow - dt)
	enemy.shred = maxf(0, enemy.shred - dt)
	enemy.flash = maxf(0, enemy.flash - dt)
	enemy.model.scale = Vector3.ONE * enemy.size * (1.08 if enemy.flash > 0 else 1.0)
	var type: Dictionary = config.enemy_types[enemy.kind]
	var power: float = config.grades[enemy.grade].damage
	var pace: float = config.enemy_speed * type.speed * config.grades[enemy.grade].speed * (config.slow_speed_factor if enemy.slow > 0 else 1.0)
	if type.has("boss"):
		tick_boss(enemy, type.boss, power, pace, dt)
		return
	enemy.charge_cooldown = maxf(0, enemy.charge_cooldown - dt)
	if enemy.charging > 0:
		# Brute charge: a straight dash along the telegraphed line that hits the witch at most once.
		var charge: Dictionary = type.charge
		enemy.charging = maxf(0, enemy.charging - dt)
		enemy.body.velocity = enemy.charge_dir * config.enemy_speed * charge.speed_factor * (config.slow_speed_factor if enemy.slow > 0 else 1.0)
		enemy.body.move_and_slide()
		var dust = enemy.body.get_meta("charge_vfx", null)
		if is_instance_valid(dust):
			dust.dust_trail(enemy.body.position)
		var struck: String = foe_in_reach(enemy.body.position, charge.reach) if not enemy.charge_hit else "none"
		if struck != "none":
			enemy.charge_hit = true
			enemy.charging = 0.0
			hit_foe(struck, charge.damage * power, enemy.grade)
		return
	if enemy.windup > 0:
		enemy.windup -= dt
		if not enemy.model.has_method("sync_enemy"):
			enemy.model.rotation.z = sin(enemy.windup * 35) * 0.12
		if enemy.windup <= 0:
			enemy.model.rotation.z = 0
			enemy.cooldown = type.cooldown
			match enemy.attack:
				"bolt": fire_bolt(enemy, aim, type.ranged, type.damage * power)
				"charge":
					enemy.charge_cooldown = type.charge.cooldown
					enemy.charging = type.charge.distance / maxf(0.01, config.enemy_speed * type.charge.speed_factor)
					enemy.charge_hit = false
					var dust = spawn_vfx()
					dust.dust_trail(enemy.body.position)
					enemy.body.set_meta("charge_vfx", dust)
				_:
					spawn_vfx().claw(enemy.body.position, aim - enemy.body.position, float(type.reach), Color(1.0, 0.42, 0.3) if enemy.kind != "brute" else Color(1.0, 0.6, 0.35), enemy.kind == "brute", map.ground_y(enemy.body.position))
					# Reach and stop distances are absolute: capsules keep bodies apart regardless of model size.
					if delta.length() < type.reach and map.sees(enemy.body.position, aim):
						hit_foe(enemy.target, type.damage * power, enemy.grade)
		return
	enemy.cooldown = maxf(0, enemy.cooldown - dt)
	# Pick a target only between attacks; a wound-up attack keeps the one it started on.
	enemy.retarget = maxf(0, enemy.retarget - dt)
	if enemy.retarget <= 0:
		enemy.target = nearest_foe(enemy)
		enemy.retarget = config.aggro_retarget_seconds
		aim = foe_position(enemy.target)
		delta = aim - enemy.body.position
	var distance: float = delta.length()
	if distance > 11:
		return
	enemy.model.look_at(Vector3(aim.x, enemy.body.global_position.y, aim.z))
	if type.has("ranged"):
		# Wire crows hold a firing band: back off when crowded, close in when too far, shoot between.
		var band: Dictionary = type.ranged
		var clear: bool = map.sees(enemy.body.position, aim)
		var step = Vector3.ZERO
		if distance > band.keep_max or not clear:
			# Without a clear shot the crow walks the route until one opens.
			step = (follow(enemy.route, enemy.body.position, aim, 0.35, dt) - enemy.body.position).normalized()
		elif distance < band.keep_min:
			step = -delta.normalized()
		enemy.body.velocity = step * pace
		enemy.body.move_and_slide()
		if enemy.cooldown <= 0 and distance <= band.bolt_range and clear:
			start_enemy_attack(enemy, "bolt", type.windup, TEAL)
		return
	var in_sight: bool = map.sees(enemy.body.position, aim)
	if type.has("charge") and enemy.charge_cooldown <= 0 and enemy.cooldown <= 0 and distance >= type.charge.min and distance <= type.charge.max and in_sight:
		enemy.charge_dir = Vector3(delta.x, 0, delta.z).normalized()
		start_enemy_attack(enemy, "charge", type.charge.windup, RED)
		telegraph(enemy.body.position, enemy.charge_dir, type.charge.distance, type.charge.width, type.charge.windup)
		return
	if distance > type.stop or not in_sight:
		# Chase along the route so corners and low walls are walked around, not into.
		var step: Vector3 = follow(enemy.route, enemy.body.position, aim, 0.35, dt) - enemy.body.position
		step.y = 0
		enemy.body.velocity = step.normalized() * pace
		enemy.body.move_and_slide()
	elif enemy.cooldown <= 0:
		start_enemy_attack(enemy, "melee", type.windup, RED)

func tick_boss(enemy: Dictionary, plan: Dictionary, power: float, pace: float, dt: float) -> void:
	# 08 §6.3 trial boss: sweep then slam up close, door-frame crossfire at range,
	# and a shockwave that calls adds at each HP mark. Every attack is telegraphed on the ground.
	for key in enemy.timers.keys():
		enemy.timers[key] = maxf(0, enemy.timers[key] - dt)
	if enemy.windup > 0:
		enemy.windup -= dt
		if not enemy.model.has_method("sync_enemy"):
			enemy.model.rotation.z = sin(enemy.windup * 22) * 0.06
		if enemy.windup <= 0:
			enemy.model.rotation.z = 0
			resolve_boss(enemy, plan, power)
		return
	for mark in plan.shockwave.marks:
		if enemy.hp <= enemy.max_hp * mark and not enemy.phases_done.has(mark):
			enemy.phases_done.append(mark)
			begin_boss(enemy, "shockwave", plan.shockwave.windup)
			disc_warning(enemy.body.position, plan.shockwave.radius, plan.shockwave.windup)
			return
	enemy.retarget = maxf(0, enemy.retarget - dt)
	if enemy.retarget <= 0:
		enemy.target = nearest_foe(enemy)
		enemy.retarget = config.aggro_retarget_seconds
	var aim: Vector3 = foe_position(enemy.target)
	var delta: Vector3 = aim - enemy.body.position
	delta.y = 0
	var distance: float = delta.length()
	if distance > 14:
		return
	enemy.model.look_at(Vector3(aim.x, enemy.body.global_position.y, aim.z))
	enemy.pattern_dir = delta.normalized() if distance > 0.01 else Vector3.FORWARD
	var clear: bool = map.sees(enemy.body.position, aim)
	if distance <= plan.sweep.range and enemy.timers.get("sweep", 0.0) <= 0 and clear:
		begin_boss(enemy, "sweep", plan.sweep.windup)
		fan_warning(enemy.body.position, enemy.pattern_dir, plan.sweep.range, plan.sweep.angle, plan.sweep.windup)
	elif distance <= plan.slam.length and enemy.timers.get("slam", 0.0) <= 0 and clear:
		begin_slam(enemy, plan)
	elif distance > plan.sweep.range and enemy.timers.get("frames", 0.0) <= 0:
		begin_frames(enemy, plan, aim)
	elif distance > plan.keep or not clear:
		var step: Vector3 = follow(enemy.route, enemy.body.position, aim, 0.4, dt) - enemy.body.position
		step.y = 0
		enemy.body.velocity = step.normalized() * pace
		enemy.body.move_and_slide()

func begin_boss(enemy: Dictionary, pattern: String, windup: float) -> void:
	enemy.attack = pattern
	enemy.windup = windup
	if enemy.model.has_method("begin_attack"):
		enemy.model.begin_attack(pattern, windup)
	spawn_vfx().tell(enemy.body.position + Vector3.UP * 2.0, Color(1.0, 0.5, 0.3), 2.0)

func begin_slam(enemy: Dictionary, plan: Dictionary, extra: float = 0.0) -> void:
	# extra: the slam that follows a sweep waits longer, so a witch stunned by the sweep can still step out.
	begin_boss(enemy, "slam", plan.slam.windup + extra)
	telegraph(enemy.body.position, enemy.pattern_dir, plan.slam.length, plan.slam.width, plan.slam.windup + extra)

func begin_frames(enemy: Dictionary, plan: Dictionary, aim: Vector3) -> void:
	# Two hovering door frames open beside the target; the shots come out of them, not the boss.
	begin_boss(enemy, "frames", plan.frames.windup)
	var side: Vector3 = enemy.pattern_dir.cross(Vector3.UP).normalized()
	enemy.frames = []
	for sign_x in [-1.0, 1.0]:
		var spot: Vector3 = aim + side * sign_x * plan.frames.offset
		spot.x = clampf(spot.x, map.bounds.position.x + 0.75, map.bounds.end.x - 0.75)
		spot.z = clampf(spot.z, map.bounds.position.y + 0.75, map.bounds.end.y - 0.75)
		enemy.frames.append(spot)
		var frame: Node3D = Shape.door_frame(world, spot, Color("8a6a3a"))
		frame.look_at(Vector3(aim.x, spot.y, aim.z))
		if frame.has_method("configure"):
			frame.configure(plan.frames.windup)
		effects.append({"node": frame, "life": plan.frames.windup + 0.35, "grow": false})
		# Ground lane from the frame to the target spot, so the side threat reads before the shot.
		var lane: Vector3 = Vector3(aim.x, 0, aim.z) - Vector3(spot.x, 0, spot.z)
		telegraph(Vector3(spot.x, 0, spot.z), lane.normalized(), lane.length() + 1.0, 0.6, plan.frames.windup)

func boss_area_hit(enemy: Dictionary, inside: Callable, damage: float) -> void:
	# Area patterns hit the witch and every summon standing in the warned shape.
	if hp > 0 and inside.call(player.position):
		damage_player(damage, enemy.grade)
	for ally in allies.duplicate():
		if inside.call(ally.node.position):
			damage_ally(ally, damage, enemy.grade)

func resolve_boss(enemy: Dictionary, plan: Dictionary, power: float) -> void:
	var origin: Vector3 = enemy.body.position
	var facing: Vector3 = enemy.pattern_dir
	if enemy.model.has_method("release_attack"):
		enemy.model.release_attack(enemy.attack)
	match enemy.attack:
		"sweep":
			var sweep: Dictionary = plan.sweep
			enemy.timers.sweep = sweep.cooldown
			var in_fan := func(at: Vector3) -> bool:
				var flat: Vector3 = at - origin
				flat.y = 0
				return flat.length() <= sweep.range and (flat.length() < 0.01 or rad_to_deg(facing.angle_to(flat.normalized())) <= sweep.angle / 2.0)
			boss_area_hit(enemy, in_fan, sweep.damage * power)
			spawn_vfx().fan_slash(origin, facing, float(sweep.range), float(sweep.angle), map.ground_y(origin))
			play_cue(0.5)
			# The lock comes down right after the sweep along the same facing.
			if enemy.timers.get("slam", 0.0) <= 0:
				begin_slam(enemy, plan, plan.slam.chain_extra)
		"slam":
			var slam: Dictionary = plan.slam
			enemy.timers.slam = slam.cooldown
			var in_line := func(at: Vector3) -> bool:
				var flat: Vector3 = at - origin
				flat.y = 0
				var along: float = flat.dot(facing)
				return along >= 0 and along <= slam.length and absf(flat.dot(facing.cross(Vector3.UP))) <= slam.width / 2.0
			boss_area_hit(enemy, in_line, slam.damage * power)
			spawn_vfx().slam(origin, facing, float(slam.length), float(slam.width), map.ground_y(origin))
			shake_time = maxf(shake_time, 0.16)
			play_cue(0.4)
		"frames":
			var frames: Dictionary = plan.frames
			enemy.timers.frames = frames.cooldown
			for spot in enemy.frames:
				fire_bolt_from(spot, foe_position(enemy.target), frames, frames.damage * power, enemy.grade)
		"shockwave":
			var wave: Dictionary = plan.shockwave
			var in_disc := func(at: Vector3) -> bool:
				var flat: Vector3 = at - origin
				flat.y = 0
				return flat.length() <= wave.radius
			boss_area_hit(enemy, in_disc, wave.damage * power)
			spawn_vfx().shockwave(origin, float(wave.radius), map.ground_y(origin))
			shake_time = maxf(shake_time, 0.22)
			play_cue(0.35)
			# Called adds join from the field edges and never respawn in A5 mode.
			for kind in wave.adds:
				for i in int(wave.adds[kind]):
					var add_id: String = "add_" + str(spawn_serial)
					spawn_serial += 1
					spawn_enemy(add_id, edge_point(), false, "normal", kind)
					enemies[add_id].respawn = false

func fan_warning(from: Vector3, facing: Vector3, radius: float, angle: float, life: float) -> void:
	for filled in [false, true]:
		var fan: MeshInstance3D = Shape.fan(world, from + Vector3(0, 0.04 if filled else 0.03, 0), radius, angle, WARN_FILL if filled else WARN)
		fan.material_override = warning_material(filled, 0, radius, 1.0, deg_to_rad(angle) / 2.0)
		fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fan.look_at(fan.position + facing)
		warn_effect(fan, life, filled, "radial")

func disc_warning(at: Vector3, radius: float, life: float) -> void:
	for filled in [false, true]:
		var disc: MeshInstance3D = Shape.cylinder(world, at + Vector3(0, 0.04 if filled else 0.03, 0), radius, 0.02, WARN_FILL if filled else WARN)
		disc.material_override = warning_material(filled, 0, radius)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		warn_effect(disc, life, filled, "radial")

func start_enemy_attack(enemy: Dictionary, attack: String, windup: float, color: Color) -> void:
	enemy.attack = attack
	enemy.windup = windup
	if enemy.model.has_method("begin_attack"):
		enemy.model.begin_attack(attack, windup)
	spawn_vfx().tell(enemy.body.position + Vector3.UP * 1.25 * enemy.size, color, enemy.size)

func telegraph(from: Vector3, direction: Vector3, length: float, width: float, life: float) -> void:
	# Flat warning strip on the ground; a brighter strip fills it from the attacker outwards.
	for filled in [false, true]:
		var pivot = Node3D.new()
		world.add_child(pivot)
		pivot.position = from + Vector3(0, 0.04 if filled else 0.03, 0)
		pivot.look_at(pivot.position + direction)
		var strip: MeshInstance3D = Shape.box(pivot, Vector3(0, 0, -length / 2), Vector3(width, 0.02, length), WARN_FILL if filled else WARN)
		strip.material_override = warning_material(filled, 1, length, width)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		warn_effect(pivot, life, filled, "length")

func warn_effect(node: Node3D, life: float, filled: bool, axis: String) -> void:
	var fx = {"node": node, "life": life, "grow": false}
	if filled:
		fx.merge({"fill": life, "axis": axis})
		node.scale = Vector3(0.02, 1, 0.02) if axis == "radial" else Vector3(1, 1, 0.02)
	effects.append(fx)

func fire_bolt(enemy: Dictionary, at: Vector3, band: Dictionary, damage: float) -> void:
	# The orb flies toward where its target stands at release, so stepping aside dodges it.
	fire_bolt_from(enemy.body.position + Vector3.UP * 1.0 * enemy.size, at, band, damage, enemy.grade)

func fire_bolt_from(origin: Vector3, at: Vector3, band: Dictionary, damage: float, grade: String) -> void:
	# Orbs fly at sight height above the shooter's ground: over low walls, into tall ones.
	origin.y = map.ground_y(origin) + FieldMap.SIGHT_HEIGHT
	var aim: Vector3 = at - origin
	aim.y = 0
	var node = Shape.sphere(world, origin, 0.12, Color("e6f6ff"))
	node.material_override = Shape.material(Color("e6f6ff"), true)
	node.material_override.emission_energy_multiplier = 2.2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail = spawn_vfx()
	trail.bolt_trail(origin, BOLT_GLOW)
	bolts.append({"node": node, "dir": aim.normalized(), "speed": float(band.bolt_speed), "left": float(band.bolt_range),
		"radius": float(band.bolt_radius), "damage": damage, "grade": grade, "trail": trail})
	play_cue(1.9)

func tick_bolts(dt: float) -> void:
	for bolt in bolts.duplicate():
		var travel: float = bolt.speed * dt
		var before: Vector3 = bolt.node.position
		bolt.node.position += bolt.dir * travel
		if is_instance_valid(bolt.trail):
			bolt.trail.bolt_trail(bolt.node.position, BOLT_GLOW)
		if not map.clear(before, bolt.node.position):
			if is_instance_valid(bolt.trail):
				bolt.trail.burst(before, BOLT_GLOW, map.ground_y(before))
			bolt.left = 0
		bolt.left -= travel
		var struck: String = foe_in_reach(bolt.node.position, bolt.radius)
		if struck != "none":
			if is_instance_valid(bolt.trail):
				bolt.trail.burst(bolt.node.position, BOLT_GLOW, map.ground_y(bolt.node.position))
			hit_foe(struck, bolt.damage, bolt.grade)
			bolt.left = 0
		if bolt.left <= 0 or not map.bounds.grow(1.0).has_point(Vector2(bolt.node.position.x, bolt.node.position.z)):
			bolt.node.queue_free()
			bolts.erase(bolt)

func _tick_allies(dt: float) -> void:
	for ally in allies.duplicate():
		ally.life -= dt
		if ally.life <= 0:
			expire_ally(ally)
			continue
		if ally.mobile and not on_screen(ally.node.position):
			ally.target = ""
			ally.node.position = ally.node.position.move_toward(follow(ally.route, ally.node.position, automaton_spawn_position(), 0.4, dt), dt * 7)
			continue
		if not eligible(ally, ally.target):
			ally.target = nearest_enemy(ally.node.position, config.summon_detection_range if ally.mobile else config.turret_detection_range, Vector3.ZERO, -1, true, true)
		if ally.target == "":
			if ally.mobile:
				ally.node.position = ally.node.position.move_toward(follow(ally.route, ally.node.position, automaton_spawn_position(), 0.4, dt), dt * 4)
			continue
		var target: Vector3 = enemies[ally.target].body.position
		ally.node.look_at(target)
		if ally.node_kind == "A" and ally.node.position.distance_to(target) <= 1.8:
			expire_ally(ally)
			continue
		if ally.mobile:
			ally.reach = automaton_reach(ally.target)
		if ally.mobile and ally.node.position.distance_to(target) > ally.reach:
			var speed: float = 4.0 * (float(config.automaton_nodes.A.speed_factor) if ally.node_kind == "A" else 1.0)
			ally.node.position = ally.node.position.move_toward(follow(ally.route, ally.node.position, target, 0.4, dt), dt * speed)
		ally.cooldown -= dt
		if ally.cooldown <= 0 and (not ally.mobile or ally.node.position.distance_to(target) <= ally.reach + 0.2):
			var shot_origin: Vector3 = ally.node.position + Vector3.UP * 0.8
			var art: Node = ally.node.get_node_or_null("ActorVisual")
			if art != null:
				art.preview_shot(ally)
				shot_origin = art.strike_point() if ally.mobile else art.muzzle_position()
			if not ally.mobile:
				spawn_vfx().summon_shot(shot_origin, target + Vector3.UP * 0.8, Color(1.0, 0.78, 0.45), map.ground_y(shot_origin))
			elif ally.node_kind != "B":
				# The automaton lands a lunging piston punch; the B node's saw makes its own sparks.
				spawn_vfx().summon_punch(shot_origin, target - ally.node.position, TEAL, map.ground_y(shot_origin))
			var saw: bool = ally.mobile and ally.node_kind == "B"
			var damage: float = config.summon_damage * (float(config.automaton_nodes.B.damage_factor) if ally.node_kind == "B" else 1.0)
			strike(ally.target, damage if ally.mobile else config.turret_damage, true, "automaton" if ally.mobile else "turret", "automaton" if ally.mobile else "turret", "saw" if saw else "")
			ally.cooldown = config.summon_attack_cooldown if ally.mobile else config.turret_attack_cooldown

func show_message(value: String) -> void:
	if value == message and message_time > 0.3:
		return
	message = value
	message_time = 1.1

func spawn_vfx() -> Node3D:
	# Presentation only: the arena frees it with the other effects once its particles die out.
	var fx = CombatVfx.new()
	world.add_child(fx)
	fx.setup(vfx_rng.randi(), camera)
	fx.entry = {"node": fx, "life": 0.05, "grow": false}
	effects.append(fx.entry)
	return fx

func tick_staff_trail(dt: float) -> void:
	# The swing trail follows the actual staff (or tool) tip of the playing clip, so swing and
	# thrust variants both draw their own path. Slow parts of the motion leave no streak.
	if paused or not is_instance_valid(staff_trail):
		return
	var visual = player_visual
	if visual.loaded_ok and visual._motion_kind == "attack" and is_instance_valid(visual.staff_root) and dt > 0:
		var tool = state.active_tool
		var reach: float = {"bolt_cutter": 0.95, "grinder": 0.98, "chainsaw": 1.1}.get(tool, 0.82)
		var tip: Vector3 = visual.staff_root.to_global(Vector3(0, reach + 0.1, 0))
		var base: Vector3 = visual.staff_root.to_global(Vector3(0, 0.36, 0))
		if staff_tip_last != null:
			var color: Color = {"bolt_cutter": Color(1.0, 0.78, 0.45), "grinder": Color(1.0, 0.62, 0.3), "chainsaw": Color(1.0, 0.42, 0.3)}.get(tool, Color(0.62, 1.0, 0.9))
			color.a = clampf((tip.distance_to(staff_tip_last) / dt - 1.2) / 2.5, 0.0, 1.0)
			staff_trail.blade_point(base, tip, color)
		staff_tip_last = tip
	else:
		staff_tip_last = null
	staff_trail.sync_effect(dt, 1.0)

func warning_material(filled: bool, kind: int, extent: float, width: float = 1.0, half_angle: float = PI + 0.1) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	material.shader = WARNING_SHADER
	material.set_shader_parameter("filled", filled)
	material.set_shader_parameter("kind", kind)
	material.set_shader_parameter("extent", extent)
	material.set_shader_parameter("width", width)
	material.set_shader_parameter("half_angle", half_angle)
	return material

func pulse(pos: Vector3, color: Color, radius: float) -> void:
	var node = Shape.ring(world, pos + Vector3(0, 0.06, 0), radius, color)
	effects.append({"node": node, "life": 0.32, "grow": true})
