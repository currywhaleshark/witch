extends RefCounted
## Damage resolution (07 attributes): hit/crit rolls, attack spread, armor, passive multipliers, enemy
## flinch and interruption, bleed, and the witch's side (block, shield, hit recovery, counter block).
## force_rolls and the combat RNGs stay on the arena so tests can pin outcomes. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func hit_chance(id: String, roller: String = "witch") -> float:
	# Trial accuracy against the target's grade evasion. The witch's comes from dexterity;
	# a summon's comes from the level of the skill that built it, never from her stats (07 §2.1).
	var chance: float = (arena.config.hit_base + arena.config.hit_per_dexterity * arena.config.dexterity) * (1.0 + arena.gear_total("hit_pct") / 100.0)
	if roller != "witch":
		chance = arena.config.summon_hit_base + arena.config.summon_hit_per_level * (arena.summon_level(roller) - 1)
	return clampf(chance - arena.config.grades[arena.enemies[id].grade].evasion, arena.config.hit_min, arena.config.hit_cap)

func crit_chance(roller: String = "witch") -> float:
	if roller != "witch":
		return minf(arena.config.crit_cap, arena.config.summon_crit_base + arena.config.summon_crit_per_level * (arena.summon_level(roller) - 1))
	return minf(arena.config.crit_cap, arena.config.crit_base + arena.config.crit_per_dexterity * arena.config.dexterity + arena.gear_total("crit_pct") / 100.0)

func attack_range() -> Vector2:
	# Her attack power: the character's own base plus the worn medium's (07 §2.1). Summons do not
	# use it; their strength comes from their skill level.
	var base: Array = arena.config.build.base_attack
	return Vector2(float(base[0]) + arena.gear_total("attack_min"), float(base[1]) + arena.gear_total("attack_max"))

func attack_skew() -> float:
	# Dexterity leans each roll toward the top of the range, never all the way.
	return minf(float(arena.config.build.attack_max_skew), 1.0 + float(arena.config.build.attack_dex_skew) * float(arena.config.dexterity))

func attack_median() -> float:
	# Where the middle roll falls in the range: 0.5 at no dexterity, at most about 0.84.
	return pow(0.5, 1.0 / attack_skew())

func roll_attack(crit: bool) -> float:
	# A crit hits with the top of the range; other hits roll inside it. Scripted checks that force
	# the hit/crit rolls also pin this one (spread, 0.5 by default = the range's middle).
	var span := attack_range()
	if crit:
		return span.y
	var spot: float = float(arena.force_rolls.get("spread", 0.5)) if not arena.force_rolls.is_empty() else pow(arena.combat_rng.randf(), 1.0 / attack_skew())
	return lerpf(span.x, span.y, spot)

func attack_factor(attack: float) -> float:
	# A skill's listed damage is its damage at the reference attack (the bare character's middle
	# roll); attack_share of it grows with attack, the rest is fixed: shotgun 30 = attack x 210% + 9.
	var share: float = float(arena.config.build.attack_share)
	return share * attack / float(arena.config.build.attack_reference) + (1.0 - share)

func spread_factor(width: float) -> float:
	# Enemy and summon hits vary by +-width around their value; forced rolls keep the value.
	return 1.0 if not arena.force_rolls.is_empty() else 1.0 + width * (2.0 * arena.combat_rng.randf() - 1.0)

func armor() -> float:
	# Worn defence, plus the shield's while it is up.
	var total: float = arena.gear_total("armor")
	# The exoskeleton's guard frame also reinforces the shield, per exoskeleton level.
	if arena.shield_time > 0:
		var shield: Dictionary = arena.rules.skills.shield
		total += float(shield.armor_base) + float(shield.armor_per_level) * (float(arena.config.shield_level) - 1.0) + shield_frame_armor()
	if arena.exo_active():
		total += arena.exo_armor()
	return total

func shield_frame_armor() -> float:
	return float(arena.exo_plan().get("shield_armor_per_level", 0.0)) * arena.exo_level()

func summon_guard() -> float:
	# Share of every hit the witch's summons shrug off, from the exoskeleton's guard frame (it
	# replaced the shock-absorbing frame passive; worn or not, it reinforces them).
	return minf(0.5, float(arena.exo_plan().get("summon_guard_per_level", 0.0)) * arena.exo_level())

