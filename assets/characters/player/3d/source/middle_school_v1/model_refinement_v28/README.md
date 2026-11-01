# Model refinement v28 — shoes, original Tripo hands and local face forms

The user requested civilian shoe/ankle alignment, better hands using the original Tripo model if possible, and a face improvement. This derivative is integrated for review; no new user art approval is recorded.

Open `model_refinement_v28.blend`. The source is packed and preserves the accepted v27 hair, v26 entry gesture, 107 body rest bones and 63 body actions plus the independent eight-bone hair rig/action. Original models and prior deliveries remain intact. Start visual review at `reports/model_refinement_v28/review.html` from the repository root.

- **Hands:** extracted from the preserved 1,980,284-triangle Tripo raw GLB. The source cuff is removed, the palm/finger centerlines fit the existing rest skeleton and weights follow the existing animations. The new pair has 7,978 triangles (previous pair 8,588), up to four influences, and a 512×512 packed base-color atlas. A short forearm extension covers the sleeve/wrist join. This is fitted/reduced original geometry, not newly handcrafted quad topology.
- **Civilian shoes:** each moves outward 21mm onto the common ankle and follows its foot rigidly. Only the ankle-opening rim is smoothed; the loafer color/UVs and main shape remain. Sock bottoms extend 27mm into the shoes and blend into foot weights. Shoe UV seams are preserved; socks gain usable UVs.
- **Face:** the existing young face, painted eyes and UVs remain. Cheek/jaw transitions, soft chin, nose and lip relief change at most 1.3742mm; skin highlights are softened. This is intentionally a small form pass. A larger improvement in close-up expression would need separate face/eye texture and expression work.

The source keeps `ARCHIVE_*_pre_v28` comparison objects hidden. `TEMPLATE_CompleteCoveredBody_v8` is a preserved fitting reference, not an exported visible body. Do not unhide it for gameplay comparisons: it protrudes through source clothing and shoes.

Runtime replacements are only body, eyes and civilian outfit under `game/assets/characters/player/model_refinement_v28/`. The original v21 animation directory remains the motion/slide contract source; later v23/v24/v26 clips, v4 transformed outfit and v27 auxiliary hair remain external and unchanged. Both outfits use the same new hands/face. Garments keep up to eight weights.

Validation: three stored GLBs pass bind/UV/weight/animation checks; a fresh Blender reimport samples 40 poses. Current arena tests pass 3,104 entry/hair checks and 192 combat/presentation checks. Review contains 334 actual Godot frames. See the delivery manifest for exact hashes/scope and QA adjudication for intentional left/right separation and tiny source UV-seam reports. Existing large-pose garment contacts and hair edge artifacts are not repaired by this pass.

Authoring helpers: `tools/prepare_model_refinement_v28.py`, `refine_model_v28.py`, `finalize_model_v28.py`, `bake_hands_v28.py`; saved asset is authoritative. `finalize_model_v28.py` exports the selected saved derivative. Run `tools/run_model_v28.ps1` for import/test/review and `tools/package_model_v28.py` to refresh this package only after current-input validation.
