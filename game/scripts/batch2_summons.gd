extends RefCounted
## Automation tree, second batch (03 §5.9, trial values): mechanical hounds, the lure beacon and
## the giant automaton. They live in the arena's allies list next to automatons and turrets, so
## enemies hit them, aggro, relay, spare parts and the HUD bars all treat them as summons; this
## file owns their own behaviour. Presentation is batch2_visual.gd.
const Batch2Visual = preload("res://scripts/batch2_visual.gd")
const SKILLS = ["hound", "beacon", "giant"]
# Where waiting giants stand beside the witch: far enough out that one 2.8m machine does not
# stand on her, and on the far side from the camera (-Z) so its bulk never hides her.
const GIANT_SLOTS = [Vector3(2.2, 0, -0.6), Vector3(-2.2, 0, -0.6), Vector3(0, 0, -2.4)]
# Who the heavy tracker goes for first (03 §5.9: reinforced, elite and boss before the rest).
const PRIORITY = {"normal": 0, "champion": 1, "elite": 2, "boss": 3}
const AMBER = Color(1.0, 0.74, 0.32)
var arena: Node
# The summons being assembled during the cast: {skill, node_kind, nodes, slots}.
var preview: Dictionary = {}
var last_bite: Dictionary = {}
var bites := 0
var last_slam: Dictionary = {}
var last_pulse: Dictionary = {}

func _init(owner: Node) -> void:
	arena = owner

func node_kind(skill: String) -> String:
	return String(arena.config.get(skill + "_node", "base"))

func plan(skill: String, node: String = "") -> Dictionary:
	# The skill entry with the chosen node's overrides laid over it.
	var entry: Dictionary = arena.rules.skills[skill]
	var merged: Dictionary = entry.duplicate(true)
	merged.erase("nodes")
	var chosen: String = node if node != "" else node_kind(skill)
	if entry.has("nodes"):
		merged.merge(entry.nodes.get(chosen, {}), true)
	merged.node = chosen
	return merged

func of_kind(skill: String) -> Array:
	return arena.allies.filter(func(ally): return ally.get("summon", "") == skill)

# --- casting -----------------------------------------------------------------------------------

func begin_preview(skill: String, cursor: Dictionary) -> void:
	# The summon clip plays at its spot while the cast runs; release turns these into allies.
	cancel_preview("recast")
	var p := plan(skill)
	var slots: Array = []
	var spots: Array = []
	match skill:
		"hound":
			slots = free_follow_slots(int(p.per_cast))
			for slot in slots:
				spots.append(arena.automaton_spawn_position(slot))
		"giant":
			slots = [free_giant_slot()]
			spots.append(giant_anchor(slots[0]))
		"beacon":
			spots.append(arena.point(cursor.ground))
	var nodes: Array = []
	for spot in spots:
		var node := Node3D.new()
		node.add_to_group("cast_assemblies")
		arena.world.add_child(node)
		node.position = arena.map.grounded(spot)
		if skill != "beacon":
			node.look_at(node.position - arena.player_model.global_basis.z, Vector3.UP)
		Batch2Visual.create(node, skill, float(p.get("scale", 1.0)), bool(p.get("armour", false)))
		nodes.append(node)
	preview = {"skill": skill, "node_kind": p.node, "nodes": nodes, "slots": slots}

func sample_preview(progress: float) -> void:
	for node in preview.get("nodes", []):
		if is_instance_valid(node):
			var art = node.get_node_or_null("ActorVisual")
			if art != null:
				art.sample_opening(progress)

func cancel_preview(_reason: String) -> void:
	# A broken cast drops what was already assembled: it falls apart without a blast.
	for node in preview.get("nodes", []):
		if not is_instance_valid(node):
			continue
		var art = node.get_node_or_null("ActorVisual")
		if art != null:
			art.detach_for_death(arena.world, arena)
		node.queue_free()
	preview = {}

func clear() -> void:
	preview = {}
	last_bite = {}
	last_slam = {}
	last_pulse = {}

