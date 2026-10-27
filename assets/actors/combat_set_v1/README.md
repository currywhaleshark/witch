# 몬스터·소환물 5종 — 게임 연결 후보 v1

> **후속 수정:** 태엽인형과 포탑의 현재 게임용 자산은 [분할 소환물 v2](../summons_v2/README.md)다. 사용자 분할 원본을 사용하며 회전부를 강체로 나누고 일반 파괴와 자폭 비산을 구분한다. 이 폴더의 v1 원본/모션/검증은 당시 비교 자료로 보존한다. 적 3종은 계속 v1을 사용한다.

2026-10-28. 사용자가 요청한 시나리오 초안 6장의 **그을음 넝마귀·전선 까마귀·철문 아귀**, **태엽인형·자동포탑**을 현재 Godot 시험판에 연결했다. 소환물 외형은 사용자가 선택한 **낡은 황동·청록, 기계장치 마녀와 통일**이다. 최종 외형/동작 승인은 아직 받지 않았다.

- 확인 화면: [실제 게임 크기와 동작](../../../reports/combat_actors_v1/review.html)
- 최종 파일 해시·검증: [delivery_manifest.json](../../../reports/combat_actors_v1/delivery_manifest.json)
- 생성 작업 번호·초기 예산: [production.json](production.json)
- 모델링 원화 5장과 프롬프트: [reference/actors/combat_set_v1](../../reference/actors/combat_set_v1/)

## 보존 원본과 저작 파일

`source/<id>_tripo_h31_raw.glb`는 실제 Tripo 다운로드 원본이다. H3.1, Ultra 끔, 약 80k 삼각형 요청, 2K PBR, 비공개로 각각 30크레딧을 사용했다. 총 5건/150크레딧이며 추가 유료 분할·리깅·리토폴로지는 실행하지 않았다. 같은 이름의 `.blend`는 원본 임포트와 텍스처 패킹본이다. 원본을 덮어쓰지 않는다.

편집 시작 파일은 `authoring/<id>_v1.blend`, 게임용 내보내기는 `exports/<id>_v1.glb`다. 게임에는 같은 바이트를 `game/assets/actors/combat_set_v1/`로 복사했다. 플레이어 v21과 별도 리그다.

| id | 이름 | 게임용 삼각형 | 뼈 | 클립 |
|---|---|---:|---:|---:|
| rag | 그을음 넝마귀 | 12,000 | 14 | 5 |
| crow | 전선 까마귀 | 10,000 | 11 | 5 |
| brute | 철문 아귀 | 17,999 | 14 | 6 |
| automaton | 태엽인형 | 10,000 | 15 | 5 |
| turret | 자동포탑 | 7,999 | 5 | 4 |

텍스처는 각 모델 1K 색/노멀/금속·거칠기 맵, 최대 4개 뼈 영향이다. 면 수는 초기 작업 예산이며 최종 성능 예산 승인을 의미하지 않는다. Blender 자동 축약과 UV 보존으로 만든 사본이며 수작업으로 다시 짠 변형용 토폴로지라고 부르지 않는다.

시나리오 원문은 작업 시작 당시 로컬에 없어 Git `7fa2416:docs/08_scenario_draft.md`의 6.2절을 읽었다. 해당 원문은 원화 폴더의 `scenario_6_2_reference.txt`에 출처와 함께 보관한다. 시나리오 진행이나 새 전투 규칙을 구현한 작업은 아니다.

## 관절·동작

계산용 표면 그래프에서 UV 중복 좌표를 묶어 팔과 몸/다리의 거리를 구한다. 떨어진 조각은 연결 성분 단위로 분류한다. 원래 위치만으로 가중치를 주면 손끝/철문이 가까운 다리로 잘못 붙었기 때문이다. 철문 판은 아래팔, 태엽은 몸 뒤, 포신과 상부 회전대는 각각의 관절을 사용한다. 최종 원본/내보내기에는 계산용 용접을 적용하지 않는다.

