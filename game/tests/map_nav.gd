extends SceneTree
## Fixed trial map v2 (08 §6.1 at 1.2x): runtime navmesh over floors and real stairs, routed movement,
## floor-following heights, sight lines, orbs vs walls, lot rows (walled houses, shopfronts), textured surfaces, wall fading,
## the boss arena trigger and map respawn spots.
const MAP = "alley_v2"
var arena: Node3D
var failures: Array = []
var checks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error(name)

func step(count: int = 1) -> void:
	for i in count:
		await physics_frame
		arena._physics_process(1.0 / 60.0)

func settle() -> void:
	# The navigation server adopts a freshly baked map a few physics frames later.
	for i in 20:
		if arena.map.nav_ready():
			return
		await step()

func fresh(witch: Vector3) -> void:
	# The trial map with no enemies; the witch placed by hand, standing on the floor below her.
	arena.load_map(MAP)
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	# The arena boss stays uncalled, so the field never counts as cleared mid-check.
	arena.boss_spawned = false
	await settle()
	arena.player.position = arena.map.grounded(witch)
	await step(1)

func enemy(kind: String, at: Vector3) -> Dictionary:
	arena.spawn_enemy("e", at, false, "normal", kind)
	return arena.enemies.e

func walk_until(done: Callable, frames: int) -> void:
	for i in frames:
		if done.call():
			return
		await step()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	check(arena.map.id == "flat", "test runs start on the flat arena")
	check(arena.config.map == MAP, "normal runs start on the v2 trial map")

	arena.load_map(MAP)
	await settle()
	var map: Node3D = arena.map
	check(map.region.navigation_mesh.get_polygon_count() > 0, "the map builds and bakes a navmesh")
	check(map.walkable(arena.player.position) and map.zone_at(arena.player.position).get("id") == "A" and is_zero_approx(arena.player.position.y), "the witch starts on low ground in zone A")
	check(arena.enemies.size() == map.data.spawns.size() and not arena.field_cleared(), "map spawns fill the zones and the boss keeps the field open")
	check(map.data.bounds[2] - map.data.bounds[0] > 80, "the v2 layout is the 1.2x scale of v1")

	check(is_equal_approx(map.ground_y(Vector3(40, 0, 0)), 1.2) and is_zero_approx(map.ground_y(Vector3(10, 0, 0))), "zone B stands 1.2m above the low alley")
	var mid: float = map.ground_y(Vector3(25.5, 0, 0))
	check(mid > 0.1 and mid < 1.1, "the stairs climb in between")

	var path: PackedVector3Array = map.route(map.start_point(), map.grounded(Vector3(72, 0, 4.8)))
	var walkable_path = true
	for p in path:
		walkable_path = walkable_path and map.walkable(Vector3(p.x, p.y, p.z))
	check(path.size() > 2 and Vector2(path[-1].x - 72, path[-1].z - 4.8).length() < 0.6 and walkable_path, "a route runs up the stairs to the boss arena over walkable ground")
	check(not map.walkable(map.grounded(Vector3(36.36, 0, 5.4))) and not map.walkable(Vector3(12, 0, 6)), "props and the void are not walkable")
	check(map.snap(Vector3(12, 0, 6)).z < 3.1, "a click past a fence snaps to the nearest walkable spot")

	check(not map.sees(map.grounded(Vector3(36.36, 0, 3.0)), map.grounded(Vector3(36.36, 0, 8.4))), "the tall phone booth blocks sight")
	check(map.sees(Vector3(8.4, 0, -0.48), Vector3(13.2, 0, -0.48)), "the low cart does not block sight")

	var front = 0
	var back = 0
	for entry in map.fadeable:
		if entry.rest < 1.0:
			front += 1
		else:
			back += 1
	check(front > 0 and back > 0, "camera-side lots rest see-through while far lots stay solid")
	var houses: Array = map.lots.filter(func(l): return l.kind == "house")
	var shops: Array = map.lots.filter(func(l): return l.kind == "shop")
	check(houses.any(func(l): return l.gate and l.building and not l.cut), "far house lots have a garden wall, a closed gate and a house set back behind a yard")
	check(shops.all(func(l): return l.piers == 0 and not l.gate) and shops.any(func(l): return l.building), "shop lots front the alley directly with no wall")
	var sign_texts: Array = map.find_children("*", "Label3D", true, false).map(func(label): return label.text)
	for decoration in map.decorations.nodes:
		if decoration.has_meta("sign_text"): sign_texts.append(decoration.get_meta("sign_text"))
	check(shops.any(func(l): return l.sign == "문방구" and l.building) and sign_texts.has("문방구"), "the shut stationery shop closes the dead-end alcove")
	check(map.lots.all(func(l): return l.piers <= (4 if l.gate else 2)), "walls keep piers to lot ends and gate posts")
	var trades_ok = true
	var hung = 0
	for l in map.lots:
		var business: String = l.body.get_meta("business", "")
		var allowed: Array = [map.decorations.VERTICAL_FOR.get(business, ""), map.decorations.AFRAME_FOR.get(business, "")] if business != "" else map.decorations.layout.home_signs.values()
		for node in l.body.find_children("Decoration_*", "MeshInstance3D", true, false):
			var trade: String = node.get_meta("decoration_id")
			if trade.begins_with("sign_v_") or trade.begins_with("aframe_"):
				hung += 1
				trades_ok = trades_ok and allowed.has(trade)
	check(hung > 0 and trades_ok, "projecting signs and A-frames repeat their own building's trade")
	check(not map.poles.is_empty() and map.poles.all(func(p): return map._floor_top(p.x, p.z) >= 0.0), "utility poles stand on the alley side of the walls")
	var ac_ok = true
	var units = 0
	var heaps_clear = true
	var heaps = 0
	for l in map.lots:
		for node in l.body.find_children("*", "Node3D", true, false):
			if node.has_meta("ac_bottom"):
				units += 1
				ac_ok = ac_ok and node.get_meta("ac_bottom") > l.ground + map.STOREY
			if node.has_meta("clutter"):
				heaps += 1
				var along: float = node.global_position.x if l.out in ["-z", "+z"] else node.global_position.z
				if l.has("gate_span"):
					heaps_clear = heaps_clear and (along + 0.8 < l.gate_span[0] - 0.35 or along - 0.8 > l.gate_span[1] + 0.35)
				for p in map.poles:
					heaps_clear = heaps_clear and node.global_position.distance_to(p) > 0.9
	check(units > 0 and ac_ok, "AC units hang above the ground floor, clear of entrances and signs")
	check(heaps > 0 and heaps_clear, "wall-side heaps keep clear of gates and poles")
	check(map.data.walls.all(func(w): return w.has("model")) and map.find_children("*", "Label3D", true, false).any(func(l): return l.text.contains("공중전화")), "roadside props are modelled (the phone booth carries its sign)")
	var stickers: Array = map.decorations.nodes.filter(func(n): return n.get_meta("decoration_id") in ["wall_gas_pipe", "wall_cables"])
	check(stickers.is_empty() and map.lots.any(func(l): return l.get("drop", Vector3.INF) != Vector3.INF), "gas risers, meters and service cables are modelled, not flat pictures")
	var cut_ok = true
	for l in map.lots.filter(func(l): return l.cut):
		for piece in l.body.find_children("*", "GeometryInstance3D", true, false):
			var box: AABB = piece.global_transform * piece.get_aabb()
			cut_ok = cut_ok and box.end.y <= l.ground + map.CUT_H + 0.01
	check(cut_ok and map.lots.any(func(l): return l.cut and l.kind == "shop"), "camera-side lots are cut down to their frontage")
	# The 1.5m witch: garden walls reach past her head, doors and storeys are full height.
	check(map.FENCE_H > 1.7 and map.STOREY >= 3.0 and map.CUT_H > map.FENCE_H, "walls, doors and storeys are sized against the witch")
	var floor_material: StandardMaterial3D = map.region.get_child(0).get_child(0).material_override
	var floor_color = Color(map.data.floors[0].color if map.data.floors[0] is Dictionary else map.data.floors[0][4])
	check(floor_material.albedo_texture != null and floor_material.uv1_world_triplanar and (floor_material.albedo_color * Color(map.SURFACES.asphalt.reference)).is_equal_approx(floor_color), "floors are textured asphalt that keeps its palette colour on average")
	var used: Dictionary = {}
	for mesh in map.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override is StandardMaterial3D and mesh.material_override.albedo_texture != null:
			used[mesh.material_override.albedo_texture.resource_path.get_file().get_basename()] = true
	check(map.SURFACES.keys().all(func(s): return used.has(s + "_color")), "brick, block, plaster, concrete, asphalt and steel surfaces all appear")

	await fresh(Vector3(15, 0, 0))
	arena.set_destination(Vector3(33, 0, 0))
	var highest_mid = 0.0
	for i in 600:
		if arena.player.position.distance_to(map.grounded(Vector3(33, 0, 0))) < 0.4:
			break
		await step()
		if arena.player.position.x > 22 and arena.player.position.x < 28:
			highest_mid = maxf(highest_mid, arena.player.position.y)
	check(is_equal_approx(arena.player.position.y, 1.2) and highest_mid > 0.1 and highest_mid < 1.21, "the witch climbs the stairs step by step onto the raised alley")

	await fresh(Vector3(33.6, 0, 0))
	arena.set_destination(Vector3(41.4, 0, -13.2))
	var stuck = false
	var last: Vector3 = arena.player.position
	var still = 0
	for i in 600:
		if Vector2(arena.player.position.x - 41.4, arena.player.position.z + 13.2).length() < 0.4:
			break
		await step()
		still = still + 1 if arena.player.position.distance_to(last) < 0.001 else 0
		stuck = stuck or still > 30
		last = arena.player.position
	check(Vector2(arena.player.position.x - 41.4, arena.player.position.z + 13.2).length() < 0.4 and not stuck, "the witch walks around fences into the dead-end alcove")

	await fresh(Vector3(36.36, 0, 3.0))
	var rag: Dictionary = enemy("rag", Vector3(36.36, 0, 8.16))
	rag.cooldown = 999
	arena.config.enemy_speed = 0
	arena.request_slot("lmb", {"enemy_id": "e"})
	check(not arena.pending_cast.is_empty(), "attacking an enemy behind the booth starts an approach instead of hitting through it")
	await walk_until(func(): return rag.hp < rag.max_hp, 600)
	check(rag.hp < rag.max_hp and map.sees(arena.player.position, rag.body.position), "the witch walks to a clear line and then hits")
	arena.config.enemy_speed = 2.1

	await fresh(Vector3(36.36, 0, 3.0))
	arena.fire_bolt_from(map.grounded(Vector3(36.36, 0, 9.0)), arena.player.position, arena.config.enemy_types.crow.ranged, 8.0, "normal")
	await walk_until(func(): return arena.bolts.is_empty(), 120)
	check(arena.hp == arena.config.max_hp, "an orb stops at the booth instead of passing through")

	await fresh(Vector3(33.6, 0, -7.2))
	rag = enemy("rag", Vector3(41.4, 0, -13.44))
	rag.cooldown = 0
	check(not map.sees(rag.body.position, arena.player.position), "the alcove fence stands between the rag-ghoul and the witch")
	await walk_until(func(): return arena.hp < arena.config.max_hp, 900)
	check(arena.hp < arena.config.max_hp, "a rag-ghoul routes out of the alcove to reach the witch")

	await fresh(Vector3(19, 0, 0))
	rag = enemy("rag", Vector3(29.5, 0, 0))
	rag.cooldown = 0
	await walk_until(func(): return arena.hp < arena.config.max_hp, 900)
	check(arena.hp < arena.config.max_hp and rag.body.position.y < 1.2, "an enemy comes down the stairs to the witch")

	await fresh(Vector3(36.36, 0, 2.64))
	var hidden: Dictionary = enemy("rag", Vector3(36.36, 0, 8.4))
	hidden.cooldown = 999
	arena.config.enemy_speed = 0
	arena.spawn_ally(Vector3(36.36, 0, 3.48), false, "")
	await step(120)
	check(hidden.hp == hidden.max_hp, "a turret does not shoot through the booth")
	arena.config.enemy_speed = 2.1

	await fresh(Vector3(26, 0, 2.2))
	await step(2)
	check(not map.faded.is_empty(), "the tall stair-side fence between camera and witch fades further")
	arena.player.position = map.grounded(Vector3(43.2, 0, 0))
	await step(2)
	check(map.faded.is_empty(), "fences return to their resting look once nothing is in the way")

	arena.load_map(MAP)
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	await settle()
	arena.player.position = map.grounded(Vector3(58.8, 0, 0))
	await step(2)
	check(not arena.boss_spawned and not arena.field_cleared(), "the boss waits outside the arena")
	arena.player.position = map.grounded(Vector3(64.8, 0, 0))
	await step(2)
	check(arena.boss_spawned and arena.enemies.has("boss_field") and is_equal_approx(arena.enemies.boss_field.body.position.y, 1.2), "entering zone C calls the boss on the raised arena once")
	await step(2)
	check(arena.enemies.size() == 1, "the boss is not called twice")

	check(arena.spatial_check(arena.rules.skills.turret, {"ground": [36.36, 1.2, 5.4]}) == "invalid_ground", "a turret cannot be placed on a prop")
	var spot: Vector3 = arena.edge_point()
	var listed = false
	for s in map.data.respawns:
		listed = listed or Vector2(s[0] - spot.x, s[1] - spot.z).length() < 0.01
	check(listed and Vector2(spot.x - arena.player.position.x, spot.z - arena.player.position.z).length() >= 10, "A5 respawns use the map's spots away from the witch")

	var key = InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = true
	key.shift_pressed = true
	root.push_input(key, true)
	check(arena.map.id == "flat" and arena.enemies.size() == arena.config.field.size(), "Shift+F5 switches to the flat arena")
	check(not arena.env.glow_enabled and not arena.env.fog_enabled and is_equal_approx(arena.sun.light_energy, 0.85), "the flat arena keeps its own light")
	check(arena.map.find_children("*", "MeshInstance3D", true, false).all(func(m): return m.material_override.albedo_texture == null), "and its untextured look")
	root.push_input(key, true)
	check(arena.map.id == MAP, "and back to the trial map")
	var dusk: Dictionary = arena.map.data.lighting
	check(arena.env.glow_enabled and is_equal_approx(arena.sun.light_energy, dusk.sun_energy) and arena.sun.light_color.is_equal_approx(Color(dusk.sun_color)), "the trial map is lit at dusk from its lighting block")
	var lamps: Array = arena.map.find_children("*", "OmniLight3D", true, false)
	check(lamps.size() >= 4, "street lamps and shop tubes light the alley")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_map_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
