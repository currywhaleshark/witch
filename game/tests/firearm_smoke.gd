extends SceneTree
## Firearm tree, smoke launcher (03 §3): canisters lobbed onto the aimed area raise a cloud. An
## enemy inside it, or looking at the witch through it, cannot see her: it turns on a summon in
## sight, or gropes slowly toward where it last saw her and starts no attack. Her own shots, her
## summons and bosses see through it. Writes no report.
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

func enemy(id: String, at: Vector3, kind: String = "light") -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", kind)
	var spawned: Dictionary = arena.enemies[id]
	spawned.cooldown = 0.0
	# Tough enough to outlast the test: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func fresh() -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.mana_regen = 0
	arena.config.enemy_speed = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.bind_slot("q", "smoke_launcher")
	enemy("anchor", Vector3(-11, 0, -9)).cooldown = 999
	await step(2)

func smoke_at(at: Vector3) -> void:
	# Cast, then wait for the canisters to land and the cloud to stand.
	arena.request_slot("q", {"ground": [at.x, 0, at.z]})
	var skill: Dictionary = arena.rules.skills.smoke_launcher
	await settle(float(skill.cast_seconds) * float(skill.release_ratio) + float(skill.flight_seconds) + 0.1)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	var skill: Dictionary = arena.rules.skills.smoke_launcher

	check(skill.get("targeting") == "direction" and arena.SKILL_TREES.smoke_launcher == "firearm", "the smoke launcher is a firearm skill aimed by direction")
	await fresh()
	var mana: float = arena.state.mana
	arena.request_slot("q", {"ground": [0, 0, 5]})
	await step(5)
	var launcher: Node3D = arena.smoke_assembly
	check(is_instance_valid(launcher) and launcher.debug_state().mode == "assembling" and launcher.parts.size() == 32, "its 32-part launcher assembles at her side during the cast")
	await settle(float(skill.cast_seconds) * float(skill.release_ratio))
	check(arena.smokes.size() == 1 and launcher.debug_state().mode == "fired" and arena.smoke_assembly == null, "on release it fires its canisters")
	check(is_equal_approx(mana - arena.state.mana, float(skill.mana_cost)) and float(arena.state.cooldowns.get("smoke_launcher", 0.0)) > 0.0, "paying its mana and starting its cooldown")
	var smoke: Dictionary = arena.smokes[0]
	check(smoke.center.distance_to(Vector3(0, 0, 5)) < 0.01, "the cloud stands where she aimed")
	check(not arena.hidden_between(Vector3(0, 0, 5), Vector3.ZERO) and smoke.cloud.density() == 0.0, "nothing is hidden while the canisters fly")
	await settle(float(skill.flight_seconds) + 0.5)
	check(arena.hidden_between(Vector3(0, 0, 5), Vector3(4, 0, 5)) and arena.hidden_between(Vector3(0, 0, 9), Vector3(0, 0, 1)) and smoke.cloud.density() > 0.9, "once they land the cloud hides what is in it and behind it")
	check(not arena.hidden_between(Vector3(5, 0, 0), Vector3(-1, 0, 0)), "but not a line that passes it by")
	arena.paused = true
	var left: float = smoke.left
	await settle(0.5)
	check(is_equal_approx(smoke.left, left), "pausing holds the smoke")
	arena.paused = false
	await settle(float(skill.smoke_seconds))
	check(arena.smokes.is_empty() and not is_instance_valid(smoke.cloud), "it clears after %.0f seconds" % float(skill.smoke_seconds))

	# A walker behind the cloud loses her: it keeps only a slow grope toward where it last saw her.
	await fresh()
	arena.config.enemy_speed = 1.6
	var walker: Dictionary = enemy("walker", Vector3(0, 0, 9))
	await settle(0.2)
	await smoke_at(Vector3(0, 0, 5))
	check(arena.blinded(walker) and walker.target == "", "an enemy behind the smoke cannot see her")
	var from: Vector3 = walker.body.position
	await settle(0.5)
	var crept: float = from.distance_to(walker.body.position)
	check(crept > 0.05 and crept < 0.5 * float(arena.config.enemy_speed) * float(skill.blind_speed) * 1.3, "it gropes forward slowly (%.2fm in 0.5s)" % crept)
	walker.body.position = Vector3(0, 0, 1.2)
	walker.last_seen = Vector3.ZERO
	arena.smokes[0].center = Vector3(0, 0, 1.2)
	var hp: float = arena.hp
	await settle(2.0)
	check(walker.windup == 0.0 and is_equal_approx(arena.hp, hp), "inside the smoke right next to her it starts no attack")
	arena.smokes[0].left = 0.01
	await settle(1.5)
	check(arena.hp < hp, "once the smoke clears it attacks again")
	arena.config.enemy_speed = 0

	await fresh()
	var crow: Dictionary = enemy("crow", Vector3(0, 0, 7), "crow")
	crow.cooldown = 999
	await smoke_at(Vector3(0, 0, 3.5))
	crow.cooldown = 0.0
	var bolts: int = arena.bolts.size()
	await settle(3.0)
	check(arena.bolts.size() == bolts and crow.windup == 0.0, "a crow cannot shoot her through the smoke")

	await fresh()
	var brute: Dictionary = enemy("brute", Vector3(0, 0, 6), "brute")
	brute.cooldown = 999
	brute.charge_cooldown = 999
	arena.spawn_ally(Vector3(3.5, 0, 6), false, "")
	await smoke_at(Vector3(0, 0, 3))
	await step(2)
	check(brute.target != "" and arena.ally_by_id(brute.target).node.position.distance_to(Vector3(3.5, 0, 6)) < 0.5, "an enemy that loses her turns on a summon in sight")

	await fresh()
	var target: Dictionary = enemy("target", Vector3(0, 0, 1.3))
	target.cooldown = 999
	await smoke_at(Vector3(0, 0, 1.3))
	var before: float = target.hp
	arena.request_slot("lmb", {"enemy_id": "target"})
	await settle(1.0)
	check(arena.blinded(target) and target.hp < before, "her own attacks still reach into the smoke")

	await fresh()
	arena.spawn_enemy("boss", Vector3(0, 0, 4), false, "boss", "latch")
	await smoke_at(Vector3(0, 0, 4))
	check(not arena.blinded(arena.enemies.boss), "a boss sees through it")

	arena.build.set_level(5)
	var base: float = arena.smoke_seconds()
	arena.build.change_skill("smoke_launcher", 2)
	check(is_equal_approx(arena.smoke_seconds(), base + 2 * float(skill.seconds_per_level)), "its skill level makes the smoke last longer")
	arena.build.reset_skills()
	arena.build.set_level(1)

	await fresh()
	await smoke_at(Vector3(0, 0, 5))
	arena.reset_arena()
	check(arena.smokes.is_empty(), "resetting the field clears the smoke")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
