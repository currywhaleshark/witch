extends Node3D
class_name Arena
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
const Batch2Summons = preload("res://scripts/batch2_summons.gd")
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
	"automaton": "automation", "turret": "automation", "relay": "automation", "hound": "automation", "beacon": "automation", "giant": "automation"}
const CombatVfx = preload("res://scripts/combat_vfx.gd")
const StatusFx = preload("res://scripts/status_fx.gd")
const AssetWarmup = preload("res://scripts/asset_warmup.gd")
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const WARNING_SHADER = preload("res://shaders/warning_zone.gdshader")
const OUTLINE_SHADER = preload("res://shaders/outline.gdshader")
const AURA_SHADER = preload("res://shaders/grade_aura.gdshader")
const MASK_SHADER = preload("res://shaders/silhouette_mask.gdshader")
const ArenaInventory = preload("res://scripts/arena_inventory.gd")
const ArenaLoot = preload("res://scripts/arena_loot.gd")
const ArenaPotions = preload("res://scripts/arena_potions.gd")
const ArenaFirearms = preload("res://scripts/arena_firearms.gd")
const ArenaDevices = preload("res://scripts/arena_devices.gd")
const ArenaTools = preload("res://scripts/arena_tools.gd")
const ArenaDamage = preload("res://scripts/arena_damage.gd")
const ArenaEnemies = preload("res://scripts/arena_enemies.gd")
const ArenaAllies = preload("res://scripts/arena_allies.gd")
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
# Every summon skill whose build cost power management trims.
const SUMMON_SKILLS = ["automaton", "turret", "hound", "beacon", "giant"]
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
# Automation batch 2 (hounds, lure beacon, giant automaton) and the giant's own cooldown, which
# the multiple-units node shortens.
var batch2: RefCounted
var giant_cooldown := 0.0
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
var last_spare_refund: Dictionary = {}
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
var inventory_sys = ArenaInventory.new(self)
var loot_sys = ArenaLoot.new(self)
var potion_sys = ArenaPotions.new(self)
var firearm_sys = ArenaFirearms.new(self)
var device_sys = ArenaDevices.new(self)
var tool_sys = ArenaTools.new(self)
var damage_sys = ArenaDamage.new(self)
var enemy_sys = ArenaEnemies.new(self)
var ally_sys = ArenaAllies.new(self)

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/trial.json"))
	rules = Rules.new(config)
	automaton_cost = {"mana_cost": rules.skills.automaton.mana_cost, "cooldown_seconds": rules.skills.automaton.cooldown_seconds}
	shotgun_cooldown = float(rules.skills.shotgun.cooldown_seconds)
	giant_cooldown = float(rules.skills.giant.cooldown_seconds)
	batch2 = Batch2Summons.new(self)
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
	last_spare_refund.clear()
	batch2.clear()
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

# enemy_sys: arena_enemies.gd (delegates keep arena's existing surface).
func spawn_enemy(id: String, pos: Vector3, heavy: bool = false, grade: String = "normal", kind: String = "") -> void:
	enemy_sys.spawn_enemy(id, pos, heavy, grade, kind)
func dress_enemy(enemy: Dictionary, outlined: bool, alive: bool = true) -> void:
	enemy_sys.dress_enemy(enemy, outlined, alive)
func tick_boss_trigger() -> void:
	enemy_sys.tick_boss_trigger()
func call_test_boss() -> void:
	enemy_sys.call_test_boss()
func tick_respawns(dt: float) -> void:
	enemy_sys.tick_respawns(dt)
func edge_point() -> Vector3:
	return enemy_sys.edge_point()
func enemy_name(id: String) -> String:
	return enemy_sys.enemy_name(id)
func enemy_level_factor(kind: String, level: int) -> float:
	return enemy_sys.enemy_level_factor(kind, level)
func set_enemy_level(value: int) -> void:
	enemy_sys.set_enemy_level(value)
