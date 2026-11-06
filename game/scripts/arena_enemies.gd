extends RefCounted
## Enemies and the trial boss (05, 08 §6.2-§6.3 trial values): spawning and spacing, levels, A5
## respawns, per-enemy AI and attacks with telegraphs, magic bolts, boss sweeps/slams/frames and
## status effect visuals. The enemies dictionary stays on the arena. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func spawn_enemy(id: String, pos: Vector3, heavy: bool = false, grade: String = "normal", kind: String = "") -> void:
	# kind picks an enemy type; without one, heavy keeps the original light/heavy test dummies.
	if kind == "":
		kind = "heavy" if heavy else "light"
	var type: Dictionary = arena.config.enemy_types[kind]
	var rank: Dictionary = arena.config.grades[grade]
	var size: float = type.scale * rank.scale
	pos = free_enemy_spot(arena.map.grounded(pos), size)
	var body = Arena.Shape.body(arena.world, pos, 2)
	body.set_meta("enemy_id", id)
	var model = Arena.Shape.enemy(body, kind)
	var pick = Arena.Shape.pick_volume(body, 0.7 * size, 1.65 * size, Arena.PICK_LAYER)
	pick.set_meta("enemy_id", id)
	var maximum: float = type.hp * rank.hp * enemy_level_factor("hp", arena.enemy_level)
	arena.enemies[id] = {"body": body, "model": model, "hp": maximum, "max_hp": maximum, "heavy": type.get("heavy", false), "kind": kind, "level": arena.enemy_level,
		"grade": grade, "size": size, "cooldown": 1.0, "windup": 0.0, "attack": "", "charge_cooldown": 1.0, "charging": 0.0,
		"charge_dir": Vector3.ZERO, "charge_hit": false, "target": "", "retarget": 0.0, "slow": 0.0, "shred": 0.0, "bleeds": [], "flash": 0.0,
		"respawn": true, "timers": {}, "phases_done": [], "pattern_dir": Vector3.ZERO, "frames": [], "route": {}, "flinch": 0.0, "flinch_guard": 0.0}
	dress_enemy(arena.enemies[id], id == arena.outlined_id)

func free_enemy_spot(pos: Vector3, size: float) -> Vector3:
	# Respawns reuse a few listed spots; a newcomer steps out to the nearest free ring point
	# instead of standing inside an enemy already there, whose capsule could never push it out.
	if enemy_spot_free(pos, size):
		return pos
	for ring in range(1, 9):
		var radius: float = 0.5 * ring
		var count: int = 6 * ring
		for i in count:
			var spot: Vector3 = arena.map.grounded(pos + Vector3(radius, 0, 0).rotated(Vector3.UP, TAU * i / count))
			if arena.map.walkable(spot) and arena.map.sees(pos, spot) and enemy_spot_free(spot, size):
				return spot
	return pos

func enemy_spot_free(pos: Vector3, size: float) -> bool:
	for other in arena.enemies.values():
		var gap := Vector2(other.body.position.x - pos.x, other.body.position.z - pos.z)
		if gap.length() < maxf(0.8, Arena.ENEMY_SPACING * (other.size + size)):
			return false
	return true

func dress_enemy(enemy: Dictionary, outlined: bool, alive: bool = true) -> void:
	# One overlay chain per enemy mesh: a stencil mask of the body, then the grade aura
	# (champion/elite) and, while hovered, the selection outline, both drawn only outside that
	# mask. Render priority keeps every mask ahead of the passes that read it. Shared per combination.
	var graded: bool = Arena.AURA_COLORS.has(enemy.grade) and alive
	var key := "%s|%s" % [enemy.grade if graded else "", outlined and alive]
	if not arena.enemy_overlays.has(key):
		var passes: Array[ShaderMaterial] = []
		if graded:
			var aura := ShaderMaterial.new()
			aura.shader = Arena.AURA_SHADER
			aura.render_priority = 1
			aura.set_shader_parameter("color", Arena.AURA_COLORS[enemy.grade])
			passes.append(aura)
		if outlined and alive:
			var outline := ShaderMaterial.new()
			outline.shader = Arena.OUTLINE_SHADER
			outline.render_priority = 2
			passes.append(outline)
		var overlay: ShaderMaterial = null
		if not passes.is_empty():
			overlay = ShaderMaterial.new()
			overlay.shader = Arena.MASK_SHADER
			var last := overlay
			for next in passes:
				last.next_pass = next
				last = next
		arena.enemy_overlays[key] = overlay
	for mesh in enemy.model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = arena.enemy_overlays[key]

