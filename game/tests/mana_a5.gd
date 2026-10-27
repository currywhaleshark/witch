extends SceneTree
## A5 tooling: skill-gap measurement, endless engagement and session logs.
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

func calm() -> void:
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies:
		arena.enemies[id].cooldown = 999

func logs() -> PackedStringArray:
	return DirAccess.get_files_at(arena.log_dir)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	# Pin hit and crit rolls; stage B rolls have their own suite.
	arena.force_rolls = {"hit": true, "crit": false}
	arena.set_physics_process(false)
	arena.log_dir = OS.get_user_data_dir().path_join("a5_test_logs")
	DirAccess.make_dir_recursive_absolute(arena.log_dir)
	for file in logs():
		DirAccess.remove_absolute(arena.log_dir.path_join(file))
	arena.set_a5_mode(true)
	calm()
	await step(2)
	check(arena.a5_mode and arena.probe.combat_seconds > 0 and not arena.skill_gap(), "A5 mode measures combat time with skills available")

	arena.request_slot("q", {})
	arena.state.mana = 1.0
	await step(20)
	check(arena.state.active_tool == null and arena.probe.counts.tool_auto_releases == 1, "tool auto release at zero mana is counted")
	check(arena.skill_gap() and arena.probe.gap_count == 1, "zero mana without a tool starts a skill gap")
	arena.request_slot("rmb", {"ground": [3, 0, 3]})
	check(arena.probe.counts.mana_failures == 1, "mana failure presses are counted")
	var before: float = arena.probe.gap_seconds
	await step(60)
	check(absf(arena.probe.gap_seconds - before - 1.0) < 0.05, "skill gap time accumulates per second of combat")
	arena.state = arena.rules.restore_mana(arena.state, 12).state
	await step()
	check(not arena.skill_gap() and arena.probe.current_gap == 0 and "automaton" in arena.unaffordable_skills(), "affordable shotgun ends the gap while dearer skills stay unaffordable")
	arena.state.mana = 0.0
	await step(30)
	check(arena.probe.gap_count == 2 and arena.probe.longest_gap > 1.0 and arena.probe.longest_gap < 1.4, "separate gaps are counted with the longest kept")

	var first: String = arena.enemies.keys()[0]
	arena.damage_enemy(first, 1000)
	check(arena.enemies.size() == arena.config.field.size() - 1 and arena.respawns.size() == 1, "kill schedules a respawn")
	await step(int(arena.config.a5_respawn_seconds * 60) + 5)
	calm()
	var fresh_id = "enemy_6"
	check(arena.enemies.size() == arena.config.field.size() and arena.enemies.has(fresh_id) and arena.enemies[fresh_id].body.position.distance_to(arena.player.position) >= 8, "respawn returns from a field edge away from the witch")
	for id in arena.enemies.keys():
		arena.damage_enemy(id, 1000)
	check(not arena.field_cleared(), "endless field never counts as cleared")
	arena.state = arena.rules.restore_mana(arena.state, 60).state
	arena.request_slot("rmb", {"ground": [3, 0, 3]})
	release()
	check(arena.last_events[-1].type == "cast", "casting still works while the field refills")

	var path: String = arena.save_mana_log("manual")
	var report = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	check(report != null and report.test == "A5" and report.metrics.skill_gap.count == 2 and report.settings.mana_regen == 0 and report.metrics.counts.tool_auto_releases == 1, "manual save writes the session log with settings")
	var head = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../.git/HEAD").simplify_path())
	check(report != null and report.build.trial_md5.length() == 32 and report.build.scripts_md5.length() == 32 and (head.is_empty() or report.build.git_commit.length() == 7), "the log carries a build stamp: commit and content hashes")
	check(arena.save_mana_log("manual") == "", "unchanged session is not saved twice")
	var key = InputEventKey.new()
	key.physical_keycode = KEY_F7
	key.pressed = true
	root.push_input(key, true)
	check(arena.config.mana_regen == arena.config.mana_regen_steps[0] and arena.probe.combat_seconds == 0, "regen change starts a fresh measurement")
	calm()
	arena.config.mana_regen = arena.config.mana_regen_steps[0]
	await step(90)
	var measured = arena.config.mana_regen
	root.push_input(key, true)
	var changed = JSON.parse_string(FileAccess.get_file_as_string(arena.last_log_path))
	check(arena.last_log_path.ends_with("_settings_changed.json") and changed.settings.mana_regen == measured and arena.config.mana_regen != measured, "a settings change saves the log under the setting it measured")
	calm()
	await step(90)
	var count = logs().size()
	arena.damage_player(1000)
	check(logs().size() == count + 1 and arena.last_log_path.ends_with("_death.json"), "death saves the session log")
	arena.set_a5_mode(false)
	check(not arena.a5_mode and arena.enemies.size() == arena.config.field.size() and arena.respawns.is_empty(), "turning A5 off restores the normal field")

	for file in logs():
		DirAccess.remove_absolute(arena.log_dir.path_join(file))
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_a5_report.json").simplify_path()
	var result = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(result, "  ") + "\n")
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
