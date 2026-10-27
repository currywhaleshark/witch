# 3D source assets status

The original ZIP handoff contained no 3D models.
On 2026-10-25, a real Tripo H3.1 GLB and a Blender import were added in
`middle_school_v1/`. See its README and inspection.json: one high-resolution
mesh, 1,980,284 triangles, three 4K textures, no rig or weights.
It is a source draft, not a game-ready export or replaceable-parts character.
The production pipeline and acceptance criteria live in `docs/09_character_art_pipeline.md` in the GitHub repository.
Do not fabricate placeholder FBX/GLB and claim an import was validated.

Current game motion delivery is the user-selected [v21 family](middle_school_v1/run_arm_v21/GAME_INTEGRATION.md): corrected run elbows/wrists plus six v20 right-handed motions, including the user-supplied Heavy Weapon Swing, equal-performance randomized thrust, one-hand casting and HP-zero collapse. Seven selected motions and the comparison-only v20 run use the complete v21 part family and per-clip staff slide curves. Main game, registry and display specification now point to v21. [v18](middle_school_v1/combat_motion_v18/README.md), v17 and v14 remain preserved historical sources.

The new [transformed-costume Tripo source](transformed_v1/README.md) was generated and imported on 2026-10-27 from front/back A-pose references, excluding the undecided staff. It contains one fused 1,947,342-triangle mesh and three packed 4K textures, with no rig or weights. The subsequent [v2 separated source](transformed_v1/parts_v2/README.md) preserves original geometry/UV/texture bytes across 64 pieces, hides the unwanted under-cape hair, and stores the [two independent twintail source meshes](transformed_v1/hair_library/twintails_source_v1/README.md) in a standalone blend and GLB. Open cut seams, fitting, weights and runtime exports remain unfinished. Fit working copies to the current v17 shared body rather than replacing its face, anatomy or rest matrices.

The current [transformed fitting candidate v3](transformed_v1/fit_v3/README.md) now fits 13 costume meshes to the unchanged v17 body/107-bone rig and preserves all 47 actions. Five-motion source/GLB/Godot pose checks and actual civilian-to-transformed replacement are recorded in its review. The 94,718-triangle outfit still has body/cloth contacts and is not promoted to the game or registry. The v2 and twintail archives remain unchanged; earlier fitting/export absence statements describe that source stage.

The subsequent [local repair v4](transformed_v1/fit_v4/README.md) remains the costume geometry editing entry point. It fixes boot/stocking intersections over its original 145 stored frames, refines cape/sleeve overlap and reduces hem/tail lift. Body/rest/actions and v3/twintail archives remain unchanged. Residual inner-shoulder/clothing contacts remain. Current gameplay uses civilian v21; the preserved reviews also swap this unchanged v4 outfit onto the new motions, without claiming new full contact clearance or promoting transformation defaults.

The following describes the historical [modular civilian v7 delivery](middle_school_v1/modular_civilian_v7/README.md).
Its `modular_civilian_v7_ready.blend` contains the shared body with face and
five-finger hands, separate semilong/eyes/civilian outfit, 83 deform bones and
11 diagnostic clips. The visible civilian assembly is 57,885 triangles, with
three color images up to 2K. Five real GLBs passed bind/weight checks, Blender
reimport and Godot 4.6.2 pose/swap validation at the selected 1.75x review scale.
[Its original NEXT_OUTFIT.md](middle_school_v1/modular_civilian_v7/NEXT_OUTFIT.md) records that stage's
deferred transformation-outfit guidance. User art approval, final combat animation,
close-up hair refinement and additional LODs remain separate. The registry
contains actual civilian paths; transformed/twintails remain null. All earlier
source/trial files are preserved. The main game was not changed for this delivery.


오른손잡이 시작 동작은 [v20](middle_school_v1/heavy_swing_v20/README.md), 최종 달리기 수정과 현재 게임 기본값은 [v21](middle_school_v1/run_arm_v21/GAME_INTEGRATION.md)을 따른다.
