extends Node3D
const Rules = preload("res://scripts/combat_rules.gd")
const Shape = preload("res://scripts/shapes.gd")
const Hud = preload("res://scripts/hud.gd")
const ManaProbe = preload("res://scripts/mana_probe.gd")
const Build = preload("res://scripts/build.gd")
const Items = preload("res://scripts/items.gd")
const GroundLoot = preload("res://scripts/ground_loot.gd")
const GroundLootVisual = preload("res://scripts/ground_loot_visual.gd")
const InventoryWindow = preload("res://scripts/inventory_window.gd")
const BuildWindow = preload("res://scripts/build_window.gd")
const FieldMap = preload("res://scripts/field_map.gd")
const PlayerVisual = preload("res://scripts/player_visual.gd")
const ActorVisual = preload("res://scripts/actor_visual.gd")
const AutomatonAssembly = preload("res://scripts/automaton_assembly.gd")
const TurretAssembly = preload("res://scripts/turret_assembly.gd")
const ShotgunCast = preload("res://scripts/shotgun_cast.gd")
const ShotgunGeometry = preload("res://scripts/shotgun_geometry.gd")
const FloatingGun = preload("res://scripts/floating_gun.gd")
const PowderKeg = preload("res://scripts/powder_keg.gd")
const GatlingGun = preload("res://scripts/gatling_gun.gd")
const SmokeLauncher = preload("res://scripts/smoke_launcher.gd")
const SmokeCloud = preload("res://scripts/smoke_cloud.gd")
const IncomingShell = preload("res://scripts/incoming_shell.gd")
const FirePatch = preload("res://scripts/fire_patch.gd")
const ShieldVisual = preload("res://scripts/shield_visual.gd")
const CastCircle = preload("res://scripts/cast_circle.gd")
const SpringPlate = preload("res://scripts/spring_plate.gd")
const DriveDevice = preload("res://scripts/drive_device.gd")
const ExoVisual = preload("res://scripts/exoskeleton_visual.gd")
# Drive executions set up on the ground and run on their own after the cast (03 §4).
const DEVICES = ["guillotine", "hydraulic_press", "compound_executor"]
# Which skill tree draws the casting circle; the basic attack draws none.
const SKILL_TREES = {"shotgun": "firearm", "matchlock": "firearm", "rifle": "firearm", "powder_keg": "firearm", "gatling": "firearm", "smoke_launcher": "firearm", "recoil_leap": "firearm", "artillery": "firearm", "naval_gun": "firearm", "bolt_cutter": "drive", "grinder": "drive", "chainsaw": "drive", "shield": "drive", "spring_dash": "drive",
	"guillotine": "drive", "hydraulic_press": "drive", "compound_executor": "drive", "restraint_winch": "drive", "exoskeleton": "drive",
	"focus_attack": "drive", "area_attack": "drive",
	"automaton": "automation", "turret": "automation", "relay": "automation"}
const CombatVfx = preload("res://scripts/combat_vfx.gd")
const StatusFx = preload("res://scripts/status_fx.gd")
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
# Centre gap per unit of summed model size between two enemies' spawn points.
const ENEMY_SPACING := 0.45
# Ground warnings: dark area plus a bright fill that reaches the edge at impact.
const WARN = Color("7a3a32")
const WARN_FILL = Color("e8604c")
# Each tool keeps its own colour on the witch, its ring and its swings.
const BLEED_RED = Color("c8463c")
const TOOL_COLORS = {"bolt_cutter": BRASS, "grinder": STEEL, "chainsaw": BLEED_RED}
const PICK_LAYER = 8
# Held inputs repeat only attack-like casts; toggles, summons and placement stay one per press.
const REPEAT_KINDS = ["aim", "enemy"]
const GUNS = ["matchlock", "rifle"]
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
var shotgun_cooldown := 0.0
# C10: potions bought or dropped wait in the stash; the four quickslots are refilled by hand
# from it (04 §8.2: no automatic refill). The stash persists; a restart still restocks the loadout.
var potion_stash: Dictionary = {}
const POTION_BAG_CAPACITY = 15
var potion_cells: Array[String] = []
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
# The firearm gun floating at her shoulder ({id, ammo, reload_left, visual}); while it is out the
# basic attack shoots, and empty rounds load back one at a time.
var gun: Dictionary = {}
var gun_assembly: Node3D
var basic_range: float
var spring_plate: Node3D
# Powder kegs: one assembles during the cast, then each rolls on its own until it bursts
# ({visual, position, direction, left, total, rolled}).
var keg_assembly: Node3D
var kegs: Array = []
var last_keg: Dictionary = {}
# The rotary cannon assembles during its spin-up, then streams rounds while its key stays held
# ({skill, slot, visual, fire_left, shots, aim, direction, focus, focus_hits}).
var gatling_assembly: Node3D
var channel: Dictionary = {}
var last_burst: Dictionary = {}
# Tool attacks (03 §2, drive II): the focus attack is a held channel in `channel`
# ({skill, tool, slot, direction, time, period, loop, fire_left, hits}); an area sweep runs here
# while its motion plays ({tool, plan, direction, phase, total, reach, struck}).
const TOOL_ATTACKS = ["focus_attack", "area_attack"]
var sweep: Dictionary = {}
var last_tool_attack: Dictionary = {}
# Smoke zones: enemies inside one, or looking through one, cannot see the witch
# ({center, radius, wait, left, total, cloud}; wait counts down the canisters' flight).
var smoke_assembly: Node3D
var smokes: Array = []
# Offscreen shells on their way in ({visual, trail, start, end, left, flight, at, impact}) and the
# burning ground some of them leave ({center, radius, left, total, damage, source, patch}).
var shells: Array = []
var fires: Array = []
var burn_clock := 0.0
var last_impact: Dictionary = {}
# Drive devices: one assembles at its spot during the cast, then each runs on its own clock
# ({skill, model, visual, time, center, plan, fired, ticks, locked, caged}). Winch hooks in flight
# ({visual, targets, spots, time, plan, fired, direction}) and the exoskeleton's clock sit beside them.
var device_assembly: Node3D
var devices: Array = []
var winches: Array = []
var last_device: Dictionary = {}
var exo_visual: Node3D
var last_shotgun: Dictionary = {}
# Unique-rule state: the twin core's second volleys and the counter hinge's push clock.
var twin_shots: Array = []
var block_push_left := 0.0
var last_recoil: Dictionary = {}
var last_spring_landing: Dictionary = {}
var last_shot: Dictionary = {}
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
	shotgun_cooldown = float(rules.skills.shotgun.cooldown_seconds)
	basic_range = float(rules.skills.basic_attack.range)
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
		inventory_window.clear_potion_hand()
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
	gun_assembly = null
	gun = {}
	sync_gun()
	keg_assembly = null
	kegs.clear()
	last_keg.clear()
	gatling_assembly = null
	channel.clear()
	last_burst.clear()
	sweep.clear()
	last_tool_attack.clear()
	smoke_assembly = null
	smokes.clear()
	device_assembly = null
	devices.clear()
	winches.clear()
	last_device.clear()
	shells.clear()
	fires.clear()
	burn_clock = 0.0
	last_impact.clear()
	last_shotgun.clear()
	twin_shots.clear()
	block_push_left = 0.0
	last_recoil.clear()
	last_spring_landing.clear()
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
	exo_visual = null
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
	var size: float = type.scale * rank.scale
	pos = free_enemy_spot(map.grounded(pos), size)
	var body = Shape.body(world, pos, 2)
	body.set_meta("enemy_id", id)
	var model = Shape.enemy(body, kind)
	var pick = Shape.pick_volume(body, 0.7 * size, 1.65 * size, PICK_LAYER)
	pick.set_meta("enemy_id", id)
	var maximum: float = type.hp * rank.hp * enemy_level_factor("hp", enemy_level)
	enemies[id] = {"body": body, "model": model, "hp": maximum, "max_hp": maximum, "heavy": type.get("heavy", false), "kind": kind, "level": enemy_level,
		"grade": grade, "size": size, "cooldown": 1.0, "windup": 0.0, "attack": "", "charge_cooldown": 1.0, "charging": 0.0,
		"charge_dir": Vector3.ZERO, "charge_hit": false, "target": "", "retarget": 0.0, "slow": 0.0, "shred": 0.0, "bleeds": [], "flash": 0.0,
		"respawn": true, "timers": {}, "phases_done": [], "pattern_dir": Vector3.ZERO, "frames": [], "route": {}, "flinch": 0.0, "flinch_guard": 0.0}
	dress_enemy(enemies[id], id == outlined_id)

func free_enemy_spot(pos: Vector3, size: float) -> Vector3:
	# Respawns reuse a few listed spots; a newcomer steps out to the nearest free ring point
	# instead of standing inside an enemy already there, whose capsule could never push it out.
	if enemy_spot_free(pos, size):
		return pos
	for ring in range(1, 9):
		var radius: float = 0.5 * ring
		var count: int = 6 * ring
		for i in count:
			var spot: Vector3 = map.grounded(pos + Vector3(radius, 0, 0).rotated(Vector3.UP, TAU * i / count))
			if map.walkable(spot) and map.sees(pos, spot) and enemy_spot_free(spot, size):
				return spot
	return pos

func enemy_spot_free(pos: Vector3, size: float) -> bool:
	for other in enemies.values():
		var gap := Vector2(other.body.position.x - pos.x, other.body.position.z - pos.z)
		if gap.length() < maxf(0.8, ENEMY_SPACING * (other.size + size)):
			return false
	return true

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
	if event is InputEventMouseButton and event.pressed and inventory_window.holding_potion():
		# Cancel a potion selection outside the window without consuming it or attacking.
		inventory_window.clear_potion_hand()
		get_viewport().set_input_as_handled()
		return
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
			call_test_boss()
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

func call_test_boss() -> void:
	# Test tool: the boss appears in the map's boss arena (a field edge on the flat arena), and
	# only while no boss is on the field. It also stands in for the arena's own entry boss.
	if enemies.values().any(func(enemy): return config.enemy_types[enemy.kind].has("boss")):
		show_message("이미 보스가 있습니다")
		return
	var pos: Vector3 = edge_point()
	if map.data.has("boss"):
		pos = Vector3(map.data.boss.pos[0], 0, map.data.boss.pos[1])
		boss_spawned = true
	spawn_enemy("boss_" + str(boss_serial), pos, true, "boss", "latch")
	boss_serial += 1
	show_message("보스 등장")

func set_a5_mode(enabled: bool) -> void:
	save_mana_log("mode_off" if a5_mode else "mode_on")
	a5_mode = enabled
	reset_arena()
	show_message("A5 마나 시험 시작 · 연속 교전" if enabled else "A5 마나 시험 종료")

func bind_slot(slot: String, skill_id) -> void:
	# The skill tree window's loadout: any skill on LMB/RMB/Q/W/E/R, kept across restarts.
	# The left button is never empty: clearing it (or swapping its basic attack onto another
	# key) gives it back the basic attack, and the basic attack never sits on another key.
	if slot == "lmb" and skill_id == null:
		skill_id = rules.basic_id
	elif slot != "lmb" and skill_id == rules.basic_id:
		skill_id = null
	cancel_pending_cast()
	split_build_log()
	config.bindings[slot] = skill_id
	state = rules.bind(state, slot, skill_id)
	# A running tool that no slot holds any more could never be switched off; release it.
	if state.active_tool != null and not state.bindings.values().has(state.active_tool):
		state.active_tool = null
	if not gun.is_empty() and not state.bindings.values().has(gun.id):
		dismiss_gun()

func drop_unlearned_bindings() -> void:
	# A reset that unlearns a skill takes it off its key.
	if state.is_empty() or build == null:
		return
	for slot in rules.SLOTS:
		var id = state.bindings[slot]
		if id != null and not build.learned(id):
			var empty = rules.basic_id if slot == "lmb" else null
			config.bindings[slot] = empty
			state = rules.bind(state, slot, empty)

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
	var visual: Node3D
	var authored := GroundLootVisual.create(node, payload)
	if not authored.is_empty():
		visual = authored.visual
		rest_height = authored.rest_height
	else:
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
	if not loading and not paused and hp > 0 and not player_visual.field_entry_active() and held_item == null and held_piece == "" and not inventory_window.holding_potion():
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
		GroundLootVisual.highlight(loot.visual, active, color)
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
			# With the inventory open it comes up on the cursor, ready to be placed or worn.
			if held_item == null and is_instance_valid(inventory_window) and inventory_window.is_visible_in_tree():
				loot.item.erase("at")
				held_item = loot.item
				refresh_build_windows()
			elif not stow(loot.item):
				show_message("가방에 자리가 없습니다")
				return
		"currency":
			coins += int(loot.amount)
		"piece":
			pieces[loot.id] += int(loot.amount)
		"potion":
			if not store_potion(loot.id, int(loot.amount)):
				show_message("물약 가방에 자리가 없습니다")
				return
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
	# The exoskeleton's drive frame trims it further.
	var cut: float = minf(0.9, gear_total("upkeep_pct") / 100.0)
	for id in tool_upkeep:
		rules.skills[id].upkeep_per_second = float(tool_upkeep[id]) * (1.0 - cut) * (1.0 - exo_upkeep_cut())

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
		# Executions are set right over their victims; other placements need a free spot.
		if not skill.get("over_enemies", false):
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
	# A gun is assembled loaded: its cost is a full magazine at its per-round price.
	for id in GUNS:
		rules.skills[id].mana_cost = gun_magazine(id) * round_cost(id)
	# Recoil control steadies the shotgun's repeat as it does every gun's.
	rules.skills.shotgun.cooldown_seconds = shotgun_cooldown * fire_interval_factor()
	sync_gun()

func round_cost(id: String) -> float:
	# Mana cost cuts trim every round as they trim every skill, at most by half.
	return float(rules.skills[id].round_cost) * (1.0 - clampf(gear_total("mana_cost_pct") / 100.0, 0.0, 0.5))

func reload_level() -> float:
	return float(config.passive_levels.get("reload", 0))

func recoil_level() -> float:
	return float(config.passive_levels.get("recoil_control", 0))

func fire_interval_factor() -> float:
	# Recoil control (firearm passive): every firearm fires again sooner, by a share per level.
	return maxf(0.1, 1.0 - float(config.passives.recoil_control.fire_interval_cut_per_level) * recoil_level())

