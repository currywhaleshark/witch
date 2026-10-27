extends SceneTree
## Fixed trial map (08 §6.1): runtime navmesh, routed movement, sight lines, orbs vs walls,
## wall fading, the boss arena trigger and map respawn spots.
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

func fresh(witch: Vector3) -> void:
	# The alley map with no enemies; the witch placed by hand.
	arena.load_map("alley_v1")
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.player.position = witch
	# The arena boss stays uncalled, so the field never counts as cleared mid-check.
	arena.boss_spawned = false
	await settle()

func settle() -> void:
	# The navigation server adopts a freshly baked map a few physics frames later.
	for i in 20:
		if arena.map.nav_ready():
			return
		await step()

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

	arena.load_map("alley_v1")
	await settle()
	var map: Node3D = arena.map
	check(map.id == "alley_v1" and map.region.navigation_mesh.get_polygon_count() > 0, "the alley map builds and bakes a navmesh")
	check(map.walkable(arena.player.position) and map.zone_at(arena.player.position).get("id") == "A", "the witch starts on walkable ground in zone A")
	check(arena.enemies.size() == map.data.spawns.size() and not arena.field_cleared(), "map spawns fill the zones and the boss keeps the field open")

	var path: PackedVector3Array = map.route(map.start_point(), Vector3(60, 0, 4))
	var walkable_path = true
	for p in path:
		walkable_path = walkable_path and map.walkable(Vector3(p.x, 0, p.z))
	check(path.size() > 2 and Vector2(path[-1].x - 60, path[-1].z - 4).length() < 0.6 and walkable_path, "a route runs from the start to the boss arena over walkable ground")
	check(not map.walkable(Vector3(30.3, 0, 4.5)) and not map.walkable(Vector3(10, 0, 5)), "walls, props and the void are not walkable")
	check(map.snap(Vector3(10, 0, 5)).z < 2.6, "a click past a wall snaps to the nearest walkable spot")

	check(not map.sees(Vector3(30.3, 0, 2.5), Vector3(30.3, 0, 7)), "the tall phone booth blocks sight")
	check(map.sees(Vector3(7, 0, -0.4), Vector3(11, 0, -0.4)), "the low cart does not block sight")

	await fresh(Vector3(28, 0, 0))
	arena.set_destination(Vector3(34.5, 0, -11))
	var stuck = false
	var last: Vector3 = arena.player.position
	var still = 0
	for i in 600:
		if arena.player.position.distance_to(Vector3(34.5, 0, -11)) < 0.4:
			break
		await step()
		still = still + 1 if arena.player.position.distance_to(last) < 0.001 else 0
		stuck = stuck or still > 30 or not map.walkable(arena.player.position)
		last = arena.player.position
	check(arena.player.position.distance_to(Vector3(34.5, 0, -11)) < 0.4 and not stuck, "the witch walks around walls into the dead-end alcove")

	await fresh(Vector3(30.3, 0, 2.5))
	var rag: Dictionary = enemy("rag", Vector3(30.3, 0, 6.8))
	rag.cooldown = 999
	arena.config.enemy_speed = 0
	arena.request_slot("lmb", {"enemy_id": "e"})
	check(not arena.pending_cast.is_empty(), "attacking an enemy behind the booth starts an approach instead of hitting through it")
	await walk_until(func(): return rag.hp < rag.max_hp, 600)
	check(rag.hp < rag.max_hp and map.sees(arena.player.position, rag.body.position), "the witch walks to a clear line and then hits")
	arena.config.enemy_speed = 2.1

	await fresh(Vector3(30.3, 0, 2.5))
	arena.fire_bolt_from(Vector3(30.3, 1.2, 7.5), arena.player.position, arena.config.enemy_types.crow.ranged, 8.0, "normal")
	await walk_until(func(): return arena.bolts.is_empty(), 120)
	check(arena.hp == arena.config.max_hp, "an orb stops at the booth instead of passing through")

	await fresh(Vector3(28, 0, -6))
	rag = enemy("rag", Vector3(34.5, 0, -11.2))
	rag.cooldown = 0
	check(not map.sees(rag.body.position, arena.player.position), "the alcove wall stands between the rag-ghoul and the witch")
	await walk_until(func(): return arena.hp < arena.config.max_hp, 900)
	check(arena.hp < arena.config.max_hp, "a rag-ghoul routes out of the alcove to reach the witch")

	await fresh(Vector3(30.3, 0, 2.2))
	var hidden: Dictionary = enemy("rag", Vector3(30.3, 0, 7))
	hidden.cooldown = 999
	arena.config.enemy_speed = 0
	arena.spawn_ally(Vector3(30.3, 0, 2.9), false, "")
	await step(120)
	check(hidden.hp == hidden.max_hp, "a turret does not shoot through the booth")
	arena.config.enemy_speed = 2.1

	await fresh(Vector3(5, 0, 1.8))
	await step(2)
	check(not map.faded.is_empty(), "the alley wall between camera and witch turns see-through")
	arena.player.position = Vector3(36, 0, 0)
	await step(2)
	check(map.faded.is_empty(), "walls go solid again once nothing is in the way")

	arena.load_map("alley_v1")
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.player.position = Vector3(49, 0, 0)
	await settle()
	check(not arena.boss_spawned and not arena.field_cleared(), "the boss waits outside the arena")
	arena.player.position = Vector3(54, 0, 0)
	await step(2)
	check(arena.boss_spawned and arena.enemies.has("boss_field") and arena.enemies.boss_field.kind == "latch", "entering zone C calls the boss once")
	await step(2)
	check(arena.enemies.size() == 1, "the boss is not called twice")

	check(arena.spatial_check(arena.rules.skills.turret, {"ground": [30.3, 0, 4.5]}) == "invalid_ground", "a turret cannot be placed on a prop")
	var spot: Vector3 = arena.edge_point()
	var listed = false
	for s in map.data.respawns:
		listed = listed or Vector2(s[0] - spot.x, s[1] - spot.z).length() < 0.01
	check(listed and spot.distance_to(arena.player.position) >= 10, "A5 respawns use the map's spots away from the witch")

	var key = InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = true
	key.shift_pressed = true
	root.push_input(key, true)
	check(arena.map.id == "flat" and arena.enemies.size() == arena.config.field.size(), "Shift+F5 switches to the flat arena")
	root.push_input(key, true)
	check(arena.map.id == "alley_v1", "and back to the alley map")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_map_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