func summon(event: Dictionary) -> void:
	var skill: String = event.skill
	var p := plan(skill)
	var nodes: Array = []
	var slots: Array = []
	if preview.get("skill", "") == skill and preview.node_kind == p.node:
		nodes = preview.nodes.filter(func(node): return is_instance_valid(node))
		slots = preview.slots
		for node in nodes:
			node.remove_from_group("cast_assemblies")
		preview = {}
	else:
		cancel_preview("node_changed")
	if nodes.is_empty():
		var spots: Array = []
		match skill:
			"hound":
				slots = free_follow_slots(int(p.per_cast))
				for slot in slots:
					spots.append(arena.automaton_spawn_position(slot))
			"giant":
				slots = [free_giant_slot()]
				spots.append(giant_anchor(slots[0]))
			"beacon":
				spots.append(arena.point(event.position))
		for spot in spots:
			var node := Node3D.new()
			arena.world.add_child(node)
			node.position = arena.map.grounded(spot)
			Batch2Visual.create(node, skill, float(p.get("scale", 1.0)), bool(p.get("armour", false)))
			nodes.append(node)
	var target = event.get("target_enemy", "")
	for i in nodes.size():
		var slot: int = int(slots[i]) if i < slots.size() else -1
		register(skill, p, nodes[i], slot, target if target != null else "")
	# Over the limit the oldest steps aside with no blast; a new beacon replaces the old one.
	var limit: int = int(p.get("max_count", 1))
	var kept := of_kind(skill)
	while kept.size() > limit:
		arena.dismantle_ally(kept.pop_front())
	arena.spawn_vfx().summon_arrive(nodes[0].position if not nodes.is_empty() else arena.player.position, arena.TEAL, arena.map.ground_y(arena.player.position))
	arena.play_sfx("summon_arrive", 1.6 if skill == "hound" else (1.2 if skill == "beacon" else 0.8))

func register(skill: String, p: Dictionary, node: Node3D, slot: int, target: String) -> void:
	var scale_factor: float = float(p.get("scale", 1.0))
	var durability: float = float(p.hp) * float(p.get("hp_factor", 1.0)) * arena.summon_growth("hp", skill)
	var life: float = float(p.lifetime)
	if skill == "beacon":
		life += float(p.lifetime_per_level) * (float(arena.config.beacon_level) - 1.0)
	life *= arena.summon_life_factor()
	var ally := {"id": "ally_%d" % arena.ally_serial, "node": node, "mobile": skill != "beacon", "summon": skill, "node_kind": p.node,
		"route": {}, "target": target, "cooldown": 0.15, "life": life, "total_life": life, "hp": durability, "max_hp": durability,
		"reach": 1.0, "slot": slot if skill == "hound" else -1, "giant_slot": slot if skill == "giant" else -1, "scale": scale_factor,
		"radius": {"hound": 0.32, "beacon": 0.45, "giant": 0.9}[skill] * scale_factor,
		"bar_height": {"hound": 0.95, "beacon": 1.75, "giant": 3.2}[skill] * scale_factor,
		"action": "", "action_time": 0.0, "acted": false, "hurt": 0.0, "pulse_clock": 0.0, "pulse_wait": 0.0}
	arena.ally_serial += 1
	arena.allies.append(ally)

func free_follow_slots(count: int) -> Array:
	var taken: Array = arena.allies.filter(func(other): return other.mobile).map(func(other): return other.slot)
	var result: Array = []
	for slot in arena.FOLLOW_SLOTS.size():
		if result.size() >= count:
			break
		if slot not in taken:
			result.append(slot)
	while result.size() < count:
		result.append((taken.size() + result.size()) % arena.FOLLOW_SLOTS.size())
	return result

func free_giant_slot() -> int:
	var taken: Array = of_kind("giant").map(func(other): return other.giant_slot)
	for slot in GIANT_SLOTS.size():
		if slot not in taken:
			return slot
	# Every place is held: the new one takes the oldest's, which is about to step aside.
	return int(taken[0]) if not taken.is_empty() else 0