func step_enemy_level(delta: int) -> bool:
	return enemy_sys.step_enemy_level(delta)
func link_enemy_level() -> void:
	enemy_sys.link_enemy_level()
func status_fx(enemy: Dictionary) -> Node3D:
	return enemy_sys.status_fx(enemy)
func sync_status_fx(enemy: Dictionary, dt: float) -> void:
	enemy_sys.sync_status_fx(enemy, dt)
func _tick_enemy(enemy: Dictionary, dt: float) -> void:
	enemy_sys._tick_enemy(enemy, dt)
func begin_boss(enemy: Dictionary, pattern: String, windup: float) -> void:
	enemy_sys.begin_boss(enemy, pattern, windup)
func begin_frames(enemy: Dictionary, plan: Dictionary, aim: Vector3) -> void:
	enemy_sys.begin_frames(enemy, plan, aim)
func disc_warning(at: Vector3, radius: float, life: float) -> void:
	enemy_sys.disc_warning(at, radius, life)
func start_enemy_attack(enemy: Dictionary, attack: String, windup: float, color: Color) -> void:
	enemy_sys.start_enemy_attack(enemy, attack, windup, color)
func fire_bolt_from(origin: Vector3, at: Vector3, band: Dictionary, damage: float, grade: String) -> void:
	enemy_sys.fire_bolt_from(origin, at, band, damage, grade)
func tick_bolts(dt: float) -> void:
	enemy_sys.tick_bolts(dt)

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

# inventory_sys: arena_inventory.gd (delegates keep arena's existing surface).
func refresh_gear() -> void:
	inventory_sys.refresh_gear()
func bag_grid() -> Vector2i:
	return inventory_sys.bag_grid()
func bag_index(item: Dictionary) -> int:
	return inventory_sys.bag_index(item)
func bag_under(cells: Rect2i, ignore = null) -> Array:
	return inventory_sys.bag_under(cells, ignore)
func arrange_bag() -> void:
	inventory_sys.arrange_bag()
func stow(item: Dictionary) -> bool:
	return inventory_sys.stow(item)
func equip(index: int) -> void:
	inventory_sys.equip(index)
func unequip(slot: String) -> bool:
	return inventory_sys.unequip(slot)
func discard(index: int) -> void:
	inventory_sys.discard(index)
func take_from_bag(item: Dictionary) -> void:
	inventory_sys.take_from_bag(item)
func put_in_bag(at: Vector2i) -> bool:
	return inventory_sys.put_in_bag(at)
func wear_held() -> bool:
	return inventory_sys.wear_held()
func take_worn(slot: String) -> bool:
	return inventory_sys.take_worn(slot)
func drop_held() -> void:
	inventory_sys.drop_held()
func salvage_held() -> void:
	inventory_sys.salvage_held()
func return_held() -> void:
	inventory_sys.return_held()
func equipment_summary() -> Dictionary:
	return inventory_sys.equipment_summary()
func socket_into(item: Dictionary, piece: String) -> bool:
	return inventory_sys.socket_into(item, piece)
func socket_piece(slot: String, piece: String) -> bool:
	return inventory_sys.socket_piece(slot, piece)
func unsocket(slot: String) -> bool:
	return inventory_sys.unsocket(slot)
func salvage(index: int) -> void:
	inventory_sys.salvage(index)
func salvage_below_rare() -> int:
	return inventory_sys.salvage_below_rare()
func reroll(slot: String, affix: int) -> bool:
	return inventory_sys.reroll(slot, affix)

# loot_sys: arena_loot.gd (delegates keep arena's existing surface).
func drop_spoils(grade: String, at: Vector3) -> void:
	loot_sys.drop_spoils(grade, at)
func drop_loot(grade: String, at: Vector3) -> void:
	loot_sys.drop_loot(grade, at)
func drop_item(item: Dictionary, at: Vector3) -> void:
	loot_sys.drop_item(item, at)
