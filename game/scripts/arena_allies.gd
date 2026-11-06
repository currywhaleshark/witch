extends RefCounted
## Summoned allies (03 §5.5-§5.9): automatons and turrets (batch2 summons live in batch2_summons.gd),
## follow slots and spacing, growth/lifetime/mana factors, targeting and aggro, damage to allies,
## expiry and self-destruct, chain cuts and spare-part refunds. The allies list stays on the arena.
## Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func sync_automaton_cost() -> void:
	# A node may override the skill's own cost: no node is the cheap one to summon in numbers,
	# A comes back quickly enough to throw as the main bomb, B pays the full price.
	var node: Dictionary = arena.config.automaton_nodes[arena.config.automaton_node]
	arena.rules.skills.automaton.cooldown_seconds = float(node.get("cooldown_seconds", arena.automaton_cost.cooldown_seconds))
	# Mana cost cuts (the 「샤」 piece on accessories, 「록샤」) trim every skill, at most by half.
	var cut: float = clampf(arena.gear_total("mana_cost_pct") / 100.0, 0.0, 0.5)
	for id in arena.base_mana_costs:
		var cost: float = float(node.get("mana_cost", arena.automaton_cost.mana_cost)) if id == "automaton" else float(arena.base_mana_costs[id])
		# Power management trims what the summons cost to build.
		if id == "giant":
			cost = float(arena.batch2.plan("giant").get("mana_cost", cost))
		arena.rules.skills[id].mana_cost = cost * (1.0 - cut) * (summon_mana_factor() if id in Arena.SUMMON_SKILLS else 1.0)
	# The giant's multiple-units node comes back sooner than the single big one.
	arena.rules.skills.giant.cooldown_seconds = float(arena.batch2.plan("giant").get("cooldown_seconds", arena.giant_cooldown))
	# A gun is assembled loaded: its cost is a full magazine at its per-round price.
	for id in Arena.GUNS:
		arena.rules.skills[id].mana_cost = arena.gun_magazine(id) * arena.round_cost(id)
	# Recoil control steadies the shotgun's repeat as it does every gun's.
	arena.rules.skills.shotgun.cooldown_seconds = arena.shotgun_cooldown * arena.fire_interval_factor()
	arena.sync_gun()

func summon_life_factor() -> float:
	# Power management (automation passive): summons and turrets run longer on one winding...
	return 1.0 + float(arena.config.passives.power_management.summon_life_per_level) * arena.passive_level("power_management")

func summon_mana_factor() -> float:
	# ...cost less mana to build...
	return maxf(0.1, 1.0 - float(arena.config.passives.power_management.summon_mana_cut_per_level) * arena.passive_level("power_management"))

func turret_plan() -> Dictionary:
	return arena.rules.skills.turret.nodes[arena.config.turret_node]

func detection_range(ally: Dictionary) -> float:
	# How far a summon looks for enemies: the turret node widens or narrows it, target judgement
	# (automation passive) widens both.
	var reach: float = float(arena.config.summon_detection_range) if ally.mobile else float(arena.config.turret_detection_range) * float(turret_plan().get("detection_factor", 1.0))
	if ally.get("summon", "") in Arena.Batch2Summons.SKILLS:
		reach = arena.batch2.detection(ally)
	return reach * (1.0 + float(arena.config.passives.target_judgement.detection_per_level) * arena.passive_level("target_judgement"))

func relay_factor(ally: Dictionary) -> float:
	# Target judgement: hits on the enemy the relay pointed them at land harder.
	if ally.target == "" or ally.target != ally.get("relayed", ""):
		return 1.0
	return 1.0 + float(arena.config.passives.target_judgement.relay_damage_per_level) * arena.passive_level("target_judgement")

func toughest_enemy(ally: Dictionary) -> String:
	# The precise turret picks the enemy with the most health it can see, nearer first on a tie.
	var best := ""
	var most := -1.0
	var near := INF
	for id in arena.enemies:
		if not arena.eligible(ally, id):
			continue
		var tough: float = float(arena.enemies[id].max_hp)
		var gap: float = ally.node.position.distance_to(arena.enemies[id].body.position)
		if tough > most + 0.001 or (absf(tough - most) <= 0.001 and gap < near):
			best = id
			most = tough
			near = gap
	return best

