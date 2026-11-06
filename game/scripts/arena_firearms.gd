extends RefCounted
## Firearm tree (03 §5.1-§5.4): floating matchlock/rifle magazines and reloads, piercing shots, the
## shotgun volley and knock-back, recoil leap, rolling powder kegs, the Gatling, offscreen artillery and
## naval shells with their fires, and smoke. Rules data stays in combat_rules/trial.json; state
## (gun, kegs, shells, fires, smokes, ...) stays on the arena. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func reload_level() -> float:
	return float(arena.config.passive_levels.get("reload", 0))

func recoil_level() -> float:
	return float(arena.config.passive_levels.get("recoil_control", 0))

func fire_interval_factor() -> float:
	# Recoil control (firearm passive): every firearm fires again sooner, by a share per level.
	return maxf(0.1, 1.0 - float(arena.config.passives.recoil_control.fire_interval_cut_per_level) * recoil_level())

func leap_speed_factor() -> float:
	# It also lands the recoil leap and the spring dash's jump faster: the same distance in less time.
	return 1.0 + float(arena.config.passives.recoil_control.leap_speed_per_level) * recoil_level()

func gun_magazine(id: String) -> int:
	# Reload mechanism levels and magazine options add rounds to every gun's magazine.
	return int(arena.rules.skills[id].magazine) + int(arena.config.passives.reload.magazine_per_level) * int(reload_level()) + int(arena.gear_total("magazine"))

func reload_seconds(id: String) -> float:
	# One empty round loads back each interval; each reload mechanism level cuts a share of it.
	return float(arena.rules.skills[id].reload_seconds) * maxf(0.1, 1.0 - float(arena.config.passives.reload.reload_time_cut_per_level) * reload_level())

func tick_gun_reload(dt: float) -> void:
	# Empty rounds load back on their own, one per interval, each paying its mana as it goes in.
	# With too little mana the next round waits; a full magazine keeps the clock wound.
	if arena.gun.is_empty():
		return
	var interval := reload_seconds(arena.gun.id)
	if int(arena.gun.ammo) >= gun_magazine(arena.gun.id):
		arena.gun.reload_left = interval
		return
	arena.gun.reload_left = float(arena.gun.reload_left) - dt
	if arena.gun.reload_left > 0:
		return
	var cost := arena.round_cost(arena.gun.id)
	if arena.state.mana + arena.rules.EPS < cost:
		arena.gun.reload_left = 0.0
		return
	arena.state.mana = maxf(0.0, arena.state.mana - cost)
	arena.probe.record([{"type": "tool_upkeep", "tool": arena.gun.id, "amount": cost}])
	arena.gun.ammo = int(arena.gun.ammo) + 1
	arena.gun.reload_left += interval

func sync_gun() -> void:
	# The basic attack takes the gun's reach while one is out.
	arena.rules.skills.basic_attack.range = float(arena.rules.skills[arena.gun.id].range) if not arena.gun.is_empty() else arena.basic_range
	# A lower reload level shrinks the magazine; rounds over it are dropped.
	if not arena.gun.is_empty():
		arena.gun.ammo = mini(int(arena.gun.ammo), gun_magazine(arena.gun.id))

func equip_gun(id: String) -> void:
	# A gun and a tool both change the basic attack, so the gun puts the tool away (and back).
	if arena.state.active_tool != null:
		arena.state.active_tool = null
		arena.flash_tool_change(null)
	var visual: Node3D = arena.gun_assembly if is_instance_valid(arena.gun_assembly) else null
	arena.gun_assembly = null
	if not arena.gun.is_empty() and arena.gun.visual != visual and is_instance_valid(arena.gun.visual):
		arena.gun.visual.dismiss()
	if visual == null:
		visual = Arena.FloatingGun.new()
		visual.configure(id)
		arena.world.add_child(visual)
		visual.initialize(arena)
	visual.gun_id = id
	visual.ready_to_fire()
	arena.gun = {"id": id, "ammo": gun_magazine(id), "reload_left": reload_seconds(id), "visual": visual}
	arena.sync_automaton_cost()
	arena.play_sfx("tool_change", 1.3)

func dismiss_gun() -> void:
	if arena.gun.is_empty():
		return
	if is_instance_valid(arena.gun.visual):
		arena.gun.visual.dismiss()
	arena.gun = {}
	arena.sync_automaton_cost()

func gun_round(id: String) -> Dictionary:
	# The rifle's node picks its round; other guns fire their own single kind.
	var skill: Dictionary = arena.rules.skills[id]
	return skill.nodes[arena.config.rifle_node] if skill.has("nodes") else skill

