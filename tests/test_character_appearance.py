import copy
import json
from pathlib import Path
import tempfile
import unittest

from tools.character_appearance import (
    AppearanceError, active_outfit, choose_form, choose_outfit,
    legacy_renderer_view, normalize_appearance, resolve_3d_plan,
)
from tools.scg_assets import resolve_layer_plan


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "assets/characters/player"


class ModularAppearanceTests(unittest.TestCase):
    def setUp(self):
        self.state = json.loads((PLAYER / "scg/config/appearance.default.json").read_text(encoding="utf-8"))
        self.spec = json.loads((PLAYER / "3d/config/modular_character.spec.json").read_text(encoding="utf-8"))

    def test_transformed_outfit_change_survives_untransform_and_save_load(self):
        # Fixture ID only: this test does not invent a production costume.
        variant = {**self.spec["outfits"]["transformed_v1"], "id": "test_transformed_b"}
        self.spec["outfits"][variant["id"]] = variant
        original = copy.deepcopy(self.state)
        transformed = choose_form(self.state, "transformed")
        changed = choose_outfit(transformed, "transformed", variant["id"], self.spec)
        civilian = choose_form(changed, "civilian")
        restored = choose_form(json.loads(json.dumps(civilian)), "transformed")
        self.assertEqual(active_outfit(civilian), "civilian_v1")
        self.assertEqual(active_outfit(restored), variant["id"])
        self.assertEqual(restored["form"], "transformed")
        for key in ("body_preset", "hair_style", "hair_color", "eye_shape", "eye_color"):
            self.assertEqual(restored[key], original[key])
        self.assertEqual(self.state, original)

    def test_missing_asset_fixture_blocks_both_forms(self):
        spec = copy.deepcopy(self.spec)
        for part in [spec["rig"], *spec["bodies"].values(), *spec["hair"].values(),
                     *spec["eyes"].values(), *spec["outfits"].values()]:
            part.update(asset=None, status="not_created")
        for form in ("civilian", "transformed"):
            plan = resolve_3d_plan(spec, choose_form(self.state, form), PLAYER / "3d")
            self.assertFalse(plan["production_ready"])
            self.assertEqual(plan["status"], "blocked_missing_production_assets")
            self.assertIn("rig:not_created", plan["blockers"])
            self.assertIn("outfit:not_created", plan["blockers"])
            self.assertIsNone(plan["parts"]["body"]["asset"])

    def test_civilian_export_resolves_but_transformed_design_stays_missing(self):
        civilian = resolve_3d_plan(self.spec, self.state, PLAYER / "3d")
        self.assertEqual(civilian["status"], "ready_for_runtime_validation")
        self.assertEqual(civilian["blockers"], [])
        # File availability does not replace the separate Godot/visual report.
        self.assertFalse(civilian["production_ready"])
        transformed = resolve_3d_plan(self.spec, choose_form(self.state, "transformed"), PLAYER / "3d")
        self.assertIn("outfit:not_created", transformed["blockers"])
        self.assertIsNone(self.spec["hair"]["twintails_v1"]["asset"])
        self.assertIsNone(self.spec["outfits"]["transformed_v1"]["asset"])

    def test_wrong_form_body_or_rig_rejected_without_mutation(self):
        original = copy.deepcopy(self.state)
        with self.assertRaises(AppearanceError):
            choose_outfit(self.state, "transformed", "civilian_v1", self.spec)
        for field in ("body_preset", "rig_id"):
            spec = copy.deepcopy(self.spec)
            spec["outfits"]["transformed_v1"][field] = "incompatible"
            with self.assertRaises(AppearanceError):
                choose_outfit(self.state, "transformed", "transformed_v1", spec)
        self.assertEqual(self.state, original)

    def test_legacy_migration_and_ambiguous_state_rejection(self):
        legacy = legacy_renderer_view(self.state)
        self.assertEqual(normalize_appearance(legacy), self.state)
        with self.assertRaises(AppearanceError):
            normalize_appearance({**self.state, "outfit": "transformed_v1"})

    def test_2d_and_3d_resolve_the_same_active_outfit(self):
        scg = json.loads((PLAYER / "scg/config/scg_layers.spec.json").read_text(encoding="utf-8"))
        for form in ("civilian", "transformed"):
            state = choose_form(self.state, form)
            layer_plan = resolve_layer_plan(scg, state)
            model_plan = resolve_3d_plan(self.spec, state, PLAYER / "3d")
            layer = next(layer for layer in layer_plan["layers"] if layer["slot"] == "outfit")
            self.assertIn(model_plan["active_outfit"], layer["path"])

    def test_missing_files_and_nonproduction_sources_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            spec = copy.deepcopy(self.spec)
            spec["rig"].update(status="validated", asset="exports/missing.glb")
            plan = resolve_3d_plan(spec, self.state, directory)
            self.assertIn("rig:file_missing", plan["blockers"])
            for invalid in ("../other.glb", "source/raw.glb", "C:/other.glb"):
                spec["rig"]["asset"] = invalid
                with self.assertRaises(AppearanceError):
                    resolve_3d_plan(spec, self.state, directory)


if __name__ == "__main__":
    unittest.main()