func leap_speed_factor() -> float:
	# It also lands the recoil leap and the spring dash's jump faster: the same distance in less time.
	return 1.0 + float(config.passives.recoil_control.leap_speed_per_level) * recoil_level()

func turret_fire_rate() -> float:
	# The reload mechanism's feed also speeds up the turret, which feeds rounds the same way (03 §2.1).
	return 1.0 + float(config.passives.reload.turret_rate_per_level) * reload_level()

func gun_magazine(id: String) -> int:
	# Reload mechanism levels and magazine options add rounds to every gun's magazine.
	return int(rules.skills[id].magazine) + int(config.passives.reload.magazine_per_level) * int(reload_level()) + int(gear_total("magazine"))

func reload_seconds(id: String) -> float:
	# One empty round loads back each interval; each reload mechanism level cuts a share of it.
	return float(rules.skills[id].reload_seconds) * maxf(0.1, 1.0 - float(config.passives.reload.reload_time_cut_per_level) * reload_level())

func tick_gun_reload(dt: float) -> void:
	# Empty rounds load back on their own, one per interval, each paying its mana as it goes in.
	# With too little mana the next round waits; a full magazine keeps the clock wound.
	if gun.is_empty():
		return
	var interval := reload_seconds(gun.id)
	if int(gun.ammo) >= gun_magazine(gun.id):
		gun.reload_left = interval
		return
	gun.reload_left = float(gun.reload_left) - dt
	if gun.reload_left > 0:
		return
	var cost := round_cost(gun.id)
	if state.mana + rules.EPS < cost:
		gun.reload_left = 0.0
		return
	state.mana = maxf(0.0, state.mana - cost)
	probe.record([{"type": "tool_upkeep", "tool": gun.id, "amount": cost}])
	gun.ammo = int(gun.ammo) + 1
	gun.reload_left += interval

func sync_gun() -> void:
	# The basic attack takes the gun's reach while one is out.
	rules.skills.basic_attack.range = float(rules.skills[gun.id].range) if not gun.is_empty() else basic_range
	# A lower reload level shrinks the magazine; rounds over it are dropped.
	if not gun.is_empty():
		gun.ammo = mini(int(gun.ammo), gun_magazine(gun.id))

func equip_gun(id: String) -> void:
	# A gun and a tool both change the basic attack, so the gun puts the tool away (and back).
	if state.active_tool != null:
		state.active_tool = null
		flash_tool_change(null)
	var visual: Node3D = gun_assembly if is_instance_valid(gun_assembly) else null
	gun_assembly = null
	if not gun.is_empty() and gun.visual != visual and is_instance_valid(gun.visual):
		gun.visual.dismiss()
	if visual == null:
		visual = FloatingGun.new()
		visual.configure(id)
		world.add_child(visual)
		visual.initialize(self)
	visual.gun_id = id
	visual.ready_to_fire()
	gun = {"id": id, "ammo": gun_magazine(id), "reload_left": reload_seconds(id), "visual": visual}
	sync_automaton_cost()
	play_sfx("tool_change", 1.3)

func dismiss_gun() -> void:
	if gun.is_empty():
		return
	if is_instance_valid(gun.visual):
		gun.visual.dismiss()
	gun = {}
	sync_automaton_cost()

func gun_round(id: String) -> Dictionary:
	# The rifle's node picks its round; other guns fire their own single kind.
	var skill: Dictionary = rules.skills[id]
	return skill.nodes[config.rifle_node] if skill.has("nodes") else skill

func fire_gun(event: Dictionary, direction: Vector3) -> void:
	# One round per shot, hit or miss, from the floating gun's muzzle to the chosen enemy.
	var skill: Dictionary = rules.skills[gun.id]
	var best := nearest_enemy(player.position, float(skill.range), direction, 0.2, false, true)
	if event.get("target_enemy") != null and enemies.has(event.target_enemy):
		best = event.target_enemy
	var target_spot: Vector3 = enemies[best].body.position if best != "" else Vector3.ZERO
	gun.ammo = maxi(0, int(gun.ammo) - 1)
	var aim: Vector3 = player.position + direction * float(skill.range) + Vector3.UP * 1.2
	if best != "":
		aim = enemies[best].body.position + Vector3.UP * 0.9 * enemies[best].size
	var origin: Vector3 = player.position + Vector3.UP * 1.3
	if is_instance_valid(gun.visual):
		gun.visual.shoot(aim)
		origin = gun.visual.muzzle()
	var shell: Dictionary = gun_round(gun.id)
	var damage: float = float(shell.shot_damage)
	var struck: Array = []
	var hit := "miss"
	if shell.has("pierce_width"):
		# Piercing rounds run the whole range and strike every enemy along the line in sight.
		aim = player.position + direction * float(skill.range) + Vector3.UP * 1.2
		if best != "":
			var flat: Vector3 = enemies[best].body.position - player.position
			flat.y = 0.0
			aim = player.position + flat.normalized() * float(skill.range) + Vector3.UP * 1.2
		var line: Vector3 = aim - player.position
		line.y = 0.0
		line = line.normalized()
		for id in enemies.keys():
			var delta: Vector3 = enemies[id].body.position - player.position
			delta.y = 0.0
			var along: float = delta.dot(line)
			if along > 0 and along <= float(skill.range) and (delta - line * along).length() <= float(shell.pierce_width) * enemies[id].size and map.sees(player.position, enemies[id].body.position):
				struck.append(id)
		for id in struck:
			var result := strike(id, damage, true, "witch", gun.id)
			if result != "miss":
				hit = result
	elif best != "":
		struck.append(best)
		hit = strike(best, damage, true, "witch", gun.id)
		if shell.has("knockback_distance") and hit != "miss":
			push_back(best, float(shell.knockback_distance), float(shell.knockback_seconds))
		var flat: Vector3 = target_spot - player.position
		flat.y = 0.0
		struck.append_array(pierce_behind(best, target_spot, flat.normalized(), float(skill.range), 0.5, damage, gun.id))
	if shell.has("blast_radius"):
		# Explosive rounds burst where they land, hit or miss: everyone else nearby is caught too.
		var at: Vector3 = Vector3(aim.x, map.ground_y(aim), aim.z)
		for id in enemies.keys():
			if (id != best or hit == "miss") and Vector2(enemies[id].body.position.x - at.x, enemies[id].body.position.z - at.z).length() <= float(shell.blast_radius):
				if not struck.has(id):
					struck.append(id)
				strike(id, damage, false, "witch", gun.id)
		spawn_vfx().blast(at, float(shell.blast_radius), map.ground_y(at), false)
	spawn_vfx().muzzle(origin, [aim], [struck.is_empty()], map.ground_y(origin))
	play_sfx("shotgun_fire", (0.85 if gun.id == "rifle" else 1.15) if hit != "miss" else 1.3)
	last_shot = {"gun": gun.id, "target": best, "result": hit, "origin": origin, "aim": aim, "struck": struck}
	if int(gun.ammo) == 0:
		show_message("탄이 없습니다")

func pierce_behind(first: String, spot: Vector3, line: Vector3, reach: float, width: float, damage: float, source: String) -> Array:
	# Pierce options (04 §4.3): a single round carries on past the enemy it struck (at `spot`, which
	# it may just have killed) into the next enemies on its line, each rolling to hit for full damage.
	var count := int(gear_total("pierce"))
	if count <= 0:
		return []
	var past: float = Vector3(spot.x - player.position.x, 0.0, spot.z - player.position.z).dot(line)
	var behind: Array = []
	for id in enemies:
		var delta: Vector3 = enemies[id].body.position - player.position
		delta.y = 0.0
		var along: float = delta.dot(line)
		if id != first and along > past and along <= reach and (delta - line * along).length() <= width * float(enemies[id].size) and map.sees(player.position, enemies[id].body.position):
			behind.append({"along": along, "id": id})
	behind.sort_custom(func(a, b): return a.along < b.along)
	var hits: Array = []
	for entry in behind.slice(0, count):
		hits.append(entry.id)
		strike(entry.id, damage, true, "witch", source)
	return hits

func request_slot(slot: String, cursor: Dictionary, shift: bool = false) -> void:
	sync_automaton_cost()
	if paused or hp <= 0 or field_cleared() or player_visual.field_entry_active():
		return
	if slot not in rules.SLOTS:
		return
	if not channel.is_empty():
		# Channeling holds her in place: her own key and ground clicks do nothing, while any other
		# skill or an attack on an enemy ends the stream first.
		if slot == channel.slot or (slot == "lmb" and cursor.get("enemy_id") == null):
			return
		stop_channel(true)
	if action_time > 0:
		# An attack motion finishes first; the latest input runs right after it.
		queued_input = {"slot": slot, "cursor": cursor.duplicate(true), "shift": shift}
		return
	var bound = state.bindings[slot]
	if bound != null and not build.learned(bound):
		show_message("배우지 않은 기술입니다")
		return
	cursor = device_cursor(bound, cursor)
	if bound in TOOL_ATTACKS and state.active_tool == null:
		# Tool attacks work only through a transformed tool, never the bare staff (03 §2).
		show_message("공구를 전개해야 쓸 수 있습니다")
		return
	if bound != null and bound in GUNS and gun.get("id") == bound:
		# Pressing the gun's key again takes it apart, free, like switching a tool off.
		cancel_pending_cast()
		dismiss_gun()
		return
	if slot == "lmb" and bound == rules.basic_id and not gun.is_empty() and int(gun.ammo) <= 0 and (shift or cursor.get("enemy_id") != null):
		show_message("탄이 없습니다")
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

func device_cursor(bound, cursor: Dictionary) -> Dictionary:
	# An execution device cast with the cursor on an enemy is set under that enemy, not on the
	# floor point the cursor ray reaches behind a tall model; while she walks into range the spot
	# keeps following it ("follow").
	if bound == null or not rules.skills[bound].get("over_enemies", false) or cursor.get("enemy_id") == null or not enemies.has(cursor.enemy_id):
		return cursor
	var aimed := cursor.duplicate(true)
	var at: Vector3 = enemies[cursor.enemy_id].body.position
	aimed.ground = [at.x, 0, at.z]
	aimed.follow = cursor.enemy_id
	return aimed

