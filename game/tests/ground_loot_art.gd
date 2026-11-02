extends SceneTree
## Authored loot integration: real geometry bounds, independent hover, pickup and game captures.
var arena: Node3D
var checks: Array = []
var failures: Array = []
var output := "res://../reports/ground_loot_v1"
var model_ids := ["health_s", "copper_ring", "part_cutting", "cotton_coat"]
var shots: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error(label)

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	arena.hud.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " capture")
	shots.append(name + ".png")

func vertices(node: Node, result: Array) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for point in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				result.append(node.global_transform * point)
	for child in node.get_children():
		vertices(child, result)

func equipment(id: String) -> Dictionary:
	var base: Dictionary = arena.items.bases[id]
	return {"base": id, "slot": base.slot, "rarity": "rare", "level": 20, "options": {}, "affixes": [], "name": base.name, "sockets": 0, "pieces": []}

func spawn(id: String, point: Vector3) -> Dictionary:
	if id == "health_s":
		arena.drop_resource("potion", id, 1, point)
	else:
		arena.drop_item(equipment(id), point)
	return arena.ground_items[-1]

func clear_drops() -> void:
	arena.set_hovered_loot({})
	for loot in arena.ground_items:
		loot.node.free()
	arena.ground_items.clear()
	arena.loot_target = {}
	arena.loot_layout.invalidate()

func lineup() -> Vector3:
	clear_drops()
	var right: Vector3 = arena.camera.basis.x
	var front := Vector3(arena.camera.basis.z.x, 0, arena.camera.basis.z.z).normalized()
	var center: Vector3 = arena.player.position + front * 1.15
	for i in model_ids.size():
		spawn(model_ids[i], center + right * (i - 1.5) * 0.85)
	return center

