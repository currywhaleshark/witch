extends SceneTree
## Shotgun level: +3% damage per level and, from Lv5, a knockback that keeps enemies off a
## firearm witch. Heavy enemies go half as far; bosses do not budge.
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

func fresh(level: int, kind: String = "light", grade: String = "normal") -> void:
	arena.reset_arena()
	arena.build.reset_skills()
	arena.build.set_level(30)
	arena.build.change_skill("shotgun", level - 1)
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	arena.force_rolls = {"hit": true, "crit": false}
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", Vector3(3, 0, 0), false, grade, kind)
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.hp = 10000.0
	arena.spawn_enemy("far", Vector3(-9, 0, 6), false)
	arena.enemies.far.cooldown = 999
	await step(2)

func blast() -> Dictionary:
	# One shotgun blast at t0; returns the damage dealt and how far t0 was pushed.
	var hp: float = arena.enemies.t0.hp
	var at: Vector3 = arena.enemies.t0.body.position
	arena.request_slot("rmb", {"enemy_id": "t0"})
	if not arena.windup.is_empty():
		arena.windup.release = 0.0
		arena.tick_windup(0.0)
	var damage: float = hp - arena.enemies.t0.hp
	await step(30)
	var moved: Vector3 = arena.enemies.t0.body.position - at
	moved.y = 0.0
	return {"damage": damage, "moved": moved.length(), "x": moved.x}

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var skill: Dictionary = arena.rules.skills.shotgun
	var per_level: float = float(arena.items.data.skill_level_damage.shotgun)

	await fresh(1)
	var base: Dictionary = await blast()
	await fresh(4)
	var lv4: Dictionary = await blast()
	check(is_equal_approx(lv4.damage, base.damage * (1.0 + 3 * per_level)) and is_equal_approx(per_level, 0.03), "each shotgun level adds 3% damage")
	check(lv4.moved < 0.05, "below Lv5 the shotgun does not knock back")
	await fresh(5)
	var lv5: Dictionary = await blast()
	check(absf(lv5.moved - float(skill.knockback_distance)) < 0.15 and lv5.x > 0, "from Lv5 a hit shoves the enemy straight away from her")
	await fresh(5, "heavy")
	var heavy: Dictionary = await blast()
	check(absf(heavy.moved - float(skill.knockback_distance) * 0.5) < 0.15, "heavy enemies go half as far")
	await fresh(10, "latch", "boss")
	var boss: Dictionary = await blast()
	check(boss.moved < 0.05, "bosses do not budge")

	await fresh(1)
	arena.bag.append({"base": "bp_shotgun", "slot": "medium", "rarity": "magic", "level": 30, "options": {"skill:shotgun": 4}, "affixes": [], "name": "시험 설계도"})
	arena.equip(arena.bag.size() - 1)
	var blueprint: Dictionary = await blast()
	check(blueprint.moved > 1.0, "blueprint levels count toward the Lv5 knockback")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_shotgun_knockback_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