func begin_cast(slot: String, cursor: Dictionary, shift: bool, stationary: bool, result: Dictionary) -> void:
	var cast = cast_event(result)
	var skill: Dictionary = {} if cast.is_empty() else rules.skills[cast.skill]
	var seconds = 0.0
	if cast.get("skill") == rules.basic_id:
		seconds = attack_seconds(gun.id if not gun.is_empty() else cast.active_tool)
	elif cast.get("skill") in TOOL_ATTACKS:
		seconds = tool_attack_seconds(cast.skill, cast.active_tool)
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
	# With a gun out the basic attack is a pointing cast that the gun answers, not a staff swing,
	# and it fires at the gun's own point of the motion.
	var shooting: bool = cast.skill == rules.basic_id and not gun.is_empty()
	var release_ratio: float = float(rules.skills[gun.id].shot_release_ratio) if shooting else float(skill.get("release_ratio", 1.0))
	if cast.skill in TOOL_ATTACKS:
		# The focus attack's enter motion runs to its end before the loop; the area attack cuts
		# from its tool's own point of the motion.
		release_ratio = 1.0 if cast.skill == "focus_attack" else float(tool_attack_plan(cast.skill, cast.active_tool).release_ratio)
	windup = {"slot": slot, "binding": state.bindings[slot], "cursor": snapshot, "shift": shift, "stationary": stationary,
		"skill": cast.skill, "release": seconds * release_ratio, "tool": cast.get("active_tool")}
	if SKILL_TREES.has(cast.skill) and cast.skill not in TOOL_ATTACKS:
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
	elif cast.skill in ["shotgun", "recoil_leap"]:
		windup.visual_duration = windup.release
		begin_shotgun_visual(cast_target(cast), aims_at_enemy(cast))
	elif cast.skill == "spring_dash":
		windup.visual_duration = windup.release
		begin_spring_plate(cast_direction(cast))
	elif cast.skill == "powder_keg":
		windup.visual_duration = windup.release
		begin_keg_visual(cast_direction(cast))
	elif cast.skill in DEVICES or cast.skill == "restraint_winch":
		windup.visual_duration = windup.release
		device_assembly = begin_device_visual(cast.skill, cast_target(cast), cast_direction(cast))
	elif cast.skill == "smoke_launcher":
		windup.visual_duration = windup.release
		var facing: Vector3 = cast_direction(cast)
		smoke_assembly = SmokeLauncher.new()
		world.add_child(smoke_assembly)
		smoke_assembly.position = map.grounded(player.position + facing.cross(Vector3.UP) * 0.75)
		smoke_assembly.look_at(smoke_assembly.global_position + facing, Vector3.UP)
		smoke_assembly.initialize(self)
	elif cast.skill == "gatling":
		windup.visual_duration = windup.release
		if is_instance_valid(gatling_assembly):
			gatling_assembly.dismiss()
		gatling_assembly = GatlingGun.new()
		world.add_child(gatling_assembly)
		gatling_assembly.initialize(self)
		gatling_assembly.aim_at(cast_target(cast) + Vector3.UP)
	elif cast.skill in GUNS:
		windup.visual_duration = windup.release
		if is_instance_valid(gun_assembly):
			gun_assembly.dismiss()
		gun_assembly = FloatingGun.new()
		gun_assembly.configure(cast.skill)
		world.add_child(gun_assembly)
		gun_assembly.initialize(self)
	player_model.look_at(player.position + cast_direction(cast))
	if cast.skill in TOOL_ATTACKS:
		var plan := tool_attack_plan(cast.skill, cast.active_tool)
		player_visual.begin_tool_motion("focus_enter" if cast.skill == "focus_attack" else "area", cast.active_tool, seconds, release_ratio, float(plan.get("blade_scale", 1.0)))
	else:
		player_visual.begin_motion("attack" if cast.skill == rules.basic_id and not shooting else ("spring_jump" if cast.skill in ["spring_dash", "recoil_leap"] else "cast"), seconds, release_ratio)
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
	if is_instance_valid(smoke_assembly):
		smoke_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(gatling_assembly):
		gatling_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(keg_assembly):
		keg_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(device_assembly):
		device_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(spring_plate):
		spring_plate.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if is_instance_valid(gun_assembly):
		gun_assembly.sample_progress(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
	if windup.release > 0:
		return
	var started: Dictionary = windup
	windup = {}
	player_visual.mark_release()
	if state.bindings[started.slot] != started.binding:
		cancel_summon_assemblies("binding_changed")
		return
	if started.skill in TOOL_ATTACKS and state.active_tool != started.get("tool"):
		show_message("공구가 바뀌어 공격이 취소되었습니다")
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
	if is_instance_valid(gun_assembly):
		gun_assembly.dismiss()
	gun_assembly = null
	if is_instance_valid(spring_plate):
		spring_plate.cancel(reason)
	spring_plate = null
	if is_instance_valid(keg_assembly):
		keg_assembly.cancel(reason)
	keg_assembly = null
	if is_instance_valid(gatling_assembly):
		gatling_assembly.dismiss()
	gatling_assembly = null
	if is_instance_valid(smoke_assembly):
		smoke_assembly.cancel(reason)
	smoke_assembly = null
	if is_instance_valid(device_assembly):
		device_assembly.cancel(reason)
	device_assembly = null

func begin_spring_plate(direction: Vector3) -> void:
	spring_plate = SpringPlate.new()
	world.add_child(spring_plate)
	spring_plate.position = map.grounded(player.position - direction * 0.16)
	spring_plate.look_at(spring_plate.global_position + direction, Vector3.UP)
	spring_plate.initialize(self)

func keg_start(direction: Vector3) -> Vector3:
	# The keg assembles on the floor just in front of her, where it will start rolling.
	return map.grounded(player.position + direction * float(rules.skills.powder_keg.start_offset))

func begin_keg_visual(direction: Vector3) -> void:
	keg_assembly = PowderKeg.new()
	world.add_child(keg_assembly)
	keg_assembly.position = keg_start(direction)
	keg_assembly.look_at(keg_assembly.global_position + direction, Vector3.UP)
	keg_assembly.initialize(self)

func device_plan(skill_id: String) -> Dictionary:
	# A device's timings and numbers: its chosen node's when it has nodes.
	var skill: Dictionary = rules.skills[skill_id]
	if skill_id == "restraint_winch":
		var plan: Dictionary = skill.duplicate()
		plan.merge(skill.nodes[config.restraint_winch_node], true)
		# Hooks reel home once the pull is done (or soon after they bite, when they only bind).
		plan.release_at = float(plan.fly_seconds) + (float(plan.pull_seconds) if plan.pull else 0.35)
		plan.end_at = float(plan.release_at) + 0.25
		return plan
	return skill.nodes[config[skill_id + "_node"]] if skill.has("nodes") else skill

func device_model(skill_id: String) -> String:
	if skill_id == "guillotine":
		return {"base": "guillotine", "saw": "guillotine_saw", "lock": "guillotine_lock"}[config.guillotine_node]
	return skill_id

func begin_device_visual(skill_id: String, target: Vector3, direction: Vector3) -> Node3D:
	# Executions assemble on the spot they will strike; the winch sets down just in front of her.
	var plan := device_plan(skill_id)
	var visual = DriveDevice.new()
	visual.configure(device_model(skill_id), plan, float(plan.get("hit_radius", plan.get("trap_radius", 0.5))))
	world.add_child(visual)
	if skill_id == "restraint_winch":
		visual.position = map.grounded(player.position + direction * float(plan.offset))
	else:
		visual.position = map.grounded(target)
	visual.look_at(visual.global_position + direction, Vector3.UP)
	visual.initialize(self)
	return visual

func place_device(skill_id: String, target: Vector3, direction: Vector3) -> void:
	var visual = device_assembly
	device_assembly = null
	if not is_instance_valid(visual):
		visual = begin_device_visual(skill_id, target, direction)
	visual.activate()
	var entry := {"skill": skill_id, "model": device_model(skill_id), "visual": visual, "time": 0.0, "center": visual.global_position,
		"plan": device_plan(skill_id), "fired": {}, "ticks": 0, "locked": "", "caged": [], "marked": []}
	devices.append(entry)
	last_device = entry
	play_sfx("summon_assemble", 1.6)

func fire_once(entry: Dictionary, key: String, at_time: float) -> bool:
	if entry.fired.has(key) or float(entry.time) < at_time:
		return false
	entry.fired[key] = true
	return true

func tick_devices(dt: float) -> void:
	# Each device runs its mechanism; the hits land on the frames the mechanism reaches them.
	for entry in devices.duplicate():
		entry.time += dt
		var t: float = entry.time
		var plan: Dictionary = entry.plan
		match entry.model:
			"guillotine":
				if fire_once(entry, "drop", float(plan.drop_at) + float(plan.drop_seconds)):
					device_hits(entry, float(plan.hit_radius), float(plan.damage), "guillotine")
					device_thud(entry, 0.6, "bolt_cutter_cut")
			"guillotine_lock":
				if fire_once(entry, "lock", 0.0):
					entry.locked = lock_target(entry)
					catch_marks(entry, [entry.locked])
				if fire_once(entry, "drop", float(plan.drop_at) + float(plan.drop_seconds)):
					device_hits(entry, float(plan.hit_radius), float(plan.damage), "guillotine", {entry.locked: float(plan.lock_bonus)})
					release_hold([entry.locked])
					device_thud(entry, 0.6, "bolt_cutter_cut")
			"guillotine_saw":
				while entry.ticks < int(plan.ticks) and t >= float(plan.tick_from) + float(plan.tick_every) * entry.ticks:
					entry.ticks += 1
					if not device_hits(entry, float(plan.hit_radius), float(plan.tick_damage), "guillotine").is_empty():
						play_sfx("chainsaw_cut", 1.05)
			"hydraulic_press":
				if fire_once(entry, "press", float(plan.press_at) + float(plan.press_seconds)):
					for id in device_hits(entry, float(plan.hit_radius), float(plan.damage), "hydraulic_press"):
						restrain(id, "stun", press_stun_seconds(float(plan.stun_seconds)))
					spawn_vfx().shockwave(entry.center, float(plan.hit_radius), map.ground_y(entry.center))
					device_thud(entry, 0.5, "boss_slam")
			"compound_executor":
				if fire_once(entry, "cage", float(plan.gate_at) + float(plan.gate_seconds) * 0.5):
					entry.caged = cage_enemies(entry)
					catch_marks(entry, entry.caged)
				if fire_once(entry, "press", float(plan.press_at) + float(plan.press_seconds)):
					for id in device_hits(entry, float(plan.trap_radius), float(plan.press_damage) * executor_synergy("hydraulic_press"), "compound_executor"):
						restrain(id, "stun", press_stun_seconds(float(plan.stun_seconds)))
					device_thud(entry, 0.5, "boss_slam")
				while entry.ticks < int(plan.saw_ticks) and t >= float(plan.saw_from) + float(plan.saw_every) * entry.ticks:
					entry.ticks += 1
					var sawn: Array = device_hits(entry, float(plan.trap_radius), float(plan.saw_damage) * executor_synergy("guillotine"), "compound_executor")
					if entry.ticks == 1:
						for id in sawn:
							add_bleed(id)
					if not sawn.is_empty():
						play_sfx("chainsaw_cut", 1.05)
				if fire_once(entry, "open", float(plan.end_at)):
					release_hold(entry.caged)
		entry.visual.work(t)
		if entry.visual.finished(t):
			release_hold(entry.caged + [entry.locked])
			entry.visual.queue_free()
			devices.erase(entry)

func device_hits(entry: Dictionary, radius: float, amount: float, source: String, bonus: Dictionary = {}) -> Array:
	# Everyone under the mechanism, plus whoever it holds, takes the hit with the execution bonus.
	var struck: Array = []
	for id in enemies.keys():
		var gap: Vector3 = enemies[id].body.position - entry.center
		gap.y = 0.0
		if gap.length() <= radius + 0.2 * float(enemies[id].size) or id in entry.caged or id == entry.locked:
			struck.append(id)
	for id in struck:
		if enemies.has(id):
			var hit_amount: float = amount * execute_factor(id, id in entry.get("marked", [])) * float(bonus.get(id, 1.0))
			if source == "guillotine" and gear_total("rule:guillotine_execute") > 0:
				hit_amount *= hinge_execution(id)
				if not enemies.has(id):
					continue
			strike(id, hit_amount, false, "witch", source)
	return struck.filter(func(id): return enemies.has(id))

func hinge_execution(id: String) -> float:
	# Unique 녹슨 단두대 경첩: a falling blade beheads a weakened ordinary or champion enemy outright;
	# elites and bosses that low only take a doubled cut. Returns the factor for the normal hit.
	var rule: Dictionary = items.data.rule_values
	var enemy: Dictionary = enemies[id]
	if float(enemy.hp) > float(enemy.max_hp) * float(rule.execute_hp_ratio):
		return 1.0
	if enemy.grade not in rule.execute_grades or config.enemy_types[enemy.kind].has("boss"):
		return float(rule.execute_tough_factor)
	var at: Vector3 = enemy.body.position
	var size: float = float(enemy.size)
	probe.strike("guillotine", "crit", damage_enemy(id, float(enemy.hp) + 1.0))
	spawn_vfx().impact(at + Vector3.UP * 0.85 * size, Vector3.UP, "guillotine", true, map.ground_y(at))
	play_sfx("crit_hit", 0.55)
	return 0.0

func device_thud(entry: Dictionary, shake: float, cue: String) -> void:
	shake_time = maxf(shake_time, 0.12 * shake)
	play_sfx(cue, 0.7)

func execute_factor(id: String, marked: bool = false) -> float:
	# Executions (03 §4) hit harder the more HP the enemy has lost, and once more if a tool has
	# marked it (slow, shred or bleed: one is enough, since switching tools is costly) or the winch
	# holds it. The devices' own stun and bind never count, so the bonus rewards setting it up first.
	# marked: a caged or clamped enemy keeps the mark it had when it was caught.
	var enemy: Dictionary = enemies[id]
	var plan: Dictionary = config.execution
	var lost: float = clampf(1.0 - float(enemy.hp) / maxf(1.0, float(enemy.max_hp)), 0.0, 1.0)
	return 1.0 + float(plan.low_hp_bonus) * lost + (float(plan.debuff_bonus) if marked or tool_marked(enemy) else 0.0)

func tool_marked(enemy: Dictionary) -> bool:
	for key in config.execution.tool_debuffs:
		if key == "bleed" and not enemy.bleeds.is_empty():
			return true
		if key != "bleed" and float(enemy.get(key, 0.0)) > 0:
			return true
	return false

func catch_marks(entry: Dictionary, ids: Array) -> void:
	# Remember who carried a tool mark when the device caught them, for the rest of its run.
	for id in ids:
		if enemies.has(id) and tool_marked(enemies[id]) and id not in entry.marked:
			entry.marked.append(id)

func restrain(id: String, kind: String, seconds: float) -> bool:
	# Stun (press) or bind (winch, cage, lock): it stops, loses its windup and its charge.
	# Bosses keep their patterns and are never held.
	if not enemies.has(id):
		return false
	var enemy: Dictionary = enemies[id]
	if config.enemy_types[enemy.kind].has("boss"):
		return false
	# Stun and bind options lengthen every hold she sets (devices release their cages themselves).
	seconds *= 1.0 + gear_total("control_pct") / 100.0
	enemy[kind] = maxf(float(enemy.get(kind, 0.0)), seconds)
	enemy.charging = 0.0
	interrupt_attack(enemy)
	return true

func release_hold(ids: Array) -> void:
	for id in ids:
		if enemies.has(id):
			enemies[id].bound = 0.0

func haul(id: String, to: Vector3, seconds: float, share: float = 1.0) -> void:
	# Drags the enemy along the floor toward a point (the knockback slide, pointed the other way).
	var enemy: Dictionary = enemies[id]
	var gap: Vector3 = to - enemy.body.position
	gap.y = 0.0
	var distance: float = gap.length() * share
	if distance < 0.05:
		return
	enemy.knockback_dir = gap.normalized()
	enemy.knockback_left = distance
	enemy.knockback_speed = distance / maxf(0.05, seconds)

func press_stun_seconds(base: float) -> float:
	return base + float(rules.skills.hydraulic_press.stun_per_level) * (float(config.hydraulic_press_level) - 1.0)

func executor_synergy(part: String) -> float:
	# The executor's press and saw grow with the press and guillotine the witch has studied.
	return 1.0 + float(rules.skills.compound_executor.synergy_per_level) * maxf(0.0, float(config[part + "_level"]) - 1.0)

func lock_target(entry: Dictionary) -> String:
	# The lock clamps close on the nearest enemy that can be held and drag it under the blade.
	var plan: Dictionary = entry.plan
	var best := ""
	var near := float(plan.lock_radius)
	for id in enemies:
		var gap: Vector3 = enemies[id].body.position - entry.center
		gap.y = 0.0
		if gap.length() <= near and not config.enemy_types[enemies[id].kind].has("boss"):
			near = gap.length()
			best = id
	if best != "":
		restrain(best, "bound", float(plan.drop_at) + float(plan.drop_seconds) + 0.2)
		haul(best, entry.center, float(plan.clamp_seconds))
	return best

func cage_enemies(entry: Dictionary) -> Array:
	# The gates shut on everyone inside; each is held near the middle until the gates reopen.
	var plan: Dictionary = entry.plan
	var caged: Array = []
	for id in enemies:
		var gap: Vector3 = enemies[id].body.position - entry.center
		gap.y = 0.0
		if gap.length() <= float(plan.trap_radius) and restrain(id, "bound", float(plan.end_at)):
			caged.append(id)
			if gap.length() > float(plan.hold_radius):
				haul(id, entry.center + gap.normalized() * float(plan.hold_radius), float(plan.gate_seconds))
	return caged

func fire_winch(event: Dictionary, direction: Vector3) -> void:
	# Restraint winch (03 drive II): hooks bite the target (and, with the multi-strand nodes, those
	# around it), then reel them in to her or bind them where they stand.
	var plan := device_plan("restraint_winch")
	var first = event.get("target_enemy")
	if first == null or not enemies.has(first):
		cancel_summon_assemblies("target_lost")
		return
	var targets: Array = [first]
	if int(plan.targets) > 1:
		var around_first: Vector3 = enemies[first].body.position
		var others: Array = enemies.keys().filter(func(id): return id != first and enemies[id].body.position.distance_to(around_first) <= float(plan.gather_radius))
		others.sort_custom(func(a, b): return enemies[a].body.position.distance_to(around_first) < enemies[b].body.position.distance_to(around_first))
		targets.append_array(others.slice(0, int(plan.targets) - 1))
	var visual = device_assembly
	device_assembly = null
	if not is_instance_valid(visual):
		visual = begin_device_visual("restraint_winch", cast_target(event), direction)
	visual.activate()
	var spots := {}
	for id in targets:
		spots[id] = enemies[id].body.position
	var entry := {"visual": visual, "targets": targets, "spots": spots, "time": 0.0, "plan": plan, "fired": {}, "direction": direction}
	winches.append(entry)
	last_device = entry
	play_sfx("staff_swing", 0.8)

func tick_winches(dt: float) -> void:
	for entry in winches.duplicate():
		entry.time += dt
		var plan: Dictionary = entry.plan
		if fire_once(entry, "hook", float(plan.fly_seconds)):
			hook_targets(entry)
		var points: Array = []
		for id in entry.targets:
			if enemies.has(id):
				entry.spots[id] = enemies[id].body.position
			points.append(entry.spots[id])
		entry.visual.work(entry.time, points)
		if entry.visual.finished(entry.time):
			entry.visual.queue_free()
			winches.erase(entry)

func hook_targets(entry: Dictionary) -> void:
	var plan: Dictionary = entry.plan
	var bind: float = float(plan.bind_seconds) + float(plan.bind_per_level) * (float(config.restraint_winch_level) - 1.0)
	var count: int = entry.targets.size()
	var across: Vector3 = Vector3(entry.direction).cross(Vector3.UP)
	for i in count:
		var id: String = entry.targets[i]
		if not enemies.has(id):
			continue
		strike(id, float(plan.hook_damage), false, "witch", "restraint_winch")
		if not enemies.has(id):
			continue
		var enemy: Dictionary = enemies[id]
		if config.enemy_types[enemy.kind].has("boss"):
			# A boss is too heavy to drag or tie down; the line only slows it.
			enemy.slow = maxf(float(enemy.slow), float(plan.boss_slow_seconds))
			continue
		if plan.pull:
			restrain(id, "bound", float(plan.pull_seconds) + bind)
			# The winch's bind is a setup for the executions, unlike the devices' own holds.
			enemy.winched = float(plan.pull_seconds) + bind
			var landing: Vector3 = player.position + Vector3(entry.direction) * float(plan.stop_distance) + across * (i - (count - 1) / 2.0) * 0.8
			haul(id, landing, float(plan.pull_seconds), float(plan.heavy_pull) if enemy.heavy else 1.0)
		else:
			restrain(id, "bound", bind)
			enemy.winched = bind
	play_sfx("staff_hit", 0.8)

func clear_devices() -> void:
	for entry in devices:
		release_hold(entry.caged + [entry.locked])
		if is_instance_valid(entry.visual):
			entry.visual.dismiss()
	devices.clear()
	for entry in winches:
		if is_instance_valid(entry.visual):
			entry.visual.dismiss()
	winches.clear()

func exo_level() -> float:
	return float(config.exoskeleton_level)

func exo_plan() -> Dictionary:
	# The frame node (1 point, one of): guard doubles the defence and halves the damage bonus,
	# drive doubles the damage bonus, trims tool upkeep and halves the defence.
	return rules.skills.exoskeleton.nodes[config.exoskeleton_node]

func exo_active() -> bool:
	# A passive since 2026-11-05: once learned it is worn while a tool is transformed, never on
	# the bare staff, and costs nothing beyond the tool's own upkeep.
	return exo_level() >= 1 and not state.is_empty() and state.active_tool != null and hp > 0

func exo_tool_bonus() -> float:
	var frame: Dictionary = rules.skills.exoskeleton
	return (float(frame.tool_damage) + float(frame.tool_damage_per_level) * (exo_level() - 1.0)) * float(exo_plan().get("damage_factor", 1.0))

func exo_armor() -> float:
	var frame: Dictionary = rules.skills.exoskeleton
	return (float(frame.armor_base) + float(frame.armor_per_level) * (exo_level() - 1.0)) * float(exo_plan().get("armor_factor", 1.0))

func exo_stun_cut() -> float:
	# Every fifth level cuts the witch's hit stagger once more while it is worn.
	var frame: Dictionary = rules.skills.exoskeleton
	return float(frame.stun_cut) * floorf(exo_level() / float(frame.stun_cut_every)) * float(exo_plan().get("stun_cut_factor", 1.0))

func exo_upkeep_cut() -> float:
	return float(exo_plan().get("upkeep_cut", 0.0)) if exo_level() >= 1 else 0.0

func exo_tool_factor() -> float:
	return 1.0 + exo_tool_bonus() if exo_active() else 1.0

func exo_stun_factor() -> float:
	return maxf(0.2, 1.0 - exo_stun_cut()) if exo_active() else 1.0

func show_exo_visual() -> void:
	# The frame goes on with the tool and stays while it runs.
	if not player_visual.loaded_ok:
		return
	if not is_instance_valid(exo_visual):
		exo_visual = ExoVisual.new()
		player_visual.runtime.skeleton.add_child(exo_visual)
		if not exo_visual.initialize(player_visual.runtime.skeleton):
			exo_visual.queue_free()
			exo_visual = null
			return
		exo_visual.prepare()
		exo_visual.wear(player_visual)

func sync_exo_visual(dt: float) -> void:
	# After the body pose: the frame fades in with the tool, out when it is put away, and follows
	# the current motion.
	if exo_active() and not is_instance_valid(exo_visual):
		show_exo_visual()
	if not is_instance_valid(exo_visual):
		return
	var target := 1.0 if exo_active() else 0.0
	exo_visual.set_shown(move_toward(exo_visual.shown, target, dt / ExoVisual.FADE_SECONDS))
	var phase: float = player_visual.clip_time / maxf(player_visual.clip_length, 0.000001)
	exo_visual.sync_pose_for_motion(ExoVisual.motion_for(player_visual), phase)
	if exo_visual.shown <= 0.0 and target <= 0.0:
		exo_visual.take_off(player_visual)
		exo_visual.queue_free()
		exo_visual = null

func roll_keg(target: Vector3, direction: Vector3) -> void:
	# Powder keg (03 §3, firearm area I): it rolls along the floor toward the aim and bursts on the
	# first enemy it touches, at a wall, or where she aimed (at least min_roll, at most its range).
	var skill: Dictionary = rules.skills.powder_keg
	if not is_instance_valid(keg_assembly):
		begin_keg_visual(direction)
	var visual: Node3D = keg_assembly
	keg_assembly = null
	visual.launch()
	var flat: Vector3 = target - player.position
	flat.y = 0.0
	var reach: float = clampf(flat.length(), float(skill.min_roll), float(skill.range)) - float(skill.start_offset)
	kegs.append({"visual": visual, "position": visual.global_position, "direction": direction, "left": reach, "total": reach, "rolled": 0.0})
	play_sfx("summon_arrive", 0.8)

func keg_contact(at: Vector3) -> String:
	# The first enemy whose body the rolling drum runs into.
	var reach: float = float(rules.skills.powder_keg.contact_radius)
	for id in enemies:
		var pos: Vector3 = enemies[id].body.position
		if Vector2(pos.x - at.x, pos.z - at.z).length() <= reach + 0.4 * float(enemies[id].size):
			return id
	return ""

func tick_kegs(dt: float) -> void:
	var speed: float = float(rules.skills.powder_keg.roll_speed)
	for keg in kegs.duplicate():
		var travel: float = minf(speed * dt, float(keg.left))
		var next: Vector3 = keg.position + keg.direction * travel
		var reason := ""
		if map.walkable(next):
			keg.position = map.grounded(next)
			keg.left -= travel
			keg.rolled += travel
			if gear_total("rule:fuse_trail") > 0:
				# Unique 불붙은 심지 다발: the lit drum leaves a line of small fires behind it.
				var rule: Dictionary = items.data.rule_values
				keg.trail = float(keg.get("trail", 0.0)) + travel
				while keg.trail >= float(rule.fuse_fire_every):
					keg.trail -= float(rule.fuse_fire_every)
					start_fire(keg.position, {"fire_radius": rule.fuse_fire_radius, "fire_seconds": rule.fuse_fire_seconds,
						"fire_damage": rule.fuse_fire_damage, "fire_tick": rule.fuse_fire_tick}, "powder_keg")
		else:
			reason = "wall"
		if is_instance_valid(keg.visual):
			keg.visual.roll_to(keg.position, keg.rolled, keg.left / maxf(0.0001, keg.total))
		if keg_contact(keg.position) != "":
			reason = "enemy"
		elif reason == "" and keg.left <= 0.0001:
			reason = "end"
		if reason != "":
			burst_keg(keg, reason)

func burst_keg(keg: Dictionary, reason: String) -> void:
	# The blast catches every enemy in its radius that open floor connects it to; no hit roll.
	kegs.erase(keg)
	var skill: Dictionary = rules.skills.powder_keg
	var at: Vector3 = keg.position
	var radius: float = float(skill.blast_radius)
	var damage: float = float(skill.blast_damage)
	if gear_total("rule:fuse_trail") > 0:
		damage *= float(items.data.rule_values.fuse_blast_factor)
	var struck: Array = []
	for id in enemies.keys():
		var pos: Vector3 = enemies[id].body.position
		if Vector2(pos.x - at.x, pos.z - at.z).length() <= radius and map.sees(at, pos):
			struck.append(id)
			strike(id, damage, false, "witch", "powder_keg")
	if is_instance_valid(keg.visual):
		keg.visual.burst()
	spawn_vfx().blast(at, radius, map.ground_y(at), false)
	shake_time = maxf(shake_time, 0.12)
	play_sfx("automaton_explode", 0.7)
	last_keg = {"at": at, "reason": reason, "rolled": keg.rolled, "struck": struck}

func clear_kegs() -> void:
	for keg in kegs:
		if is_instance_valid(keg.visual):
			keg.visual.dismiss()
	kegs.clear()

func strike_point(target: Vector3, direction: Vector3, reach: float) -> Vector3:
	# Where an offscreen gun aims: the cursor, at most its range away, on open floor.
	var flat: Vector3 = target - player.position
	flat.y = 0.0
	var center: Vector3 = player.position + direction * minf(flat.length(), reach)
	if not map.walkable(center):
		center = map.snap(center)
	return map.grounded(center)

func witch_amount(amount: float, source: String) -> float:
	# Her damage before any roll: power, gear and skill level, as strike() applies them. The attack
	# roll comes on impact (strike_amount); burning ground takes the middle of her range.
	return amount * build.power_factor() * (1.0 + gear_total("damage_pct") / 100.0) * skill_level_factor(source)

func mark_target(center: Vector3, radius: float, seconds: float) -> void:
	# A gold ring where her own barrage will land, gone when the last shell is down.
	var ring: MeshInstance3D = Shape.ring(world, center + Vector3(0, 0.05, 0), radius, Color(0.85, 0.72, 0.48, 0.8), 0.05)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.append({"node": ring, "life": seconds, "grow": false})

func send_shell(kind: String, at: Vector3, delay: float, flight: float, impact: Dictionary, burst_height: float = 0.0) -> void:
	# The shell comes in from far up and off to the side, beyond the screen, and lands after delay.
	var end: Vector3 = at + Vector3.UP * burst_height
	var start: Vector3 = end + Vector3(-9.0, 24.0, -6.0)
	var visual: Node3D = null
	var trail: Node3D = null
	if kind != "":
		visual = IncomingShell.new()
		world.add_child(visual)
		visual.initialize(kind, start, end)
		trail = spawn_vfx()
	shells.append({"visual": visual, "trail": trail, "start": start, "end": end, "left": delay, "flight": flight, "at": at, "impact": impact})

func call_artillery(target: Vector3, direction: Vector3) -> void:
	# Rocket barrage (03 §3, firearm IV): after a short wait the shells come in one by one, at
	# uneven moments, scattered over a wide circle. The node picks the shell: high explosive,
	# cluster (bursts overhead into bomblets over a wider spread) or white phosphorus (sets fires).
	var skill: Dictionary = rules.skills.artillery
	var shell: Dictionary = skill.nodes[config.artillery_node]
	var center := strike_point(target, direction, float(skill.range))
	var count: int = int(skill.shells)
	var spread: float = float(shell.get("spread_radius", skill.spread_radius))
	var last := 0.0
	for i in count:
		# A fixed scatter (not the combat RNG): golden-angle spokes, uneven landing times.
		var angle: float = i * 2.39996 + 0.7
		var spot: Vector3 = center + Vector3(cos(angle), 0, sin(angle)) * spread * sqrt((i + 0.5) / count)
		spot = map.grounded(spot) if map.walkable(spot) else center
		var delay: float = float(skill.first_delay) + float(skill.barrage_seconds) * clampf((i + 0.45 * sin(i * 12.9898)) / count, 0.0, 1.0)
		last = maxf(last, delay)
		var impact := {"kind": "cluster" if shell.has("bomblets") else "blast", "radius": float(shell.blast_radius), "damage": witch_amount(float(shell.shot_damage), "artillery"), "source": "artillery", "shell": shell}
		send_shell("artillery", spot, delay, float(skill.flight_seconds), impact, float(shell.get("airburst_height", 0.0)))
	mark_target(center, spread + float(shell.get("bomblet_spread", shell.blast_radius)), last)
	last_impact = {"skill": "artillery", "center": center, "shells": count}
	play_sfx("shotgun_fire", 0.45, -8.0)

func call_naval_gun(target: Vector3, direction: Vector3) -> void:
	# Heavy naval gun (03 §3, firearm IV): one slow, heavy shell from far off, telegraphed by its
	# ring. Its node trades area for weight: a wide burst that leaves the ground burning, or a
	# narrow piercing round for one strong enemy.
	var skill: Dictionary = rules.skills.naval_gun
	var shell: Dictionary = skill.nodes[config.naval_gun_node]
	var center := strike_point(target, direction, float(skill.range))
	var impact := {"kind": "blast", "radius": float(shell.blast_radius), "damage": witch_amount(float(shell.shot_damage), "naval_gun"), "source": "naval_gun", "shell": shell, "heavy": true}
	send_shell("naval", center, float(skill.delay), float(skill.flight_seconds), impact)
	mark_target(center, float(shell.blast_radius), float(skill.delay))
	last_impact = {"skill": "naval_gun", "center": center}
	play_sfx("shotgun_fire", 0.4, -6.0)

func tick_shells(dt: float) -> void:
	for shell in shells.duplicate():
		shell.left = float(shell.left) - dt
		if is_instance_valid(shell.visual) and shell.left <= shell.flight:
			var before: Vector3 = shell.visual.global_position if shell.visual.visible else shell.start
			shell.visual.place(1.0 - maxf(0.0, shell.left) / float(shell.flight))
			if is_instance_valid(shell.trail):
				shell.trail.streak(before, shell.visual.global_position, 0.06, Color(1.0, 0.85, 0.6, 0.8), 0.2)
				# Smoke every third frame is enough for the trail and keeps a barrage's particles down.
				if Engine.get_physics_frames() % 3 == 0:
					shell.trail.puff(before, Vector3.ZERO, 0.18, 0.6, Color(0.55, 0.55, 0.52, 0.35), 0.6, 0.1)
		if shell.left > 0:
			continue
		shells.erase(shell)
		if is_instance_valid(shell.visual):
			shell.visual.queue_free()
		land_shell(shell)

func land_shell(shell: Dictionary) -> void:
	var impact: Dictionary = shell.impact
	var at: Vector3 = shell.at
	if impact.kind == "cluster":
		# Bursts overhead: bomblets rain over a wider patch, each a small blast.
		var burst: Vector3 = shell.end
		var fx := spawn_vfx()
		# The bomblets draw into this same effect, so it must outlive their fall.
		fx.entry.life = maxf(float(fx.entry.life), 1.2)
		fx.flash(burst, 1.2, Color(1.0, 0.75, 0.4), 0.18, 1.0)
		fx.sparks(burst, Vector3.DOWN, 18, 6.0, 1.2, Color(1.0, 0.8, 0.45), 0.4, 0.02, map.ground_y(at))
		var bomblets: int = int(impact.shell.bomblets)
		for i in bomblets:
			var angle: float = TAU * i / bomblets + float(shell.end.x) * 1.7
			var spot: Vector3 = at + Vector3(cos(angle), 0, sin(angle)) * float(impact.shell.bomblet_spread) * (0.45 + 0.55 * fposmod(i * 0.618, 1.0))
			spot = map.grounded(spot) if map.walkable(spot) else at
			fx.streak(burst, spot, 0.04, Color(1.0, 0.7, 0.35, 0.7), 0.25)
			send_shell("", spot, 0.22 + 0.03 * i, 0.0, {"kind": "blast", "radius": impact.radius, "damage": impact.damage, "source": impact.source, "shell": {}, "small": true, "fx": fx, "first": i == 0})
		play_sfx("shotgun_fire", 0.7, -4.0)
		return
	var struck: Array = []
	for id in enemies.keys():
		var pos: Vector3 = enemies[id].body.position
		if Vector2(pos.x - at.x, pos.z - at.z).length() <= float(impact.radius) + 0.3 * float(enemies[id].size) and map.sees(at, pos):
			struck.append(id)
			strike_amount(id, float(impact.damage), impact.source)
	var heavy: bool = impact.get("heavy", false)
	var small: bool = impact.get("small", false)
	if small and is_instance_valid(impact.get("fx")):
		impact.fx.small_blast(at, float(impact.radius), map.ground_y(at))
	else:
		spawn_vfx().blast(at, float(impact.radius), map.ground_y(at), heavy)
	shake_time = maxf(shake_time, 0.3 if heavy else (0.05 if small else 0.12))
	# A shell's bomblets crackle under one sound, not one each.
	if not small or impact.get("first", false):
		play_sfx("automaton_explode", 0.5 if heavy else (1.1 if small else 0.75))
	if impact.shell.has("fire_radius"):
		start_fire(at, impact.shell, impact.source)
	last_impact = {"at": at, "struck": struck, "source": impact.source, "radius": impact.radius}

func strike_amount(id: String, amount: float, source: String) -> void:
	# A blast already scaled by her power, gear and skill level: no hit roll, its own crit roll.
	if not enemies.has(id):
		return
	var crit: bool = force_rolls.get("crit", combat_rng.randf() < crit_chance("witch"))
	var dealt: float = damage_enemy(id, amount * attack_factor(roll_attack(crit)) * passive_factor(source) * (config.crit_multiplier if crit else 1.0))
	probe.strike(source, "crit" if crit else "hit", dealt)
	leech(dealt)

func leech(dealt: float) -> void:
	# Life and mana leech (04 §4.3): a share of what her own direct hit actually removed. Bleed,
	# burning ground and summon hits never pass here, and neither does a kill's overkill.
	if hp <= 0 or dealt <= 0:
		return
	hp = minf(config.max_hp, hp + dealt * gear_total("life_leech_pct") / 100.0)
	state.mana = minf(state.max_mana, state.mana + dealt * gear_total("mana_leech_pct") / 100.0)

func start_fire(at: Vector3, shell: Dictionary, source: String) -> void:
	var patch: Node3D = FirePatch.new()
	world.add_child(patch)
	patch.initialize(at, float(shell.fire_radius))
	fires.append({"center": at, "radius": float(shell.fire_radius), "left": float(shell.fire_seconds), "total": float(shell.fire_seconds),
		"damage": witch_amount(float(shell.fire_damage), source) * attack_factor((attack_range().x + attack_range().y) / 2.0), "tick": float(shell.fire_tick), "patch": patch})

func tick_fires(dt: float) -> void:
	# Each enemy standing in fire burns once per tick, from the strongest fire it stands in. Burning
	# is not a direct hit: no roll, no crit, no flinch, like bleed.
	for fire in fires.duplicate():
		fire.left = float(fire.left) - dt
		if is_instance_valid(fire.patch):
			fire.patch.advance(dt)
			fire.patch.show_state(maxf(0.0, fire.left), fire.total)
		if fire.left <= 0:
			if is_instance_valid(fire.patch):
				fire.patch.queue_free()
			fires.erase(fire)
	if fires.is_empty():
		burn_clock = 0.0
		return
	burn_clock += dt
	var tick: float = float(fires[0].tick)
	if burn_clock < tick:
		return
	burn_clock -= tick
	for id in enemies.keys():
		if not enemies.has(id):
			continue
		var pos: Vector3 = enemies[id].body.position
		var amount := 0.0
		for fire in fires:
			if Vector2(pos.x - fire.center.x, pos.z - fire.center.z).length() <= float(fire.radius):
				amount = maxf(amount, float(fire.damage))
		if amount > 0:
			probe.burn(damage_enemy(id, amount, false))

func clear_barrage() -> void:
	for shell in shells:
		if is_instance_valid(shell.visual):
			shell.visual.queue_free()
	shells.clear()
	for fire in fires:
		if is_instance_valid(fire.patch):
			fire.patch.queue_free()
	fires.clear()

func smoke_seconds() -> float:
	var skill: Dictionary = rules.skills.smoke_launcher
	return float(skill.smoke_seconds) + float(skill.seconds_per_level) * (float(config.smoke_launcher_level) - 1.0)

func launch_smoke(target: Vector3, direction: Vector3) -> void:
	# Smoke launcher (03 §3, firearm III): six canisters land around the aimed point (its range at
	# most) and raise a cloud once they are down. Her own shots and her summons see through it.
	var skill: Dictionary = rules.skills.smoke_launcher
	var flat: Vector3 = target - player.position
	flat.y = 0.0
	var center: Vector3 = player.position + direction * minf(flat.length(), float(skill.range))
	if not map.walkable(center):
		center = map.snap(center)
	center = map.grounded(center)
	var landings: Array[Vector3] = []
	for i in 6:
		var spot: Vector3 = center + Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0)) * float(skill.canister_spread)
		landings.append(map.grounded(spot) if map.walkable(spot) else center)
	if not is_instance_valid(smoke_assembly):
		smoke_assembly = SmokeLauncher.new()
		world.add_child(smoke_assembly)
		smoke_assembly.position = map.grounded(player.position + direction.cross(Vector3.UP) * 0.75)
		smoke_assembly.look_at(smoke_assembly.global_position + direction, Vector3.UP)
		smoke_assembly.initialize(self)
	var seconds := smoke_seconds()
	smoke_assembly.fire(landings, float(skill.flight_seconds), seconds)
	smoke_assembly = null
	var cloud: Node3D = SmokeCloud.new()
	world.add_child(cloud)
	cloud.initialize(center, float(skill.smoke_radius))
	smokes.append({"center": center, "radius": float(skill.smoke_radius), "wait": float(skill.flight_seconds), "left": seconds, "total": seconds, "cloud": cloud})
	play_sfx("shotgun_fire", 0.55, -4.0)