func fire_gun(event: Dictionary, direction: Vector3) -> void:
	# One round per shot, hit or miss, from the floating gun's muzzle to the chosen enemy.
	var skill: Dictionary = arena.rules.skills[arena.gun.id]
	var best := arena.nearest_enemy(arena.player.position, float(skill.range), direction, 0.2, false, true)
	if event.get("target_enemy") != null and arena.enemies.has(event.target_enemy):
		best = event.target_enemy
	var target_spot: Vector3 = arena.enemies[best].body.position if best != "" else Vector3.ZERO
	arena.gun.ammo = maxi(0, int(arena.gun.ammo) - 1)
	var aim: Vector3 = arena.player.position + direction * float(skill.range) + Vector3.UP * 1.2
	if best != "":
		aim = arena.enemies[best].body.position + Vector3.UP * 0.9 * arena.enemies[best].size
	var origin: Vector3 = arena.player.position + Vector3.UP * 1.3
	if is_instance_valid(arena.gun.visual):
		arena.gun.visual.shoot(aim)
		origin = arena.gun.visual.muzzle()
	var shell: Dictionary = gun_round(arena.gun.id)
	var damage: float = float(shell.shot_damage)
	var struck: Array = []
	var hit := "miss"
	if shell.has("pierce_width"):
		# Piercing rounds run the whole range and strike every enemy along the line in sight.
		aim = arena.player.position + direction * float(skill.range) + Vector3.UP * 1.2
		if best != "":
			var flat: Vector3 = arena.enemies[best].body.position - arena.player.position
			flat.y = 0.0
			aim = arena.player.position + flat.normalized() * float(skill.range) + Vector3.UP * 1.2
		var line: Vector3 = aim - arena.player.position
		line.y = 0.0
		line = line.normalized()
		for id in arena.enemies.keys():
			var delta: Vector3 = arena.enemies[id].body.position - arena.player.position
			delta.y = 0.0
			var along: float = delta.dot(line)
			if along > 0 and along <= float(skill.range) and (delta - line * along).length() <= float(shell.pierce_width) * arena.enemies[id].size and arena.map.sees(arena.player.position, arena.enemies[id].body.position):
				struck.append(id)
		for id in struck:
			var result := arena.strike(id, damage, true, "witch", arena.gun.id)
			if result != "miss":
				hit = result
	elif best != "":
		struck.append(best)
		hit = arena.strike(best, damage, true, "witch", arena.gun.id)
		if shell.has("knockback_distance") and hit != "miss":
			push_back(best, float(shell.knockback_distance), float(shell.knockback_seconds))
		var flat: Vector3 = target_spot - arena.player.position
		flat.y = 0.0
		struck.append_array(pierce_behind(best, target_spot, flat.normalized(), float(skill.range), 0.5, damage, arena.gun.id))
	if shell.has("blast_radius"):
		# Explosive rounds burst where they land, hit or miss: everyone else nearby is caught too.
		var at: Vector3 = Vector3(aim.x, arena.map.ground_y(aim), aim.z)
		for id in arena.enemies.keys():
			if (id != best or hit == "miss") and Vector2(arena.enemies[id].body.position.x - at.x, arena.enemies[id].body.position.z - at.z).length() <= float(shell.blast_radius):
				if not struck.has(id):
					struck.append(id)
				arena.strike(id, damage, false, "witch", arena.gun.id)
		arena.spawn_vfx().blast(at, float(shell.blast_radius), arena.map.ground_y(at), false)
	arena.spawn_vfx().muzzle(origin, [aim], [struck.is_empty()], arena.map.ground_y(origin))
	arena.play_sfx("shotgun_fire", (0.85 if arena.gun.id == "rifle" else 1.15) if hit != "miss" else 1.3)
	arena.last_shot = {"gun": arena.gun.id, "target": best, "result": hit, "origin": origin, "aim": aim, "struck": struck}
	if int(arena.gun.ammo) == 0:
		arena.show_message("탄이 없습니다")

func pierce_behind(first: String, spot: Vector3, line: Vector3, reach: float, width: float, damage: float, source: String) -> Array:
	# Pierce options (04 §4.3): a single round carries on past the enemy it struck (at `spot`, which
	# it may just have killed) into the next enemies on its line, each rolling to hit for full damage.
	var count := int(arena.gear_total("pierce"))
	if count <= 0:
		return []
	var past: float = Vector3(spot.x - arena.player.position.x, 0.0, spot.z - arena.player.position.z).dot(line)
	var behind: Array = []
	for id in arena.enemies:
		var delta: Vector3 = arena.enemies[id].body.position - arena.player.position
		delta.y = 0.0
		var along: float = delta.dot(line)
		if id != first and along > past and along <= reach and (delta - line * along).length() <= width * float(arena.enemies[id].size) and arena.map.sees(arena.player.position, arena.enemies[id].body.position):
			behind.append({"along": along, "id": id})
	behind.sort_custom(func(a, b): return a.along < b.along)
	var hits: Array = []
	for entry in behind.slice(0, count):
		hits.append(entry.id)
		arena.strike(entry.id, damage, true, "witch", source)
	return hits

func keg_start(direction: Vector3) -> Vector3:
	# The keg assembles on the floor just in front of her, where it will start rolling.
	return arena.map.grounded(arena.player.position + direction * float(arena.rules.skills.powder_keg.start_offset))

