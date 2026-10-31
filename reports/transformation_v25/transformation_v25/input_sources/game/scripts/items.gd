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
	var item := {"base": base.id, "slot": slot, "rarity": rarity, "level": level, "options": {}, "affixes": [], "name": ""}
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
		"affixes": [], "name": unique.name, "unique": id, "rule": unique.rule}

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

func describe(item: Dictionary) -> PackedStringArray:
	var base: Dictionary = bases[item.base]
	var lines := PackedStringArray([item.name])
	var kind: Array = [data.rarity_names[item.rarity]]
	if item.name != base.name:
		kind.append(base.name)
	kind.append_array([data.slot_names[item.slot], "아이템 레벨 %d" % item.level])
	lines.append(" · ".join(kind))
	for key in base.get("implicit", {}):
		if item.options.has(key) and item.rarity != "unique":
			lines.append("기본: " + option_text(key, base.implicit[key][tier_for(item.level)]))
	for affix in item.affixes:
		lines.append("%s %s" % [["I", "II", "III"][affix.tier], option_text(affix.id, affix.value)])
	if item.rarity == "unique":
		for key in item.options:
			lines.append(option_text(key, item.options[key]))
		lines.append("고유: " + uniques[item.unique].rule_text)
	return lines

func totals(equipped: Array) -> Dictionary:
	# Everything the worn items add, keyed as the options are; a unique adds "rule:<id>" too.
	var sum := {}
	for item in equipped:
		for key in item.options:
			sum[key] = float(sum.get(key, 0.0)) + float(item.options[key])
		if item.has("rule"):
			sum["rule:" + item.rule] = 1.0
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
