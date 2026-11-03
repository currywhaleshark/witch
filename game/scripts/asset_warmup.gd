extends Node3D
## Start-of-game warmup behind the loading screen, so the field entry and first casts don't stall.
## 1) threaded loads of assets that are otherwise loaded on first use (transformed outfit, actors,
##    ground loot models),
## 2) the transformed outfit's texture content keys (the modular runtime hashes texture pixels),
## 3) one rendered frame of every part model and effect shader, so the Compatibility renderer
##    compiles their shaders now instead of mid-combat.
## Presentation only: no gameplay state, clocks or RNG are touched.
signal finished
const ModularRuntime = preload("res://scripts/modular_character_runtime.gd")
const ActorVisual = preload("res://scripts/actor_visual.gd")
const FieldEntry = preload("res://scripts/field_entry_transformation.gd")
const OutfitReveal = preload("res://scripts/outfit_reveal.gd")
const GroundLootVisual = preload("res://scripts/ground_loot_visual.gd")
const Shape = preload("res://scripts/shapes.gd")
const FloatingGun = preload("res://scripts/floating_gun.gd")
const PowderKeg = preload("res://scripts/powder_keg.gd")
const GatlingGun = preload("res://scripts/gatling_gun.gd")
const SmokeLauncher = preload("res://scripts/smoke_launcher.gd")
const IncomingShell = preload("res://scripts/incoming_shell.gd")
const STAFF := "res://assets/weapons/staff_material_v3/staff_parts.glb"
const PART_SCRIPTS := ["res://scripts/automaton_assembly.gd", "res://scripts/turret_assembly.gd",
	"res://scripts/shotgun_cast.gd", "res://scripts/spring_plate.gd", "res://scripts/shield_visual.gd"]
const SHADERS := ["res://shaders/vfx_glow.gdshader", "res://shaders/vfx_smoke.gdshader", "res://shaders/cast_circle.gdshader",
	"res://shaders/warning_zone.gdshader", "res://shaders/outline.gdshader", "res://shaders/grade_aura.gdshader",
	"res://shaders/silhouette_mask.gdshader", "res://shaders/alley_gear_reveal.gdshader"]
# Loaded resources stay referenced so later load() calls hit Godot's resource cache.
static var held: Dictionary = {}
var progress := 0.0
var step := "에셋 불러오는 중"
var done := false

func run(camera: Camera3D) -> void:
	var paths: Array = [FieldEntry.OUTFIT, STAFF]
	paths.append_array(ActorVisual.FILES.values())
	paths.append_array(loot_paths())
	paths.append_array(SHADERS)
	var pending: Array = paths.filter(func(path): return not held.has(path) and ResourceLoader.exists(path))
	for path in pending:
		ResourceLoader.load_threaded_request(path)
	while not pending.is_empty():
		for path in pending.duplicate():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			# A failed load is left to the original on-demand path and its error handling.
			held[path] = ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED else null
			pending.erase(path)
		progress = 0.6 * (1.0 - float(pending.size()) / maxf(1.0, paths.size()))
		await get_tree().process_frame
	# The first drop of each loot model reuses these scenes instead of loading its GLB mid-combat.
	for id in GroundLootVisual.profiles:
		if held.get(GroundLootVisual.profiles[id].path) is PackedScene:
			GroundLootVisual.scenes[id] = held[GroundLootVisual.profiles[id].path]
	step = "변신 의상 준비 중"
	var outfit: PackedScene = held.get(FieldEntry.OUTFIT)
	if outfit != null:
		var probe := outfit.instantiate()
		var textures: Array = []
		for mesh: MeshInstance3D in probe.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if material != null and material.albedo_texture != null and material.albedo_texture not in textures:
					textures.append(material.albedo_texture)
		probe.free()
		for i in textures.size():
			ModularRuntime.content_key(textures[i])
			progress = 0.6 + 0.2 * float(i + 1) / textures.size()
			await get_tree().process_frame
	step = "그래픽 준비 중"
	progress = 0.8
	await get_tree().process_frame
	_stage(camera)
	# A few drawn frames let every material and shader variant compile behind the overlay.
	for i in 4:
		await get_tree().process_frame
		progress = 0.8 + 0.05 * (i + 1)
	for child in get_children():
		child.free()
	progress = 1.0
	done = true
	finished.emit()

