extends SceneTree
## Automation tree, second batch (2026-11-06): mechanical hounds (pack / tracker nodes), the lure
## beacon and the giant automaton (single / multiple nodes) on the delivered models. Writes no report.
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

func foe(id: String, at: Vector3, grade: String = "normal", tough: float = 999999.0) -> Dictionary:
	arena.spawn_enemy(id, at, false, grade, "light")
	var enemy: Dictionary = arena.enemies[id]
	enemy.cooldown = 999
	enemy.max_hp = tough
	enemy.hp = tough
	return enemy

func summons(skill: String) -> Array:
	return arena.allies.filter(func(ally): return ally.get("summon", "") == skill)

func cast(skill: String, cursor: Dictionary) -> void:
	# Wait out the previous motion, then full mana and no cooldown, press, and step until the
	# release has turned into allies.
	for i in 120:
		if arena.action_time <= 0 and arena.windup.is_empty():
			break
		await step()
	arena.state.mana = arena.state.max_mana
	arena.state.cooldowns.clear()
	arena.bind_slot("q", skill)
	arena.request_slot("q", cursor)
	check(not arena.windup.is_empty(), "the %s cast starts" % skill)
	for i in 160:
		await step()
		if arena.windup.is_empty():
			break

func art(ally: Dictionary) -> Node:
	return ally.node.get_node_or_null("ActorVisual")

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.force_rolls = {"hit": true, "crit": false}
	await step(2)
	arena.build.set_level(30)
	var build = arena.build
	arena.state.max_mana = 500.0
	await fresh()

	# The three placeholders in the automation tab are now real skills; the giant needs the automaton.
	for id in ["hound", "beacon", "giant"]:
		var node = arena.skill_window.find_node(id)
		check(node != null and arena.skill_window.node_state(node) == "levels", "%s sits in the automation tree" % id)
	check(build.skills.hound == 1 and build.skills.beacon == 1 and build.skills.giant == 0 and build.requires.get("giant") == "automaton", "hound and beacon start at Lv1, the giant unlearned behind the automaton")
	check(arena.skill_window.drag_data("hound", "") != null and arena.skill_window.drag_data("beacon", "") != null and arena.skill_window.drag_data("giant", "") == null, "learned hound and beacon icons drag onto a key; the unlearned giant does not")
	var points: int = build.skill_points()
	check(build.change_skill("giant", 1) and build.skill_points() == points - 1, "learning the giant takes a point")
	check(arena.skill_window.drag_data("giant", "") != null, "after which it drags too")
	arena.skill_window.drop_skill("e", {"skill": "hound", "from": ""})
	check(arena.state.bindings.e == "hound", "a hound icon dropped on E takes that key")

	# Hound: the cast assembles two hounds beside her, which run down the enemy and bite it.
	var hound: Dictionary = arena.rules.skills.hound
	arena.state.mana = arena.state.max_mana
	arena.bind_slot("q", "hound")
	foe("prey", Vector3(0, 0, 7))
	foe("anchor", Vector3(-11, 0, -9))
	arena.request_slot("q", {"enemy_id": "prey", "ground": [0, 0, 7]})
	await step(5)
	var shown: Array = arena.batch2.preview.get("nodes", [])
	check(shown.size() == 2 and shown[0].get_node("ActorVisual").visual_state == "spawn", "two hounds assemble during the cast")
	for i in 60:
		await step()
		if arena.windup.is_empty():
			break
	var pack: Array = summons("hound")
	check(pack.size() == 2 and pack.all(func(ally): return ally.target == "prey"), "the release leaves two hounds set on the enemy")
	check(pack.size() == 2 and art(pack[0]).loaded_ok and art(pack[0]).players.size() == 1 and is_equal_approx(art(pack[0]).variant_scale, 1.0), "on the delivered hound model")
	check(pack.size() == 2 and absf(art(pack[0]).playback_speed(6.5) - 1.1797711686) < 0.0001, "whose gallop plays at 1.18x at 6.5m/s")
	var start: Vector3 = pack[0].node.position
	await step(30)
	check(pack[0].node.position.distance_to(start) > 2.5, "hounds run fast (%.1fm in 0.5s)" % pack[0].node.position.distance_to(start))
	var ran := false
	for i in 60:
		await step()
		ran = ran or art(pack[0]).visual_state == "run"
		if not arena.batch2.last_bite.is_empty():
			break
	check(ran, "playing the gallop as they go")
	var bite_damage: float = float(hound.bite_damage) * arena.summon_growth("damage", "hound")
	check(not arena.batch2.last_bite.is_empty() and is_equal_approx(float(arena.batch2.last_bite.damage), bite_damage), "and bite for %.1f" % bite_damage)
	check(float(arena.enemies.prey.slow) > 0.0, "a bite slows the enemy")
	var counted: int = arena.batch2.bites
	await step(120)
	var bites: int = arena.batch2.bites - counted
	check(bites >= 5 and bites <= 7, "two hounds bite about every %.1fs each (%d bites in 2s)" % [float(hound.bite_seconds), bites])
	check(pack.size() == 2 and ["bite", "idle", "run"].has(art(pack[0]).visual_state), "the visual follows the bite (%s)" % art(pack[0]).visual_state)

	# The cap: four hounds at once, the oldest stepping aside with no blast.
	await cast("hound", {"enemy_id": "prey", "ground": [0, 0, 7]})
	await cast("hound", {"enemy_id": "prey", "ground": [0, 0, 7]})
	check(summons("hound").size() == 4, "no more than %d hounds at once" % int(hound.nodes.base.max_count))
	var hp_before: float = arena.enemies.prey.hp
	var oldest: Dictionary = summons("hound")[0]
	oldest.life = 0.0
	await step()
	check(not arena.allies.has(oldest) and absf(arena.enemies.prey.hp - hp_before) < bite_damage * 2.5, "a hound that runs down just stops, with no self-destruct")

	# Pack node: three smaller hounds a cast, weaker each, spread over different enemies.
	await fresh()
	check(build.set_skill_node("hound", "pack"), "the pack node is one point")
	foe("a", Vector3(-1.2, 0, 5))
	foe("b", Vector3(0, 0, 5.4))
	foe("c", Vector3(1.2, 0, 5))
	foe("anchor", Vector3(-11, 0, -9))
	await cast("hound", {"ground": [0, 0, 3]})
	pack = summons("hound")
	var pack_plan: Dictionary = hound.nodes.pack
	check(pack.size() == 3 and is_equal_approx(art(pack[0]).variant_scale, 0.8), "the pack comes three at a time, at 0.8x")
	check(pack.size() == 3 and is_equal_approx(pack[0].max_hp, float(hound.hp) * float(pack_plan.hp_factor) * arena.summon_growth("hp", "hound")), "each weaker")
	await step(20)
	var targets := {}
	for ally in pack:
		targets[ally.target] = true
	check(targets.size() == 3, "and they split up over different enemies (%s)" % str(targets.keys()))
	await cast("hound", {"ground": [0, 0, 3]})
	await cast("hound", {"ground": [0, 0, 3]})
	check(summons("hound").size() == int(pack_plan.max_count), "up to %d of them" % int(pack_plan.max_count))

	# Tracker node: one armoured hound that goes for the elite before the nearer common enemy.
	await fresh()
	build.set_skill_node("hound", "tracker")
	foe("near", Vector3(0, 0, 3.5))
	foe("elite", Vector3(1, 0, 5.5), "elite")
	foe("anchor", Vector3(-11, 0, -9))
	await cast("hound", {"ground": [0, 0, 2]})
	var tracker: Array = summons("hound")
	check(tracker.size() == 1 and art(tracker[0]).players.size() == 2 and is_equal_approx(art(tracker[0]).variant_scale, 1.2), "the tracker is one armoured hound at 1.2x")
	await step(10)
	check(tracker.size() == 1 and tracker[0].target == "elite", "that hunts the elite first")
	check(arena.skill_window.effect_note("hound").contains("중장 추적기"), "the skill window names the hound node")
	build.set_skill_node("hound", "base")

	# Lure beacon: set on the floor, it rings every second and turns the enemies round it on itself.
	await fresh()
	var beacon: Dictionary = arena.rules.skills.beacon
	foe("lured", Vector3(4, 0, 3))
	foe("far", Vector3(-9, 0, 6))
	foe("anchor", Vector3(-11, 0, -9))
	await step(30)
	check(arena.enemies.lured.target == "", "an enemy goes for her before the beacon stands")
	await cast("beacon", {"ground": [3, 0, 2]})
	var beacons: Array = summons("beacon")
	check(beacons.size() == 1 and Vector2(beacons[0].node.position.x, beacons[0].node.position.z).distance_to(Vector2(3, 2)) < 0.01, "the beacon stands where she placed it")
	await step(3)
	check(beacons.size() == 1 and arena.enemies.lured.target == beacons[0].id and arena.enemies.far.target == "", "its signal turns enemies within %.0fm on it, not the far one" % float(beacon.lure_radius))
	await step(40)
	check(beacons.size() == 1 and arena.enemies.lured.target == beacons[0].id, "and they stay on it")
	check(beacons.size() == 1 and art(beacons[0]).visual_state == "pulse", "the bell keeps ringing (%s)" % art(beacons[0]).visual_state)
	var life: float = float(beacon.lifetime) + float(beacon.lifetime_per_level) * (float(arena.config.beacon_level) - 1.0)
	check(beacons.size() == 1 and absf(float(beacons[0].total_life) - life) < 0.001, "it lasts %.1fs at Lv%d" % [life, int(arena.config.beacon_level)])
	var first: Dictionary = beacons[0]
	await cast("beacon", {"ground": [-2, 0, 2]})
	check(summons("beacon").size() == 1 and summons("beacon")[0] != first, "a new beacon replaces the old one")
	summons("beacon")[0].life = 0.0
	await step(30)
	check(summons("beacon").is_empty() and arena.enemies.lured.target == "", "when it winds down the enemies go back to her")

	# Giant automaton: assembles over the cast, then slams the floor in front of it.
	await fresh()
	var giant: Dictionary = arena.rules.skills.giant
	foe("front", Vector3(2.0, 0, 3.0))
	foe("anchor", Vector3(-11, 0, -9))
	arena.state.mana = arena.state.max_mana
	arena.state.cooldowns.clear()
	arena.bind_slot("q", "giant")
	arena.request_slot("q", {"enemy_id": "front", "ground": [2, 0, 3]})
	await step(30)
	shown = arena.batch2.preview.get("nodes", [])
	check(shown.size() == 1 and shown[0].get_node("ActorVisual").visual_state == "assemble", "the giant assembles during its long cast")
	for i in 120:
		await step()
		if arena.windup.is_empty():
			break
	var giants: Array = summons("giant")
	check(giants.size() == 1 and art(giants[0]).loaded_ok, "and stands on the delivered giant model")
	var slam_damage: float = float(giant.damage) * arena.summon_growth("damage", "giant")
	var spot: Vector3 = arena.enemies.front.body.position
	var slammed := false
	for i in 240:
		await step()
		if not arena.batch2.last_slam.is_empty():
			slammed = true
			break
	check(slammed and arena.batch2.last_slam.struck.size() == 1 and arena.batch2.last_slam.struck[0].id == "front", "it slams the enemy in front")
	check(slammed and is_equal_approx(float(arena.batch2.last_slam.damage), slam_damage), "for %.0f" % slam_damage)
	check(slammed and art(giants[0]).visual_state == "slam" and absf(art(giants[0]).clip_seconds - float(giant.slam_hit_at)) < 0.03, "as the clip's fists land (%.2fs)" % art(giants[0]).clip_seconds)
	await step(15)
	var shoved: float = Vector2(arena.enemies.front.body.position.x - giants[0].node.position.x, arena.enemies.front.body.position.z - giants[0].node.position.z).length() - Vector2(spot.x - giants[0].node.position.x, spot.z - giants[0].node.position.z).length()
	check(shoved > 0.3, "and shoves it away from itself (%.2fm)" % shoved)
	# Its slam covers the front fan only, and it draws enemies a little more than its distance says.
	await fresh()
	foe("ahead", Vector3(0, 0, -1.2))
	foe("behind", Vector3(0, 0, 1.2))
	foe("anchor", Vector3(-11, 0, -9))
	arena.batch2.register("giant", arena.batch2.plan("giant"), giant_node(Vector3.ZERO), 0, "ahead")
	giants = summons("giant")
	giants[0].cooldown = 0.0
	giants[0].node.rotation = Vector3.ZERO
	for i in 120:
		await step()
		if not arena.batch2.last_slam.is_empty():
			break
	var hit_ids: Array = arena.batch2.last_slam.get("struck", []).map(func(row): return row.id)
	check(hit_ids.has("ahead") and not hit_ids.has("behind"), "the slam reaches the front fan, not behind it (%s)" % str(hit_ids))
	arena.player.position = Vector3(3.2, 0, 0)
	var middle: Dictionary = arena.enemies.behind
	check(arena.aggro_distance(middle, giants[0].id) < arena.aggro_distance(middle, "") , "the giant counts %.1fm closer for aggro" % float(giant.aggro_bias))

	# Single node: a bigger armoured giant whose slam also stuns; multiple: up to three cheaper small ones.
	await fresh()
	build.set_skill_node("giant", "single")
	foe("front", Vector3(2.0, 0, 3.0))
	foe("anchor", Vector3(-11, 0, -9))
	await cast("giant", {"enemy_id": "front", "ground": [2, 0, 3]})
	giants = summons("giant")
	check(giants.size() == 1 and art(giants[0]).players.size() == 2 and is_equal_approx(art(giants[0]).variant_scale, 1.1), "the single giant wears its armour at 1.1x")
	arena.batch2.last_slam = {}
	for i in 240:
		await step()
		if not arena.batch2.last_slam.is_empty():
			break
	check(float(arena.enemies.front.get("stun", 0.0)) > 0.0, "and its slam stuns")
	build.set_skill_node("giant", "multi")
	var multi: Dictionary = giant.nodes.multi
	await fresh()
	foe("anchor", Vector3(-11, 0, -9))
	check(is_equal_approx(float(arena.rules.skills.giant.cooldown_seconds), float(multi.cooldown_seconds)) and float(arena.rules.skills.giant.mana_cost) < float(arena.base_mana_costs.giant), "multiple units cost less (%.1f) and come back sooner" % float(arena.rules.skills.giant.mana_cost))
	for k in 4:
		await cast("giant", {"ground": [0, 0, 3]})
	giants = summons("giant")
	check(giants.size() == int(multi.max_count) and giants.all(func(ally): return is_equal_approx(art(ally).variant_scale, 0.75)), "up to three small giants at 0.75x")
	var spots := {}
	for ally in giants:
		spots[ally.giant_slot] = true
	check(spots.size() == 3, "each with its own place beside her")
	build.set_skill_node("giant", "base")

	# Shared automation passives reach the new summons.
	await fresh()
	foe("anchor", Vector3(-11, 0, -9))
	var plain_cost: float = float(arena.rules.skills.hound.mana_cost)
	build.change_skill("power_management", 10)
	check(float(arena.rules.skills.hound.mana_cost) < plain_cost and float(arena.rules.skills.beacon.mana_cost) < float(arena.base_mana_costs.beacon), "power management trims their cost too")
	build.change_skill("power_management", -10)
	build.change_skill("spare_parts", 10)
	await cast("hound", {"ground": [0, 0, 3]})
	arena.state.mana = 10.0
	arena.damage_ally(summons("hound")[0], 1e9, "normal")
	check(arena.last_spare_refund.get("skill") == "hound" and arena.state.mana > 10.0, "spare parts refund a broken hound's own cost")
	build.change_skill("spare_parts", -10)

	# A cancelled cast drops its preview without leaving a summon behind.
	await fresh()
	foe("anchor", Vector3(-11, 0, -9))
	arena.state.mana = arena.state.max_mana
	arena.state.cooldowns.clear()
	arena.bind_slot("q", "giant")
	arena.request_slot("q", {"ground": [0, 0, 3]})
	await step(10)
	# A heavy blow stuns her and breaks the cast.
	arena.damage_player(float(arena.config.max_hp) * 0.4, "normal")
	check(arena.windup.is_empty(), "a heavy hit breaks the giant's cast")
	await step(80)
	check(summons("giant").is_empty() and arena.batch2.preview.is_empty(), "a cancelled giant cast leaves nothing standing")

	build.reset_skills()
	check(arena.config.giant_level == 0 and arena.config.hound_node == "base", "a skill reset takes the giant and nodes back")

	print("AUTOMATION_BATCH2 ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)

func giant_node(at: Vector3) -> Node3D:
	var node := Node3D.new()
	arena.world.add_child(node)
	node.position = at
	load("res://scripts/batch2_visual.gd").create(node, "giant", 1.0, false)
	return node