func spare_parts_refund(ally: Dictionary) -> void:
	# Spare parts (automation passive): a summon broken by enemies hands back part of its mana and
	# cuts what is left of its skill's cooldown, so it can be put back sooner.
	var level: float = arena.passive_level("spare_parts")
	if level <= 0:
		return
	var plan: Dictionary = arena.config.passives.spare_parts
	var skill: String = ally_skill(ally)
	var refund: float = float(arena.rules.skills[skill].mana_cost) * float(plan.mana_refund_per_level) * level
	arena.state.mana = minf(arena.state.max_mana, arena.state.mana + refund)
	if arena.state.cooldowns.has(skill):
		arena.state.cooldowns[skill] = float(arena.state.cooldowns[skill]) * maxf(0.0, 1.0 - float(plan.cooldown_cut_per_level) * level)
	arena.last_spare_refund = {"skill": skill, "mana": refund}

func ally_skill(ally: Dictionary) -> String:
	# The skill that built a summon: batch 2 summons say so, the rest are automatons or turrets.
	return String(ally.get("summon", "automaton" if ally.mobile else "turret"))

func turret_fire_rate() -> float:
	# The reload mechanism's feed also speeds up the turret, which feeds rounds the same way (03 §2.1).
	return 1.0 + float(arena.config.passives.reload.turret_rate_per_level) * arena.reload_level()

func automaton_spawn_position(slot: int = 0) -> Vector3:
	# Casting and idle following share these anchors to avoid a step on release. Each automaton
	# keeps its own place beside the witch (slot 0 is the original anchor); casts ask for a free one.
	var pos: Vector3 = arena.player.position + Arena.FOLLOW_SLOTS[slot % Arena.FOLLOW_SLOTS.size()]
	pos.x = clampf(pos.x, arena.map.bounds.position.x + 0.25, arena.map.bounds.end.x - 0.25)
	pos.z = clampf(pos.z, arena.map.bounds.position.y + 0.25, arena.map.bounds.end.y - 0.25)
	return arena.map.snap(pos) if not arena.map.walkable(pos) else pos

func free_follow_slot() -> int:
	var taken: Array = arena.allies.filter(func(other): return other.mobile).map(func(other): return other.slot)
	for slot in Arena.FOLLOW_SLOTS.size():
		if slot not in taken:
			return slot
	return taken.size() % Arena.FOLLOW_SLOTS.size()

func face_travel(ally: Dictionary, before: Vector3, dt: float) -> void:
	# A following automaton turns towards where it walks; pursuit aims at its target instead.
	var travel: Vector3 = ally.node.position - before
	travel.y = 0.0
	if travel.length() < 0.001:
		return
	var yaw := atan2(-travel.x, -travel.z)
	ally.node.rotation = Vector3(0, lerp_angle(ally.node.rotation.y, yaw, minf(1.0, dt * 12.0)), 0)

func separate_allies(dt: float) -> void:
	# Automatons ease apart instead of standing inside each other or a turret; turrets stay put.
	for i in arena.allies.size():
		for j in range(i + 1, arena.allies.size()):
			var a: Dictionary = arena.allies[i]
			var b: Dictionary = arena.allies[j]
			if not a.mobile and not b.mobile:
				continue
			var gap := Vector3(b.node.position.x - a.node.position.x, 0, b.node.position.z - a.node.position.z)
			# Batch 2 summons carry their own footprint (the giant stands 0.9m wide).
			var spacing: float = maxf(Arena.ALLY_SPACING, float(a.get("radius", Arena.ALLY_SPACING / 2)) + float(b.get("radius", Arena.ALLY_SPACING / 2)))
			var overlap: float = spacing - gap.length()
			if overlap <= 0.0:
				continue
			var away: Vector3 = gap.normalized() if gap.length() > 0.001 else Vector3.RIGHT.rotated(Vector3.UP, j * 2.4)
			var share := 0.5 if a.mobile and b.mobile else 1.0
			var push: Vector3 = away * minf(overlap * share, dt * 2.0)
			if a.mobile and arena.map.walkable(a.node.position - push):
				a.node.position -= push
			if b.mobile and arena.map.walkable(b.node.position + push):
				b.node.position += push

func summon_growth(kind: String, roller: String) -> float:
	# Summons grow with their own skill level (blueprints included), not with the witch's power
	# or damage gear (07 §2.1), so a level 30 build's summons can stand against level 30 enemies.
	# Summon options on gear (summon damage / summon life +%) keep late summons in step with gear.
	return (1.0 + float(arena.config["summon_%s_per_level" % kind]) * (float(arena.config[roller + "_level"]) - 1.0)) * (1.0 + arena.gear_total("summon_%s_pct" % kind) / 100.0)

func summon_level(roller: String) -> int:
	return int(arena.config[roller + "_level"])

