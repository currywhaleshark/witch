extends RefCounted
## C4-C6 trial items (04 §2-§4): bases, four rarities, prefix/suffix options in tiers I-III,
## the machinery witch's blueprints and parts, two uniques and drop tables. Pure data and rolls;
## the arena owns what lies on the field, the bag and the equipped slots.
var data: Dictionary
var bases: Dictionary = {}
var affixes: Dictionary = {}
var uniques: Dictionary = {}

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for base in data.bases:
		bases[base.id] = base
	for affix in data.affixes:
		affixes[affix.id] = affix
	for unique in data.uniques:
		uniques[unique.id] = unique

func tier_for(level: int) -> int:
	# The highest option tier this item level opens: I from 1, II from 12, III from 24.
	var tier := 0
	for i in data.tier_levels.size():
		if level >= int(data.tier_levels[i]):
			tier = i
	return tier

func weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for key in weights:
		total += float(weights[key])
	var pick: float = rng.randf() * total
	for key in weights:
		pick -= float(weights[key])
		if pick < 0.0:
			return key
	return weights.keys()[-1]

func shuffled(rng: RandomNumberGenerator, items: Array) -> Array:
	var result: Array = items.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var held = result[i]
		result[i] = result[j]
		result[j] = held
	return result

func generate(rng: RandomNumberGenerator, level: int, rarity: String, slot: String = "") -> Dictionary:
	if rarity == "unique":
		return make_unique(rng, level)
	if slot == "":
		slot = data.slots[rng.randi_range(0, data.slots.size() - 1)]
	var pool: Array = data.bases.filter(func(b): return b.slot == slot and level >= int(b.min_level))
	var base: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var top: int = tier_for(level)
	# Sockets roll 0 up to the base's maximum when the item drops (04 §6).
	var item := {"base": base.id, "slot": slot, "rarity": rarity, "level": level, "options": {}, "affixes": [], "name": "",
		"sockets": rng.randi_range(0, int(base.get("socket_max", 0))), "pieces": []}
	# A blueprint or part always carries its base option, sized by the item level.
	for key in base.get("implicit", {}):
		item.options[key] = int(base.implicit[key][top])
	# Counts are [fewest, most, most of one kind]: magic 1-2 with at most one prefix and one
	# suffix, rare 3-5 with at most three of each. No option appears twice on one item.
	var counts: Array = data.affix_counts.get(rarity, [0, 0, 0])
	var wanted: int = rng.randi_range(int(counts[0]), int(counts[1]))
	var kinds := {"prefix": 0, "suffix": 0}
	for affix in shuffled(rng, data.affixes.filter(func(a): return slot in a.slots)):
		if item.affixes.size() >= wanted:
			break
		if kinds[affix.kind] >= int(counts[2]):
			continue
		kinds[affix.kind] += 1
		var tier: int = rng.randi_range(0, top)
		var span: Array = affix.tiers[tier]
		var value: int = rng.randi_range(int(span[0]), int(span[1]))
		item.affixes.append({"id": affix.id, "kind": affix.kind, "tier": tier, "value": value})
		item.options[affix.id] = int(item.options.get(affix.id, 0)) + value
	item.name = name_for(rng, item, base)
	return item

func make_unique(rng: RandomNumberGenerator, level: int, id: String = "") -> Dictionary:
	if id == "":
		id = uniques.keys()[rng.randi_range(0, uniques.size() - 1)]
	var unique: Dictionary = uniques[id]
	var base: Dictionary = bases[unique.base]
	return {"base": base.id, "slot": base.slot, "rarity": "unique", "level": level, "options": unique.options.duplicate(),
		"affixes": [], "name": unique.name, "unique": id, "rule": unique.rule, "sockets": 0, "pieces": []}

func name_for(rng: RandomNumberGenerator, item: Dictionary, base: Dictionary) -> String:
	match item.rarity:
		"magic":
			# 04 §4.4: "[suffix]의 [prefix] [base]", leaving out whichever side is missing.
			var parts: Array = []
			for kind in ["suffix", "prefix"]:
				for affix in item.affixes:
					if affix.kind == kind:
						parts.append(affixes[affix.id].words[affix.tier])
			parts.append(base.name)
			return " ".join(parts)
		"rare":
			var words: Array = data.rare_words
			return "%s %s" % [words[0][rng.randi_range(0, words[0].size() - 1)], words[1][rng.randi_range(0, words[1].size() - 1)]]
	return base.name

func option_text(key: String, value: int) -> String:
	if data.implicit_labels.has(key):
		return data.implicit_labels[key] % value
	return affixes[key].label % value

func display_name(item: Dictionary) -> String:
	# A woken true name leads the item's name, the way the pieces spell it out on the item.
	var word = true_name(item)
	return "%s %s" % [word.name, item.name] if word != null else item.name

func size_of(item: Dictionary) -> Vector2i:
	# Bag cells an item takes, by the slot it is worn in.
	var span: Array = data.slot_sizes[item.slot]
	return Vector2i(int(span[0]), int(span[1]))

func glyph(piece: String) -> String:
	# The syllable a name piece carries, for its icon: 「록」 조각 -> 록.
	var name: String = data.pieces[piece].name
	return name.substr(name.find("「") + 1, name.find("」") - name.find("「") - 1)