func drop_resource(kind: String, id: String, amount: int, at: Vector3) -> void:
	loot_sys.drop_resource(kind, id, amount, at)
func tick_ground_loot(dt: float) -> void:
	loot_sys.tick_ground_loot(dt)
func loot_labels() -> Array:
	return loot_sys.loot_labels()
func loot_pointer_available(screen: Vector2) -> bool:
	return loot_sys.loot_pointer_available(screen)
func loot_at(screen: Vector2) -> Dictionary:
	return loot_sys.loot_at(screen)
func update_loot_hover(screen: Vector2) -> void:
	loot_sys.update_loot_hover(screen)
func set_hovered_loot(next: Dictionary) -> void:
	loot_sys.set_hovered_loot(next)
func pick_up(loot: Dictionary) -> void:
	loot_sys.pick_up(loot)
func tick_pickup() -> void:
	loot_sys.tick_pickup()

func sync_tool_upkeep() -> void:
	# Upkeep options and the power part trim every tool's drain, never below a tenth.
	# The exoskeleton's drive frame trims it further.
	var cut: float = minf(0.9, gear_total("upkeep_pct") / 100.0)
	for id in tool_upkeep:
		rules.skills[id].upkeep_per_second = float(tool_upkeep[id]) * (1.0 - cut) * (1.0 - exo_upkeep_cut()) * (1.0 - power_upkeep_cut())

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

# ally_sys: arena_allies.gd (delegates keep arena's existing surface).
func sync_automaton_cost() -> void:
	ally_sys.sync_automaton_cost()
func summon_life_factor() -> float:
	return ally_sys.summon_life_factor()
func turret_plan() -> Dictionary:
	return ally_sys.turret_plan()
func detection_range(ally: Dictionary) -> float:
	return ally_sys.detection_range(ally)
func relay_factor(ally: Dictionary) -> float:
	return ally_sys.relay_factor(ally)
func turret_fire_rate() -> float:
	return ally_sys.turret_fire_rate()
func automaton_spawn_position(slot: int = 0) -> Vector3:
	return ally_sys.automaton_spawn_position(slot)
func free_follow_slot() -> int:
	return ally_sys.free_follow_slot()
func face_travel(ally: Dictionary, before: Vector3, dt: float) -> void:
	ally_sys.face_travel(ally, before, dt)
func summon_growth(kind: String, roller: String) -> float:
	return ally_sys.summon_growth(kind, roller)
func summon_level(roller: String) -> int:
	return ally_sys.summon_level(roller)
func spawn_ally(pos: Vector3, mobile: bool, target_id) -> void:
	ally_sys.spawn_ally(pos, mobile, target_id)
func automaton_reach(id: String) -> float:
	return ally_sys.automaton_reach(id)
func dismantle_ally(ally: Dictionary) -> void:
	ally_sys.dismantle_ally(ally)
func chain_cut(first: String, damage: float, skip: Array = [], label: String = "") -> void:
	ally_sys.chain_cut(first, damage, skip, label)
func expire_ally(ally: Dictionary) -> void:
	ally_sys.expire_ally(ally)
func ally_by_id(id: String) -> Dictionary:
	return ally_sys.ally_by_id(id)
func foe_position(target: String) -> Vector3:
	return ally_sys.foe_position(target)
func aggro_distance(enemy: Dictionary, target: String) -> float:
	return ally_sys.aggro_distance(enemy, target)
func nearest_foe(enemy: Dictionary) -> String:
	return ally_sys.nearest_foe(enemy)
func hit_foe(target: String, amount: float, grade: String) -> void:
	ally_sys.hit_foe(target, amount, grade)
func damage_ally(ally: Dictionary, amount: float, grade: String) -> void:
	ally_sys.damage_ally(ally, amount, grade)
func foe_in_reach(at: Vector3, reach: float) -> String:
	return ally_sys.foe_in_reach(at, reach)