func tick_smokes(dt: float) -> void:
	for smoke in smokes.duplicate():
		if smoke.wait > 0:
			smoke.wait = maxf(0.0, float(smoke.wait) - dt)
		else:
			smoke.left = float(smoke.left) - dt
		if is_instance_valid(smoke.cloud):
			smoke.cloud.advance(dt)
			smoke.cloud.show_state(smoke.wait, maxf(0.0, smoke.left), smoke.total)
		if smoke.left <= 0:
			if is_instance_valid(smoke.cloud):
				smoke.cloud.queue_free()
			smokes.erase(smoke)

func hidden_between(a: Vector3, b: Vector3) -> bool:
	# True when a standing cloud covers either end or the line between them (on the floor plan).
	for smoke in smokes:
		if smoke.wait > 0 or smoke.left <= 0:
			continue
		var c := Vector2(smoke.center.x, smoke.center.z)
		var from := Vector2(a.x, a.z)
		var to := Vector2(b.x, b.z)
		var line: Vector2 = to - from
		var along: float = clampf((c - from).dot(line) / maxf(line.length_squared(), 0.0001), 0.0, 1.0)
		if c.distance_to(from + line * along) <= float(smoke.radius):
			return true
	return false

func blinded(enemy: Dictionary) -> bool:
	# Bosses keep their own patterns and see through the smoke.
	return hp > 0 and not config.enemy_types[enemy.kind].has("boss") and hidden_between(enemy.body.position, player.position)