func begin_keg_visual(direction: Vector3) -> void:
	arena.keg_assembly = Arena.PowderKeg.new()
	arena.world.add_child(arena.keg_assembly)
	arena.keg_assembly.position = keg_start(direction)
	arena.keg_assembly.look_at(arena.keg_assembly.global_position + direction, Vector3.UP)
	arena.keg_assembly.initialize(arena)

func roll_keg(target: Vector3, direction: Vector3) -> void:
	# Powder keg (03 §3, firearm area I): it rolls along the floor toward the aim and bursts on the
	# first enemy it touches, at a wall, or where she aimed (at least min_roll, at most its range).
	var skill: Dictionary = arena.rules.skills.powder_keg
	if not is_instance_valid(arena.keg_assembly):
		begin_keg_visual(direction)
	var visual: Node3D = arena.keg_assembly
	arena.keg_assembly = null
	visual.launch()
	var flat: Vector3 = target - arena.player.position
	flat.y = 0.0
	var reach: float = clampf(flat.length(), float(skill.min_roll), float(skill.range)) - float(skill.start_offset)
	arena.kegs.append({"visual": visual, "position": visual.global_position, "direction": direction, "left": reach, "total": reach, "rolled": 0.0})
	arena.play_sfx("summon_arrive", 0.8)

func keg_contact(at: Vector3) -> String:
	# The first enemy whose body the rolling drum runs into.
	var reach: float = float(arena.rules.skills.powder_keg.contact_radius)
	for id in arena.enemies:
		var pos: Vector3 = arena.enemies[id].body.position
		if Vector2(pos.x - at.x, pos.z - at.z).length() <= reach + 0.4 * float(arena.enemies[id].size):
			return id
	return ""

func tick_kegs(dt: float) -> void:
	var speed: float = float(arena.rules.skills.powder_keg.roll_speed)
	for keg in arena.kegs.duplicate():
		var travel: float = minf(speed * dt, float(keg.left))
		var next: Vector3 = keg.position + keg.direction * travel
		var reason := ""
		if arena.map.walkable(next):
			keg.position = arena.map.grounded(next)
			keg.left -= travel
			keg.rolled += travel
			if arena.gear_total("rule:fuse_trail") > 0:
				# Unique 불붙은 심지 다발: the lit drum leaves a line of small fires behind it.
				var rule: Dictionary = arena.items.data.rule_values
				keg.trail = float(keg.get("trail", 0.0)) + travel
				while keg.trail >= float(rule.fuse_fire_every):
					keg.trail -= float(rule.fuse_fire_every)
					start_fire(keg.position, {"fire_radius": rule.fuse_fire_radius, "fire_seconds": rule.fuse_fire_seconds,
						"fire_damage": rule.fuse_fire_damage, "fire_tick": rule.fuse_fire_tick}, "powder_keg")
		else:
			reason = "wall"
		if is_instance_valid(keg.visual):
			keg.visual.roll_to(keg.position, keg.rolled, keg.left / maxf(0.0001, keg.total))
		if keg_contact(keg.position) != "":
			reason = "enemy"
		elif reason == "" and keg.left <= 0.0001:
			reason = "end"
		if reason != "":
			burst_keg(keg, reason)

func burst_keg(keg: Dictionary, reason: String) -> void:
	# The blast catches every enemy in its radius that open floor connects it to; no hit roll.
	arena.kegs.erase(keg)
	var skill: Dictionary = arena.rules.skills.powder_keg
	var at: Vector3 = keg.position
	var radius: float = float(skill.blast_radius)
	var damage: float = float(skill.blast_damage)
	if arena.gear_total("rule:fuse_trail") > 0:
		damage *= float(arena.items.data.rule_values.fuse_blast_factor)
	var struck: Array = []
	for id in arena.enemies.keys():
		var pos: Vector3 = arena.enemies[id].body.position
		if Vector2(pos.x - at.x, pos.z - at.z).length() <= radius and arena.map.sees(at, pos):
			struck.append(id)
			arena.strike(id, damage, false, "witch", "powder_keg")
	if is_instance_valid(keg.visual):
		keg.visual.burst()
	arena.spawn_vfx().blast(at, radius, arena.map.ground_y(at), false)
	arena.shake_time = maxf(arena.shake_time, 0.12)
	arena.play_sfx("automaton_explode", 0.7)
	arena.last_keg = {"at": at, "reason": reason, "rolled": keg.rolled, "struck": struck}

func clear_kegs() -> void:
	for keg in arena.kegs:
		if is_instance_valid(keg.visual):
			keg.visual.dismiss()
	arena.kegs.clear()

func strike_point(target: Vector3, direction: Vector3, reach: float) -> Vector3:
	# Where an offscreen gun aims: the cursor, at most its range away, on open floor.
	var flat: Vector3 = target - arena.player.position
	flat.y = 0.0
	var center: Vector3 = arena.player.position + direction * minf(flat.length(), reach)
	if not arena.map.walkable(center):
		center = arena.map.snap(center)
	return arena.map.grounded(center)