func armor_reduction(level: int = -1) -> float:
	# Defence against an attacker's level: the same armour turns away less from stronger enemies,
	# so old armour falls behind as the enemies' levels rise (07 §2.4).
	var attacker: int = arena.enemy_level if level < 0 else level
	var k: Array = arena.config.build.armor_k
	var value := armor()
	return minf(float(arena.config.build.armor_cap), value / maxf(0.001, value + float(k[0]) + float(k[1]) * attacker))

func strike(id: String, amount: float, accuracy_roll: bool, roller: String, source: String, look: String = "", label: String = "") -> String:
	# roller is "witch" or the summon skill ("automaton", "turret") whose level drives the rolls.
	# One direct damage event: optional hit roll, then its own crit roll (area attacks call this per enemy).
	# label, if given, is the A5 log row in place of source.
	if not arena.enemies.has(id):
		return "miss"
	amount *= passive_factor(source + ("_" + look if look != "" else ""))
	if roller == "witch":
		amount *= arena.build.power_factor() * (1.0 + arena.gear_total("damage_pct") / 100.0) * arena.skill_level_factor(source)
	if accuracy_roll and not arena.force_rolls.get("hit", arena.combat_rng.randf() < hit_chance(id, roller)):
		arena.probe.strike(source if label == "" else label, "miss", 0.0)
		return "miss"
	var crit: bool = arena.force_rolls.get("crit", arena.combat_rng.randf() < crit_chance(roller))
	amount *= attack_factor(roll_attack(crit)) if roller == "witch" else spread_factor(float(arena.config.build.summon_spread))
	var at: Vector3 = arena.enemies[id].body.position
	var size: float = arena.enemies[id].size
	var dealt: float = damage_enemy(id, amount * (arena.config.crit_multiplier if crit else 1.0))
	arena.probe.strike(source if label == "" else label, "crit" if crit else "hit", dealt)
	if roller == "witch":
		arena.leech(dealt)
	# Burst on the near surface: toward the witch and the camera, never buried inside the model.
	var toward: Vector3 = arena.player.position - at
	toward.y = 0
	var surface: Vector3 = at + Vector3.UP * 0.85 * size + toward.normalized() * 0.3 * size + arena.camera.global_basis.z * 0.6 * size
	# look only picks the impact style (the B saw); source stays the logged damage source.
	arena.spawn_vfx().impact(surface, -toward, look if look != "" else source, crit, arena.map.ground_y(at))
	if crit:
		arena.play_sfx("crit_hit", 0.55)
		arena.shake_time = 0.12
	return "crit" if crit else "hit"

func passive_factor(attack: String) -> float:
	# Passives follow the machine principle an attack uses (03 §2.1), not the tree it belongs to:
	# cutting precision also sharpens the B automaton's saw, ballistics also the turret's shots.
	# Untagged hits (staff, punches, blasts) and bleed ticks never gain from them.
	var tag: String = arena.config.attack_tags.get(attack, "")
	var factor := 1.0
	for id in arena.config.passives:
		if tag != "" and arena.config.passives[id].get("tag", "") == tag:
			factor += float(arena.config.passives[id].damage_per_level) * float(arena.config.passive_levels[id])
	# Parts add to their principle the same way (04 §3.3).
	if tag != "":
		factor += arena.gear_total("tag:" + tag) / 100.0
	return factor

func flinch_seconds(enemy: Dictionary) -> float:
	# Lighter grades flinch longer; each level the enemy stands above the witch shortens it
	# (below her, lengthens it). Bosses keep their own patterns and never flinch.
	var plan: Dictionary = arena.config.enemy_flinch
	if arena.config.enemy_types[enemy.kind].has("boss"):
		return 0.0
	var gap: float = float(arena.build.level) - float(enemy.level)
	var factor: float = clampf(1.0 + float(plan.level_step) * gap, float(plan.min_factor), float(plan.max_factor))
	return float(plan.seconds.get(enemy.grade, 0.0)) * factor