func gatling_round() -> Dictionary:
	return rules.skills.gatling.nodes[config.gatling_node]

func gatling_interval() -> float:
	# Rounds follow attack speed: the stream is her basic fire, the spin-up cast is the machine.
	var base: float = float(rules.skills.gatling.fire_seconds)
	return motion_seconds(base, base * config.min_cast_ratio, config.attack_speed_k, config.attack_speed_score) * fire_interval_factor()

func tool_speed(base: float) -> float:
	# Tool attacks are attacks: their motions and hit intervals follow attack speed.
	return motion_seconds(base, base * config.min_cast_ratio, config.attack_speed_k, config.attack_speed_score)

func tool_attack_plan(skill_id: String, tool) -> Dictionary:
	# The tool's own numbers for this attack, with the chosen node's factors on top.
	var skill: Dictionary = rules.skills[skill_id]
	var plan: Dictionary = (skill.tools.get(tool, {}) as Dictionary).duplicate(true)
	plan.merge(skill.nodes[config[skill_id + "_node"]], true)
	return plan

func tool_attack_seconds(skill_id: String, tool) -> float:
	var skill: Dictionary = rules.skills[skill_id]
	return tool_speed(float(skill.enter_seconds) if skill_id == "focus_attack" else float(tool_attack_plan(skill_id, tool).seconds))

func tool_hit_damage(skill_id: String, plan: Dictionary) -> float:
	# The exoskeleton drives every tool attack harder; the skill's level and damage node add on.
	return float(plan.damage) * float(plan.get("damage_factor", 1.0)) * exo_tool_factor() * skill_level_factor(skill_id)

func tool_strike(id: String, tool: String, damage: float, plan: Dictionary, skill_id: String) -> String:
	# One tool hit rolls to hit like the basic attack and, on a hit, leaves the tool's own mark:
	# slow (bolt cutter), shred (grinder) or bleed (chainsaw). The debuff node lengthens slow and
	# shred and adds bleed stacks. The log keeps it apart from the tool's basic attacks under
	# "<skill>:<tool>"; damage rules still treat the tool as its source.
	var result := "miss"
	var label := skill_id + ":" + tool
	if tool == "chainsaw":
		result = strike(id, damage, true, "witch", tool, "", label)
		if result != "miss":
			for i in int(plan.get("bleed_stacks", 1)):
				if enemies.has(id):
					add_bleed(id)
		return result
	var debuff: String = rules.skills[tool].debuff
	var before: float = enemies[id][debuff]
	enemies[id][debuff] = maxf(before, float(rules.skills[tool].debuff_seconds) * float(plan.get("debuff_factor", 1.0)))
	result = strike(id, damage, true, "witch", tool, "", label)
	if result == "miss" and enemies.has(id):
		enemies[id][debuff] = before
	return result

func tool_hit_sound(tool: String) -> void:
	match tool:
		"bolt_cutter": play_sfx("bolt_cutter_cut", 0.8)
		"grinder": play_sfx("grinder_hit", 1.55)
		"chainsaw": play_sfx("chainsaw_cut", 1.05)

func channel_slot(skill_id: String) -> String:
	# The key that holds the channel: the one pressed, else the first bound to it.
	var slot: String = hold.get("slot", "")
	if state.bindings.get(slot) != skill_id:
		slot = ""
		for key in rules.SLOTS:
			if state.bindings[key] == skill_id and slot == "":
				slot = key
	return slot

func start_tool_channel(tool, direction: Vector3) -> void:
	# Focus attack (03 §2): while its key is held she stands and strikes faster than her attack
	# speed, piling the tool's mark onto one enemy in front. The bolt cutter thrusts once per loop,
	# at the jaws' snap; the grinder and chainsaw hold the blade in and cut on their own clock.
	if tool == null:
		return
	var plan := tool_attack_plan("focus_attack", tool)
	var period: float = tool_speed(float(plan.interval))
	var loop: float = period if plan.has("hit_phase") else tool_speed(float(plan.loop_seconds))
	moving = false
	move_marker.visible = false
	channel = {"skill": "focus_attack", "tool": tool, "slot": channel_slot("focus_attack"), "direction": direction,
		"time": 0.0, "period": period, "loop": loop, "fire_left": period * float(plan.get("hit_phase", 0.5)), "hits": 0, "plan": plan}
	probe.channel_begin("focus_attack:" + str(tool))
	player_visual.begin_focus_loop(tool, loop)