func _tick_allies(dt: float) -> void:
	ally_sys._tick_allies(dt)

func round_cost(id: String) -> float:
	# Mana cost cuts trim every round as they trim every skill, at most by half.
	return float(rules.skills[id].round_cost) * (1.0 - clampf(gear_total("mana_cost_pct") / 100.0, 0.0, 0.5))

# firearm_sys: arena_firearms.gd (delegates keep arena's existing surface).
func reload_level() -> float:
	return firearm_sys.reload_level()
func fire_interval_factor() -> float:
	return firearm_sys.fire_interval_factor()
func leap_speed_factor() -> float:
	return firearm_sys.leap_speed_factor()
func gun_magazine(id: String) -> int:
	return firearm_sys.gun_magazine(id)
func reload_seconds(id: String) -> float:
	return firearm_sys.reload_seconds(id)
func tick_gun_reload(dt: float) -> void:
	firearm_sys.tick_gun_reload(dt)
func sync_gun() -> void:
	firearm_sys.sync_gun()
func equip_gun(id: String) -> void:
	firearm_sys.equip_gun(id)
func dismiss_gun() -> void:
	firearm_sys.dismiss_gun()
func fire_gun(event: Dictionary, direction: Vector3) -> void:
	firearm_sys.fire_gun(event, direction)
func begin_keg_visual(direction: Vector3) -> void:
	firearm_sys.begin_keg_visual(direction)
func roll_keg(target: Vector3, direction: Vector3) -> void:
	firearm_sys.roll_keg(target, direction)
func tick_kegs(dt: float) -> void:
	firearm_sys.tick_kegs(dt)
func clear_kegs() -> void:
	firearm_sys.clear_kegs()
func strike_point(target: Vector3, direction: Vector3, reach: float) -> Vector3:
	return firearm_sys.strike_point(target, direction, reach)
func call_artillery(target: Vector3, direction: Vector3) -> void:
	firearm_sys.call_artillery(target, direction)
func call_naval_gun(target: Vector3, direction: Vector3) -> void:
	firearm_sys.call_naval_gun(target, direction)
func tick_shells(dt: float) -> void:
	firearm_sys.tick_shells(dt)
func leech(dealt: float) -> void:
	firearm_sys.leech(dealt)
func tick_fires(dt: float) -> void:
	firearm_sys.tick_fires(dt)
func clear_barrage() -> void:
	firearm_sys.clear_barrage()
func smoke_seconds() -> float:
	return firearm_sys.smoke_seconds()
func launch_smoke(target: Vector3, direction: Vector3) -> void:
	firearm_sys.launch_smoke(target, direction)
func tick_smokes(dt: float) -> void:
	firearm_sys.tick_smokes(dt)
func hidden_between(a: Vector3, b: Vector3) -> bool:
	return firearm_sys.hidden_between(a, b)
func blinded(enemy: Dictionary) -> bool:
	return firearm_sys.blinded(enemy)
func gatling_interval() -> float:
	return firearm_sys.gatling_interval()
func fire_gatling(direction: Vector3) -> void:
	firearm_sys.fire_gatling(direction)
func begin_shotgun_visual(target: Vector3, at_enemy: bool = false) -> void:
	firearm_sys.begin_shotgun_visual(target, at_enemy)
func push_back(id: String, distance: float, seconds: float, from = null) -> void:
	firearm_sys.push_back(id, distance, seconds, from)
func fire_shotgun(target: Vector3, at_enemy: bool = false) -> void:
	firearm_sys.fire_shotgun(target, at_enemy)
func tick_twin_shots(dt: float) -> void:
	firearm_sys.tick_twin_shots(dt)
func recoil_leap(target: Vector3, direction: Vector3, at_enemy: bool) -> void:
	firearm_sys.recoil_leap(target, direction, at_enemy)

func passive_level(id: String) -> float:
	return float(config.passive_levels.get(id, 0))

