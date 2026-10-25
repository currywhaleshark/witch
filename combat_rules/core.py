"""Pure transitions for the approved input/resource rules in docs/02_combat.md.

No rendering, damage, motion, AI, implicit recovery, or hidden pending casts.
Unresolved choices must be supplied as an explicitly named TrialPolicy.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from decimal import Decimal, InvalidOperation
from enum import Enum
from typing import Callable


SLOTS = ("lmb", "rmb", "q", "w", "e", "r")
ZERO = Decimal(0)


def quantity(value) -> Decimal:
    """Use decimal time/resources so a split upkeep tick reaches zero exactly."""
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError(f"Invalid quantity: {value!r}") from exc
    if not result.is_finite() or result < 0:
        raise ValueError(f"Expected a finite, nonnegative quantity: {value!r}")
    return result


class SkillKind(str, Enum):
    AIM = "aim"  # Enemy or ground aim; includes a force-cast basic attack.
    ENEMY = "enemy"
    GROUND = "ground"
    MOBILE_SUMMON = "mobile_summon"
    SELF = "self"
    TOOL = "tool"


@dataclass(frozen=True)
class Skill:
    id: str
    kind: SkillKind
    mana_cost: Decimal
    cooldown_seconds: Decimal
    upkeep_per_second: Decimal

    def __post_init__(self):
        if not isinstance(self.id, str) or not self.id:
            raise ValueError("A skill needs a nonempty id")
        object.__setattr__(self, "kind", SkillKind(self.kind))
        for field in ("mana_cost", "cooldown_seconds", "upkeep_per_second"):
            object.__setattr__(self, field, quantity(getattr(self, field)))
        if self.kind != SkillKind.TOOL and self.upkeep_per_second != ZERO:
            raise ValueError("Only tool toggles have upkeep in this harness")
        if self.kind == SkillKind.TOOL and self.upkeep_per_second <= ZERO:
            raise ValueError("An active tool must consume mana over time")


@dataclass(frozen=True)
class TrialPolicy:
    """Implementation trials, not approved game decisions. No implicit defaults."""

    name: str
    failure_order: tuple[str, ...]
    non_mana_failure: str
    manual_tool_release: str
    zero_mana_cast_order: str

    def __post_init__(self):
        if not self.name:
            raise ValueError("Name the trial policy explicitly")
        object.__setattr__(self, "failure_order", tuple(self.failure_order))
        if len(self.failure_order) != 4 or set(self.failure_order) != {"target", "spatial", "cooldown", "mana"}:
            raise ValueError("failure_order must contain target, spatial, cooldown, mana once")
        supported = {
            "non_mana_failure": "reject_without_moving",
            "manual_tool_release": "free_before_checks",
            "zero_mana_cast_order": "cast_then_release",
        }
        for field, expected in supported.items():
            if getattr(self, field) != expected:
                raise ValueError(f"Unimplemented trial policy {field}: {getattr(self, field)}")


@dataclass(frozen=True)
class Cursor:
    """Snapshot at key-down, supplied by the future engine's picking adapter.

    enemy_id must identify a valid enemy. ground is a valid picked world point;
    both may be present when an enemy has ground underneath it.
    """

    enemy_id: str | None = None
    ground: tuple[float, float, float] | None = None

    def __post_init__(self):
        if self.enemy_id is not None and (not isinstance(self.enemy_id, str) or not self.enemy_id):
            raise ValueError("enemy_id must be a nonempty id or None")
        if self.ground is not None:
            point = tuple(self.ground)
            if len(point) != 3:
                raise ValueError("ground must be a three-dimensional world point")
            for component in point:
                if not Decimal(str(component)).is_finite():
                    raise ValueError("Ground coordinates must be finite")
            object.__setattr__(self, "ground", point)


@dataclass(frozen=True)
class State:
    mana: Decimal
    max_mana: Decimal
    bindings: tuple[str | None, ...]
    active_tool: str | None = None
    cooldowns: tuple[tuple[str, Decimal], ...] = ()


@dataclass(frozen=True)
class Transition:
    state: State
    events: tuple[dict, ...]


# None means the spatial check passed; otherwise out_of_range or invalid_ground.
# Required on every press: the core must not silently skip collision/range checks.
SpatialCheck = Callable[[Skill, Cursor], str | None]


class CombatRules:
    def __init__(self, skills: list[Skill], basic_attack_id: str, policy: TrialPolicy):
        self.skills = {skill.id: skill for skill in skills}
        if len(self.skills) != len(skills):
            raise ValueError("Duplicate skill id")
        if basic_attack_id not in self.skills:
            raise ValueError("Missing basic attack")
        basic = self.skills[basic_attack_id]
        if basic.kind != SkillKind.AIM or basic.mana_cost != ZERO:
            raise ValueError("The basic attack must support aimed force-casting at zero mana cost")
        self.basic_attack_id = basic_attack_id
        self.policy = policy

    def initial_state(self, max_mana, mana=None) -> State:
        maximum = quantity(max_mana)
        current = maximum if mana is None else quantity(mana)
        state = State(current, maximum, (self.basic_attack_id, None, None, None, None, None))
        self._validate(state)
        return state

    def bind(self, state: State, slot: str, skill_id: str | None) -> State:
        self._validate(state)
        if slot not in SLOTS or (skill_id is not None and skill_id not in self.skills):
            raise ValueError("Unknown slot or skill")
        if slot == "lmb" and skill_id is None:
            raise ValueError("An empty left-click slot is outside this trial contract")
        bindings = list(state.bindings)
        bindings[SLOTS.index(slot)] = skill_id
        return replace(state, bindings=tuple(bindings))

    def _validate(self, state: State):
        if not isinstance(state.mana, Decimal) or not isinstance(state.max_mana, Decimal):
            raise ValueError("Create states through initial_state; resources must be Decimal")
        if quantity(state.mana) > quantity(state.max_mana):
            raise ValueError("Mana exceeds capacity")
        if len(state.bindings) != 6 or state.bindings[0] is None:
            raise ValueError("Exactly six active slots and an equipped LMB are required")
        if any(skill is not None and skill not in self.skills for skill in state.bindings):
            raise ValueError("Unknown bound skill")
        if state.active_tool is not None:
            if state.active_tool not in self.skills or self.skills[state.active_tool].kind != SkillKind.TOOL:
                raise ValueError("Invalid active tool")
            if state.mana == ZERO:
                raise ValueError("A tool cannot remain active at zero mana")
        ids = [skill for skill, _ in state.cooldowns]
        if len(ids) != len(set(ids)) or any(skill not in self.skills for skill in ids):
            raise ValueError("Invalid cooldown skill ids")
        for _, seconds in state.cooldowns:
            quantity(seconds)

    @staticmethod
    def _target(skill: Skill, cursor: Cursor) -> dict | None:
        if skill.kind in {SkillKind.SELF, SkillKind.TOOL}:
            return {"origin": "player"}
        if skill.kind == SkillKind.GROUND:
            return {"origin": "cursor_ground", "position": cursor.ground} if cursor.ground is not None else None
        if cursor.enemy_id is not None:
            return {"origin": "player_adjacent" if skill.kind == SkillKind.MOBILE_SUMMON else "player",
                    "target_enemy": cursor.enemy_id}
        if cursor.ground is not None and skill.kind in {SkillKind.AIM, SkillKind.MOBILE_SUMMON}:
            if skill.kind == SkillKind.MOBILE_SUMMON:
                return {"origin": "player_adjacent", "target_enemy": None}
            return {"origin": "player", "position": cursor.ground}
        return None

    def _failure(self, state: State, skill: Skill, cursor: Cursor, spatial_check: SpatialCheck) -> str | None:
        for check in self.policy.failure_order:
            if check == "target" and self._target(skill, cursor) is None:
                return "invalid_target"
            if check == "spatial" and skill.kind not in {SkillKind.SELF, SkillKind.TOOL}:
                reason = spatial_check(skill, cursor)
                if reason not in {None, "out_of_range", "invalid_ground"}:
                    raise ValueError(f"Unexpected spatial failure: {reason}")
                if reason is not None:
                    return reason
            if check == "cooldown" and dict(state.cooldowns).get(skill.id, ZERO) > ZERO:
                return "cooldown"
            if check == "mana" and state.mana < skill.mana_cost:
                return "insufficient_mana"
        return None

    @staticmethod
    def _release_at_zero(state: State, events: list[dict]) -> State:
        if state.mana == ZERO and state.active_tool is not None:
            events.append({"type": "tool_released", "tool": state.active_tool, "reason": "mana_empty"})
            return replace(state, active_tool=None)
        return state

    def press(self, state: State, slot: str, cursor: Cursor, *, spatial_check: SpatialCheck,
              shift: bool = False) -> Transition:
        """Resolve one key-down immediately. No target confirmation or held-input loop."""
        self._validate(state)
        if slot not in SLOTS:
            return Transition(state, ({"type": "input_ignored", "input": slot,
                                       "reason": "outside_active_slots"},))
        if slot == "lmb" and not shift and cursor.enemy_id is None:
            if cursor.ground is None:
                return Transition(state, ({"type": "input_failed", "reason": "invalid_ground"},))
            return Transition(state, ({"type": "move_requested", "position": cursor.ground},))
        skill_id = state.bindings[SLOTS.index(slot)]
        if skill_id is None:
            return Transition(state, ({"type": "input_failed", "reason": "empty_slot", "slot": slot},))
        skill = self.skills[skill_id]
        if skill.kind == SkillKind.TOOL and state.active_tool == skill.id:
            return Transition(replace(state, active_tool=None),
                              ({"type": "tool_released", "tool": skill.id, "reason": "manual"},))
        events = []
        reason = self._failure(state, skill, cursor, spatial_check)
        if reason == "insufficient_mana" and slot == "lmb":
            events.append({"type": "basic_attack_fallback", "requested_skill": skill.id,
                           "skill": self.basic_attack_id, "reason": reason})
            skill = self.skills[self.basic_attack_id]
            reason = self._failure(state, skill, cursor, spatial_check)
        if reason is not None:
            events.append({"type": "cast_failed", "slot": slot, "skill": skill.id, "reason": reason})
            return Transition(state, tuple(events))
        # Commit only after all selected-skill checks (including fallback checks).
        next_state = replace(state, mana=state.mana - skill.mana_cost)
        if skill.mana_cost:
            events.append({"type": "mana_spent", "amount": skill.mana_cost})
        if skill.kind == SkillKind.TOOL:
            next_state = replace(next_state, active_tool=skill.id)
            events.append({"type": "tool_changed", "previous": state.active_tool, "tool": skill.id})
        events.append({"type": "cast", "slot": slot, "skill": skill.id,
                       "active_tool": next_state.active_tool, **self._target(skill, cursor)})
        cooldowns = dict(state.cooldowns)
        if skill.cooldown_seconds:
            cooldowns[skill.id] = skill.cooldown_seconds
        next_state = replace(next_state, cooldowns=tuple(sorted(cooldowns.items())))
        next_state = self._release_at_zero(next_state, events)
        return Transition(next_state, tuple(events))

    def advance(self, state: State, seconds) -> Transition:
        """Only cooldown time and tool upkeep advance; no automatic mana recovery."""
        self._validate(state)
        delta = quantity(seconds)
        cooldowns = tuple((skill, remaining - delta) for skill, remaining in state.cooldowns if remaining > delta)
        next_state = replace(state, cooldowns=cooldowns)
        events = []
        if state.active_tool is not None:
            cost = min(state.mana, self.skills[state.active_tool].upkeep_per_second * delta)
            if cost:
                next_state = replace(next_state, mana=state.mana - cost)
                events.append({"type": "tool_upkeep", "tool": state.active_tool, "amount": cost})
            next_state = self._release_at_zero(next_state, events)
        return Transition(next_state, tuple(events))

    def restore_mana(self, state: State, amount) -> Transition:
        """External test/recovery event; does not choose potions or a regen formula."""
        self._validate(state)
        recovered = min(quantity(amount), state.max_mana - state.mana)
        return Transition(replace(state, mana=state.mana + recovered),
                          ({"type": "mana_restored", "amount": recovered},))