func tick_tool_channel(dt: float) -> void:
	var skill: Dictionary = rules.skills.focus_attack
	if state.active_tool != channel.tool:
		# Switching or losing the tool ends the stream.
		stop_channel(true)
		return
	var cost: float = float(skill.channel_mana_per_second) * dt
	if state.mana + rules.EPS < cost:
		stop_channel(true)
		show_message("마나 부족 · 공격 중지")
		return
	state.mana = maxf(0.0, state.mana - cost)
	probe.record([{"type": "tool_upkeep", "tool": "focus_attack", "amount": cost}])
	probe.channel_time("focus_attack:" + str(channel.tool), dt, cost)
	var cursor := field_cursor()
	var aim = null
	if cursor.get("enemy_id") != null and enemies.has(cursor.enemy_id):
		aim = enemies[cursor.enemy_id].body.position
	elif cursor.get("ground") != null:
		aim = map.grounded(point(cursor.ground))
	if aim != null:
		var flat: Vector3 = aim - player.position
		flat.y = 0.0
		if flat.length() > 0.05:
			var wanted: Vector3 = flat.normalized()
			var plan: Dictionary = channel.plan
			if plan.has("turn_degrees_per_second"):
				# The chainsaw cuts slowly: she turns the blade after the cursor at a limited rate.
				var current: Vector3 = channel.direction
				var turn: float = current.signed_angle_to(wanted, Vector3.UP)
				var step: float = deg_to_rad(float(plan.turn_degrees_per_second)) * dt
				channel.direction = current.rotated(Vector3.UP, clampf(turn, -step, step)).normalized()
			else:
				channel.direction = wanted
	var direction: Vector3 = channel.direction
	player_model.look_at(player.position + direction)
	channel.time = float(channel.time) + dt
	player_visual.set_focus_loop_phase(float(channel.time) / float(channel.loop))
	channel.fire_left = float(channel.fire_left) - dt
	while not channel.is_empty() and channel.fire_left <= 0:
		focus_hit(direction)
		channel.fire_left = float(channel.fire_left) + float(channel.period)

func focus_hit(direction: Vector3) -> void:
	# The nearest enemy in front, in sight and in reach, takes the hit; an empty swing is silent.
	var tool: String = channel.tool
	var best: String = nearest_enemy(player.position, float(rules.skills.focus_attack.range), direction, 0.2, false, true)
	channel.hits = int(channel.hits) + 1
	if best == "":
		last_tool_attack = {"skill": "focus_attack", "tool": tool, "target": "", "result": "miss", "hits": channel.hits}
		return
	var damage := tool_hit_damage("focus_attack", channel.plan)
	var result := tool_strike(best, tool, damage, channel.plan, "focus_attack")
	if result != "miss":
		tool_hit_sound(tool)
		# Each landed bolt cutter thrust drags one more enemy in, like a basic attack hit.
		if tool == "bolt_cutter" and gear_total("rule:chain_cut") > 0:
			chain_cut(best, damage, [], "focus_attack:bolt_cutter")
	last_tool_attack = {"skill": "focus_attack", "tool": tool, "target": best, "result": result, "hits": channel.hits}

func tool_area(tool, direction: Vector3) -> void:
	# Area attack (03 §2): the bolt cutter's enlarged blade cuts a long, narrow fan at once; the
	# grinder's half circle and the chainsaw's full turn strike each enemy as the blade passes it.
	if tool == null:
		return
	var plan := tool_attack_plan("area_attack", tool)
	var reach: float = float(plan.reach) * float(plan.get("reach_factor", 1.0))
	play_sfx("staff_swing", 0.8)
	if plan.has("sweep"):
		sweep = {"tool": tool, "plan": plan, "direction": direction, "phase": float(plan.release_ratio),
			"total": tool_attack_seconds("area_attack", tool), "reach": reach, "struck": []}
		last_tool_attack = {"skill": "area_attack", "tool": tool, "struck": [], "results": {}}
		tick_sweep(0.0)
		return
	var half: float = deg_to_rad(float(plan.half_angle_degrees))
	var struck: Array = []
	for id in enemies.keys():
		var delta: Vector3 = enemies[id].body.position - player.position
		delta.y = 0.0
		if delta.length() <= reach + 0.3 * float(enemies[id].size) and absf(direction.signed_angle_to(delta, Vector3.UP)) <= half and map.sees(player.position, enemies[id].body.position):
			struck.append(id)
	var results := {}
	var damage := tool_hit_damage("area_attack", plan)
	for id in struck:
		if enemies.has(id):
			results[id] = tool_strike(id, tool, damage, plan, "area_attack")
	if results.values().has("hit") or results.values().has("crit"):
		tool_hit_sound(tool)
		if tool == "bolt_cutter" and gear_total("rule:chain_cut") > 0:
			# One drag per swing: from the nearest enemy it cut to the nearest one it did not.
			var first := ""
			for id in struck:
				if results.get(id, "miss") != "miss" and enemies.has(id) and (first == "" or player.position.distance_to(enemies[id].body.position) < player.position.distance_to(enemies[first].body.position)):
					first = id
			chain_cut(first, damage, struck, "area_attack:bolt_cutter")
	spawn_vfx().fan_slash(player.position, direction, reach, rad_to_deg(half) * 2.0, map.ground_y(player.position))
	last_tool_attack = {"skill": "area_attack", "tool": tool, "struck": struck, "results": results}

func sweep_angle(keys: Array, phase: float) -> float:
	# Staff-tip bearing of the playing clip (degrees, right positive), sampled from the v32 motion.
	if phase <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if phase <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(float(a[1]), float(b[1]), (phase - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.000001))
	return float(keys[-1][1])

func tick_sweep(dt: float) -> void:
	if sweep.is_empty():
		return
	var keys: Array = sweep.plan.sweep
	var before := sweep_angle(keys, float(sweep.phase))
	sweep.phase = float(sweep.phase) + dt / maxf(float(sweep.total), 0.000001)
	var now := sweep_angle(keys, float(sweep.phase))
	var facing: Vector3 = sweep.direction
	var right: Vector3 = facing.cross(Vector3.UP)
	var damage := tool_hit_damage("area_attack", sweep.plan)
	var cut := false
	for id in enemies.keys():
		if id in sweep.struck:
			continue
		var delta: Vector3 = enemies[id].body.position - player.position
		delta.y = 0.0
		if delta.length() > float(sweep.reach) + 0.3 * float(enemies[id].size):
			continue
		var bearing := rad_to_deg(atan2(delta.dot(right), delta.dot(facing)))
		var passed := false
		for turn in range(-2, 3):
			var angle := bearing + 360.0 * turn
			if angle >= now - 0.001 and angle <= before + 0.001:
				passed = true
		if passed and map.sees(player.position, enemies[id].body.position):
			sweep.struck.append(id)
			var result := tool_strike(id, sweep.tool, damage, sweep.plan, "area_attack")
			last_tool_attack.struck.append(id)
			last_tool_attack.results[id] = result
			cut = cut or result != "miss"
	if cut:
		tool_hit_sound(sweep.tool)
	if float(sweep.phase) >= float(keys[-1][0]):
		sweep.clear()

func start_channel(target: Vector3, direction: Vector3) -> void:
	# Rotary cannon (03 §3, firearm III): after the spin-up cast it fires for as long as its key is
	# held, turning after the cursor, while she stands still. Mana drains by the second.
	var visual: Node3D = gatling_assembly
	gatling_assembly = null
	if not is_instance_valid(visual):
		visual = GatlingGun.new()
		world.add_child(visual)
		visual.initialize(self)
	visual.ready_to_fire()
	moving = false
	move_marker.visible = false
	var slot: String = channel_slot("gatling")
	channel = {"skill": "gatling", "slot": slot, "visual": visual, "fire_left": 0.0, "shots": 0,
		"aim": target, "direction": direction, "focus": "", "focus_hits": 0}
	probe.channel_begin("gatling")

func channel_held() -> bool:
	return not channel.is_empty() and hold.get("slot") == channel.slot and state.bindings.get(channel.slot) == channel.skill

func stop_channel(exit: bool = false) -> void:
	# exit: the focus attack lets go with its exit motion (a short recovery); interrupts, death
	# and field clear end it without one.
	if channel.is_empty():
		return
	if channel.skill == "focus_attack":
		player_visual.end_focus_loop()
		if exit and hp > 0 and not field_cleared():
			var seconds: float = tool_speed(float(rules.skills.focus_attack.exit_seconds))
			action_time = maxf(action_time, seconds)
			player_visual.begin_tool_motion("focus_exit", channel.tool, seconds, 1.0)
	elif is_instance_valid(channel.visual):
		channel.visual.dismiss()
	channel.clear()

func tick_channel(dt: float) -> void:
	if channel.is_empty():
		return
	if not channel_held():
		stop_channel(true)
		return
	if channel.skill == "focus_attack":
		tick_tool_channel(dt)
		return
	var skill: Dictionary = rules.skills.gatling
	var cost: float = float(skill.channel_mana_per_second) * dt
	if state.mana + rules.EPS < cost:
		stop_channel()
		show_message("마나 부족 · 사격 중지")
		return
	state.mana = maxf(0.0, state.mana - cost)
	probe.record([{"type": "tool_upkeep", "tool": "gatling", "amount": cost}])
	probe.channel_time("gatling", dt, cost)
	# The stream follows the cursor: an enemy under it, else the floor point.
	var cursor := field_cursor()
	if cursor.get("enemy_id") != null and enemies.has(cursor.enemy_id):
		channel.aim = enemies[cursor.enemy_id].body.position
	elif cursor.get("ground") != null:
		channel.aim = map.grounded(point(cursor.ground))
	var flat: Vector3 = channel.aim - player.position
	flat.y = 0.0
	if flat.length() > 0.05:
		channel.direction = flat.normalized()
	var direction: Vector3 = channel.direction
	player_model.look_at(player.position + direction)
	if is_instance_valid(channel.visual):
		channel.visual.aim_at(player.position + direction * float(skill.range) + Vector3.UP)
	channel.fire_left = float(channel.fire_left) - dt
	while not channel.is_empty() and channel.fire_left <= 0:
		fire_gatling(direction)
		channel.fire_left = float(channel.fire_left) + gatling_interval()

func fire_gatling(direction: Vector3) -> void:
	# One round, woven across the node's spread (a fixed pattern, so the stream covers it evenly),
	# strikes the nearest enemy in sight on its line. Each round rolls to hit like other shots.
	var skill: Dictionary = rules.skills.gatling
	var shell := gatling_round()
	var spread: float = deg_to_rad(float(shell.spread_degrees)) * sin(float(channel.shots) * 2.39996)
	channel.shots = int(channel.shots) + 1
	var line: Vector3 = direction.rotated(Vector3.UP, spread)
	var reach: float = float(skill.range)
	var best := ""
	var nearest := INF
	for id in enemies:
		var delta: Vector3 = enemies[id].body.position - player.position
		delta.y = 0.0
		var along: float = delta.dot(line)
		if along > 0 and along <= reach and along < nearest and (delta - line * along).length() <= float(skill.hit_width) * float(enemies[id].size) and map.sees(player.position, enemies[id].body.position):
			best = id
			nearest = along
	var origin: Vector3 = player.position + Vector3.UP
	if is_instance_valid(channel.visual):
		origin = channel.visual.muzzle()
	var end: Vector3 = player.position + line * reach + Vector3.UP
	var hit := "miss"
	if best != "":
		end = enemies[best].body.position + Vector3.UP * 0.8 * float(enemies[best].size)
		var damage: float = float(shell.shot_damage)
		if shell.has("focus_per_hit"):
			# Converging fire: steady hits on one enemy build up; a new target starts over.
			if channel.focus != best:
				channel.focus = best
				channel.focus_hits = 0
			damage *= 1.0 + minf(float(shell.focus_max), float(shell.focus_per_hit) * float(channel.focus_hits))
		var spot: Vector3 = enemies[best].body.position
		hit = strike(best, damage, true, "witch", "gatling")
		pierce_behind(best, spot, line, reach, float(skill.hit_width), damage, "gatling")
		if hit != "miss" and shell.has("focus_per_hit"):
			channel.focus_hits = int(channel.focus_hits) + 1
		if hit != "miss" and shell.has("stagger_hits") and enemies.has(best):
			# Suppressing fire: every few hits on one enemy stagger it hard, past the usual guard.
			var enemy: Dictionary = enemies[best]
			enemy.suppressed = int(enemy.get("suppressed", 0)) + 1
			if enemy.suppressed >= int(shell.stagger_hits):
				enemy.suppressed = 0
				flinch(enemy, float(shell.stagger_factor), true)
	if is_instance_valid(channel.visual):
		channel.visual.shoot(end)
	spawn_vfx().muzzle(origin, [end], [best == ""], map.ground_y(origin))
	play_sfx("shotgun_fire", 1.8 if hit != "miss" else 2.0, -6.0)
	last_burst = {"target": best, "result": hit, "origin": origin, "end": end, "line": line, "shots": channel.shots}

func begin_shotgun_visual(target: Vector3, at_enemy: bool = false) -> void:
	shotgun_assembly=ShotgunCast.new()
	world.add_child(shotgun_assembly)
	shotgun_assembly.initialize(self)
	shotgun_assembly.global_transform=ShotgunGeometry.frame(self,target,at_enemy)

func knock_back(id: String) -> void:
	# Shotgun Lv5+ (the firearm tree is safest at range): a hit shoves the enemy straight away.
	var skill: Dictionary = rules.skills.shotgun
	if config.shotgun_level < float(skill.knockback_level):
		return
	push_back(id, float(skill.knockback_distance), float(skill.knockback_seconds))

func push_back(id: String, distance: float, seconds: float) -> void:
	# Shoves the enemy straight away from her. Heavy enemies go half as far, bosses and charging
	# brutes not at all.
	if not enemies.has(id):
		return
	var enemy: Dictionary = enemies[id]
	if config.enemy_types[enemy.kind].has("boss") or enemy.get("charging", 0.0) > 0:
		return
	var away: Vector3 = enemy.body.position - player.position
	away.y = 0.0
	if away.length() < 0.01:
		away = -player_model.global_basis.z
	distance *= 0.5 if enemy.heavy else 1.0
	enemy.knockback_dir = away.normalized()
	enemy.knockback_left = distance
	enemy.knockback_speed = distance / seconds

