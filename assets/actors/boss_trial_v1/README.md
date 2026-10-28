# 시험판 보스·말뚝·문 v1

2026-10-28 요청에 따른 **게임 연결 검토 후보**다. 사용자의 외형 승인·최종 성능 예산 승인은 아직 없다. 기준은 `docs/08_scenario_draft.md` §6.3이며 시나리오 원문과 전투 수치는 변경하지 않았다.

- [실제 크기·동작 검토](../../../reports/boss_trial_v1/review.html)
- [최종 파일 해시·검증](../../../reports/boss_trial_v1/delivery_manifest.json)
- [생성 작업·원본·보존 파일 기록](production.json)

## 수정 시작 파일

| 자산 | Blender 작업 파일 | 런타임 삼각형 | 부품 / 뼈 | 텍스처 | 크기 |
|---|---|---:|---:|---|---|
| 빗장 보스 | `authoring/latch_v1.blend` | 27,923 | 98 / 119 | 2K PBR 3장, 2재질 | 원본 리그 2m, 기존 보스 배율 2.24로 게임 4.48m |
| 유인 말뚝 | `authoring/stake_v1.blend` | 6,499 | 1 / 2 | 1K PBR 3장, 1재질 | 2.6m, 최대 수평 반경축 0.46503m |
| 교차 사격 문 | `authoring/door_v1.blend` | 8,962 | 60 / 62 | 1K PBR 3장, 1재질 | 2.3m |

모든 작업 파일에 텍스처가 packed 상태로 들어 있다. `exports/*_v1.glb`와 `game/assets/actors/boss_trial_v1/*_v1.glb`는 바이트가 같다. 단위는 m, 런타임 정면은 Godot -Z다. 각 부품의 모든 정점은 해당 part 뼈에 가중치 1로 연결된다. 파트의 회전에 따라 나무·금속을 늘이는 혼합 스키닝은 사용하지 않는다.

소스는 `source/*_tripo_h31_raw.glb` 3개, 보스·문 `*_tripo_segmented.glb` 2개 및 packed raw import `.blend`다. 소스를 덮어쓰지 않는다. 원화는 `assets/reference/actors/boss_trial_v1/`와 각 generation JSON에 있다. Tripo H3.1, 80k 요청, 2K PBR, Ultra/AI 보정 끔, 비공개 생성이며 보스 98개/문 60개 부품 분할과 UV packing을 받았다. 생성 90 + 분할 80 = 170 credits를 사용했다. CC0 외부 라이브러리로 표시하지 않는다.

이번 세션은 Blender MCP가 연결되지 않아 **설치된 Blender 5.1.1의 background CLI**로 작업했다. 저작 모델은 UV를 유지한 파트별 decimation 파생본이지 수작업 리토폴로지 결과가 아니다. 말뚝 감소 후 바닥을 0으로 다시 맞췄다. 보스 불씨 파트 77은 게임의 비스듬한 시점에서 보이도록 앞(+Y)으로 12cm 옮기고 별도 발광 재질을 부여했다. 다른 생성 소스 형상을 재설계한 것은 아니다.

## 동작과 게임 연결

보스는 `idle`, `move`, `sweep`, `slam`, `frames`, `shockwave`, `hit`, `death` 8클립이다. 24fps이며 이동 1초, 피격 0.5초, 나머지 2초다. Blender에서 작성하고 프레임별로 구운 동작으로 외부 모션 캡처가 아니다. 네 다리는 두 구간 IK로 발을 지지하며, 자물쇠를 높이 들었다 내릴 때 몸을 낮춘다. 사망은 실제 분리 부품이 중력과 바닥 지지를 따라 무너지는 사전 계산 동작이다. 문은 `idle`, `open`, `close` 3클립이며 말뚝의 `idle`은 정적이다.

`game/scripts/actor_visual.gd`의 `latch`가 새 GLB를 불러오고 `boss_visual.gd`가 기존 arena 타이머와 발동 이벤트로 자세를 선택한다. **발동 프레임은 해당 공격 클립의 0.5**다. 휩쓸기 발동과 내려찍기 시작이 같은 업데이트에서 일어날 때는 휩쓸기의 접촉 자세를 한 업데이트 표시한 후, 남은 실제 windup으로 내려찍기를 시작한다. 피해·범위·재사용·소환 규칙은 arena에 남는다. 단순 도형용 몸체 흔들기와 보스의 고정 머리띠만 새 리그 표시에서 제외하고 등급 바닥 고리·체력 표시는 유지한다.

`boss_door_visual.gd`는 경첩 애니메이션과 푸른 통로 막을 표시한다. 문은 기존 경고 시간 초기에 열리고 발사 순간에 빛이 강해지며 기존 effect 수명으로 제거된다. 막의 시간은 엔진 TIME 대신 arena가 넘기는 dt를 쓰므로 일시정지에도 멈춘다. `shapes.gd`의 문 생성 경로와 `alley_props.gd`의 말뚝만 새 모델로 연결한다. 충격파 중심은 기존대로 보스이며 말뚝으로 옮기지 않는다. 말뚝 collider 0.96 × 0.96m와 지도/내비게이션은 그대로다.

사망 시 목표·충돌을 즉시 제거하고 현재 자세부터 짧게 이어진 잔해만 남긴다. 일시정지/재시작/수명 종료 정리를 기존 소환물 방식과 공유한다. 잔해는 combat RNG를 소비하지 않는다. **실시간 물리, 부품끼리·벽·임의 지형의 충돌은 구현하지 않았다.**