func witch_amount(amount: float, source: String) -> float:
	# Her damage before any roll: power, gear and skill level, as strike() applies them. The attack
	# roll comes on impact (strike_amount); burning ground takes the middle of her range.
	return amount * arena.build.power_factor() * (1.0 + arena.gear_total("damage_pct") / 100.0) * arena.skill_level_factor(source)

func mark_target(center: Vector3, radius: float, seconds: float) -> void:
	# A gold ring where her own barrage will land, gone when the last shell is down.
	var ring: MeshInstance3D = Arena.Shape.ring(arena.world, center + Vector3(0, 0.05, 0), radius, Color(0.85, 0.72, 0.48, 0.8), 0.05)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.effects.append({"node": ring, "life": seconds, "grow": false})

func send_shell(kind: String, at: Vector3, delay: float, flight: float, impact: Dictionary, burst_height: float = 0.0) -> void:
	# The shell comes in from far up and off to the side, beyond the screen, and lands after delay.
	var end: Vector3 = at + Vector3.UP * burst_height
	var start: Vector3 = end + Vector3(-9.0, 24.0, -6.0)
	var visual: Node3D = null
	var trail: Node3D = null
	if kind != "":
		visual = Arena.IncomingShell.new()
		arena.world.add_child(visual)
		visual.initialize(kind, start, end)
		trail = arena.spawn_vfx()
	arena.shells.append({"visual": visual, "trail": trail, "start": start, "end": end, "left": delay, "flight": flight, "at": at, "impact": impact})

func call_artillery(target: Vector3, direction: Vector3) -> void:
	# Rocket barrage (03 §3, firearm IV): after a short wait the shells come in one by one, at
	# uneven moments, scattered over a wide circle. The node picks the shell: high explosive,
	# cluster (bursts overhead into bomblets over a wider spread) or white phosphorus (sets fires).
	var skill: Dictionary = arena.rules.skills.artillery
	var shell: Dictionary = skill.nodes[arena.config.artillery_node]
	var center := strike_point(target, direction, float(skill.range))
	var count: int = int(skill.shells)
	var spread: float = float(shell.get("spread_radius", skill.spread_radius))
	var last := 0.0
	for i in count:
		# A fixed scatter (not the combat RNG): golden-angle spokes, uneven landing times.
		var angle: float = i * 2.39996 + 0.7
		var spot: Vector3 = center + Vector3(cos(angle), 0, sin(angle)) * spread * sqrt((i + 0.5) / count)
		spot = arena.map.grounded(spot) if arena.map.walkable(spot) else center
		var delay: float = float(skill.first_delay) + float(skill.barrage_seconds) * clampf((i + 0.45 * sin(i * 12.9898)) / count, 0.0, 1.0)
		last = maxf(last, delay)
		var impact := {"kind": "cluster" if shell.has("bomblets") else "blast", "radius": float(shell.blast_radius), "damage": witch_amount(float(shell.shot_damage), "artillery"), "source": "artillery", "shell": shell}
		send_shell("artillery", spot, delay, float(skill.flight_seconds), impact, float(shell.get("airburst_height", 0.0)))
	mark_target(center, spread + float(shell.get("bomblet_spread", shell.blast_radius)), last)
	arena.last_impact = {"skill": "artillery", "center": center, "shells": count}
	arena.play_sfx("shotgun_fire", 0.45, -8.0)

func call_naval_gun(target: Vector3, direction: Vector3) -> void:
	# Heavy naval gun (03 §3, firearm IV): one slow, heavy shell from far off, telegraphed by its
	# ring. Its node trades area for weight: a wide burst that leaves the ground burning, or a
	# narrow piercing round for one strong enemy.
	var skill: Dictionary = arena.rules.skills.naval_gun
	var shell: Dictionary = skill.nodes[arena.config.naval_gun_node]
	var center := strike_point(target, direction, float(skill.range))
	var impact := {"kind": "blast", "radius": float(shell.blast_radius), "damage": witch_amount(float(shell.shot_damage), "naval_gun"), "source": "naval_gun", "shell": shell, "heavy": true}
	send_shell("naval", center, float(skill.delay), float(skill.flight_seconds), impact)
	mark_target(center, float(shell.blast_radius), float(skill.delay))
	arena.last_impact = {"skill": "naval_gun", "center": center}
	arena.play_sfx("shotgun_fire", 0.4, -6.0)

func tick_shells(dt: float) -> void:
	for shell in arena.shells.duplicate():
		shell.left = float(shell.left) - dt
		if is_instance_valid(shell.visual) and shell.left <= shell.flight:
			var before: Vector3 = shell.visual.global_position if shell.visual.visible else shell.start
			shell.visual.place(1.0 - maxf(0.0, shell.left) / float(shell.flight))
			if is_instance_valid(shell.trail):
				shell.trail.streak(before, shell.visual.global_position, 0.06, Color(1.0, 0.85, 0.6, 0.8), 0.2)
				# Smoke every third frame is enough for the trail and keeps a barrage's particles down.
				if Engine.get_physics_frames() % 3 == 0:
					shell.trail.puff(before, Vector3.ZERO, 0.18, 0.6, Color(0.55, 0.55, 0.52, 0.35), 0.6, 0.1)
		if shell.left > 0:
			continue
		arena.shells.erase(shell)
		if is_instance_valid(shell.visual):
			shell.visual.queue_free()
		land_shell(shell)

