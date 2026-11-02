extends Node3D
const Rules = preload("res://scripts/combat_rules.gd")
const Shape = preload("res://scripts/shapes.gd")
const Hud = preload("res://scripts/hud.gd")
const ManaProbe = preload("res://scripts/mana_probe.gd")
const Build = preload("res://scripts/build.gd")
const Items = preload("res://scripts/items.gd")
const GroundLoot = preload("res://scripts/ground_loot.gd")
const InventoryWindow = preload("res://scripts/inventory_window.gd")
const BuildWindow = preload("res://scripts/build_window.gd")
const FieldMap = preload("res://scripts/field_map.gd")
const PlayerVisual = preload("res://scripts/player_visual.gd")
const ActorVisual = preload("res://scripts/actor_visual.gd")
const AutomatonAssembly = preload("res://scripts/automaton_assembly.gd")
const TurretAssembly = preload("res://scripts/turret_assembly.gd")
const ShotgunCast = preload("res://scripts/shotgun_cast.gd")
const ShotgunGeometry = preload("res://scripts/shotgun_geometry.gd")
const ShieldVisual = preload("res://scripts/shield_visual.gd")
const CastCircle = preload("res://scripts/cast_circle.gd")
const SpringPlate = preload("res://scripts/spring_plate.gd")
# Which skill tree draws the casting circle; the basic attack draws none.
const SKILL_TREES = {"shotgun": "firearm", "bolt_cutter": "drive", "grinder": "drive", "chainsaw": "drive", "shield": "drive", "spring_dash": "drive",
	"automaton": "automation", "turret": "automation", "relay": "automation"}
const CombatVfx = preload("res://scripts/combat_vfx.gd")
const AssetWarmup = preload("res://scripts/asset_warmup.gd")
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const WARNING_SHADER = preload("res://shaders/warning_zone.gdshader")
const OUTLINE_SHADER = preload("res://shaders/outline.gdshader")
const AURA_SHADER = preload("res://shaders/grade_aura.gdshader")
const MASK_SHADER = preload("res://shaders/silhouette_mask.gdshader")
# Champion and elite enemies glow (saturated grade hues) instead of wearing a ring and head band.
const AURA_COLORS = {"champion": Color(0.35, 0.6, 1.0), "elite": Color(1.0, 0.68, 0.18)}
const TEAL = Color("8dd8c4")
const BRASS = Color("c69b62")
const RED = Color("ee987d")
const STEEL = Color("a9c1d6")
const GOLD_FLASH = Color("ffe08a")
const BOLT_GLOW = Color(0.62, 0.86, 1.0)
# World offsets from the witch where following automatons wait; the first is the original anchor.
const FOLLOW_SLOTS = [Vector3(1, 0, 0.6), Vector3(-1, 0, 0.6), Vector3(1, 0, -0.9), Vector3(-1, 0, -0.9),
	Vector3(0, 0, 1.3), Vector3(1.8, 0, -0.1), Vector3(-1.8, 0, -0.1), Vector3(0, 0, -1.6)]
const ALLY_SPACING := 0.85
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
# C1/C2 trial build and its two windows (character C, skill tree S).
var build: RefCounted
var character_window: PanelContainer
var skill_window: PanelContainer
# Spring dash in flight: {direction, left, speed}; empty when not dashing.
var dash: Dictionary = {}
# C4-C6 trial items: what lies on the field, the bag, the worn slots (slot -> item or null)
# and the totals of what is worn. Drops roll on their own stream, never the combat one.
var items: RefCounted
var loot_rng = RandomNumberGenerator.new()
var ground_items: Array = []
var deferred_ground_items: Array = []
var loot_layout := GroundLoot.new()
var hovered_loot: Dictionary = {}
var show_all_loot_labels := false
var loot_pointer := Vector2.ZERO
# The loot she was clicked over to; it goes into the bag once she is near it.
var loot_target: Dictionary = {}
var bag: Array = []
# What the inventory window's cursor carries: an item taken out of the bag or a slot, or a name
# piece to click into a socket. Both stay on the arena so a restart or closing the window can
# put them back.
var held_item = null
var held_piece := ""
var equipment: Dictionary = {}
var gear: Dictionary = {}
var inventory_window: PanelContainer
var tool_upkeep: Dictionary = {}
# C7/C8: 각인전 (currency), salvage material and stacked name pieces; they persist like the bag.
var coins := 0
# Trial enemy level: enemies grow in HP and damage per level so a level 30 build is not measured
# against first-area enemies. It follows the trial level until it is set apart in the C window.
var enemy_level := 1
var enemy_level_linked := true
var scrap := 0
var pieces: Dictionary = {}
var base_mana_costs: Dictionary = {}
# C10: potions bought or dropped wait in the stash; the four quickslots are refilled by hand
# from it (04 §8.2: no automatic refill). The stash persists; a restart still restocks the loadout.
var potion_stash: Dictionary = {}
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
var spring_plate: Node3D
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
# Named combat effects; play_cue stays for cues without one.
var sfx: Node
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
var shield_ring: Node3D
var shield_visual = null
var cast_circles: Array = []
var charging_circle = null
# Potion quickslots 1-4: refills over time, cooldowns shared per group, no auto-restock.
var potion_slots: Array = []
var potion_cooldowns: Dictionary = {}
var potion_effects: Array = []
var speed_buff = 0.0
var elapsed = 0.0
var last_events: Array = []
var hover_id = ""
var outlined_id = ""
var enemy_overlays: Dictionary = {}
var hover_ring: Node3D
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
# Auto follows the existing standalone-game versus scripted-harness convention.
# Integration tests and reviews explicitly select Always; ordinary combat harnesses
# retain their immediate flat-arena setup. Disabled is useful for repeated playtests.
@export_enum("Auto", "Always", "Disabled") var field_entry_mode: int = 0
# Start-of-game asset/shader warmup behind a temporary loading screen; same Auto convention.
@export_enum("Auto", "Always", "Disabled") var preload_mode: int = 0
var loading := false
var loading_layer: CanvasLayer

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/trial.json"))
	rules = Rules.new(config)
	automaton_cost = {"mana_cost": rules.skills.automaton.mana_cost, "cooldown_seconds": rules.skills.automaton.cooldown_seconds}
	items = Items.new()
	loot_rng.randomize()
	for slot in items.data.slots:
		equipment[slot] = null
	for id in rules.skills:
		if rules.skills[id].kind == "tool":
			tool_upkeep[id] = rules.skills[id].upkeep_per_second
		base_mana_costs[id] = rules.skills[id].mana_cost
	for id in items.data.pieces:
		pieces[id] = 0
	for id in config.potions:
		potion_stash[id] = 0
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
	loading = preload_mode == 1 or (preload_mode == 0 and get_tree().get_script() == null)
	reset_arena()
	if loading:
		_begin_loading()
	build = Build.new(self)
	character_window = BuildWindow.new()
	skill_window = BuildWindow.new()
	for window in [character_window, skill_window]:
		canvas.add_child(window)
	character_window.setup(self, "character")
	skill_window.setup(self, "skills")
	character_window.position = Vector2(24, 84)
	inventory_window = InventoryWindow.new()
	canvas.add_child(inventory_window)
	inventory_window.setup(self)
	skill_window.position = Vector2(get_viewport().get_visible_rect().size.x - 560, 84)
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
	# The hovered enemy is outlined on its own meshes; this empty marker only keeps the old handle
	# that review scripts hide before capturing.
	hover_ring = Node3D.new()
	world.add_child(hover_ring)
	move_marker = Shape.ring(world, Vector3.ZERO, 0.3, TEAL)
	hover_ring.visible = false
	move_marker.visible = false

func place_camera(focus: Vector3) -> void:
	# The angle never changes; the view only slides with the witch, kept a little below center.
	var screen_up = Vector3(-camera.basis.z.x, 0, -camera.basis.z.z).normalized()
	camera.position = focus + screen_up + camera.basis.z * 30

func _build_audio() -> void:
	sfx = preload("res://scripts/combat_sfx.gd").new()
	add_child(sfx)
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

func play_sfx(cue: String, fallback_pitch: float = 1.0, gain_db: float = 0.0) -> void:
	# Falls back to the old pitched impact when the named file is missing.
	if muted:
		return
	if sfx == null or not sfx.play(cue, gain_db):
		play_cue(fallback_pitch, gain_db)

