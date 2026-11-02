extends SceneTree
## Firearm tree, single-shot line (03 §3): the matchlock assembles a gun that floats beside the
## witch and turns her basic attack into shots until it is dismissed. Empty rounds load back one at
## a time for their mana; the reload mechanism passive adds rounds, loads faster and speeds up turrets.
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

func fresh(enemy: Vector3 = Vector3(0, 0, 6)) -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.config.mana_regen = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("t0", enemy, false, "normal", "brute")
	arena.enemies.t0.cooldown = 999
	arena.enemies.t0.charge_cooldown = 999
	# Tough enough to outlast every shot here: a dead last enemy clears the field and stops the clock.
	arena.enemies.t0.max_hp = 99999.0
	arena.enemies.t0.hp = 99999.0
	arena.bind_slot("q", "matchlock")
	arena.bind_slot("w", "bolt_cutter")
	await step(2)

func settle(seconds: float = 1.0) -> void:
	await step(int(60 * seconds))

func shoot() -> void:
	arena.request_slot("lmb", {"enemy_id": "t0"})
	await settle(1.2)

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	var gun: Dictionary = arena.rules.skills.matchlock
	var reload: Dictionary = arena.config.passives.reload
	var magazine: int = int(gun.magazine)

	await fresh()
	var mana: float = arena.state.mana
	arena.request_slot("q", {"ground": [0, 0, 6]})
	check(arena.gun.is_empty() and arena.action_time > 0 and is_instance_valid(arena.gun_assembly), "the matchlock assembles during a short stationary cast")
	await settle(0.8)
	check(arena.gun.get("id") == "matchlock" and arena.gun.ammo == magazine, "the assembled gun floats beside her, fully loaded")
	check(is_equal_approx(mana - arena.state.mana, magazine * float(gun.round_cost)), "assembling it costs a full magazine at the per-round price")
	check(is_instance_valid(arena.gun.visual) and arena.gun.visual.mode == "ready" and arena.gun.visual.global_position.distance_to(arena.player.position + Vector3.UP * 1.3) < 0.8, "its model hovers at her shoulder")
	check(is_equal_approx(arena.rules.skills.basic_attack.range, float(gun.range)), "while it is out the basic attack reaches the gun's range")

	var hp: float = arena.enemies.t0.hp
	var start: Vector3 = arena.player.position
	# No mana holds the reload, so each click's round stays spent.
	arena.state.mana = 0.0
	arena.request_slot("lmb", {"enemy_id": "t0"})
	check(is_equal_approx(float(arena.windup.release), arena.attack_seconds("matchlock") * float(gun.shot_release_ratio)) and float(arena.windup.release) < 0.75 * 0.5, "the shot fires earlier in its motion than a staff swing would")
	await settle(1.2)
	check(arena.gun.ammo == magazine - 1 and arena.last_shot.get("target") == "t0", "a left click on an enemy fires one round at it")
	check(is_equal_approx(hp - arena.enemies.t0.hp, float(gun.shot_damage)), "the shot deals the gun's damage")
	check(arena.player.position.distance_to(start) < 0.05 and arena.state.mana == 0.0, "she shoots from where she stands (6m), and the shot itself costs no mana")
	check(arena.player_visual._motion_kind != "attack", "shooting plays the pointing cast, not a staff swing")
	check(is_equal_approx(arena.attack_seconds("matchlock"), arena.motion_seconds(float(gun.attack_seconds), arena.config.min_attack_seconds, arena.config.attack_speed_k, arena.config.attack_speed_score)), "shot pacing follows attack speed")

	for i in magazine - 1:
		await shoot()
	check(arena.gun.ammo == 0, "every click spends a round until the magazine is empty")
	hp = arena.enemies.t0.hp
	arena.request_slot("lmb", {"enemy_id": "t0"})
	check(arena.action_time <= 0 and arena.message == "탄이 없습니다", "an empty gun cannot attack and says it is out of rounds")
	await settle(0.5)
	check(is_equal_approx(hp, arena.enemies.t0.hp) and arena.gun.get("id") == "matchlock", "the empty gun stays out and nothing is struck")
	await settle(12.0)
	check(arena.gun.get("id") == "matchlock" and arena.gun.ammo == 0, "an unused gun never disappears, and without mana no round loads")

	arena.state.mana = arena.state.max_mana
	mana = arena.state.mana
	await step()
	check(arena.gun.ammo == 1 and is_equal_approx(mana - arena.state.mana, float(gun.round_cost)), "the round that waited for mana loads as soon as it can be paid for")
	await settle(float(gun.reload_seconds) - 0.1)
	check(arena.gun.ammo == 1, "the next round takes the reload interval")
	await settle(0.2)
	check(arena.gun.ammo == 2 and is_equal_approx(mana - arena.state.mana, 2 * float(gun.round_cost)), "and pays its own price")
	await settle(float(gun.reload_seconds) * (magazine - 2))
	check(arena.gun.ammo == magazine and is_equal_approx(mana - arena.state.mana, magazine * float(gun.round_cost)), "rounds keep loading one at a time until the magazine is full")
	mana = arena.state.mana
	await settle(3.0)
	check(is_equal_approx(mana, arena.state.mana), "a full magazine spends nothing")
	arena.state.mana = float(gun.round_cost) * 1.5
	await shoot()
	await shoot()
	await settle(float(gun.reload_seconds) * 2.5)
	check(arena.gun.ammo == magazine - 1 and arena.state.mana < float(gun.round_cost), "short of mana, only the rounds it can pay for load")
	arena.state.mana = arena.state.max_mana
	check(not arena.rules.skills.has("reload") and arena.build.passives.has("reload"), "the reload mechanism is a passive and takes no skill slot")

	arena.request_slot("q", {"ground": [0, 0, 6]})
	await settle(0.2)
	check(arena.gun.is_empty() and is_equal_approx(arena.rules.skills.basic_attack.range, arena.basic_range), "pressing the matchlock again takes the gun apart and the staff returns")
	await settle(0.4)

	arena.request_slot("w", {"ground": [0, 0, 6]})
	await settle(0.2)
	check(arena.state.active_tool == "bolt_cutter", "a tool can be switched on")
	arena.request_slot("q", {"ground": [0, 0, 6]})
	await settle(0.8)
	check(arena.gun.get("id") == "matchlock" and arena.state.active_tool == null, "assembling a gun puts the tool away")
	arena.request_slot("w", {"ground": [0, 0, 6]})
	await settle(0.2)
	check(arena.state.active_tool == "bolt_cutter" and arena.gun.is_empty(), "switching a tool on takes the gun apart")

	await fresh(Vector3(11.5, 0, 0))
	arena.request_slot("q", {"ground": [0, 0, 6]})
	await settle(0.8)
	arena.state.mana = 0.0
	arena.request_slot("lmb", {"enemy_id": "t0"})
	await settle(0.3)
	check(arena.moving or arena.player.position.x > 0.5, "an enemy beyond the gun's range is approached first")
	await settle(3.0)
	check(arena.gun.ammo == magazine - 1 and arena.player.position.distance_to(arena.enemies.t0.body.position) > float(arena.rules.skills.basic_attack.range) - 1.5, "she stops at gun range and fires")

	await fresh()
	arena.build.set_level(30)
	arena.build.change_skill("reload", 4)
	arena.build.change_skill("matchlock", 2)
	check(arena.gun_magazine("matchlock") == magazine + 4 * int(reload.magazine_per_level), "reload mechanism levels add rounds to the magazine")
	check(is_equal_approx(arena.reload_seconds("matchlock"), float(gun.reload_seconds) * (1.0 - 4 * float(reload.reload_time_cut_per_level))), "and cut the time each round takes to load")
	arena.build.change_skill("reload", 6)
	check(is_equal_approx(arena.reload_seconds("matchlock"), float(gun.reload_seconds) * 0.75), "Lv10 cuts it by a quarter")
	arena.build.change_skill("reload", -6)
	check(is_equal_approx(arena.rules.skills.matchlock.mana_cost, arena.gun_magazine("matchlock") * float(gun.round_cost)), "the gun's cost follows its magazine")
	check(is_equal_approx(arena.turret_fire_rate(), 1.0 + 4 * float(reload.turret_rate_per_level)), "the reload mechanism also speeds up turret fire")
	check(is_equal_approx(arena.skill_level_factor("matchlock"), 1.0 + 2 * float(arena.items.data.skill_level_damage.matchlock)), "matchlock levels raise its damage")
	arena.request_slot("q", {"ground": [0, 0, 6]})
	await settle(0.8)
	hp = arena.enemies.t0.hp
	arena.state.mana = 0.0
	await shoot()
	check(arena.gun.ammo == arena.gun_magazine("matchlock") - 1 and absf((hp - arena.enemies.t0.hp) - float(gun.shot_damage) * arena.skill_level_factor("matchlock") * arena.build.power_factor() * arena.passive_factor("matchlock")) < 0.01, "a levelled gun holds more rounds and hits harder")
	arena.build.change_skill("reload", -4)
	check(arena.gun.ammo <= arena.gun_magazine("matchlock"), "lowering the reload level trims rounds over the smaller magazine")
	arena.reset_arena()
	check(arena.gun.is_empty() and arena.world.get_children().all(func(child): return child.name != "FloatingGun" or child.is_queued_for_deletion()), "a restart clears the gun")
	arena.build.set_level(1)

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
