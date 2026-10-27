# 현재 게임 연결 · 사용자 승인 v21

2026-10-27 사용자가 달리기 수정본을 승인하고 본 게임 교체를 요청했다. 현재 기본 자산은 `game/assets/characters/player/run_arm_v21/`의 body/hair/eyes/civilian 4개 GLB와 `runtime_contract.json`이다. 이 폴더의 `run_arm_v21.blend`는 변경 없이 보존한다. 기존 README/NEXT_OUTFIT/원본 계약의 후보 표기는 최초 비교 전달 당시 기록이며, **현재 게임 상태는 이 문서와 후속 integration manifest가 우선**한다.

- 기본 동작: `combat_run_rh_v21`과 v20의 idle/heavy_swing/thrust/cast/hit/collapse 6종. 이전 `combat_run_rh_v20`은 비교용이다.
- 오른손 위·왼손 아래. 모든 동작에서 계약의 지팡이 축 이동 키를 샘플링한다. v18의 고정 0/+0.28m 계산을 다시 사용하지 않는다.
- 같은 107본 rest와 최대8 의상 웨이트. 기존 1.75× 표시 크기, 3.242813140153885m/cycle, 실제 전투 시계/판정/전투 RNG를 유지한다.
- 본 게임의 8클립/215포즈 GPU 대조, 실제 손/지팡이 343표본, 게임 재생 1,287검사/547캡처, 동일 공격 성능 931검사/12사례, 외형 설정 회귀 7개를 통과했다. 범위·해시·실행 종료는 `reports/run_arm_v21/integration/delivery_manifest.json`을 따른다.
- 다음 의상 작업도 이 원본과 `player_humanoid_v11` 바인드를 사용한다. 변신복 원본은 `transformed_v1/fit_v4/transformed_fit_v4.blend`, 트윈테일 보관 파일은 `transformed_v1/hair_library/twintails_source_v1/`이다. 현재 게임 기본 외형은 일상복이다.

재현: `tools/validate_run_game_v21.ps1 -Phase import`, 이후 `parity`, `hands`, `gameplay`, `variants`. 일반 실행은 `game/project.godot`을 열고 F5 또는 `tools/run_godot.ps1`을 사용한다.

이번 승인은 현재 모션 선택에 관한 것이며 모든 의상 접촉·최종 성능 예산·밸런스 확정은 별도다. 기존 비교 원본과 보고서는 보존했다. 새 모션은 연속 비틀림, 의상 보조 뼈, 반복/전환과 실제 엔진 검사를 다시 수행한다. 변신/커스터마이징 UI는 이번 작업 범위에 포함하지 않았다.