func spawn_ally(pos: Vector3, mobile: bool, target_id) -> void:
	var node = Node3D.new()
	arena.world.add_child(node)
	node.position = arena.map.grounded(pos)
	Arena.ActorVisual.create(node, "automaton" if mobile else "turret", str(arena.config.automaton_node) if mobile else "base", float(arena.config.summon_lifetime) * summon_life_factor())
	var durability: float = (arena.config.automaton_hp if mobile else arena.config.turret_hp) * summon_growth("hp", "automaton" if mobile else "turret")
	# The automaton keeps the node it was summoned with; B never times out but only so many stay.
	# Taken before an old B steps aside, so the new one keeps the place it was assembled at.
	var slot := free_follow_slot() if mobile else -1
	var kind: String = arena.config.automaton_node if mobile else ""
	var life: float = (arena.config.summon_lifetime if mobile else arena.config.turret_lifetime) * summon_life_factor()
	if kind == "B":
		# The lasting B automaton is a tank: a little harder hitting and sturdier.
		life = INF
		durability *= float(arena.config.automaton_nodes.B.hp_factor)
		var kept: Array = arena.allies.filter(func(other): return other.node_kind == "B")
		if kept.size() >= int(arena.config.automaton_nodes.B.max_count):
			dismantle_ally(kept[0])
	arena.allies.append({"id": "ally_%d" % arena.ally_serial, "node": node, "mobile": mobile, "node_kind": kind, "route": {}, "target": target_id if target_id != null else "", "cooldown": 0.2,
		"life": life, "hp": durability, "max_hp": durability, "reach": 1.6, "slot": slot})
	arena.ally_serial += 1
	arena.spawn_vfx().summon_arrive(node.position, Arena.TEAL, arena.map.ground_y(node.position))
	arena.play_sfx("summon_arrive", 1.8)

func automaton_reach(id: String) -> float:
	# Automatons stop at arm's length from the target's body, so small foes get punched rather than
	# stared at from 1.6m. The boss keeps the old distance: its body is a whole door frame.
	var enemy: Dictionary = arena.enemies[id]
	return 1.6 if enemy.kind == "latch" else 0.45 + 0.5 * float(enemy.size)

func dismantle_ally(ally: Dictionary) -> void:
	# The oldest B automaton makes room for a new one: it breaks apart with no blast.
	var art: Node = ally.node.get_node_or_null("ActorVisual")
	if art != null:
		art.detach_for_death(arena.world, arena)
	arena.spawn_vfx().shutdown(ally.node.position, arena.map.ground_y(ally.node.position))
	ally.node.queue_free()
	arena.allies.erase(ally)

func chain_cut(first: String, damage: float, skip: Array = [], label: String = "") -> void:
	# Unique 집행자의 도르래: a landed bolt cutter hit (basic, focus or area attack) drags the
	# nearest other enemy in. Enemies in `skip` were already cut by the same swing.
	if not arena.enemies.has(first):
		return
	var rule: Dictionary = arena.items.data.rule_values
	var origin: Vector3 = arena.enemies[first].body.position
	var second := ""
	var best := float(rule.chain_cut_range)
	for id in arena.enemies:
		var gap: float = arena.enemies[id].body.position.distance_to(origin)
		if id != first and id not in skip and gap <= best:
			best = gap
			second = id
	if second != "":
		arena.strike(second, damage * float(rule.chain_cut_factor), true, "witch", "bolt_cutter", "", label)

func expire_ally(ally: Dictionary) -> void:
	# End of life: automatons self-destruct, turrets just shut down. An A automaton also lands
	# here the moment it reaches its target, trading its repeated attacks for a bigger blast.
	if ally.mobile:
		var damage: float = arena.config.shot_damage * (float(arena.config.automaton_nodes.A.blast_factor) if ally.node_kind == "A" else 1.0) * summon_growth("damage", "automaton")
		for id in arena.enemies.keys():
			if arena.enemies.has(id) and ally.node.position.distance_to(arena.enemies[id].body.position) < arena.config.summon_explosion_range:
				arena.strike(id, damage, false, "automaton", "automaton_blast")
		arena.spawn_vfx().blast(ally.node.position, float(arena.config.summon_explosion_range), arena.map.ground_y(ally.node.position), ally.node_kind == "A")
		arena.shake_time = maxf(arena.shake_time, 0.14 if ally.node_kind == "A" else 0.1)
	else:
		arena.spawn_vfx().shutdown(ally.node.position, arena.map.ground_y(ally.node.position))
	var art: Node = ally.node.get_node_or_null("ActorVisual")
	if art != null:
		art.detach_for_death(arena.world, arena, ally.mobile)
	if ally.mobile:
		arena.play_sfx("automaton_explode", 0.65)
	else:
		arena.play_cue(1.15)
	var spot: Vector3 = ally.node.position
	ally.node.queue_free()
	arena.allies.erase(ally)
	# Unique 자기복제 태엽: a self-destructing automaton leaves one replica with half the life;
	# replicas never copy themselves again.
	if ally.mobile and arena.gear_total("rule:self_replicate") > 0 and not ally.get("replica", false):
		spawn_ally(spot, true, "")
		var replica: Dictionary = arena.allies[-1]
		replica.replica = true
		replica.life *= float(arena.items.data.rule_values.replica_life_factor)