func reset_arena() -> void:
	if is_instance_valid(inventory_window):
		inventory_window.set_salvage_mode(false)
	for child in world.get_children():
		if child.is_in_group("actor_corpses") or child.is_in_group("cast_assemblies"):
			child.free()
	# Loot left on the field goes with the run; the bag and worn items stay, like the build.
	for loot in ground_items:
		if is_instance_valid(loot.node):
			loot.node.free()
	ground_items.clear()
	deferred_ground_items.clear()
	hovered_loot = {}
	loot_layout.invalidate()
	loot_target = {}
	if held_item != null and stow(held_item):
		held_item = null
	automaton_assembly = null
	turret_assembly = null
	shotgun_assembly = null
	last_shotgun.clear()
	spring_plate = null
	for id in enemies:
		enemies[id].body.free()
	enemies.clear()
	for ally in allies:
		ally.node.free()
	allies.clear()
	for fx in effects:
		fx.node.free()
	effects.clear()
	for circle in cast_circles:
		circle.free()
	cast_circles.clear()
	charging_circle = null
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
	# No ground rings under the witch: the staff itself shows the active tool.
	# The folding shield prop replaced the old ring; the empty marker keeps the handle review scripts hide.
	shield_ring = Node3D.new()
	player.add_child(shield_ring)
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
	dash.clear()
	hold.clear()
	move_hold.clear()
	queued_input.clear()
	action_time = 0
	message_time = 0
	hit_time = 0
	stun_time = 0
	shield_time = 0
	if is_instance_valid(shield_visual):
		shield_visual.queue_free()
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
	elif not loading:
		start_field_entry()

func start_field_entry() -> void:
	if field_entry_mode == 1 or (field_entry_mode == 0 and get_tree().get_script() == null):
		var entry_facing := Vector3(camera.basis.z.x,0,camera.basis.z.z).normalized()
		player_visual.look_at(player.position+entry_facing)
		player_visual.begin_field_entry()

func _begin_loading() -> void:
	# Combat, input and the field entry wait until the warmup has finished behind the overlay.
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 100
	add_child(loading_layer)
	var warmup := AssetWarmup.new()
	world.add_child(warmup)
	var screen := LoadingScreen.new()
	screen.warmup = warmup
	loading_layer.add_child(screen)
	await get_tree().process_frame
	await warmup.run(camera)
	warmup.queue_free()
	loading_layer.queue_free()
	loading = false
	if player_visual.loaded_ok:
		start_field_entry()

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
	var pick = Shape.pick_volume(body, 0.7 * size, 1.65 * size, PICK_LAYER)
	pick.set_meta("enemy_id", id)
	var maximum: float = type.hp * rank.hp * enemy_level_factor("hp", enemy_level)
	enemies[id] = {"body": body, "model": model, "hp": maximum, "max_hp": maximum, "heavy": type.get("heavy", false), "kind": kind, "level": enemy_level,
		"grade": grade, "size": size, "cooldown": 1.0, "windup": 0.0, "attack": "", "charge_cooldown": 1.0, "charging": 0.0,
		"charge_dir": Vector3.ZERO, "charge_hit": false, "target": "", "retarget": 0.0, "slow": 0.0, "shred": 0.0, "bleeds": [], "flash": 0.0,
		"respawn": true, "timers": {}, "phases_done": [], "pattern_dir": Vector3.ZERO, "frames": [], "route": {}}
	dress_enemy(enemies[id], id == outlined_id)

func dress_enemy(enemy: Dictionary, outlined: bool, alive: bool = true) -> void:
	# One overlay chain per enemy mesh: a stencil mask of the body, then the grade aura
	# (champion/elite) and, while hovered, the selection outline, both drawn only outside that
	# mask. Render priority keeps every mask ahead of the passes that read it. Shared per combination.
	var graded: bool = AURA_COLORS.has(enemy.grade) and alive
	var key := "%s|%s" % [enemy.grade if graded else "", outlined and alive]
	if not enemy_overlays.has(key):
		var passes: Array[ShaderMaterial] = []
		if graded:
			var aura := ShaderMaterial.new()
			aura.shader = AURA_SHADER
			aura.render_priority = 1
			aura.set_shader_parameter("color", AURA_COLORS[enemy.grade])
			passes.append(aura)
		if outlined and alive:
			var outline := ShaderMaterial.new()
			outline.shader = OUTLINE_SHADER
			outline.render_priority = 2
			passes.append(outline)
		var overlay: ShaderMaterial = null
		if not passes.is_empty():
			overlay = ShaderMaterial.new()
			overlay.shader = MASK_SHADER
			var last := overlay
			for next in passes:
				last.next_pass = next
				last = next
		enemy_overlays[key] = overlay
	for mesh in enemy.model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = enemy_overlays[key]

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		loot_pointer = event.position
	# Observe releases before GUI controls, so Alt cannot stick after moving over a window.
	if event is InputEventKey and event.physical_keycode == KEY_ALT:
		if not event.echo:
			show_all_loot_labels = event.pressed and not loading
			if not show_all_loot_labels:
				# An expired label revealed by Alt must not keep itself alive through label hover.
				set_hovered_loot({})
				if is_instance_valid(player_visual):
					update_loot_hover(loot_pointer)
			if is_instance_valid(hud):
				hud.queue_redraw()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if loading:
		return
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
				if sfx != null:
					sfx.stop_all()
				return
			KEY_H:
				help_visible = not help_visible
				return
	if event is InputEventMouse:
		pointer = event.position
	if event is InputEventMouseButton and event.pressed and (held_item != null or held_piece != ""):
		# A click past the windows with something in the hand: the item drops at her feet, a
		# piece goes back to the pouch, and no attack comes out of it.
		held_piece = ""
		if event.button_index == MOUSE_BUTTON_LEFT:
			drop_held()
		refresh_build_windows()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed:
		if hold.get("button") == event.button_index:
			hold.clear()
		if move_hold.get("button") == event.button_index:
			move_hold.clear()
	if event is InputEventKey and not event.pressed and hold.get("key") == event.physical_keycode:
		hold.clear()
	if paused or hp <= 0 or player_visual.field_entry_active():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
		var index: int = [KEY_1, KEY_2, KEY_3, KEY_4].find(event.physical_keycode)
		if event.shift_pressed:
			cycle_potion(index)
		else:
			drink(index)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed and pointer_over_field():
		var loot := loot_at(event.position)
		if not loot.is_empty():
			cancel_pending_cast()
			move_hold.clear()
			pick_up(loot)
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
		if event.physical_keycode == KEY_F1:
			cancel_pending_cast()
			restart_probe("settings_changed")
			state = rules.bind(state, "lmb", "shotgun" if state.bindings.lmb == "basic_attack" else "basic_attack")
			return
		if event.physical_keycode == KEY_I:
			inventory_window.toggle()
			return
		if event.physical_keycode == KEY_G and event.ctrl_pressed:
			# Test tool: one of each name piece, 200 각인전 and 10 salvage material.
			for id in pieces:
				pieces[id] += 1
			coins += 200
			scrap += 10
			refresh_build_windows()
			show_message("시험용: 이름 조각 3종 · 각인전 200 · %s 10" % items.data.crafting.material_name)
			return
		if event.physical_keycode == KEY_G:
			# Test tool: drop an item at her feet (Shift: a unique) at the trial level.
			var rarity: String = "unique" if event.shift_pressed else items.weighted(loot_rng, {"normal": 1, "magic": 2, "rare": 2})
			drop_item(items.generate(loot_rng, build.level, rarity), player.position + Vector3(0.7, 0, 0.4))
			return
		if event.physical_keycode == KEY_C or event.physical_keycode == KEY_S:
			# Trial character / skill tree windows; combat keeps running while they are open.
			(character_window if event.physical_keycode == KEY_C else skill_window).toggle()
			return
		if event.physical_keycode == KEY_F9 and event.ctrl_pressed:
			# Ctrl+F9: which bleed growth (A rate / B upkeep) the chainsaw level drives.
			restart_probe("settings_changed")
			var growths: Array = config.bleed.growth_steps
			config.bleed.growth = growths[(growths.find(config.bleed.growth) + 1) % growths.size()]
			var plan: Dictionary = bleed_plan(0)
			show_message("전기톱 Lv %d · 출혈 성장 %s안 · %.1f초 · 일반 %d%%" % [config.chainsaw_level, config.bleed.growth, plan.seconds, roundi(100 * plan.ratio * float(config.bleed.ratio.normal))])
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
		loot_target = {}
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
		show_all_loot_labels = false
		set_hovered_loot({})
		if is_instance_valid(hud):
			hud.queue_redraw()
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
	if route.index >= points.size() - 1 and Vector2(goal.x - next.x, goal.z - next.z).length() < 0.6:
		# The plan's last point lags a goal that has since moved a little (a held cursor drags it
		# along every frame). Walking back to that point shuttles in place, so aim at the goal.
		next = goal
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