func flinch(enemy: Dictionary, scale: float = 1.0, forced: bool = false) -> void:
	# A direct hit (any source, not bleed) makes the enemy flinch: it stops where it is and loses
	# the attack it was winding up. A short guard afterwards keeps fast hits from pinning it.
	# A telegraphed brute charge, once its line is on the ground, is not broken off.
	# forced (a suppressing barrage's stagger) cuts through the guard, not through a charge.
	if (float(enemy.flinch_guard) > 0 and not forced) or float(enemy.get("charging", 0.0)) > 0:
		return
	if enemy.windup > 0 and enemy.attack == "charge":
		return
	var seconds := flinch_seconds(enemy) * scale
	if seconds <= 0:
		return
	enemy.flinch = seconds
	enemy.flinch_guard = seconds + float(arena.config.enemy_flinch.guard_seconds)
	arena.probe.counts.enemy_flinches += 1
	interrupt_attack(enemy)

func interrupt_attack(enemy: Dictionary) -> void:
	# It loses the attack it was winding up.
	if enemy.windup > 0:
		enemy.windup = 0.0
		enemy.attack = ""
		arena.probe.counts.enemy_attacks_interrupted += 1
		if enemy.model.has_method("interrupt_attack"):
			enemy.model.interrupt_attack()
		else:
			enemy.model.rotation.z = 0

func damage_enemy(id: String, amount: float, direct: bool = true) -> float:
	# Returns the HP actually removed, for the A5 log. Bleed ticks pass direct = false.
	if not arena.enemies.has(id):
		return 0.0
	var enemy: Dictionary = arena.enemies[id]
	# Trial shred: no armour formula exists yet, so shredded enemies take more direct damage.
	# Bleed ignores defence, so shred never raises it (07 §2.2).
	# Shred-strength options grow only the shred's extra share (1.25 -> 1.25 + 0.25 x option).
	var shred: float = 1.0 + (float(arena.config.shred_damage_taken) - 1.0) * (1.0 + arena.gear_total("shred_pct") / 100.0)
	var taken: float = amount * (shred if enemy.shred > 0 and direct else 1.0)
	var dealt: float = minf(maxf(enemy.hp, 0.0), taken)
	enemy.hp -= taken
	if direct:
		enemy.flash = 0.16
		flinch(enemy)
	if enemy.hp <= 0:
		# No ground ring on death: the collapse itself shows it. The falling corpse keeps neither
		# the selection outline nor the grade aura.
		arena.dress_enemy(enemy, false, false)
		if enemy.model.has_method("detach_for_death"):
			enemy.model.detach_for_death(arena.world, arena)
		enemy.body.queue_free()
		arena.enemies.erase(id)
		arena.kills += 1
		arena.drop_loot(enemy.grade, enemy.body.position)
		arena.drop_spoils(enemy.grade, enemy.body.position)
		# 「록」 in the medium and on-kill options: each kill mends a little and refills some mana,
		# whoever landed the killing blow (a summon or a bleed tick counts too).
		if arena.hp > 0:
			arena.hp = minf(arena.config.max_hp, arena.hp + arena.gear_total("life_on_kill"))
			arena.state.mana = minf(arena.state.max_mana, arena.state.mana + arena.gear_total("mana_on_kill"))
		arena.probe.counts.kills += 1
		arena.probe.grade(enemy.grade).kills += 1
		# A test boss is a one-off; everything else keeps the A5 field topped up.
		if arena.a5_mode and enemy.grade != "boss" and enemy.respawn:
			arena.respawns.append({"time": float(arena.config.a5_respawn_seconds), "kind": enemy.kind, "grade": enemy.grade})
		if arena.pending_cast.get("cursor", {}).get("enemy_id") == id:
			arena.cancel_pending_cast()
			arena.show_message("대상이 사라졌습니다")
		if arena.queued_input.get("cursor", {}).get("enemy_id") == id:
			arena.queued_input.clear()
		if arena.hold.get("enemy_id") == id:
			arena.hold.clear()
		if arena.enemies.is_empty():
			arena.cancel_pending_cast()
	return dealt

