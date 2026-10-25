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


func release() -> void:
	# Fast-forward the started motion to its release point.
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)

func fresh(target: Vector3 = Vector3(2, 0, 0), heavy: bool = true) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.attack_speed_score = 0
	arena.config.cast_speed_score = 0
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

	await fresh(Vector3(8, 0, -8))
	mouse(MOUSE_BUTTON_LEFT, true, screen(Vector3(-6, 0, 0)))
	await step(10)
	var walking: Vector3 = arena.player.position
	key(KEY_Q, true)
	check(arena.state.active_tool == "bolt_cutter" and arena.action_time == 0 and arena.moving, "move-cast tool toggles without stopping a held move")
	await step(10)
	check(arena.player.position.distance_to(walking) > 0.5, "witch keeps walking while the tool turns on")
	key(KEY_Q, false)
	await step(2)
	check(not arena.move_hold.is_empty() and arena.moving, "releasing a skill key keeps the held move")
	walking = arena.player.position
	mouse(MOUSE_BUTTON_RIGHT, true, screen(arena.player.position + Vector3(-3, 0, 0)))
	check(arena.windup.get("skill") == "shotgun" and arena.action_time > 0, "stop skill starts its cast motion during a held move")
	await step(int(arena.cast_seconds(arena.rules.skills.shotgun) * 60) - 4)
	check(arena.player.position.distance_to(walking) < 0.01 and arena.state.cooldowns.has("shotgun"), "stop skill pauses the held move for its cast motion")
	mouse(MOUSE_BUTTON_RIGHT, false, screen(arena.player.position + Vector3(-3, 0, 0)))
	await step(15)
	check(arena.player.position.distance_to(walking) > 0.5 and arena.moving, "held move resumes after the cast motion without a new click")
	arena.request_slot("e", {"ground": [8, 0, 8]})
	await step(3)
	check(not arena.pending_cast.is_empty() and arena.destination.distance_to(Vector3(8, 0, 8)) < 9, "approach-cast takes over a held move")
	for i in 600:
		if arena.allies.size() == 1:
			break
		await step()
	await step(int(arena.cast_seconds(arena.rules.skills.turret) * 60) + 5)
	var placed: Vector3 = arena.player.position
	await step(10)
	check(arena.allies.size() == 1 and arena.pending_cast.is_empty() and arena.player.position.distance_to(placed) > 0.3, "held move steers again after the approach-cast")
	mouse(MOUSE_BUTTON_LEFT, false, Vector2.ZERO)

	await fresh(Vector3(8, 0, -8))
	arena.request_slot("lmb", {"ground": [-6, 0, 0]})
	await step(5)
	walking = arena.player.position
	arena.request_slot("w", {"ground": [0, 0, 3]})
	check(arena.allies.is_empty() and arena.windup.get("skill") == "automaton" and arena.action_time > 0, "summon starts its cast motion during click movement")
	await step(int(arena.cast_seconds(arena.rules.skills.automaton) * 60) - 4)
	check(arena.player.position.distance_to(walking) < 0.01 and arena.allies.size() == 1, "summon appears at its release point while click movement pauses")
	await step(30)
	check(arena.player.position.x < walking.x - 0.5 and arena.destination.distance_to(Vector3(-6, 0, 0)) < 0.01, "click movement resumes toward the same destination after a stop skill")

	await fresh(Vector3(8, 0, -8))
	var shot: Dictionary = arena.rules.skills.shotgun
	var summon: Dictionary = arena.rules.skills.automaton
	check(is_equal_approx(arena.cast_seconds(shot), shot.cast_seconds) and arena.cast_seconds(shot) < arena.cast_seconds(summon), "stop time is the base cast time and summons cast longer than shotgun")
	var slow_summon: float = arena.cast_seconds(summon)
	arena.config.attack_speed_score = 40
	check(is_equal_approx(arena.cast_seconds(summon), slow_summon), "attack speed does not shorten cast time")
	arena.config.cast_speed_score = 40
	var fast_summon: float = arena.cast_seconds(summon)
	check(fast_summon < slow_summon and fast_summon > summon.cast_seconds * arena.config.min_cast_ratio, "cast speed shortens cast time above its floor")
	arena.request_slot("lmb", {"ground": [-6, 0, 0]})
	await step(5)
	arena.request_slot("w", {"ground": [0, 0, 3]})
	check(is_equal_approx(arena.action_time, fast_summon), "summon stop time follows cast speed")
	walking = arena.player.position
	await step(int(fast_summon * 60) + 3)
	check(arena.player.position.distance_to(walking) > 0.05, "faster cast resumes walking sooner")

	await fresh()
	var full: float = arena.enemies.target.hp
	mouse(MOUSE_BUTTON_LEFT, true, screen(arena.enemies.target.body.position + Vector3.UP * 1.3))
	check(hits(full) == 0 and arena.action_time > 0, "press on enemy head starts an attack motion")
	await step(int(arena.attack_seconds(false) * arena.rules.skills.basic_attack.release_ratio * 60) + 1)
	check(hits(full) == 1, "attack hits at its release point")
	check(not arena.state.cooldowns.has("basic_attack"), "basic attack uses no cooldown")
	motion(screen(Vector3(-6, 0, 5)))
	await step(66)
	check(hits(full) == 2, "held attack repeats once per basic attack motion")
	check(arena.player.position.is_equal_approx(Vector3.ZERO) and not arena.moving, "held target stays locked when cursor leaves it")
	mouse(MOUSE_BUTTON_LEFT, false, screen(Vector3(-6, 0, 5)))
	# A swing already in motion still lands; only new repeats stop.
	var swinging = not arena.windup.is_empty()
	await step(int(arena.attack_seconds(false) * 60) + 2)
	check(not swinging or hits(full) == 3, "release lets the started swing land")
	var released: float = arena.enemies.target.hp
	await step(80)
	check(arena.enemies.target.hp == released, "release stops repeated attacks")

	await fresh(Vector3(2, 0, 0), false)
	arena.request_slot("lmb", {"enemy_id": "target"})
	arena.enemies.target.body.position = Vector3(6, 0, 0)
	await step(int(arena.attack_seconds(false) * arena.rules.skills.basic_attack.release_ratio * 60) + 2)
	check(arena.enemies.target.hp == arena.enemies.target.max_hp and arena.message_time == 0 and arena.state.mana == arena.state.max_mana, "target leaving range during the windup is a silent whiff")

	await fresh(Vector3(4, 0, 0), false)
	arena.spawn_enemy("other", Vector3(-8, 0, 8))
	arena.enemies.other.cooldown = 999
	var shot_mp: float = arena.state.mana
	arena.request_slot("rmb", {"enemy_id": "target"})
	check(arena.state.mana == shot_mp, "shotgun spends nothing during its windup")
	arena.damage_enemy("target", 1000)
	await step(int(arena.cast_seconds(arena.rules.skills.shotgun) * 60) + 2)
	check(arena.state.mana == shot_mp - 10 and arena.state.cooldowns.has("shotgun"), "shotgun still fires toward a target that died during its windup")

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
	await step(100)
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