func bind_slot(slot: String, skill_id: String) -> void:
	# The skill tree window's loadout: any skill on RMB/Q/W/E/R, kept across restarts.
	cancel_pending_cast()
	split_build_log()
	config.bindings[slot] = skill_id
	state = rules.bind(state, slot, skill_id)
	# A running tool that no slot holds any more could never be switched off; release it.
	if state.active_tool != null and not state.bindings.values().has(state.active_tool):
		state.active_tool = null

func split_build_log() -> void:
	# Called before a C/S window change: the running A5 segment is saved with the build it was
	# actually played with. A few seconds of clicking through the windows is not a measurement,
	# so such short segments are dropped instead of saved.
	if probe.combat_seconds >= float(config.build.log_min_seconds):
		restart_probe("build_changed")
	else:
		probe = ManaProbe.new()
		logged_seconds = -1.0

func gear_total(key: String) -> float:
	return float(gear.get(key, 0.0))

func refresh_gear() -> void:
	# Worn items feed the build, which writes the scores and maximums combat reads.
	var worn: Array = equipment.values().filter(func(item): return item != null)
	gear = items.totals(worn)
	build.apply()
	refresh_build_windows()

func bag_grid() -> Vector2i:
	return Vector2i(int(items.data.bag_grid[0]), int(items.data.bag_grid[1]))

func bag_index(item: Dictionary) -> int:
	for i in bag.size():
		if is_same(bag[i], item):
			return i
	return -1

func bag_under(cells: Rect2i, ignore = null) -> Array:
	# Bag items covering any of these cells.
	return bag.filter(func(other): return not is_same(other, ignore) and other.has("at") and Rect2i(other.at, items.size_of(other)).intersects(cells))

func bag_spot(item: Dictionary):
	# The first free top-left cell, column by column, or null when the item does not fit.
	var size: Vector2i = items.size_of(item)
	var grid := bag_grid()
	for x in grid.x - size.x + 1:
		for y in grid.y - size.y + 1:
			if bag_under(Rect2i(Vector2i(x, y), size), item).is_empty():
				return Vector2i(x, y)
	return null

func arrange_bag() -> void:
	# Items appended without a cell take the first free one; those that cannot fit keep none.
	for item in bag:
		if not item.has("at"):
			var spot = bag_spot(item)
			if spot != null:
				item.at = spot

func stow(item: Dictionary) -> bool:
	arrange_bag()
	var spot = bag_spot(item)
	if spot == null:
		return false
	item.at = spot
	bag.append(item)
	return true

func equip(index: int) -> void:
	# Wears a bag item; what was worn takes its cells (same slot, same size).
	var item: Dictionary = bag[index]
	split_build_log()
	bag.remove_at(index)
	var old = equipment[item.slot]
	equipment[item.slot] = item
	if old != null:
		if item.has("at"):
			old.at = item.at
			bag.append(old)
		elif not stow(old):
			drop_item(old, player.position)
	item.erase("at")
	refresh_gear()

func unequip(slot: String) -> bool:
	if equipment[slot] == null:
		return false
	var item: Dictionary = equipment[slot]
	if bag_spot(item) == null:
		show_message("가방에 자리가 없습니다")
		return false
	split_build_log()
	equipment[slot] = null
	stow(item)
	refresh_gear()
	return true

func discard(index: int) -> void:
	bag.remove_at(index)
	refresh_build_windows()

# The inventory window's hand: one item or one kind of name piece rides the cursor at a time.
func take_from_bag(item: Dictionary) -> void:
	if held_item != null:
		return
	bag.remove_at(bag_index(item))
	item.erase("at")
	held_item = item
	refresh_build_windows()

func put_in_bag(at: Vector2i) -> bool:
	# The held item goes down at a cell; a single item under it swaps onto the cursor.
	if held_item == null:
		return false
	var cells := Rect2i(at, items.size_of(held_item))
	if not Rect2i(Vector2i.ZERO, bag_grid()).encloses(cells):
		return false
	var under: Array = bag_under(cells)
	if under.size() > 1:
		return false
	var item: Dictionary = held_item
	held_item = null
	if under.size() == 1:
		take_from_bag(under[0])
	item.at = at
	bag.append(item)
	refresh_build_windows()
	return true

func wear_held() -> bool:
	# The held item goes on; whatever was worn there comes onto the cursor.
	if held_item == null:
		return false
	split_build_log()
	var item: Dictionary = held_item
	held_item = equipment[item.slot]
	equipment[item.slot] = item
	refresh_gear()
	return true

func take_worn(slot: String) -> bool:
	if equipment[slot] == null or held_item != null:
		return false
	split_build_log()
	held_item = equipment[slot]
	equipment[slot] = null
	refresh_gear()
	return true

func drop_held() -> void:
	# Out of the hand onto the ground at her feet, where it can be picked up again.
	if held_item == null:
		return
	var item: Dictionary = held_item
	held_item = null
	drop_item(item, player.position + Vector3(0.9, 0, 0.5))
	refresh_build_windows()

func salvage_held() -> void:
	if held_item == null:
		return
	salvage_item(held_item)
	held_item = null
	refresh_build_windows()

func return_held() -> void:
	# Closing the window puts the hand back in the bag, or on the ground when it is full.
	held_piece = ""
	if held_item == null:
		return
	if stow(held_item):
		held_item = null
		refresh_build_windows()
	else:
		drop_held()

func equipment_summary() -> Dictionary:
	var summary := {}
	for slot in equipment:
		if equipment[slot] != null:
			var worn: Dictionary = equipment[slot]
			var word = items.true_name(worn)
			summary[slot] = {"name": worn.name, "rarity": worn.rarity, "options": worn.options, "sockets": worn.get("sockets", 0),
				"pieces": worn.get("pieces", []), "true_name": word.id if word != null else ""}
	return summary

func is_worn(item: Dictionary) -> bool:
	return equipment.values().any(func(worn): return is_same(worn, item))

func socket_into(item: Dictionary, piece: String) -> bool:
	# Into the next free socket of a worn or bag item; a full matching row wakes its true name.
	if pieces.get(piece, 0) <= 0 or item.get("pieces", []).size() >= int(item.get("sockets", 0)):
		return false
	var worn := is_worn(item)
	if worn:
		split_build_log()
	pieces[piece] -= 1
	item.pieces.append(piece)
	# One piece per click, like a rune: the hand is empty again afterwards.
	held_piece = ""
	if worn:
		refresh_gear()
	else:
		refresh_build_windows()
	return true

func socket_piece(slot: String, piece: String) -> bool:
	return equipment[slot] != null and socket_into(equipment[slot], piece)

func unsocket(slot: String) -> bool:
	# Paid removal (04 §6): the last piece comes back intact for 각인전.
	var item = equipment[slot]
	var cost: int = int(items.data.crafting.unsocket_coins)
	if item == null or item.pieces.is_empty() or coins < cost:
		return false
	split_build_log()
	coins -= cost
	pieces[item.pieces.pop_back()] += 1
	refresh_gear()
	return true

func salvage_item(item: Dictionary) -> void:
	# Breaking an item down yields salvage material by rarity (04 §7); its pieces come back.
	scrap += int(items.data.crafting.salvage[item.rarity])
	for piece in item.get("pieces", []):
		pieces[piece] += 1

func salvage(index: int) -> void:
	salvage_item(bag[index])
	bag.remove_at(index)
	refresh_build_windows()

func salvage_below_rare() -> int:
	# Only bag equipment is eligible; worn/held items and resource stores are untouched.
	var count := 0
	for index in range(bag.size() - 1, -1, -1):
		if bag[index].rarity in ["normal", "magic"]:
			salvage_item(bag[index])
			bag.remove_at(index)
			count += 1
	show_message("일반·마법 장비 %d개 분해" % count if count > 0 else "분해할 일반·마법 장비가 없습니다")
	refresh_build_windows()
	return count

func reroll(slot: String, affix: int) -> bool:
	# One option of a worn item re-rolls for 각인전 and material (04 §7 trial costs).
	var item = equipment[slot]
	var craft: Dictionary = items.data.crafting
	if item == null or affix >= item.affixes.size() or coins < int(craft.reroll_coins) or scrap < int(craft.reroll_material):
		return false
	split_build_log()
	coins -= int(craft.reroll_coins)
	scrap -= int(craft.reroll_material)
	items.reroll_affix(loot_rng, item, affix)
	refresh_gear()
	return true