직접 저작한 초기 모션 25개다. 외부 모션 캡처나 Tripo 자동 애니메이션을 사용한 것으로 설명하지 않는다.

- 넝마귀·까마귀·태엽인형: `idle`, `move`, `attack`, `hit`, `death`.
- 철문 아귀: 위 5개와 `charge`.
- 포탑: `idle`, `attack`, `hit`, `death`. 조준 회전은 런타임 상부 관절에 합성한다.
- 전방은 Godot `-Z`, 단위는 m. 포탑 원본은 다른 네 모델과 정면 축이 달라 별도로 회전했다.
- 지상 모델의 발 위치는 전달한 프레임에서 지면에 맞췄고, 까마귀는 부유 후 사망 때 내려온다. 실제 속도에 맞춘 정교한 발 고정/보행 IK 시스템은 아니다.
- GLB 임포트는 **24fps, `remove_immutable_tracks=false`, 자동 LOD 끔**이다. 상태 전환 때 고정 기준 트랙이 사라지면 이전 클립 포즈가 남을 수 있다.

## 런타임 계약

[actor_visual.gd](../../../game/scripts/actor_visual.gd)는 표현만 담당한다. `shapes.gd`가 적 3종 모델을 생성하고, `arena.gd`가 기존 전투 상태를 전달한다. 보스/이전 시험용 종류의 도형 외형은 유지한다.

- 적 준비 시간은 기존 `windup`, 실제 발동 프레임은 `attack`의 **0.5**를 사용한다. 이동/돌진은 실제 프레임 이동 거리로 재생한다.
- 소환물의 대상 선택·이동·피해·쿨다운·수명·만료 폭발은 기존 코드다. 사격 광선의 시작점만 모델의 공격 지점으로 옮겼다.
- 포탑 하부는 고정하고 상부만 조준한다. 대기 탐색과 포신 반동은 시각 동작이다.
- 처치 순간 기존 대상/충돌은 즉시 제거한다. 남은 외형만 월드로 분리해 쓰러진 뒤 1.5초에 정리한다. 일시정지와 필드 초기화를 따른다.
- 피해/마나/사거리/속도/타깃팅/충돌 크기/전투 RNG를 변경하지 않는다. 원래 종류별 `scale`과 1.75배 카메라를 유지한다.

## 재생성·검사

1. `blender -b --factory-startup -t 4 -P tools/build_combat_actors_v1.py -- rag crow brute automaton turret`
2. `python tools/validate_actor_glbs_v1.py`
3. `blender -b --factory-startup -t 4 -P tools/validate_actor_deformation_v1.py -- rag crow brute automaton turret`
4. `tools/run_combat_actors_v1.ps1 -Phase import`, `-Phase runtime`, `-Phase review`.
5. `-Phase test -Test enemy_types` / `boss` / `grades_hits` / `smoke_arena`.
6. `python tools/package_combat_actors_v1.py`.

별도 GLB 검사에서 바인드·정규화 가중치·인덱스·텍스처·유한 애니메이션 값·게임 복사본 해시를 확인한다. 실제 GPU 런타임 검사에서 5종/25클립, 반복 끝점, 실제 공격 시점, 포탑 조준, 일시정지와 사망 정리를 확인했다. 확대 동작 425장과 실제 크기/게임 화면 2장을 저장한다. 전투 회귀 결과와 실행 종료 코드는 manifest를 따른다. 작업 환경의 `user://` 캐시/에디터 프로파일러 경고는 숨기지 않고 실행 기록에서 구분한다.

## 남은 범위

작은 화면의 첫 연결본이다. 원본에 붙어 있는 어깨/골반/날개 접합부에는 접힘과 국소 늘어남이 남는다. `reports/combat_actors_v1/build/<id>/deformation.json`은 실제 프레임의 8mm 초과 모서리 신장 측정이며, 무변형/무관통 통과 선언이 아니다. 임의 자세, 다수 개체 성능, 최종 동작 느낌과 외형은 추가 검토 대상이다. 현재 큰 방패/손끝이 다리를 따라 찢어지는 오류를 수정한 결과부터 이어간다.
