extends RefCounted
## The witch's bag grid, worn equipment, the inventory hand, sockets, salvage and rerolls (04 items).
## State (bag, equipment, held_item, pieces, coins, scrap) stays on the arena, which tests and
## windows read; this component owns the operations. Split out of arena.gd.
var arena: Arena

func _init(owner: Arena) -> void:
	arena = owner

func refresh_gear() -> void:
	# Worn items feed the build, which writes the scores and maximums combat reads.
	var worn: Array = arena.equipment.values().filter(func(item): return item != null)
	arena.gear = arena.items.totals(worn)
	arena.build.apply()
	arena.refresh_build_windows()

func bag_grid() -> Vector2i:
	return Vector2i(int(arena.items.data.bag_grid[0]), int(arena.items.data.bag_grid[1]))

func bag_index(item: Dictionary) -> int:
	for i in arena.bag.size():
		if is_same(arena.bag[i], item):
			return i
	return -1

func bag_under(cells: Rect2i, ignore = null) -> Array:
	# Bag items covering any of these cells.
	return arena.bag.filter(func(other): return not is_same(other, ignore) and other.has("at") and Rect2i(other.at, arena.items.size_of(other)).intersects(cells))

func bag_spot(item: Dictionary):
	# The first free top-left cell, column by column, or null when the item does not fit.
	var size: Vector2i = arena.items.size_of(item)
	var grid := bag_grid()
	for x in grid.x - size.x + 1:
		for y in grid.y - size.y + 1:
			if bag_under(Rect2i(Vector2i(x, y), size), item).is_empty():
				return Vector2i(x, y)
	return null

func arrange_bag() -> void:
	# Items appended without a cell take the first free one; those that cannot fit keep none.
	for item in arena.bag:
		if not item.has("at"):
			var spot = bag_spot(item)
			if spot != null:
				item.at = spot

func stow(item: Dictionary) -> bool:
	arrange_bag()
	var spot = bag_spot(item)
	if spot == null:
		return false
	item.at = spot
	arena.bag.append(item)
	return true

func equip(index: int) -> void:
	# Wears a bag item; what was worn takes its cells (same slot, same size).
	var item: Dictionary = arena.bag[index]
	arena.split_build_log()
	arena.bag.remove_at(index)
	var old = arena.equipment[item.slot]
	arena.equipment[item.slot] = item
	if old != null:
		if item.has("at"):
			old.at = item.at
			arena.bag.append(old)
		elif not stow(old):
			arena.drop_item(old, arena.player.position)
	item.erase("at")
	refresh_gear()

func unequip(slot: String) -> bool:
	if arena.equipment[slot] == null:
		return false
	var item: Dictionary = arena.equipment[slot]
	if bag_spot(item) == null:
		arena.show_message("가방에 자리가 없습니다")
		return false
	arena.split_build_log()
	arena.equipment[slot] = null
	stow(item)
	refresh_gear()
	return true

func discard(index: int) -> void:
	arena.bag.remove_at(index)
	arena.refresh_build_windows()

# The inventory window's hand: one item or one kind of name piece rides the cursor at a time.
func take_from_bag(item: Dictionary) -> void:
	if arena.held_item != null:
		return
	arena.bag.remove_at(bag_index(item))
	item.erase("at")
	arena.held_item = item
	arena.refresh_build_windows()

func put_in_bag(at: Vector2i) -> bool:
	# The held item goes down at a cell; a single item under it swaps onto the cursor.
	if arena.held_item == null:
		return false
	var cells := Rect2i(at, arena.items.size_of(arena.held_item))
	if not Rect2i(Vector2i.ZERO, bag_grid()).encloses(cells):
		return false
	var under: Array = bag_under(cells)
	if under.size() > 1:
		return false
	var item: Dictionary = arena.held_item
	arena.held_item = null
	if under.size() == 1:
		take_from_bag(under[0])
	item.at = at
	arena.bag.append(item)
	arena.refresh_build_windows()
	return true

func wear_held() -> bool:
	# The held item goes on; whatever was worn there comes onto the cursor.
	if arena.held_item == null:
		return false
	arena.split_build_log()
	var item: Dictionary = arena.held_item
	arena.held_item = arena.equipment[item.slot]
	arena.equipment[item.slot] = item
	refresh_gear()
	return true

