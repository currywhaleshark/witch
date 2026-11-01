extends SceneTree
## C1/C2 trial build: trial level points, stat effects, skill/passive/node spending, free resets,
## and the character (C) / skill tree (S) windows that drive them.
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
	arena.build.reset_stats()
	arena.build.reset_skills()
	arena.build.set_level(1)
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(2, 0, 0), false)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.hp = 10000.0
	await step(2)

func key(code: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func hold_key(code: int, down: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(box: Control, button: int) -> void:
	# Tree points go in on release, so a click is a press and a release.
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.pressed = down
		box.gui_input.emit(click)

func buttons(window: Node, caption: String) -> Array:
	return window.find_children("*", "Button", true, false).filter(func(b): return b.text == caption)

func struck(roller: String) -> float:
	var before: float = arena.enemies.t0.hp
	arena.strike("t0", 10.0, false, roller, "staff")
	return before - arena.enemies.t0.hp

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var build = arena.build
	var per_stat: int = int(build.rules.stat_points_per_level)
	var effects: Dictionary = build.rules.stat_effects

	await fresh()
	check(build.level == 1 and build.stat_points() == per_stat and build.skill_points() == 1, "trial level 1 hands out one level of stat and skill points")
	for i in per_stat:
		build.change_stat("power", 1)
	check(build.stats.power == per_stat and not build.change_stat("vitality", 1), "stat points run out at the level's budget")
	check(build.change_skill("chainsaw", 1) and not build.change_skill("shield", 1) and arena.config.chainsaw_level == 2, "a skill point raises one skill level, then the pool is empty")

	build.set_level(30)
	check(build.skill_points() == 29 and build.stat_points() == 30 * per_stat - per_stat, "a higher trial level adds both pools")
	build.change_skill("chainsaw", 8)
	check(arena.config.chainsaw_level == 10 and not build.change_skill("chainsaw", 1), "skills stop at level 10")
	var short_shield: float = arena.shield_duration()
	build.change_skill("shield", 9)
	check(arena.shield_duration() > short_shield and arena.shield_duration() >= arena.rules.skills.shield.cooldown_seconds, "shield levels lengthen it until Lv10 outlasts its cooldown")
	build.change_skill("shield", -9)
	check(not build.change_skill("ballistics", -1) and not build.change_skill("shield", -1), "passives cannot drop below 0 nor skills below 1")
	var before_node: int = build.skill_points()
	build.set_node("A")
	var after_a: int = build.skill_points()
	build.set_node("B")
	check(before_node - after_a == int(build.rules.node_cost) and build.skill_points() == after_a and arena.config.automaton_node == "B", "a node costs one point and A/B swap without paying again")
	build.set_node("base")
	check(build.skill_points() == before_node and arena.rules.skills.automaton.mana_cost == float(arena.config.automaton_nodes.base.mana_cost), "dropping the node refunds it and restores the cheap cost")

	build.change_skill("cutting_precision", 10)
	build.set_level(5)
	check(build.skill_points() == 5 and arena.config.chainsaw_level == 1 and arena.config.passive_levels.cutting_precision == 0, "lowering the level refunds a pool that no longer fits")
	check(build.stat_points() == 5 * per_stat - per_stat and build.stats.power == per_stat, "a pool that still fits keeps its spending")

	await fresh()
	build.set_level(30)
	build.change_stat("power", 10)
	check(is_equal_approx(struck("witch"), 10.0 * (1.0 + 10 * float(effects.power))) and is_equal_approx(struck("automaton"), 10.0), "power raises the witch's own hits, not her summons'")
	var hp_before: float = arena.hp
	build.change_stat("vitality", 10)
	check(is_equal_approx(arena.config.max_hp, 100.0 + 10 * float(effects.vitality)) and is_equal_approx(arena.hp, hp_before + 10 * float(effects.vitality)), "vitality raises max HP and current HP rises with it")
	build.change_stat("will", 10)
	check(is_equal_approx(arena.state.max_mana, 60.0 + 10 * float(effects.will)) and is_equal_approx(arena.state.mana, arena.state.max_mana), "will raises max mana")
	var hit_before: float = arena.hit_chance("t0")
	build.change_stat("dexterity", 50)
	check(arena.config.dexterity == 50 and arena.hit_chance("t0") > hit_before, "dexterity feeds the existing hit formula")
	build.reset_stats()
	check(build.stat_points() == 30 * per_stat and arena.config.max_hp == 100.0 and arena.state.max_mana == 60.0 and arena.hp <= 100.0, "resetting stats is free and returns every point")
	arena.reset_arena()
	check(arena.hp == arena.config.max_hp and arena.state.max_mana == 60.0, "a restart uses the build's maximums")

	await fresh()
	key(KEY_C)
	key(KEY_S)
	check(arena.character_window.visible and arena.skill_window.visible, "C and S open the character and skill tree windows")
	var start: float = arena.elapsed
	await step(30)
	check(arena.elapsed > start + 0.4, "combat keeps running while the windows are open")
	build.set_level(3)
	# The first + is the trial level's, the second the enemy level's; the third is power's.
	var plus: Array = buttons(arena.character_window, "+")
	plus[2].pressed.emit()
	check(build.stats.power == 1, "the character window's + spends a stat point")
	# The tree shows one tab at a time; the automaton's node row sits under the automation tree.
	arena.skill_window.tree_tab = "automation"
	arena.skill_window.refresh()
	var a_button: Array = buttons(arena.skill_window, "A 자폭 특화")
	a_button[0].pressed.emit()
	check(build.node == "A" and buttons(arena.skill_window, "● A 자폭 특화").size() == 1, "the skill tree window picks a node and marks it")
	buttons(arena.skill_window, "초기화")[0].pressed.emit()
	check(build.node == "base" and build.skill_points() == 3, "the skill tree window's reset refunds everything")
	build.set_level(30)
	hold_key(KEY_SHIFT, true)
	buttons(arena.character_window, "+")[2].pressed.emit()
	hold_key(KEY_SHIFT, false)
	var shifted_power: int = build.stats.power
	arena.skill_window.tree_tab = "drive"
	arena.skill_window.refresh()
	var tree: Node = arena.skill_window.find_child("Tree", true, false)
	var chainsaw: Control = tree.find_child("Node_chainsaw", false, false)
	var states: Array = tree.get_children().map(func(box): return arena.skill_window.node_state(arena.skill_window.find_node(box.name.trim_prefix("Node_"))))
	check(states.count("levels") == 3 and states.count("fixed") == 3 and states.count("missing") == 10,
		"the drive tree lights its 3 levelled and 3 fixed implemented skills and greys the 10 unbuilt ones")
	hold_key(KEY_CTRL, true)
	tap(chainsaw, MOUSE_BUTTON_LEFT)
	var ctrl_once: int = build.skills.chainsaw
	arena.skill_window.click_node("chainsaw", 1)
	hold_key(KEY_CTRL, false)
	check(shifted_power == 11 and ctrl_once == 6, "Shift+click spends 10 points at once and Ctrl+click 5")
	check(build.skills.chainsaw == 10, "a multi-step click stops at the level cap")
	tap(arena.skill_window.find_child("Node_chainsaw", true, false), MOUSE_BUTTON_RIGHT)
	check(build.skills.chainsaw == 9, "a plain right-click lowers one step")
	var guillotine: Control = arena.skill_window.find_child("Node_낙하 단두대", true, false)
	var spent: int = build.skill_points()
	tap(guillotine, MOUSE_BUTTON_LEFT)
	check(build.skill_points() == spent, "an unbuilt skill takes no points")
	key(KEY_C)
	key(KEY_S)
	check(not arena.character_window.visible and not arena.skill_window.visible, "the same keys close them")

	await fresh()
	var levels: Array = [arena.config.shield_level, arena.config.dexterity, arena.config.automaton_level, arena.config.turret_level, arena.config.chainsaw_level, arena.config.automaton_node, arena.config.passive_levels.duplicate()]
	for code in [KEY_F10, KEY_F11, KEY_N, KEY_J, KEY_K]:
		key(code)
	var shifted = InputEventKey.new()
	shifted.physical_keycode = KEY_F9
	shifted.pressed = true
	shifted.shift_pressed = true
	root.push_input(shifted, true)
	check(levels == [arena.config.shield_level, arena.config.dexterity, arena.config.automaton_level, arena.config.turret_level, arena.config.chainsaw_level, arena.config.automaton_node, arena.config.passive_levels], "the old level keys no longer change the build")
	var score: float = arena.config.hit_recovery_score
	key(KEY_F12)
	check(arena.config.hit_recovery_score == score, "F12 no longer steps the hit recovery score; items carry it")

	arena.log_dir = OS.get_user_data_dir().path_join("build_log_test")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-log-dir="):
			arena.log_dir = arg.trim_prefix("--test-log-dir=")
	DirAccess.make_dir_recursive_absolute(arena.log_dir)
	arena.set_a5_mode(true)
	await fresh()
	build.set_level(4)
	build.change_stat("will", 3)
	for i in 72:
		await step()
	var path: String = arena.save_mana_log("manual")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	check(saved != null and saved.settings.build.level == 4 and saved.settings.build.stats.will == 3 and saved.settings.max_mana == 63, "the A5 log records the trial build")
	for i in 60 * 11:
		await step()
	var files: int = DirAccess.get_files_at(arena.log_dir).size()
	build.change_stat("will", 1)
	var names: PackedStringArray = DirAccess.get_files_at(arena.log_dir)
	var split = null
	for file in names:
		if file.ends_with("_build_changed.json"):
			split = JSON.parse_string(FileAccess.get_file_as_string(arena.log_dir.path_join(file)))
	check(names.size() == files + 1 and split != null and split.settings.build.stats.will == 3 and split.settings.max_mana == 63, "a build change first saves the segment with the build it was played with")
	for i in 180:
		await step()
	build.change_stat("will", 1)
	check(DirAccess.get_files_at(arena.log_dir).size() == files + 1, "a few seconds of clicking in the windows leaves no fragment log")
	arena.set_a5_mode(false)
	for file in DirAccess.get_files_at(arena.log_dir):
		DirAccess.remove_absolute(arena.log_dir.path_join(file))

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_build_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
