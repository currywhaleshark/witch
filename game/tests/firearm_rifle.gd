extends SceneTree
## Firearm tree, single-shot line (03 §3): the rifled long gun reaches further and fires almost at
## once, with fewer, dearer rounds. Its node picks the round: plain (hardest hit, slight knockback),
## explosive (a small burst where it lands) or piercing (through every enemy on the line).
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
	# Tough enough to outlast every shot here: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func fresh(node: String) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.build.set_rifle_node(node)
	arena.bind_slot("q", "rifle")
	arena.bind_slot("w", "matchlock")
	enemy("front", Vector3(0, 0, 10))
	enemy("behind", Vector3(0, 0, 11.4))
	enemy("side", Vector3(4, 0, 10))
	await step(2)
	arena.request_slot("q", {"ground": [0, 0, 6]})
	await settle(0.9)
	# No mana holds the reload, so each shot's round stays spent.
	arena.state.mana = 0.0

func shoot() -> Dictionary:
	var hp := {}
	for id in arena.enemies:
		hp[id] = arena.enemies[id].hp
	arena.request_slot("lmb", {"enemy_id": "front"})
	var release: float = float(arena.windup.get("release", -1.0))
	await settle(1.3)
	var lost := {}
	for id in hp:
		lost[id] = hp[id] - arena.enemies[id].hp
	return {"release": release, "lost": lost}

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(5)
	var rifle: Dictionary = arena.rules.skills.rifle
	var matchlock: Dictionary = arena.rules.skills.matchlock

	check(float(rifle.range) > float(matchlock.range) and int(rifle.magazine) < int(matchlock.magazine) and float(rifle.round_cost) > float(matchlock.round_cost), "the rifle reaches further with fewer, dearer rounds than the matchlock")
	await fresh("base")
	check(arena.gun.get("id") == "rifle" and arena.gun.ammo == int(rifle.magazine), "the rifle assembles loaded")
	check(is_instance_valid(arena.gun.visual) and arena.gun.visual.parts_scene.resource_path.ends_with("/rifle.glb") and arena.gun.visual.scale.is_equal_approx(Vector3.ONE), "the rifle uses its dedicated long gun at authored scale")
	var start: Vector3 = arena.player.position
	var shot: Dictionary = await shoot()
	check(arena.player.position.distance_to(start) < 0.05, "it shoots from 10m without walking in")
	check(shot.release < arena.attack_seconds("matchlock") * float(matchlock.shot_release_ratio) * 0.5 and shot.release > 0, "it fires almost at once (%.2fs)" % shot.release)
	check(is_equal_approx(shot.lost.front, float(rifle.nodes.base.shot_damage)) and shot.lost.behind == 0.0 and shot.lost.side == 0.0, "a plain round hits only its target, for the most damage")
	check(arena.enemies.front.body.position.z > 10.2, "and shoves it back a little")
	check(float(rifle.nodes.base.shot_damage) > float(rifle.nodes.explosive.shot_damage) and float(rifle.nodes.base.shot_damage) > float(rifle.nodes.piercing.shot_damage), "plain rounds hit harder than the special ones")
	check(arena.gun.ammo == int(rifle.magazine) - 1, "each shot spends a round")

	var points: int = arena.build.skill_points()
	await fresh("explosive")
	check(arena.build.rifle_node == "explosive" and arena.build.skill_points() == points - int(arena.build.rules.node_cost), "a rifle node costs a skill point")
	arena.enemies.behind.body.position = Vector3(0, 0, 10.9)
	shot = await shoot()
	check(is_equal_approx(shot.lost.front, float(rifle.nodes.explosive.shot_damage)) and is_equal_approx(shot.lost.behind, float(rifle.nodes.explosive.shot_damage)), "an explosive round also catches an enemy close behind its target")
	check(shot.lost.side == 0.0, "but not one outside the burst")
	check(arena.enemies.front.body.position.z < 10.2, "explosive rounds do not knock back")

	await fresh("piercing")
	shot = await shoot()
	check(is_equal_approx(shot.lost.front, float(rifle.nodes.piercing.shot_damage)) and is_equal_approx(shot.lost.behind, float(rifle.nodes.piercing.shot_damage)), "a piercing round goes through its target into the one behind")
	check(shot.lost.side == 0.0, "but not one off the line")

	arena.state.mana = arena.state.max_mana
	arena.request_slot("w", {"ground": [0, 0, 6]})
	await settle(0.9)
	check(arena.gun.get("id") == "matchlock" and arena.gun.ammo == int(matchlock.magazine), "assembling the matchlock swaps the rifle for it")
	check(is_equal_approx(arena.reload_seconds("rifle"), float(rifle.reload_seconds)) and float(rifle.reload_seconds) > float(matchlock.reload_seconds), "rifle rounds take longer to load")
	arena.build.reset_skills()
	check(arena.build.rifle_node == "base", "resetting skills returns the plain round")
	arena.build.set_level(1)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