func drop_spoils(grade: String, at: Vector3) -> void:
	# Keep the existing roll order and quantities; ownership changes only on pickup.
	var drop: Dictionary = items.data.currency.drops.get(grade, items.data.currency.drops.normal)
	if loot_rng.randf() < float(drop.chance):
		drop_resource("currency", "", loot_rng.randi_range(int(drop.range[0]), int(drop.range[1])), at)
	var potions: Dictionary = items.data.potion_drops
	if loot_rng.randf() < float(potions.chance.get(grade, 0.0)):
		var potion: String = items.weighted(loot_rng, potions.weights)
		drop_resource("potion", potion, 1, at)
	if loot_rng.randf() < float(items.data.piece_drops.get(grade, 0.0)):
		var id: String = items.data.pieces.keys()[loot_rng.randi_range(0, items.data.pieces.size() - 1)]
		drop_resource("piece", id, 1, at)

func drop_loot(grade: String, at: Vector3) -> void:
	# Item level is the trial character level, +1 for elites and +2 for bosses (04 §4.3).
	var level: int = build.level + int(items.data.grade_level_bonus.get(grade, 0))
	for item in items.roll_drops(loot_rng, grade, level):
		drop_item(item, at + Vector3(loot_rng.randf_range(-0.5, 0.5), 0, loot_rng.randf_range(-0.5, 0.5)))

func drop_item(item: Dictionary, at: Vector3) -> void:
	drop_ground_loot({"kind": "equipment", "item": item, "name": item.name, "color": Color(items.data.rarity_colors[item.rarity])}, at)

func drop_resource(kind: String, id: String, amount: int, at: Vector3) -> void:
	var title: String
	var color: Color
	match kind:
		"currency":
			title = "%d %s" % [amount, items.data.currency.name]
			color = GOLD_FLASH
		"piece":
			title = items.data.pieces[id].name
			color = Color("c9a0dc")
		"potion":
			title = config.potions[id].name
			color = Hud.POTION_COLORS[config.potions[id].kind]
		_:
			return
	if amount <= 0:
		return
	if kind != "currency" and amount > 1:
		title += " × %d" % amount
	drop_ground_loot({"kind": kind, "id": id, "amount": amount, "name": title, "color": color}, at)

func drop_ground_loot(payload: Dictionary, at: Vector3) -> void:
	var spot = GroundLoot.find_position(map, at, ground_items)
	if spot == null:
		deferred_ground_items.append({"loot": payload, "at": at})
		return
	var color: Color = payload.color
	# The pickup destination stays on the floor while only the visible mesh falls and spins.
	var node := Node3D.new()
	world.add_child(node)
	var rest_height := 0.05
	var visual: MeshInstance3D
	match payload.kind:
		"currency":
			rest_height = 0.03
			visual = Shape.cylinder(node, Vector3.ZERO, 0.16, 0.04, color)
		"piece":
			rest_height = 0.04
			visual = Shape.box(node, Vector3.ZERO, Vector3(0.2, 0.06, 0.28), color)
		"potion":
			rest_height = 0.14
			visual = Shape.cylinder(node, Vector3.ZERO, 0.12, 0.24, color, 0.075)
			Shape.cylinder(visual, Vector3(0, 0.14, 0), 0.06, 0.04, BRASS)
		_:
			visual = Shape.cylinder(node, Vector3.ZERO, 0.17, 0.08, color)
	node.position = spot + Vector3(0, rest_height, 0)
	GroundLoot.pose_drop(visual, 0.0)
	var selection := Shape.ring(node, Vector3(0, 0.06 - rest_height, 0), 0.27, Color("fff1c4"), 0.025)
	selection.visible = false
	ground_items.append(payload.merged({"node": node, "visual": visual, "selection": selection, "age": 0.0}))
	loot_layout.invalidate()

func tick_ground_loot(dt: float) -> void:
	if paused:
		return
	var moved := false
	for loot in ground_items:
		var before: float = loot.age
		loot.age = minf(GroundLoot.LABEL_SECONDS, before + dt)
		if before < GroundLoot.DROP_SECONDS:
			GroundLoot.pose_drop(loot.visual, loot.age)
			moved = true
	if moved:
		loot_layout.invalidate()

func loot_labels() -> Array:
	var shown: Array = []
	for loot in ground_items:
		if show_all_loot_labels or loot.age < GroundLoot.LABEL_SECONDS or is_same(loot, hovered_loot):
			shown.append(loot.node.get_instance_id())
	var focused: int = 0 if hovered_loot.is_empty() else hovered_loot.node.get_instance_id()
	return loot_layout.labels(ground_items, camera, hud.font, get_viewport().get_visible_rect().size, shown, focused)

func loot_pointer_available(screen: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size - Vector2(0, 155)).has_point(screen):
		return false
	for window in [inventory_window, character_window, skill_window]:
		if is_instance_valid(window) and window.is_visible_in_tree() and window.get_global_rect().has_point(screen):
			return false
	return true

func loot_at(screen: Vector2) -> Dictionary:
	return GroundLoot.pick(screen, loot_labels(), ground_items, camera) if loot_pointer_available(screen) else {}

func update_loot_hover(screen: Vector2) -> void:
	loot_pointer = screen
	var next: Dictionary = {}
	if not loading and not paused and hp > 0 and not player_visual.field_entry_active() and held_item == null and held_piece == "":
		next = loot_at(screen)
	set_hovered_loot(next)

func set_hovered_loot(next: Dictionary) -> void:
	if is_same(next, hovered_loot):
		return
	for loot in [hovered_loot, next]:
		if loot.is_empty() or not is_instance_valid(loot.node):
			continue
		var active := is_same(loot, next)
		var color: Color = loot.color
		var material: StandardMaterial3D = loot.visual.material_override
		material.albedo_color = color.lerp(Color.WHITE, 0.45) if active else color
		material.emission_enabled = active
		material.emission = color
		material.emission_energy_multiplier = 0.9
		loot.selection.visible = active
	hovered_loot = next

func pick_up(loot: Dictionary) -> void:
	# A click on loot walks her over to it; walking past loot never picks it up.
	loot_target = loot
	tick_pickup()
	if not loot_target.is_empty():
		set_destination(loot.node.position)

func tick_pickup() -> void:
	if loot_target.is_empty():
		return
	var loot: Dictionary = loot_target
	var index: int = -1
	for i in ground_items.size():
		if is_same(ground_items[i], loot):
			index = i
	if index < 0:
		loot_target = {}
		return
	var flat: Vector3 = loot.node.position - player.position
	flat.y = 0.0
	if flat.length() > float(items.data.pickup_radius):
		return
	loot_target = {}
	moving = false
	move_marker.visible = false
	match loot.kind:
		"equipment":
			if not stow(loot.item):
				show_message("가방에 자리가 없습니다")
				return
		"currency":
			coins += int(loot.amount)
		"piece":
			pieces[loot.id] += int(loot.amount)
		"potion":
			potion_stash[loot.id] += int(loot.amount)
	loot.node.queue_free()
	ground_items.remove_at(index)
	if is_same(hovered_loot, loot):
		hovered_loot = {}
	loot_layout.invalidate()
	var waiting := deferred_ground_items.duplicate()
	deferred_ground_items.clear()
	for entry in waiting:
		drop_ground_loot(entry.loot, entry.at)
	show_message(items.display_name(loot.item) if loot.kind == "equipment" else loot.name + " 획득")
	refresh_build_windows()

func sync_tool_upkeep() -> void:
	# Upkeep options and the power part trim every tool's drain, never below a tenth.
	var cut: float = minf(0.9, gear_total("upkeep_pct") / 100.0)
	for id in tool_upkeep:
		rules.skills[id].upkeep_per_second = float(tool_upkeep[id]) * (1.0 - cut)

func skill_level_factor(source: String) -> float:
	# Skills whose level raises their damage (the shotgun, for its blueprint) scale here.
	var per_level: float = float(items.data.skill_level_damage.get(source, 0.0))
	return 1.0 + per_level * (float(config.get(source + "_level", 1)) - 1.0) if per_level > 0 else 1.0

func slow_factor() -> float:
	# Slow strength options deepen the cut to an enemy's speed (0.45 of normal at base).
	return clampf(1.0 - (1.0 - config.slow_speed_factor) * (1.0 + gear_total("slow_pct") / 100.0), 0.1, 1.0)

