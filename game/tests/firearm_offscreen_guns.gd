extends SceneTree
## Firearm tree IV (03 §3): the rocket barrage and the heavy naval gun fire from beyond the screen.
## The barrage drops eight shells at uneven moments over a wide circle (high explosive, cluster
## bomblets bursting overhead, or white phosphorus that sets the ground burning); the naval gun
## drops one slow heavy shell (plain, a wide burst that leaves fire, or a narrow piercing round).
## Writes no report.
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
	# Tough enough to outlast the test: a dead last enemy clears the field and stops the clock.
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func lost(id: String) -> float:
	return 99999.0 - float(arena.enemies[id].hp)

func fresh() -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.bind_slot("q", "artillery")
	arena.bind_slot("w", "naval_gun")
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(5)
	var barrage: Dictionary = arena.rules.skills.artillery
	var naval: Dictionary = arena.rules.skills.naval_gun

	await fresh()
	enemy("center", Vector3(0, 0, 8))
	enemy("far", Vector3(7, 0, 8))
	var mana: float = arena.state.mana
	arena.request_slot("q", {"ground": [0, 0, 8]})
	await settle(float(barrage.cast_seconds) * float(barrage.release_ratio) + 0.05)
	check(arena.shells.size() == int(barrage.shells) and is_equal_approx(mana - arena.state.mana, float(barrage.mana_cost)), "the barrage calls in %d shells for its mana" % int(barrage.shells))
	var landings: Array = arena.shells.map(func(shell): return float(shell.left))
	var gaps: Array = []
	landings.sort()
	for i in range(1, landings.size()):
		gaps.append(snappedf(landings[i] - landings[i - 1], 0.01))
	check(gaps.min() < gaps.max() - 0.05, "landing at uneven moments")
	var widest := 0.0
	for shell in arena.shells:
		widest = maxf(widest, Vector2(shell.at.x, shell.at.z - 8).length())
		check(shell.start.y > shell.at.y + 20.0, "each shell starts far overhead, off screen")
	check(widest > float(barrage.spread_radius) * 0.8, "scattered over a wide circle (%.1fm)" % widest)
	await settle(0.9)
	var seen: Array = arena.shells.filter(func(shell): return is_instance_valid(shell.visual) and shell.visual.visible)
	check(not seen.is_empty(), "the shells are seen falling in")
	await settle(float(barrage.barrage_seconds) + 0.5)
	check(arena.shells.is_empty() and lost("center") > 0 and lost("far") == 0.0, "they blast the aimed area, not beyond it")
	check(fmod(lost("center"), float(barrage.nodes.base.shot_damage) * arena.skill_level_factor("artillery")) < 0.01, "each high-explosive hit deals its shell damage")

	await fresh()
	arena.build.set_skill_node("artillery", "cluster")
	enemy("center", Vector3(0, 0, 8))
	arena.request_slot("q", {"ground": [0, 0, 8]})
	await settle(float(barrage.cast_seconds) * float(barrage.release_ratio) + 0.05)
	var airburst: Array = arena.shells.filter(func(shell): return shell.end.y > shell.at.y + 2.0)
	check(airburst.size() == int(barrage.shells), "cluster shells burst overhead")
	await settle(float(barrage.barrage_seconds) + 1.0)
	var bomblet: float = float(barrage.nodes.cluster.shot_damage) * arena.skill_level_factor("artillery")
	check(lost("center") > 0 and fmod(lost("center"), bomblet) < 0.01, "and rain bomblets of %.1f each" % bomblet)
	check(float(barrage.nodes.cluster.shot_damage) < float(barrage.nodes.base.shot_damage) and float(barrage.nodes.cluster.spread_radius) > float(barrage.spread_radius), "weaker per hit, over a wider patch")

	await fresh()
	arena.build.set_skill_node("artillery", "phosphorus")
	var target: Dictionary = enemy("center", Vector3(0, 0, 8))
	arena.request_slot("q", {"ground": [0, 0, 8]})
	await settle(float(barrage.cast_seconds) + float(barrage.first_delay) + float(barrage.barrage_seconds) + 0.3)
	check(not arena.fires.is_empty(), "white phosphorus leaves the ground burning")
	var burnt: float = lost("center")
	target.flinch = 0.0
	await settle(1.0)
	check(lost("center") > burnt and float(target.flinch) == 0.0, "an enemy in the fire keeps burning without flinching")
	check(float(arena.probe.sources.burn.damage) > 0.0, "burning counts as its own damage source")
	await settle(float(barrage.nodes.phosphorus.fire_seconds))
	check(arena.fires.is_empty(), "and the fire dies down")

	await fresh()
	enemy("center", Vector3(0, 0, 10))
	enemy("near", Vector3(2.8, 0, 10))
	arena.request_slot("w", {"ground": [0, 0, 10]})
	await settle(float(naval.cast_seconds) * float(naval.release_ratio) + 0.05)
	check(arena.shells.size() == 1 and lost("center") == 0.0, "the naval gun sends one shell")
	await settle(float(naval.delay) - 0.2)
	check(lost("center") == 0.0, "which takes its time to arrive")
	await settle(0.4)
	var heavy: float = float(naval.nodes.base.shot_damage) * arena.skill_level_factor("naval_gun")
	check(is_equal_approx(lost("center"), heavy) and lost("near") == 0.0, "then hits hard (%.0f) where it was aimed" % heavy)

	await fresh()
	arena.build.set_skill_node("naval_gun", "burst")
	enemy("center", Vector3(0, 0, 10))
	enemy("near", Vector3(2.8, 0, 10))
	arena.request_slot("w", {"ground": [0, 0, 10]})
	await settle(float(naval.cast_seconds) + float(naval.delay) + 0.1)
	check(lost("near") > 0 and not arena.fires.is_empty(), "a bursting shell reaches wider and leaves fire")

	await fresh()
	arena.build.set_skill_node("naval_gun", "pierce")
	enemy("center", Vector3(0, 0, 10))
	enemy("near", Vector3(1.6, 0, 10))
	arena.request_slot("w", {"ground": [0, 0, 10]})
	await settle(float(naval.cast_seconds) + float(naval.delay) + 0.1)
	check(is_equal_approx(lost("center"), float(naval.nodes.pierce.shot_damage) * arena.skill_level_factor("naval_gun")) and lost("near") == 0.0, "a piercing round hits one enemy hardest")

	await fresh()
	arena.request_slot("q", {"ground": [0, 0, 8]})
	await settle(1.0)
	arena.reset_arena()
	check(arena.shells.is_empty() and arena.fires.is_empty(), "resetting the field calls off the shells")
	arena.build.reset_skills()
	check(arena.build.skill_nodes.artillery == "base" and arena.build.skill_nodes.naval_gun == "base", "resetting skills returns the plain shells")
	arena.build.set_level(1)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
