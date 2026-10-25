"""Replay portable input/expected-output fixtures, without engine dependencies."""

from __future__ import annotations

from decimal import Decimal
import json
from pathlib import Path

from .core import CombatRules, Cursor, SLOTS, Skill, State, Transition, TrialPolicy


def json_value(value):
    if isinstance(value, Decimal):
        return format(value.normalize(), "f")
    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [json_value(item) for item in value]
    return value


def snapshot(state: State) -> dict:
    return json_value({"mana": state.mana, "max_mana": state.max_mana,
                       "active_tool": state.active_tool,
                       "bindings": dict(zip(SLOTS, state.bindings)),
                       "cooldowns": dict(state.cooldowns)})


def load_fixture(path: Path) -> dict:
    fixture = json.loads(path.read_text(encoding="utf-8-sig"))
    if fixture.get("schema_version") != 1 or fixture.get("status") != "test_values_not_approved_balance":
        raise ValueError("Expected a version 1, explicitly provisional combat fixture")
    if not fixture.get("cases") or len({case["id"] for case in fixture["cases"]}) != len(fixture["cases"]):
        raise ValueError("Scenarios must have nonempty, unique case ids")
    return fixture


def build_rules(fixture: dict) -> CombatRules:
    return CombatRules([Skill(**entry) for entry in fixture["skills"]],
                       fixture["basic_attack_id"], TrialPolicy(**fixture["policy"]))


def differences(expected, actual, path="result") -> list[str]:
    """Objects select fields; arrays and empty objects require exact contents."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [f"{path}: expected an object, got {actual!r}"]
        if not expected and actual:
            return [f"{path}: expected empty object, got {actual!r}"]
        errors = []
        for key, value in expected.items():
            if key not in actual:
                errors.append(f"{path}.{key}: missing")
            else:
                errors.extend(differences(value, actual[key], f"{path}.{key}"))
        return errors
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            return [f"{path}: expected {len(expected)} items, got {actual!r}"]
        return [error for i, (left, right) in enumerate(zip(expected, actual))
                for error in differences(left, right, f"{path}[{i}]")]
    return [] if expected == actual else [f"{path}: expected {expected!r}, got {actual!r}"]


def replay_case(fixture: dict, case: dict) -> dict:
    rules = build_rules(fixture)
    state = rules.initial_state(fixture["max_mana"], case["initial_mana"])
    for slot, skill in {**fixture["bindings"], **case.get("bindings", {})}.items():
        state = rules.bind(state, slot, skill)
    steps = []
    if not case["steps"]:
        raise ValueError(f"Empty scenario: {case['id']}")
    for index, step in enumerate(case["steps"]):
        before = snapshot(state)
        action = step["action"]
        op = action["op"]
        if op == "press":
            failures = action.get("spatial_failures", {})
            result = rules.press(state, action["slot"], Cursor(**action.get("cursor", {})),
                                 shift=action.get("shift", False),
                                 spatial_check=lambda skill, cursor: failures.get(skill.id))
        elif op == "advance":
            result = rules.advance(state, action["seconds"])
        elif op == "restore_mana":
            result = rules.restore_mana(state, action["amount"])
        elif op == "bind":
            result = Transition(rules.bind(state, action["slot"], action["skill"]), ())
        else:
            raise ValueError(f"Unknown scenario operation: {op}")
        actual = {"state": snapshot(result.state), "events": json_value(result.events)}
        if not step.get("expect"):
            raise ValueError(f"Step needs explicit expectations: {case['id']}:{index + 1}")
        errors = differences(step["expect"], actual)
        steps.append({"step": index + 1, "before": before, "action": action,
                      "expected": step["expect"], "actual": actual,
                      "passed": not errors, "errors": errors})
        state = result.state
    return {"id": case["id"], "covers": case["covers"], "description": case["description"],
            "passed": all(step["passed"] for step in steps), "steps": steps}


def replay(fixture: dict) -> dict:
    cases = [replay_case(fixture, case) for case in fixture["cases"]]
    return {"report_version": 1, "scope": "headless_rule_checks_only_not_P0_completion",
            "policy": fixture["policy"], "fixture_status": fixture["status"],
            "summary": {"cases": len(cases), "passed": sum(case["passed"] for case in cases),
                        "failed": sum(not case["passed"] for case in cases),
                        "steps": sum(len(case["steps"]) for case in cases)},
            "not_verified": ["3D picking/navigation/collision", "damage and enemy AI", "HP/death",
                             "summon lifetime/AI/camera bounds", "UI and combat feel", "balance"],
            "cases": cases}
