# witch

마녀도시 세계관을 바탕으로 구상 중인 **디아블로 2형 쿼터뷰 핵앤슬래시 RPG**. **Godot 4.6 + GDScript로 첫 도형 3D 전투 필드**를 구현했습니다. 기계장치의 마녀·적 2종·클릭 이동·기본 공격·산탄·공구 토글·태엽인형·포탑·HP/MP를 시험할 수 있습니다. 완성 아트와 성장/파밍 시스템은 아직 없습니다.

- **[전투 시안 실행·조작법·검증 결과](docs/godot_prototype.md)** — Godot에서 `game/project.godot` 열기, 또는 `powershell -ExecutionPolicy Bypass -File tools/run_godot.ps1`

- [인계 점검 결과·검증 도구 실행법·P0 구현 순서](docs/handoff_status.md)
- [전투 규칙 코드·시나리오 실행법·검증 범위](docs/combat_rules_harness.md) — `python -m combat_rules`

## 현행 기획 (v0.3 · 2026-10-25)

- [00 · 프로젝트 개요 및 설계 원칙](docs/00_overview.md)
- [01 · 세계관과 이름](docs/01_world.md)
- [02 · 전투와 조작](docs/02_combat.md)
- [03 · 기계장치의 마녀 스킬트리 — 검토용 초안](docs/03_skills.md)
- [04 · 아이템·장비·파밍](docs/04_items.md)
- [05 · 콘텐츠와 진행 구조](docs/05_content.md)
- [06 · 첫 시험판 범위](docs/06_vertical_slice.md)
- [07 · 스탯·능력치 및 자유 초기화](docs/07_attributes.md)
- [09 · 캐릭터 아트 제작·2D SCG·Tripo 3D·Codex 인계](docs/09_character_art_pipeline.md)
- [10 · UI·화면 구성](docs/10_ui.md)
- [결정·변경 이력](docs/decisions.md)

## 보존된 기획 기록

- [기획 기록 v0.1](docs/마녀도시_핵앤슬래시_기획기록_v0.1.md) — 최초 통합 스냅샷 (수정 없이 보존)

**문서 표기법:** `[합의]` 현재 설계 원칙 / `[원안/기존 구상]` 오래전 구상에서 이어진 설정 / `[제안]` 아직 결정되지 않은 후보 / `[미결]` 추후 논의 필요.

**단일 원본 원칙:** 규칙의 정확한 효력과 담당 문서는 [00 · 개요/문서 지도](docs/00_overview.md)에서 확인합니다. [06 · 첫 시험판](docs/06_vertical_slice.md)은 검증만, [결정 로그](docs/decisions.md)는 당시의 역사 기록만 유지합니다. 스킬 후보의 개별 명칭·효과는 일부만 확정되어 있습니다.
