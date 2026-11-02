extends SceneTree
## Enemies entering at the same spot (A5 respawns reuse a few listed spots) step out to free
## ground instead of standing inside each other. Prints its result; writes no report.
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

func clear_field() -> void:
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.respawns.clear()
	arena.boss_spawned = false

func apart() -> bool:
	# Every pair keeps at least the gap its two model sizes ask for.
	var list: Array = arena.enemies.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			var gap := Vector2(a.body.position.x - b.body.position.x, a.body.position.z - b.body.position.z).length()
			if gap < maxf(0.8, arena.ENEMY_SPACING * (a.size + b.size)) - 0.001:
				return false
	return true

func pile(at: Vector3, kinds: Array) -> void:
	for i in kinds.size():
		arena.spawn_enemy("pile_" + str(i), at, false, "elite" if i % 3 == 2 else "normal", kinds[i])

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.config.mana_regen = 0
	await step(2)

	for map_id in ["alley_v2", "flat"]:
		if arena.map.id != map_id:
			arena.load_map(map_id)
		for i in 20:
			if arena.map.nav_ready():
				break
			await step()
		clear_field()
		arena.player.position = arena.map.start_point()
		var spot: Vector3 = arena.edge_point()
		pile(spot, ["rag", "rag", "brute", "crow", "rag", "heavy", "light", "rag"])
		check(arena.enemies.size() == 8 and apart(), "%s: eight enemies spawned on one spot stand apart" % map_id)
		check(arena.enemies.values().all(func(e): return arena.map.walkable(e.body.position)), "%s: every moved enemy stands on walkable ground" % map_id)
		var first: Dictionary = arena.enemies.pile_0
		check(Vector2(first.body.position.x - spot.x, first.body.position.z - spot.z).length() < 0.01, "%s: the first one keeps the listed spot" % map_id)
		arena.spawn_enemy("boss_t", spot, true, "boss", "latch")
		check(apart(), "%s: a boss entering there clears the crowd too" % map_id)

	# A5 respawns: every queued kill comes back at once, still apart.
	clear_field()
	arena.load_map("alley_v2")
	await step(20)
	clear_field()
	arena.a5_mode = true
	for i in 10:
		arena.respawns.append({"time": 0.0, "grade": "normal", "kind": "rag" if i % 2 == 0 else "light"})
	await step()
	check(arena.enemies.size() == 10 and apart(), "ten A5 respawns arriving together stand apart")
	arena.a5_mode = false

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
