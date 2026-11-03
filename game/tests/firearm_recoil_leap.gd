extends SceneTree
## Firearm tree, recoil leap (03 §3): learned with a point after the shotgun, it fires a short wide
## blast that shoves the enemies in front away while its kick throws the witch straight back,
## still facing her aim. Hits cannot stagger her mid-leap. Writes no report.
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
	spawned.cooldown = 999
	# Tough enough to outlast the test: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func fresh(at: Vector3 = Vector3.ZERO) -> void:
	arena.reset_arena()
	arena.player.position = at
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)

func leap(toward: Vector3) -> void:
	arena.request_slot("q", {"ground": [toward.x, 0, toward.z]})
	await settle(0.6)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	var skill: Dictionary = arena.rules.skills.recoil_leap
	var build = arena.build

	# Learning: after the shotgun, for a point.
	build.set_level(3)
	check(build.requires.get("recoil_leap") == "shotgun" and build.skills.recoil_leap == 0 and not build.learned("recoil_leap"), "the recoil leap starts unlearned and needs the shotgun")
	await fresh()
	arena.bind_slot("q", "recoil_leap")
	var mana: float = arena.state.mana
	arena.request_slot("q", {"ground": [0, 0, 5]})
	check(arena.message == "배우지 않은 기술입니다" and arena.windup.is_empty() and arena.state.mana == mana, "an unlearned leap does nothing")
	build.skills.shotgun = 0
	check(not build.change_skill("recoil_leap", 1), "it cannot be learned before the shotgun")
	build.skills.shotgun = 1
	var points: int = build.skill_points()
	check(build.change_skill("recoil_leap", 1) and build.skill_points() == points - 1 and build.learned("recoil_leap"), "with the shotgun learned it takes one point")
	check(not build.change_skill("shotgun", -1), "and the shotgun cannot be dropped under it")
	var node = arena.skill_window.find_node("recoil_leap")
	check(node != null and int(node.tier) == 3, "it sits in the tree below the shotgun")
	var links: Array = arena.skill_window.TREE_UI.trees[0].links
	check(links.has(["산탄포", "반동 도약"]), "linked from it")

	# The leap: blast forward, thrown back.
	await fresh()
	arena.bind_slot("q", "recoil_leap")
	enemy("front", Vector3(0, 0, 2))
	enemy("wide", Vector3(1.6, 0, 1.4))
	enemy("behind", Vector3(2.2, 0, -3))
	enemy("far", Vector3(0, 0, 6))
	mana = arena.state.mana
	arena.request_slot("q", {"ground": [0, 0, 5]})
	await settle(0.6)
	check(is_equal_approx(lost("front"), float(skill.shot_damage)) and is_equal_approx(lost("wide"), float(skill.shot_damage)), "the blast hits the enemies in front of her")
	check(lost("behind") == 0.0 and lost("far") == 0.0, "but not those behind or past its reach")
	check(arena.enemies.front.body.position.z > 3.5, "and shoves them away")
	check(arena.player.position.z < -float(skill.leap_distance) + 0.3 and absf(arena.player.position.x) < 0.05, "its kick throws her straight back (%.2fm)" % -arena.player.position.z)
	check((-arena.player_model.global_basis.z).dot(Vector3.BACK) > 0.95, "still facing her aim")
	check(is_equal_approx(mana - arena.state.mana, float(skill.mana_cost)) and float(arena.state.cooldowns.get("recoil_leap", 0.0)) > 0.0, "it pays its mana and starts its cooldown")
	check(arena.last_shotgun.is_empty(), "it is not the shotgun skill firing")

	await fresh()
	arena.bind_slot("q", "recoil_leap")
	enemy("front", Vector3(0, 0, 2))
	arena.request_slot("q", {"ground": [0, 0, 5]})
	for i in 60:
		await step()
		if not arena.dash.is_empty():
			break
	var hp: float = arena.hp
	arena.damage_player(arena.config.max_hp * 0.5)
	check(arena.hp < hp and arena.stun_time <= 0.0, "a hit mid-leap does not stagger her")
	arena.hp = arena.config.max_hp
	await settle(0.5)

	await fresh(Vector3(0, 0, -10))
	arena.bind_slot("q", "recoil_leap")
	await leap(Vector3(0, 0, -5))
	check(arena.player.position.z >= arena.map.bounds.position.y and arena.last_recoil.leap < float(skill.leap_distance), "the field's edge behind cuts the leap short (%.1fm)" % arena.last_recoil.leap)

	await fresh()
	arena.bind_slot("q", "recoil_leap")
	arena.bind_slot("w", "matchlock")
	arena.request_slot("w", {"ground": [0, 0, 5]})
	await settle(0.9)
	await leap(Vector3(0, 0, 5))
	check(arena.gun.get("id") == "matchlock", "a floating gun stays out through the leap")

	build.reset_skills()
	check(build.skills.recoil_leap == 0 and arena.state.bindings.q == null, "resetting skills unlearns it and takes it off its key")
	build.set_level(1)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