func land_shell(shell: Dictionary) -> void:
	var impact: Dictionary = shell.impact
	var at: Vector3 = shell.at
	if impact.kind == "cluster":
		# Bursts overhead: bomblets rain over a wider patch, each a small blast.
		var burst: Vector3 = shell.end
		var fx := arena.spawn_vfx()
		# The bomblets draw into this same effect, so it must outlive their fall.
		fx.entry.life = maxf(float(fx.entry.life), 1.2)
		fx.flash(burst, 1.2, Color(1.0, 0.75, 0.4), 0.18, 1.0)
		fx.sparks(burst, Vector3.DOWN, 18, 6.0, 1.2, Color(1.0, 0.8, 0.45), 0.4, 0.02, arena.map.ground_y(at))
		var bomblets: int = int(impact.shell.bomblets)
		for i in bomblets:
			var angle: float = TAU * i / bomblets + float(shell.end.x) * 1.7
			var spot: Vector3 = at + Vector3(cos(angle), 0, sin(angle)) * float(impact.shell.bomblet_spread) * (0.45 + 0.55 * fposmod(i * 0.618, 1.0))
			spot = arena.map.grounded(spot) if arena.map.walkable(spot) else at
			fx.streak(burst, spot, 0.04, Color(1.0, 0.7, 0.35, 0.7), 0.25)
			send_shell("", spot, 0.22 + 0.03 * i, 0.0, {"kind": "blast", "radius": impact.radius, "damage": impact.damage, "source": impact.source, "shell": {}, "small": true, "fx": fx, "first": i == 0})
		arena.play_sfx("shotgun_fire", 0.7, -4.0)
		return
	var struck: Array = []
	for id in arena.enemies.keys():
		var pos: Vector3 = arena.enemies[id].body.position
		if Vector2(pos.x - at.x, pos.z - at.z).length() <= float(impact.radius) + 0.3 * float(arena.enemies[id].size) and arena.map.sees(at, pos):
			struck.append(id)
			strike_amount(id, float(impact.damage), impact.source)
	var heavy: bool = impact.get("heavy", false)
	var small: bool = impact.get("small", false)
	if small and is_instance_valid(impact.get("fx")):
		impact.fx.small_blast(at, float(impact.radius), arena.map.ground_y(at))
	else:
		arena.spawn_vfx().blast(at, float(impact.radius), arena.map.ground_y(at), heavy)
	arena.shake_time = maxf(arena.shake_time, 0.3 if heavy else (0.05 if small else 0.12))
	# A shell's bomblets crackle under one sound, not one each.
	if not small or impact.get("first", false):
		arena.play_sfx("automaton_explode", 0.5 if heavy else (1.1 if small else 0.75))
	if impact.shell.has("fire_radius"):
		start_fire(at, impact.shell, impact.source)
	arena.last_impact = {"at": at, "struck": struck, "source": impact.source, "radius": impact.radius}

func strike_amount(id: String, amount: float, source: String) -> void:
	# A blast already scaled by her power, gear and skill level: no hit roll, its own crit roll.
	if not arena.enemies.has(id):
		return
	var crit: bool = arena.force_rolls.get("crit", arena.combat_rng.randf() < arena.crit_chance("witch"))
	var dealt: float = arena.damage_enemy(id, amount * arena.attack_factor(arena.roll_attack(crit)) * arena.passive_factor(source) * (arena.config.crit_multiplier if crit else 1.0))
	arena.probe.strike(source, "crit" if crit else "hit", dealt)
	leech(dealt)

func leech(dealt: float) -> void:
	# Life and mana leech (04 §4.3): a share of what her own direct hit actually removed. Bleed,
	# burning ground and summon hits never pass here, and neither does a kill's overkill.
	if arena.hp <= 0 or dealt <= 0:
		return
	arena.hp = minf(arena.config.max_hp, arena.hp + dealt * arena.gear_total("life_leech_pct") / 100.0)
	arena.state.mana = minf(arena.state.max_mana, arena.state.mana + dealt * arena.gear_total("mana_leech_pct") / 100.0)

func start_fire(at: Vector3, shell: Dictionary, source: String) -> void:
	var patch: Node3D = Arena.FirePatch.new()
	arena.world.add_child(patch)
	patch.initialize(at, float(shell.fire_radius))
	arena.fires.append({"center": at, "radius": float(shell.fire_radius), "left": float(shell.fire_seconds), "total": float(shell.fire_seconds),
		"damage": witch_amount(float(shell.fire_damage), source) * arena.attack_factor((arena.attack_range().x + arena.attack_range().y) / 2.0), "tick": float(shell.fire_tick), "patch": patch})

