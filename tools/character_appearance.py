"""Engine-independent appearance selection and modular 3D loading plans.

Selections are immutable drafts. A renderer must stage and validate every new
part before committing a plan; these functions never replace a live character.
"""

from copy import deepcopy
from pathlib import Path, PurePosixPath
import re


FORMS = ("civilian", "transformed")
DEFAULT_OUTFITS = {"civilian": "civilian_v1", "transformed": "transformed_v1"}


class AppearanceError(ValueError):
    pass


def normalize_appearance(appearance):
    """Migrate legacy active-outfit input without storing two sources of truth."""
    result = deepcopy(appearance)
    version = result.get("schema_version")
    if version == "0.1-draft":
        if "outfits_by_form" in result:
            raise AppearanceError("Legacy outfit and outfits_by_form cannot coexist")
        if result.get("form") not in FORMS or not result.get("outfit"):
            raise AppearanceError("Invalid legacy form/outfit")
        result["outfits_by_form"] = dict(DEFAULT_OUTFITS)
        result["outfits_by_form"][result["form"]] = result.pop("outfit")
        result["schema_version"] = "0.2-draft"
    elif version != "0.2-draft":
        raise AppearanceError("Unsupported appearance schema")
    if "outfit" in result:
        raise AppearanceError("Active outfit is derived, not stored in schema 0.2")
    if result.get("form") not in FORMS:
        raise AppearanceError("Unknown form")
    choices = result.get("outfits_by_form")
    if not isinstance(choices, dict) or set(choices) != set(FORMS):
        raise AppearanceError("Each form must remember its own outfit")
    for value in list(choices.values()) + [result.get(k) for k in (
            "character_id", "body_preset", "hair_style", "eye_shape", "expression")]:
        if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", value):
            raise AppearanceError("Invalid preset ID")
    for key in ("hair_color", "eye_color"):
        if not isinstance(result.get(key), str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", result[key]):
            raise AppearanceError(f"Invalid {key}")
    return result


def active_outfit(appearance):
    state = normalize_appearance(appearance)
    return state["outfits_by_form"][state["form"]]


def legacy_renderer_view(appearance):
    """Derived adapter for the existing SCG resolver; never persist this view."""
    state = normalize_appearance(appearance)
    outfit = state["outfits_by_form"][state["form"]]
    state.pop("outfits_by_form")
    return {**state, "schema_version": "0.1-draft", "outfit": outfit}


def choose_form(appearance, form):
    state = normalize_appearance(appearance)
    if form not in FORMS:
        raise AppearanceError("Unknown form")
    state["form"] = form
    return state


def choose_outfit(appearance, form, outfit_id, spec):
    state = normalize_appearance(appearance)
    outfit = spec["outfits"].get(outfit_id)
    if form not in FORMS or outfit is None or outfit.get("form") != form:
        raise AppearanceError("Outfit does not belong to the requested form")
    if outfit.get("body_preset") != state["body_preset"]:
        raise AppearanceError("Outfit does not fit the common body")
    if outfit.get("rig_id") != spec["rig"]["id"]:
        raise AppearanceError("Outfit requires a different rig")
    state["outfits_by_form"][form] = outfit_id
    return state


def resolve_3d_plan(spec, appearance, asset_root):
    """Validate registry/file availability, not geometry or animation quality.

    Null paths are explicit missing production assets. Static decimation trials
    must not be registered as a modular body, hair, eyes or outfit.
    """
    state = normalize_appearance(appearance)
    if spec.get("schema_version") != "0.1-modular-draft":
        raise AppearanceError("Unsupported modular spec")
    if spec.get("character_id") != state["character_id"]:
        raise AppearanceError("Character mismatch")
    try:
        chosen = {
            "rig": spec["rig"],
            "body": spec["bodies"][state["body_preset"]],
            "hair": spec["hair"][state["hair_style"]],
            "eyes": spec["eyes"][state["eye_shape"]],
            "outfit": spec["outfits"][active_outfit(state)],
        }
    except KeyError as exc:
        raise AppearanceError(f"Unknown modular preset: {exc}") from exc
    choose_outfit(state, state["form"], active_outfit(state), spec)
    root = Path(asset_root).resolve()
    blockers = []
    parts = {}
    for slot, part in chosen.items():
        if slot != "rig" and (part.get("rig_id") != spec["rig"]["id"]
                or part.get("body_preset") != state["body_preset"]):
            raise AppearanceError(f"Incompatible {slot}")
        path = part.get("asset")
        if part.get("status") != "validated":
            blockers.append(f"{slot}:not_validated")
        if path is None:
            blockers.append(f"{slot}:not_created")
        elif not isinstance(path, str) or "\\" in path or ":" in path:
            raise AppearanceError(f"Invalid {slot} asset path")
        else:
            relative = PurePosixPath(path)
            resolved = (root / relative).resolve()
            if relative.is_absolute() or ".." in relative.parts or not resolved.is_relative_to(root):
                raise AppearanceError(f"Asset escapes root: {slot}")
            if relative.parts[:1] != ("exports",) or relative.suffix != ".glb":
                raise AppearanceError("Only validated exports/*.glb may serve as modular parts")
            if not resolved.is_file():
                blockers.append(f"{slot}:file_missing")
        parts[slot] = {"id": part["id"], "asset": path}
    return {
        "status": "blocked_missing_production_assets" if blockers else "ready_for_runtime_validation",
        "appearance": state,
        "active_outfit": active_outfit(state),
        "parts": parts,
        "body_regions_hidden_by_outfit": chosen["outfit"].get("hide_body_regions", []),
        "colors": {"hair": state["hair_color"], "iris": state["eye_color"]},
        "blockers": blockers,
        "preserve_on_outfit_swap": ["rig_instance", "body_identity", "animation_state", "transform", "gameplay_state"],
        "commit_policy": "stage_validate_all_parts_then_swap_atomically_keep_previous_on_failure",
        "production_ready": False,
    }