func tick_boss_trigger() -> void:
	# Entering the arena zone calls the map's boss once per run.
	if arena.boss_spawned or not arena.map.data.has("boss"):
		return
	var r: Array = arena.map.data.boss.trigger
	if arena.player.position.x >= r[0] and arena.player.position.x <= r[2] and arena.player.position.z >= r[1] and arena.player.position.z <= r[3]:
		arena.boss_spawned = true
		spawn_enemy("boss_field", Vector3(arena.map.data.boss.pos[0], 0, arena.map.data.boss.pos[1]), true, "boss", "latch")
		arena.show_message("보스 등장")

func call_test_boss() -> void:
	# Test tool: the boss appears in the map's boss arena (a field edge on the flat arena), and
	# only while no boss is on the field. It also stands in for the arena's own entry boss.
	if arena.enemies.values().any(func(enemy): return arena.config.enemy_types[enemy.kind].has("boss")):
		arena.show_message("이미 보스가 있습니다")
		return
	var pos: Vector3 = edge_point()
	if arena.map.data.has("boss"):
		pos = Vector3(arena.map.data.boss.pos[0], 0, arena.map.data.boss.pos[1])
		arena.boss_spawned = true
	spawn_enemy("boss_" + str(arena.boss_serial), pos, true, "boss", "latch")
	arena.boss_serial += 1
	arena.show_message("보스 등장")

func tick_respawns(dt: float) -> void:
	for entry in arena.respawns.duplicate():
		entry.time -= dt
		if entry.time > 0:
			continue
		arena.respawns.erase(entry)
		spawn_enemy("enemy_" + str(arena.spawn_serial), edge_point(), false, entry.grade, entry.kind)
		arena.spawn_serial += 1

func edge_point() -> Vector3:
	# Enter away from the witch to keep a steady engagement: field edges, or the map's listed spots.
	return arena.map.respawn_point(arena.player.position, arena.rng)

func enemy_name(id: String) -> String:
	var enemy: Dictionary = arena.enemies[id]
	return "%s %s Lv %d" % [arena.config.grades[enemy.grade].name, arena.config.enemy_types[enemy.kind].name, enemy.level]

func enemy_level_factor(kind: String, level: int) -> float:
	return 1.0 + float(arena.config.build["enemy_%s_per_level" % kind]) * (level - 1)

func set_enemy_level(value: int) -> void:
	# Living enemies keep their HP fraction; bleed, phases and stun read max HP, so they follow.
	arena.enemy_level = clampi(value, 1, int(arena.config.build.max_level))
	for id in arena.enemies:
		var enemy: Dictionary = arena.enemies[id]
		var ratio: float = enemy_level_factor("hp", arena.enemy_level) / enemy_level_factor("hp", enemy.level)
		enemy.hp *= ratio
		enemy.max_hp *= ratio
		enemy.level = arena.enemy_level

func step_enemy_level(delta: int) -> bool:
	if arena.enemy_level + delta < 1 or arena.enemy_level + delta > int(arena.config.build.max_level):
		return false
	arena.split_build_log()
	set_enemy_level(arena.enemy_level + delta)
	arena.enemy_level_linked = arena.enemy_level == arena.build.level
	return true

func link_enemy_level() -> void:
	arena.split_build_log()
	arena.enemy_level_linked = true
	set_enemy_level(arena.build.level)

func status_fx(enemy: Dictionary) -> Node3D:
	return enemy.body.get_node_or_null("StatusFx")

func sync_status_fx(enemy: Dictionary, dt: float) -> void:
	# Debuff markers (presentation only): made the first time the enemy has one, then kept so
	# they can fade out.
	var fx := status_fx(enemy)
	if fx == null:
		if not (enemy.slow > 0 or enemy.shred > 0 or not enemy.bleeds.is_empty() or float(enemy.get("stun", 0.0)) > 0 or float(enemy.get("bound", 0.0)) > 0):
			return
		fx = Arena.StatusFx.new()
		enemy.body.add_child(fx)
		fx.setup(enemy)
	fx.sync(enemy, dt)