func tick_fires(dt: float) -> void:
	# Each enemy standing in fire burns once per tick, from the strongest fire it stands in. Burning
	# is not a direct hit: no roll, no crit, no flinch, like bleed.
	for fire in arena.fires.duplicate():
		fire.left = float(fire.left) - dt
		if is_instance_valid(fire.patch):
			fire.patch.advance(dt)
			fire.patch.show_state(maxf(0.0, fire.left), fire.total)
		if fire.left <= 0:
			if is_instance_valid(fire.patch):
				fire.patch.queue_free()
			arena.fires.erase(fire)
	if arena.fires.is_empty():
		arena.burn_clock = 0.0
		return
	arena.burn_clock += dt
	var tick: float = float(arena.fires[0].tick)
	if arena.burn_clock < tick:
		return
	arena.burn_clock -= tick
	for id in arena.enemies.keys():
		if not arena.enemies.has(id):
			continue
		var pos: Vector3 = arena.enemies[id].body.position
		var amount := 0.0
		for fire in arena.fires:
			if Vector2(pos.x - fire.center.x, pos.z - fire.center.z).length() <= float(fire.radius):
				amount = maxf(amount, float(fire.damage))
		if amount > 0:
			arena.probe.burn(arena.damage_enemy(id, amount, false))

func clear_barrage() -> void:
	for shell in arena.shells:
		if is_instance_valid(shell.visual):
			shell.visual.queue_free()
	arena.shells.clear()
	for fire in arena.fires:
		if is_instance_valid(fire.patch):
			fire.patch.queue_free()
	arena.fires.clear()

func smoke_seconds() -> float:
	var skill: Dictionary = arena.rules.skills.smoke_launcher
	return float(skill.smoke_seconds) + float(skill.seconds_per_level) * (float(arena.config.smoke_launcher_level) - 1.0)

func launch_smoke(target: Vector3, direction: Vector3) -> void:
	# Smoke launcher (03 §3, firearm III): six canisters land around the aimed point (its range at
	# most) and raise a cloud once they are down. Her own shots and her summons see through it.
	var skill: Dictionary = arena.rules.skills.smoke_launcher
	var flat: Vector3 = target - arena.player.position
	flat.y = 0.0
	var center: Vector3 = arena.player.position + direction * minf(flat.length(), float(skill.range))
	if not arena.map.walkable(center):
		center = arena.map.snap(center)
	center = arena.map.grounded(center)
	var landings: Array[Vector3] = []
	for i in 6:
		var spot: Vector3 = center + Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0)) * float(skill.canister_spread)
		landings.append(arena.map.grounded(spot) if arena.map.walkable(spot) else center)
	if not is_instance_valid(arena.smoke_assembly):
		arena.smoke_assembly = Arena.SmokeLauncher.new()
		arena.world.add_child(arena.smoke_assembly)
		arena.smoke_assembly.position = arena.map.grounded(arena.player.position + direction.cross(Vector3.UP) * 0.75)
		arena.smoke_assembly.look_at(arena.smoke_assembly.global_position + direction, Vector3.UP)
		arena.smoke_assembly.initialize(arena)
	var seconds := smoke_seconds()
	arena.smoke_assembly.fire(landings, float(skill.flight_seconds), seconds)
	arena.smoke_assembly = null
	var cloud: Node3D = Arena.SmokeCloud.new()
	arena.world.add_child(cloud)
	cloud.initialize(center, float(skill.smoke_radius))
	arena.smokes.append({"center": center, "radius": float(skill.smoke_radius), "wait": float(skill.flight_seconds), "left": seconds, "total": seconds, "cloud": cloud})
	arena.play_sfx("shotgun_fire", 0.55, -4.0)

func tick_smokes(dt: float) -> void:
	for smoke in arena.smokes.duplicate():
		if smoke.wait > 0:
			smoke.wait = maxf(0.0, float(smoke.wait) - dt)
		else:
			smoke.left = float(smoke.left) - dt
		if is_instance_valid(smoke.cloud):
			smoke.cloud.advance(dt)
			smoke.cloud.show_state(smoke.wait, maxf(0.0, smoke.left), smoke.total)
		if smoke.left <= 0:
			if is_instance_valid(smoke.cloud):
				smoke.cloud.queue_free()
			arena.smokes.erase(smoke)

func hidden_between(a: Vector3, b: Vector3) -> bool:
	# True when a standing cloud covers either end or the line between them (on the floor plan).
	for smoke in arena.smokes:
		if smoke.wait > 0 or smoke.left <= 0:
			continue
		var c := Vector2(smoke.center.x, smoke.center.z)
		var from := Vector2(a.x, a.z)
		var to := Vector2(b.x, b.z)
		var line: Vector2 = to - from
		var along: float = clampf((c - from).dot(line) / maxf(line.length_squared(), 0.0001), 0.0, 1.0)
		if c.distance_to(from + line * along) <= float(smoke.radius):
			return true
	return false

func blinded(enemy: Dictionary) -> bool:
	# Bosses keep their own patterns and see through the smoke.
	return arena.hp > 0 and not arena.config.enemy_types[enemy.kind].has("boss") and hidden_between(enemy.body.position, arena.player.position)

func gatling_round() -> Dictionary:
	return arena.rules.skills.gatling.nodes[arena.config.gatling_node]