func giant_anchor(slot: int) -> Vector3:
	var pos: Vector3 = arena.player.position + GIANT_SLOTS[slot % GIANT_SLOTS.size()]
	pos.x = clampf(pos.x, arena.map.bounds.position.x + 0.9, arena.map.bounds.end.x - 0.9)
	pos.z = clampf(pos.z, arena.map.bounds.position.y + 0.9, arena.map.bounds.end.y - 0.9)
	return arena.map.snap(pos) if not arena.map.walkable(pos) else pos

func detection(ally: Dictionary) -> float:
	return float(plan(ally.summon, ally.node_kind).get("detection", 12.0))

# --- behaviour ---------------------------------------------------------------------------------

func retire(ally: Dictionary) -> void:
	# End of life: no self-destruct. Hounds and giants wind down into their part collapse; the
	# beacon folds its legs and goes dark.
	var art = ally.node.get_node_or_null("ActorVisual")
	if art != null:
		art.detach_for_death(arena.world, arena, false, "shutdown" if ally.summon == "beacon" else "death")
	arena.spawn_vfx().shutdown(ally.node.position, arena.map.ground_y(ally.node.position))
	arena.play_cue(1.15)
	ally.node.queue_free()
	arena.allies.erase(ally)

func tick(ally: Dictionary, dt: float) -> void:
	ally.hurt = maxf(0.0, float(ally.hurt) - dt)
	match ally.summon:
		"hound": tick_hound(ally, dt)
		"beacon": tick_beacon(ally, dt)
		"giant": tick_giant(ally, dt)

func go_home(ally: Dictionary, anchor: Vector3, speed: float, dt: float) -> void:
	var before: Vector3 = ally.node.position
	ally.node.position = ally.node.position.move_toward(arena.follow(ally.route, ally.node.position, anchor, 0.4, dt), dt * speed)
	arena.face_travel(ally, before, dt)

func face(ally: Dictionary, at: Vector3, dt: float) -> void:
	var gap: Vector3 = at - ally.node.position
	gap.y = 0.0
	if gap.length() < 0.01:
		return
	ally.node.rotation = Vector3(0, lerp_angle(ally.node.rotation.y, atan2(-gap.x, -gap.z), minf(1.0, dt * 12.0)), 0)

func hound_target(ally: Dictionary, p: Dictionary) -> String:
	# A hound holds the enemy it bit until that enemy dies or gets well out of its reach. The pack
	# spreads over different enemies; the tracker goes for the strongest grades first.
	var held: String = ally.target
	if held != "" and arena.enemies.has(held) and ally.node.position.distance_to(arena.enemies[held].body.position) <= arena.detection_range(ally) * 1.5:
		return held
	var taken: Array = []
	if p.get("split_targets", false):
		taken = of_kind("hound").filter(func(other): return other != ally).map(func(other): return other.target)
	var best := ""
	var best_score := INF
	for id in arena.enemies:
		if not arena.eligible(ally, id):
			continue
		var gap: float = ally.node.position.distance_to(arena.enemies[id].body.position)
		var score: float = gap
		if id in taken:
			score += 100.0
		if p.get("elites_first", false):
			var grade: String = "boss" if arena.config.enemy_types[arena.enemies[id].kind].has("boss") else String(arena.enemies[id].grade)
			score -= 1000.0 * float(PRIORITY.get(grade, 0))
		if score < best_score:
			best_score = score
			best = id
	return best

