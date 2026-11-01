extends SceneTree
## Trial enemy level: enemy HP and damage grow per level, the level follows the trial level until
## it is set apart in the C window, and living enemies keep their HP fraction when it changes.
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
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(6, 0, 0), false)
	arena.enemies.t0.cooldown = 999
	await step(2)

func base_hp(id: String) -> float:
	var enemy: Dictionary = arena.enemies[id]
	return float(arena.config.enemy_types[enemy.kind].hp) * float(arena.config.grades[enemy.grade].hp)

func stepper_button(label: String, index: int) -> Button:
	for node in arena.character_window.find_children("*", "Label", true, false):
		if node.text == label:
			return node.get_parent().get_child(index)
	return null

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var rules: Dictionary = arena.config.build
	var top: int = int(rules.max_level)
	var hp_factor: float = 1.0 + float(rules.enemy_hp_per_level) * (top - 1)
	var damage_factor: float = 1.0 + float(rules.enemy_damage_per_level) * (top - 1)

	await fresh()
	check(arena.enemy_level == 1 and is_equal_approx(arena.enemies.t0.max_hp, base_hp("t0")), "at trial level 1 enemies keep their trial values")
	check(arena.enemy_name("t0").ends_with("Lv 1"), "the hover name shows the enemy level")

	arena.enemies.t0.hp = arena.enemies.t0.max_hp * 0.5
	arena.build.set_level(top)
	check(arena.enemy_level == top and arena.enemy_level_linked, "the enemy level follows the trial level")
	check(is_equal_approx(arena.enemies.t0.max_hp, base_hp("t0") * hp_factor) and is_equal_approx(arena.enemies.t0.hp, arena.enemies.t0.max_hp * 0.5),
		"a living enemy grows with the level and keeps its HP fraction")
	arena.spawn_enemy("t1", Vector3(-6, 0, 0), false, "elite")
	arena.enemies.t1.cooldown = 999
	check(is_equal_approx(arena.enemies.t1.max_hp, base_hp("t1") * hp_factor), "new enemies spawn at the enemy level, grade multiplier included")

	# An adjacent enemy's hit lands with the level's damage factor.
	arena.enemies.t1.body.free()
	arena.enemies.erase("t1")
	arena.enemies.t0.body.position = Vector3(1.0, 0, 0)
	arena.enemies.t0.cooldown = 0.0
	var before: float = arena.hp
	var dealt := 0.0
	for i in 240:
		await step()
		if arena.hp < before:
			dealt = before - arena.hp
			break
	var expected: float = float(arena.config.enemy_types.light.damage) * damage_factor
	check(absf(dealt - expected) < 0.01, "enemy hits deal the level's damage factor (%.2f, expected %.2f)" % [dealt, expected])

	await fresh()
	check(is_equal_approx(arena.enemies.t0.max_hp, base_hp("t0") * hp_factor), "a restart respawns enemies at the enemy level")
	check(arena.step_enemy_level(-5) and arena.enemy_level == top - 5 and not arena.enemy_level_linked, "the enemy level can be set apart from the trial level")
	arena.build.set_level(10)
	check(arena.enemy_level == top - 5, "a set-apart enemy level ignores trial level changes")
	check(not arena.step_enemy_level(top), "the enemy level stays within 1 and the level cap")
	arena.link_enemy_level()
	check(arena.enemy_level == 10 and arena.enemy_level_linked, "linking puts the enemy level back on the trial level")
	check(arena.build.snapshot().enemy_level == 10, "the A5 build snapshot records the enemy level")

	# Window.
	arena.character_window.visible = true
	arena.refresh_build_windows()
	var plus: Button = stepper_button("적 레벨", 3)
	check(plus != null and not plus.disabled, "the C window has an enemy level stepper")
	plus.pressed.emit()
	check(arena.enemy_level == 11 and not arena.enemy_level_linked, "its + raises the enemy level apart from the trial level")
	var link: Array = arena.character_window.find_children("*", "Button", true, false).filter(func(b): return b.text == "적 레벨을 시험 레벨에 맞춤")
	check(link.size() == 1, "a set-apart enemy level offers relinking")
	link[0].pressed.emit()
	check(arena.enemy_level == 10 and arena.enemy_level_linked, "the relink button follows the trial level again")
	arena.character_window.visible = false

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_enemy_level_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
