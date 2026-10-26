# Project handoff rules for Codex

Read [docs/00_overview.md](docs/00_overview.md) before editing. **The user's immediate goal is the minimal 3D combat-field prototype** described in [docs/06_vertical_slice.md](docs/06_vertical_slice.md): one machinery witch, basic enemies/controls/attacks/HP-MP, **no scenario, dong office hub, dialogue UI or character customization UI yet**.

For planned full-game story, see the **in-progress** [docs/08_scenario_draft.md](docs/08_scenario_draft.md). Keep the attached v0.3 draft verbatim as source material; do not implement its 4-act storyline, dialogue, hub NPCs, or scenario field suggestions in the P0 combat-only prototype without a separate request. Draft labels are not implementation approvals.

For character art and later 2D/3D customization, read [docs/09_character_art_pipeline.md](docs/09_character_art_pipeline.md). Its references are delivered as a separate ZIP (witch_character_art_codex_handoff.zip). The 2D PNGs are NOT currently in GitHub. Check imports and report missing files rather than inventing completion.

Single source of truth: controls/mana in docs/02_combat.md, machinery skill design in docs/03_skills.md, item system in docs/04_items.md, world/class identity in docs/01_world.md, combat damage in docs/07_attributes.md, art production pipeline in docs/09_character_art_pipeline.md, and HUD/menu layout in docs/10_ui.md. Keep docs/06_vertical_slice.md focused on test cases, docs/decisions.md historical only. New unresolved ideas remain proposals, not approved rules.

Do not call a patched full-image hair swap a true replaceable 2D hair layer. Production requires one fixed shared face/body and independent transparent hair components. Do not claim Tripo meshes, shared rigs, costumes, or finished PSD layers exist before inspecting concrete assets.