func tick_hound(ally: Dictionary, dt: float) -> void:
	var p := plan("hound", ally.node_kind)
	if ally.action == "bite":
		ally.action_time += dt
		if not ally.acted and ally.action_time >= float(p.bite_hit_at):
			ally.acted = true
			bite(ally, p)
		if ally.action_time >= float(p.bite_seconds):
			ally.action = ""
	if not arena.on_screen(ally.node.position):
		ally.target = ""
		ally.action = ""
		go_home(ally, arena.automaton_spawn_position(ally.slot), maxf(7.0, float(p.speed)), dt)
		return
	ally.target = hound_target(ally, p)
	if ally.target == "":
		if ally.action == "":
			go_home(ally, arena.automaton_spawn_position(ally.slot), float(p.speed), dt)
		return
	var at: Vector3 = arena.enemies[ally.target].body.position
	face(ally, at, dt)
	ally.reach = (arena.automaton_reach(ally.target) + 0.15) * float(ally.scale)
	var gap: float = ally.node.position.distance_to(at)
	if ally.action == "" and gap > ally.reach:
		ally.node.position = ally.node.position.move_toward(arena.follow(ally.route, ally.node.position, at, 0.4, dt), dt * float(p.speed))
	ally.cooldown -= dt
	if ally.action == "" and ally.cooldown <= 0.0 and gap <= ally.reach + 0.2:
		ally.action = "bite"
		ally.action_time = 0.0
		ally.acted = false
		ally.cooldown = float(p.bite_seconds)

func bite(ally: Dictionary, p: Dictionary) -> void:
	# The jaw shuts at the clip's 0.3s: one roll, and a bite that lands slows the enemy briefly.
	var id: String = ally.target
	if not arena.enemies.has(id):
		return
	var damage: float = float(p.bite_damage) * float(p.get("damage_factor", 1.0)) * arena.summon_growth("damage", "hound") * arena.relay_factor(ally)
	var art = ally.node.get_node_or_null("ActorVisual")
	var jaw: Vector3 = art.strike_point() if art != null else ally.node.position + Vector3.UP * 0.5
	arena.spawn_vfx().summon_punch(jaw, arena.enemies[id].body.position - ally.node.position, arena.TEAL, arena.map.ground_y(jaw))
	var result: String = arena.strike(id, damage, true, "hound", "hound")
	if result != "miss" and arena.enemies.has(id):
		arena.enemies[id].slow = maxf(float(arena.enemies[id].slow), float(p.slow_seconds))
	bites += 1
	last_bite = {"ally": ally.id, "target": id, "result": result, "damage": damage}

func tick_beacon(ally: Dictionary, dt: float) -> void:
	# A signal every second from the moment it stands: enemies within reach turn on it and stay
	# turned while it lives. Bosses do not answer it. It never attacks.
	var p := plan("beacon")
	ally.pulse_clock += dt
	ally.pulse_wait -= dt
	if ally.pulse_wait > 0.0:
		return
	ally.pulse_wait += float(p.pulse_seconds)
	ally.pulse_clock = 0.0
	var lured: Array = []
	for id in arena.enemies:
		var enemy: Dictionary = arena.enemies[id]
		if arena.config.enemy_types[enemy.kind].has("boss"):
			continue
		var gap: Vector3 = enemy.body.position - ally.node.position
		gap.y = 0.0
		if gap.length() <= float(p.lure_radius) + 0.4 * float(enemy.size):
			enemy.lure = ally.id
			enemy.target = ally.id
			lured.append(id)
	var at: Vector3 = ally.node.position
	var floor_y: float = arena.map.ground_y(at)
	arena.spawn_vfx().ground_ring(Vector3(at.x, floor_y, at.z), 0.4, float(p.lure_radius), 0.12, AMBER, 0.55)
	arena.play_cue(1.9, -6.0)
	last_pulse = {"ally": ally.id, "lured": lured}

func lured_to(enemy: Dictionary, ally: Dictionary) -> bool:
	return ally.get("summon", "") == "beacon" and enemy.get("lure", "") == ally.id

func giant_target(ally: Dictionary) -> String:
	if arena.eligible(ally, ally.target):
		return ally.target
	return arena.nearest_enemy(ally.node.position, arena.detection_range(ally), Vector3.ZERO, -1, true, true)

