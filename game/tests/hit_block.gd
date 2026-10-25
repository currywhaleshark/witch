extends SceneTree
## Hit recovery cancels actions; a deployed shield blocks by level and dexterity without interrupting.
# A hit big enough to stun with the trial threshold (10% of max HP).
const HEAVY = 15.0
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
	arena.config.mana_regen = 0
	arena.config.hit_recovery_score = 0
	arena.config.shield_level = 1
	arena.config.dexterity = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("target", Vector3(2, 0, 0), true)
	arena.enemies.target.cooldown = 999
	arena.rules.skills.shield.block_base = 0.2
	arena.rules.skills.shield.block_cap = 0.75
	await step(2)

func force_block(always: bool) -> void:
	# Pin the roll outcome; the chance formula is checked separately.
	arena.rules.skills.shield.block_base = 1.0 if always else -10.0
	arena.rules.skills.shield.block_cap = 1.0 if always else 0.75

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)

	await fresh()
	check(arena.state.bindings.r == "shield" and arena.rules.skills.shield.get("while_moving", false), "R deploys the shield as a move-cast skill")
	arena.request_slot("lmb", {"enemy_id": "target"})
	var light: float = arena.config.max_hp * arena.config.hit_stun_min_ratio - 1
	arena.damage_player(light)
	check(arena.hp == arena.config.max_hp - light and arena.stun_time == 0 and not arena.windup.is_empty(), "a hit below the stun threshold hurts without interrupting")
	await fresh()
	var full: float = arena.enemies.target.hp
	arena.request_slot("lmb", {"enemy_id": "target"})
	check(not arena.windup.is_empty(), "attack windup starts")
	arena.damage_player(HEAVY)
	check(arena.windup.is_empty() and arena.stun_time > 0 and is_equal_approx(arena.action_time, arena.stun_time), "an unblocked heavy hit cancels the windup with hit recovery")
	await step(int(arena.attack_seconds() * 60) + 5)
	check(arena.enemies.target.hp == full, "the cancelled attack never lands")

	await fresh()
	var mp: float = arena.state.mana
	arena.request_slot("rmb", {"ground": [4, 0, 0]})
	arena.damage_player(HEAVY)
	await step(30)
	check(arena.state.mana == mp and not arena.state.cooldowns.has("shotgun"), "a cancelled cast spends no mana or cooldown")

	await fresh()
	arena.request_slot("lmb", {"ground": [-6, 0, 0]})
	await step(5)
	var hit_at: Vector3 = arena.player.position
	arena.damage_player(HEAVY)
	await step(int(arena.hit_recovery_seconds() * 60) + 10)
	check(arena.player.position.distance_to(hit_at) < 0.01 and not arena.moving, "hit recovery cancels click movement")

	await fresh()
	arena.move_hold = {"button": MOUSE_BUTTON_LEFT}
	arena.pointer = arena.camera.unproject_position(Vector3(-6, 0, 0))
	await step(5)
	hit_at = arena.player.position
	arena.damage_player(HEAVY)
	await step(int(arena.hit_recovery_seconds() * 60) - 3)
	check(arena.player.position.distance_to(hit_at) < 0.01, "the witch stands still during hit recovery")
	await step(10)
	check(arena.player.position.distance_to(hit_at) > 0.2, "a held move resumes after hit recovery")
	arena.move_hold = {}

	await fresh()
	var slow_recovery: float = arena.hit_recovery_seconds()
	arena.config.attack_speed_score = 40
	arena.config.cast_speed_score = 40
	check(is_equal_approx(arena.hit_recovery_seconds(), slow_recovery), "attack and cast speed leave hit recovery alone")
	arena.config.hit_recovery_score = 40
	check(arena.hit_recovery_seconds() < slow_recovery and arena.hit_recovery_seconds() > arena.config.min_hit_recovery_seconds, "hit recovery speed shortens the stun above its floor")
	arena.config.attack_speed_score = 0
	arena.config.cast_speed_score = 0

	await fresh()
	var base: float = arena.block_chance()
	arena.config.shield_level = 5
	var levelled: float = arena.block_chance()
	arena.config.dexterity = 50
	var dexterous: float = arena.block_chance()
	check(levelled > base and dexterous > levelled, "block chance grows with shield level and dexterity")
	arena.config.shield_level = 10
	arena.config.dexterity = 100
	check(is_equal_approx(arena.block_chance(), arena.rules.skills.shield.block_cap), "block chance stops at its cap")

	await fresh()
	mp = arena.state.mana
	force_block(true)
	arena.damage_player(HEAVY)
	check(arena.hp < arena.config.max_hp, "nothing is blocked before the shield is raised")
	arena.stun_time = 0
	arena.action_time = 0
	arena.request_slot("r", {})
	check(arena.shield_time > 0 and arena.state.mana == mp - arena.rules.skills.shield.mana_cost and arena.state.cooldowns.has("shield") and arena.action_time == 0, "raising the shield is instant and spends its cost")
	var hp: float = arena.hp
	full = arena.enemies.target.hp
	arena.request_slot("lmb", {"enemy_id": "target"})
	arena.damage_player(HEAVY)
	check(arena.hp == hp and arena.stun_time == 0 and not arena.windup.is_empty(), "a blocked hit deals nothing and keeps the windup")
	await step(int(arena.attack_seconds() * 60))
	check(arena.enemies.target.hp < full, "the attack lands through a blocked hit")
	force_block(false)
	arena.damage_player(HEAVY)
	check(arena.hp < hp and arena.stun_time > 0, "a failed block still stuns while the shield is up")
	force_block(true)
	await step(int(arena.rules.skills.shield.duration_seconds * 60) + 2)
	hp = arena.hp
	arena.damage_player(HEAVY)
	check(arena.shield_time == 0 and arena.hp < hp, "the shield drops after its duration")

	await fresh()
	arena.enemies.target.body.position = Vector3(1, 0, 0)
	arena.enemies.target.cooldown = 0
	arena.request_slot("lmb", {"enemy_id": "target"})
	for i in 120:
		if arena.hp < arena.config.max_hp:
			break
		await step()
	check(arena.hp < arena.config.max_hp and arena.stun_time > 0, "an enemy swing triggers hit recovery in play")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_hit_block_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