func refresh_build_windows() -> void:
	if is_instance_valid(inventory_window):
		inventory_window.refresh()
	for window in [character_window, skill_window]:
		if is_instance_valid(window):
			window.refresh()

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
			"automaton_node": config.automaton_node, "passive_levels": config.passive_levels.duplicate(), "build": build.snapshot(),
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
	# A node may override the skill's own cost: no node is the cheap one to summon in numbers,
	# A comes back quickly enough to throw as the main bomb, B pays the full price.
	var node: Dictionary = config.automaton_nodes[config.automaton_node]
	rules.skills.automaton.cooldown_seconds = float(node.get("cooldown_seconds", automaton_cost.cooldown_seconds))
	# Mana cost cuts (the 「샤」 piece on accessories, 「록샤」) trim every skill, at most by half.
	var cut: float = clampf(gear_total("mana_cost_pct") / 100.0, 0.0, 0.5)
	for id in base_mana_costs:
		var cost: float = float(node.get("mana_cost", automaton_cost.mana_cost)) if id == "automaton" else float(base_mana_costs[id])
		rules.skills[id].mana_cost = cost * (1.0 - cut)

func request_slot(slot: String, cursor: Dictionary, shift: bool = false) -> void:
	sync_automaton_cost()
	if paused or hp <= 0 or field_cleared() or player_visual.field_entry_active():
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
	if SKILL_TREES.has(cast.skill):
		windup.circle_total = windup.release
		charging_circle = spawn_cast_circle(SKILL_TREES[cast.skill], false)
	if cast.skill == "automaton":
		windup.visual_duration = windup.release
		automaton_assembly = AutomatonAssembly.new()
		automaton_assembly.configure(str(config.automaton_node))
		world.add_child(automaton_assembly)
		automaton_assembly.position = map.grounded(automaton_spawn_position(free_follow_slot()))
		automaton_assembly.initialize(self)
	elif cast.skill == "turret":
		windup.visual_duration = windup.release
		turret_assembly = TurretAssembly.new()
		world.add_child(turret_assembly)
		turret_assembly.position = map.grounded(point(snapshot.ground))
		turret_assembly.initialize(self)
	elif cast.skill == "shotgun":
		windup.visual_duration = windup.release
		begin_shotgun_visual(cast_target(cast), aims_at_enemy(cast))
	elif cast.skill == "spring_dash":
		windup.visual_duration = windup.release
		begin_spring_plate(cast_direction(cast))
	player_model.look_at(player.position + cast_direction(cast))
	player_visual.begin_motion("attack" if cast.skill == rules.basic_id else ("spring_jump" if cast.skill == "spring_dash" else "cast"), seconds, float(skill.get("release_ratio", 1.0)))
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
		shotgun_assembly.global_transform = ShotgunGeometry.frame(self,cast_target(aim),aims_at_enemy(aim))
		shotgun_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(spring_plate):
		spring_plate.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
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

func automaton_spawn_position(slot: int = 0) -> Vector3:
	# Casting and idle following share these anchors to avoid a step on release. Each automaton
	# keeps its own place beside the witch (slot 0 is the original anchor); casts ask for a free one.
	var pos: Vector3 = player.position + FOLLOW_SLOTS[slot % FOLLOW_SLOTS.size()]
	pos.x = clampf(pos.x, map.bounds.position.x + 0.25, map.bounds.end.x - 0.25)
	pos.z = clampf(pos.z, map.bounds.position.y + 0.25, map.bounds.end.y - 0.25)
	return map.snap(pos) if not map.walkable(pos) else pos

func free_follow_slot() -> int:
	var taken: Array = allies.filter(func(other): return other.mobile).map(func(other): return other.slot)
	for slot in FOLLOW_SLOTS.size():
		if slot not in taken:
			return slot
	return taken.size() % FOLLOW_SLOTS.size()

func face_travel(ally: Dictionary, before: Vector3, dt: float) -> void:
	# A following automaton turns towards where it walks; pursuit aims at its target instead.
	var travel: Vector3 = ally.node.position - before
	travel.y = 0.0
	if travel.length() < 0.001:
		return
	var yaw := atan2(-travel.x, -travel.z)
	ally.node.rotation = Vector3(0, lerp_angle(ally.node.rotation.y, yaw, minf(1.0, dt * 12.0)), 0)

func separate_allies(dt: float) -> void:
	# Automatons ease apart instead of standing inside each other or a turret; turrets stay put.
	for i in allies.size():
		for j in range(i + 1, allies.size()):
			var a: Dictionary = allies[i]
			var b: Dictionary = allies[j]
			if not a.mobile and not b.mobile:
				continue
			var gap := Vector3(b.node.position.x - a.node.position.x, 0, b.node.position.z - a.node.position.z)
			var overlap: float = ALLY_SPACING - gap.length()
			if overlap <= 0.0:
				continue
			var away: Vector3 = gap.normalized() if gap.length() > 0.001 else Vector3.RIGHT.rotated(Vector3.UP, j * 2.4)
			var share := 0.5 if a.mobile and b.mobile else 1.0
			var push: Vector3 = away * minf(overlap * share, dt * 2.0)
			if a.mobile and map.walkable(a.node.position - push):
				a.node.position -= push
			if b.mobile and map.walkable(b.node.position + push):
				b.node.position += push

func cancel_summon_assemblies(reason: String) -> void:
	if is_instance_valid(player_visual):player_visual.cancel_spring_preparation()
	if is_instance_valid(automaton_assembly):
		automaton_assembly.cancel(reason)
	automaton_assembly = null
	if is_instance_valid(turret_assembly):
		turret_assembly.cancel(reason)
	turret_assembly = null
	if is_instance_valid(shotgun_assembly):
		shotgun_assembly.cancel(reason)
	shotgun_assembly = null
	if is_instance_valid(spring_plate):
		spring_plate.cancel(reason)
	spring_plate = null

func begin_spring_plate(direction: Vector3) -> void:
	spring_plate = SpringPlate.new()
	world.add_child(spring_plate)
	spring_plate.position = map.grounded(player.position - direction * 0.16)
	spring_plate.look_at(spring_plate.global_position + direction, Vector3.UP)
	spring_plate.initialize(self)

func begin_shotgun_visual(target: Vector3, at_enemy: bool = false) -> void:
	shotgun_assembly=ShotgunCast.new()
	world.add_child(shotgun_assembly)
	shotgun_assembly.initialize(self)
	shotgun_assembly.global_transform=ShotgunGeometry.frame(self,target,at_enemy)

func knock_back(id: String) -> void:
	# Shotgun Lv5+ (the firearm tree is safest at range): a hit shoves the enemy straight away
	# from her. Heavy enemies go half as far, bosses and charging brutes not at all.
	var skill: Dictionary = rules.skills.shotgun
	if not enemies.has(id) or config.shotgun_level < float(skill.knockback_level):
		return
	var enemy: Dictionary = enemies[id]
	if config.enemy_types[enemy.kind].has("boss") or enemy.get("charging", 0.0) > 0:
		return
	var away: Vector3 = enemy.body.position - player.position
	away.y = 0.0
	if away.length() < 0.01:
		away = -player_model.global_basis.z
	var distance: float = float(skill.knockback_distance) * (0.5 if enemy.heavy else 1.0)
	enemy.knockback_dir = away.normalized()
	enemy.knockback_left = distance
	enemy.knockback_speed = distance / float(skill.knockback_seconds)

func fire_shotgun(target: Vector3, at_enemy: bool = false) -> void:
	var shot: Transform3D=ShotgunGeometry.frame(self,target,at_enemy)
	if not is_instance_valid(shotgun_assembly): begin_shotgun_visual(target,at_enemy)
	shotgun_assembly.fire(shot)
	shotgun_assembly=null
	var struck: Array[String]=[]
	for id in enemies.keys():
		if ShotgunGeometry.contains(self,shot,enemies[id].body):
			struck.append(id)
			if strike(id,config.shot_damage,false,"witch","shotgun") != "miss":
				knock_back(id)
	var endpoints: Array[Vector3]=ShotgunGeometry.traces(self,shot)
	# Unblocked traces end on the 8m circle around the witch; shorter ones hit a wall or floor.
	var blocked: Array[bool]=[]
	for end in endpoints:
		var flat: Vector3=end-player.position; flat.y=0.0
		blocked.append(flat.length()<float(rules.skills.shotgun.range)-0.05)
	spawn_vfx().muzzle(shot.origin,endpoints,blocked,map.ground_y(shot.origin))
	last_shotgun={"frame":shot,"origin":shot.origin,"direction":-shot.basis.z,"ends":endpoints,"struck":struck}
	play_sfx("shotgun_fire", 0.65)

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

