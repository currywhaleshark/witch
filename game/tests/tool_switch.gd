extends SceneTree
## A4 tool switching: bolt cutter and grinder toggles, their attacks and coexisting debuffs.
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

func fresh() -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("target", Vector3(2, 0, 0), true)
	arena.enemies.target.cooldown = 999
	# R defaults to the shield; these checks need the grinder there.
	arena.state = arena.rules.bind(arena.state, "r", "grinder")
	# Enough HP to survive a whole comparison sequence.
	arena.enemies.target.hp = 1000.0
	arena.enemies.target.max_hp = 1000.0
	await step(2)

func swing() -> float:
	# One whole basic attack on the target; returns the HP it lost.
	var before: float = arena.enemies.target.hp
	arena.request_slot("lmb", {"enemy_id": "target"})
	release()
	arena.action_time = 0
	return before - arena.enemies.target.hp

func key(code: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)

	await fresh()
	check(arena.state.bindings.r == "grinder" and arena.rules.skills.grinder.kind == "tool", "grinder is a tool toggle bound to R")
	arena.request_slot("r", {})
	check(arena.state.active_tool == "grinder" and arena.tool_visuals.grinder.visible == false, "R deploys the grinder at once")
	await step()
	check(arena.tool_visuals.grinder.visible and not arena.tool_visuals.bolt_cutter.visible, "only the grinder is shown")
	arena.request_slot("q", {})
	check(arena.state.active_tool == "bolt_cutter" and arena.last_events.any(func(e): return e.type == "tool_changed" and e.previous == "grinder"), "deploying the bolt cutter replaces the grinder")
	arena.request_slot("q", {})
	check(arena.state.active_tool == null, "the same key releases the active tool")
	arena.request_slot("r", {})
	arena.request_slot("r", {})
	check(arena.state.active_tool == null, "the grinder also releases on its own key")

	check(arena.attack_seconds("grinder") < arena.attack_seconds() and arena.attack_seconds() < arena.attack_seconds("bolt_cutter"), "grinder cuts faster than the staff, bolt cutter swings slower")
	var bare: float = swing()
	arena.request_slot("r", {})
	var first_cut: float = swing()
	var shred: float = arena.rules.skills.grinder.debuff_seconds
	check(is_equal_approx(arena.enemies.target.shred, shred) and arena.enemies.target.slow == 0, "a grinder cut shreds without slowing")
	check(is_equal_approx(first_cut, arena.rules.skills.grinder.attack_damage * arena.config.shred_damage_taken), "shred applies from the cut that lands it")
	check(first_cut < bare * arena.config.shred_damage_taken, "a single grinder cut is lighter than a staff hit")

	arena.state.cooldowns.clear()
	arena.action_time = 0
	var hp: float = arena.enemies.target.hp
	arena.request_slot("rmb", {"enemy_id": "target"})
	release()
	arena.action_time = 0
	check(is_equal_approx(hp - arena.enemies.target.hp, arena.config.shot_damage * arena.config.shred_damage_taken), "other skills hit harder on a shredded enemy")
	check(arena.state.active_tool == "grinder", "other skills keep the grinder deployed")

	arena.request_slot("q", {})
	var crush: float = swing()
	check(arena.enemies.target.slow > 0 and arena.enemies.target.shred > 0, "switching tools keeps the earlier shred while the bolt cutter slows")
	check(is_equal_approx(crush, arena.rules.skills.bolt_cutter.attack_damage * arena.config.shred_damage_taken), "bolt cutter hits gain from the grinder's shred")
	await step(int(arena.rules.skills.bolt_cutter.debuff_seconds * 60) + 2)
	check(arena.enemies.target.slow == 0 and arena.enemies.target.shred > 0, "debuffs expire on their own timers")
	await step(int(shred * 60))
	check(arena.enemies.target.shred == 0, "shred wears off")

	await fresh()
	arena.request_slot("r", {})
	arena.state.mana = 3.0
	await step(40)
	check(arena.state.active_tool == null and arena.state.mana == 0 and not arena.tool_visuals.grinder.visible, "grinder upkeep drains mana and auto-releases")

	await fresh()
	key(KEY_F9)
	check(arena.state.bindings.r == "relay" and arena.state.bindings.q == "bolt_cutter", "F9 cycles R from the grinder to the target relay")
	key(KEY_F9)
	check(arena.state.bindings.r == "shield", "F9 cycles R on to the shield")
	key(KEY_F9)
	check(arena.state.bindings.r == "grinder", "F9 cycles R back to the grinder")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_tool_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
