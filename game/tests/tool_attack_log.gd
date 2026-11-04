extends SceneTree
## The A5 log keeps the focus and area attacks apart from the tool's basic attacks, and records
## how long and how often the focus attack was held and what that cost. Writes no report.
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

func enemy(id: String, at: Vector3) -> void:
	arena.spawn_enemy(id, at, false, "normal", "light")
	arena.enemies[id].cooldown = 999
	arena.enemies[id].max_hp = 99999.0
	arena.enemies[id].hp = 99999.0

func hold_q(seconds: float) -> void:
	var at := Vector3(0, 0, 1.4)
	arena.pointer = arena.camera.unproject_position(at)
	arena.hold = {"key": KEY_Q, "slot": "q", "shift": false, "enemy_id": ""}
	arena.request_slot("q", {"ground": [at.x, 0, at.z]})
	await step(int(60 * seconds))
	arena.hold.clear()
	await step(30)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	enemy("a", Vector3(0, 0, 1.4))
	enemy("anchor", Vector3(-11, 0, -9))
	arena.bind_slot("q", "focus_attack")
	arena.bind_slot("rmb", "area_attack")
	arena.bind_slot("w", "grinder")
	await step(2)
	arena.request_slot("w", {})
	await step(20)
	var probe = arena.probe

	# One long hold and two taps.
	await hold_q(1.5)
	await hold_q(0.35)
	await hold_q(0.35)
	var row: Dictionary = probe.channels.get("focus_attack:grinder", {})
	check(row.get("count") == 3, "each press of the focus attack is one held stream (%s)" % row.get("count"))
	# The stream starts after the entry motion, so each press holds for its time less the entry.
	var entry: float = arena.tool_speed(float(arena.rules.skills.focus_attack.enter_seconds))
	check(absf(float(row.get("seconds", 0)) - (2.2 - 3.0 * entry)) < 0.1, "the streams' held time adds up, without the entry motions (%.2fs)" % float(row.get("seconds", 0)))
	check(float(row.get("longest_seconds", 0)) > 0.9 and float(row.get("longest_seconds", 0)) < 1.6, "the longest hold is kept (%.2fs)" % float(row.get("longest_seconds", 0)))
	var stream: float = float(arena.rules.skills.focus_attack.channel_mana_per_second)
	check(absf(float(row.get("mana", 0)) - stream * float(row.get("seconds", 0))) < 0.2, "the stream's own mana is kept")
	check(probe.upkeep_by.has("grinder") and absf(float(probe.upkeep_by.get("focus_attack", 0)) - float(row.mana)) < 0.01, "upkeep is split between the tool and the focus stream")
	check(absf(float(probe.upkeep_by.grinder) + float(probe.upkeep_by.focus_attack) - probe.mana_flow.upkeep) < 0.01, "and the split adds up to the total upkeep")
	var hits: Dictionary = probe.sources.get("focus_attack:grinder", {})
	check(int(hits.get("hits", 0)) > 3 and float(hits.get("damage", 0)) > 0, "focus hits are logged under their own row")
	check(not probe.sources.has("grinder"), "and not mixed into the grinder's basic attacks")

	# The area attack and a basic attack each go under their own row.
	arena.pointer = arena.camera.unproject_position(Vector3(0, 0, 1.4))
	arena.request_slot("rmb", {"ground": [0, 0, 1.4]})
	await step(120)
	check(int(probe.sources.get("area_attack:grinder", {}).get("hits", 0)) >= 1, "area hits are logged under their own row")
	arena.request_slot("lmb", {"enemy_id": "a", "ground": [0, 0, 1.4]})
	await step(90)
	check(int(probe.sources.get("grinder", {}).get("hits", 0)) >= 1, "the tool's basic attack keeps the plain tool row")
	var saved: Dictionary = probe.to_dict()
	check(saved.has("channels") and saved.channels.has("focus_attack:grinder") and saved.channels["focus_attack:grinder"].has("average_seconds"), "the saved log carries the held streams")
	check(saved.has("upkeep_by") and saved.by_source.has("focus_attack:grinder") and saved.by_source.has("area_attack:grinder"), "and the split upkeep and damage rows")

	print("TOOL_ATTACK_LOG ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
