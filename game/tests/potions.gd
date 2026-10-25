extends SceneTree
## Potion quickslots: gradual refills, per-group cooldowns, stacks without restock, speed buff.
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
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	arena.spawn_enemy("target", Vector3(8, 0, 8))
	arena.enemies.target.cooldown = 999
	await step(2)

func key(code: int, shift: bool = false) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func potion(index: int) -> Dictionary:
	return arena.config.potions[arena.potion_slots[index].id]

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)

	await fresh()
	check(arena.potion_slots.size() == 4 and arena.potion_slots[0].id == "health_m" and arena.potion_slots[1].id == "mana_m", "four quickslots start with the trial loadout")
	arena.hp = 20.0
	var stock: int = arena.potion_slots[0].count
	key(KEY_1)
	check(arena.hp == 20.0 and arena.potion_slots[0].count == stock - 1, "a health potion is spent but does not heal at once")
	check(is_equal_approx(arena.pending_fill("hp_rate"), potion(0).hp), "the whole refill is pending for the HUD")
	await step(60)
	check(arena.hp > 20.0 and arena.hp < 20.0 + potion(0).hp, "health refills over time")
	await step(int(potion(0).seconds * 60))
	check(is_equal_approx(arena.hp, 20.0 + potion(0).hp), "the full amount arrives by the end")

	await fresh()
	arena.hp = 20.0
	key(KEY_1)
	stock = arena.potion_slots[0].count
	key(KEY_1)
	check(arena.potion_slots[0].count == stock and arena.message == "물약 준비 중입니다", "same group is blocked while on cooldown")
	arena.state.mana = 0.0
	key(KEY_2)
	check(arena.potion_slots[1].count == arena.config.potion_loadout[1].count - 1, "a mana potion is not blocked by the health cooldown")
	stock = arena.potion_slots[2].count
	key(KEY_3)
	check(arena.potion_slots[2].count == stock, "a rejuvenation potion waits for both cooldowns")
	check(potion(0).cooldown_seconds > potion(0).seconds, "cooldown is a little longer than the refill")
	await step(int(potion(0).cooldown_seconds * 60) + 2)
	key(KEY_3)
	check(arena.potion_slots[2].count == stock - 1 and arena.potion_cooldown("health_m") > 0 and arena.potion_cooldown("mana_m") > 0, "rejuvenation starts both health and mana cooldowns")

	await fresh()
	arena.potion_slots[0].count = 1
	arena.hp = 50.0
	key(KEY_1)
	await step(int(potion(0).cooldown_seconds * 60) + 2)
	arena.hp = 50.0
	key(KEY_1)
	check(arena.potion_slots[0].count == 0 and arena.potion_effects.is_empty(), "an empty stack does nothing and is never restocked")

	await fresh()
	arena.state.mana = 0.0
	key(KEY_2, true)
	check(arena.potion_slots[1].id == "mana_l" and arena.potion_slots[1].count == arena.config.potion_test_count, "Shift+number cycles that slot's potion type for testing")
	arena.potion_slots[1].id = "full_mana"
	key(KEY_2)
	await step(int(potion(1).seconds * 60) + 1)
	check(is_equal_approx(arena.state.mana, arena.state.max_mana), "full mana refills to the maximum over its time")

	await fresh()
	arena.request_slot("lmb", {"ground": [-8, 0, 0]})
	await step(30)
	var plain: float = absf(arena.player.position.x)
	await fresh()
	key(KEY_4)
	check(arena.speed_buff > 0 and arena.potion_cooldown("speed") > arena.speed_buff, "the speed potion starts a buff whose cooldown outlasts it")
	arena.request_slot("lmb", {"ground": [-8, 0, 0]})
	await step(30)
	check(absf(arena.player.position.x) > plain * 1.15, "the speed buff makes the witch walk faster")
	await step(int(potion(3).seconds * 60))
	check(arena.speed_buff == 0, "the speed buff wears off")

	await fresh()
	arena.enemies.target.body.position = Vector3(2, 0, 0)
	arena.hp = 40.0
	arena.request_slot("lmb", {"enemy_id": "target"})
	key(KEY_1)
	check(not arena.windup.is_empty() and not arena.potion_effects.is_empty(), "drinking during an attack windup neither waits nor cancels it")
	arena.damage_player(arena.config.max_hp * arena.config.hit_stun_min_ratio + 1)
	arena.state.mana = 0.0
	key(KEY_2)
	check(arena.stun_time > 0 and arena.potion_effects.size() == 2, "potions can be drunk during hit recovery")

	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_potion_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