func bleed_plan(stacks: int) -> Dictionary:
	# What a new bleed gets at the chainsaw's level. Growth A raises the share of max HP; growth B
	# (chosen) lengthens the bleed at the same rate per second every level, and at every fifth level
	# lets later stacks keep more of their weight.
	var bleed: Dictionary = arena.config.bleed
	var level: int = int(arena.config.chainsaw_level) - 1
	var weights: Array = bleed.weights
	var weight: float = float(weights[mini(stacks, weights.size() - 1)])
	var ratio := 1.0
	var seconds: float = float(bleed.seconds)
	if bleed.growth == "A":
		ratio += float(bleed.a_ratio_per_level) * level
	else:
		seconds += float(bleed.b_seconds_per_level) * level
		var milestones: int = floori(float(arena.config.chainsaw_level) / float(bleed.b_weight_every))
		weight += (1.0 - weight) * minf(1.0, float(bleed.b_weight_per_milestone) * milestones)
	# Bleed duration options stretch it at the same rate per second (04 §4.3: duration, never share).
	seconds *= 1.0 + arena.gear_total("bleed_pct") / 100.0
	return {"ratio": ratio * seconds / float(bleed.seconds), "seconds": seconds, "weight": weight}

func add_bleed(id: String) -> void:
	# Up to five independent stacks per enemy, each with its own timer. A stack's total is
	# max HP x grade share x its weight, fixed when applied by how many stacks were already running;
	# a sixth bleed replaces the oldest (trial rule).
	var enemy: Dictionary = arena.enemies[id]
	var stacks: Array = enemy.bleeds
	if stacks.size() >= int(arena.config.bleed.max_stacks):
		stacks.pop_front()
	var plan: Dictionary = bleed_plan(stacks.size())
	var total: float = enemy.max_hp * float(arena.config.bleed.ratio[enemy.grade]) * plan.ratio * plan.weight
	var step: float = float(arena.config.bleed.tick_seconds)
	var ticks: int = maxi(1, ceili(plan.seconds / step - 0.00000001))
	# Keep the selected duration and rate: a 4.2s bleed has eight 0.5s ticks and a 0.2s tail.
	# All timing and damage are captured here, so later level changes do not rewrite old stacks.
	stacks.append({"left": ticks, "per_tick": total * step / plan.seconds, "clock": 0.0,
		"tick_seconds": step, "last_seconds": plan.seconds - (ticks - 1) * step})
	arena.probe.counts.bleeds_applied += 1

func tick_bleeds(dt: float) -> void:
	# Bleed is its own non-critical damage event: no hit roll, no crit, no defence, no stun.
	for id in arena.enemies.keys():
		if not arena.enemies.has(id):
			continue
		var stacks: Array = arena.enemies[id].bleeds
		var amount := 0.0
		for stack in stacks:
			stack.clock += dt
			while stack.left > 0:
				var interval: float = stack.last_seconds if stack.left == 1 else stack.tick_seconds
				if stack.clock + 0.00000001 < interval:
					break
				stack.clock = maxf(0.0, stack.clock - interval)
				stack.left -= 1
				amount += stack.per_tick * interval / stack.tick_seconds
		arena.enemies[id].bleeds = stacks.filter(func(stack): return stack.left > 0)
		if amount > 0:
			arena.probe.bleed(damage_enemy(id, amount, false))

func shield_duration() -> float:
	# Each shield level holds it up longer; at Lv10 it outlasts its own cooldown, so a fully
	# invested shield can be kept up for good by recasting.
	var shield: Dictionary = arena.rules.skills.shield
	return float(shield.duration_seconds) + float(shield.duration_per_level) * (arena.config.shield_level - 1)

func block_chance() -> float:
	# Trial formula from shield level and dexterity; it only applies while the shield is up.
	var shield: Dictionary = arena.rules.skills.shield
	var chance: float = shield.block_base + shield.block_per_level * (arena.config.shield_level - 1) + shield.block_per_dexterity * arena.config.dexterity
	return clampf(chance, 0.0, shield.block_cap)

func hit_recovery_seconds() -> float:
	# The exoskeleton shortens the stagger once every few of its levels.
	return arena.motion_seconds(arena.config.hit_recovery_seconds, arena.config.min_hit_recovery_seconds, arena.config.hit_recovery_k, arena.config.hit_recovery_score) * arena.exo_stun_factor()