func _tick_enemy(enemy: Dictionary, dt: float) -> void:
	if enemy.target != "" and arena.ally_by_id(enemy.target).is_empty():
		enemy.target = ""
		enemy.retarget = 0.0
	var aim: Vector3 = arena.foe_position(enemy.target)
	var delta: Vector3 = aim - enemy.body.position
	enemy.slow = maxf(0, enemy.slow - dt)
	enemy.shred = maxf(0, enemy.shred - dt)
	enemy.flash = maxf(0, enemy.flash - dt)
	enemy.model.scale = Vector3.ONE * enemy.size * (1.08 if enemy.flash > 0 else 1.0)
	enemy.flinch_guard = maxf(0, float(enemy.get("flinch_guard", 0.0)) - dt)
	enemy.stun = maxf(0, float(enemy.get("stun", 0.0)) - dt)
	enemy.bound = maxf(0, float(enemy.get("bound", 0.0)) - dt)
	enemy.winched = maxf(0, float(enemy.get("winched", 0.0)) - dt)
	if float(enemy.get("flinch", 0.0)) > 0 and enemy.get("knockback_left", 0.0) <= 0.0:
		# Flinching: it stands still and starts nothing until it recovers.
		enemy.flinch = maxf(0, float(enemy.flinch) - dt)
		enemy.body.velocity = Vector3.ZERO
		return
	if enemy.get("knockback_left", 0.0) > 0.0:
		# Knocked back: it slides away and neither steers nor advances its attack meanwhile.
		var travel: float = minf(enemy.knockback_speed * dt, enemy.knockback_left)
		enemy.body.velocity = enemy.knockback_dir * travel / dt
		enemy.body.move_and_slide()
		enemy.knockback_left -= travel
		return
	if enemy.stun > 0 or enemy.bound > 0:
		# Stunned by a press or bound by the winch / a device: it stands still and starts nothing.
		enemy.body.velocity = Vector3.ZERO
		return
	var type: Dictionary = arena.config.enemy_types[enemy.kind]
	var power: float = arena.config.grades[enemy.grade].damage * enemy_level_factor("damage", enemy.level)
	var pace: float = arena.config.enemy_speed * type.speed * arena.config.grades[enemy.grade].speed * (arena.slow_factor() if enemy.slow > 0 else 1.0)
	if type.has("boss"):
		tick_boss(enemy, type.boss, power, pace, dt)
		return
	enemy.charge_cooldown = maxf(0, enemy.charge_cooldown - dt)
	if enemy.charging > 0:
		# Brute charge: a straight dash along the telegraphed line that hits the witch at most once.
		var charge: Dictionary = type.charge
		enemy.charging = maxf(0, enemy.charging - dt)
		enemy.body.velocity = enemy.charge_dir * arena.config.enemy_speed * charge.speed_factor * (arena.slow_factor() if enemy.slow > 0 else 1.0)
		enemy.body.move_and_slide()
		var dust = enemy.body.get_meta("charge_vfx", null)
		if is_instance_valid(dust):
			dust.dust_trail(enemy.body.position)
		var struck: String = arena.foe_in_reach(enemy.body.position, charge.reach) if not enemy.charge_hit else "none"
		if struck != "none":
			enemy.charge_hit = true
			enemy.charging = 0.0
			arena.hit_foe(struck, charge.damage * power, enemy.grade)
		return
	if enemy.windup > 0:
		enemy.windup -= dt
		if not enemy.model.has_method("sync_enemy"):
			enemy.model.rotation.z = sin(enemy.windup * 35) * 0.12
		if enemy.windup <= 0:
			enemy.model.rotation.z = 0
			enemy.cooldown = type.cooldown
			match enemy.attack:
				"bolt": fire_bolt(enemy, aim, type.ranged, type.damage * power)
				"charge":
					enemy.charge_cooldown = type.charge.cooldown
					enemy.charging = type.charge.distance / maxf(0.01, arena.config.enemy_speed * type.charge.speed_factor)
					enemy.charge_hit = false
					var dust = arena.spawn_vfx()
					dust.dust_trail(enemy.body.position)
					enemy.body.set_meta("charge_vfx", dust)
				_:
					arena.spawn_vfx().claw(enemy.body.position, aim - enemy.body.position, float(type.reach), Color(1.0, 0.42, 0.3) if enemy.kind != "brute" else Color(1.0, 0.6, 0.35), enemy.kind == "brute", arena.map.ground_y(enemy.body.position))
					# Reach and stop distances are absolute: capsules keep bodies apart regardless of model size.
					if delta.length() < type.reach and arena.map.sees(enemy.body.position, aim):
						arena.hit_foe(enemy.target, type.damage * power, enemy.grade)
		return
	enemy.cooldown = maxf(0, enemy.cooldown - dt)
	var hidden := arena.blinded(enemy)
	if not hidden:
		enemy.last_seen = arena.player.position
	elif enemy.target == "":
		# She vanished into smoke: a summon in sight draws it at once.
		enemy.target = arena.nearest_foe(enemy)
		enemy.retarget = arena.config.aggro_retarget_seconds
		aim = arena.foe_position(enemy.target)
		delta = aim - enemy.body.position
	# Pick a target only between attacks; a wound-up attack keeps the one it started on.
	enemy.retarget = maxf(0, enemy.retarget - dt)
	if enemy.retarget <= 0:
		enemy.target = arena.nearest_foe(enemy)
		enemy.retarget = arena.config.aggro_retarget_seconds
		aim = arena.foe_position(enemy.target)
		delta = aim - enemy.body.position
	if enemy.target == "" and hidden:
		# Lost in the smoke: it gropes slowly toward where it last saw her and starts nothing.
		var seen: Vector3 = enemy.get("last_seen", enemy.body.position)
		var toward: Vector3 = seen - enemy.body.position
		toward.y = 0.0
		enemy.body.velocity = Vector3.ZERO
		if toward.length() > 0.5:
			var grope: Vector3 = arena.follow(enemy.route, enemy.body.position, seen, 0.35, dt) - enemy.body.position
			grope.y = 0.0
			enemy.body.velocity = grope.normalized() * pace * float(arena.rules.skills.smoke_launcher.blind_speed)
			enemy.model.look_at(Vector3(seen.x, enemy.body.global_position.y, seen.z))
		enemy.body.move_and_slide()
		return
	var distance: float = delta.length()
	if distance > 11:
		return
	enemy.model.look_at(Vector3(aim.x, enemy.body.global_position.y, aim.z))
	if type.has("ranged"):
		# Wire crows hold a firing band: back off when crowded, close in when too far, shoot between.
		var band: Dictionary = type.ranged
		var clear: bool = arena.map.sees(enemy.body.position, aim)
		var step = Vector3.ZERO
		if distance > band.keep_max or not clear:
			# Without a clear shot the crow walks the route until one opens.
			step = (arena.follow(enemy.route, enemy.body.position, aim, 0.35, dt) - enemy.body.position).normalized()
		elif distance < band.keep_min:
			step = -delta.normalized()
		enemy.body.velocity = step * pace
		enemy.body.move_and_slide()
		if enemy.cooldown <= 0 and distance <= band.bolt_range and clear:
			start_enemy_attack(enemy, "bolt", type.windup, Arena.TEAL)
		return
	var in_sight: bool = arena.map.sees(enemy.body.position, aim)
	if type.has("charge") and enemy.charge_cooldown <= 0 and enemy.cooldown <= 0 and distance >= type.charge.min and distance <= type.charge.max and in_sight:
		enemy.charge_dir = Vector3(delta.x, 0, delta.z).normalized()
		start_enemy_attack(enemy, "charge", type.charge.windup, Arena.RED)
		telegraph(enemy.body.position, enemy.charge_dir, type.charge.distance, type.charge.width, type.charge.windup)
		return
	if distance > type.stop or not in_sight:
		# Chase along the route so corners and low walls are walked around, not into.
		var step: Vector3 = arena.follow(enemy.route, enemy.body.position, aim, 0.35, dt) - enemy.body.position
		step.y = 0
		enemy.body.velocity = step.normalized() * pace
		enemy.body.move_and_slide()
	elif enemy.cooldown <= 0:
		start_enemy_attack(enemy, "melee", type.windup, Arena.RED)

