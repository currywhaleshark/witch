# 전투 필드 입장 변신 v25

사용자 요청으로 **지팡이 없는 평상복 → 지팡이 부품 조립 → 오른손으로 잡기 → 양손 대기 자세 → 빛과 함께 변신복 교체**를 실제 게임 입장에 연결했다. [게임 화면 리뷰](../../../../../../../reports/transformation_v25/review.html)와 [현재 입력·검증 기록](../../../../../../../reports/transformation_v25/delivery_manifest.json)을 따른다. 이번 연출은 사용자 검토 후보이며 기존 의상/모션 선택 기록을 변경하지 않는다.

## 시간과 게임 연결

| 입장 후 | 동작 |
|---|---|
| 0–0.30초 | 평상복, 빈손, 팔을 내린 자세 |
| 0.30–1.15초 | 손 앞에서 지팡이 자루·코어·부품 조립 |
| 1.20–1.40초 | 오른손을 닫아 완성된 지팡이를 잡음 |
| 1.50–2.10초 | 기존 오른손 위·왼손 아래 양손 대기 자세로 가져옴 |
| 2.12–2.85초 | 의상 빛 연출, 2.40초에 완전한 의상 슬롯 교체 |
| 3.00초 | 전투 시작 |

`game/scripts/field_entry_transformation.gd`는 별도 연출 시계를 사용한다. 떠 있는 지팡이를 뼈대 공간의 고정 프레임에 두고, 잡는 순간부터 현재 오른손의 기존 부착 프레임을 따른다. `staff_visual.gd`는 기존 자루/코어 9개 부품과 선택된 장식의 원래 변환을 보존하며 생성/조립만 샘플링한다. 공구 전환·날 구동·장비 장식 기능은 유지한다.

`arena.gd`는 이 동안 전투 시간, 적 이동/공격, 자원 변화와 전투 입력을 진행하지 않는다. Esc 정지/복귀, M 음소거, H 도움말은 동작한다. 재시작/맵 전환은 새 필드의 평상복·빈손부터 시작한다. 강제 사망은 남은 입장 연출을 취소하고 기존 쓰러짐으로 넘어간다. 새 게임에서 캐릭터가 카메라 쪽을 보며 시작하고 기존 카메라 크기/조명/이동 속도는 유지한다.

`field_entry_mode`는 Auto/Always/Disabled다. Auto는 일반 게임 실행에서 켜지고, 기존 평지 전투 테스트와 같은 scripted SceneTree에서는 생략한다. 입장 통합 검사와 리뷰는 **Always를 명시**하여 실제 경로를 검사한다. 반복 전투 시험에만 Disabled를 사용할 수 있다.

기존 `mechanical_impact.wav`를 조립 시작·잡기·의상 교체에 각각 한 번씩 피치/볼륨을 달리하여 재사용한다. 새 음원 생성은 없으며 음소거 검사와 파일 메타데이터/피크를 기록했다. 캡처 재생은 무음이고 별도의 청취 품질 판정은 하지 않았다.

## 자산과 보존

- 작성본 `transformation_v25.blend`는 v24에서 이어지며 **29개 메시·107개 rest 뼈·61개 기존 액션을 보존**한다. 팔의 내려놓기/뻗기/잡기/복귀만 새로 작성한 `combat_transform_entry_v25`를 추가했다. 외부 모션을 새로 다운로드하지 않았다.
- 새 동작은 73키/24fps/3초다. 마지막 자세는 현재 `combat_idle_rh_v20` 첫 자세에 일치한다. 다리·치마·가디건 지지 뼈는 조용한 대기를 유지한다.
- `3d/exports/transformation_v25/combat_transform_entry_v25.glb`와 게임 사본은 같은 리그의 클립 전용 파일이다. 작은 운반 메시 하나는 애니메이션 전송에만 쓰고 화면에는 추가하지 않는다.
- 게임의 `transformation_v25/outfit_transformed_v4.glb`는 기존 피팅 v4 수출본과 **바이트가 동일**하다. 13개 메시·94,718삼각형·최대 8웨이트와 원래 문양/2K 텍스처를 유지했다. 새 동작은 현재 v21 공통 뼈대가 구동한다.
- 몸체·머리·눈·AnimationPlayer는 같은 인스턴스다. `replace_parts`의 검증/원자적 교체를 사용하고 평상복을 먼저 지우는 단계를 만들지 않는다. 의상 교체 전후에 몸체 가림 영역도 계속 유지한다. 형상을 벗기거나 몸체만 표시하는 중간 프레임이 없다.
- `modular_character.spec.json`에 실제 변신복 수출본과 게임 경로를 등록했다. 트윈테일 원본은 보관 상태 그대로이며 별도 커스터마이징 UI는 추가하지 않았다.