func tick_giant(ally: Dictionary, dt: float) -> void:
	var p := plan("giant", ally.node_kind)
	if ally.action == "slam":
		# The slam plants it: no walking until the fists are back up.
		ally.action_time += dt
		if not ally.acted and ally.action_time >= float(p.slam_hit_at):
			ally.acted = true
			slam(ally, p)
		if ally.action_time >= float(p.slam_seconds):
			ally.action = ""
		return
	if not arena.on_screen(ally.node.position):
		ally.target = ""
		go_home(ally, giant_anchor(ally.giant_slot), float(p.speed) * 1.6, dt)
		return
	ally.target = giant_target(ally)
	if ally.target == "":
		go_home(ally, giant_anchor(ally.giant_slot), float(p.speed), dt)
		return
	var at: Vector3 = arena.enemies[ally.target].body.position
	face(ally, at, dt)
	# The fists come down about a metre ahead (Socket_attack), scaled with the machine.
	ally.reach = 1.25 * float(ally.scale) + 0.4 * float(arena.enemies[ally.target].size)
	var gap: float = Vector2(at.x - ally.node.position.x, at.z - ally.node.position.z).length()
	if gap > ally.reach:
		ally.node.position = ally.node.position.move_toward(arena.follow(ally.route, ally.node.position, at, 0.4, dt), dt * float(p.speed))
	ally.cooldown -= dt
	var facing: Vector3 = -ally.node.global_basis.z
	var toward: Vector3 = (at - ally.node.position) * Vector3(1, 0, 1)
	if ally.cooldown <= 0.0 and gap <= ally.reach + 0.2 and facing.dot(toward.normalized()) > 0.8:
		ally.action = "slam"
		ally.action_time = 0.0
		ally.acted = false
		ally.cooldown = float(p.slam_seconds)

func slam(ally: Dictionary, p: Dictionary) -> void:
	# Both fists hit the floor in front: every enemy in the 2.2m front fan takes its own roll and is
	# shoved back from the giant (heavy half, bosses not); the single node also stuns briefly.
	var origin: Vector3 = ally.node.position
	var facing: Vector3 = -ally.node.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var damage: float = float(p.damage) * float(p.get("damage_factor", 1.0)) * arena.summon_growth("damage", "giant")
	var struck: Array = []
	for id in arena.enemies.keys():
		if not arena.enemies.has(id):
			continue
		var gap: Vector3 = arena.enemies[id].body.position - origin
		gap.y = 0.0
		var size: float = float(arena.enemies[id].size)
		if gap.length() > float(p.slam_radius) + 0.4 * size:
			continue
		if gap.length() > 0.3 and gap.normalized().dot(facing) < float(p.slam_dot):
			continue
		if not arena.map.sees(origin, arena.enemies[id].body.position):
			continue
		var factor: float = arena.relay_factor({"target": id, "relayed": ally.get("relayed", "")})
		var result: String = arena.strike(id, damage * factor, true, "giant", "giant")
		struck.append({"id": id, "result": result})
		if result != "miss" and arena.enemies.has(id):
			arena.push_back(id, float(p.push_distance), float(p.push_seconds), origin)
			if float(p.get("stun_seconds", 0.0)) > 0.0:
				arena.restrain(id, "stun", float(p.stun_seconds))
	var art = ally.node.get_node_or_null("ActorVisual")
	var at: Vector3 = art.strike_point() if art != null else origin + facing * 1.1
	var floor_y: float = arena.map.ground_y(at)
	var fx = arena.spawn_vfx()
	fx.fan_slash(Vector3(origin.x, floor_y, origin.z), facing, float(p.slam_radius), 120.0, floor_y)
	fx.ground_ring(Vector3(at.x, floor_y, at.z), 0.2, 1.0 * float(ally.scale), 0.18, Color(1.0, 0.62, 0.32), 0.35)
	arena.shake_time = maxf(arena.shake_time, 0.12 * float(ally.scale))
	arena.play_sfx("boss_slam", 1.25)
	last_slam = {"ally": ally.id, "struck": struck, "damage": damage, "at": at}
