extends "res://tests/ground_loot_art.gd"
## Complete-set art integration. Gameplay definitions supply the coverage set.
var catalogue: Array = []
var potion_projected_bounds: Dictionary = {}
var groups := {
	"mediums": ["glass_orb", "crystal_core", "bp_shotgun", "bp_chainsaw", "bp_automaton"],
	"machines": ["part_cutting", "part_ballistic", "part_power", "executioner_pulley", "self_replicating_spring"],
	"clothing": ["cotton_coat", "quilted_cape", "cotton_gloves", "work_gloves", "sneakers", "leather_boots"],
	"jewelry": ["ribbon_tie", "star_pin", "brass_brooch", "silver_brooch", "copper_ring", "silver_ring"],
	"health": ["health_s", "health_m", "health_l", "full_health"],
	"mana": ["mana_s", "mana_m", "mana_l", "full_mana"],
	"recovery": ["rejuv_s", "rejuv_m", "rejuv_l", "full_rejuv", "speed"],
	"resources": ["currency", "bel", "rok", "sha"]}

func equipment(id: String) -> Dictionary:
	if arena.items.uniques.has(id):
		var unique: Dictionary = arena.items.uniques[id]
		var item := super.equipment(unique.base)
		item.unique = id
		item.name = unique.name
		item.rarity = "unique"
		return item
	return super.equipment(id)

func spawn(id: String, point: Vector3) -> Dictionary:
	if arena.config.potions.has(id):
		arena.drop_resource("potion", id, 1, point)
	elif id == "currency":
		arena.drop_resource("currency", "", 7, point)
	elif arena.items.data.pieces.has(id):
		arena.drop_resource("piece", id, 1, point)
	else:
		arena.drop_item(equipment(id), point)
	return arena.ground_items[-1]

func own_count(id: String) -> int:
	if arena.config.potions.has(id):
		return arena.potion_stash[id]
	if id == "currency":
		return arena.coins
	if arena.pieces.has(id):
		return arena.pieces[id]
	return arena.bag.size()