func ally_by_id(id: String) -> Dictionary:
	for ally in arena.allies:
		if ally.id == id:
			return ally
	return {}

func foe_position(target: String) -> Vector3:
	# "" is the witch; anything else is a summon or turret id.
	var ally: Dictionary = ally_by_id(target)
	return arena.player.position if ally.is_empty() else ally.node.position

func aggro_distance(enemy: Dictionary, target: String) -> float:
	# The witch counts a little closer than she is, so summons don't soak every hit.
	if target == "":
		# Smoke hides her altogether: summons in sight draw the enemy instead.
		return INF if arena.hp <= 0 or arena.blinded(enemy) else enemy.body.position.distance_to(arena.player.position) - arena.config.aggro_witch_bias
	var ally: Dictionary = ally_by_id(target)
	if ally.is_empty():
		return INF
	# A lure beacon's signal turns the enemies it reached on it for as long as it stands; the giant
	# counts closer than it is so it draws enemies off the witch (03 §5.9).
	if arena.batch2.lured_to(enemy, ally):
		return -1000.0
	var bias: float = float(arena.rules.skills.giant.aggro_bias) if ally.get("summon", "") == "giant" else 0.0
	return enemy.body.position.distance_to(ally.node.position) - bias

func nearest_foe(enemy: Dictionary) -> String:
	# Aggro goes to whatever is closest, so summons and turrets can draw enemies off the witch.
	var best = ""
	var best_distance: float = aggro_distance(enemy, "")
	for ally in arena.allies:
		var d: float = aggro_distance(enemy, ally.id)
		if d < best_distance:
			best_distance = d
			best = ally.id
	# Sticky target: switch only when the new one is clearly closer, so an enemy standing
	# between two targets doesn't flip back and forth.
	var current: float = aggro_distance(enemy, enemy.target)
	if best != enemy.target and current < INF and best_distance > current - arena.config.aggro_switch_margin:
		return enemy.target
	return best

func hit_foe(target: String, amount: float, grade: String) -> void:
	var ally: Dictionary = ally_by_id(target)
	if ally.is_empty():
		arena.damage_player(amount, grade)
	else:
		damage_ally(ally, amount, grade)

func damage_ally(ally: Dictionary, amount: float, grade: String) -> void:
	amount *= arena.spread_factor(float(arena.config.build.enemy_spread)) * (1.0 - arena.summon_guard())
	ally.hp -= amount
	ally.hurt = 0.25
	arena.probe.ally_hit(grade, minf(amount, maxf(ally.hp + amount, 0.0)), ally.hp <= 0)
	var floor_y: float = arena.map.ground_y(ally.node.position)
	arena.spawn_vfx().summon_hit(ally.node.position + Vector3.UP * 0.6 + arena.camera.global_basis.z * 0.4, floor_y)
	if ally.hp <= 0:
		# Destroyed summons break apart without the end-of-life self-destruct blast.
		arena.spawn_vfx().summon_break(ally.node.position + Vector3.UP * 0.5, floor_y)
		arena.play_sfx("summon_break", 1.15)
		spare_parts_refund(ally)
		var art: Node = ally.node.get_node_or_null("ActorVisual")
		if art != null:
			art.detach_for_death(arena.world, arena)
		ally.node.queue_free()
		arena.allies.erase(ally)

func foe_in_reach(at: Vector3, reach: float) -> String:
	# First thing within reach of a moving hit (orb or charge): the witch, else the nearest summon.
	var flat: Vector3 = arena.player.position - at
	flat.y = 0
	if arena.hp > 0 and flat.length() < reach:
		return ""
	for ally in arena.allies:
		flat = ally.node.position - at
		flat.y = 0
		if flat.length() < reach:
			return ally.id
	return "none"

