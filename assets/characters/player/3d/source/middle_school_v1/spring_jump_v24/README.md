# 스프링 돌진 · 낮은 도약 v24

사용자가 제공한 `C:/Users/yurib/Downloads/Unarmed Jump.fbx`의 점프 느낌을 기존 스프링 돌진에 연결했다. [실제 게임 비교](../../../../../../../reports/spring_jump_v24/review.html)와 [최종 검사·현재 입력 해시](../../../../../../../reports/spring_jump_v24/delivery_manifest.json)를 따른다. 2026-10-31 사용자의 검토 후 커밋 요청으로 현재 발판 연출과 낮은 도약을 시험판에 채택했다([선택 기록](../../../../../../../reports/spring_jump_v24/approval.json)). 아래의 검증 범위와 남은 한계는 유지한다.

## 제작 파일과 원본

- `spring_jump_v24.blend`: 현재 작성본. `thrust_v23/thrust_v23.blend`를 기반으로 **29개 메시·107개 rest 뼈·60개 기존 액션을 보존**하고 `combat_spring_jump_v24` 하나를 추가했다.
- `runtime_contract.json`: 점프 클립, 이륙/착지 위상, 양손 지팡이 슬라이드와 실제 원본 출처.
- `../../../exports/spring_jump_v24/combat_spring_jump_v24.glb`: 49키/24fps/2초 길이의 정규화된 원본 클립. 게임은 짧은 실제 시전·돌진·착지 시간에 맞춰 구간별로 샘플링한다.
- `game/assets/characters/player/spring_jump_v24/`: 같은 뼈대의 클립 전용 GLB 및 계약. 기존 v21 본체·의상·머리·눈과 v23 찌르기 GLB는 재수출하지 않았다. `Outfit_Buttons_v7` 하나는 동일한 스킨/트랙 경로를 만들기 위한 운반 메시이며 게임에 추가로 표시하지 않는다.

FBX의 SHA-256은 `c3a76978f47439d4c929ebad881f277ade45d60b3543bf4e92821a979949bc68`, 실제 임포트 액션은 `Armature|mixamo.com|Layer0`, 원본은 1–71프레임/30fps다. 원본 사본은 `assets/characters/player/3d/source/motion_library/mixamo_local/Unarmed_Jump_user_2026-10-30.fbx`에 보관하며 기존 Git 제외 규칙을 따른다. Mixamo 원본을 CC0로 취급하거나 게임 산출물과 함께 재배포하지 않는다.

## 동작과 게임 연결

원본의 몸 낮춤 → 무릎 접기 → 착지 흐름을 옮기되 몸통/다리 회전은 약 55–67%로 줄였다. 이륙은 원본 25프레임, 공중 중앙은 35프레임, 착지는 45프레임, 충격 흡수는 52프레임 부근을 사용한다. 길게 서 있는 구간은 압축했다. 원본의 뿌리 이동과 큰 수직 이동은 가져오지 않는다. 팔은 기존 오른손 위/왼손 아래의 양손 그립을 몸통에 상대적으로 유지한다. 새 손목 풀이와 대기 자세의 비틀림 경로가 달라 중간 프레임에서 크게 도는 문제를 피한 구성이다.

`player_visual.gd`가 추가 GLB를 기존 애니메이션 라이브러리에 읽는다. 기존 발동 대기에는 점프 준비 구간 0–0.25, 실제 돌진에는 0.25–0.75, 착지에는 0.75–1을 사용한다. 일반 공격/캐스팅의 발동 위상 0.5와 기존 클립은 유지한다.

`spring_jump_motion.gd`는 **시각 모델에만** `0.32 × 4p(1-p)`m의 낮은 포물선을 더한다. `p`는 기존 돌진의 남은 거리를 통해 얻으며, 캐릭터 충돌체는 기존 지상 경로를 따른다. 기본 0.06초 발동 및 0.2초 돌진, 거리·마나·쿨다운·벽 충돌·피격 판정은 변경하지 않는다. 신발의 실제 높이는 32cm 모델 원점 상승에 무릎 접기까지 더한 값이다.