func power_upkeep_cut() -> float:
	# ...and lend a little to the drive tools' upkeep (03 §2.1 synergy).
	return float(config.passives.power_management.tool_upkeep_cut_per_level) * passive_level("power_management")

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
	# A plain left click on the floor walks there whatever LMB holds; the skill checks below
	# belong to attacks (an enemy click or Shift) only.
	var walking: bool = slot == "lmb" and not shift and cursor.get("enemy_id") == null
	var bound = null if walking else state.bindings[slot]
	if bound != null and not build.learned(bound):
		show_message("배우지 않은 기술입니다")
		return
	cursor = device_cursor(bound, cursor)
	if bound in TOOL_ATTACKS and state.active_tool == null:
		# Tool attacks work only through a transformed tool, never the bare staff (03 §2). On LMB
		# the staff's basic attack goes out instead (press_slot); other keys do nothing.
		show_message("공구를 전개해야 쓸 수 있습니다")
		if slot != "lmb":
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
	var result: Dictionary = press_slot(slot, cursor, checker, shift)
	var final_event: Dictionary = result.events[-1]
	if not stationary and final_event.type == "cast_failed" and final_event.reason == "out_of_range":
		# Dry-run availability/fallback checks; discard its resource/cooldown state.
		var probe: Dictionary = press_slot(slot, cursor, spatial_without_range, shift)
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

func press_slot(slot: String, cursor: Dictionary, spatial: Callable, shift: bool) -> Dictionary:
	# rules.press, except that a tool attack on LMB with no tool out answers with the staff's basic
	# attack. The real bindings stay in the resulting state, so binding-change checks still hold.
	if slot != "lmb" or state.bindings.lmb not in TOOL_ATTACKS or state.active_tool != null:
		return rules.press(state, slot, cursor, spatial, shift)
	var stand_in: Dictionary = state.duplicate(true)
	stand_in.bindings.lmb = rules.basic_id
	var result: Dictionary = rules.press(stand_in, slot, cursor, spatial, shift)
	result.state.bindings = state.bindings.duplicate(true)
	return result

# device_sys: arena_devices.gd (delegates keep arena's existing surface).
func device_cursor(bound, cursor: Dictionary) -> Dictionary:
	return device_sys.device_cursor(bound, cursor)
func device_plan(skill_id: String) -> Dictionary:
	return device_sys.device_plan(skill_id)
func begin_device_visual(skill_id: String, target: Vector3, direction: Vector3) -> Node3D:
	return device_sys.begin_device_visual(skill_id, target, direction)
func place_device(skill_id: String, target: Vector3, direction: Vector3) -> void:
	device_sys.place_device(skill_id, target, direction)
func tick_devices(dt: float) -> void:
	device_sys.tick_devices(dt)
func tool_marked(enemy: Dictionary) -> bool:
	return device_sys.tool_marked(enemy)
func restrain(id: String, kind: String, seconds: float) -> bool:
	return device_sys.restrain(id, kind, seconds)
func press_stun_seconds(base: float) -> float:
	return device_sys.press_stun_seconds(base)
func executor_synergy(part: String) -> float:
	return device_sys.executor_synergy(part)
func fire_winch(event: Dictionary, direction: Vector3) -> void:
	device_sys.fire_winch(event, direction)
func tick_winches(dt: float) -> void:
	device_sys.tick_winches(dt)
func clear_devices() -> void:
	device_sys.clear_devices()
func exo_level() -> float:
	return device_sys.exo_level()
func exo_plan() -> Dictionary:
	return device_sys.exo_plan()
func exo_active() -> bool:
	return device_sys.exo_active()
func exo_tool_bonus() -> float:
	return device_sys.exo_tool_bonus()
func exo_armor() -> float:
	return device_sys.exo_armor()
func exo_upkeep_cut() -> float:
	return device_sys.exo_upkeep_cut()
