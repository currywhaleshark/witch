extends SceneTree
## C3: cast speed from worn items versus the production efficiency passive. Both add into
## one cast speed score under the existing soft cap (04 §4.1). An item slot holding cast speed
## cannot hold life or mana instead; that is the price on the gear side.
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

func fresh() -> void:
	arena.reset_arena()
	for slot in arena.equipment:
		arena.equipment[slot] = null
	arena.bag.clear()
	arena.refresh_gear()
	arena.build.reset_stats()
	arena.build.reset_skills()
	arena.build.set_level(30)
	await step(2)

func wear(slot: String, options: Dictionary) -> void:
	arena.bag.append({"base": "copper_ring" if slot == "ring" else "brass_brooch", "slot": slot, "rarity": "magic", "level": 30, "options": options, "affixes": [], "name": "시험 " + slot})
	arena.equip(arena.bag.size() - 1)

func key(code: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var build = arena.build
	var automaton: Dictionary = arena.rules.skills.automaton
	var per_level: float = float(arena.config.passives.production_efficiency.cast_speed_per_level)

	await fresh()
	var plain: float = arena.cast_seconds(automaton)
	check(arena.config.cast_speed_score == 0 and is_equal_approx(plain, float(automaton.cast_seconds)), "no gear and no passive leave casts at their base time")
	build.change_skill("production_efficiency", 5)
	check(arena.config.cast_speed_score == 5 * per_level and arena.cast_seconds(automaton) < plain, "production efficiency levels raise the cast speed score")
	check(arena.cast_seconds(arena.rules.skills.shotgun) < float(arena.rules.skills.shotgun.cast_seconds) and arena.cast_seconds(arena.rules.skills.spring_dash) < float(arena.rules.skills.spring_dash.cast_seconds), "it speeds every cast, other trees' included")
	check(is_equal_approx(arena.attack_seconds(), float(arena.config.basic_attack_seconds)), "it leaves attack motions alone")

	await fresh()
	var spent: int = build.skill_points()
	wear("ring", {"cast_speed": 20})
	check(arena.config.cast_speed_score == 20 and build.skill_points() == spent, "a gear cast speed option needs no skill points")
	wear("brooch", {"cast_speed": 20})
	build.change_skill("production_efficiency", 10)
	check(arena.config.cast_speed_score == 40 + 10 * per_level, "gear and passive cast speed add up into one score")
	var times: Array = []
	for score in [0.0, 20.0, 40.0, 60.0, 80.0]:
		arena.config.cast_speed_score = score
		times.append(arena.cast_seconds(automaton))
	build.apply()
	var gains: Array = []
	for i in 4:
		gains.append(times[i] - times[i + 1])
	check(gains[0] > gains[1] and gains[1] > gains[2] and gains[2] > gains[3] and times[4] > automaton.cast_seconds * arena.config.min_cast_ratio, "each further 20 cast speed saves less time under the soft cap")

	await fresh()
	var stat_budget: int = build.stat_points()
	var hp_before: float = arena.config.max_hp
	wear("ring", {"life": 30})
	wear("brooch", {"mana": 20})
	check(is_equal_approx(arena.config.max_hp, hp_before + 30) and is_equal_approx(arena.state.max_mana, 80.0) and arena.config.cast_speed_score == 0, "slots spent on life or mana give that instead of cast speed")
	build.reset_stats()
	check(build.stat_points() == stat_budget and arena.equipment.ring != null, "worn items sit outside the point budget and survive a free stat reset")

	await fresh()
	key(KEY_F8)
	check(arena.config.cast_speed_score == 0, "F8 no longer steps cast speed; items and the passive do")
	wear("ring", {"cast_speed": 25})
	arena.character_window.visible = true
	arena.character_window.refresh()
	var shown: bool = arena.character_window.find_children("*", "Label", true, false).any(func(label): return label.text.begins_with("시전 속도 25 (장비 25"))
	arena.character_window.visible = false
	check(shown, "the character window shows the cast speed split into gear and passive")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_cast_speed_gear_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
