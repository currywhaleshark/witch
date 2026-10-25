extends SceneTree
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
		arena._physics_process(1.0 / 60.0 * Engine.time_scale)


func release() -> void:
	# Fast-forward the started motion to its release point.
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)

func fresh(target: Vector3 = Vector3(8, 0, 0)) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("target", target)
	arena.enemies.target.cooldown = 999
	# R defaults to the grinder; approach checks need the target relay there.
	arena.state = arena.rules.bind(arena.state, "r", "relay")
	await step(2)

func finish_approach() -> void:
	for i in 240:
		if arena.pending_cast.is_empty():
			release()
			return
		await step()
	check(false, "approach completes within test limit")

func run() -> void:
	Engine.time_scale = 4
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await fresh()
	var initial_mp: float = arena.state.mana
	arena.request_slot("lmb", {"enemy_id": "target"})
	check(not arena.pending_cast.is_empty() and arena.moving, "distant enemy click begins approach")
	check(arena.enemies.target.hp == 60 and arena.state.cooldowns.is_empty() and arena.state.mana == initial_mp, "approach start has no hit, mana cost or cooldown")
	await step(5)
	arena.enemies.target.body.position = Vector3(8, 0, 4)
	await finish_approach()
	check(arena.enemies.target.hp == 42 and not arena.moving, "moving target is followed and attacked once")
	check(arena.player.position.distance_to(arena.enemies.target.body.position) <= 2.6, "attack stops inside actual basic range")
	await step(20)
	check(arena.enemies.target.hp == 42, "single click does not repeat attacks")

	await fresh(Vector3(12, 0, 0))
	arena.request_slot("rmb", {"enemy_id": "target"})
	release()
	check(arena.pending_cast.is_empty() and arena.player.position.is_equal_approx(Vector3.ZERO) and arena.state.mana == 50, "direction skill fires at a distant enemy without walking")
	check(arena.enemies.target.hp == 60, "direction skill range still limits its reach")
	arena.state.cooldowns.clear()
	arena.action_time = 0
	arena.request_slot("rmb", {"ground": [-12, 0, 0]})
	release()
	check(arena.pending_cast.is_empty() and arena.state.mana == 40 and not arena.moving, "direction skill aimed at far ground fires in place")

	await fresh(Vector3(12, 0, 0))
	arena.player.position = Vector3(-6, 0, 0)
	arena.request_slot("r", {"enemy_id": "target"})
	check(not arena.pending_cast.is_empty() and arena.state.mana == 60, "targeted ranged skill begins approach without spending mana")
	await finish_approach()
	check(arena.state.mana == 57 and arena.last_events[-1].get("skill") == "relay", "targeted ranged skill spends mana exactly once on cast")
	check(arena.player.position.x > -2.5 and arena.player.position.x < -1.5, "targeted ranged skill stops at its own range instead of melee range")

	await fresh()
	arena.request_slot("e", {"ground": [-12, 0, 0]})
	await finish_approach()
	check(arena.allies.size() == 1 and arena.allies[0].node.position.is_equal_approx(Vector3(-12, 0, 0)), "ground skill approaches and preserves picked location")
	check(arena.state.mana == 45, "placement spends mana only once")

	await fresh(Vector3(12, 0, 0))
	arena.state = arena.rules.bind(arena.state, "lmb", "turret")
	arena.request_slot("lmb", {"enemy_id": "target", "ground": [12, 0, 2]})
	await finish_approach()
	check(arena.allies.size() == 1 and arena.allies[0].node.position.is_equal_approx(Vector3(12, 0, 2)) and arena.state.mana == 45, "left-bound ground skill remains a cast after approaching")

	await fresh()
	arena.request_slot("lmb", {"ground": [4, 0, 0]})
	arena.request_slot("lmb", {"enemy_id": "target"}, true)
	await step(5)
	check(arena.pending_cast.is_empty() and not arena.moving and arena.player.position.is_equal_approx(Vector3.ZERO), "Shift distant attack cancels movement and never approaches")
	check(arena.enemies.target.hp == 60, "Shift cannot hit a distant target")

	await fresh()
	arena.request_slot("lmb", {"enemy_id": "target"})
	await step(3)
	arena.request_slot("lmb", {"ground": [-3, 0, 0]})
	check(arena.pending_cast.is_empty() and arena.destination == Vector3(-3, 0, 0), "ground move cancels queued attack")
	await step(25)
	check(arena.enemies.target.hp == 60 and arena.player.position.x < 0, "cancelled attack does not fire later")

	await fresh()
	arena.request_slot("lmb", {"enemy_id": "target"})
	arena.damage_enemy("target", 1000)
	check(arena.pending_cast.is_empty() and not arena.moving, "target death cancels approach even when it is the last enemy")

	await fresh(Vector3(12, 0, 0))
	arena.player.position = Vector3(-6, 0, 0)
	arena.state.mana = 0.0
	arena.request_slot("r", {"enemy_id": "target"})
	check(arena.pending_cast.is_empty() and arena.last_events[-1].reason == "insufficient_mana", "unusable skill does not begin walking")
	arena.state = arena.rules.bind(arena.state, "lmb", "shotgun")
	arena.request_slot("lmb", {"enemy_id": "target"})
	await finish_approach()
	check(arena.enemies.target.hp == 42 and arena.state.bindings.lmb == "shotgun" and arena.player.position.distance_to(arena.enemies.target.body.position) <= 2.6, "mana fallback approaches to basic range while preserving binding")

	await fresh(Vector3(12, 0, 0))
	arena.player.position = Vector3(-6, 0, 0)
	arena.request_slot("r", {"enemy_id": "target"})
	arena.state.mana = 0.0
	await step()
	check(arena.pending_cast.is_empty() and not arena.moving and arena.enemies.target.hp == 60, "mana loss during approach cancels without casting")

	await fresh()
	arena.request_slot("lmb", {"enemy_id": "target"})
	arena.paused = true
	await step(5)
	check(not arena.pending_cast.is_empty() and arena.player.position.is_equal_approx(Vector3.ZERO), "pause preserves queued target without moving")
	arena.paused = false
	arena.damage_player(1000)
	check(arena.pending_cast.is_empty() and not arena.moving, "player death clears queued cast")

	await fresh()
	arena.request_slot("lmb", {"enemy_id": "target"})
	arena.reset_arena()
	check(arena.pending_cast.is_empty() and not arena.moving, "restart clears queued cast")

	await fresh()
	var wall = StaticBody3D.new()
	wall.collision_layer = 1
	var shape = CollisionShape3D.new()
	var geometry = BoxShape3D.new()
	geometry.size = Vector3(0.5, 4, 20)
	shape.shape = geometry
	wall.add_child(shape)
	arena.world.add_child(wall)
	wall.position = Vector3(1.5, 1, 0)
	await step(2)
	arena.request_slot("lmb", {"enemy_id": "target"})
	await finish_approach()
	check(arena.enemies.target.hp == 60 and not arena.moving and arena.message == "접근할 수 없습니다", "blocked approach stops without damaging target")
	wall.queue_free()

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_approach_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	Engine.time_scale = 1
	quit(0 if failures.is_empty() else 1)