func tick_boss(enemy: Dictionary, plan: Dictionary, power: float, pace: float, dt: float) -> void:
	# 08 §6.3 trial boss: sweep then slam up close, door-frame crossfire at range,
	# and a shockwave that calls adds at each HP mark. Every attack is telegraphed on the ground.
	for key in enemy.timers.keys():
		enemy.timers[key] = maxf(0, enemy.timers[key] - dt)
	if enemy.windup > 0:
		enemy.windup -= dt
		if not enemy.model.has_method("sync_enemy"):
			enemy.model.rotation.z = sin(enemy.windup * 22) * 0.06
		if enemy.windup <= 0:
			enemy.model.rotation.z = 0
			resolve_boss(enemy, plan, power)
		return
	for mark in plan.shockwave.marks:
		if enemy.hp <= enemy.max_hp * mark and not enemy.phases_done.has(mark):
			enemy.phases_done.append(mark)
			begin_boss(enemy, "shockwave", plan.shockwave.windup)
			disc_warning(enemy.body.position, plan.shockwave.radius, plan.shockwave.windup)
			return
	enemy.retarget = maxf(0, enemy.retarget - dt)
	if enemy.retarget <= 0:
		enemy.target = arena.nearest_foe(enemy)
		enemy.retarget = arena.config.aggro_retarget_seconds
	var aim: Vector3 = arena.foe_position(enemy.target)
	var delta: Vector3 = aim - enemy.body.position
	delta.y = 0
	var distance: float = delta.length()
	if distance > 14:
		return
	enemy.model.look_at(Vector3(aim.x, enemy.body.global_position.y, aim.z))
	enemy.pattern_dir = delta.normalized() if distance > 0.01 else Vector3.FORWARD
	var clear: bool = arena.map.sees(enemy.body.position, aim)
	if distance <= plan.sweep.range and enemy.timers.get("sweep", 0.0) <= 0 and clear:
		begin_boss(enemy, "sweep", plan.sweep.windup)
		fan_warning(enemy.body.position, enemy.pattern_dir, plan.sweep.range, plan.sweep.angle, plan.sweep.windup)
	elif distance <= plan.slam.length and enemy.timers.get("slam", 0.0) <= 0 and clear:
		begin_slam(enemy, plan)
	elif distance > plan.sweep.range and enemy.timers.get("frames", 0.0) <= 0:
		begin_frames(enemy, plan, aim)
	elif distance > plan.keep or not clear:
		var step: Vector3 = arena.follow(enemy.route, enemy.body.position, aim, 0.4, dt) - enemy.body.position
		step.y = 0
		enemy.body.velocity = step.normalized() * pace
		enemy.body.move_and_slide()

