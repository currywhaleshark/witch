extends SceneTree
## Enemies flinch when struck: they stop and lose the attack they were winding up, for a time set
## by their grade and their level against the witch's, with a short guard so fast hits cannot pin
## them. Bosses never flinch; a telegraphed brute charge is not broken off. Writes no report.
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

func fresh(kind: String = "light", grade: String = "normal", at: Vector3 = Vector3(0, 0, 6)) -> Dictionary:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", at, kind == "heavy", grade, kind)
	var enemy: Dictionary = arena.enemies.t0
	enemy.max_hp = 99999.0
	enemy.hp = 99999.0
	enemy.retarget = 0.0
	await step(2)
	return enemy

func hit(enemy: Dictionary) -> void:
	arena.damage_enemy("t0", 1.0)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	var plan: Dictionary = arena.config.enemy_flinch

	var enemy: Dictionary = await fresh()
	await step(10)
	var before: Vector3 = enemy.body.position
	check(before.distance_to(Vector3(0, 0, 6)) > 0.05, "an unhit enemy walks toward her")
	hit(enemy)
	check(is_equal_approx(float(enemy.flinch), float(plan.seconds.normal)), "a normal enemy flinches for its grade's time")
	before = enemy.body.position
	await step(int(60 * float(plan.seconds.normal)) - 2)
	check(enemy.body.position.distance_to(before) < 0.01, "a flinching enemy stands still")
	await step(10)
	check(enemy.body.position.distance_to(before) > 0.02, "it walks on once it recovers")
	hit(enemy)
	check(float(enemy.flinch) == 0.0, "a hit inside the guard right after does not flinch it again")
	await step(int(60 * float(plan.guard_seconds)) + 5)
	hit(enemy)
	check(float(enemy.flinch) > 0.0, "after the guard it flinches again")

	enemy = await fresh("light", "normal", Vector3(0, 0, 1.0))
	for i in 120:
		if enemy.windup > 0:
			break
		await step()
	check(enemy.windup > 0 and enemy.attack == "melee", "a close enemy winds up its attack")
	var hp: float = arena.hp
	hit(enemy)
	check(enemy.windup == 0.0 and enemy.attack == "" and arena.probe.counts.enemy_attacks_interrupted == 1, "a flinch breaks off the attack it was winding up")
	await step(int(60 * float(plan.seconds.normal)))
	check(is_equal_approx(hp, arena.hp), "the broken-off attack never lands")

	for grade in ["champion", "elite"]:
		enemy = await fresh("light", grade)
		hit(enemy)
		check(is_equal_approx(float(enemy.flinch), float(plan.seconds[grade])), "a %s flinches for a shorter %.2fs" % [grade, float(plan.seconds[grade])])
	check(float(plan.seconds.normal) > float(plan.seconds.champion) and float(plan.seconds.champion) > float(plan.seconds.elite), "stronger grades flinch less")

	arena.build.set_level(20)
	arena.set_enemy_level(30)
	enemy = await fresh()
	hit(enemy)
	check(is_equal_approx(float(enemy.flinch), float(plan.seconds.normal) * (1.0 - 10 * float(plan.level_step))), "an enemy ten levels above her flinches half as long")
	arena.set_enemy_level(10)
	enemy = await fresh()
	hit(enemy)
	check(is_equal_approx(float(enemy.flinch), float(plan.seconds.normal) * (1.0 + 10 * float(plan.level_step))), "one ten levels below flinches half again as long")
	arena.set_enemy_level(1)
	enemy = await fresh()
	hit(enemy)
	check(is_equal_approx(float(enemy.flinch), float(plan.seconds.normal) * float(plan.max_factor)), "the level effect is capped")
	arena.link_enemy_level()
	arena.build.set_level(1)

	enemy = await fresh("latch", "boss")
	hit(enemy)
	check(float(enemy.flinch) == 0.0, "a boss never flinches")

	enemy = await fresh("brute", "normal", Vector3(0, 0, 5))
	enemy.cooldown = 0.0
	enemy.charge_cooldown = 0.0
	for i in 120:
		if enemy.windup > 0:
			break
		await step()
	check(enemy.attack == "charge" and enemy.windup > 0, "a brute at range winds up its charge")
	hit(enemy)
	check(enemy.windup > 0 and float(enemy.flinch) == 0.0, "a telegraphed charge is not broken off")

	enemy = await fresh()
	var bled: float = enemy.hp
	arena.damage_enemy("t0", 1.0, false)
	check(float(enemy.flinch) == 0.0 and enemy.hp < bled, "bleed ticks do not make it flinch")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
