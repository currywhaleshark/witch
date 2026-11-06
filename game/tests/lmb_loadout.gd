extends SceneTree
## The left button as a skill key: a skill dropped on the LMB box is cast by clicking an enemy
## (or Shift+click) while plain ground clicks still move; clearing it gives back the basic attack.
## A key's icon dragged off and let go anywhere but on a key leaves that key. Writes no report.
var arena: Node3D
var failures: Array = []
var checks: Array = []
var pointer := Vector2.ZERO

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

func fresh() -> void:
	arena.reset_arena()
	# Pin the hit roll: an unpinned basic attack can miss and leave the enemy's HP unchanged.
	arena.force_rolls = {"hit": true, "crit": false}
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(0, 0, 1.2), false)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.max_hp = 99999.0
	arena.enemies.t0.hp = 99999.0
	await step(2)

func mouse(at: Vector2, pressed = null) -> void:
	# A real pointer: a press, a motion or a release at a screen point.
	var event: InputEvent
	if pressed == null:
		event = InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		# The viewport starts a drag from the summed relative motion.
		event.relative = at - pointer
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	pointer = at
	root.push_input(event, true)
	await process_frame

func drag(from: Vector2, to: Vector2) -> void:
	await mouse(from, true)
	for i in 8:
		await mouse(from.lerp(to, (i + 1) / 8.0))
	await mouse(to, false)
	await process_frame

func centre(window, slot: String) -> Vector2:
	return window.find_child("Slot_" + slot, true, false).get_global_rect().get_center()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	await fresh()
	var basic: String = arena.rules.basic_id
	var window = arena.skill_window

	# The skill window has a left-button box that starts with the basic attack.
	arena.character_window.visible = false
	window.toggle()
	await process_frame
	check(window.find_child("Slot_lmb", true, false) != null, "the skill window has a left-button key box")
	check(window.slot_skill("lmb") == "" and window.drag_data(basic, "lmb") == null, "the basic attack on it cannot be dragged away")
	window.drop_skill("lmb", window.drag_data("shotgun", ""))
	check(arena.state.bindings.lmb == "shotgun" and arena.config.bindings.lmb == "shotgun", "a skill icon dropped on LMB binds it")
	window.toggle()

	# Clicking an enemy casts it; a plain ground click still walks; Shift+click casts in place.
	await fresh()
	arena.bind_slot("lmb", "shotgun")
	var mana: float = arena.state.mana
	arena.request_slot("lmb", {"enemy_id": "t0", "ground": [0, 0, 1.2]})
	check(arena.windup.get("skill") == "shotgun", "clicking an enemy with LMB casts the bound skill")
	await step(60)
	check(arena.state.mana < mana - 0.5, "and pays for it")
	await fresh()
	arena.request_slot("lmb", {"ground": [3, 0, 0]})
	check(arena.windup.is_empty() and arena.moving, "a plain ground click still moves her")
	await fresh()
	arena.request_slot("lmb", {"ground": [0, 0, 1.2]}, true)
	check(arena.windup.get("skill") == "shotgun", "Shift+click casts it toward the ground")
	await fresh()
	arena.state.mana = 0.0
	arena.request_slot("lmb", {"enemy_id": "t0", "ground": [0, 0, 1.2]})
	check(arena.windup.get("skill") == basic, "without the mana LMB falls back to the basic attack")

	# A tool attack on LMB with no tool out: floor clicks just walk, with no tool warning; clicking
	# an enemy warns and swings the staff's basic attack instead.
	await fresh()
	arena.bind_slot("lmb", "focus_attack")
	arena.message = ""
	arena.request_slot("lmb", {"ground": [3, 0, 0]})
	check(arena.windup.is_empty() and arena.moving and arena.message == "", "a floor click with a tool attack on LMB walks without the tool warning")
	arena.request_slot("lmb", {"enemy_id": "t0", "ground": [0, 0, 1.2]})
	check(arena.windup.get("skill") == basic and arena.message.contains("공구"), "an enemy click without a tool warns and swings the basic attack")
	var before: float = arena.enemies.t0.hp
	await step(60)
	check(arena.enemies.t0.hp < before and arena.state.bindings.lmb == "focus_attack", "the basic attack lands and LMB keeps its tool attack")
	await fresh()
	arena.bind_slot("lmb", "focus_attack")
	arena.request_slot("lmb", {"ground": [0, 0, 1.2]}, true)
	check(arena.windup.get("skill") == basic, "Shift+click without a tool also swings the basic attack")
	await fresh()
	arena.bind_slot("q", "focus_attack")
	arena.request_slot("q", {"enemy_id": "t0", "ground": [0, 0, 1.2]})
	check(arena.windup.is_empty(), "on other keys a tool attack without a tool still does nothing")
	arena.bind_slot("q", null)

	# Clearing the left button gives back the basic attack; it never moves to another key.
	await fresh()
	arena.bind_slot("lmb", null)
	check(arena.state.bindings.lmb == basic and arena.config.bindings.lmb == basic, "clearing LMB returns it to the basic attack")
	arena.bind_slot("q", "bolt_cutter")
	window.toggle()
	window.drop_skill("lmb", window.drag_data("bolt_cutter", "q"))
	check(arena.state.bindings.lmb == "bolt_cutter" and arena.state.bindings.q == null, "moving a key's skill onto a bare LMB leaves that key empty, not holding the basic attack")
	arena.bind_slot("q", "shield")
	window.drop_skill("q", window.drag_data("bolt_cutter", "lmb"))
	check(arena.state.bindings.q == "bolt_cutter" and arena.state.bindings.lmb == "shield", "dragging LMB's skill onto another key swaps them")
	window.toggle()

	# A real drag: let go off every key and the key empties; LMB goes back to the basic attack.
	window.toggle()
	await process_frame
	await process_frame
	var outside: Vector2 = window.get_global_rect().position + Vector2(window.size.x * 0.5, 40)
	await drag(centre(window, "q"), centre(window, "q") + Vector2(0, -6) + Vector2(14, -14))
	check(arena.state.bindings.q == "bolt_cutter", "a short drag let go on the key itself keeps it")
	await drag(centre(window, "q"), outside)
	check(arena.state.bindings.q == null and arena.config.bindings.q == null, "a key's icon let go off the keys leaves it")
	await drag(centre(window, "lmb"), Vector2(30, 30))
	check(arena.state.bindings.lmb == basic, "dragging LMB's skill out gives back the basic attack")
	arena.bind_slot("w", "automaton")
	await drag(centre(window, "w"), centre(window, "e"))
	check(arena.state.bindings.e == "automaton" and arena.state.bindings.w != "automaton", "let go on another key it moves there instead")
	await drag(centre(window, "lmb"), outside)
	check(arena.state.bindings.lmb == basic, "the bare basic attack cannot be dragged off")
	window.toggle()

	# A reset that unlearns LMB's skill leaves the basic attack, not an empty button.
	await fresh()
	arena.build.skills["chainsaw"] = 1
	arena.bind_slot("lmb", "chainsaw")
	arena.build.reset_skills()
	check(arena.state.bindings.lmb == basic or arena.build.learned("chainsaw"), "a skill reset that unlearns LMB's skill leaves the basic attack")

	print("LMB_LOADOUT ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