func begin_boss(enemy: Dictionary, pattern: String, windup: float) -> void:
	enemy.attack = pattern
	enemy.windup = windup
	if enemy.model.has_method("begin_attack"):
		enemy.model.begin_attack(pattern, windup)
	arena.spawn_vfx().tell(enemy.body.position + Vector3.UP * 2.0, Color(1.0, 0.5, 0.3), 2.0)

func begin_slam(enemy: Dictionary, plan: Dictionary, extra: float = 0.0) -> void:
	# extra: the slam that follows a sweep waits longer, so a witch stunned by the sweep can still step out.
	begin_boss(enemy, "slam", plan.slam.windup + extra)
	telegraph(enemy.body.position, enemy.pattern_dir, plan.slam.length, plan.slam.width, plan.slam.windup + extra)

func begin_frames(enemy: Dictionary, plan: Dictionary, aim: Vector3) -> void:
	# Two hovering door frames open beside the target; the shots come out of them, not the boss.
	begin_boss(enemy, "frames", plan.frames.windup)
	var side: Vector3 = enemy.pattern_dir.cross(Vector3.UP).normalized()
	enemy.frames = []
	for sign_x in [-1.0, 1.0]:
		var spot: Vector3 = aim + side * sign_x * plan.frames.offset
		spot.x = clampf(spot.x, arena.map.bounds.position.x + 0.75, arena.map.bounds.end.x - 0.75)
		spot.z = clampf(spot.z, arena.map.bounds.position.y + 0.75, arena.map.bounds.end.y - 0.75)
		enemy.frames.append(spot)
		var frame: Node3D = Arena.Shape.door_frame(arena.world, spot, Color("8a6a3a"))
		frame.look_at(Vector3(aim.x, spot.y, aim.z))
		if frame.has_method("configure"):
			frame.configure(plan.frames.windup)
		arena.effects.append({"node": frame, "life": plan.frames.windup + 0.35, "grow": false})
		# Ground lane from the frame to the target spot, so the side threat reads before the shot.
		var lane: Vector3 = Vector3(aim.x, 0, aim.z) - Vector3(spot.x, 0, spot.z)
		telegraph(Vector3(spot.x, 0, spot.z), lane.normalized(), lane.length() + 1.0, 0.6, plan.frames.windup)