func gatling_interval() -> float:
	# Rounds follow attack speed: the stream is her basic fire, the spin-up cast is the machine.
	var base: float = float(arena.rules.skills.gatling.fire_seconds)
	return arena.motion_seconds(base, base * arena.config.min_cast_ratio, arena.config.attack_speed_k, arena.config.attack_speed_score) * fire_interval_factor()

func fire_gatling(direction: Vector3) -> void:
	# One round, woven across the node's spread (a fixed pattern, so the stream covers it evenly),
	# strikes the nearest enemy in sight on its line. Each round rolls to hit like other shots.
	var skill: Dictionary = arena.rules.skills.gatling
	var shell := gatling_round()
	var spread: float = deg_to_rad(float(shell.spread_degrees)) * sin(float(arena.channel.shots) * 2.39996)
	arena.channel.shots = int(arena.channel.shots) + 1
	var line: Vector3 = direction.rotated(Vector3.UP, spread)
	var reach: float = float(skill.range)
	var best := ""
	var nearest := INF
	for id in arena.enemies:
		var delta: Vector3 = arena.enemies[id].body.position - arena.player.position
		delta.y = 0.0
		var along: float = delta.dot(line)
		if along > 0 and along <= reach and along < nearest and (delta - line * along).length() <= float(skill.hit_width) * float(arena.enemies[id].size) and arena.map.sees(arena.player.position, arena.enemies[id].body.position):
			best = id
			nearest = along
	var origin: Vector3 = arena.player.position + Vector3.UP
	if is_instance_valid(arena.channel.visual):
		origin = arena.channel.visual.muzzle()
	var end: Vector3 = arena.player.position + line * reach + Vector3.UP
	var hit := "miss"
	if best != "":
		end = arena.enemies[best].body.position + Vector3.UP * 0.8 * float(arena.enemies[best].size)
		var damage: float = float(shell.shot_damage)
		if shell.has("focus_per_hit"):
			# Converging fire: steady hits on one enemy build up; a new target starts over.
			if arena.channel.focus != best:
				arena.channel.focus = best
				arena.channel.focus_hits = 0
			damage *= 1.0 + minf(float(shell.focus_max), float(shell.focus_per_hit) * float(arena.channel.focus_hits))
		var spot: Vector3 = arena.enemies[best].body.position
		hit = arena.strike(best, damage, true, "witch", "gatling")
		pierce_behind(best, spot, line, reach, float(skill.hit_width), damage, "gatling")
		if hit != "miss" and shell.has("focus_per_hit"):
			arena.channel.focus_hits = int(arena.channel.focus_hits) + 1
		if hit != "miss" and shell.has("stagger_hits") and arena.enemies.has(best):
			# Suppressing fire: every few hits on one enemy stagger it hard, past the usual guard.
			var enemy: Dictionary = arena.enemies[best]
			enemy.suppressed = int(enemy.get("suppressed", 0)) + 1
			if enemy.suppressed >= int(shell.stagger_hits):
				enemy.suppressed = 0
				arena.flinch(enemy, float(shell.stagger_factor), true)
	if is_instance_valid(arena.channel.visual):
		arena.channel.visual.shoot(end)
	arena.spawn_vfx().muzzle(origin, [end], [best == ""], arena.map.ground_y(origin))
	arena.play_sfx("shotgun_fire", 1.8 if hit != "miss" else 2.0, -6.0)
	arena.last_burst = {"target": best, "result": hit, "origin": origin, "end": end, "line": line, "shots": arena.channel.shots}

func begin_shotgun_visual(target: Vector3, at_enemy: bool = false) -> void:
	arena.shotgun_assembly=Arena.ShotgunCast.new()
	arena.world.add_child(arena.shotgun_assembly)
	arena.shotgun_assembly.initialize(arena)
	arena.shotgun_assembly.global_transform=Arena.ShotgunGeometry.frame(arena,target,at_enemy)

func knock_back(id: String) -> void:
	# Shotgun Lv5+ (the firearm tree is safest at range): a hit shoves the enemy straight away.
	var skill: Dictionary = arena.rules.skills.shotgun
	if arena.config.shotgun_level < float(skill.knockback_level):
		return
	push_back(id, float(skill.knockback_distance), float(skill.knockback_seconds))

func push_back(id: String, distance: float, seconds: float, from = null) -> void:
	# Shoves the enemy straight away from her (or from `from`, the giant's fists). Heavy enemies go
	# half as far, bosses and charging brutes not at all.
	if not arena.enemies.has(id):
		return
	var enemy: Dictionary = arena.enemies[id]
	if arena.config.enemy_types[enemy.kind].has("boss") or enemy.get("charging", 0.0) > 0:
		return
	var away: Vector3 = enemy.body.position - (arena.player.position if from == null else from)
	away.y = 0.0
	if away.length() < 0.01:
		away = -arena.player_model.global_basis.z
	distance *= 0.5 if enemy.heavy else 1.0
	enemy.knockback_dir = away.normalized()
	enemy.knockback_left = distance
	enemy.knockback_speed = distance / seconds

