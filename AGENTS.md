# Project handoff rules for Codex

Read [docs/00_overview.md](docs/00_overview.md) before editing. **The user's immediate goal is the minimal 3D combat-field prototype** described in [docs/06_vertical_slice.md](docs/06_vertical_slice.md): one machinery witch, basic enemies/controls/attacks/HP-MP, **no scenario, dong office hub, dialogue UI or character customization UI yet**.

For character art and later 2D/3D customization, read [docs/09_character_art_pipeline.md](docs/09_character_art_pipeline.md). Its separate ZIP (witch_character_art_codex_handoff.zip) has been imported and the seven reference PNGs were pushed to GitHub on 2026-10-25 (9e8aa55, included in 9b711cd). Production layers and 3D character assets are still missing. Check imports and report missing files rather than inventing completion.

The initial Godot 4.6 + GDScript combat prototype is in `game/`. Read [docs/godot_prototype.md](docs/godot_prototype.md) for running it and its explicit trial assumptions. Keep the Python input scenarios as a shared porting contract. Do not equate passing automated checks with play-feel or final-balance approval.

Single source of truth: controls/mana in docs/02_combat.md, machinery skill design in docs/03_skills.md, item system in docs/04_items.md, world/class identity in docs/01_world.md, combat damage in docs/07_attributes.md, art production pipeline in docs/09_character_art_pipeline.md, and HUD/menu layout in docs/10_ui.md. Keep docs/06_vertical_slice.md focused on test cases, docs/decisions.md historical only. New unresolved ideas remain proposals, not approved rules.

Do not call a patched full-image hair swap a true replaceable 2D hair layer. Production requires one fixed shared face/body and independent transparent hair components. Do not claim Tripo meshes, shared rigs, costumes, or finished PSD layers exist before inspecting concrete assets.