func damage_player(amount: float, by_grade: String = "unknown") -> void:
	# by_grade names the attacker's grade for the A5 log; direct test calls leave it unknown.
	if arena.hp <= 0:
		return
	if arena.shield_time > 0 and arena.block_rng.randf() < block_chance():
		# A blocked hit deals nothing and never interrupts; sound and flash tell it apart.
		# The blow came from somewhere; the nearest enemy picks which side panel takes it.
		var near_id: String = arena.nearest_enemy(arena.player.position, 30.0)
		var threat: Vector3 = arena.enemies[near_id].body.position if arena.enemies.has(near_id) else arena.player.position - arena.player_model.global_basis.z
		var guard: Vector3 = arena.shield_visual.block(threat) if is_instance_valid(arena.shield_visual) else arena.player.position + Vector3.UP * 0.9
		arena.spawn_vfx().block(guard, arena.map.ground_y(arena.player.position))
		arena.play_sfx("block", 2.2)
		arena.probe.witch_hit(by_grade, 0.0, false, true)
		if arena.gear_total("rule:block_counter") > 0:
			counter_block()
		return
	# Enemy hits vary a little; her armour turns away a share by the attacker's level, then damage
	# reduction options shave the rest, at most by half.
	amount *= spread_factor(float(arena.config.build.enemy_spread)) * (1.0 - armor_reduction())
	amount *= 1.0 - minf(0.5, arena.gear_total("damage_reduction") / 100.0)
	# Only a heavy enough hit that leaves her standing stuns.
	var stunned: bool = arena.hp - amount > 0 and amount >= arena.config.max_hp * arena.config.hit_stun_min_ratio and arena.dash.is_empty()
	arena.probe.witch_hit(by_grade, minf(arena.hp, amount), stunned, false)
	if arena.gear_total("rule:exo_mana") > 0 and arena.exo_active():
		# Unique 무쇠 연골: the worn exoskeleton turns a share of every blow into mana.
		arena.state.mana = minf(arena.state.max_mana, arena.state.mana + minf(arena.hp, amount) * float(arena.items.data.rule_values.exo_mana_share))
	arena.hp = maxf(0, arena.hp - amount)
	arena.hit_time = 0.25
	arena.spawn_vfx().hurt(arena.player.position + Vector3.UP * 0.85, arena.map.ground_y(arena.player.position))
	arena.play_sfx("player_hurt", 0.75)
	if stunned:
		# Hit recovery cancels the motion, approach, click move and queued input; nothing was spent yet.
		arena.cancel_summon_assemblies("hit_stun")
		arena.windup.clear()
		arena.cancel_pending_cast()
		arena.queued_input.clear()
		arena.moving = false
		arena.move_marker.visible = false
		arena.stun_time = hit_recovery_seconds()
		arena.action_time = arena.stun_time
		arena.player_visual.hit_react(arena.stun_time)
		arena.stop_channel()
		arena.sweep.clear()
	if arena.hp == 0:
		arena.cancel_summon_assemblies("death")
		arena.stop_channel()
		arena.sweep.clear()
		arena.probe.counts.deaths += 1
		arena.save_mana_log("death")
		arena.cancel_pending_cast()
		arena.windup.clear()
		arena.hold.clear()
		arena.move_hold.clear()
		arena.queued_input.clear()
		arena.moving = false
		arena.state.active_tool = null
		arena.move_marker.visible = false
		arena.player_visual.freeze_for_death()

func counter_block() -> void:
	# Unique 반격 경첩: every block mends her a little and, at most once a second, the panels
	# shove everything close away.
	var rule: Dictionary = arena.items.data.rule_values
	arena.hp = minf(arena.config.max_hp, arena.hp + float(rule.block_life))
	arena.state.mana = minf(arena.state.max_mana, arena.state.mana + float(rule.block_mana))
	if arena.block_push_left > 0.0:
		return
	arena.block_push_left = float(rule.block_push_every)
	for id in arena.enemies.keys():
		var gap: Vector3 = arena.enemies[id].body.position - arena.player.position
		gap.y = 0.0
		if gap.length() <= float(rule.block_push_radius) + 0.4 * float(arena.enemies[id].size):
			arena.push_back(id, float(rule.block_push_distance), float(rule.block_push_seconds))
	arena.spawn_vfx().shockwave(arena.player.position, float(rule.block_push_radius), arena.map.ground_y(arena.player.position))