func exo_tool_factor() -> float:
	return device_sys.exo_tool_factor()
func exo_stun_factor() -> float:
	return device_sys.exo_stun_factor()
func sync_exo_visual(dt: float) -> void:
	device_sys.sync_exo_visual(dt)

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
	elif cast.skill in Batch2Summons.SKILLS:
		windup.visual_duration = windup.release
		batch2.begin_preview(cast.skill, snapshot)
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
	if not batch2.preview.is_empty():
		batch2.sample_preview(1.0 - float(windup.release) / maxf(0.0001, float(windup.visual_duration)))
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
	var result: Dictionary = press_slot(started.slot, cursor, checker, started.shift)
	if result.events[-1].get("reason") == "out_of_range":
		# A whiff stays silent; the missing hit sound and effect tell it apart.
		last_events = result.events
		probe.record(last_events)
		cancel_summon_assemblies("out_of_range")
		return
	apply_transition(result)
	# A failed recheck or LMB fallback must collapse its preview too.
	cancel_summon_assemblies("release_failed")

func cancel_summon_assemblies(reason: String) -> void:
	if is_instance_valid(player_visual):player_visual.cancel_spring_preparation()
	if is_instance_valid(automaton_assembly):
		automaton_assembly.cancel(reason)
	automaton_assembly = null
	if is_instance_valid(turret_assembly):
		turret_assembly.cancel(reason)
	turret_assembly = null
	batch2.cancel_preview(reason)
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

# tool_sys: arena_tools.gd (delegates keep arena's existing surface).
func tool_speed(base: float) -> float:
	return tool_sys.tool_speed(base)
func tool_attack_plan(skill_id: String, tool) -> Dictionary:
	return tool_sys.tool_attack_plan(skill_id, tool)
func tool_attack_seconds(skill_id: String, tool) -> float:
	return tool_sys.tool_attack_seconds(skill_id, tool)
func tool_hit_damage(skill_id: String, plan: Dictionary) -> float:
	return tool_sys.tool_hit_damage(skill_id, plan)
func start_tool_channel(tool, direction: Vector3) -> void:
	tool_sys.start_tool_channel(tool, direction)
func tool_area(tool, direction: Vector3) -> void:
	tool_sys.tool_area(tool, direction)
func tick_sweep(dt: float) -> void:
	tool_sys.tick_sweep(dt)
func start_channel(target: Vector3, direction: Vector3) -> void:
	tool_sys.start_channel(target, direction)
func stop_channel(exit: bool = false) -> void:
	tool_sys.stop_channel(exit)
func tick_channel(dt: float) -> void:
	tool_sys.tick_channel(dt)

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
	var cast = cast_event(press_slot(slot, cursor, spatial_without_range, true))
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
	var probe: Dictionary = press_slot(slot, cursor, spatial_without_range, true)
	var cast = cast_event(probe)
	if cast.is_empty():
		cancel_pending_cast()
		apply_transition(probe)
		return
	var skill: Dictionary = rules.skills[cast.skill]
	if spatial_check(skill, cursor) == null:
		cancel_pending_cast()
		begin_cast(slot, cursor, true, false, press_slot(slot, cursor, spatial_check, true))
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
		"hound", "beacon", "giant":
			batch2.summon(event)
		"relay":
			var linked: Array = []
			for ally in allies:
				# The beacon only calls enemies over; it takes no orders.
				if ally.get("summon", "") != "beacon" and eligible(ally, event.target_enemy):
					ally.target = event.target_enemy
					ally.relayed = event.target_enemy
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

# damage_sys: arena_damage.gd (delegates keep arena's existing surface).
func hit_chance(id: String, roller: String = "witch") -> float:
	return damage_sys.hit_chance(id, roller)
func crit_chance(roller: String = "witch") -> float:
	return damage_sys.crit_chance(roller)
func attack_range() -> Vector2:
	return damage_sys.attack_range()
