# Hand rebuild v29 — round hands fitted to the existing finger bones (game default)

The user found the v28 hands unnatural: very thin wrists and pointed fingers. Measuring the v28 body
(left hand, rest pose) confirmed it: the wrist section was 34 × 25 mm against a ~60 mm forearm, and
every finger segment was only 1–4 mm thick in its thinnest direction (v21: 10–15 mm). The fingers
were flat ribbons from the Tripo scan, so they read as pointed. At the user's choice ("새 손 메시로
교체") this candidate replaces only the hand geometry.

## What changed

- `hand_rebuild_v29.blend` is a copy of `model_refinement_v28.blend` in which only `Body_Hands_v7`
  has new geometry, material and weights. The v28 mesh is kept as `ARCHIVE_Hands_v28_mesh` (fake user).
  The v28 source itself is unchanged (hash checked before/after building).
- Built by [`tools/build_hands_v29.py`](../../../../../../tools/build_hands_v29.py): metaball capsules
  along every unchanged finger bone (proximal ~14 mm, tips ~10 mm), metacarpal capsules, a padded palm,
  thenar/hypothenar pads and a wrist that continues 45 mm up the forearm under the sleeves (v28: 20 mm).
  Voxel remesh (1.2 mm), smoothing and decimation give 7,198 triangles for both hands (v28: 7,978).
- Weights use the same bones as v28 (`DEF-forearm.*.002`, `DEF-hand`, 15 finger segments per side):
  finger ownership is gated at each knuckle, joints blend over ±3.5 mm, then six surface-smoothing
  passes remove abrupt owner changes between fingers. Maximum four influences.
- Material `HandsSkin_v29`: plain skin colour, the mean of the v28 hand atlas converted to linear
  (no texture, so no nails or knuckle shading yet).
- Measured (left hand, rest): wrist 47 × 42 mm, palm 60 mm wide, middle fingertip about 10 × 11 mm.

## Outputs and checks

- Export: [`tools/export_hands_v29.py`](../../../../../../tools/export_hands_v29.py) uses the v28 exporter
  and clip list → `exports/hand_rebuild_v29/body_standard_v29.glb`, copied to
  `game/assets/characters/player/hand_rebuild_v29/` with the v28 import settings (24 fps, no
  optimizer/compression, constant tracks kept).
- [`reports/hand_rebuild_v29/glb_comparison.json`](../../../../../../reports/hand_rebuild_v29/glb_comparison.json):
  against the v28 body GLB, all 107 inverse binds and all 2,568 animation channels are equal by name
  (max difference 0), and all body/face meshes except `Body_Hands_v7` are identical.
- Review: [`reports/hand_rebuild_v29/review/compare_v28_v29.jpg`](../../../../../../reports/hand_rebuild_v29/review/compare_v28_v29.jpg)
  and 24+24 close-ups from the real arena on a GPU (staff in hand, civilian and transformed outfits,
  idle / run / attack / cast) made by `game/tests/review_hand_rebuild_v29.gd`. That script swaps the
  body only inside its own run (resource-path takeover); game code is not changed.

## Not done / limits

- **Game default since 2026-11-01** at the user's request ("게임에 적용"): `player_visual.gd` `BODY_PATH`
  and the registry body/rig entries (`modular_character.spec.json`, sha256 and previous asset v28) point to
  the v29 body. Eyes and the civilian outfit stay v28. The other v28 integration lines in those files
  belong to another worker and were left as they were.
  Because v29 is built on the v28 body and the v28 game integration (assets, eyes/outfit paths,
  registry) is still uncommitted work of another worker, the `BODY_PATH`/registry switch and the
  AGENTS.md / docs/09 §3.37 entries are left in the working tree to be committed together with v28.
  Committed alone they would pair the v29 body with the v21 eyes/outfit, which was never tested.
- Plain colour material: no nails, knuckle or palm-line shading. Gripping fingers can merge visually
  where they press together; the shaft still passes through fingers as before (no contact solving).
- Regression runs after promotion are listed in `reports/hand_rebuild_v29/regression.json`. Applying it to the game
  is not a final art approval.
