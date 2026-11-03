extends SceneTree
## Firearm tree, rotary cannon (03 §3): a spin-up cast assembles the cannon, then it streams rounds
## while its key is held, turning after the cursor while the witch stands still and mana drains.
## Nodes: suppressing fire (wide, hard stagger every few hits, weaker rounds) or converging fire
## (narrow, rounds grow on the same enemy). Writes no report.
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

func settle(seconds: float) -> void:
	await step(int(60 * seconds))

func enemy(id: String, at: Vector3) -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", "light")
	var spawned: Dictionary = arena.enemies[id]
	spawned.cooldown = 999
	# Tough enough to outlast every round here: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func point_at(pos: Vector3) -> void:
	arena.pointer = arena.camera.unproject_position(pos)

func fresh(node: String = "base") -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.config.attack_speed_score = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.build.set_gatling_node(node)
	arena.bind_slot("q", "gatling")
	arena.bind_slot("w", "shotgun")
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)

func channel(at: Vector3) -> void:
	# What holding Q does: the hold is recorded, then the slot pressed.
	point_at(at)
	arena.hold = {"key": KEY_Q, "slot": "q", "shift": false, "enemy_id": ""}
	arena.request_slot("q", {"ground": [at.x, 0, at.z]})
	await settle(float(arena.rules.skills.gatling.cast_seconds) + 0.05)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(5)
	var skill: Dictionary = arena.rules.skills.gatling
	var nodes: Dictionary = skill.nodes

	check(skill.get("channel") == true and skill.get("targeting") == "direction" and arena.SKILL_TREES.gatling == "firearm" and arena.config.attack_tags.gatling == "projectile", "the rotary cannon is a channeled firearm projectile skill")
	await fresh()
	enemy("front", Vector3(0, 0, 6))
	var mana: float = arena.state.mana
	point_at(Vector3(0, 0, 6))
	arena.hold = {"key": KEY_Q, "slot": "q", "shift": false, "enemy_id": ""}
	arena.request_slot("q", {"ground": [0, 0, 6]})
	await step(5)
	var visual: Node3D = arena.gatling_assembly
	check(is_instance_valid(visual) and visual.debug_state().mode == "assembling" and arena.channel.is_empty(), "it assembles during its spin-up cast")
	check(is_instance_valid(visual) and visual.parts.size() == 32 and visual.rotor.size() == 16, "from the cannon's 32 parts, 16 of them on the rotor")
	await settle(float(skill.cast_seconds))
	check(not arena.channel.is_empty() and arena.channel.visual == visual and visual.debug_state().mode == "ready", "then it starts firing")
	check(mana - arena.state.mana >= float(skill.mana_cost), "the spin-up pays its mana")
	mana = arena.state.mana
	var shots: int = arena.channel.shots
	await settle(1.0)
	var fired: int = arena.channel.shots - shots
	check(absi(fired - roundi(1.0 / float(skill.fire_seconds))) <= 1, "it fires %d rounds a second" % fired)
	check(absf(mana - arena.state.mana - float(skill.channel_mana_per_second)) < 0.3, "and drains its mana by the second (%.2f)" % (mana - arena.state.mana))
	check(lost("front") > 0 and fmod(lost("front"), float(nodes.base.shot_damage) * arena.skill_level_factor("gatling")) < 0.01, "its rounds strike the enemy under the cursor")
	check(visual.debug_state().spin_speed > 0.99 and visual.debug_state().spin > 0.0, "its rotor spins")

	enemy("side", Vector3(6, 0, 0))
	point_at(Vector3(6, 0, 0))
	await settle(0.4)
	var side_before: float = lost("side")
	var front_before: float = lost("front")
	await settle(0.5)
	check(lost("side") > side_before and is_equal_approx(lost("front"), front_before), "the stream turns to follow the cursor")
	check((-arena.player_model.global_basis.z).dot(Vector3.RIGHT) > 0.95, "and she turns with it")

	var spot: Vector3 = arena.player.position
	arena.move_hold = {"button": MOUSE_BUTTON_LEFT}
	arena.request_slot("lmb", {"ground": [-6, 0, 0]})
	point_at(Vector3(-6, 0, 0))
	await settle(0.6)
	check(arena.player.position.distance_to(spot) < 0.01 and not arena.channel.is_empty(), "a ground click does not move her while she channels")
	arena.move_hold.clear()
	point_at(Vector3(6, 0, 0))

	arena.paused = true
	shots = arena.channel.shots
	await settle(0.3)
	check(arena.channel.shots == shots, "pausing stops the stream")
	arena.paused = false

	arena.hold.clear()
	await step(2)
	check(arena.channel.is_empty() and visual.debug_state().mode == "dismissed", "releasing the key stops it and the cannon comes apart")

	await fresh()
	enemy("front", Vector3(0, 0, 6))
	await channel(Vector3(0, 0, 6))
	arena.state.mana = 0.05
	await step(3)
	check(arena.channel.is_empty() and arena.message == "마나 부족 · 사격 중지", "running out of mana stops it")

	await fresh()
	enemy("front", Vector3(0, 0, 6))
	await channel(Vector3(0, 0, 6))
	arena.hold = {"key": KEY_W, "slot": "w", "shift": false, "enemy_id": ""}
	arena.request_slot("w", {"ground": [0, 0, 6]})
	check(arena.channel.is_empty(), "another skill ends the stream")

	await fresh()
	enemy("front", Vector3(0, 0, 6))
	await channel(Vector3(0, 0, 6))
	arena.damage_player(arena.config.max_hp * 0.5)
	check(arena.channel.is_empty(), "a staggering hit ends it")
	arena.hp = arena.config.max_hp

	# Spread: an enemy 1.6m off the line at 6m sits outside the plain stream but inside the barrage;
	# one 1.1m off is grazed by the plain stream but missed by the converging one.
	for case in [["base", 1.6, false], ["suppress", 1.6, true], ["base", 1.1, true], ["converge", 1.1, false]]:
		await fresh(case[0])
		enemy("front", Vector3(0, 0, 6))
		enemy("off", Vector3(case[1], 0, 6))
		await channel(Vector3(0, 0, 6))
		await settle(2.0)
		check((lost("off") > 0) == case[2], "%s fire %s an enemy %.1fm off the line" % [case[0], "reaches" if case[2] else "misses", case[1]])
		arena.hold.clear()
		await step(2)

	await fresh("suppress")
	var target: Dictionary = enemy("front", Vector3(0, 0, 6))
	await channel(Vector3(0, 0, 6))
	var longest := 0.0
	# The wide barrage puts only some rounds on one enemy, so give it a few seconds.
	for i in 300:
		await step()
		longest = maxf(longest, float(target.flinch))
	# Sampled after the frame that set it has already ticked it down once.
	var stagger: float = arena.flinch_seconds(target) * float(nodes.suppress.stagger_factor)
	check(longest <= stagger + 0.001 and longest > stagger - 0.05, "suppressing fire staggers hard every %d hits (%.2fs)" % [int(nodes.suppress.stagger_hits), longest])
	check(float(nodes.suppress.shot_damage) < float(nodes.base.shot_damage), "but its rounds are weaker")
	arena.hold.clear()

	await fresh("converge")
	enemy("front", Vector3(0, 0, 6))
	await channel(Vector3(0, 0, 6))
	await settle(0.15)
	var first: float = lost("front")
	var hits: int = arena.channel.focus_hits
	await settle(2.0)
	var later: float = (lost("front") - first) / float(arena.channel.focus_hits - hits)
	check(later > float(nodes.converge.shot_damage) * arena.skill_level_factor("gatling") * 1.3, "converging rounds grow on the same enemy (%.1f per round)" % later)
	enemy("second", Vector3(2, 0, 5))
	point_at(Vector3(2, 0, 5))
	await settle(0.4)
	check(arena.channel.focus == "second" and arena.channel.focus_hits < 5, "and start over on a new one")
	arena.hold.clear()

	var points: int = arena.build.skill_points()
	arena.build.set_gatling_node("base")
	check(arena.build.skill_points() == points + int(arena.build.rules.node_cost), "a cannon node costs a skill point")
	var slow: float = arena.gatling_interval()
	arena.config.attack_speed_score = 40
	check(arena.gatling_interval() < slow, "attack speed quickens the stream")
	arena.config.attack_speed_score = 0
	await fresh("suppress")
	enemy("front", Vector3(0, 0, 6))
	await channel(Vector3(0, 0, 6))
	arena.reset_arena()
	check(arena.channel.is_empty() and arena.build.gatling_node == "suppress", "resetting the field ends the stream but keeps the build")
	arena.build.reset_skills()
	check(arena.build.gatling_node == "base", "resetting skills returns the plain stream")
	arena.build.set_level(1)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
