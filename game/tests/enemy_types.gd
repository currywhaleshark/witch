extends SceneTree
## 08 §6.2 trial enemies: rag-ghoul pack melee, wire-crow ranged orbs, iron-door brute charge and slam.
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

func fresh(kind: String, at: Vector3) -> void:
	# One enemy of the given kind; the witch stands at the origin.
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("e", at, false, "normal", kind)
	arena.enemies.e.cooldown = 999
	arena.enemies.e.charge_cooldown = 999
	await step(2)

func flat_distance() -> float:
	var delta: Vector3 = arena.enemies.e.body.position - arena.player.position
	delta.y = 0
	return delta.length()

func wait_for(condition: Callable, frames: int) -> void:
	for i in frames:
		if condition.call():
			return
		await step()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)

	var kinds: Dictionary = {}
	var champion_rag = false
	var elite_crow = false
	for id in arena.enemies:
		var enemy: Dictionary = arena.enemies[id]
		kinds[enemy.kind] = kinds.get(enemy.kind, 0) + 1
		champion_rag = champion_rag or (enemy.kind == "rag" and enemy.grade == "champion")
		elite_crow = elite_crow or (enemy.kind == "crow" and enemy.grade == "elite")
	check(kinds.get("rag", 0) == 5 and kinds.get("crow", 0) == 2 and kinds.get("brute", 0) == 1, "the field is a rag-ghoul pack, two crows and a brute")
	check(champion_rag and elite_crow, "grades still apply on top of the new types")
	var types: Dictionary = arena.config.enemy_types
	check(types.rag.hp < types.crow.hp and types.crow.hp < types.brute.hp and types.rag.speed > types.brute.speed, "rag-ghouls are weak and fast, brutes tough and slow")

	await fresh("rag", Vector3(3, 0, 0))
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return arena.hp < arena.config.max_hp, 180)
	check(is_equal_approx(arena.config.max_hp - arena.hp, types.rag.damage) and arena.stun_time == 0, "a rag-ghoul closes in and scratches without stunning")

	await fresh("crow", Vector3(2, 0, 0))
	await step(60)
	check(flat_distance() > 3.5, "a crow backs off when the witch is close")
	await fresh("crow", Vector3(11, 0, 0))
	await step(120)
	check(flat_distance() <= types.crow.ranged.keep_max + 0.3, "a crow closes in to its firing band")

	await fresh("crow", Vector3(6, 0, 0))
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return not arena.bolts.is_empty(), 120)
	check(arena.bolts.size() == 1 and arena.hp == arena.config.max_hp, "a crow fires an orb after its windup")
	arena.enemies.e.cooldown = 999
	await wait_for(func(): return arena.bolts.is_empty(), 180)
	check(is_equal_approx(arena.config.max_hp - arena.hp, types.crow.damage) and arena.stun_time == 0, "the orb flies to the witch and hits without stunning")

	await fresh("crow", Vector3(6, 0, 0))
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return not arena.bolts.is_empty(), 120)
	arena.enemies.e.cooldown = 999
	arena.player.position = Vector3(0, 0, 3)
	await wait_for(func(): return arena.bolts.is_empty(), 180)
	check(arena.hp == arena.config.max_hp, "stepping aside dodges an orb in flight")

	await fresh("crow", Vector3(6, 0, 0))
	arena.shield_time = 5.0
	arena.rules.skills.shield.block_base = 1.0
	arena.rules.skills.shield.block_cap = 1.0
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return not arena.bolts.is_empty(), 120)
	arena.enemies.e.cooldown = 999
	await wait_for(func(): return arena.bolts.is_empty(), 180)
	check(arena.hp == arena.config.max_hp and arena.probe.counts.blocks == 1, "the shield blocks a crow's orb")
	arena.rules.skills.shield.block_base = 0.2
	arena.rules.skills.shield.block_cap = 0.75

	await fresh("brute", Vector3(5, 0, 0))
	arena.enemies.e.cooldown = 0
	arena.enemies.e.charge_cooldown = 0
	await step(2)
	check(arena.enemies.e.attack == "charge" and arena.enemies.e.windup > 0 and arena.effects.size() > 0, "a brute at mid range winds up a charge with a ground warning")
	var start: Vector3 = arena.enemies.e.body.position
	await wait_for(func(): return arena.hp < arena.config.max_hp, 120)
	check(is_equal_approx(arena.config.max_hp - arena.hp, types.brute.charge.damage) and arena.stun_time > 0, "the charge hits hard enough to stun")
	check(arena.enemies.e.body.position.distance_to(start) > 2.0, "the brute actually dashes along the line")

	await fresh("brute", Vector3(5, 0, 0))
	arena.enemies.e.cooldown = 0
	arena.enemies.e.charge_cooldown = 0
	await step(2)
	arena.player.position = Vector3(0, 0, 4)
	await step(int((types.brute.charge.windup + 1.0) * 60))
	check(arena.hp == arena.config.max_hp, "leaving the warning strip dodges the charge")

	await fresh("brute", Vector3(1.6, 0, 0))
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return arena.hp < arena.config.max_hp, 120)
	check(arena.enemies.e.attack == "melee" and is_equal_approx(arena.config.max_hp - arena.hp, types.brute.damage) and arena.stun_time > 0, "up close the brute slams and stuns")

	await fresh("rag", Vector3(5, 0, 0))
	arena.spawn_ally(Vector3(2.5, 0, 0), false, "")
	var turret: Dictionary = arena.allies[0]
	turret.cooldown = 999
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return turret.hp < turret.max_hp, 180)
	check(turret.hp < turret.max_hp and arena.hp == arena.config.max_hp and arena.enemies.e.target == turret.id, "an enemy closer to a turret attacks the turret, not the witch")
	turret.hp = 1.0
	await wait_for(func(): return arena.allies.is_empty(), 180)
	check(arena.allies.is_empty() and arena.probe.counts.allies_lost == 1, "a turret at zero HP is destroyed")
	await wait_for(func(): return arena.hp < arena.config.max_hp, 240)
	check(arena.hp < arena.config.max_hp, "with the turret gone the enemy turns on the witch")

	await fresh("crow", Vector3(8, 0, 0))
	arena.spawn_ally(Vector3(4, 0, 0), false, "")
	arena.allies[0].cooldown = 999
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return arena.allies[0].hp < arena.allies[0].max_hp, 180)
	check(arena.allies[0].hp < arena.allies[0].max_hp and arena.hp == arena.config.max_hp, "a crow shoots the nearer turret")

	await fresh("rag", Vector3(2, 0, 0))
	arena.spawn_ally(Vector3(-6, 0, 0), true, "")
	arena.allies[0].cooldown = 999
	arena.enemies.e.cooldown = 0
	await wait_for(func(): return arena.hp < arena.config.max_hp, 180)
	check(arena.hp < arena.config.max_hp and arena.allies[0].hp == arena.allies[0].max_hp, "the witch keeps aggro when she is nearer than the summon")

	await fresh("rag", Vector3(3, 0, 0))
	arena.spawn_ally(Vector3(3, 0, 2.5), false, "")
	var guard: Dictionary = arena.allies[0]
	var rag: Dictionary = arena.enemies.e
	rag.target = ""
	check(arena.nearest_foe(rag) == "", "the witch's bias keeps aggro over a slightly closer turret")
	rag.target = guard.id
	arena.player.position = Vector3(-0.2, 0, 0)
	check(arena.nearest_foe(rag) == guard.id, "a held target is kept while the other is only a little closer")
	arena.player.position = Vector3(1.0, 0, 0)
	check(arena.nearest_foe(rag) == "", "the target switches once the other is clearly closer")
	guard.node.free()
	arena.allies.clear()
	rag.target = "gone"
	check(arena.nearest_foe(rag) == "", "a lost target is replaced without the switch margin")

	arena.set_a5_mode(true)
	var crow_id = ""
	for id in arena.enemies:
		if arena.enemies[id].kind == "crow":
			crow_id = id
	arena.damage_enemy(crow_id, 100000)
	check(arena.respawns.size() == 1 and arena.respawns[0].kind == "crow", "A5 respawns keep the enemy type")
	arena.set_a5_mode(false)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_enemy_types_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