func walk_to_destination(dt: float) -> void:
	var delta: Vector3 = destination - player.position
	# Feet always follow the floor, so arrival is about where she stands, not how high.
	delta.y = 0.0
	if delta.length() < (0.01 if not pending_cast.is_empty() else 0.15):
		moving = false
		move_marker.visible = false
	else:
		var speed: float = config.player_speed * (1.0 + (config.potions.speed.speed_bonus if speed_buff > 0 else 0.0)) * (1.0 + gear_total("move_speed") / 100.0)
		var step: Vector3 = follow(player_route, player.position, destination, 0.5, dt) - player.position
		step.y = 0
		if step.length() < 0.001:
			step = delta
		var before: Vector3 = player.position
		player.velocity = step.normalized() * minf(speed, step.length() / dt)
		player.move_and_slide()
		player_model.look_at(player.position + step.normalized())
		var made := Vector2(player.position.x - before.x, player.position.z - before.z).length()
		if pending_cast.is_empty() and delta.length() < 0.6 and made < 0.1 * minf(speed * dt, delta.length()):
			# Stop at an obstructing step or prop edge instead of pushing into it indefinitely.
			moving = false
			move_marker.visible = false

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
			"tool_changed":
				play_sfx("tool_change", 1.65)
				flash_tool_change(event.tool)
			"tool_released": flash_tool_change(null)

func flash_tool_change(tool) -> void:
	# The staff head marks a tool change in that tool's colour (teal back to the bare staff).
	var head: Vector3 = player.position + Vector3.UP * 1.1
	if player_visual.loaded_ok and is_instance_valid(player_visual.staff_root):
		head = player_visual.staff_root.to_global(Vector3(0, 0.9, 0))
	var color: Color = TOOL_COLORS.get(tool, Color(0.45, 1.0, 0.85)) if tool != null else Color(0.45, 1.0, 0.85)
	spawn_vfx().tool_shift(head, color.lightened(0.15), map.ground_y(player.position), tool != null)

func spawn_cast_circle(tree: String, instant: bool) -> Node3D:
	var circle = CastCircle.new()
	world.add_child(circle)
	circle.setup(tree, instant)
	circle.global_position = map.grounded(player.position) + Vector3.UP * 0.03
	cast_circles.append(circle)
	return circle

func tick_cast_circles(dt: float) -> void:
	var feet: Vector3 = map.grounded(player.position)
	for circle in cast_circles.duplicate():
		var charge := 1.0
		var still: bool = circle == charging_circle and not windup.is_empty()
		if still:
			charge = 1.0 - float(windup.release) / maxf(0.0001, float(windup.get("circle_total", 1.0)))
		if not circle.sync(dt, feet, still, charge):
			cast_circles.erase(circle)
			circle.queue_free()

func aims_at_enemy(event: Dictionary) -> bool:
	return event.get("target_enemy") != null and enemies.has(event.target_enemy)

func cast_target(event: Dictionary) -> Vector3:
	if aims_at_enemy(event):
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

func start_dash(target: Vector3, direction: Vector3, at_enemy: bool) -> void:
	# Spring dash (03 drive II): a short burst toward the cursor that hits cannot stagger.
	# It stops short of an enemy it was aimed at and never runs off walkable floor.
	var skill: Dictionary = rules.skills.spring_dash
	var flat: Vector3 = target - player.position
	flat.y = 0.0
	var reach: float = clampf(flat.length() - (float(skill.stop_short) if at_enemy else 0.0), float(skill.min_distance), float(skill.range))
	var length := 0.0
	while length + 0.2 <= reach and map.walkable(player.position + direction * (length + 0.2)):
		length += 0.2
	moving = false
	move_marker.visible = false
	dash = {"direction": direction, "left": length, "speed": length / float(skill.dash_seconds), "visual_distance":length}
	player_visual.launch_spring_jump(float(skill.dash_seconds))
	if not is_instance_valid(spring_plate):begin_spring_plate(direction)
	spring_plate.launch(direction)
	spring_plate = null

func tick_dash(dt: float) -> void:
	var travel: float = minf(dash.speed * dt, dash.left)
	var before: Vector3 = player.position
	player.velocity = dash.direction * travel / dt
	player.move_and_slide()
	var made := Vector2(player.position.x - before.x, player.position.z - before.z).length()
	dash.left -= travel
	player_visual.update_spring_jump(1.0 - float(dash.left) / maxf(float(dash.visual_distance), 0.0001))
	# Done, or pinned against a wall the floor check could not see.
	if dash.left <= 0.001 or made < travel * 0.3:
		player_visual.land_spring_jump()
		dash.clear()
		player.velocity = Vector3.ZERO

func execute_cast(event: Dictionary) -> void:
	if SKILL_TREES.has(event.skill):
		if is_instance_valid(charging_circle) and charging_circle.charging:
			charging_circle.flare()
		else:
			spawn_cast_circle(SKILL_TREES[event.skill], true)
	charging_circle = null
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
			# Every swing whooshes; a miss adds no hit sound, no flash, no debuff.
			play_sfx("staff_swing", 1.0)
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
					play_sfx("chainsaw_cut", 1.05)
			elif best != "" and tool != null:
				var debuff: String = rules.skills[tool].debuff
				var before: float = enemies[best][debuff]
				# Debuffs of different tools coexist; switching tools never clears them.
				enemies[best][debuff] = float(rules.skills[tool].debuff_seconds)
				if strike(best, damage, true, "witch", tool) == "miss":
					enemies[best][debuff] = before
				else:
					play_sfx({"bolt_cutter": "bolt_cutter_cut", "grinder": "grinder_hit"}[tool], {"bolt_cutter": 0.8, "grinder": 1.55}[tool])
					if tool == "bolt_cutter" and gear_total("rule:chain_cut") > 0:
						chain_cut(best, damage)
			elif best != "" and strike(best, damage, true, "witch", "staff") != "miss":
				play_sfx("staff_hit", 1.2)
		"shotgun":
			fire_shotgun(target, aims_at_enemy(event))
		"spring_dash":
			start_dash(target, direction, aims_at_enemy(event))
		"bolt_cutter", "grinder", "chainsaw": pass  # the staff itself transforms; no ground ring
		"shield":
			shield_time = shield_duration()
			# Recasting while the fan is up only refreshes the clock; otherwise a new one assembles.
			if not is_instance_valid(shield_visual) or shield_visual.mode not in ["assembling", "open"]:
				shield_visual = ShieldVisual.new()
				world.add_child(shield_visual)
				shield_visual.initialize(self, player.position, player_model.global_rotation.y)
		"automaton":
			var pos := automaton_spawn_position(free_follow_slot())
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
	return "%s %s Lv %d" % [config.grades[enemy.grade].name, config.enemy_types[enemy.kind].name, enemy.level]

func enemy_level_factor(kind: String, level: int) -> float:
	return 1.0 + float(config.build["enemy_%s_per_level" % kind]) * (level - 1)

func set_enemy_level(value: int) -> void:
	# Living enemies keep their HP fraction; bleed, phases and stun read max HP, so they follow.
	enemy_level = clampi(value, 1, int(config.build.max_level))
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		var ratio: float = enemy_level_factor("hp", enemy_level) / enemy_level_factor("hp", enemy.level)
		enemy.hp *= ratio
		enemy.max_hp *= ratio
		enemy.level = enemy_level

func step_enemy_level(delta: int) -> bool:
	if enemy_level + delta < 1 or enemy_level + delta > int(config.build.max_level):
		return false
	split_build_log()
	set_enemy_level(enemy_level + delta)
	enemy_level_linked = enemy_level == build.level
	return true

func link_enemy_level() -> void:
	split_build_log()
	enemy_level_linked = true
	set_enemy_level(build.level)

func summon_growth(kind: String, roller: String) -> float:
	# Summons grow with their own skill level (blueprints included), not with the witch's power
	# or damage gear (07 §2.1), so a level 30 build's summons can stand against level 30 enemies.
	return 1.0 + float(config["summon_%s_per_level" % kind]) * (float(config[roller + "_level"]) - 1.0)

func summon_level(roller: String) -> int:
	return int(config[roller + "_level"])

func hit_chance(id: String, roller: String = "witch") -> float:
	# Trial accuracy against the target's grade evasion. The witch's comes from dexterity;
	# a summon's comes from the level of the skill that built it, never from her stats (07 §2.1).
	var chance: float = (config.hit_base + config.hit_per_dexterity * config.dexterity) * (1.0 + gear_total("hit_pct") / 100.0)
	if roller != "witch":
		chance = config.summon_hit_base + config.summon_hit_per_level * (summon_level(roller) - 1)
	return clampf(chance - config.grades[enemies[id].grade].evasion, config.hit_min, config.hit_cap)

