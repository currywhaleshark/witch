extends SceneTree
const Rules = preload("res://scripts/combat_rules.gd")
var failures: Array = []
var steps = 0

func _initialize() -> void:
	var path = ProjectSettings.globalize_path("res://").path_join("../tests/fixtures/combat_rules.json")
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not fixture is Dictionary:
		push_error("Cannot read shared fixture: " + path)
		quit(1)
		return
	var rules = Rules.new(fixture)
	for scenario in fixture.cases:
		var state = rules.initial_state(float(fixture.max_mana), scenario.get("initial_mana"))
		var bindings: Dictionary = fixture.get("bindings", {}).duplicate()
		bindings.merge(scenario.get("bindings", {}), true)
		for slot in bindings:
			state = rules.bind(state, slot, bindings[slot])
		for step in scenario.steps:
			steps += 1
			var action: Dictionary = step.action
			var result: Dictionary
			match action.op:
				"press":
					var spatial = func(skill, _cursor): return action.get("spatial_failures", {}).get(skill.id)
					result = rules.press(state, action.slot, action.get("cursor", {}), spatial, action.get("shift", false))
				"advance": result = rules.advance(state, float(action.seconds))
				"restore_mana": result = rules.restore_mana(state, float(action.amount))
				"bind": result = {"state": rules.bind(state, action.slot, action.skill), "events": []}
				_:
					failures.append("Unknown action: " + str(action))
					continue
			state = result.state
			compare(result, step.expect, scenario.id + ":" + str(steps))
	# Fractional upkeep reaches zero without an immortal toggle.
	var small = rules.initial_state(30, 0.3)
	small = rules.press(rules.bind(small, "q", "trial_tool_a"), "q", {}, func(_s, _c): return null).state
	for i in 3:
		small = rules.advance(small, 0.05).state
	compare(small, {"mana": "0", "active_tool": null}, "fractional upkeep")
	var report = {"engine": Engine.get_version_info().string, "scenarios": fixture.cases.size(), "steps": steps, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/godot_rules_report.json")
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func compare(actual, expected, at: String) -> void:
	if expected is Dictionary:
		if not actual is Dictionary:
			failures.append(at + " expected object")
			return
		if expected.is_empty() and not actual.is_empty():
			failures.append(at + " expected empty object, got " + str(actual))
		for key in expected:
			if not actual.has(key):
				failures.append(at + " missing " + key)
			else:
				compare(actual[key], expected[key], at + "." + key)
	elif expected is Array:
		if not actual is Array or actual.size() != expected.size():
			failures.append(at + " array mismatch " + str(actual))
			return
		for i in expected.size():
			compare(actual[i], expected[i], at + "[" + str(i) + "]")
	elif expected is String and expected.is_valid_float() and (actual is float or actual is int):
		if absf(float(expected) - float(actual)) > 0.000001:
			failures.append(at + " number mismatch " + str(actual))
	elif actual != expected:
		failures.append(at + " expected " + str(expected) + " got " + str(actual))
