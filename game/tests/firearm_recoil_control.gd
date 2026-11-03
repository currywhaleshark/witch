extends SceneTree
## Firearm passive, recoil control (03 §3): each level shortens the interval between shots of every
## firearm (gun shots, the rotary cannon's stream, the shotgun's wait) and speeds up the recoil
## leap and the spring dash jump over the same distance. Writes no report.
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

func fresh() -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("anchor", Vector3(-11, 0, -9))
	arena.enemies.anchor.cooldown = 999
	await step(2)

func leap_frames(slot: String) -> int:
	# Frames from the jump leaving the ground to landing.
	arena.request_slot(slot, {"ground": [0, 0, 5]})
	var frames := 0
	for i in 120:
		await step()
		if not arena.dash.is_empty():
			frames += 1
		elif frames > 0:
			break
	return frames

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await step(2)
	var passive: Dictionary = arena.config.passives.recoil_control
	var build = arena.build
	build.set_level(12)
	build.change_skill("recoil_leap", 1)

	await fresh()
	arena.bind_slot("q", "recoil_leap")
	arena.bind_slot("w", "spring_dash")
	var shot: float = arena.attack_seconds("matchlock")
	var rifle: float = arena.attack_seconds("rifle")
	var stream: float = arena.gatling_interval()
	var wait: float = float(arena.rules.skills.shotgun.cooldown_seconds)
	var staff: float = arena.attack_seconds()
	var leap: int = await leap_frames("q")
	await step(30)
	var dash: int = await leap_frames("w")

	check(build.change_skill("recoil_control", 10), "recoil control takes points like the other passives")
	var cut: float = 1.0 - 10 * float(passive.fire_interval_cut_per_level)
	check(is_equal_approx(arena.attack_seconds("matchlock"), shot * cut) and is_equal_approx(arena.attack_seconds("rifle"), rifle * cut), "gun shots come %d%% sooner" % roundi(100 * (1.0 - cut)))
	check(is_equal_approx(arena.gatling_interval(), stream * cut), "so does the rotary cannon's stream")
	check(is_equal_approx(float(arena.rules.skills.shotgun.cooldown_seconds), wait * cut), "and the shotgun's wait")
	check(is_equal_approx(arena.attack_seconds(), staff), "the staff's own swing is untouched")
	await fresh()
	var faster: int = await leap_frames("q")
	await step(30)
	var faster_dash: int = await leap_frames("w")
	var speed: float = 1.0 + 10 * float(passive.leap_speed_per_level)
	check(faster < leap and absi(faster - roundi(leap / speed)) <= 1, "the recoil leap lands sooner (%d -> %d frames)" % [leap, faster])
	check(faster_dash < dash and absi(faster_dash - roundi(dash / speed)) <= 1, "so does the spring dash (%d -> %d frames)" % [dash, faster_dash])
	build.reset_skills()
	check(is_equal_approx(float(arena.rules.skills.shotgun.cooldown_seconds), wait), "resetting skills restores the shotgun's wait")
	build.set_level(1)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