func attack_median() -> float:
	return damage_sys.attack_median()
func roll_attack(crit: bool) -> float:
	return damage_sys.roll_attack(crit)
func attack_factor(attack: float) -> float:
	return damage_sys.attack_factor(attack)
func spread_factor(width: float) -> float:
	return damage_sys.spread_factor(width)
func armor() -> float:
	return damage_sys.armor()
func summon_guard() -> float:
	return damage_sys.summon_guard()
func armor_reduction(level: int = -1) -> float:
	return damage_sys.armor_reduction(level)
func strike(id: String, amount: float, accuracy_roll: bool, roller: String, source: String, look: String = "", label: String = "") -> String:
	return damage_sys.strike(id, amount, accuracy_roll, roller, source, look, label)
func passive_factor(attack: String) -> float:
	return damage_sys.passive_factor(attack)
func flinch_seconds(enemy: Dictionary) -> float:
	return damage_sys.flinch_seconds(enemy)
func flinch(enemy: Dictionary, scale: float = 1.0, forced: bool = false) -> void:
	damage_sys.flinch(enemy, scale, forced)
func interrupt_attack(enemy: Dictionary) -> void:
	damage_sys.interrupt_attack(enemy)
func damage_enemy(id: String, amount: float, direct: bool = true) -> float:
	return damage_sys.damage_enemy(id, amount, direct)
func bleed_plan(stacks: int) -> Dictionary:
	return damage_sys.bleed_plan(stacks)
func add_bleed(id: String) -> void:
	damage_sys.add_bleed(id)
func tick_bleeds(dt: float) -> void:
	damage_sys.tick_bleeds(dt)
func shield_duration() -> float:
	return damage_sys.shield_duration()
func block_chance() -> float:
	return damage_sys.block_chance()
func hit_recovery_seconds() -> float:
	return damage_sys.hit_recovery_seconds()
func damage_player(amount: float, by_grade: String = "unknown") -> void:
	damage_sys.damage_player(amount, by_grade)

# potion_sys: arena_potions.gd (delegates keep arena's existing surface).
func potion_cooldown(id: String) -> float:
	return potion_sys.potion_cooldown(id)
func drink(index: int) -> void:
	potion_sys.drink(index)
func arrange_potions() -> void:
	potion_sys.arrange_potions()
func store_potion(id: String, count: int) -> bool:
	return potion_sys.store_potion(id, count)
func move_potion_cell(from: int, to: int) -> void:
	potion_sys.move_potion_cell(from, to)
func put_quickslot_in_bag(index: int, cell: int) -> bool:
	return potion_sys.put_quickslot_in_bag(index, cell)
func move_potion_quickslot(from: int, to: int) -> void:
	potion_sys.move_potion_quickslot(from, to)
func buy_potion(id: String) -> bool:
	return potion_sys.buy_potion(id)
func assign_quickslot(index: int, id: String) -> bool:
	return potion_sys.assign_quickslot(index, id)
func fill_quickslot(index: int) -> void:
	potion_sys.fill_quickslot(index)
func potion_factor() -> float:
	return potion_sys.potion_factor()
func cycle_potion(index: int) -> void:
	potion_sys.cycle_potion(index)
func tick_potions(dt: float) -> void:
	potion_sys.tick_potions(dt)
func pending_fill(key: String) -> float:
	return potion_sys.pending_fill(key)

func on_screen(pos: Vector3) -> bool:
	if camera.is_position_behind(pos):
		return false
	var screen = camera.unproject_position(pos)
	var rect = get_viewport().get_visible_rect()
	rect.size.y -= 155
	return rect.has_point(screen)

func eligible(ally: Dictionary, id: String) -> bool:
	return enemies.has(id) and on_screen(enemies[id].body.position) and ally.node.position.distance_to(enemies[id].body.position) <= detection_range(ally) and map.sees(ally.node.position, enemies[id].body.position)

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
