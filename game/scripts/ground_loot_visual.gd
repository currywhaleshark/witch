extends RefCounted
## Four authored drop candidates. All geometry shares the existing drop transform.
const FOLDER = "res://assets/props/ground_loot_v1/"
const IDS = ["health_s", "copper_ring", "part_cutting", "cotton_coat"]
static var scenes: Dictionary = {}
static var profiles: Dictionary = {}

static func create(parent: Node3D, payload: Dictionary) -> Dictionary:
	var id: String = payload.get("id", "")
	if payload.kind == "equipment":
		# A unique has its own design and must not borrow its base's candidate.
		id = payload.item.get("unique", payload.item.base)
	elif payload.kind != "potion":
		return {}
	if id not in IDS:
		return {}
	if profiles.is_empty():
		profiles = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "models.json"))
	if not scenes.has(id):
		scenes[id] = load(FOLDER + id + ".glb")
	var visual := Node3D.new()
	visual.name = "GroundLoot_" + id
	parent.add_child(visual)
	visual.add_child(scenes[id].instantiate())
	var materials: Array = []
	collect_materials(visual, materials)
	visual.set_meta("loot_materials", materials)
	visual.set_meta("loot_model", id)
	visual.set_meta("loot_highlighted", false)
	return {"visual": visual, "rest_height": float(profiles[id].rest_height)}

static func collect_materials(node: Node, materials: Array) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				node.set_surface_override_material(surface, material)
				materials.append({"material": material, "color": material.albedo_color,
					"enabled": material.emission_enabled, "emission": material.emission,
					"energy": material.emission_energy_multiplier})
	for child in node.get_children():
		collect_materials(child, materials)

static func highlight(visual: Node3D, active: bool, color: Color) -> void:
	if visual.has_meta("loot_materials"):
		for entry in visual.get_meta("loot_materials"):
			var material: StandardMaterial3D = entry.material
			material.albedo_color = entry.color.lerp(Color.WHITE, 0.22) if active else entry.color
			material.emission_enabled = true if active else entry.enabled
			material.emission = entry.color if active else entry.emission
			material.emission_energy_multiplier = 0.55 if active else entry.energy
		visual.set_meta("loot_highlighted", active)
	else:
		var material: StandardMaterial3D = visual.material_override
		material.albedo_color = color.lerp(Color.WHITE, 0.45) if active else color
		material.emission_enabled = active
		material.emission = color
		material.emission_energy_multiplier = 0.9

static func highlighted(visual: Node3D) -> bool:
	if visual.has_meta("loot_highlighted"):
		return visual.get_meta("loot_highlighted")
	return visual.material_override.emission_enabled