func crit_chance(roller: String = "witch") -> float:
	if roller != "witch":
		return minf(config.crit_cap, config.summon_crit_base + config.summon_crit_per_level * (summon_level(roller) - 1))
	return minf(config.crit_cap, config.crit_base + config.crit_per_dexterity * config.dexterity + gear_total("crit_pct") / 100.0)

func strike(id: String, amount: float, accuracy_roll: bool, roller: String, source: String, look: String = "") -> String:
	# roller is "witch" or the summon skill ("automaton", "turret") whose level drives the rolls.
	# One direct damage event: optional hit roll, then its own crit roll (area attacks call this per enemy).
	if not enemies.has(id):
		return "miss"
	amount *= passive_factor(source + ("_" + look if look != "" else ""))
	if roller == "witch":
		amount *= build.power_factor() * (1.0 + gear_total("damage_pct") / 100.0) * skill_level_factor(source)
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
		play_sfx("crit_hit", 0.55)
		shake_time = 0.12
	return "crit" if crit else "hit"

func passive_factor(attack: String) -> float:
	# Passives follow the machine principle an attack uses (03 §2.1), not the tree it belongs to:
	# cutting precision also sharpens the B automaton's saw, ballistics also the turret's shots.
	# Untagged hits (staff, punches, blasts) and bleed ticks never gain from them.
	var tag: String = config.attack_tags.get(attack, "")
	var factor := 1.0
	for id in config.passives:
		if tag != "" and config.passives[id].get("tag", "") == tag:
			factor += float(config.passives[id].damage_per_level) * float(config.passive_levels[id])
	# Parts add to their principle the same way (04 §3.3).
	if tag != "":
		factor += gear_total("tag:" + tag) / 100.0
	return factor

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
		# No ground ring on death: the collapse itself shows it. The falling corpse keeps neither
		# the selection outline nor the grade aura.
		dress_enemy(enemy, false, false)
		if enemy.model.has_method("detach_for_death"):
			enemy.model.detach_for_death(world, self)
		enemy.body.queue_free()
		enemies.erase(id)
		kills += 1
		drop_loot(enemy.grade, enemy.body.position)
		drop_spoils(enemy.grade, enemy.body.position)
		# 「록」 in the medium: each kill mends a little.
		if hp > 0 and gear_total("life_on_kill") > 0:
			hp = minf(config.max_hp, hp + gear_total("life_on_kill"))
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
	# Bleed duration options stretch it at the same rate per second (04 §4.3: duration, never share).
	seconds *= 1.0 + gear_total("bleed_pct") / 100.0
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
	var step: float = float(config.bleed.tick_seconds)
	var ticks: int = maxi(1, ceili(plan.seconds / step - 0.00000001))
	# Keep the selected duration and rate: a 4.2s bleed has eight 0.5s ticks and a 0.2s tail.
	# All timing and damage are captured here, so later level changes do not rewrite old stacks.
	stacks.append({"left": ticks, "per_tick": total * step / plan.seconds, "clock": 0.0,
		"tick_seconds": step, "last_seconds": plan.seconds - (ticks - 1) * step})
	probe.counts.bleeds_applied += 1

func tick_bleeds(dt: float) -> void:
	# Bleed is its own non-critical damage event: no hit roll, no crit, no defence, no stun.
	for id in enemies.keys():
		if not enemies.has(id):
			continue
		var stacks: Array = enemies[id].bleeds
		var amount := 0.0
		for stack in stacks:
			stack.clock += dt
			while stack.left > 0:
				var interval: float = stack.last_seconds if stack.left == 1 else stack.tick_seconds
				if stack.clock + 0.00000001 < interval:
					break
				stack.clock = maxf(0.0, stack.clock - interval)
				stack.left -= 1
				amount += stack.per_tick * interval / stack.tick_seconds
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
			"hp_rate": (config.max_hp if full else potion.get("hp", 0.0) * potion_factor()) / seconds if potion.kind != "mp" else 0.0,
			"mp_rate": (state.max_mana if full else potion.get("mp", 0.0) * potion_factor()) / seconds if potion.kind != "hp" else 0.0})
	probe.potions[slot.id] = probe.potions.get(slot.id, 0) + 1
	# A light in the potion colour around the witch tells which potion was drunk.
	spawn_vfx().potion_glow(player.position, {"hp": Color(1.0, 0.32, 0.28), "mp": Color(0.35, 0.85, 1.0), "both": Color(0.82, 0.55, 1.0), "speed": Color(0.62, 1.0, 0.38)}[potion.kind], map.ground_y(player.position))
	play_sfx("potion_drink", 1.4)

func buy_potion(id: String) -> bool:
	# Trial shop in the inventory: full-restore potions are drop-only (04 §8.2).
	var price: int = int(items.data.potion_prices.get(id, 0))
	if price <= 0 or coins < price:
		return false
	coins -= price
	potion_stash[id] += 1
	refresh_build_windows()
	return true

func assign_quickslot(index: int, id: String) -> void:
	# The slot's potions go back to the stash and the chosen kind's whole stack moves in.
	var slot: Dictionary = potion_slots[index]
	potion_stash[slot.id] += slot.count
	slot.id = id
	slot.count = potion_stash[id]
	potion_stash[id] = 0
	refresh_build_windows()

func fill_quickslot(index: int) -> void:
	var slot: Dictionary = potion_slots[index]
	slot.count += potion_stash[slot.id]
	potion_stash[slot.id] = 0
	refresh_build_windows()

func potion_factor() -> float:
	# 「록」 on accessories and 「록샤」 raise how much an ordinary potion restores.
	return 1.0 + gear_total("potion_pct") / 100.0

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
		var drunk: Dictionary = rules.restore_mana(state, effect.mp_rate * spent)
		state = drunk.state
		probe.mana_gain("potions", drunk.events[0].amount)
		effect.time -= spent
		if effect.time <= 0:
			potion_effects.erase(effect)

func pending_fill(key: String) -> float:
	# What running potions will still add; the HUD shows it as a pale layer.
	var total = 0.0
	for effect in potion_effects:
		total += effect[key] * effect.time
	return total

func shield_duration() -> float:
	# Each shield level holds it up longer; at Lv10 it outlasts its own cooldown, so a fully
	# invested shield can be kept up for good by recasting.
	var shield: Dictionary = rules.skills.shield
	return float(shield.duration_seconds) + float(shield.duration_per_level) * (config.shield_level - 1)

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
		# The blow came from somewhere; the nearest enemy picks which side panel takes it.
		var near_id: String = nearest_enemy(player.position, 30.0)
		var threat: Vector3 = enemies[near_id].body.position if enemies.has(near_id) else player.position - player_model.global_basis.z
		var guard: Vector3 = shield_visual.block(threat) if is_instance_valid(shield_visual) else player.position + Vector3.UP * 0.9
		spawn_vfx().block(guard, map.ground_y(player.position))
		play_sfx("block", 2.2)
		probe.witch_hit(by_grade, 0.0, false, true)
		return
	# Damage reduction options shave every unblocked hit, at most by half.
	amount *= 1.0 - minf(0.5, gear_total("damage_reduction") / 100.0)
	# Only a heavy enough hit that leaves her standing stuns.
	var stunned: bool = hp - amount > 0 and amount >= config.max_hp * config.hit_stun_min_ratio and dash.is_empty()
	probe.witch_hit(by_grade, minf(hp, amount), stunned, false)
	hp = maxf(0, hp - amount)
	hit_time = 0.25
	spawn_vfx().hurt(player.position + Vector3.UP * 0.85, map.ground_y(player.position))
	play_sfx("player_hurt", 0.75)
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
	var durability: float = (config.automaton_hp if mobile else config.turret_hp) * summon_growth("hp", "automaton" if mobile else "turret")
	# The automaton keeps the node it was summoned with; B never times out but only so many stay.
	# Taken before an old B steps aside, so the new one keeps the place it was assembled at.
	var slot := free_follow_slot() if mobile else -1
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
		"life": life, "hp": durability, "max_hp": durability, "reach": 1.6, "slot": slot})
	ally_serial += 1
	spawn_vfx().summon_arrive(node.position, TEAL, map.ground_y(node.position))
	play_sfx("summon_arrive", 1.8)

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

func chain_cut(first: String, damage: float) -> void:
	# Unique 집행자의 도르래: a landed bolt cutter hit drags the nearest other enemy in.
	if not enemies.has(first):
		return
	var rule: Dictionary = items.data.rule_values
	var origin: Vector3 = enemies[first].body.position
	var second := ""
	var best := float(rule.chain_cut_range)
	for id in enemies:
		var gap: float = enemies[id].body.position.distance_to(origin)
		if id != first and gap <= best:
			best = gap
			second = id
	if second != "":
		strike(second, damage * float(rule.chain_cut_factor), true, "witch", "bolt_cutter")

