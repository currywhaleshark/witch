"""Inspect the handoff and resolve SCG layers without rendering substitute art.

The renderer-facing interface is resolve_layer_plan(spec, appearance). Paths are
relative to assets/characters/player/scg, ordered from back to front. This module
does not generate art, import an unverified ZIP, or approve production quality.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

from PIL import Image

try:
    from tools.character_appearance import AppearanceError, legacy_renderer_view
except ModuleNotFoundError:  # Direct invocation: python tools/scg_assets.py
    from character_appearance import AppearanceError, legacy_renderer_view


SCG_ROOT = Path("assets/characters/player/scg")
REFERENCE_ROOT = Path("assets/reference/character/scg")
HANDOFF_ROOT = Path("assets/reference/character/handoff")
CANVAS = (1086, 1448)
REFERENCES = {
    "semilong_reference.png": "canonical_flat_illustration",
    "twintails_reference.png": "hair_design_flat_illustration",
    "hair_swap_comparison.png": "delta_patch_experiment",
    "hair_color_variations.png": "color_mask_experiment",
    "dialogue_ui_reference.png": "unapproved_ui_reference",
    "mask_quality_check.png": "mask_quality_inspection",
    "hair_swap_mask_overlay.png": "delta_patch_error_analysis",
}
SHARED_SLOTS = {
    "body_base": "body_base",
    "face_base": "face_base",
    "eyes": "eyes_neutral",
    "eyebrows": "brows_neutral",
    "mouth": "mouth_neutral",
}
HAIR_SLOTS = {
    "hair_back": "back",
    "hair_front": "front",
    "hair_over_clothes": "over_clothes",
}


class ContractError(ValueError):
    """The draft cannot be loaded without silently changing the appearance."""


def read_json(path: Path) -> dict:
    with path.open(encoding="utf-8-sig") as source:
        value = json.load(source)
    if not isinstance(value, dict):
        raise ContractError(f"Expected a JSON object: {path.name}")
    return value


def layer_path(value: str) -> str:
    if not isinstance(value, str) or "\\" in value or ":" in value:
        raise ContractError(f"Invalid layer path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.parts[:1] != ("layers",):
        raise ContractError(f"Production layers must stay inside layers/: {value}")
    if path.suffix.lower() != ".png":
        raise ContractError(f"Expected a PNG layer: {value}")
    return path.as_posix()


def resolve_layer_plan(spec: dict, appearance: dict) -> dict:
    """Return a draft loading plan, or fail explicitly for unsupported presets.

    Missing files are handled by audit(); no alternate full illustration is used.
    The same shared body/face/outfit paths serve both supported hair styles.
    """
    try:
        if appearance.get("schema_version") == "0.2-draft":
            appearance = legacy_renderer_view(appearance)
        if spec["schema_version"] != "0.1-draft" or appearance["schema_version"] != "0.1-draft":
            raise ContractError("Unsupported schema version")
        canvas = spec["canvas"]
        if (canvas["width"], canvas["height"]) != CANVAS:
            raise ContractError("The master canvas must remain 1086x1448")
        if (canvas["origin"] != "top_left" or canvas["color_space"] != "sRGB"
                or canvas["transparent_background"] is not True):
            raise ContractError("Unsupported canvas origin, color space, or alpha contract")
        if spec["character_id"] != "player" or appearance["character_id"] != "player":
            raise ContractError("Only the player draft is defined")
        for key, expected in {
            "body_preset": "standard_v1", "eye_shape": "neutral_v1", "expression": "neutral",
        }.items():
            if appearance[key] != expected:
                raise ContractError(f"Unsupported {key}: {appearance[key]}")
        for key in ("hair_color", "eye_color"):
            color = appearance[key]
            if not isinstance(color, str) or len(color) != 7 or color[0] != "#":
                raise ContractError(f"Invalid {key}; expected #RRGGBB")
            try:
                int(color[1:], 16)
            except ValueError as exc:
                raise ContractError(f"Invalid {key}; expected #RRGGBB") from exc
        form = appearance["form"]
        outfits = {"civilian": ("civilian_v1", "civilian_outfit"),
                   "transformed": ("transformed_v1", "transformed_outfit")}
        if form not in outfits or appearance["outfit"] != outfits[form][0]:
            raise ContractError("Unsupported or inconsistent outfit/form combination")
        style = spec["styles"][appearance["hair_style"]]
        shared = spec["shared"]
        paths = {slot: shared[key] for slot, key in SHARED_SLOTS.items()}
        paths.update({slot: style[key] for slot, key in HAIR_SLOTS.items()})
        paths["outfit"] = shared[outfits[form][1]]
        order = spec["render_order"]
        if len(order) != len(paths) or {item["slot"] for item in order} != set(paths):
            raise ContractError("Render order must contain each defined slot exactly once")
        if any(type(item["order"]) is not int for item in order):
            raise ContractError("Render orders must be integers")
        if len({item["order"] for item in order}) != len(order):
            raise ContractError("Duplicate render orders")
        layers = [{"slot": item["slot"], "order": item["order"],
                   "path": layer_path(paths[item["slot"]])}
                  for item in sorted(order, key=lambda item: item["order"])]
        if len({item["path"] for item in layers}) != len(layers):
            raise ContractError("Independent slots cannot alias the same image")
        return {
            "status": "draft_plan_not_asset_approval",
            "canvas": dict(canvas),
            "appearance": dict(appearance),
            "layers": layers,
            "masks": {
                "hair_color": {"path": layer_path(style["recolor_mask"]),
                               "color": appearance["hair_color"]},
                "eye_color": {"path": layer_path(shared["iris_mask"]),
                              "color": appearance["eye_color"]},
            },
        }
    except (KeyError, TypeError, AppearanceError) as exc:
        raise ContractError(f"Missing or unsupported draft field: {exc}") from exc


def inspect_png(root: Path, relative: str, *, expected_size=None, production=False) -> dict:
    """Check decoding/CRC, canvas, alpha, nonempty content and record SHA-256.

    This cannot establish semantic isolation (e.g. skin baked into hair), correct
    occlusion, or faithful recoloring. Those always require visual review.
    """
    result = {"path": relative, "status": "missing", "errors": []}
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        return {**result, "status": "invalid", "errors": ["path_outside_root"]}
    if not path.is_file():
        return result
    try:
        data = path.read_bytes()
        result.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        with Image.open(path) as img:
            if img.format != "PNG":
                raise ValueError("not_png")
            img.verify()
        with Image.open(path) as img:
            img.load()
            result.update(width=img.width, height=img.height, mode=img.mode)
            if expected_size and img.size != tuple(expected_size):
                result["errors"].append("wrong_canvas_size")
            has_alpha = "A" in img.getbands() or "transparency" in img.info
            result["has_alpha"] = has_alpha
            if has_alpha:
                low, high = img.convert("RGBA").getchannel("A").getextrema()
                result["alpha_range"] = [low, high]
            if production:
                if not has_alpha:
                    result["errors"].append("missing_alpha")
                else:
                    if high == 0:
                        result["errors"].append("empty_placeholder")
                    if low == 255:
                        result["errors"].append("opaque_background")
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as exc:
        result["errors"].append(f"unreadable_png: {exc}")
    result["status"] = "invalid" if result["errors"] else "technical_checks_passed"
    return result


def verify_source_manifest(root: Path) -> dict:
    """Compare imported bytes to the preserved, original handoff manifest."""
    manifest_path = root / HANDOFF_ROOT / "MANIFEST.json"
    if not manifest_path.is_file():
        return {"status": "pending_original_zip_and_MANIFEST.json", "files": []}
    manifest = read_json(manifest_path)
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise ContractError("Source manifest must contain a nonempty files list")
    results = []
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ContractError("Invalid source manifest entry")
        source = entry.get("path", "")
        if not isinstance(source, str):
            raise ContractError("Source manifest path must be a string")
        path = PurePosixPath(source)
        if (not source or path.is_absolute() or ".." in path.parts
                or "\\" in source or ":" in source or source in seen):
            raise ContractError(f"Unsafe or duplicate source manifest path: {source}")
        seen.add(source)
        if source == "README.md":
            destination = HANDOFF_ROOT / "README.md"
        elif path.parts[0] in {"assets", "experiments"}:
            destination = Path(source)
        else:
            raise ContractError(f"Unexpected source manifest path: {source}")
        full_path = (root / destination).resolve()
        if not full_path.is_relative_to(root.resolve()):
            raise ContractError(f"Source destination escapes project: {source}")
        result = {"source": source, "destination": destination.as_posix(), "status": "missing"}
        if full_path.is_file():
            data = full_path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            matches = digest == entry.get("sha256") and len(data) == entry.get("bytes")
            result.update(status="matched" if matches else "mismatch", sha256=digest, bytes=len(data))
        results.append(result)
    return {"status": "matched" if all(item["status"] == "matched" for item in results) else "mismatch",
            "manifest": (HANDOFF_ROOT / "MANIFEST.json").as_posix(), "files": results}


def audit(root: Path, appearance_path: Path | None = None) -> dict:
    root = root.resolve()
    spec = read_json(root / SCG_ROOT / "config/scg_layers.spec.json")
    appearance = read_json(appearance_path or root / SCG_ROOT / "config/appearance.default.json")
    plan = resolve_layer_plan(spec, appearance)
    references = []
    for filename, kind in REFERENCES.items():
        size = CANVAS if filename in ("semilong_reference.png", "twintails_reference.png") else None
        entry = inspect_png(root, (REFERENCE_ROOT / filename).as_posix(), expected_size=size)
        references.append({**entry, "classification": kind})
    all_paths = set(spec["shared"].values())
    for style in spec["styles"].values():
        all_paths.update(style.values())
    layers = [inspect_png(root, (SCG_ROOT / layer_path(path)).as_posix(),
                          expected_size=CANVAS, production=True) for path in sorted(all_paths)]
    required = {item["path"] for item in plan["layers"]}
    required.update(item["path"] for item in plan["masks"].values())
    required = {(SCG_ROOT / path).as_posix() for path in required}
    selected_ready = all(entry["status"] == "technical_checks_passed"
                         for entry in layers if entry["path"] in required)
    model_dir = root / "assets/characters/player/3d"
    model_files = []
    if model_dir.exists():
        for path in sorted(model_dir.rglob("*")):
            if path.is_file() and path.suffix.lower() in {".glb", ".gltf", ".fbx", ".blend"}:
                model_files.append({"path": path.relative_to(root).as_posix(),
                                    "bytes": path.stat().st_size,
                                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                    "status": "uninspected_model_file"})
    counts = lambda entries: {status: sum(item["status"] == status for item in entries)
                              for status in ("missing", "invalid", "technical_checks_passed")}
    return {
        "report_version": 1,
        "source_checksum_verification": verify_source_manifest(root),
        "summary": {
            "references": counts(references), "production_pngs": counts(layers),
            "selected_appearance": "technically_loadable" if selected_ready else "blocked_missing_or_invalid_layers",
            "production_art_approval": "not_established_by_this_tool",
            "model_files_found": len(model_files),
            "rig_and_animation_validation": "not_performed",
        },
        "references": references, "production_pngs": layers,
        "layer_plan": plan, "model_files": model_files,
        "manual_checks_required": [
            "Verify sRGB/profile, fringe, occlusion and alignment visually.",
            "Confirm hairless shared body restoration and independent hair content.",
            "Confirm tint masks do not affect skin, eye whites or background.",
            "Civilian outfit tint_mask.png is described in docs/09 but absent from the draft manifest.",
            "Inspect any supplied 3D model, shared rig, weights and animation clips.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--appearance", type=Path, help="Optional appearance JSON; unknown presets fail explicitly")
    parser.add_argument("--report", type=Path, help="Write the full audit JSON")
    args = parser.parse_args()
    try:
        report = audit(args.root, args.appearance)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
        complete = (report["summary"]["references"]["technical_checks_passed"] == len(REFERENCES)
                    and report["summary"]["selected_appearance"] == "technically_loadable"
                    and report["source_checksum_verification"]["status"] == "matched")
        return 0 if complete else 1
    except (OSError, ValueError) as exc:
        print(f"Asset audit error: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