func describe(item: Dictionary) -> PackedStringArray:
	var base: Dictionary = bases[item.base]
	var lines := PackedStringArray([display_name(item)])
	var kind: Array = [data.rarity_names[item.rarity]]
	if item.name != base.name:
		kind.append(base.name)
	kind.append_array([data.slot_names[item.slot], "아이템 레벨 %d" % item.level])
	lines.append(" · ".join(kind))
	var stats := base_stats(item)
	if stats.has("attack_min"):
		lines.append("공격력 %d~%d" % [stats.attack_min, stats.attack_max])
	if stats.has("armor"):
		lines.append("방어력 %d" % stats.armor)
	for key in base.get("implicit", {}):
		if item.options.has(key) and item.rarity != "unique":
			lines.append("기본: " + option_text(key, base.implicit[key][tier_for(item.level)]))
	for affix in item.affixes:
		lines.append("%s %s" % [["I", "II", "III"][affix.tier], option_text(affix.id, affix.value)])
	if item.rarity == "unique":
		for key in item.options:
			lines.append(option_text(key, item.options[key]))
		lines.append("고유: " + uniques[item.unique].rule_text)
	if int(item.get("sockets", 0)) > 0:
		var group: String = data.slot_groups[item.slot]
		var filled: Array = []
		for piece in item.pieces:
			filled.append(data.pieces[piece].name)
		lines.append(("소켓 %d/%d %s" % [item.pieces.size(), item.sockets, " ".join(filled)]).strip_edges())
		for piece in item.pieces:
			for key in data.pieces[piece][group]:
				lines.append("  %s: %s" % [data.pieces[piece].name, option_text(key, data.pieces[piece][group][key])])
		var word = true_name(item)
		if word != null:
			lines.append("진명 복원 %s (%s):" % [word.name, word.meaning])
			for key in word.bonus:
				lines.append("  " + option_text(key, word.bonus[key]))
	return lines

func true_name(item: Dictionary):
	# A true name wakes when its pieces fill every socket in order, on a slot it allows (08 §5.3 trial).
	for word in data.true_names:
		if item.slot in word.slots and int(item.get("sockets", 0)) == word.pieces.size() and item.get("pieces", []) == word.pieces:
			return word
	return null

func describe_piece(id: String) -> PackedStringArray:
	var piece: Dictionary = data.pieces[id]
	var lines := PackedStringArray(["%s (%s)" % [piece.name, piece.meaning]])
	for group in ["medium", "armor", "accessory"]:
		for key in piece[group]:
			lines.append("%s: %s" % [data.slot_group_names[group], option_text(key, piece[group][key])])
	return lines

func reroll_affix(rng: RandomNumberGenerator, item: Dictionary, index: int) -> void:
	# 04 §4.2: one option re-rolls inside the same side (prefix/suffix) and the same slot pool,
	# at a tier the item level allows, never into an option the item already has.
	var old: Dictionary = item.affixes[index]
	var taken: Array = item.affixes.map(func(a): return a.id)
	var pool: Array = data.affixes.filter(func(a): return a.kind == old.kind and item.slot in a.slots and (a.id == old.id or not a.id in taken))
	var affix: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var tier: int = rng.randi_range(0, tier_for(item.level))
	var span: Array = affix.tiers[tier]
	var value: int = rng.randi_range(int(span[0]), int(span[1]))
	item.options[old.id] = int(item.options.get(old.id, 0)) - int(old.value)
	if item.options[old.id] == 0:
		item.options.erase(old.id)
	item.affixes[index] = {"id": affix.id, "kind": affix.kind, "tier": tier, "value": value}
	item.options[affix.id] = int(item.options.get(affix.id, 0)) + value
	if item.rarity == "magic":
		item.name = name_for(rng, item, bases[item.base])

func base_stats(item: Dictionary) -> Dictionary:
	# A medium's attack range or worn armour's defence, set by the item level alone (rarity adds
	# options, not base stats), so a higher-level normal item can outdo a low-level rare one.
	var spec: Dictionary = data.base_stats.get(item.slot, {})
	if spec.is_empty():
		return {}
	var base: Dictionary = bases[item.base]
	var scale: float = float(base.get("base_scale", 1.0)) * float(data.base_stats.family_scale.get(base.get("family", ""), 1.0))
	var stats := {}
	for key in spec:
		var line: Array = spec[key]
		stats[key] = maxi(1, roundi((float(line[0]) + float(line[1]) * (int(item.level) - 1)) * scale))
	return stats

func totals(equipped: Array) -> Dictionary:
	# Everything the worn items add, keyed as the options are; a unique adds "rule:<id>" too.
	var sum := {}
	for item in equipped:
		var stats := base_stats(item)
		for key in stats:
			sum[key] = float(sum.get(key, 0.0)) + float(stats[key])
		for key in item.options:
			sum[key] = float(sum.get(key, 0.0)) + float(item.options[key])
		if item.has("rule"):
			sum["rule:" + item.rule] = 1.0
		# Name pieces work by where they sit: the medium, worn armour or an accessory.
		var group: String = data.slot_groups[item.slot]
		for piece in item.get("pieces", []):
			for key in data.pieces[piece][group]:
				sum[key] = float(sum.get(key, 0.0)) + float(data.pieces[piece][group][key])
		var word = true_name(item)
		if word != null:
			for key in word.bonus:
				sum[key] = float(sum.get(key, 0.0)) + float(word.bonus[key])
	return sum

func roll_drops(rng: RandomNumberGenerator, grade: String, level: int) -> Array:
	# What one defeated enemy leaves behind; elites may and bosses always add a unique medium.
	var table: Dictionary = data.drops.get(grade, data.drops.normal)
	var found: Array = []
	if rng.randf() < float(table.chance):
		found.append(generate(rng, level, weighted(rng, table.weights)))
	if table.get("guaranteed_unique", false) or rng.randf() < float(table.get("unique_chance", 0.0)):
		found.append(make_unique(rng, level))
	return found