func fire_shotgun(target: Vector3, at_enemy: bool = false) -> void:
	var shot: Transform3D=ShotgunGeometry.frame(self,target,at_enemy)
	if not is_instance_valid(shotgun_assembly): begin_shotgun_visual(target,at_enemy)
	shotgun_assembly.fire(shot)
	shotgun_assembly=null
	if gear_total("rule:twin_barrels") > 0:
		# Unique 쌍둥이 포열핵: two narrower volleys a beat apart, each at a reduced share.
		var rule: Dictionary = items.data.rule_values
		shotgun_volley(shot, float(rule.twin_factor), float(rule.twin_cone_dot))
		twin_shots.append({"left": float(rule.twin_delay), "shot": shot, "factor": float(rule.twin_factor), "dot": float(rule.twin_cone_dot)})
	else:
		shotgun_volley(shot, 1.0, ShotgunGeometry.CONE_DOT)

func shotgun_volley(shot: Transform3D, factor: float, dot: float) -> void:
	var struck: Array[String]=[]
	for id in enemies.keys():
		if ShotgunGeometry.contains(self,shot,enemies[id].body,dot):
			struck.append(id)
			if strike(id,config.shot_damage*factor,false,"witch","shotgun") != "miss":
				knock_back(id)
	var endpoints: Array[Vector3]=ShotgunGeometry.traces(self,shot,dot)
	# Unblocked traces end on the 8m circle around the witch; shorter ones hit a wall or floor.
	var blocked: Array[bool]=[]
	for end in endpoints:
		var flat: Vector3=end-player.position; flat.y=0.0
		blocked.append(flat.length()<float(rules.skills.shotgun.range)-0.05)
	spawn_vfx().muzzle(shot.origin,endpoints,blocked,map.ground_y(shot.origin))
	last_shotgun={"frame":shot,"origin":shot.origin,"direction":-shot.basis.z,"ends":endpoints,"struck":struck}
	play_sfx("shotgun_fire", 0.65)

func tick_twin_shots(dt: float) -> void:
	for pending in twin_shots.duplicate():
		pending.left = float(pending.left) - dt
		if pending.left <= 0.0:
			twin_shots.erase(pending)
			shotgun_volley(pending.shot, float(pending.factor), float(pending.dot))

func tick_move_hold() -> void:
	# A held ground click steers movement; sweeping over enemies never starts an attack.
	# An approach-cast or queued input takes over until it finishes, then steering resumes.
	if move_hold.is_empty() or not pending_cast.is_empty() or not queued_input.is_empty():
		return
	var cursor = field_cursor()
	if cursor.get("ground") != null:
		set_destination(point(cursor.ground))

func tick_hold() -> void:
	if not channel.is_empty():
		# The held key is the channel itself; ground steering waits until it ends.
		return
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
	var seconds := motion_seconds(base, config.min_attack_seconds, config.attack_speed_k, config.attack_speed_score)
	return seconds * fire_interval_factor() if tool in GUNS else seconds

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
	if cursor.has("follow") and enemies.has(cursor.follow):
		# A device aimed at an enemy goes where that enemy is now (its last spot if it died).
		var at: Vector3 = enemies[cursor.follow].body.position
		cursor.ground = [at.x, 0, at.z]
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
				dismiss_gun()
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
	var seconds: float = float(skill.dash_seconds) / leap_speed_factor()
	dash = {"direction": direction, "left": length, "speed": length / seconds, "visual_distance":length}
	if config.spring_dash_node != "base":
		dash.landing = config.spring_dash_node
	player_visual.launch_spring_jump(seconds)
	if not is_instance_valid(spring_plate):begin_spring_plate(direction)
	spring_plate.launch(direction)
	spring_plate = null

func recoil_leap(target: Vector3, direction: Vector3, at_enemy: bool) -> void:
	# Recoil leap (03 §3, firearm III, learned after the shotgun): a short wide blast shoves the
	# enemies in front away, and its kick throws her straight back. She keeps facing the aim, and
	# hits cannot stagger her mid-leap, as in the spring dash.
	var skill: Dictionary = rules.skills.recoil_leap
	var shot: Transform3D = ShotgunGeometry.frame(self, target, at_enemy)
	if not is_instance_valid(shotgun_assembly):
		begin_shotgun_visual(target, at_enemy)
	shotgun_assembly.fire(shot)
	shotgun_assembly = null
	var struck: Array = []
	for id in enemies.keys():
		var delta: Vector3 = enemies[id].body.position - player.position
		delta.y = 0.0
		var close: bool = delta.length() <= float(skill.range) + 0.4 * float(enemies[id].size)
		if close and (delta.length() < 0.3 or delta.normalized().dot(direction) >= float(skill.blast_dot)) and map.sees(player.position, enemies[id].body.position):
			struck.append(id)
			if strike(id, float(skill.shot_damage), false, "witch", "recoil_leap") != "miss":
				push_back(id, float(skill.knockback_distance), float(skill.knockback_seconds))
	var ends: Array[Vector3] = []
	var blocked: Array[bool] = []
	for step in range(-3, 4):
		ends.append(shot.origin + direction.rotated(Vector3.UP, acos(float(skill.blast_dot)) * step / 3.0) * float(skill.range))
		blocked.append(false)
	spawn_vfx().muzzle(shot.origin, ends, blocked, map.ground_y(shot.origin))
	play_sfx("shotgun_fire", 0.55)
	shake_time = maxf(shake_time, 0.1)
	# The kick carries her back as far as open floor allows.
	var back: Vector3 = -direction
	var length := 0.0
	while length + 0.2 <= float(skill.leap_distance) and map.walkable(player.position + back * (length + 0.2)):
		length += 0.2
	moving = false
	move_marker.visible = false
	var seconds: float = float(skill.leap_seconds) / leap_speed_factor()
	dash = {"direction": back, "left": length, "speed": length / seconds, "visual_distance": length}
	player_visual.launch_spring_jump(seconds)
	last_recoil = {"struck": struck, "back": back, "leap": length, "origin": shot.origin}

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
		var landing: String = dash.get("landing", "")
		player_visual.land_spring_jump()
		dash.clear()
		player.velocity = Vector3.ZERO
		if landing != "":
			spring_landing(landing)

func spring_landing(node: String) -> void:
	# Spring dash nodes (2026-11-05): the plate's kick hits the floor where she lands. Approach
	# stuns the enemies round her so the drive tools can cut; retreat shoves them off so guns and
	# summons keep their range. No damage and no roll; bosses ignore both, heavy enemies slide half.
	var plan: Dictionary = rules.skills.spring_dash.nodes[node]
	var struck: Array = []
	for id in enemies.keys():
		var delta: Vector3 = enemies[id].body.position - player.position
		delta.y = 0.0
		if delta.length() <= float(plan.radius) + 0.4 * float(enemies[id].size) and map.sees(player.position, enemies[id].body.position):
			struck.append(id)
			if node == "approach":
				restrain(id, "stun", float(plan.stun_seconds))
			else:
				push_back(id, float(plan.knockback_distance), float(plan.knockback_seconds))
	var floor_y: float = map.ground_y(player.position)
	var at := Vector3(player.position.x, floor_y, player.position.z)
	var fx = spawn_vfx()
	var tint := Color(1.0, 0.82, 0.35) if node == "approach" else Color(0.55, 0.85, 1.0)
	fx.ground_ring(at, 0.3, float(plan.radius), 0.16, tint, 0.32)
	for i in 3:
		fx.dust_trail(at, 0.0)
	shake_time = maxf(shake_time, 0.08)
	last_spring_landing = {"node": node, "struck": struck, "at": at}

func execute_cast(event: Dictionary) -> void:
	if SKILL_TREES.has(event.skill) and event.skill not in TOOL_ATTACKS:
		if is_instance_valid(charging_circle) and charging_circle.charging:
			charging_circle.flare()
		else:
			spawn_cast_circle(SKILL_TREES[event.skill], true)
	charging_circle = null
	var target = cast_target(event)
	var direction = cast_direction(event)
	player_model.look_at(player.position + direction)
	if event.skill == rules.basic_id and not gun.is_empty():
		fire_gun(event, direction)
		return
	match event.skill:
		"basic_attack":
			var tool = event.active_tool
			# The exoskeleton drives the tool attacks harder, not the bare staff.
			var damage: float = rules.skills[tool].attack_damage * exo_tool_factor() if tool != null else config.basic_damage
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
		"matchlock", "rifle":
			equip_gun(event.skill)
		"powder_keg":
			roll_keg(target, direction)
		"gatling":
			start_channel(target, direction)
		"smoke_launcher":
			launch_smoke(target, direction)
		"spring_dash":
			start_dash(target, direction, aims_at_enemy(event))
		"recoil_leap":
			recoil_leap(target, direction, aims_at_enemy(event))
		"artillery":
			call_artillery(target, direction)
		"naval_gun":
			call_naval_gun(target, direction)
		"guillotine", "hydraulic_press", "compound_executor":
			place_device(event.skill, target, direction)
		"restraint_winch":
			fire_winch(event, direction)
		"bolt_cutter", "grinder", "chainsaw": pass  # the staff itself transforms; no ground ring
		"focus_attack":
			start_tool_channel(event.active_tool, direction)
		"area_attack":
			tool_area(event.active_tool, direction)
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
	# Summon options on gear (summon damage / summon life +%) keep late summons in step with gear.
	return (1.0 + float(config["summon_%s_per_level" % kind]) * (float(config[roller + "_level"]) - 1.0)) * (1.0 + gear_total("summon_%s_pct" % kind) / 100.0)

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

func attack_range() -> Vector2:
	# Her attack power: the character's own base plus the worn medium's (07 §2.1). Summons do not
	# use it; their strength comes from their skill level.
	var base: Array = config.build.base_attack
	return Vector2(float(base[0]) + gear_total("attack_min"), float(base[1]) + gear_total("attack_max"))

func attack_skew() -> float:
	# Dexterity leans each roll toward the top of the range, never all the way.
	return minf(float(config.build.attack_max_skew), 1.0 + float(config.build.attack_dex_skew) * float(config.dexterity))

func attack_median() -> float:
	# Where the middle roll falls in the range: 0.5 at no dexterity, at most about 0.84.
	return pow(0.5, 1.0 / attack_skew())

func roll_attack(crit: bool) -> float:
	# A crit hits with the top of the range; other hits roll inside it. Scripted checks that force
	# the hit/crit rolls also pin this one (spread, 0.5 by default = the range's middle).
	var span := attack_range()
	if crit:
		return span.y
	var spot: float = float(force_rolls.get("spread", 0.5)) if not force_rolls.is_empty() else pow(combat_rng.randf(), 1.0 / attack_skew())
	return lerpf(span.x, span.y, spot)

func attack_factor(attack: float) -> float:
	# A skill's listed damage is its damage at the reference attack (the bare character's middle
	# roll); attack_share of it grows with attack, the rest is fixed: shotgun 30 = attack x 210% + 9.
	var share: float = float(config.build.attack_share)
	return share * attack / float(config.build.attack_reference) + (1.0 - share)

func spread_factor(width: float) -> float:
	# Enemy and summon hits vary by +-width around their value; forced rolls keep the value.
	return 1.0 if not force_rolls.is_empty() else 1.0 + width * (2.0 * combat_rng.randf() - 1.0)

func armor() -> float:
	# Worn defence, plus the shield's while it is up.
	var total: float = gear_total("armor")
	# The exoskeleton's guard frame also reinforces the shield, per exoskeleton level.
	if shield_time > 0:
		var shield: Dictionary = rules.skills.shield
		total += float(shield.armor_base) + float(shield.armor_per_level) * (float(config.shield_level) - 1.0) + shield_frame_armor()
	if exo_active():
		total += exo_armor()
	return total

func shield_frame_armor() -> float:
	return float(exo_plan().get("shield_armor_per_level", 0.0)) * exo_level()

func summon_guard() -> float:
	# Share of every hit the witch's summons shrug off, from the exoskeleton's guard frame (it
	# replaced the shock-absorbing frame passive; worn or not, it reinforces them).
	return minf(0.5, float(exo_plan().get("summon_guard_per_level", 0.0)) * exo_level())

func armor_reduction(level: int = -1) -> float:
	# Defence against an attacker's level: the same armour turns away less from stronger enemies,
	# so old armour falls behind as the enemies' levels rise (07 §2.4).
	var attacker: int = enemy_level if level < 0 else level
	var k: Array = config.build.armor_k
	var value := armor()
	return minf(float(config.build.armor_cap), value / maxf(0.001, value + float(k[0]) + float(k[1]) * attacker))

func strike(id: String, amount: float, accuracy_roll: bool, roller: String, source: String, look: String = "", label: String = "") -> String:
	# roller is "witch" or the summon skill ("automaton", "turret") whose level drives the rolls.
	# One direct damage event: optional hit roll, then its own crit roll (area attacks call this per enemy).
	# label, if given, is the A5 log row in place of source.
	if not enemies.has(id):
		return "miss"
	amount *= passive_factor(source + ("_" + look if look != "" else ""))
	if roller == "witch":
		amount *= build.power_factor() * (1.0 + gear_total("damage_pct") / 100.0) * skill_level_factor(source)
	if accuracy_roll and not force_rolls.get("hit", combat_rng.randf() < hit_chance(id, roller)):
		probe.strike(source if label == "" else label, "miss", 0.0)
		return "miss"
	var crit: bool = force_rolls.get("crit", combat_rng.randf() < crit_chance(roller))
	amount *= attack_factor(roll_attack(crit)) if roller == "witch" else spread_factor(float(config.build.summon_spread))
	var at: Vector3 = enemies[id].body.position
	var size: float = enemies[id].size
	var dealt: float = damage_enemy(id, amount * (config.crit_multiplier if crit else 1.0))
	probe.strike(source if label == "" else label, "crit" if crit else "hit", dealt)
	if roller == "witch":
		leech(dealt)
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

func flinch_seconds(enemy: Dictionary) -> float:
	# Lighter grades flinch longer; each level the enemy stands above the witch shortens it
	# (below her, lengthens it). Bosses keep their own patterns and never flinch.
	var plan: Dictionary = config.enemy_flinch
	if config.enemy_types[enemy.kind].has("boss"):
		return 0.0
	var gap: float = float(build.level) - float(enemy.level)
	var factor: float = clampf(1.0 + float(plan.level_step) * gap, float(plan.min_factor), float(plan.max_factor))
	return float(plan.seconds.get(enemy.grade, 0.0)) * factor