func take_worn(slot: String) -> bool:
	if arena.equipment[slot] == null or arena.held_item != null:
		return false
	arena.split_build_log()
	arena.held_item = arena.equipment[slot]
	arena.equipment[slot] = null
	refresh_gear()
	return true

func drop_held() -> void:
	# Out of the hand onto the ground at her feet, where it can be picked up again.
	if arena.held_item == null:
		return
	var item: Dictionary = arena.held_item
	arena.held_item = null
	arena.drop_item(item, arena.player.position + Vector3(0.9, 0, 0.5))
	arena.refresh_build_windows()

func salvage_held() -> void:
	if arena.held_item == null:
		return
	salvage_item(arena.held_item)
	arena.held_item = null
	arena.refresh_build_windows()

func return_held() -> void:
	# Closing the window puts the hand back in the bag, or on the ground when it is full.
	arena.held_piece = ""
	if arena.held_item == null:
		return
	if stow(arena.held_item):
		arena.held_item = null
		arena.refresh_build_windows()
	else:
		drop_held()

func equipment_summary() -> Dictionary:
	var summary := {}
	for slot in arena.equipment:
		if arena.equipment[slot] != null:
			var worn: Dictionary = arena.equipment[slot]
			var word = arena.items.true_name(worn)
			summary[slot] = {"name": worn.name, "rarity": worn.rarity, "options": worn.options, "sockets": worn.get("sockets", 0),
				"pieces": worn.get("pieces", []), "true_name": word.id if word != null else ""}
	return summary

func is_worn(item: Dictionary) -> bool:
	return arena.equipment.values().any(func(worn): return is_same(worn, item))

func socket_into(item: Dictionary, piece: String) -> bool:
	# Into the next free socket of a worn or bag item; a full matching row wakes its true name.
	if arena.pieces.get(piece, 0) <= 0 or item.get("pieces", []).size() >= int(item.get("sockets", 0)):
		return false
	var worn := is_worn(item)
	if worn:
		arena.split_build_log()
	arena.pieces[piece] -= 1
	item.pieces.append(piece)
	# One piece per click, like a rune: the hand is empty again afterwards.
	arena.held_piece = ""
	if worn:
		refresh_gear()
	else:
		arena.refresh_build_windows()
	return true

func socket_piece(slot: String, piece: String) -> bool:
	return arena.equipment[slot] != null and socket_into(arena.equipment[slot], piece)

func unsocket(slot: String) -> bool:
	# Paid removal (04 §6): the last piece comes back intact for 각인전.
	var item = arena.equipment[slot]
	var cost: int = int(arena.items.data.crafting.unsocket_coins)
	if item == null or item.pieces.is_empty() or arena.coins < cost:
		return false
	arena.split_build_log()
	arena.coins -= cost
	arena.pieces[item.pieces.pop_back()] += 1
	refresh_gear()
	return true

func salvage_item(item: Dictionary) -> void:
	# Breaking an item down yields salvage material by rarity (04 §7); its pieces come back.
	arena.scrap += int(arena.items.data.crafting.salvage[item.rarity])
	for piece in item.get("pieces", []):
		arena.pieces[piece] += 1

func salvage(index: int) -> void:
	salvage_item(arena.bag[index])
	arena.bag.remove_at(index)
	arena.refresh_build_windows()

func salvage_below_rare() -> int:
	# Only bag equipment is eligible; worn/held items and resource stores are untouched.
	var count := 0
	for index in range(arena.bag.size() - 1, -1, -1):
		if arena.bag[index].rarity in ["normal", "magic"]:
			salvage_item(arena.bag[index])
			arena.bag.remove_at(index)
			count += 1
	arena.show_message("일반·마법 장비 %d개 분해" % count if count > 0 else "분해할 일반·마법 장비가 없습니다")
	arena.refresh_build_windows()
	return count

func reroll(slot: String, affix: int) -> bool:
	# One option of a worn item re-rolls for 각인전 and material (04 §7 trial costs).
	var item = arena.equipment[slot]
	var craft: Dictionary = arena.items.data.crafting
	if item == null or affix >= item.affixes.size() or arena.coins < int(craft.reroll_coins) or arena.scrap < int(craft.reroll_material):
		return false
	arena.split_build_log()
	arena.coins -= int(craft.reroll_coins)
	arena.scrap -= int(craft.reroll_material)
	arena.items.reroll_affix(arena.loot_rng, item, affix)
	refresh_gear()
	return true