돌진 종료 후 0.12초의 착지 자세는 연출이며 새로운 입력 제한을 만들지 않는다. 새 공격/피격 동작은 점프 자세보다 우선할 수 있고 수직 오프셋은 따로 정리한다. 벽으로 조기 종료되면 현재 높이·자세에서 짧게 내려온다. 발동 전 취소는 이륙하지 않는다. 일시정지는 자세/높이/이동을 함께 멈추며 사망은 높이를 내리면서 기존 쓰러짐을 유지한다. 초기화·맵 전환은 상태를 제거한다.

스프링판 모델과 `spring_plate.gd`는 이전 v1 그대로다. 판의 작동/소멸과 기존 효과음은 계속 실제 발동을 따른다. 이번에 새 음원이나 물리 스프링은 추가하지 않았다.

## 확인 범위

저장 Blender를 다시 열어 정수 및 반 프레임 **97개**를 검사했다. 메시·기존 액션·rest 보존, 손가락 방향, 양손 접촉, 시작/끝 일치를 확인했다. 최대 양손 간격 오차는 약 0.00160mm, 포물선을 포함한 샘플 신발 바닥 오차는 최소 약 -0.081mm이며 시작/끝 행렬 차이는 0이다.

새 런타임 검사 **67개**에는 30/60/120fps × FCR 0/40, 기존 발동/소모/거리, 17개 실제 임포트 뼈 자세 대조, 양손 그립, 정지·취소·사망·초기화·맵 전환·높은 바닥·후속 행동이 포함된다. 임포트 뼈 위치 오차 최대 약 0.00414mm, 손 간격 오차 약 0.00168mm, 시각 포물선 오차 약 0.0000119mm, 지상 충돌체 높이 변경은 0이다. 조기 벽 종료의 시각 정리는 해당 콜백을 직접 호출해 검사했으며 임의 벽 배치 전체를 검증한 것은 아니다.

기존 발판 조립·돌진/슬롯·피격/막기·캐릭터 동작 검사를 함께 수행한다. 정확한 총계와 성공한 현재 파일 해시는 위 매니페스트를 따른다. GPU 리뷰는 **8장면/488장**, 60Hz의 실제 arena 경로를 수동 진행해 렌더 속도의 영향을 배제하며 현재 게임 조명을 사용한다. 캡처는 무음이고 HTML은 재생 속도·탐색을 제공한다. 브라우저 조작 자동검사는 수행하지 않았다.

이 검사는 일반 의상 접촉 보장이나 실시간 천 물리, 발을 실제 발판에 고정하는 접촉 풀이, 최종 성능 승인에 해당하지 않는다. 변신복은 새 점프의 별도 촬영/접촉 검사 대상이 아니며 현재 게임 일상복을 검토했다.

## 이어서 작업하기

`tools/build_spring_jump_v24.py`는 원본 FBX와 기존 캐릭터에서 별도 작성본을 만든다. `tools/finalize_spring_jump_v24.py`는 저장본을 다시 검사하고 클립을 수출한다. 둘 다 **새 백그라운드 Blender**에서 실행하며 사용자 세션을 덮어쓰지 않는다. 현재 작성본을 직접 수정했다면 다시 빌드하지 말고 finalize만 실행한다.

```powershell
& tools/run_spring_jump_v24.ps1 -Phase import
& tools/run_spring_jump_v24.ps1 -Test spring_jump_v24
& tools/run_spring_jump_v24.ps1 -Test spring_plate_v1
& tools/run_spring_jump_v24.ps1 -Test loadout_dash
& tools/run_spring_jump_v24.ps1 -Test hit_block
& tools/run_spring_jump_v24.ps1 -Test player_visual
& tools/run_spring_jump_v24.ps1 -Test build_windows
& tools/run_spring_jump_v24.ps1 -Phase review
python tools/package_spring_jump_v24.py
```

임포트는 24fps, immutable 트랙 보존, AnimationPlayer 최적화/압축 해제를 유지한다. 매니페스트 생성은 검사 이후 입력이 바뀌었으면 실패한다. 작업 전 `arena.gd`·`player_visual.gd`·발판·설정은 `reports/spring_jump_v24/baseline/`에 보관했다. 그때부터 스프링판과 `trial.json`은 동일하며, 동시에 진행되는 다른 작업자의 스킬/성장/UI 변경을 보존한다.
