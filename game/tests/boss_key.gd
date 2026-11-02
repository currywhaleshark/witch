extends SceneTree
## The B test key calls the trial boss into the map's boss arena, only while no boss is on the
## field, and in place of the arena's own entry boss. Writes no report.
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

func press_b() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	root.push_input(key, true)

func bosses() -> Array:
	return arena.enemies.keys().filter(func(id): return arena.config.enemy_types[arena.enemies[id].kind].has("boss"))

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	await step(2)

	press_b()
	check(bosses().size() == 1, "on the flat arena B brings in one boss at a field edge")
	press_b()
	check(bosses().size() == 1 and arena.message == "이미 보스가 있습니다", "a second B while it lives brings no other boss")

	arena.load_map("alley_v2")
	for i in 20:
		if arena.map.nav_ready():
			break
		await step()
	var room := Vector3(arena.map.data.boss.pos[0], 0, arena.map.data.boss.pos[1])
	check(bosses().is_empty() and not arena.boss_spawned, "the alley starts without its boss")
	press_b()
	var ids := bosses()
	check(ids.size() == 1 and Vector2(arena.enemies[ids[0]].body.position.x - room.x, arena.enemies[ids[0]].body.position.z - room.z).length() < 1.0, "on the alley B brings the boss into its arena")
	check(arena.boss_spawned, "it counts as the arena's boss")
	var trigger: Array = arena.map.data.boss.trigger
	arena.player.position = arena.map.grounded(Vector3((trigger[0] + trigger[2]) / 2.0, 0, (trigger[1] + trigger[3]) / 2.0))
	await step(3)
	check(bosses().size() == 1, "walking into the arena then calls no second boss")
	press_b()
	check(bosses().size() == 1, "nor does B again")
	arena.damage_enemy(ids[0], 1.0e9)
	check(bosses().is_empty(), "the boss falls")
	press_b()
	check(bosses().size() == 1, "after it falls B can call another")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