임포트는 24fps, `animation/remove_immutable_tracks=false`, `animation/trimming=false`, AnimationPlayer `optimizer/enabled=false`, `compression/enabled=false`를 유지한다. 최적화를 켜면 짧은 hit 클립의 기준 자세가 수 mm 달라질 수 있다. 현재 `.glb.import`에 설정을 저장했다.

## 확인한 범위

- GLB 3개: 정점·인덱스·UV·역바인드·정규화된 단일 강체 가중치, 예산, 텍스처, 0초 시작, 뼈당 TRS 상수 트랙, export/runtime 동일 해시.
- 독립 Blender 재실행: 저장한 3개 blend 재열기와 3개 GLB 재임포트, 72개 기준 자세, 뼈/삼각형/동작/packed image 확인. glTF 임포터가 생성하는 80삼각형 bone display shape는 실제 custom_shape 참조로 식별해 모델 수량에서 제외한다.
- Godot 4.6.2 `boss_art`: 28,673 checks. 36개 기준 자세의 뼈 머리 위치가 Blender와 최대 약 **0.00054mm** 오차. 25회/클립 강체 변환 검사, 실제 스킨 정점의 바닥 높이 및 말뚝 폭, 4패턴 발동, 연계, pause, 문 발사·정리, 사망 시작 자세/비충돌/정리 검사. 이것은 엔진 뼈/CPU 스킨 좌표 검사이며 GPU 정점 readback 검사가 아니다.
- 기존 boss 21, map_nav 49, combat_actors 9,109, summons_v2 50,821 checks 통과. 마지막 두 수치는 정점/뼈 반복 검사도 포함한 assertion 수다. 보스·맵·소환물 회귀는 표시용 불씨 재질/12cm 전진 최종 수정 이전 실행이고 해당 전투 코드·지도·소환물 자산은 동일하다. 수정 후 GLB·저장 파일·boss_art·combat_actors·GPU 촬영을 다시 확인했다.
- 실제 GPU 촬영 325장: C구역/HUD/크기 비교 2, 실제 arena 전투 연계 68, 문 사격 4, 확대 동작 251. 확대는 수동 seek, `combat_chain`은 실제 arena 업데이트다. 출력/실행 기록 및 완료 마커를 보존했다.
- 전투 수치, `alley_v2.json`, 플레이어 표시/모듈 코드, 시나리오 원문은 작업 시작 해시와 같다.

Godot의 작업 영역 밖 `user://` shader cache/profiler 경고와 Blender의 사용자 thumbnail 폴더 쓰기 경고가 실행 기록에 있다. 지정 출력의 저장·재열기·임포트는 통과했다. 확대 시 생성 표면·부품 경계 거칠음, 낡은 판재의 구멍, 임의 자세 접촉, 최종 성능 및 사용자 외형 판정은 별도다.

## 문 닫힘 폭 수정 v2 (2026-10-28)

사용자가 지적한 틈은 문짝 폭 부족이었다. 경첩을 기준으로 모든 움직이는 판재·철물의 rest 폭을 1.28배로 함께 보정하고 같은 `door_v1.blend`/GLB/게임 경로에 반영했다. 문틀 정점, 고정 뼈와 경첩 rest, 토폴로지·UV·가중치·packed 텍스처, 세 클립 곡선은 수정 전 저장본과 같다. 애니메이션 중 scale을 늘리는 방식이 아니다. 분할된 판재 조각을 따로 이동하면 판재 안에 틈이 생기므로 연결 부품에 같은 폭 변환을 적용한다.

[전후 및 여닫기 비교](../../../reports/door_fit_v2/review.html), [독립 저장본 비교·실측](../../../reports/door_fit_v2/fit_validation.json)을 참고한다. 정면 높이 0.4–1.7m에서 손잡이 쪽 최대 틈은 204mm → 4mm였다(가로 2mm/세로 10mm 광선 표본). 전체 개구부의 미피복 비율은 약 26.69% → 2.96%이며 원래 판재의 작은 구멍까지 막지는 않았다. 문틀과 움직이는 부품 사이의 모든 접촉을 보장하는 검사는 아니다.

수정 후 GLB 구조, 독립 Blender 저장본 재열기/재임포트, Godot `boss_art` 28,673 checks 및 GPU 325장 촬영을 다시 통과했다. 문 뼈 위치 오차는 최대 약 0.00018mm다. 보스·말뚝과 Tripo 원본 해시는 그대로다. 기존 `boss`/`map_nav`/`combat_actors`/`summons_v2` 결과는 이전 실행을 유지하며 이번 문 수정에서 다시 실행한 결과로 표시하지 않는다.

## 재현

`tools/build_boss_trial_v1.py`를 Blender background에서 실행한다(`-- latch stake door`). 이후 `tools/run_boss_trial_v1.ps1 -Phase import`, `boss_art`, `review` 순서로 임포트/검사/촬영한다. 기존 회귀 phase는 `boss`, `map_nav`, `combat_actors`, `summons_v2`다. `tools/verify_boss_saved_v1.py`는 Blender 재열기/재임포트만 수행한다. `tools/validate_boss_glbs_v1.py`와 `tools/package_boss_trial_v1.py`가 바이너리 검사와 검토 페이지/매니페스트를 작성한다. 소스를 자동 재생성하거나 Tripo 작업을 다시 구매하는 명령은 없다.
