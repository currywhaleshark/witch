extends RefCounted
## Potions (02 §3, 04 §8): the potion bag cells, four quickslots, buying, drinking, cooldowns and
## the running heal/mana effects. Stash, cells and slots stay on the arena. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func potion_cooldown(id: String) -> float:
	var longest = 0.0
	for group in arena.config.potions[id].groups:
		longest = maxf(longest, arena.potion_cooldowns.get(group, 0.0))
	return longest

func drink(index: int) -> void:
	# Drinking is instant and never waits for or cancels a motion, approach or hit recovery.
	var slot: Dictionary = arena.potion_slots[index]
	if slot.count <= 0:
		return
	var potion: Dictionary = arena.config.potions[slot.id]
	if potion_cooldown(slot.id) > 0:
		arena.show_message("물약 준비 중입니다")
		return
	slot.count -= 1
	for group in potion.groups:
		arena.potion_cooldowns[group] = float(potion.cooldown_seconds)
	var seconds: float = potion.seconds
	if potion.kind == "speed":
		arena.speed_buff = seconds
	else:
		var full: bool = potion.get("full", false)
		arena.potion_effects.append({"time": seconds,
			"hp_rate": (arena.config.max_hp if full else potion.get("hp", 0.0) * potion_factor()) / seconds if potion.kind != "mp" else 0.0,
			"mp_rate": (arena.state.max_mana if full else potion.get("mp", 0.0) * potion_factor()) / seconds if potion.kind != "hp" else 0.0})
	arena.probe.potions[slot.id] = arena.probe.potions.get(slot.id, 0) + 1
	# A light in the potion colour around the witch tells which potion was drunk.
	arena.spawn_vfx().potion_glow(arena.player.position, {"hp": Color(1.0, 0.32, 0.28), "mp": Color(0.35, 0.85, 1.0), "both": Color(0.82, 0.55, 1.0), "speed": Color(0.62, 1.0, 0.38)}[potion.kind], arena.map.ground_y(arena.player.position))
	arena.play_sfx("potion_drink", 1.4)

func arrange_potions() -> void:
	# Counts stay in the stash; this fixed grid remembers where each nonempty kind lives.
	while arena.potion_cells.size() < Arena.POTION_BAG_CAPACITY:
		arena.potion_cells.append("")
	for index in arena.potion_cells.size():
		if arena.potion_stash.get(arena.potion_cells[index], 0) <= 0:
			arena.potion_cells[index] = ""
	for id in arena.potion_stash:
		if arena.potion_stash[id] > 0 and not arena.potion_cells.has(id):
			var empty := arena.potion_cells.find("")
			if empty >= 0:
				arena.potion_cells[empty] = id

func store_potion(id: String, count: int) -> bool:
	arrange_potions()
	if not arena.config.potions.has(id) or count <= 0:
		return false
	if not arena.potion_cells.has(id):
		var empty := arena.potion_cells.find("")
		if empty < 0:
			return false
		arena.potion_cells[empty] = id
	arena.potion_stash[id] = int(arena.potion_stash.get(id, 0)) + count
	return true

func move_potion_cell(from: int, to: int) -> void:
	var old: String = arena.potion_cells[to]
	arena.potion_cells[to] = arena.potion_cells[from]
	arena.potion_cells[from] = old
	arena.refresh_build_windows()

func put_quickslot_in_bag(index: int, cell: int) -> bool:
	arrange_potions()
	var slot: Dictionary = arena.potion_slots[index]
	if slot.count <= 0:
		return false
	var target: String = arena.potion_cells[cell]
	if target != "" and target != slot.id:
		return assign_quickslot(index, target)
	var existing := arena.potion_cells.find(slot.id)
	if not store_potion(slot.id, slot.count):
		return false
	if existing < 0:
		arena.potion_cells[arena.potion_cells.find(slot.id)] = ""
		arena.potion_cells[cell] = slot.id
	slot.count = 0
	arena.refresh_build_windows()
	return true

func move_potion_quickslot(from: int, to: int) -> void:
	if from != to:
		if arena.potion_slots[from].id == arena.potion_slots[to].id:
			arena.potion_slots[to].count += arena.potion_slots[from].count
			arena.potion_slots[from].count = 0
		else:
			var old: Dictionary = arena.potion_slots[to]
			arena.potion_slots[to] = arena.potion_slots[from]
			arena.potion_slots[from] = old
	arena.refresh_build_windows()

func buy_potion(id: String) -> bool:
	# Trial shop in the inventory: full-restore potions are drop-only (04 §8.2).
	var price: int = int(arena.items.data.potion_prices.get(id, 0))
	if price <= 0 or arena.coins < price:
		return false
	if not store_potion(id, 1):
		arena.show_message("물약 가방에 자리가 없습니다")
		return false
	arena.coins -= price
	arena.refresh_build_windows()
	return true

func assign_quickslot(index: int, id: String) -> bool:
	# The slot's potions go back to the stash and the chosen kind's whole stack moves in.
	arrange_potions()
	var slot: Dictionary = arena.potion_slots[index]
	var source := arena.potion_cells.find(id)
	if slot.count > 0 and not arena.potion_cells.has(slot.id) and source < 0 and not arena.potion_cells.has(""):
		return false
	arena.potion_stash[slot.id] += slot.count
	if source >= 0 and slot.id != id:
		arena.potion_cells[source] = slot.id if slot.count > 0 and not arena.potion_cells.has(slot.id) else ""
	slot.id = id
	slot.count = arena.potion_stash[id]
	arena.potion_stash[id] = 0
	arrange_potions()
	arena.refresh_build_windows()
	return true

func fill_quickslot(index: int) -> void:
	var slot: Dictionary = arena.potion_slots[index]
	slot.count += arena.potion_stash[slot.id]
	arena.potion_stash[slot.id] = 0
	arrange_potions()
	arena.refresh_build_windows()

func potion_factor() -> float:
	# 「록」 on accessories and 「록샤」 raise how much an ordinary potion restores.
	return 1.0 + arena.gear_total("potion_pct") / 100.0

func cycle_potion(index: int) -> void:
	# Test tool: Shift+1-4 swaps that slot's potion type and restocks it.
	var ids: Array = arena.config.potions.keys()
	var slot: Dictionary = arena.potion_slots[index]
	slot.id = ids[(ids.find(slot.id) + 1) % ids.size()]
	slot.count = int(arena.config.potion_test_count)
	arena.show_message("%d번: %s ×%d" % [index + 1, arena.config.potions[slot.id].name, slot.count])

func tick_potions(dt: float) -> void:
	for group in arena.potion_cooldowns.keys():
		arena.potion_cooldowns[group] = maxf(0, arena.potion_cooldowns[group] - dt)
	arena.speed_buff = maxf(0, arena.speed_buff - dt)
	for effect in arena.potion_effects.duplicate():
		var spent: float = minf(dt, effect.time)
		arena.hp = minf(arena.config.max_hp, arena.hp + effect.hp_rate * spent)
		var drunk: Dictionary = arena.rules.restore_mana(arena.state, effect.mp_rate * spent)
		arena.state = drunk.state
		arena.probe.mana_gain("potions", drunk.events[0].amount)
		effect.time -= spent
		if effect.time <= 0:
			arena.potion_effects.erase(effect)

func pending_fill(key: String) -> float:
	# What running potions will still add; the HUD shows it as a pale layer.
	var total = 0.0
	for effect in arena.potion_effects:
		total += effect[key] * effect.time
	return total
