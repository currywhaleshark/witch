extends SceneTree
## Held mouse/key input, enemy lock, whole-body picking and attack-speed pacing.
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

func fresh(target: Vector3 = Vector3(2, 0, 0), heavy: bool = true) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.attack_speed_score = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("target", target, heavy)
	arena.enemies.target.cooldown = 999
	await step(2)

func screen(pos: Vector3) -> Vector2:
	return arena.camera.unproject_position(pos)

func mouse(button: int, pressed: bool, at: Vector2, shift: bool = false) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.shift_pressed = shift
	root.push_input(event, true)

func motion(at: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = at
	root.push_input(event, true)

func key(code: int, pressed: bool) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event, true)

func hits(before: float) -> int:
	return roundi((before - arena.enemies.target.hp) / arena.config.basic_damage)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)

	for heavy in [false, true]:
		await fresh(Vector3(2, 0, 0), heavy)
		var body: Vector3 = arena.enemies.target.body.position
		var scale = 1.15 if heavy else 1.0
		var picked = true
		for offset in [Vector3(0, 1.35, 0), Vector3(0.6, 0.75, 0), Vector3(-0.6, 0.75, 0), Vector3(0, 0.1, 0)]:
			picked = picked and arena.pick_cursor(screen(body + offset * scale)).get("enemy_id") == "target"
		check(picked, "whole %s enemy silhouette is clickable" % ("heavy" if heavy else "normal"))

	await fresh(Vector3(4, 0, 4))
	mouse(MOUSE_BUTTON_LEFT, true, screen(Vector3(3, 0, 0)))
	await step(2)
	check(arena.moving and arena.destination.distance_to(Vector3(3, 0, 0)) < 0.3, "ground press starts movement")
	motion(screen(arena.player.position + Vector3(0, 0, -3)))
	await step(2)
	var steering: Vector3 = arena.destination
	check(arena.moving and steering.z < arena.player.position.z - 2, "held ground click follows the cursor")
	motion(screen(arena.enemies.target.body.position + Vector3.UP * 0.8))
	await step(3)
	check(arena.enemies.target.hp == arena.enemies.target.max_hp and arena.pending_cast.is_empty(), "held move sweeping over an enemy does not attack")
	mouse(MOUSE_BUTTON_LEFT, false, screen(arena.enemies.target.body.position))
	steering = arena.destination
	motion(screen(arena.player.position + Vector3(-3, 0, 3)))
	await step(2)
	check(arena.destination == steering, "release stops steering")

	await fresh()
	var full: float = arena.enemies.target.hp
	mouse(MOUSE_BUTTON_LEFT, true, screen(arena.enemies.target.body.position + Vector3.UP * 1.3))
	check(hits(full) == 1 and arena.action_time > 0, "press on enemy head attacks immediately")
	check(not arena.state.cooldowns.has("basic_attack"), "basic attack uses no cooldown")
	motion(screen(Vector3(-6, 0, 5)))
	await step(66)
	check(hits(full) == 2, "held attack repeats once per basic attack motion")
	check(arena.player.position.is_equal_approx(Vector3.ZERO) and not arena.moving, "held target stays locked when cursor leaves it")
	mouse(MOUSE_BUTTON_LEFT, false, screen(Vector3(-6, 0, 5)))
	var released: float = arena.enemies.target.hp
	await step(80)
	check(arena.enemies.target.hp == released, "release stops repeated attacks")

	await fresh()
	arena.config.attack_speed_score = 40
	check(arena.attack_seconds(false) < arena.config.basic_attack_seconds and arena.attack_seconds(false) > arena.config.min_attack_seconds, "attack speed shortens motion above its floor")
	full = arena.enemies.target.hp
	mouse(MOUSE_BUTTON_LEFT, true, screen(arena.enemies.target.body.position + Vector3.UP * 0.8))
	await step(66)
	check(hits(full) == 3, "faster attack speed fits more held attacks in the same time")
	mouse(MOUSE_BUTTON_LEFT, false, Vector2.ZERO)

	await fresh(Vector3(6, 0, 0))
	mouse(MOUSE_BUTTON_LEFT, true, screen(arena.enemies.target.body.position + Vector3.UP * 0.8))
	for i in 240:
		if arena.enemies.target.hp < arena.enemies.target.max_hp:
			break
		await step()
	full = arena.enemies.target.hp
	arena.enemies.target.body.position = Vector3(10, 0, 0)
	for i in 300:
		if arena.enemies.target.hp < full:
			break
		await step()
	check(arena.enemies.target.hp < full and arena.player.position.x > 6, "held lock follows a target that moves out of range")
	mouse(MOUSE_BUTTON_LEFT, false, Vector2.ZERO)

	await fresh()
	mouse(MOUSE_BUTTON_LEFT, true, screen(arena.enemies.target.body.position + Vector3.UP * 0.8))
	mouse(MOUSE_BUTTON_LEFT, false, screen(arena.enemies.target.body.position + Vector3.UP * 0.8))
	arena.request_slot("lmb", {"ground": [-4, 0, 0]})
	await step(5)
	check(not arena.queued_input.is_empty() and arena.player.position.is_equal_approx(Vector3.ZERO), "input during attack motion waits")
	await step(int(arena.config.basic_attack_seconds * 60) + 20)
	check(arena.player.position.x < -0.5, "queued move runs after the attack motion")

	await fresh(Vector3(4, 0, 0), false)
	mouse(MOUSE_BUTTON_LEFT, true, screen(arena.enemies.target.body.position + Vector3.UP * 0.8))
	arena.damage_enemy("target", 1000)
	await step(5)
	check(arena.hold.is_empty() and not arena.moving, "target death ends the held lock")
	mouse(MOUSE_BUTTON_LEFT, false, Vector2.ZERO)

	await fresh(Vector3(4, 0, 0))
	var mp: float = arena.state.mana
	motion(screen(Vector3(4, 0, 2)))
	mouse(MOUSE_BUTTON_RIGHT, true, screen(Vector3(4, 0, 2)))
	await step(80)
	check(arena.state.mana == mp - 20, "held right click repeats an attack skill at its cooldown")
	mouse(MOUSE_BUTTON_RIGHT, false, screen(Vector3(4, 0, 2)))

	await fresh()
	key(KEY_Q, true)
	await step(30)
	check(arena.state.active_tool == "bolt_cutter", "held tool key toggles only once")
	key(KEY_Q, false)
	motion(screen(Vector3(-2, 0, 2)))
	key(KEY_W, true)
	await step(300)
	check(arena.allies.size() == 1, "held summon key spawns only once")
	key(KEY_W, false)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_hold_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