func boss_area_hit(enemy: Dictionary, inside: Callable, damage: float) -> void:
	# Area patterns hit the witch and every summon standing in the warned shape.
	if arena.hp > 0 and inside.call(arena.player.position):
		arena.damage_player(damage, enemy.grade)
	for ally in arena.allies.duplicate():
		if inside.call(ally.node.position):
			arena.damage_ally(ally, damage, enemy.grade)

func resolve_boss(enemy: Dictionary, plan: Dictionary, power: float) -> void:
	var origin: Vector3 = enemy.body.position
	var facing: Vector3 = enemy.pattern_dir
	if enemy.model.has_method("release_attack"):
		enemy.model.release_attack(enemy.attack)
	match enemy.attack:
		"sweep":
			var sweep: Dictionary = plan.sweep
			enemy.timers.sweep = sweep.cooldown
			var in_fan := func(at: Vector3) -> bool:
				var flat: Vector3 = at - origin
				flat.y = 0
				return flat.length() <= sweep.range and (flat.length() < 0.01 or rad_to_deg(facing.angle_to(flat.normalized())) <= sweep.angle / 2.0)
			boss_area_hit(enemy, in_fan, sweep.damage * power)
			arena.spawn_vfx().fan_slash(origin, facing, float(sweep.range), float(sweep.angle), arena.map.ground_y(origin))
			arena.play_sfx("boss_sweep", 0.5)
			# The lock comes down right after the sweep along the same facing.
			if enemy.timers.get("slam", 0.0) <= 0:
				begin_slam(enemy, plan, plan.slam.chain_extra)
		"slam":
			var slam: Dictionary = plan.slam
			enemy.timers.slam = slam.cooldown
			var in_line := func(at: Vector3) -> bool:
				var flat: Vector3 = at - origin
				flat.y = 0
				var along: float = flat.dot(facing)
				return along >= 0 and along <= slam.length and absf(flat.dot(facing.cross(Vector3.UP))) <= slam.width / 2.0
			boss_area_hit(enemy, in_line, slam.damage * power)
			arena.spawn_vfx().slam(origin, facing, float(slam.length), float(slam.width), arena.map.ground_y(origin))
			arena.shake_time = maxf(arena.shake_time, 0.16)
			arena.play_sfx("boss_slam", 0.4)
		"frames":
			var frames: Dictionary = plan.frames
			enemy.timers.frames = frames.cooldown
			for spot in enemy.frames:
				fire_bolt_from(spot, arena.foe_position(enemy.target), frames, frames.damage * power, enemy.grade)
		"shockwave":
			var wave: Dictionary = plan.shockwave
			var in_disc := func(at: Vector3) -> bool:
				var flat: Vector3 = at - origin
				flat.y = 0
				return flat.length() <= wave.radius
			boss_area_hit(enemy, in_disc, wave.damage * power)
			arena.spawn_vfx().shockwave(origin, float(wave.radius), arena.map.ground_y(origin))
			arena.shake_time = maxf(arena.shake_time, 0.22)
			arena.play_sfx("boss_shockwave", 0.35)
			# Called adds join from the field edges and never respawn in A5 mode.
			for kind in wave.adds:
				for i in int(wave.adds[kind]):
					var add_id: String = "add_" + str(arena.spawn_serial)
					arena.spawn_serial += 1
					spawn_enemy(add_id, edge_point(), false, "normal", kind)
					arena.enemies[add_id].respawn = false

func fan_warning(from: Vector3, facing: Vector3, radius: float, angle: float, life: float) -> void:
	for filled in [false, true]:
		var fan: MeshInstance3D = Arena.Shape.fan(arena.world, from + Vector3(0, 0.04 if filled else 0.03, 0), radius, angle, Arena.WARN_FILL if filled else Arena.WARN)
		fan.material_override = arena.warning_material(filled, 0, radius, 1.0, deg_to_rad(angle) / 2.0)
		fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fan.look_at(fan.position + facing)
		warn_effect(fan, life, filled, "radial")