func run() -> void:
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await physics_frame
	await physics_frame
	var old_combat: int = arena.combat_rng.state
	var old_loot: int = arena.loot_rng.state
	lineup()
	check(arena.combat_rng.state == old_combat and arena.loot_rng.state == old_loot, "authored visual creation does not consume gameplay RNG")
	var originals: Array = arena.ground_items.duplicate()
	var destinations: Array = []
	for i in model_ids.size():
		var loot: Dictionary = originals[i]
		destinations.append(loot.node.position)
		check(loot.visual.get_meta("loot_model", "") == model_ids[i], model_ids[i] + " uses its authored model")
		check(loot.visual.get_meta("loot_materials", []).size() > 1, model_ids[i] + " retains multiple authored materials")
		check(is_equal_approx(loot.visual.position.y, 0.95), model_ids[i] + " starts at the existing waist-height offset")
	await capture("flat_launch")
	var floors_clear := true
	var motion_selectable := true
	for frame in range(1, 25):
		arena.tick_ground_loot(0.4 / 24.0)
		for loot in originals:
			var points: Array = []
			vertices(loot.visual, points)
			for point in points:
				floors_clear = floors_clear and point.y >= arena.map.grounded(loot.node.position).y - 0.002
			motion_selectable = motion_selectable and is_same(arena.loot_at(arena.camera.unproject_position(loot.visual.global_position)), loot)
		if frame == 8:
			await capture("flat_tumble")
	check(floors_clear, "sampled full mesh vertices remain above the flat floor throughout the drop")
	check(motion_selectable, "all four rotating models remain selectable at their visual centers")
	for i in originals.size():
		var loot: Dictionary = originals[i]
		check(loot.node.position == destinations[i] and loot.visual.position.length() < 0.0001, model_ids[i] + " lands after 0.4s without pickup destination drift")
		var points: Array = []
		vertices(loot.visual, points)
		var bottom: float = INF
		var radius := 0.0
		for point in points:
			bottom = minf(bottom, point.y - arena.map.grounded(loot.node.position).y)
			radius = maxf(radius, Vector2(point.x-loot.node.position.x, point.z-loot.node.position.z).length())
		check(absf(bottom - 0.012) < 0.002 and radius < 0.35, model_ids[i] + " rests 12mm above the floor inside the shared spacing footprint")
	await capture("flat_native")
	var duplicate_loot := spawn("copper_ring", arena.player.position + Vector3(-2, 0, 0))
	arena.tick_ground_loot(5.0)
	for i in originals.size():
		var loot: Dictionary = originals[i]
		var material_states: Array = loot.visual.get_meta("loot_materials")
		arena.update_loot_hover(arena.camera.unproject_position(loot.visual.global_position))
		check(is_same(arena.hovered_loot, loot) and loot.selection.visible and arena.loot_labels().size() == 1, model_ids[i] + " hover reveals only its expired label")
		var lit := true
		for entry in material_states:
			lit = lit and entry.material.emission_enabled and entry.material.albedo_color != entry.color
		check(lit and not arena.GroundLootVisual.highlighted(duplicate_loot.visual), model_ids[i] + " highlights every surface without changing another instance")
		arena.update_loot_hover(Vector2(2, 2))
		var restored := true
		for entry in material_states:
			restored = restored and entry.material.albedo_color == entry.color and entry.material.emission_enabled == entry.enabled and entry.material.emission == entry.emission
		check(restored, model_ids[i] + " restores exact material colors and emission")
	arena.bag.clear()
	var potion_count: int = arena.potion_stash.health_s
	for loot in originals:
		arena.player.position = loot.node.position
		arena.pick_up(loot)
		check(not arena.ground_items.has(loot), loot.name + " picks up through the original ownership path")
	check(arena.bag.size() == 3 and arena.potion_stash.health_s == potion_count+1, "four model pickups grant exactly three equipment items and one potion")
	await process_frame
	check(originals.all(func(loot): return not is_instance_valid(loot.node)), "picked-up model hierarchies are freed")
	clear_drops()
	# Actual alley geometry/lighting and ordinary game camera for the user's review.
	arena.map.build(arena.config.map)
	arena.map.apply_lighting(arena.env, arena.sun)
	arena.reset_arena()
	arena.set_physics_process(false)
	# Rebuilt collision/nav data must reach the physics server before sampling elevated floors.
	await physics_frame
	await physics_frame
	for frame in 180:
		if arena.map.nav_ready():
			break
		await physics_frame
	check(arena.map.nav_ready(), "alley navigation is ready before review placement")
	# The open middle courtyard keeps foreground wall cutaways out of the comparison.
	arena.player.position = arena.map.grounded(arena.map.snap(Vector3(46, 1.2, -4)))
	arena.place_camera(arena.player.position)
	for enemy in arena.enemies.values():
		enemy.body.hide()
		enemy.body.position = Vector3(500, 0, 500)
	var center := lineup()
	await capture("alley_launch")
	arena.tick_ground_loot(0.13)
	await capture("alley_tumble")
	arena.tick_ground_loot(0.28)
	for loot in arena.ground_items:
		var points: Array = []
		vertices(loot.visual, points)
		var lowest: float = INF
		for point in points:
			lowest = minf(lowest, point.y - arena.map.grounded(loot.node.position).y)
		check(absf(lowest - 0.012) < 0.002, loot.name + " rests above the actual elevated alley floor")
	await capture("alley_native")
	arena.tick_ground_loot(5.0)
	await capture("alley_hidden")
	for i in model_ids.size():
		arena.update_loot_hover(arena.camera.unproject_position(arena.ground_items[i].visual.global_position))
		await capture("alley_hover_" + model_ids[i])
	arena.set_hovered_loot({})
	arena.hud.visible = false
	var native_size: float = arena.camera.size
	arena.camera.size = native_size / 2.7
	arena.camera.position = center + arena.camera.basis.z * 30
	await capture("detail_lineup")
	# Pause/reset integration, using the actual new model hierarchy.
	clear_drops()
	var fresh := spawn("health_s", center)
	arena.tick_ground_loot(0.12)
	var pose: Transform3D = fresh.visual.transform
	arena.paused = true
	arena.tick_ground_loot(1.0)
	check(fresh.visual.transform == pose, "pause freezes the complete authored hierarchy")
	arena.paused = false
	arena.reset_arena()
	check(arena.ground_items.is_empty() and not is_instance_valid(fresh.node), "reset frees the complete authored hierarchy")
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "captures": shots, "native_camera_size": native_size, "scope": model_ids}
	FileAccess.open(output.path_join("runtime.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ")+"\n")
	print("GROUND_LOOT_ART_RESULT checks=%d failures=%s" % [checks.size(), str(failures)])
	quit(0 if failures.is_empty() else 1)
