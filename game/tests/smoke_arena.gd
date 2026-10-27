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

func frame(count: int = 1) -> void:
	for i in count:
		await physics_frame

func release() -> void:
	# Fast-forward the started motion to its release point.
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	# Pin hit and crit rolls; stage B rolls have their own suite.
	arena.force_rolls = {"hit": true, "crit": false}
	await frame(3)
	arena.muted = true
	arena.config.mana_regen = 0
	check(arena.enemies.size() == arena.config.field.size() and arena.hp == 100, "scene starts with witch and the trial field")
	var enemy = arena.enemies.enemy_0.body
	var screen: Vector2 = arena.camera.unproject_position(enemy.position + Vector3.UP * 0.8)
	check(arena.pick_cursor(screen).get("enemy_id") == "enemy_0", "physics ray selects enemy collider")
	check(arena.pick_cursor(Vector2(-500, -500)).get("ground") == null, "outside floor is not valid ground")
	var move = InputEventMouseButton.new()
	move.button_index = MOUSE_BUTTON_LEFT
	move.pressed = true
	move.position = arena.camera.unproject_position(arena.player.position + Vector3(2, 0, 0))
	root.push_input(move, true)
	check(arena.moving, "viewport mouse event requests movement")
	var release = move.duplicate()
	release.pressed = false
	root.push_input(release, true)
	var start: Vector3 = arena.player.position
	var view: Basis = arena.camera.global_basis
	var offset: Vector3 = arena.camera.position - arena.player.position
	await frame(25)
	check(arena.player.position.distance_to(start) > 0.5, "physics player moves toward clicked ground")
	check(arena.camera.global_basis.is_equal_approx(view) and (arena.camera.position - arena.player.position).is_equal_approx(offset), "camera keeps a fixed angle and follows by translation")
	arena.request_slot("lmb", {"ground": [10, 0, 10]}, true)
	check(not arena.moving, "Shift force attack stops previous movement")
	check(arena.last_events[-1].type == "windup_started" and arena.state.cooldowns.is_empty(), "attack starts its motion before the hit")
	release()
	check(arena.last_events[-1].type == "cast", "Shift ground casts basic attack at the release point")
	check(arena.action_time > 0 and not arena.state.cooldowns.has("basic_attack"), "basic attack starts an attack motion instead of a cooldown")
	arena.action_time = 0.0
	arena.enemies.enemy_0.body.position = arena.player.position + Vector3(1.8, 0, 0)
	var before: float = arena.enemies.enemy_0.hp
	arena.request_slot("lmb", {"enemy_id": "enemy_0"})
	check(arena.enemies.enemy_0.hp == before, "targeted basic attack waits for its release point")
	release()
	check(arena.enemies.enemy_0.hp < before, "targeted basic attack deals real HP damage")
	arena.action_time = 0.0
	var mp: float = arena.state.mana
	arena.enemies.enemy_5.body.position = Vector3(-13, 0, -11)
	# R defaults to the grinder; these checks need the target relay there.
	arena.state = arena.rules.bind(arena.state, "r", "relay")
	arena.request_slot("r", {"enemy_id": "enemy_5"})
	check(arena.state.mana == mp and not arena.pending_cast.is_empty(), "out-of-range skill queues approach without spending mana")
	arena.state.cooldowns.clear()
	arena.request_slot("q", {})
	check(arena.state.active_tool == "bolt_cutter", "tool activates without cursor")
	mp = arena.state.mana
	arena.request_slot("w", {"enemy_id": "enemy_0"})
	check(arena.allies.is_empty() and arena.state.mana == mp, "summon spends nothing before its release point")
	release()
	check(arena.allies.size() == 1 and arena.allies[0].node.position.distance_to(arena.player.position) < 1.3, "automaton spawns beside player")
	check(arena.allies[0].target == "enemy_0", "summon stores cursor target")
	check(arena.state.active_tool == "bolt_cutter", "summon cast preserves active tool")
	# Skip the summon cast motion; inputs during it are queued.
	arena.action_time = 0
	var placement: Vector3 = arena.player.position + Vector3(0, 0, 3)
	arena.request_slot("e", {"ground": [placement.x, 0, placement.z]})
	release()
	check(arena.allies.size() == 2 and arena.allies[1].node.position.is_equal_approx(placement), "turret spawns on picked ground")
	arena.action_time = 0
	arena.state.cooldowns.clear()
	mp = arena.state.mana
	arena.request_slot("e", arena.pick_cursor(Vector2(-500, -500)))
	check(arena.message == "설치할 수 없습니다" and arena.state.mana == mp and arena.allies.size() == 2, "placement off the floor reports unplaceable ground")
	arena.state = arena.rules.advance(arena.state, 30).state
	check(arena.state.mana == 0 and arena.state.active_tool == null, "upkeep depletes MP and releases tool")
	arena.state = arena.rules.bind(arena.state, "lmb", "shotgun")
	arena.action_time = 0
	arena.request_slot("lmb", {"enemy_id": "enemy_0"})
	release()
	check(arena.last_events[0].type == "basic_attack_fallback" and arena.state.bindings.lmb == "shotgun", "left fallback preserves binding in live scene")
	arena.state.cooldowns.clear()
	arena.action_time = 0.0
	arena.request_slot("rmb", {"ground": [2, 0, 2]})
	check(arena.last_events[-1].reason == "insufficient_mana", "right click fails at zero MP")
	check(arena.message_time > 0, "failure creates overhead feedback")
	arena.reset_arena()
	arena.config.mana_regen = 0
	arena.request_slot("q", {})
	arena.paused = true
	mp = arena.state.mana
	start = arena.enemies.enemy_0.body.position
	await frame(8)
	check(arena.state.mana == mp and arena.enemies.enemy_0.body.position == start, "pause freezes AI and resource clocks")
	arena.paused = false
	arena.enemies.enemy_0.body.position = arena.player.position + Vector3(1.1, 0, 0)
	arena.enemies.enemy_0.cooldown = 0
	await frame(45)
	check(arena.hp < 100, "enemy windup resolves player damage")
	arena.damage_player(1000)
	check(arena.hp == 0 and arena.state.active_tool == null and not arena.moving, "death clamps HP and disables movement/tool")
	mp = arena.state.mana
	arena.request_slot("w", {"ground": [0, 0, 0]})
	check(arena.state.mana == mp and arena.allies.is_empty(), "dead player cannot cast")
	arena.reset_arena()
	check(arena.hp == 100 and arena.enemies.size() == arena.config.field.size() and arena.allies.is_empty(), "restart rebuilds actors and resources")
	arena.spawn_ally(Vector3(14, 0, -12), true, "enemy_0")
	start = arena.allies[0].node.position
	arena._tick_allies(0.2)
	check(arena.allies[0].node.position.distance_to(arena.player.position) < start.distance_to(arena.player.position), "offscreen automaton returns toward player")
	for id in arena.enemies.keys():
		arena.damage_enemy(id, 1000)
	check(arena.kills == arena.config.field.size() and arena.enemies.is_empty(), "kills remove targets and complete arena")
	# Render a reproducible live scene with both automation samples and tool HUD.
	arena.reset_arena()
	arena.muted = true
	arena.request_slot("q", {})
	arena.request_slot("w", {"ground": [0, 0, 0]})
	release()
	arena.action_time = 0
	arena.request_slot("e", {"ground": [-2, 0, 1]})
	release()
	await frame(15)
	arena.paused = true
	# Freeze simulation without the pause overlay for the captured play view.
	arena.set_physics_process(false)
	arena.paused = false
	arena.hud.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var path = ProjectSettings.globalize_path("res://").path_join("../reports/godot_combat_preview.png").simplify_path()
		var result = root.get_texture().get_image().save_png(path)
		check(result == OK, "rendered viewport screenshot saved")
	var report = {"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(), "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_smoke_report.json")
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
