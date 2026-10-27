# 다음 의상·모션 작업

`run_arm_v21.blend`와 `runtime_contract.json`에서 시작한다. `player_humanoid_v11` 107개 rest bone과 최대8 garment weight를 지킨다. v20 7개 동작 중 달리기만 `combat_run_rh_v21`로 바꾼 후보이며, 공격/대기/캐스팅/경직/쓰러짐과 기존 58개 액션을 보존한다. 현재 게임 기본값은 v18이며 승격 전에는 별도 비교본으로 다룬다.

변신복은 `transformed_v1/fit_v4/transformed_fit_v4.blend`와 해당 GLB, 분리 트윈테일은 `transformed_v1/hair_library/twintails_source_v1/`을 보존한다. 다른 rest family와 섞지 않는다. 새 클립은 관절면·연속 비틀림·의상 보조 뼈·양손 접촉·실제 엔진 표시를 다시 검토한다. 지팡이는 아직 임시 디자인이다.
