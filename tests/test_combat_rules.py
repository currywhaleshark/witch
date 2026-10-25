import copy
from dataclasses import replace
from decimal import Decimal
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from combat_rules.core import CombatRules, Cursor, SLOTS, Skill, SkillKind, TrialPolicy
from combat_rules.scenarios import build_rules, differences, load_fixture, replay


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/combat_rules.json"
ENEMY = Cursor(enemy_id="enemy_1", ground=(4, 0, 2))
GROUND = Cursor(ground=(4, 0, 2))


class CombatRuleTests(unittest.TestCase):
    def setUp(self):
        self.fixture = load_fixture(FIXTURE)
        self.rules = build_rules(self.fixture)

    def state(self, mana="30"):
        state = self.rules.initial_state("30", mana)
        for slot, skill in self.fixture["bindings"].items():
            state = self.rules.bind(state, slot, skill)
        return state

    def press(self, state, slot, cursor=ENEMY, **kwargs):
        return self.rules.press(state, slot, cursor,
                                spatial_check=kwargs.pop("spatial_check", lambda skill, aim: None), **kwargs)

    def test_portable_A1_to_A5_scenarios(self):
        report = replay(self.fixture)
        for case in report["cases"]:
            with self.subTest(case=case["id"]):
                self.assertTrue(case["passed"], case["steps"])

    def test_only_six_slots_and_basic_attack_starts_in_left_slot(self):
        state = self.rules.initial_state("30")
        self.assertEqual(state.bindings, ("basic_attack", None, None, None, None, None))
        with self.assertRaises(ValueError):
            self.rules.bind(state, "7", "basic_attack")
        for key in ("1", "2", "3", "4"):
            result = self.press(state, key)
            self.assertEqual(result.state, state)
            self.assertEqual(result.events[0]["type"], "input_ignored")

    def test_all_five_non_left_slots_fail_for_mana_without_fallback(self):
        for slot in SLOTS[1:]:
            with self.subTest(slot=slot):
                state = self.rules.bind(self.state("0"), slot, "trial_shot")
                result = self.press(state, slot)
                self.assertEqual(result.state, state)
                self.assertEqual(result.events, ({"type": "cast_failed", "slot": slot,
                                                 "skill": "trial_shot", "reason": "insufficient_mana"},))

    def test_all_instant_slots_use_current_cursor_without_pending_confirmation(self):
        for slot in SLOTS[1:]:
            with self.subTest(slot=slot):
                state = self.rules.bind(self.state(), slot, "trial_target")
                result = self.press(state, slot, Cursor(enemy_id="picked_now"))
                casts = [event for event in result.events if event["type"] == "cast"]
                self.assertEqual(len(casts), 1)
                self.assertEqual(casts[0]["target_enemy"], "picked_now")
                idle = self.rules.advance(result.state, "100")
                self.assertEqual(idle.events, ())

    def test_shift_left_mana_fallback_aims_at_ground_without_moving(self):
        state = self.rules.bind(self.state("0"), "lmb", "trial_shot")
        result = self.press(state, "lmb", GROUND, shift=True)
        self.assertEqual([event["type"] for event in result.events], ["basic_attack_fallback", "cast"])
        self.assertEqual(result.events[1]["position"], GROUND.ground)
        self.assertEqual(result.state.bindings[0], "trial_shot")

    def test_fallback_basic_attack_has_its_own_spatial_check(self):
        state = self.rules.bind(self.state("0"), "lmb", "trial_shot")
        checked = []

        def check(skill, cursor):
            checked.append(skill.id)
            return "out_of_range" if skill.id == "basic_attack" else None

        result = self.press(state, "lmb", spatial_check=check)
        self.assertEqual(checked, ["trial_shot", "basic_attack"])
        self.assertEqual(result.state, state)
        self.assertEqual([event["type"] for event in result.events], ["basic_attack_fallback", "cast_failed"])
        self.assertEqual(result.events[-1]["reason"], "out_of_range")

    def test_target_failure_and_mana_failure_priority_is_explicit_policy(self):
        state = self.rules.bind(self.state("0"), "lmb", "trial_target")
        normal = self.press(state, "lmb", GROUND, shift=True)
        self.assertEqual(normal.events[0]["reason"], "invalid_target")
        alternative = CombatRules(list(self.rules.skills.values()), "basic_attack",
                                  replace(self.rules.policy, name="trial_mana_first",
                                          failure_order=("mana", "target", "spatial", "cooldown")))
        changed = alternative.press(state, "lmb", GROUND, shift=True, spatial_check=lambda skill, cursor: None)
        self.assertEqual([event["type"] for event in changed.events], ["basic_attack_fallback", "cast"])

    def test_self_and_tool_do_not_need_cursor_or_spatial_target(self):
        def must_not_query(skill, cursor):
            self.fail("Self-targeted input queried the world cursor")

        for skill in ("trial_self", "trial_tool_a"):
            with self.subTest(skill=skill):
                state = self.rules.bind(self.state(), "q", skill)
                result = self.press(state, "q", Cursor(), spatial_check=must_not_query)
                self.assertIn("cast", [event["type"] for event in result.events])

    def test_invalid_ground_and_missing_target_do_not_spend_or_start_cooldown(self):
        state = self.state()
        for cursor, check, expected in ((Cursor(), lambda skill, cursor: None, "invalid_target"),
                                        (GROUND, lambda skill, cursor: "invalid_ground", "invalid_ground")):
            with self.subTest(expected=expected):
                result = self.press(state, "e", cursor, spatial_check=check)
                self.assertEqual(result.state, state)
                self.assertEqual(result.events[-1]["reason"], expected)

    def test_placement_can_receive_ground_under_enemy_without_using_enemy_as_target(self):
        result = self.press(self.state(), "e", ENEMY)
        cast = result.events[-1]
        self.assertEqual(cast["origin"], "cursor_ground")
        self.assertEqual(cast["position"], ENEMY.ground)
        self.assertNotIn("target_enemy", cast)

    def test_shift_left_summon_can_set_initial_enemy(self):
        state = self.rules.bind(self.state(), "lmb", "trial_summon")
        result = self.press(state, "lmb", ENEMY, shift=True)
        self.assertEqual(result.events[-1]["origin"], "player_adjacent")
        self.assertEqual(result.events[-1]["target_enemy"], "enemy_1")

    def test_failed_switch_keeps_previous_tool_and_its_upkeep(self):
        active = self.press(self.state("5"), "q", Cursor()).state
        state = self.rules.bind(active, "q", "trial_costly_tool")
        failure = self.press(state, "q", Cursor())
        self.assertEqual(failure.state, state)
        self.assertEqual(failure.events[-1]["reason"], "insufficient_mana")
        tick = self.rules.advance(failure.state, "1")
        self.assertEqual(tick.state.active_tool, "trial_tool_a")
        self.assertEqual(tick.state.mana, Decimal("3"))

    def test_manual_release_is_free_even_during_cooldown_under_trial_policy(self):
        state = self.rules.bind(self.state("11"), "q", "trial_costly_tool")
        active = self.press(state, "q", Cursor()).state
        self.assertEqual(active.mana, Decimal("1"))
        result = self.press(active, "q", Cursor())
        self.assertIsNone(result.state.active_tool)
        self.assertEqual(result.state.mana, active.mana)
        self.assertEqual(result.state.cooldowns, active.cooldowns)
        self.assertEqual(result.events[0]["reason"], "manual")

    def test_basic_attack_reports_active_tool_without_removing_it(self):
        active = self.press(self.state(), "q", Cursor()).state
        result = self.press(active, "lmb")
        self.assertEqual(result.events[0]["active_tool"], "trial_tool_a")
        self.assertEqual(result.state.active_tool, "trial_tool_a")

    def test_other_skill_categories_keep_tool_until_zero(self):
        for slot in ("rmb", "w", "e", "r"):
            with self.subTest(slot=slot):
                active = self.press(self.state(), "q", Cursor()).state
                result = self.press(active, slot)
                self.assertEqual(result.state.active_tool, "trial_tool_a")
                before_tick = result.state.mana
                tick = self.rules.advance(result.state, "1")
                self.assertEqual(tick.state.mana, before_tick - Decimal("2"))

    def test_switch_replaces_upkeep_instead_of_stacking_it(self):
        state = self.press(self.state(), "q", Cursor()).state
        state = self.rules.bind(state, "r", "trial_tool_b")
        state = self.press(state, "r", Cursor()).state
        result = self.rules.advance(state, "2")
        self.assertEqual(result.state.active_tool, "trial_tool_b")
        self.assertEqual(result.state.mana, Decimal("24"))

    def test_split_ticks_match_whole_tick_at_exact_exhaustion(self):
        initial = self.press(self.state("2"), "q", Cursor()).state
        whole = self.rules.advance(initial, "1")
        state = initial
        releases = []
        for _ in range(10):
            result = self.rules.advance(state, "0.1")
            state = result.state
            releases.extend(event for event in result.events if event["type"] == "tool_released")
        self.assertEqual(state, whole.state)
        self.assertEqual(state.mana, Decimal("0"))
        self.assertIsNone(state.active_tool)
        self.assertEqual(len(releases), 1)

    def test_large_tick_never_overdraws_and_releases_once(self):
        state = self.press(self.state("3"), "q", Cursor()).state
        result = self.rules.advance(state, "1000")
        self.assertEqual(result.state.mana, Decimal("0"))
        self.assertEqual(result.events[0]["amount"], Decimal("3"))
        self.assertEqual(len([e for e in result.events if e["type"] == "tool_released"]), 1)
        self.assertEqual(self.rules.advance(result.state, "1000").events, ())

    def test_zero_cost_tool_at_zero_cannot_remain_active(self):
        result = self.press(self.state("0"), "q", Cursor())
        self.assertIsNone(result.state.active_tool)
        self.assertEqual(result.events[-1]["reason"], "mana_empty")

    def test_exact_cost_tool_activation_ends_released(self):
        state = self.rules.bind(self.state("10"), "q", "trial_costly_tool")
        result = self.press(state, "q", Cursor())
        self.assertEqual(result.state.mana, Decimal("0"))
        self.assertIsNone(result.state.active_tool)
        self.assertEqual([event["type"] for event in result.events],
                         ["mana_spent", "tool_changed", "cast", "tool_released"])

    def test_restore_clamps_capacity_and_never_reactivates_tool(self):
        state = self.press(self.state("2"), "q", Cursor()).state
        state = self.rules.advance(state, "1").state
        result = self.rules.restore_mana(state, "100")
        self.assertEqual(result.state.mana, Decimal("30"))
        self.assertEqual(result.events[0]["amount"], Decimal("30"))
        self.assertIsNone(result.state.active_tool)

    def test_cooldown_boundary_and_no_queued_cast(self):
        result = self.press(self.state(), "rmb")
        pending = self.rules.advance(result.state, "1.999")
        failure = self.press(pending.state, "rmb")
        self.assertEqual(failure.events[-1]["reason"], "cooldown")
        ready = self.rules.advance(failure.state, "0.001")
        self.assertEqual(ready.events, ())
        self.assertEqual(ready.state.cooldowns, ())
        self.assertEqual(self.press(ready.state, "rmb").events[-1]["type"], "cast")

    def test_input_state_is_not_mutated_by_success_or_failure(self):
        state = self.state()
        before = copy.deepcopy(state)
        success = self.press(state, "rmb")
        self.assertEqual(state, before)
        before_failure = copy.deepcopy(success.state)
        self.press(success.state, "rmb")
        self.assertEqual(success.state, before_failure)

    def test_invalid_resources_and_time_are_rejected(self):
        for value in ("-1", "NaN", "Infinity", "bad"):
            with self.subTest(value=value):
                for action in (lambda: self.rules.initial_state(value),
                               lambda: self.rules.advance(self.state(), value),
                               lambda: self.rules.restore_mana(self.state(), value)):
                    with self.assertRaises(ValueError):
                        action()
        with self.assertRaises(ValueError):
            self.rules.initial_state("10", "11")

    def test_invalid_catalog_and_unimplemented_policy_fail_explicitly(self):
        with self.assertRaises(ValueError):
            Skill("bad", SkillKind.AIM, "0", "0", "1")
        with self.assertRaises(ValueError):
            Skill("bad", SkillKind.TOOL, "0", "0", "0")
        with self.assertRaises(ValueError):
            replace(self.rules.policy, non_mana_failure="auto_move_and_cast")
        with self.assertRaises(ValueError):
            replace(self.rules.policy, failure_order=("mana", "mana", "target", "spatial"))