func fire_shotgun(target: Vector3, at_enemy: bool = false) -> void:
	var shot: Transform3D=Arena.ShotgunGeometry.frame(arena,target,at_enemy)
	if not is_instance_valid(arena.shotgun_assembly): begin_shotgun_visual(target,at_enemy)
	arena.shotgun_assembly.fire(shot)
	arena.shotgun_assembly=null
	if arena.gear_total("rule:twin_barrels") > 0:
		# Unique 쌍둥이 포열핵: two narrower volleys a beat apart, each at a reduced share.
		var rule: Dictionary = arena.items.data.rule_values
		shotgun_volley(shot, float(rule.twin_factor), float(rule.twin_cone_dot))
		arena.twin_shots.append({"left": float(rule.twin_delay), "shot": shot, "factor": float(rule.twin_factor), "dot": float(rule.twin_cone_dot)})
	else:
		shotgun_volley(shot, 1.0, Arena.ShotgunGeometry.CONE_DOT)

func shotgun_volley(shot: Transform3D, factor: float, dot: float) -> void:
	var struck: Array[String]=[]
	for id in arena.enemies.keys():
		if Arena.ShotgunGeometry.contains(arena,shot,arena.enemies[id].body,dot):
			struck.append(id)
			if arena.strike(id,arena.config.shot_damage*factor,false,"witch","shotgun") != "miss":
				knock_back(id)
	var endpoints: Array[Vector3]=Arena.ShotgunGeometry.traces(arena,shot,dot)
	# Unblocked traces end on the 8m circle around the witch; shorter ones hit a wall or floor.
	var blocked: Array[bool]=[]
	for end in endpoints:
		var flat: Vector3=end-arena.player.position; flat.y=0.0
		blocked.append(flat.length()<float(arena.rules.skills.shotgun.range)-0.05)
	arena.spawn_vfx().muzzle(shot.origin,endpoints,blocked,arena.map.ground_y(shot.origin))
	arena.last_shotgun={"frame":shot,"origin":shot.origin,"direction":-shot.basis.z,"ends":endpoints,"struck":struck}
	arena.play_sfx("shotgun_fire", 0.65)

func tick_twin_shots(dt: float) -> void:
	for pending in arena.twin_shots.duplicate():
		pending.left = float(pending.left) - dt
		if pending.left <= 0.0:
			arena.twin_shots.erase(pending)
			shotgun_volley(pending.shot, float(pending.factor), float(pending.dot))

func recoil_leap(target: Vector3, direction: Vector3, at_enemy: bool) -> void:
	# Recoil leap (03 §3, firearm III, learned after the shotgun): a short wide blast shoves the
	# enemies in front away, and its kick throws her straight back. She keeps facing the aim, and
	# hits cannot stagger her mid-leap, as in the spring dash.
	var skill: Dictionary = arena.rules.skills.recoil_leap
	var shot: Transform3D = Arena.ShotgunGeometry.frame(arena, target, at_enemy)
	if not is_instance_valid(arena.shotgun_assembly):
		begin_shotgun_visual(target, at_enemy)
	arena.shotgun_assembly.fire(shot)
	arena.shotgun_assembly = null
	var struck: Array = []
	for id in arena.enemies.keys():
		var delta: Vector3 = arena.enemies[id].body.position - arena.player.position
		delta.y = 0.0
		var close: bool = delta.length() <= float(skill.range) + 0.4 * float(arena.enemies[id].size)
		if close and (delta.length() < 0.3 or delta.normalized().dot(direction) >= float(skill.blast_dot)) and arena.map.sees(arena.player.position, arena.enemies[id].body.position):
			struck.append(id)
			if arena.strike(id, float(skill.shot_damage), false, "witch", "recoil_leap") != "miss":
				push_back(id, float(skill.knockback_distance), float(skill.knockback_seconds))
	var ends: Array[Vector3] = []
	var blocked: Array[bool] = []
	for step in range(-3, 4):
		ends.append(shot.origin + direction.rotated(Vector3.UP, acos(float(skill.blast_dot)) * step / 3.0) * float(skill.range))
		blocked.append(false)
	arena.spawn_vfx().muzzle(shot.origin, ends, blocked, arena.map.ground_y(shot.origin))
	arena.play_sfx("shotgun_fire", 0.55)
	arena.shake_time = maxf(arena.shake_time, 0.1)
	# The kick carries her back as far as open floor allows.
	var back: Vector3 = -direction
	var length := 0.0
	while length + 0.2 <= float(skill.leap_distance) and arena.map.walkable(arena.player.position + back * (length + 0.2)):
		length += 0.2
	arena.moving = false
	arena.move_marker.visible = false
	var seconds: float = float(skill.leap_seconds) / leap_speed_factor()
	arena.dash = {"direction": back, "left": length, "speed": length / seconds, "visual_distance": length}
	arena.player_visual.launch_spring_jump(seconds)
	arena.last_recoil = {"struck": struck, "back": back, "leap": length, "origin": shot.origin}
