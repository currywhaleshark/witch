extends SceneTree
## After the C1/C2 play: a free slot loadout (chainsaw and shield together) and the drive tree's
## spring dash for getting in and out.
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

func fresh(at: Vector3 = Vector3.ZERO, enemy: Vector3 = Vector3(0, 0, 9)) -> void:
	arena.reset_arena()
	arena.player.position = at
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	# An enemy keeps the field from counting as cleared.
	arena.spawn_enemy("t0", enemy, false)
	arena.enemies.t0.cooldown = 999
	arena.bind_slot("q", "spring_dash")
	await step(2)

func dash(cursor: Dictionary) -> Vector3:
	var start: Vector3 = arena.player.position
	arena.request_slot("q", cursor)
	await step(30)
	return arena.player.position - start

func flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var skill: Dictionary = arena.rules.skills.spring_dash

	await fresh()
	var mana: float = arena.state.mana
	var moved: Vector3 = await dash({"ground": [3, 0, 0]})
	check(absf(flat(moved) - 3.0) < 0.25 and moved.x > 2.7, "the spring dash carries the witch to a nearby cursor")
	check(is_equal_approx(mana - arena.state.mana, skill.mana_cost) and arena.state.cooldowns.get("spring_dash", 0.0) > 0.0, "it costs its mana and starts its cooldown")
	await fresh()
	arena.request_slot("q", {"ground": [3, 0, 0]})
	await step(int(60 * (skill.cast_seconds * skill.release_ratio)) + 2)
	await step(int(60 * skill.dash_seconds * 0.5))
	var midway: float = arena.player.position.x
	await step(30)
	check(midway > 0.4 and midway < arena.player.position.x - 0.4, "the dash takes a moment rather than teleporting")

	await fresh()
	moved = await dash({"ground": [10, 0, 0]})
	check(absf(flat(moved) - float(skill.range)) < 0.25, "a far cursor caps the dash at its range")
	await fresh()
	moved = await dash({"ground": [0.4, 0, 0]})
	check(absf(flat(moved) - float(skill.min_distance)) < 0.25, "a cursor at her feet still springs the minimum distance")
	await fresh(Vector3.ZERO, Vector3(4, 0, 0))
	moved = await dash({"enemy_id": "t0"})
	check(absf(flat(moved) - (4.0 - float(skill.stop_short))) < 0.3, "aimed at an enemy it stops short beside it")

	var edge: float = arena.map.bounds.end.x
	await fresh(Vector3(edge - 1.5, 0, 0))
	moved = await dash({"ground": [edge - 0.2, 0, 0]})
	await step(10)
	check(arena.map.bounds.has_point(Vector2(arena.player.position.x, arena.player.position.z)) and arena.player.position.x < edge, "it never runs off the walkable field")

	await fresh()
	arena.request_slot("q", {"ground": [5, 0, 0]})
	await step(int(60 * (skill.cast_seconds * skill.release_ratio)) + 2)
	check(not arena.dash.is_empty(), "the dash is under way")
	arena.damage_player(arena.config.max_hp * 0.5, "normal")
	check(arena.stun_time <= 0.0, "a heavy hit during the dash does not stagger her")
	await step(30)
	check(arena.dash.is_empty(), "the dash ends on its own")

	await fresh()
	arena.character_window.visible = false
	arena.skill_window.toggle()
	var window = arena.skill_window
	var slot: Control = window.find_child("Slot_r", true, false)
	var data = window.drag_data("chainsaw", "")
	check(slot != null and window.can_take(data), "a key box takes a dragged skill icon")
	window.drop_skill("r", data)
	check(arena.state.bindings.r == "chainsaw" and arena.config.bindings.r == "chainsaw", "dropping a skill icon on a key binds it")
	var q_skill: String = arena.state.bindings.q
	window.drop_skill("q", window.drag_data("chainsaw", "r"))
	check(arena.state.bindings.q == "chainsaw" and arena.state.bindings.r == q_skill, "dragging a key's icon onto another key swaps them")
	check(window.drag_data("", "") == null and window.drag_data("ballistics", "") == null, "unbuilt skills and passives cannot be dragged onto a key")
	arena.skill_window.toggle()
	arena.bind_slot("r", "shield")
	arena.bind_slot("q", "bolt_cutter")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_loadout_dash_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