func disc_warning(at: Vector3, radius: float, life: float) -> void:
	for filled in [false, true]:
		var disc: MeshInstance3D = Arena.Shape.cylinder(arena.world, at + Vector3(0, 0.04 if filled else 0.03, 0), radius, 0.02, Arena.WARN_FILL if filled else Arena.WARN)
		disc.material_override = arena.warning_material(filled, 0, radius)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		warn_effect(disc, life, filled, "radial")

func start_enemy_attack(enemy: Dictionary, attack: String, windup: float, color: Color) -> void:
	enemy.attack = attack
	enemy.windup = windup
	if enemy.model.has_method("begin_attack"):
		enemy.model.begin_attack(attack, windup)
	arena.spawn_vfx().tell(enemy.body.position + Vector3.UP * 1.25 * enemy.size, color, enemy.size)

func telegraph(from: Vector3, direction: Vector3, length: float, width: float, life: float) -> void:
	# Flat warning strip on the ground; a brighter strip fills it from the attacker outwards.
	for filled in [false, true]:
		var pivot = Node3D.new()
		arena.world.add_child(pivot)
		pivot.position = from + Vector3(0, 0.04 if filled else 0.03, 0)
		pivot.look_at(pivot.position + direction)
		var strip: MeshInstance3D = Arena.Shape.box(pivot, Vector3(0, 0, -length / 2), Vector3(width, 0.02, length), Arena.WARN_FILL if filled else Arena.WARN)
		strip.material_override = arena.warning_material(filled, 1, length, width)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		warn_effect(pivot, life, filled, "length")

func warn_effect(node: Node3D, life: float, filled: bool, axis: String) -> void:
	var fx = {"node": node, "life": life, "grow": false}
	if filled:
		fx.merge({"fill": life, "axis": axis})
		node.scale = Vector3(0.02, 1, 0.02) if axis == "radial" else Vector3(1, 1, 0.02)
	arena.effects.append(fx)

func fire_bolt(enemy: Dictionary, at: Vector3, band: Dictionary, damage: float) -> void:
	# The orb flies toward where its target stands at release, so stepping aside dodges it.
	fire_bolt_from(enemy.body.position + Vector3.UP * 1.0 * enemy.size, at, band, damage, enemy.grade)

func fire_bolt_from(origin: Vector3, at: Vector3, band: Dictionary, damage: float, grade: String) -> void:
	# Orbs fly at sight height above the shooter's ground: over low walls, into tall ones.
	origin.y = arena.map.ground_y(origin) + Arena.FieldMap.SIGHT_HEIGHT
	var aim: Vector3 = at - origin
	aim.y = 0
	var node = Arena.Shape.sphere(arena.world, origin, 0.12, Color("e6f6ff"))
	node.material_override = Arena.Shape.material(Color("e6f6ff"), true)
	node.material_override.emission_energy_multiplier = 2.2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail = arena.spawn_vfx()
	trail.bolt_trail(origin, Arena.BOLT_GLOW)
	arena.bolts.append({"node": node, "dir": aim.normalized(), "speed": float(band.bolt_speed), "left": float(band.bolt_range),
		"radius": float(band.bolt_radius), "damage": damage, "grade": grade, "trail": trail})
	arena.play_sfx("enemy_bolt", 1.9)

func tick_bolts(dt: float) -> void:
	for bolt in arena.bolts.duplicate():
		var travel: float = bolt.speed * dt
		var before: Vector3 = bolt.node.position
		bolt.node.position += bolt.dir * travel
		if is_instance_valid(bolt.trail):
			bolt.trail.bolt_trail(bolt.node.position, Arena.BOLT_GLOW)
		if not arena.map.clear(before, bolt.node.position):
			if is_instance_valid(bolt.trail):
				bolt.trail.burst(before, Arena.BOLT_GLOW, arena.map.ground_y(before))
			bolt.left = 0
		bolt.left -= travel
		var struck: String = arena.foe_in_reach(bolt.node.position, bolt.radius)
		if struck != "none":
			if is_instance_valid(bolt.trail):
				bolt.trail.burst(bolt.node.position, Arena.BOLT_GLOW, arena.map.ground_y(bolt.node.position))
			arena.hit_foe(struck, bolt.damage, bolt.grade)
			bolt.left = 0
		if bolt.left <= 0 or not arena.map.bounds.grow(1.0).has_point(Vector2(bolt.node.position.x, bolt.node.position.z)):
			bolt.node.queue_free()
			arena.bolts.erase(bolt)