## 검증 범위

사용자가 지적한 시작 팔 꼬임을 수정했다. 최초 방식은 전투 대기 자세의 위팔 회전을 팔을 내린 자세까지 운반해 팔꿈치 축에 대해 약 139도/152도 비틀린 상태였다. 현재는 v21의 rest 기준 팔꿈치 축과 연속 전완 비틀림 분산을 사용하고, 빈손 손바닥은 몸 안쪽을 향한다. 시작 팔꿈치는 약 32.6도, 손목 꺾임은 약 10도로 줄였다. 대기 자세에 도달하는 동안에만 기존 guard의 잔여 회전을 부드럽게 되돌려 최종 자세를 보존한다. [145개 자세의 전후 측정](../../../../../../../reports/transformation_v25/arm_fix/after.json)과 [이전 측정](../../../../../../../reports/transformation_v25/arm_fix/before.json)을 남겼다. 지팡이 조립 위치, 잡기/교체 시점, 기존 전투 클립은 변경하지 않았다.

저장 Blender 재열기에서 145개 정수/반 프레임, 보존된 메시/rest/액션, 손가락 굽힘, 양손 대기 접촉과 최종 대기 자세를 확인했다. 실제 Godot 임포트 뼈대 대조, 30/60/120fps 입장 순서·3초 길이·지팡이 부착·몸체/머리/눈 유지·전투 정지·입력 재개·일시정지·재입장·사망·음소거를 검사했다. 기존 캐릭터/지팡이/도약/슬롯 검사와 Python 외형 검사를 재실행했다. 정확한 총계·오차와 실행 해시는 최종 매니페스트에 기록한다.

리뷰는 60Hz 실제 arena 진행을 30fps로 촬영한 9장면/663장이다. 기본/뒤쪽/정지 비교는 평지 경기장, 실제 크기는 골목 시험 맵이며 각각의 게임 조명을 사용한다. 변신 후 달리기·공격·캐스팅·경직·점프도 촬영한다. 공격 상세 화면에서는 시험 표적 모델만 숨기며 타격 판정은 실제로 수행한다.

원본 v4의 국소 어깨·소매·머리/옷 접촉과 치마 접힘 한계는 남는다. 이번 작업은 새 의상 리토폴로지, 실시간 천/머리 물리, 모든 동작의 삼각형 접촉 해소, 최종 성능 예산 검증이 아니다. 의상은 기존 모습의 완전한 교체이며 천이 형태를 바꾸는 물리 시뮬레이션은 아니다.

## 다시 실행

Blender 작성/검사는 새 background 프로세스에서 `tools/build_transformation_v25.py`, `tools/finalize_transformation_v25.py` 순서로 실행한다. 현재 blend를 직접 손봤다면 build로 덮어쓰지 않고 finalize만 실행한다.

```powershell
& tools/run_transformation_v25.ps1 -Phase import
& tools/run_transformation_v25.ps1 -Test transformation_v25
& tools/run_transformation_v25.ps1 -Test staff_visual
& tools/run_transformation_v25.ps1 -Test spring_jump_v24
& tools/run_transformation_v25.ps1 -Test player_visual
& tools/run_transformation_v25.ps1 -Test loadout_dash
& tools/run_transformation_v25.ps1 -Phase review
python tools/package_transformation_v25.py
```
