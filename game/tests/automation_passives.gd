extends SceneTree
## Automation tree, first batch (2026-11-05): three passives (power management, target judgement,
## spare parts) and the turret's two nodes (suppressing fire / precise aim). Writes no report.
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
	for ally in arena.allies.duplicate():
		ally.node.free()
	arena.allies.clear()
	await step(2)

func foe(id: String, at: Vector3, tough: float = 999999.0) -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", "light")
	var enemy: Dictionary = arena.enemies[id]
	enemy.cooldown = 999
	enemy.max_hp = tough
	enemy.hp = tough
	return enemy

func turret_at(at: Vector3) -> Dictionary:
	arena.spawn_ally(at, false, "")
	return arena.allies[-1]

func first_volley(ids: Array) -> Dictionary:
	# Steps until the turret's first shot lands; returns each enemy's damage taken.
	var before := {}
	for id in ids:
		before[id] = float(arena.enemies[id].hp)
	for i in 40:
		await step()
		for id in ids:
			if float(arena.enemies[id].hp) < before[id]:
				var taken := {}
				for other in ids:
					taken[other] = before[other] - float(arena.enemies[other].hp)
				return taken
	return {}

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	var build = arena.build
	var passives: Dictionary = arena.config.passives
	await fresh()

	# The three passives sit in the automation tab, start at Lv0 and take a point a level.
	for id in ["power_management", "target_judgement", "spare_parts"]:
		var node = arena.skill_window.find_node(id)
		check(node != null and arena.skill_window.node_state(node) == "levels" and build.passives.get(id) == 0, "%s is a Lv0 passive in the tree" % id)
	var points: int = build.skill_points()
	check(build.change_skill("power_management", 10) and build.skill_points() == points - 10, "ten levels cost ten points")

	# Power management Lv10: summons last longer and cost less; the drive tools' upkeep is trimmed.
	var power: Dictionary = passives.power_management
	var base_cost: float = float(arena.base_mana_costs.turret) * (1.0 - clampf(arena.gear_total("mana_cost_pct") / 100.0, 0.0, 0.5))
	check(is_equal_approx(float(arena.rules.skills.turret.mana_cost), base_cost * (1.0 - 10.0 * float(power.summon_mana_cut_per_level))), "the turret costs %d%% less" % roundi(1000 * float(power.summon_mana_cut_per_level)))
	var upkeep: float = float(arena.tool_upkeep.bolt_cutter) * (1.0 - minf(0.9, arena.gear_total("upkeep_pct") / 100.0)) * (1.0 - arena.exo_upkeep_cut())
	check(is_equal_approx(float(arena.rules.skills.bolt_cutter.upkeep_per_second), upkeep * (1.0 - 10.0 * float(power.tool_upkeep_cut_per_level))), "and lends a little to the tools' upkeep")
	var lasting: Dictionary = turret_at(Vector3(0, 0, 2))
	check(is_equal_approx(float(lasting.life), float(arena.config.turret_lifetime) * (1.0 + 10.0 * float(power.summon_life_per_level))), "a turret runs %.1fs instead of %.1fs" % [float(lasting.life), float(arena.config.turret_lifetime)])
	build.change_skill("power_management", -10)
	check(is_equal_approx(float(arena.rules.skills.turret.mana_cost), base_cost), "unlearning it restores the cost")

	# Target judgement Lv10: wider detection, harder hits on the relayed enemy.
	await fresh()
	var judge: Dictionary = passives.target_judgement
	var probe_ally := {"mobile": false}
	var plain_reach: float = arena.detection_range(probe_ally)
	build.change_skill("target_judgement", 10)
	check(is_equal_approx(arena.detection_range(probe_ally), plain_reach * (1.0 + 10.0 * float(judge.detection_per_level))), "detection widens (%.1fm -> %.1fm)" % [plain_reach, arena.detection_range(probe_ally)])
	var gunner: Dictionary = turret_at(Vector3(0, 0, 2))
	var marked: Dictionary = foe("marked", Vector3(0, 0, 5))
	foe("other", Vector3(2.5, 0, 5))
	foe("anchor", Vector3(-11, 0, -9))
	gunner.cooldown = 99.0
	await step(2)
	arena.bind_slot("q", "relay")
	arena.request_slot("q", {"enemy_id": "marked", "ground": [0, 0, 5]})
	await step(3)
	check(gunner.get("relayed") == "marked" and is_equal_approx(arena.relay_factor(gunner), 1.0 + 10.0 * float(judge.relay_damage_per_level)), "the relayed enemy takes +%d%% from summons" % roundi(1000 * float(judge.relay_damage_per_level)))
	gunner.target = "other"
	check(is_equal_approx(arena.relay_factor(gunner), 1.0), "other enemies do not")
	gunner.target = "marked"
	gunner.cooldown = 0.0
	var relayed_hit: Dictionary = await first_volley(["marked"])
	build.change_skill("target_judgement", -10)
	gunner.cooldown = 0.0
	var plain_hit: Dictionary = await first_volley(["marked"])
	check(not relayed_hit.is_empty() and not plain_hit.is_empty() and absf(relayed_hit.marked / plain_hit.marked - (1.0 + 10.0 * float(judge.relay_damage_per_level))) < 0.01, "and the shots really land harder (%.2f vs %.2f)" % [relayed_hit.get("marked", 0.0), plain_hit.get("marked", 0.0)])

	# Spare parts Lv10: a summon broken by enemies refunds mana and cuts its cooldown.
	await fresh()
	var spare: Dictionary = passives.spare_parts
	build.change_skill("spare_parts", 10)
	var broken: Dictionary = turret_at(Vector3(0, 0, 2))
	arena.state.mana = 10.0
	arena.state.cooldowns.turret = 4.0
	arena.damage_ally(broken, 1e9, "normal")
	var refund: float = float(arena.rules.skills.turret.mana_cost) * 10.0 * float(spare.mana_refund_per_level)
	check(not arena.allies.has(broken) and is_equal_approx(arena.state.mana, 10.0 + refund), "a broken turret hands back %.1f mana" % refund)
	check(is_equal_approx(float(arena.state.cooldowns.turret), 4.0 * (1.0 - 10.0 * float(spare.cooldown_cut_per_level))), "and cuts its cooldown to %.2fs" % float(arena.state.cooldowns.turret))
	var spent: Dictionary = turret_at(Vector3(0, 0, 2))
	arena.state.mana = 10.0
	arena.expire_ally(spent)
	check(is_equal_approx(arena.state.mana, 10.0), "a turret that simply runs out refunds nothing")
	build.change_skill("spare_parts", -10)

	# Turret nodes. The base turret fires one shot at the nearest enemy.
	await fresh()
	var ids := ["main", "near1", "near2", "far"]
	var layout := {"main": Vector3(0, 0, 5), "near1": Vector3(1, 0, 5.5), "near2": Vector3(-1, 0, 5.5), "far": Vector3(0, 0, 6.8)}
	for id in ids:
		foe(id, layout[id])
	foe("anchor", Vector3(-11, 0, -9))
	turret_at(Vector3(0, 0, 2))
	var base_hit: Dictionary = await first_volley(ids)
	check(base_hit.get("main", 0.0) > 0.0 and base_hit.near1 == 0.0 and base_hit.near2 == 0.0, "the base turret hits only its target")

	points = build.skill_points()
	check(build.set_skill_node("turret", "suppress") and build.skill_points() == points - 1, "a turret node costs one point")
	var suppress: Dictionary = arena.rules.skills.turret.nodes.suppress
	check(is_equal_approx(arena.detection_range(probe_ally), float(arena.config.turret_detection_range) * float(suppress.detection_factor)), "suppressing fire looks wider")
	await fresh()
	for id in ids:
		foe(id, layout[id])
	foe("anchor", Vector3(-11, 0, -9))
	turret_at(Vector3(0, 0, 2))
	var spread_hit: Dictionary = await first_volley(ids)
	check(absf(spread_hit.get("main", 0.0) / base_hit.main - float(suppress.damage_factor)) < 0.01, "each shot is weaker (x%s)" % str(suppress.damage_factor))
	check(spread_hit.near1 > 0.0 and spread_hit.near2 > 0.0 and is_equal_approx(spread_hit.near1, spread_hit.main), "and also strikes the two nearest enemies round the target")
	check(spread_hit.far == 0.0, "but no more than %d of them" % int(suppress.spread_targets))

	build.set_skill_node("turret", "precise")
	var precise: Dictionary = arena.rules.skills.turret.nodes.precise
	await fresh()
	foe("main", Vector3(0, 0, 3.5))
	foe("tough", Vector3(1, 0, 5.5), 2000000.0)
	foe("anchor", Vector3(-11, 0, -9))
	var aimer: Dictionary = turret_at(Vector3(0, 0, 2))
	var aimed_hit: Dictionary = await first_volley(["main", "tough"])
	check(aimed_hit.get("tough", 0.0) > 0.0 and aimed_hit.main == 0.0, "precise aim picks the toughest enemy over the nearest")
	check(absf(aimed_hit.tough / base_hit.main - float(precise.damage_factor)) < 0.01, "and hits it harder (x%s)" % str(precise.damage_factor))
	var interval: float = float(arena.config.turret_attack_cooldown) / arena.turret_fire_rate() * float(precise.interval_factor)
	check(absf(float(aimer.cooldown) - interval) < 0.03, "at a slower rate (%.2fs)" % float(aimer.cooldown))
	check(arena.detection_range(probe_ally) < float(arena.config.turret_detection_range), "over a narrower watch")
	check(arena.skill_window.effect_note("turret").contains("정밀 조준"), "the skill window names the turret node")

	build.reset_skills()
	check(arena.config.turret_node == "base" and arena.passive_level("spare_parts") == 0, "a skill reset takes the node and passives back")

	print("AUTOMATION_PASSIVES ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
