extends "res://tests/player_visual.gd"
## Compare actual gameplay outcomes with each presentation variant selected.
var variant_cases: Array = []

func force_variant(kind: String) -> void:
	var probe := RandomNumberGenerator.new()
	for value in range(1, 100):
		probe.seed = value
		var selected := "attack" if probe.randf() < 0.5 else "attack_thrust"
		if selected == kind:
			visual()._attack_rng.seed = value
			return
	check(false, "deterministic seed exists for " + kind)

func run_case(kind: String, speed: int, outcome: String) -> Dictionary:
	await fresh()
	arena.config.attack_speed_score = speed
	arena.combat_rng.seed = 424242
	arena.force_rolls = {"hit": outcome != "miss", "crit": outcome == "critical"}
	force_variant(kind)
	var health: float = arena.enemies.target.hp
	var mana: float = arena.state.mana
	var origin: Vector3 = arena.player.position
	arena.request_slot("lmb", {"enemy_id": "target"})
	check(state().attack_variant == kind, "selected requested variant: %s/%d/%s" % [kind, speed, outcome])
	var selected: String = state().clip
	var duration: float = arena.action_time
	var released := -1
	var frames := 0
	var sequence := ("swing" if kind == "attack" else "thrust") if speed == 0 and outcome == "hit" else ""
	while frames < 180 and state().state == "attack":
		frames += 1
		var pending: bool = not arena.windup.is_empty()
		await step(1, sequence)
		if pending and arena.windup.is_empty():
			released = frames
			check(absf(clip_fraction() - 0.5) < 0.0001, "actual release pose 0.5: " + sequence + outcome + str(speed))
			check(absf(float(state().staff_slide_m) - 0.16) < 0.00001, "both attack grips are at the lower shaft at release")
		check(arena.player.position.is_equal_approx(origin), "attack has no world displacement")
		if state().state == "attack":
			check(state().clip == selected, "variant is latched for the complete action")
	check(frames < 180 and state().state == "idle", "attack returns to idle")
	check(absf(float(state().staff_slide_m) + 0.26) < 0.00001, "grip slide returns to the idle attachment")
	var result := {"duration": duration, "release_frame": released, "recovery_frames": frames,
		"damage": health - arena.enemies.target.hp, "mana_cost": mana - arena.state.mana,
		"combat_rng_state": arena.combat_rng.state, "range": arena.rules.skills.basic_attack.range,
		"position": [arena.player.position.x, arena.player.position.y, arena.player.position.z]}
	variant_cases.append({"variant": kind, "speed": speed, "outcome": outcome, "result": result})
	return result

func run() -> void:
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	if not check(visual().loaded_ok, "selected character assets load"):
		finish(); return
	for speed in [0, 40]:
		for outcome in ["hit", "critical", "miss"]:
			var swing := await run_case("attack", speed, outcome)
			var thrust := await run_case("attack_thrust", speed, outcome)
			check(swing == thrust, "identical damage/mana/range/release/recovery/RNG for both variants: %d/%s" % [speed, outcome])
	# Sampling presentation randomness must not affect either combat or global RNG.
	await fresh()
	var random_state: int = arena.combat_rng.state
	seed(90210)
	var expected_random := randf()
	seed(90210)
	var selected_counts := {"attack": 0, "attack_thrust": 0}
	visual()._attack_rng.seed = 123456
	for i in 64:
		visual().begin_motion("attack", 1.0, 0.5)
		selected_counts[visual()._attack_clip_kind] += 1
	check(randf() == expected_random and arena.combat_rng.state == random_state, "visual random selection leaves global and combat RNG unchanged")
	check(selected_counts.attack > 0 and selected_counts.attack_thrust > 0, "both random variants occur")
	observations.random_counts = selected_counts
	# Exact authored endpoints return both feet to the idle pose.
	visual()._sample("idle", 0.0)
	var idle_feet: Array = []
	for side in ["L", "R"]:
		idle_feet.append(skeleton().get_bone_global_pose(skeleton().find_bone("DEF-foot." + side)))
	for kind in ["attack", "attack_thrust"]:
		visual()._attack_clip_kind = kind
		for time in [0.0, visual()._length("attack")]:
			visual()._sample("attack", time)
			for i in 2:
				var actual := skeleton().get_bone_global_pose(skeleton().find_bone("DEF-foot." + ["L", "R"][i]))
				check(actual.is_equal_approx(idle_feet[i]), "attack endpoints restore the actual imported foot transform")
	# A target that leaves range during windup is still a whiff for either motion.
	for kind in ["attack", "attack_thrust"]:
		await fresh()
		force_variant(kind)
		var before: float = arena.enemies.target.hp
		arena.request_slot("lmb", {"enemy_id": "target"})
		arena.enemies.target.body.position = Vector3(12, 0, 0)
		await step(90)
		check(arena.enemies.target.hp == before, "no extra reach from the visual step: " + kind)
	finish()

func finish() -> void:
	var file := FileAccess.open(report_dir.path_join("variant_validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"cases": variant_cases, "observations": observations, "captures": captured}, "  "))
	print("MOTION_VARIANTS_V18_COMPLETE ", checks.size(), " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
