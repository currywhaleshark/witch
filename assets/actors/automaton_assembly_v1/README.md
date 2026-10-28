# 태엽인형 시전 조립·중단 v1

2026-10-28 사용자 요청: 캐스팅 동안 빛무리와 함께 부품 생성·조립, 피격 경직 등으로 취소되면 현재 상태에서 중단하고 붕괴한다. 현재 시험판에 연결한 검토 후보이며 사용자 연출 채택 전이다.

- [성공·취소·실제 크기 검토](../../../reports/automaton_assembly_v1/review.html)
- [검증·저장 파일 해시](../../../reports/automaton_assembly_v1/delivery_manifest.json)
- 외형 사본: `authoring/automaton_parts.blend`, `exports/automaton_parts.glb`, `parts.json`.
- 연출 수정: `game/scripts/automaton_assembly.gd`. 생성 순서·이동·빛·낙하를 코드에서 조정한다.
- 연결: `game/scripts/arena.gd`의 `begin_cast`, `tick_windup`, `cancel_automaton_assembly`, `execute_cast`, `damage_player`, `reset_arena`.

## 외형과 시계

사용자가 채택한 `summons_v2/authoring/automaton_v2.blend`의 idle 첫 프레임을 평가해 13개 강체 부품으로 분리했다. 새 모델 생성이나 decimation은 하지 않았다. 9,791삼각형과 기존 1K PBR 아틀라스를 사용한다. 원본 v2 blend/GLB와 실제 소환체의 rig·동작은 유지한다. 조립 사본은 13개 독립 메시이며 스킨·애니메이션이 없다.

발 → 다리 축 → 몸통 → 팔 → 머리 → 태엽 순서로 나타나며 청록빛이 사라지면서 본래 황동·청록 표면을 드러낸다. 전투 RNG를 사용하지 않는다. 기본 시전 0.6초 중 기존 발동 비율 0.85, 즉 **0.51초**에 완성된다. FCR 40은 약 **0.32169초**에 완성된다. 남은 시간은 기존 시전 후동작이다. 시전시간/발동비율/피해/비용/쿨다운/소환 위치 규칙은 이 작업에서 바꾸지 않았다.

조립 중에는 소환체·충돌체·공격 대상이 아닌 외형만 있다. 시전 시작 시 기존 플레이어 옆 소환 지점을 고정하고, 성공 발동 때 같은 곳에서 v2 태엽인형 하나로 바꾼다. 완성된 사본 표면과 실제 엔진의 스킨 idle 표면은 각 FCR에서 14,585개 정점을 대조했으며 최대 차이는 약 **0.0021mm**였다. 이는 CPU 좌표 비교이며 GPU 정점 readback은 아니다.

완성 직후 밀리던 현상은 소환 오프셋 `(1.0, 0.6)`과 대기 AI 오프셋 `(0.8, 0.8)`의 불일치였다. 대기·화면 밖 복귀도 `automaton_spawn_position()`을 사용하도록 통일했다. 실제 physics 프레임에서 30/60fps × FCR 0/40을 검사해 최대 위치 이동이 **0.28284m → 0m**, 불필요한 걷기 프레임이 **3/5 → 0**으로 줄었다. 마녀 이동 시 추종과 가까운 적 추적은 계속된다. 재현 전 결과는 `reports/automaton_assembly_v1/anchor_before.json`, 수정 후는 `automaton_spawn_anchor/result.json`이다.

## 취소와 정리

- 큰 피격 경직·사망: 즉시 현재 부품 위치/회전을 유지한 채 낙하로 전환한다.
- 대상 소멸·슬롯 변경·자원 부족 등 기존 발동 재검사 실패: 소환체를 만들지 않고 조립 외형을 무너뜨린다.
- 작은 피격·방패 막기: 시전을 유지한다. 이미 성공 발동한 소환체는 이후 마녀의 경직 때문에 취소되지 않는다.
- 나타나지 않은 부품은 취소 후 생성되지 않는다. 미완성 잔해에 공격·자폭·피해·마나 소비·쿨다운은 없다.
- 일시정지는 조립과 낙하를 멈춘다. 재시작/맵 교체는 관련 외형을 정리한다. 이전 잔해가 남아 있어도 다음 시전은 별개다.
- 낙하는 120Hz 고정 간격의 표시용 중력·회전·바닥 지지 계산이며, 약 1.7초 뒤 사라진다. 부품끼리나 벽과 충돌하는 RigidBody 시뮬레이션은 아니다.

기존 `game/audio/mechanical_impact.wav`(약 0.455초, 44.1kHz stereo)를 낮은 음량의 조립/착지음으로 재사용한다. 성공 소환음은 기존 호출을 사용한다. `play_cue`의 선택적 음량 인자는 다음 호출마다 기본 음량으로 돌아가며 기존 mute를 따른다. 새 음원 생성은 하지 않았다. 검토 페이지는 무음 캡처다.

## 검증·재현

`tools/export_automaton_assembly_v1.py`를 Blender background로 실행하면 보호된 v2 파일에서 사본을 재생성한다. Blender MCP는 해당 세션에서 연결되지 않아 설치된 Blender 5.1.1을 사용했다. `tools/run_automaton_assembly_v1.ps1 -Phase import/test/review`, 마지막으로 `tools/package_automaton_assembly_v1.py`를 실행한다. 테스트 코드는 `game/tests/automaton_assembly.gd`, 촬영은 `review_automaton_assembly.gd`다.

성공/마나/쿨다운/두 FCR, 15·50·85% 중단, 현재 자세 보존, 태어나지 않은 부품 유지, 바닥, 일시정지, 약한 피격/막기, 사망·실패·대상 소멸·필드 종료, 재시작·맵 교체·재시전을 검사한다. 기존 `hit_block`, `approach_cast`, `summons_v2` 회귀도 실행했다. GPU 리뷰는 30fps 표본 370장/7장면이며 실제 arena 시전과 피해를 사용한다. 재현성을 위해 촬영에서만 취소 후 외형 시계를 명시적으로 진행한다. 화면용 `user://` 캐시 진단은 실행 기록에 구분했다.

대기 위치 수정 뒤 `automaton_spawn_anchor`(20개), `automaton_assembly`, `summons_v2`를 재실행하고 GPU 370장을 다시 촬영했다. `hit_block`·`approach_cast`는 직전 연출 연결 검증을 유지한다. GPU 성공 장면도 소환 후 실제 위치와 idle 상태를 기록·검사한다.

공유 작업공간의 전기톱·출혈 등 병행 전투 변경을 보존했다. 매니페스트의 arena/config/player 해시는 검사한 결합 상태를 식별하며, 해당 전투 변경까지 이 작업에서 작성했다는 뜻이 아니다. 13개 메시의 짧은 조립 연출에 대한 최종 성능 예산·임의 지형/벽 접촉·사용자 연출 평가는 별도다.