func loot_paths() -> Array:
	if GroundLootVisual.profiles.is_empty():
		var profiles = JSON.parse_string(FileAccess.get_file_as_string(GroundLootVisual.PROFILE_PATH))
		if not profiles is Dictionary:
			return []
		GroundLootVisual.profiles = profiles
	var paths: Array = []
	for id in GroundLootVisual.profiles:
		var path: String = GroundLootVisual.profiles[id].path
		if path not in paths:
			paths.append(path)
	return paths

func _stage(camera: Camera3D) -> void:
	# The orthographic camera looks at its focus 30m ahead; lay everything out around it.
	global_position = camera.global_position - camera.global_basis.z * 30.0
	var scenes: Array = [held.get(FieldEntry.OUTFIT), held.get(STAFF)]
	scenes.append_array(FloatingGun.MODELS.values())
	scenes.append(PowderKeg.MODEL)
	scenes.append(GatlingGun.MODEL)
	scenes.append(SmokeLauncher.MODEL)
	scenes.append_array(IncomingShell.MODELS.values())
	for path in ActorVisual.FILES.values():
		scenes.append(held.get(path))
	for path in PART_SCRIPTS:
		var constants: Dictionary = (load(path) as Script).get_script_constant_map()
		scenes.append(constants.get("PARTS"))
		var variants = constants.get("VARIANT_PARTS")
		if variants is Dictionary:
			scenes.append_array(variants.values())
	var slot := 0
	for scene in scenes:
		if scene is PackedScene:
			_place(scene.instantiate(), slot)
			slot += 1
	# The outfit reveal swaps skinned outfit surfaces to its own shader; compile that variant too.
	if held.get(FieldEntry.OUTFIT) is PackedScene:
		var revealed: Node3D = held[FieldEntry.OUTFIT].instantiate()
		for mesh: MeshInstance3D in revealed.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material := ShaderMaterial.new()
				material.shader = OutfitReveal.SHADER
				mesh.set_surface_override_material(surface, material)
		_place(revealed, slot)
		slot += 1
	# Ground loot is small: a dense grid of each model as dropped and as hover-highlighted,
	# plus the selection ring drawn under a hovered item.
	var loot: Array = loot_paths().filter(func(path): return held.get(path) is PackedScene)
	for i in loot.size():
		for lit in [false, true]:
			var model: Node3D = held[loot[i]].instantiate()
			if lit:
				var visual := Node3D.new()
				visual.add_child(model)
				var materials: Array = []
				GroundLootVisual.collect_materials(visual, materials)
				visual.set_meta("loot_materials", materials)
				GroundLootVisual.highlight(visual, true, Color.WHITE)
				model = visual
			add_child(model)
			model.position = Vector3((i % 10) - 4.5, 0.0, int(i / 10) * 2 + int(lit) - 3.5) * 0.5
	var ring := Node3D.new()
	Shape.ring(ring, Vector3.ZERO, 0.27, Color("fff1c4"), 0.025)
	_place(ring, slot)
	slot += 1
	for path in SHADERS:
		if held.get(path) is Shader:
			var quad := MeshInstance3D.new()
			quad.mesh = QuadMesh.new()
			var material := ShaderMaterial.new()
			material.shader = held[path]
			quad.material_override = material
			_place(quad, slot)
			slot += 1

func _place(node: Node3D, slot: int) -> void:
	add_child(node)
	node.position = Vector3((slot % 6) - 2.5, 0.0, int(slot / 6) - 1.5) * 1.6
	for child in node.find_children("*", "Node3D", true, false):
		child.visible = true
