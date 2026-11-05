extends SceneTree
## Spring dash nodes (2026-11-05): one point picks what the plate's kick does where she lands.
## Approach stuns the enemies round the landing spot (drive closes in to cut); retreat shoves
## them away (guns and summons keep their range). The base plate does neither. Bosses ignore
## both; heavy enemies slide half as far. Writes no report.
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

func fresh(node: String) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.build.set_skill_node("spring_dash", node)
	arena.bind_slot("q", "spring_dash")
	await step(2)

func foe(id: String, at: Vector3, grade: String = "normal", kind: String = "light") -> Dictionary:
	arena.spawn_enemy(id, at, grade == "boss", grade, kind)
	var enemy: Dictionary = arena.enemies[id]
	enemy.cooldown = 999
	enemy.max_hp = 999999.0
	enemy.hp = 999999.0
	return enemy

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func dash_to(ground: Vector3) -> void:
	# Dash and wait for the landing (cast 0.12s, leap 0.2s).
	arena.request_slot("q", {"ground": [ground.x, 0, ground.z]})
	var leapt := false
	for i in 90:
		await step()
		leapt = leapt or not arena.dash.is_empty()
		if leapt and arena.dash.is_empty():
			break

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	var plan: Dictionary = arena.rules.skills.spring_dash.nodes
	var build = arena.build

	# The base plate lands without touching anyone.
	await fresh("base")
	var idle: Dictionary = foe("idle", Vector3(1.0, 0, 4.4))
	foe("anchor", Vector3(-11, 0, -9))
	await step(2)
	await dash_to(Vector3(0, 0, 4))
	check(arena.player.position.z > 3.0, "the dash carries her to the cursor (%.2f)" % arena.player.position.z)
	check(arena.last_spring_landing.is_empty() and float(idle.get("stun", 0.0)) == 0.0 and float(idle.get("knockback_left", 0.0)) == 0.0, "the base plate lands with no effect")

	# A node costs one point; it never takes a key or a level.
	var points: int = build.skill_points()
	check(build.set_skill_node("spring_dash", "approach") and build.skill_points() == points - 1, "a landing node costs one point")
	check(arena.skill_window.effect_note("spring_dash").contains("기절"), "the skill window names the approach landing")
	build.set_skill_node("spring_dash", "base")

	# Approach: the enemies round the landing spot are stunned; far ones and the boss are not.
	await fresh("approach")
	var near: Dictionary = foe("near", Vector3(1.0, 0, 4.6))
	var far: Dictionary = foe("far", Vector3(-4.0, 0, 8.0))
	var boss: Dictionary = foe("boss", Vector3(-1.6, 0, 5.2), "boss", "latch")
	foe("anchor", Vector3(-11, 0, -9))
	await step(2)
	await dash_to(Vector3(0, 0, 4))
	check(arena.last_spring_landing.get("node") == "approach", "an approach landing fires once she lands")
	check(float(near.get("stun", 0.0)) > float(plan.approach.stun_seconds) - 0.2, "a nearby enemy is stunned (%.2fs)" % float(near.get("stun", 0.0)))
	check(float(far.get("stun", 0.0)) == 0.0, "an enemy outside the radius is not")
	check(float(boss.get("stun", 0.0)) == 0.0, "the boss is never stunned")
	check(float(near.get("knockback_left", 0.0)) == 0.0, "and nothing is shoved")
	var held: Vector3 = near.body.position
	await step(30)
	check(flat(near.body.position, held) < 0.01, "the stunned enemy stays put")

	# Retreat: the enemies round the landing spot are shoved away from her.
	await fresh("retreat")
	var light: Dictionary = foe("light", Vector3(1.0, 0, 4.6))
	var brute: Dictionary = foe("brute", Vector3(-1.2, 0, 5.0), "normal", "brute")
	var big: Dictionary = foe("boss", Vector3(0.6, 0, 2.6), "boss", "latch")
	foe("anchor", Vector3(-11, 0, -9))
	await step(2)
	await dash_to(Vector3(0, 0, 4))
	var landed: Vector3 = arena.last_spring_landing.get("at", arena.player.position)
	var light_gap: float = flat(light.body.position, landed)
	var brute_gap: float = flat(brute.body.position, landed)
	var boss_at: Vector3 = big.body.position
	await step(40)
	var light_moved: float = flat(light.body.position, landed) - light_gap
	var brute_moved: float = flat(brute.body.position, landed) - brute_gap
	check(arena.last_spring_landing.get("node") == "retreat" and light_moved > 0.8 * float(plan.retreat.knockback_distance), "a nearby enemy is shoved off (%.2fm)" % light_moved)
	check(brute_moved > 0.3 * float(plan.retreat.knockback_distance) and brute_moved < 0.7 * float(plan.retreat.knockback_distance), "a heavy enemy slides about half as far (%.2fm)" % brute_moved)
	check(flat(big.body.position, boss_at) < 0.01, "the boss is not moved")
	check(float(light.get("stun", 0.0)) == 0.0, "and nothing is stunned")

	# The recoil leap shares the leap code but never fires a spring landing.
	await fresh("retreat")
	arena.build.change_skill("recoil_leap", 1)
	arena.bind_slot("w", "recoil_leap")
	foe("anchor", Vector3(-11, 0, -9))
	await step(2)
	arena.request_slot("w", {"ground": [0, 0, 3]})
	await step(60)
	check(arena.last_spring_landing.is_empty(), "the recoil leap does not trigger the spring landing")

	# A skill reset refunds the node.
	build.set_skill_node("spring_dash", "retreat")
	build.reset_skills()
	check(arena.config.spring_dash_node == "base", "a skill reset takes the node back")

	print("SPRING_DASH_NODES ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