func expire_ally(ally: Dictionary) -> void:
	# End of life: automatons self-destruct, turrets just shut down. An A automaton also lands
	# here the moment it reaches its target, trading its repeated attacks for a bigger blast.
	if ally.mobile:
		var damage: float = config.shot_damage * (float(config.automaton_nodes.A.blast_factor) if ally.node_kind == "A" else 1.0) * summon_growth("damage", "automaton")
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
	if ally.mobile:
		play_sfx("automaton_explode", 0.65)
	else:
		play_cue(1.15)
	var spot: Vector3 = ally.node.position
	ally.node.queue_free()
	allies.erase(ally)
	# Unique 자기복제 태엽: a self-destructing automaton leaves one replica with half the life;
	# replicas never copy themselves again.
	if ally.mobile and gear_total("rule:self_replicate") > 0 and not ally.get("replica", false):
		spawn_ally(spot, true, "")
		var replica: Dictionary = allies[-1]
		replica.replica = true
		replica.life *= float(items.data.rule_values.replica_life_factor)

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
	if not is_instance_valid(player) or loading:
		return
	if player_visual.field_entry_active():
		# Entry is outside the combat clock: enemies, resources and pending actions
		# wait until the staff is held and the covered outfit swap has completed.
		player_visual.sync_state(dt,false,0.0,paused,hp<=0,false,0.0)
		if sfx != null:
			sfx.set_drone(null)
		for cue in player_visual.consume_entry_cues():
			# Assembly and outfit change have their own sounds; the grasp keeps the pitched impact.
			var named: String = {"assembly": "staff_assemble", "outfit": "outfit_change"}.get(cue.get("event", ""), "")
			if named != "" and sfx != null and sfx.has_cue(named):
				play_sfx(named, float(cue.pitch))
			else:
				play_cue(float(cue.pitch),float(cue.gain_db))
		place_camera(player.position)
		map.fade_between(camera.global_position,player.position+Vector3.UP)
		hud.queue_redraw()
		return
	tick_ground_loot(dt)
	sync_automaton_cost()
	if not paused and field_cleared():
		cancel_summon_assemblies("field_cleared")
	var visual_start_position := player.position
	var collecting_after_clear := field_cleared() and not loot_target.is_empty()
	if not paused and hp > 0 and collecting_after_clear:
		# Collect the final enemy's drops without restarting any combat/resource clocks.
		tick_pickup()
		if moving and not loot_target.is_empty():
			walk_to_destination(dt)
			player.position.y = map.ground_y(player.position)
			tick_pickup()
	if not paused and hp > 0 and not field_cleared():
		elapsed += dt
		var advanced: Dictionary = rules.advance(state, dt)
		state = advanced.state
		probe.record(advanced.events)
		for event in advanced.events:
			if event.type == "tool_released":
				show_message("마나 소진 · 공구 해제")
				flash_tool_change(null)
		var regen: Dictionary = rules.restore_mana(state, config.mana_regen * (1.0 + gear_total("mana_regen_pct") / 100.0) * dt)
		state = regen.state
		probe.mana_gain("regen", regen.events[0].amount)
		if a5_mode:
			probe.tick(dt, skill_gap(), unaffordable_skills())
			tick_respawns(dt)
		tick_potions(dt)
		tick_bolts(dt)
		tick_bleeds(dt)
		tick_pickup()
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
		if not dash.is_empty():
			tick_dash(dt)
		elif moving and action_time <= 0:
			walk_to_destination(dt)
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
	if sfx != null:
		# The grinder and chainsaw keep running while they are out; any action revs them up.
		var running: bool = not muted and not paused and hp > 0 and not field_cleared()
		sfx.set_drone(state.active_tool if running else null, 1.0 if action_time > 0 else 0.0)
	if is_instance_valid(grinder_disk) and state.active_tool == "grinder" and not paused and hp > 0 and not field_cleared():
		grinder_disk.rotate_object_local(Vector3.UP, dt * 18)
	var visual_distance := player.position.distance_to(visual_start_position)
	player_visual.sync_state(dt, visual_distance > 0.0001, 0.0 if collecting_after_clear else action_time, paused, hp <= 0, field_cleared() and not (collecting_after_clear and visual_distance > 0.0001), visual_distance / maxf(dt, 0.000001))
	tick_staff_trail(dt)
	shield_ring.visible = false
	place_camera(player.position)
	map.fade_between(camera.global_position, player.position + Vector3.UP)
	if shake_time > 0:
		# Short crit or boss-impact jolt; the camera angle never changes, only a small offset.
		shake_time = maxf(0, shake_time - dt)
		camera.position += Vector3(sin(elapsed * 90), 0, cos(elapsed * 77)) * 0.06
	var mouse := get_viewport().get_mouse_position()
	update_loot_hover(mouse)
	var hovered = pick_cursor(mouse) if hovered_loot.is_empty() and loot_pointer_available(mouse) else {}
	hover_id = hovered.get("enemy_id", "")
	hover_ring.visible = enemies.has(hover_id)
	if hover_id != outlined_id:
		if enemies.has(outlined_id):
			dress_enemy(enemies[outlined_id], false)
		if enemies.has(hover_id):
			dress_enemy(enemies[hover_id], true)
		outlined_id = hover_id
	if not paused:
		message_time = maxf(0, message_time - dt)
		fallback_time = maxf(0, fallback_time - dt)
		hit_time = maxf(0, hit_time - dt)
		stun_time = maxf(0, stun_time - dt)
		shield_time = maxf(0, shield_time - dt)
		tick_cast_circles(dt)
		if is_instance_valid(shield_visual):
			shield_visual.sync(dt, player.position, player_model.global_rotation.y, shield_time > 0 and hp > 0)
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
		play_sfx("summon_break", 1.15)
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
	if enemy.get("knockback_left", 0.0) > 0.0:
		# Knocked back: it slides away and neither steers nor advances its attack meanwhile.
		var travel: float = minf(enemy.knockback_speed * dt, enemy.knockback_left)
		enemy.body.velocity = enemy.knockback_dir * travel / dt
		enemy.body.move_and_slide()
		enemy.knockback_left -= travel
		return
	var type: Dictionary = config.enemy_types[enemy.kind]
	var power: float = config.grades[enemy.grade].damage * enemy_level_factor("damage", enemy.level)
	var pace: float = config.enemy_speed * type.speed * config.grades[enemy.grade].speed * (slow_factor() if enemy.slow > 0 else 1.0)
	if type.has("boss"):
		tick_boss(enemy, type.boss, power, pace, dt)
		return
	enemy.charge_cooldown = maxf(0, enemy.charge_cooldown - dt)
	if enemy.charging > 0:
		# Brute charge: a straight dash along the telegraphed line that hits the witch at most once.
		var charge: Dictionary = type.charge
		enemy.charging = maxf(0, enemy.charging - dt)
		enemy.body.velocity = enemy.charge_dir * config.enemy_speed * charge.speed_factor * (slow_factor() if enemy.slow > 0 else 1.0)
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
			play_sfx("boss_sweep", 0.5)
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
			play_sfx("boss_slam", 0.4)
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
			play_sfx("boss_shockwave", 0.35)
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
	play_sfx("enemy_bolt", 1.9)

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
			var before: Vector3 = ally.node.position
			ally.node.position = ally.node.position.move_toward(follow(ally.route, ally.node.position, automaton_spawn_position(ally.slot), 0.4, dt), dt * 7)
			face_travel(ally, before, dt)
			continue
		if not eligible(ally, ally.target):
			ally.target = nearest_enemy(ally.node.position, config.summon_detection_range if ally.mobile else config.turret_detection_range, Vector3.ZERO, -1, true, true)
		if ally.target == "":
			if ally.mobile:
				var before: Vector3 = ally.node.position
				ally.node.position = ally.node.position.move_toward(follow(ally.route, ally.node.position, automaton_spawn_position(ally.slot), 0.4, dt), dt * 4)
				face_travel(ally, before, dt)
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
			damage = (damage if ally.mobile else config.turret_damage) * summon_growth("damage", "automaton" if ally.mobile else "turret")
			strike(ally.target, damage, true, "automaton" if ally.mobile else "turret", "automaton" if ally.mobile else "turret", "saw" if saw else "")
			ally.cooldown = config.summon_attack_cooldown if ally.mobile else config.turret_attack_cooldown
	separate_allies(dt)

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