func flinch(enemy: Dictionary, scale: float = 1.0, forced: bool = false) -> void:
	# A direct hit (any source, not bleed) makes the enemy flinch: it stops where it is and loses
	# the attack it was winding up. A short guard afterwards keeps fast hits from pinning it.
	# A telegraphed brute charge, once its line is on the ground, is not broken off.
	# forced (a suppressing barrage's stagger) cuts through the guard, not through a charge.
	if (float(enemy.flinch_guard) > 0 and not forced) or float(enemy.get("charging", 0.0)) > 0:
		return
	if enemy.windup > 0 and enemy.attack == "charge":
		return
	var seconds := flinch_seconds(enemy) * scale
	if seconds <= 0:
		return
	enemy.flinch = seconds
	enemy.flinch_guard = seconds + float(config.enemy_flinch.guard_seconds)
	probe.counts.enemy_flinches += 1
	interrupt_attack(enemy)

func interrupt_attack(enemy: Dictionary) -> void:
	# It loses the attack it was winding up.
	if enemy.windup > 0:
		enemy.windup = 0.0
		enemy.attack = ""
		probe.counts.enemy_attacks_interrupted += 1
		if enemy.model.has_method("interrupt_attack"):
			enemy.model.interrupt_attack()
		else:
			enemy.model.rotation.z = 0

func damage_enemy(id: String, amount: float, direct: bool = true) -> float:
	# Returns the HP actually removed, for the A5 log. Bleed ticks pass direct = false.
	if not enemies.has(id):
		return 0.0
	var enemy: Dictionary = enemies[id]
	# Trial shred: no armour formula exists yet, so shredded enemies take more direct damage.
	# Bleed ignores defence, so shred never raises it (07 §2.2).
	# Shred-strength options grow only the shred's extra share (1.25 -> 1.25 + 0.25 x option).
	var shred: float = 1.0 + (float(config.shred_damage_taken) - 1.0) * (1.0 + gear_total("shred_pct") / 100.0)
	var taken: float = amount * (shred if enemy.shred > 0 and direct else 1.0)
	var dealt: float = minf(maxf(enemy.hp, 0.0), taken)
	enemy.hp -= taken
	if direct:
		enemy.flash = 0.16
		flinch(enemy)
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
		# 「록」 in the medium and on-kill options: each kill mends a little and refills some mana,
		# whoever landed the killing blow (a summon or a bleed tick counts too).
		if hp > 0:
			hp = minf(config.max_hp, hp + gear_total("life_on_kill"))
			state.mana = minf(state.max_mana, state.mana + gear_total("mana_on_kill"))
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

func arrange_potions() -> void:
	# Counts stay in the stash; this fixed grid remembers where each nonempty kind lives.
	while potion_cells.size() < POTION_BAG_CAPACITY:
		potion_cells.append("")
	for index in potion_cells.size():
		if potion_stash.get(potion_cells[index], 0) <= 0:
			potion_cells[index] = ""
	for id in potion_stash:
		if potion_stash[id] > 0 and not potion_cells.has(id):
			var empty := potion_cells.find("")
			if empty >= 0:
				potion_cells[empty] = id

func store_potion(id: String, count: int) -> bool:
	arrange_potions()
	if not config.potions.has(id) or count <= 0:
		return false
	if not potion_cells.has(id):
		var empty := potion_cells.find("")
		if empty < 0:
			return false
		potion_cells[empty] = id
	potion_stash[id] = int(potion_stash.get(id, 0)) + count
	return true

func move_potion_cell(from: int, to: int) -> void:
	var old: String = potion_cells[to]
	potion_cells[to] = potion_cells[from]
	potion_cells[from] = old
	refresh_build_windows()

func put_quickslot_in_bag(index: int, cell: int) -> bool:
	arrange_potions()
	var slot: Dictionary = potion_slots[index]
	if slot.count <= 0:
		return false
	var target: String = potion_cells[cell]
	if target != "" and target != slot.id:
		return assign_quickslot(index, target)
	var existing := potion_cells.find(slot.id)
	if not store_potion(slot.id, slot.count):
		return false
	if existing < 0:
		potion_cells[potion_cells.find(slot.id)] = ""
		potion_cells[cell] = slot.id
	slot.count = 0
	refresh_build_windows()
	return true

func move_potion_quickslot(from: int, to: int) -> void:
	if from != to:
		if potion_slots[from].id == potion_slots[to].id:
			potion_slots[to].count += potion_slots[from].count
			potion_slots[from].count = 0
		else:
			var old: Dictionary = potion_slots[to]
			potion_slots[to] = potion_slots[from]
			potion_slots[from] = old
	refresh_build_windows()

func buy_potion(id: String) -> bool:
	# Trial shop in the inventory: full-restore potions are drop-only (04 §8.2).
	var price: int = int(items.data.potion_prices.get(id, 0))
	if price <= 0 or coins < price:
		return false
	if not store_potion(id, 1):
		show_message("물약 가방에 자리가 없습니다")
		return false
	coins -= price
	refresh_build_windows()
	return true

func assign_quickslot(index: int, id: String) -> bool:
	# The slot's potions go back to the stash and the chosen kind's whole stack moves in.
	arrange_potions()
	var slot: Dictionary = potion_slots[index]
	var source := potion_cells.find(id)
	if slot.count > 0 and not potion_cells.has(slot.id) and source < 0 and not potion_cells.has(""):
		return false
	potion_stash[slot.id] += slot.count
	if source >= 0 and slot.id != id:
		potion_cells[source] = slot.id if slot.count > 0 and not potion_cells.has(slot.id) else ""
	slot.id = id
	slot.count = potion_stash[id]
	potion_stash[id] = 0
	arrange_potions()
	refresh_build_windows()
	return true

func fill_quickslot(index: int) -> void:
	var slot: Dictionary = potion_slots[index]
	slot.count += potion_stash[slot.id]
	potion_stash[slot.id] = 0
	arrange_potions()
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
	# The exoskeleton shortens the stagger once every few of its levels.
	return motion_seconds(config.hit_recovery_seconds, config.min_hit_recovery_seconds, config.hit_recovery_k, config.hit_recovery_score) * exo_stun_factor()

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
		if gear_total("rule:block_counter") > 0:
			counter_block()
		return
	# Enemy hits vary a little; her armour turns away a share by the attacker's level, then damage
	# reduction options shave the rest, at most by half.
	amount *= spread_factor(float(config.build.enemy_spread)) * (1.0 - armor_reduction())
	amount *= 1.0 - minf(0.5, gear_total("damage_reduction") / 100.0)
	# Only a heavy enough hit that leaves her standing stuns.
	var stunned: bool = hp - amount > 0 and amount >= config.max_hp * config.hit_stun_min_ratio and dash.is_empty()
	probe.witch_hit(by_grade, minf(hp, amount), stunned, false)
	if gear_total("rule:exo_mana") > 0 and exo_active():
		# Unique 무쇠 연골: the worn exoskeleton turns a share of every blow into mana.
		state.mana = minf(state.max_mana, state.mana + minf(hp, amount) * float(items.data.rule_values.exo_mana_share))
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
		stop_channel()
		sweep.clear()
	if hp == 0:
		cancel_summon_assemblies("death")
		stop_channel()
		sweep.clear()
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

func counter_block() -> void:
	# Unique 반격 경첩: every block mends her a little and, at most once a second, the panels
	# shove everything close away.
	var rule: Dictionary = items.data.rule_values
	hp = minf(config.max_hp, hp + float(rule.block_life))
	state.mana = minf(state.max_mana, state.mana + float(rule.block_mana))
	if block_push_left > 0.0:
		return
	block_push_left = float(rule.block_push_every)
	for id in enemies.keys():
		var gap: Vector3 = enemies[id].body.position - player.position
		gap.y = 0.0
		if gap.length() <= float(rule.block_push_radius) + 0.4 * float(enemies[id].size):
			push_back(id, float(rule.block_push_distance), float(rule.block_push_seconds))
	spawn_vfx().shockwave(player.position, float(rule.block_push_radius), map.ground_y(player.position))

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

func chain_cut(first: String, damage: float, skip: Array = [], label: String = "") -> void:
	# Unique 집행자의 도르래: a landed bolt cutter hit (basic, focus or area attack) drags the
	# nearest other enemy in. Enemies in `skip` were already cut by the same swing.
	if not enemies.has(first):
		return
	var rule: Dictionary = items.data.rule_values
	var origin: Vector3 = enemies[first].body.position
	var second := ""
	var best := float(rule.chain_cut_range)
	for id in enemies:
		var gap: float = enemies[id].body.position.distance_to(origin)
		if id != first and id not in skip and gap <= best:
			best = gap
			second = id
	if second != "":
		strike(second, damage * float(rule.chain_cut_factor), true, "witch", "bolt_cutter", "", label)

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
		clear_kegs()
		clear_devices()
		stop_channel()
		sweep.clear()
		clear_barrage()
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
		tick_gun_reload(dt)
		tick_twin_shots(dt)
		block_push_left = maxf(0.0, block_push_left - dt)
		tick_kegs(dt)
		tick_channel(dt)
		tick_sweep(dt)
		tick_smokes(dt)
		tick_shells(dt)
		tick_fires(dt)
		tick_devices(dt)
		tick_winches(dt)
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
		elif moving and action_time <= 0 and channel.is_empty():
			walk_to_destination(dt)
		# Feet follow the floor: bodies only collide with walls, so steps lift them here.
		player.position.y = map.ground_y(player.position)
		for id in enemies.keys():
			_tick_enemy(enemies[id], dt)
			if enemies.has(id):
				enemies[id].body.position.y = map.ground_y(enemies[id].body.position)
			if enemies.has(id) and enemies[id].model.has_method("sync_enemy"):
				enemies[id].model.sync_enemy(enemies[id], dt)
			if enemies.has(id):
				sync_status_fx(enemies[id], dt)
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
	sync_exo_visual(0.0 if paused else dt)
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
		# Smoke hides her altogether: summons in sight draw the enemy instead.
		return INF if hp <= 0 or blinded(enemy) else enemy.body.position.distance_to(player.position) - config.aggro_witch_bias
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
	amount *= spread_factor(float(config.build.enemy_spread)) * (1.0 - summon_guard())
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

func status_fx(enemy: Dictionary) -> Node3D:
	return enemy.body.get_node_or_null("StatusFx")

func sync_status_fx(enemy: Dictionary, dt: float) -> void:
	# Debuff markers (presentation only): made the first time the enemy has one, then kept so
	# they can fade out.
	var fx := status_fx(enemy)
	if fx == null:
		if not (enemy.slow > 0 or enemy.shred > 0 or not enemy.bleeds.is_empty() or float(enemy.get("stun", 0.0)) > 0 or float(enemy.get("bound", 0.0)) > 0):
			return
		fx = StatusFx.new()
		enemy.body.add_child(fx)
		fx.setup(enemy)
	fx.sync(enemy, dt)

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
	enemy.flinch_guard = maxf(0, float(enemy.get("flinch_guard", 0.0)) - dt)
	enemy.stun = maxf(0, float(enemy.get("stun", 0.0)) - dt)
	enemy.bound = maxf(0, float(enemy.get("bound", 0.0)) - dt)
	enemy.winched = maxf(0, float(enemy.get("winched", 0.0)) - dt)
	if float(enemy.get("flinch", 0.0)) > 0 and enemy.get("knockback_left", 0.0) <= 0.0:
		# Flinching: it stands still and starts nothing until it recovers.
		enemy.flinch = maxf(0, float(enemy.flinch) - dt)
		enemy.body.velocity = Vector3.ZERO
		return
	if enemy.get("knockback_left", 0.0) > 0.0:
		# Knocked back: it slides away and neither steers nor advances its attack meanwhile.
		var travel: float = minf(enemy.knockback_speed * dt, enemy.knockback_left)
		enemy.body.velocity = enemy.knockback_dir * travel / dt
		enemy.body.move_and_slide()
		enemy.knockback_left -= travel
		return
	if enemy.stun > 0 or enemy.bound > 0:
		# Stunned by a press or bound by the winch / a device: it stands still and starts nothing.
		enemy.body.velocity = Vector3.ZERO
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
	var hidden := blinded(enemy)
	if not hidden:
		enemy.last_seen = player.position
	elif enemy.target == "":
		# She vanished into smoke: a summon in sight draws it at once.
		enemy.target = nearest_foe(enemy)
		enemy.retarget = config.aggro_retarget_seconds
		aim = foe_position(enemy.target)
		delta = aim - enemy.body.position
	# Pick a target only between attacks; a wound-up attack keeps the one it started on.
	enemy.retarget = maxf(0, enemy.retarget - dt)
	if enemy.retarget <= 0:
		enemy.target = nearest_foe(enemy)
		enemy.retarget = config.aggro_retarget_seconds
		aim = foe_position(enemy.target)
		delta = aim - enemy.body.position
	if enemy.target == "" and hidden:
		# Lost in the smoke: it gropes slowly toward where it last saw her and starts nothing.
		var seen: Vector3 = enemy.get("last_seen", enemy.body.position)
		var toward: Vector3 = seen - enemy.body.position
		toward.y = 0.0
		enemy.body.velocity = Vector3.ZERO
		if toward.length() > 0.5:
			var grope: Vector3 = follow(enemy.route, enemy.body.position, seen, 0.35, dt) - enemy.body.position
			grope.y = 0.0
			enemy.body.velocity = grope.normalized() * pace * float(rules.skills.smoke_launcher.blind_speed)
			enemy.model.look_at(Vector3(seen.x, enemy.body.global_position.y, seen.z))
		enemy.body.move_and_slide()
		return
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
			ally.cooldown = config.summon_attack_cooldown if ally.mobile else config.turret_attack_cooldown / turret_fire_rate()
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
	if visual.loaded_ok and visual._motion_kind in ["attack", "area", "focus_loop"] and is_instance_valid(visual.staff_root) and dt > 0:
		var tool = state.active_tool
		var reach: float = {"bolt_cutter": 0.62 + 0.33 * visual.blade_scale, "grinder": 0.98, "chainsaw": 1.1}.get(tool, 0.82)
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
