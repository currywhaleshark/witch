extends SceneTree
## Execution devices cast with the cursor on an enemy are set under that enemy, not on the floor
## point the cursor ray reaches behind a tall model (the boss misses from play, 2026-11-05).
## Walking into range, the spot follows the enemy. A bare floor click still places on the floor.
## Writes no report.
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

func fresh(skill: String) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.bind_slot("q", skill)
	await step(2)

func foe(id: String, at: Vector3, grade: String, kind: String) -> Dictionary:
	arena.spawn_enemy(id, at, grade == "boss", grade, kind)
	var enemy: Dictionary = arena.enemies[id]
	enemy.cooldown = 999
	enemy.max_hp = 999999.0
	enemy.hp = 999999.0
	return enemy

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func cursor_on(enemy: Dictionary, height: float) -> Dictionary:
	# A real pick: the pointer over the enemy's body at this height above its feet.
	arena.pointer = arena.camera.unproject_position(enemy.body.position + Vector3(0, height, 0))
	return arena.pick_cursor(arena.pointer)

func cast_and_place(cursor: Dictionary, skill: String, frames: int = 0) -> void:
	arena.request_slot("q", cursor)
	var data: Dictionary = arena.rules.skills[skill]
	await step(frames + int(60 * float(data.cast_seconds) * float(data.release_ratio)) + 3)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)

	for skill in ["guillotine", "hydraulic_press", "compound_executor"]:
		# The boss: the pointer on its upper body reaches the floor well behind it.
		await fresh(skill)
		var boss: Dictionary = foe("boss", Vector3(0, 0, 4.5), "boss", "latch")
		foe("anchor", Vector3(-11, 0, -9), "normal", "light")
		await step(2)
		var cursor := cursor_on(boss, 2.2)
		check(cursor.get("enemy_id") == "boss", "%s: the pointer picks the boss" % skill)
		var miss: float = flat(arena.point(cursor.ground), boss.body.position)
		await cast_and_place(cursor, skill)
		check(arena.devices.size() == 1 and flat(arena.devices[0].center, boss.body.position) < 0.05,
			"%s: set under the boss, not on the floor %.2fm behind it" % [skill, miss])

	# A brute (tall, heavy) gets the same.
	await fresh("guillotine")
	var brute: Dictionary = foe("brute", Vector3(2, 0, 3.5), "normal", "brute")
	foe("anchor", Vector3(-11, 0, -9), "normal", "light")
	await step(2)
	var on_brute := cursor_on(brute, 1.6)
	var miss_brute: float = flat(arena.point(on_brute.ground), brute.body.position)
	await cast_and_place(on_brute, "guillotine")
	check(on_brute.get("enemy_id") == "brute" and flat(arena.devices[0].center, brute.body.position) < 0.05, "a brute is hit at its feet (the floor pick was %.2fm off)" % miss_brute)
	var before: float = float(brute.hp)
	await step(90)
	check(float(brute.hp) < before, "and the blade lands on it")

	# Out of range: she walks in and the spot follows the enemy as it moves.
	await fresh("guillotine")
	var runner: Dictionary = foe("runner", Vector3(0, 0, 12), "normal", "light")
	foe("anchor", Vector3(-11, 0, -9), "normal", "light")
	await step(2)
	var far := cursor_on(runner, 0.8)
	arena.request_slot("q", far)
	await step(5)
	check(not arena.pending_cast.is_empty(), "a far enemy makes her walk in first")
	runner.body.position = Vector3(2.5, 0, 9.5)
	for i in 240:
		await step()
		if not arena.devices.is_empty():
			break
	check(arena.devices.size() == 1 and flat(arena.devices[0].center, runner.body.position) < 0.05, "the device goes where the enemy has moved to")

	# A floor click with no enemy under the pointer still places on that floor point.
	await fresh("guillotine")
	foe("anchor", Vector3(-11, 0, -9), "normal", "light")
	await step(2)
	await cast_and_place({"ground": [1.5, 0, 3.0]}, "guillotine")
	check(arena.devices.size() == 1 and flat(arena.devices[0].center, Vector3(1.5, 0, 3.0)) < 0.05, "a floor click places on the floor")

	# Other ground skills (the turret) keep their own floor-spot rule.
	await fresh("turret")
	var near: Dictionary = foe("near", Vector3(0, 0, 3.5), "normal", "light")
	foe("anchor", Vector3(-11, 0, -9), "normal", "light")
	await step(2)
	var aimed: Dictionary = arena.device_cursor("turret", cursor_on(near, 0.8))
	check(not aimed.has("follow"), "a turret is not moved onto an enemy")

	print("DEVICE_AIM ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