func _tick_allies(dt: float) -> void:
	for ally in arena.allies.duplicate():
		ally.life -= dt
		if ally.get("summon", "") in Arena.Batch2Summons.SKILLS:
			if ally.life <= 0:
				arena.batch2.retire(ally)
			else:
				arena.batch2.tick(ally, dt)
			continue
		if ally.life <= 0:
			expire_ally(ally)
			continue
		if ally.mobile and not arena.on_screen(ally.node.position):
			ally.target = ""
			var before: Vector3 = ally.node.position
			ally.node.position = ally.node.position.move_toward(arena.follow(ally.route, ally.node.position, automaton_spawn_position(ally.slot), 0.4, dt), dt * 7)
			face_travel(ally, before, dt)
			continue
		if not arena.eligible(ally, ally.target):
			if not ally.mobile and turret_plan().get("toughest_first", false):
				ally.target = toughest_enemy(ally)
			else:
				ally.target = arena.nearest_enemy(ally.node.position, detection_range(ally), Vector3.ZERO, -1, true, true)
		if ally.target == "":
			if ally.mobile:
				var before: Vector3 = ally.node.position
				ally.node.position = ally.node.position.move_toward(arena.follow(ally.route, ally.node.position, automaton_spawn_position(ally.slot), 0.4, dt), dt * 4)
				face_travel(ally, before, dt)
			continue
		var target: Vector3 = arena.enemies[ally.target].body.position
		ally.node.look_at(target)
		if ally.node_kind == "A" and ally.node.position.distance_to(target) <= 1.8:
			expire_ally(ally)
			continue
		if ally.mobile:
			ally.reach = automaton_reach(ally.target)
		if ally.mobile and ally.node.position.distance_to(target) > ally.reach:
			var speed: float = 4.0 * (float(arena.config.automaton_nodes.A.speed_factor) if ally.node_kind == "A" else 1.0)
			ally.node.position = ally.node.position.move_toward(arena.follow(ally.route, ally.node.position, target, 0.4, dt), dt * speed)
		ally.cooldown -= dt
		if ally.cooldown <= 0 and (not ally.mobile or ally.node.position.distance_to(target) <= ally.reach + 0.2):
			var shot_origin: Vector3 = ally.node.position + Vector3.UP * 0.8
			var art: Node = ally.node.get_node_or_null("ActorVisual")
			if art != null:
				art.preview_shot(ally)
				shot_origin = art.strike_point() if ally.mobile else art.muzzle_position()
			if not ally.mobile:
				arena.spawn_vfx().summon_shot(shot_origin, target + Vector3.UP * 0.8, Color(1.0, 0.78, 0.45), arena.map.ground_y(shot_origin))
			elif ally.node_kind != "B":
				# The automaton lands a lunging piston punch; the B node's saw makes its own sparks.
				arena.spawn_vfx().summon_punch(shot_origin, target - ally.node.position, Arena.TEAL, arena.map.ground_y(shot_origin))
			var saw: bool = ally.mobile and ally.node_kind == "B"
			var damage: float = arena.config.summon_damage * (float(arena.config.automaton_nodes.B.damage_factor) if ally.node_kind == "B" else 1.0)
			damage = (damage if ally.mobile else arena.config.turret_damage) * summon_growth("damage", "automaton" if ally.mobile else "turret")
			var plan: Dictionary = {} if ally.mobile else turret_plan()
			damage *= float(plan.get("damage_factor", 1.0))
			var aimed: String = ally.target
			arena.strike(aimed, damage * relay_factor(ally), true, "automaton" if ally.mobile else "turret", "automaton" if ally.mobile else "turret", "saw" if saw else "")
			if int(plan.get("spread_targets", 0)) > 0:
				turret_spread(ally, aimed, target, damage, shot_origin, plan)
			ally.cooldown = arena.config.summon_attack_cooldown if ally.mobile else arena.config.turret_attack_cooldown / turret_fire_rate() * float(plan.get("interval_factor", 1.0))
	separate_allies(dt)

func turret_spread(ally: Dictionary, aimed: String, at: Vector3, damage: float, origin: Vector3, plan: Dictionary) -> void:
	# The suppressing turret's burst scatters: each shot also strikes a few other enemies near
	# its target, at the node's lowered damage per hit.
	var near: Array = []
	for id in arena.enemies:
		if id != aimed and arena.enemies[id].body.position.distance_to(at) <= float(plan.spread_radius) and arena.eligible(ally, id):
			near.append(id)
	near.sort_custom(func(a, b): return arena.enemies[a].body.position.distance_to(at) < arena.enemies[b].body.position.distance_to(at))
	for id in near.slice(0, int(plan.spread_targets)):
		if arena.enemies.has(id):
			arena.spawn_vfx().summon_shot(origin, arena.enemies[id].body.position + Vector3.UP * 0.8, Color(1.0, 0.78, 0.45), arena.map.ground_y(origin))
			arena.strike(id, damage, true, "turret", "turret")
