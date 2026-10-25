import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from tools.scg_assets import CANVAS, ContractError, HANDOFF_ROOT, SCG_ROOT, inspect_png, read_json, resolve_layer_plan, verify_source_manifest


ROOT = Path(__file__).resolve().parents[1]


class LayerContractTests(unittest.TestCase):
    def setUp(self):
        self.spec = read_json(ROOT / SCG_ROOT / "config/scg_layers.spec.json")
        self.appearance = read_json(ROOT / SCG_ROOT / "config/appearance.default.json")

    def test_hair_switch_preserves_shared_assets_and_order(self):
        first = resolve_layer_plan(self.spec, self.appearance)
        self.appearance["hair_style"] = "twintails_v1"
        second = resolve_layer_plan(self.spec, self.appearance)
        self.assertEqual(len(first["layers"]), 9)
        self.assertEqual([item["order"] for item in first["layers"]], sorted(item["order"] for item in first["layers"]))
        for left, right in zip(first["layers"], second["layers"]):
            if left["slot"].startswith("hair_"):
                self.assertNotEqual(left["path"], right["path"])
            else:
                self.assertEqual(left, right)

    def test_unknown_presets_fail_without_fallback(self):
        for field in ("hair_style", "eye_shape", "body_preset", "outfit", "form", "expression"):
            with self.subTest(field=field):
                appearance = {**self.appearance, field: "not_created"}
                with self.assertRaises(ContractError):
                    resolve_layer_plan(self.spec, appearance)

    def test_reference_and_traversal_cannot_be_used_as_layers(self):
        for path in ("../reference.png", "layers/../../escape.png", "C:/image.png", "experiments/patch.png", "layers\\bad.png"):
            with self.subTest(path=path):
                spec = copy.deepcopy(self.spec)
                spec["styles"]["semilong_v1"]["front"] = path
                with self.assertRaises(ContractError):
                    resolve_layer_plan(spec, self.appearance)

    def test_bad_canvas_and_duplicate_slots_are_rejected(self):
        bad_canvas = copy.deepcopy(self.spec)
        bad_canvas["canvas"]["width"] = 1
        duplicate = copy.deepcopy(self.spec)
        duplicate["render_order"][0] = duplicate["render_order"][1]
        for spec in (bad_canvas, duplicate):
            with self.assertRaises(ContractError):
                resolve_layer_plan(spec, self.appearance)

    def test_plan_does_not_mutate_data_and_roundtrips(self):
        before = copy.deepcopy((self.spec, self.appearance))
        plan = resolve_layer_plan(self.spec, self.appearance)
        self.assertEqual((self.spec, self.appearance), before)
        self.assertEqual(plan, resolve_layer_plan(self.spec, json.loads(json.dumps(self.appearance))))


class ImageInspectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def inspect(self):
        return inspect_png(self.root, "sample.png", expected_size=CANVAS, production=True)

    def test_missing_is_not_success(self):
        self.assertEqual(self.inspect()["status"], "missing")

    def test_empty_full_size_placeholder_is_rejected(self):
        Image.new("RGBA", CANVAS).save(self.root / "sample.png")
        self.assertIn("empty_placeholder", self.inspect()["errors"])

    def test_one_pixel_placeholder_is_rejected(self):
        Image.new("RGBA", (1, 1)).save(self.root / "sample.png")
        self.assertIn("wrong_canvas_size", self.inspect()["errors"])

    def test_rgb_and_opaque_backgrounds_are_rejected(self):
        for mode, color, error in (("RGB", "white", "missing_alpha"), ("RGBA", "white", "opaque_background")):
            with self.subTest(mode=mode):
                Image.new(mode, CANVAS, color).save(self.root / "sample.png")
                self.assertIn(error, self.inspect()["errors"])

    def test_valid_png_has_hash_but_only_technical_pass(self):
        image = Image.new("RGBA", CANVAS)
        image.putpixel((100, 100), (120, 100, 80, 255))
        image.save(self.root / "sample.png")
        result = self.inspect()
        self.assertEqual(result["status"], "technical_checks_passed")
        self.assertEqual(len(result["sha256"]), 64)
        self.assertEqual(result["alpha_range"], [0, 255])

    def test_corrupt_png_is_rejected(self):
        (self.root / "sample.png").write_bytes(b"\x89PNG\r\n\x1a\ncorrupt")
        self.assertEqual(self.inspect()["status"], "invalid")

    def test_escape_is_rejected_before_reading(self):
        result = inspect_png(self.root, "../outside.png")
        self.assertEqual(result["errors"], ["path_outside_root"])


class SourceIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / HANDOFF_ROOT).mkdir(parents=True)

    def write_manifest(self, entries):
        (self.root / HANDOFF_ROOT / "MANIFEST.json").write_text(
            json.dumps({"files": entries}), encoding="utf-8")

    def test_imported_readme_is_checked_without_overwriting_project_readme(self):
        content = b"Original bundle README\n"
        (self.root / HANDOFF_ROOT / "README.md").write_bytes(content)
        (self.root / "README.md").write_bytes(b"Project documentation\n")
        self.write_manifest([{"path": "README.md", "bytes": len(content),
                              "sha256": hashlib.sha256(content).hexdigest()}])
        self.assertEqual(verify_source_manifest(self.root)["status"], "matched")

    def test_changed_and_missing_imports_cannot_pass(self):
        self.write_manifest([{"path": "assets/sample.png", "bytes": 8,
                              "sha256": hashlib.sha256(b"original").hexdigest()}])
        result = verify_source_manifest(self.root)
        self.assertEqual(result["status"], "mismatch")
        self.assertEqual(result["files"][0]["status"], "missing")
        (self.root / "assets/sample.png").write_bytes(b"modified")
        self.assertEqual(verify_source_manifest(self.root)["files"][0]["status"], "mismatch")

    def test_manifest_traversal_is_rejected(self):
        self.write_manifest([{"path": "assets/../../outside.png"}])
        with self.assertRaises(ContractError):
            verify_source_manifest(self.root)


if __name__ == "__main__":
    unittest.main()