class ScenarioRunnerTests(unittest.TestCase):
    def test_mismatch_returns_failure_exit_code_and_writes_report(self):
        fixture = load_fixture(FIXTURE)
        fixture["cases"] = [fixture["cases"][0]]
        fixture["cases"][0]["steps"][0]["expect"]["state"]["mana"] = "999"
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.json"
            report_path = Path(folder) / "report.json"
            path.write_text(json.dumps(fixture), encoding="utf-8")
            result = subprocess.run([sys.executable, "-m", "combat_rules", "--fixture", str(path),
                                     "--report", str(report_path)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["summary"]["failed"], 1)
            self.assertIn("expected '999'", report["cases"][0]["steps"][0]["errors"][0])

    def test_empty_or_unmarked_fixture_is_not_success(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.json"
            path.write_text('{"schema_version": 1}', encoding="utf-8")
            result = subprocess.run([sys.executable, "-m", "combat_rules", "--fixture", str(path)],
                                    cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)

    def test_empty_event_lists_and_empty_cooldowns_are_strict(self):
        self.assertTrue(differences([], [{"type": "cast"}]))
        self.assertTrue(differences({}, {"trial_shot": "2"}))
        self.assertEqual(differences({"type": "cast"}, {"type": "cast", "slot": "q"}), [])


if __name__ == "__main__":
    unittest.main()