func mesh_counts(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		result.meshes += 1
		result.surfaces += node.mesh.get_surface_count()
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result.triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size() / 3
			result.colors = result.colors and arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty()
	for child in node.get_children():
		mesh_counts(child, result)

func inspect(id: String, point: Vector3) -> void:
	clear_drops()
	arena.bag.clear()
	var combat_state: int = arena.combat_rng.state
	var loot_state: int = arena.loot_rng.state
	var loot := spawn(id, point)
	check(arena.combat_rng.state == combat_state and arena.loot_rng.state == loot_state, id + " creation does not consume gameplay RNG")
	check(loot.visual.get_meta("loot_model", "") == id, id + " resolves its exact authored profile")
	var counts := {"meshes": 0, "surfaces": 0, "triangles": 0, "colors": true}
	mesh_counts(loot.visual, counts)
	if id not in ["health_s", "copper_ring", "part_cutting", "cotton_coat"]:
		check(counts.meshes == 1 and counts.surfaces <= 3 and counts.colors, id + " runtime mesh retains vertex color with <=3 surfaces")
	var destination: Vector3 = loot.node.position
	var floor_clear := true
	for frame in 48:
		arena.tick_ground_loot(0.4 / 48)
		var points: Array = []
		vertices(loot.visual, points)
		for p in points:
			floor_clear = floor_clear and p.y >= arena.map.grounded(loot.node.position).y - 0.002
	check(floor_clear, id + " actual vertices remain above flat ground through 48 tumble samples")
	check(loot.node.position == destination and loot.visual.position.length() < 0.0001, id + " unchanged 0.4s landing without destination drift")
	var points: Array = []
	vertices(loot.visual, points)
	var bottom: float = INF
	var radius := 0.0
	for p in points:
		bottom = minf(bottom, p.y - arena.map.grounded(loot.node.position).y)
		radius = maxf(radius, Vector2(p.x-loot.node.position.x, p.z-loot.node.position.z).length())
	check(absf(bottom - 0.012) < 0.002 and radius < 0.35, id + " true floor support and spacing footprint")
	var duplicate := spawn(id, point + arena.camera.basis.x * 1.1)
	arena.tick_ground_loot(5)
	arena.update_loot_hover(arena.camera.unproject_position(loot.visual.global_position))
	check(is_same(arena.hovered_loot, loot) and loot.selection.visible and arena.loot_labels().size() == 1, id + " hover selects its actual center and expired label")
	var materials: Array = loot.visual.get_meta("loot_materials")
	check(materials.all(func(m): return m.material.emission_enabled) and not arena.GroundLootVisual.highlighted(duplicate.visual), id + " all surfaces highlight independently")
	arena.set_hovered_loot({})
	check(materials.all(func(m): return m.material.albedo_color == m.color and m.material.emission_enabled == m.enabled and m.material.emission == m.emission and m.material.emission_energy_multiplier == m.energy), id + " full PBR highlight state restored")
	var before := own_count(id)
	arena.player.position = loot.node.position
	arena.pick_up(loot)
	check(not arena.ground_items.has(loot) and own_count(id) == before + (7 if id == "currency" else 1), id + " exact original ownership change")
	if loot.kind == "equipment":
		check(arena.bag[-1].get("unique", arena.bag[-1].base) == id, id + " base or unique identity survives pickup")
	await process_frame
	check(not is_instance_valid(loot.node), id + " picked-up hierarchy freed")
	catalogue.append({"id": id, "triangles": counts.triangles, "meshes": counts.meshes, "surfaces": counts.surfaces, "floor_clearance": bottom, "radius": radius})

func group_lineup(ids: Array, center: Vector3) -> void:
	clear_drops()
	var right: Vector3 = arena.camera.basis.x
	for i in ids.size():
		spawn(ids[i], center + right * (i-(ids.size()-1)/2.0) * 0.75)

func projected_area(loot: Dictionary) -> float:
	var points: Array = []
	vertices(loot.visual, points)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		var screen: Vector2 = arena.camera.unproject_position(point)
		low = low.min(screen)
		high = high.max(screen)
	var size := high - low
	return size.x * size.y

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/ground_loot_v2")
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.make_dir_recursive_absolute(output.path_join("details"))
	arena = load("res://main.tscn").instantiate()
	arena.field_entry_mode = 2
	arena.preload_mode = 2
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await physics_frame
	await physics_frame
	model_ids = arena.items.bases.keys() + arena.items.uniques.keys() + arena.config.potions.keys() + ["currency"] + arena.pieces.keys()
	check(model_ids.size() == 39, "39 existing item/resource definitions covered")
	var origin: Vector3 = arena.player.position + Vector3(0, 0, -1)
	for id in model_ids:
		await inspect(id, origin)
	clear_drops()
	var container := Node3D.new()
	root.add_child(container)
	check(arena.GroundLootVisual.create(container, {"kind":"potion", "id":"unknown_future_item"}).is_empty(), "unknown future definitions retain the existing fallback")
	container.free()
	# Keep the source gameplay camera/lighting. Rebuild and wait for the raised alley.
	arena.map.build(arena.config.map)
	arena.map.apply_lighting(arena.env, arena.sun)
	arena.reset_arena()
	arena.set_physics_process(false)
	await physics_frame
	await physics_frame
	for frame in 180:
		if arena.map.nav_ready(): break
		await physics_frame
	check(arena.map.nav_ready(), "alley navigation ready before actual-floor captures")
	arena.player.position = arena.map.grounded(arena.map.snap(Vector3(46,1.2,-4)))
	arena.place_camera(arena.player.position)
	for enemy in arena.enemies.values():
		enemy.body.hide()
		enemy.body.position = Vector3(500,0,500)
	var native_size: float = arena.camera.size
	var native_pose: Transform3D = arena.camera.transform
	var front := Vector3(arena.camera.basis.z.x,0,arena.camera.basis.z.z).normalized()
	var center: Vector3 = arena.player.position + front*1.2
	for category in groups:
		arena.camera.size = native_size
		arena.camera.transform = native_pose
		arena.hud.visible = true
		group_lineup(groups[category], center)
		await capture(category + "_launch")
		arena.tick_ground_loot(.13)
		await capture(category + "_tumble")
		arena.tick_ground_loot(.28)
		if category in ["health", "mana", "recovery"]:
			var small := projected_area(arena.ground_items[0])
			var medium := projected_area(arena.ground_items[1])
			var large := projected_area(arena.ground_items[2])
			potion_projected_bounds[category] = {"small": small, "medium": medium, "large": large}
			check(medium > small * 1.05 and large > medium * 1.05, category + " small/medium/large increase in native projected bounds")
		for loot in arena.ground_items:
			var points: Array = []
			vertices(loot.visual, points)
			var bottom: float = INF
			for p in points: bottom = minf(bottom,p.y-arena.map.grounded(loot.node.position).y)
			check(absf(bottom-.012)<.002, str(loot.visual.get_meta("loot_model")) + " actual raised alley support")
		await capture(category + "_native")
		arena.tick_ground_loot(5)
		await capture(category + "_hidden")
		arena.update_loot_hover(arena.camera.unproject_position(arena.ground_items[0].visual.global_position))
		await capture(category + "_hover")
		arena.set_hovered_loot({})
		arena.hud.visible = false
		arena.camera.size = native_size / 2.7
		arena.camera.position = center + arena.camera.basis.z*30
		await capture(category + "_detail")
	# One larger actual-engine view per item; no extra studio light or shader substitution.
	for id in model_ids:
		clear_drops()
		var loot := spawn(id,center)
		arena.tick_ground_loot(5)
		arena.camera.size = .86
		arena.camera.position = loot.node.position + arena.camera.basis.z * 20
		await capture("details/" + id)
	clear_drops()
	var fresh := spawn("self_replicating_spring",center)
	arena.tick_ground_loot(.12)
	var pose: Transform3D = fresh.visual.transform
	arena.paused = true
	arena.tick_ground_loot(1)
	check(fresh.visual.transform == pose, "pause freezes complete new hierarchy")
	arena.paused = false
	arena.reset_arena()
	check(arena.ground_items.is_empty() and not is_instance_valid(fresh.node), "reset frees new hierarchy")
	var report := {"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"captures":shots,"scope":model_ids,"catalogue":catalogue,"groups":groups,"native_camera_size":native_size,"potion_projected_bounds":potion_projected_bounds}
	FileAccess.open(output.path_join("runtime.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("GROUND_LOOT_V2_RESULT checks=%d failures=%s" % [checks.size(),str(failures)])
	quit(0 if failures.is_empty() else 1)
