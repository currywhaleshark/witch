extends SceneTree
## 08 §6.3 trial boss: sweep-then-slam, door-frame crossfire and HP-mark shockwaves with adds.
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

func fresh(at: Vector3) -> void:
	# The boss alone, standing still; the witch at the origin.
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("boss", at, true, "boss", "latch")
	await step(1)

func boss() -> Dictionary:
	return arena.enemies.boss

func lost() -> float:
	return arena.config.max_hp - arena.hp

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	var plan: Dictionary = arena.config.enemy_types.latch.boss
	var power: float = arena.config.grades.boss.damage

	await fresh(Vector3(0, 0, -2.5))
	check(boss().max_hp == arena.config.enemy_types.latch.hp * arena.config.grades.boss.hp and arena.enemy_name("boss").contains("빗장"), "the latch boss spawns with boss HP and its name")
	check(boss().attack == "sweep" and boss().windup > 0 and arena.effects.size() > 0, "up close the boss winds up a sweep with a fan warning")
	await step(int(plan.sweep.windup * 30))
	var fills: Array = arena.effects.filter(func(fx): return fx.has("fill"))
	check(fills.size() == 1 and fills[0].node.scale.x > 0.4 and fills[0].node.scale.x < 0.6, "the warning fill is about half way at half the windup")
	await step(int(plan.sweep.windup * 30) - 2)
	check(fills[0].node.scale.x > 0.9, "the fill nearly reaches the edge just before impact")
	await step(4)
	check(is_equal_approx(lost(), plan.sweep.damage * power) and arena.stun_time > 0, "the sweep hits and stuns the witch inside the fan")
	check(boss().attack == "slam" and boss().windup > plan.slam.windup + plan.slam.chain_extra - 0.1, "the lock slam follows the sweep with extra time to step out")

	await fresh(Vector3(0, 0, -2.5))
	arena.player.position = Vector3(0, 0, -6)
	await step(int((plan.sweep.windup + plan.slam.windup + plan.slam.chain_extra) * 60) + 4)
	check(arena.hp == arena.config.max_hp, "stepping behind the boss dodges both the sweep and the slam")

	await fresh(Vector3(0, 0, -6))
	check(boss().attack == "slam" and boss().windup > 0, "at mid range the boss winds up the lock slam with a line warning")
	await step(int(plan.slam.windup * 60) + 2)
	check(is_equal_approx(lost(), plan.slam.damage * power) and arena.stun_time > 0, "the slam hits the witch standing on the line")

	await fresh(Vector3(0, 0, -6))
	arena.player.position = Vector3(2.2, 0, 0)
	await step(int(plan.slam.windup * 60) + 2)
	check(arena.hp == arena.config.max_hp, "leaving the line dodges the slam")

	await fresh(Vector3(0, 0, -10))
	check(boss().attack == "frames" and boss().frames.size() == 2, "at range the boss opens two door frames beside the witch")
	var side: float = absf(boss().frames[0].x - arena.player.position.x)
	check(is_equal_approx(side, plan.frames.offset), "the frames stand to the witch's sides")
	await step(int(plan.frames.windup * 60) + 2)
	check(arena.bolts.size() == 2, "each frame fires an orb at release")
	for i in 120:
		if arena.bolts.is_empty():
			break
		await step()
	check(is_equal_approx(lost(), 2 * plan.frames.damage * power), "the crossfire orbs come in from the sides and hit")

	await fresh(Vector3(0, 0, -2.5))
	arena.spawn_ally(Vector3(0.6, 0, -0.9), false, "")
	var turret: Dictionary = arena.allies[0]
	turret.cooldown = 999
	arena.player.position = Vector3(0, 0, 4)
	boss().windup = 0.0
	boss().timers = {}
	boss().target = turret.id
	boss().retarget = 99
	await step(int(plan.sweep.windup * 60) + 3)
	check(turret.hp < turret.max_hp or arena.allies.is_empty(), "boss area attacks also hit summons inside the warning")

	await fresh(Vector3(0, 0, -5))
	# Cancel the slam it opened on its first frame; only the HP mark should act here.
	boss().windup = 0.0
	boss().attack = ""
	boss().timers = {"sweep": 99.0, "slam": 99.0, "frames": 99.0}
	boss().hp = boss().max_hp * 0.64
	await step(1)
	check(boss().attack == "shockwave" and boss().windup > 0, "crossing 65% HP starts a shockwave with a ground disc")
	await step(int(plan.shockwave.windup * 60) + 2)
	check(is_equal_approx(lost(), plan.shockwave.damage * power), "the shockwave hits the witch inside its radius")
	var adds = 0
	for id in arena.enemies:
		if not arena.enemies[id].respawn:
			adds += 1
	check(adds == int(plan.shockwave.adds.rag) + int(plan.shockwave.adds.crow), "the shockwave calls rag-ghouls and crows")
	await step(int(plan.shockwave.windup * 60) + 10)
	check(boss().attack != "shockwave" or boss().windup <= 0, "each HP mark triggers only once")
	boss().hp = boss().max_hp * 0.29
	await step(1)
	check(boss().attack == "shockwave" and boss().phases_done.size() == 2, "crossing 30% HP triggers the second shockwave")

	arena.a5_mode = true
	var add_id = ""
	for id in arena.enemies:
		if not arena.enemies[id].respawn:
			add_id = id
	var waiting: int = arena.respawns.size()
	arena.damage_enemy(add_id, 100000)
	arena.damage_enemy("boss", 1.0e9)
	check(arena.respawns.size() == waiting, "called adds and the boss never respawn in A5 mode")
	arena.a5_mode = false

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_boss_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
