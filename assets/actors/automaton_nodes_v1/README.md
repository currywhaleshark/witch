# 태엽인형 노드 외형 v1

2026-10-29. 채택된 `summons_v2` 태엽인형을 바탕으로 A 자폭형과 B 절삭형을 제작하고 현재 시험판의 노드 선택에 연결했다. 기본형은 보존하며, 스킬 레벨에 따른 추가 외형 변화는 사용자 요청에 따라 보류한다. 두 외형은 2026-10-29 「좋아」로 현재 시험판용 채택되었다. [선택 범위](approval.json)를 따른다.

- [기본형·A·B 비교와 실제 동작](../../../reports/automaton_nodes_v1/review.html)
- [검증·파일 해시](../../../reports/automaton_nodes_v1/delivery_manifest.json)
- 수정 시작: `authoring/automaton_a.blend`, `authoring/automaton_b.blend`.
- 게임용 리그: `exports/automaton_a.glb`, `exports/automaton_b.glb`.
- 조립용 사본: `exports/automaton_a_parts.glb`, `exports/automaton_b_parts.glb`.
- 부품 순서·심지 경로·회전축: `automaton_a.json`, `automaton_b.json`.

## 외형과 원본 보존

| 노드 | 외형 | 삼각형 | 강체 부품 | 본 |
|---|---|---:|---:|---:|
| 기본형 | 기존 낡은 황동·청록 인형 | 9,791 | 13 | 26 |
| A 자폭형 | 구리색 폭약통, 점화구, 12구간 심지 | 10,583 | 27 | 40 |
| B 절삭형 | 가슴·어깨·정강이 장갑, 손목 가드, 모터·원형 칼날 | 11,827 | 21 | 34 |

불변 원본은 `assets/actors/summons_v2/authoring/automaton_v2.blend`이며 SHA-256은 `3984623532d7b4f64e2276681aa5bb07f7b1196f5bf07f98f60a3556a582b074`다. 빌더는 기본 메시 정점 바이트와 기존 26개 본의 rest 행렬을 대조하고, 별도 파일에 추가 부품·본을 저장한다. 원본 1K PBR 재질은 유지하며 추가 장갑/폭약통은 단순한 PBR 재질을 사용한다. 새 Tripo 생성물이 아니라 기존 모델을 Blender에서 파생한 실물 자산이다.

두 리그 GLB에는 기존 여섯 동작 `idle`, `move`, `attack`, `hit`, `death`, `explode`가 있다. 추가 부품은 자신의 본에 100% 연결되며, 분해/폭발 동작에 별도 낙하·비산 키를 추가했다. 기존 클립의 새 외형용 사본이며 새로운 모션캡처는 아니다. 조립 GLB는 idle 첫 프레임의 독립 부품 사본이고 스킨·클립이 없다.

## 게임 연결

`N`은 기본 → A → B 순서로 노드를 선택하고, 기본 배치의 `W`로 소환한다. 이미 소환한 인형은 자신의 노드와 외형을 유지한다. 디버그 선택을 시전 중 바꾸면 같은 원점·현재 조립 진행률로 외형을 갱신해 실제 발동 때 선택되는 노드와 맞춘다.

- `game/scripts/automaton_assembly.gd`: 노드별 조립 GLB와 추가 부품 생성 순서를 선택한다. 미완성 인형의 심지는 켜지지 않는다.
- `game/scripts/summon_assembly.gd`: 원래 공통 생성/취소/낙하 동작을 유지하며, 한 부품의 여러 표면 재질을 각각 복제해 장갑과 테두리 색을 보존한다.
- `game/scripts/actor_visual.gd`: 살아 있는 노드별 모델을 선택하고 기존 전투/분해 동작을 재생한다. 적·포탑·기본형은 기존 경로다.
- `game/scripts/automaton_node_effects.gd`: A의 소모 심지·불꽃, B의 연속 칼날 회전·접촉 불꽃을 표시한다.
- `game/scripts/arena.gd`: 기존 노드 판정과 발동 시점에 외형을 연결한다. B 타격의 이전 광선 표시를 칼날 연출로 대체한다.

A는 소환 성공 후 점화한다. 심지는 남은 수명과 표적 접근 진행률 중 더 진행된 값을 따라 줄어들며, 표적 변경/일시정지 후에도 다시 길어지지 않는다. 심지는 폭발을 예고하는 외형이다. 별도 폭발 타이머나 피해 판정을 만들지 않고 기존 arena의 표적 도달/수명 만료 판정으로 자폭한다. 사망·자폭 후 불꽃은 꺼진다.

B는 기존 노드의 지속 공격·수명·수량 제한과 최신 HP/피해 계수를 그대로 따른다. 외형 코드에서 추가 능력치 보너스를 계산하지 않는다. 칼날 회전은 동작 전환 때 각도를 유지하며 공격 중 더 빨라진다. 교체/사망 때 장갑과 칼날도 함께 분해된다. 레벨 성장에 따른 추가 외형은 구현하지 않았다.

## 검증과 재현

최종 수치와 실제 검사 입력 해시는 링크한 매니페스트를 기준으로 한다. A/B 조립 완성 사본과 살아 있는 스킨은 FCR 0/40 각각 15,587 / 18,283개의 CPU 정점으로 대조했다. 최대 차이는 A 약 0.00578mm, B 약 0.00486mm다. GPU 정점 readback을 했다는 뜻은 아니다.

A/B 외형 검사는 각각 675 / 615개이며, 초기·중간·후기 취소, 부품별 색, 실제 발동 전 미생성, 비용·쿨다운, 심지 소모·일시정지·소등, 칼날 회전, 기존 인형의 노드 유지와 시전 중 선택 변경을 포함한다. 기본 인형 조립 405개와 포탑 조립 2,371개도 재실행했다. 다른 작업자의 최신 `automaton_node.gd`를 출력 경로만 바꾼 `automaton_node_art_regression.gd`로 실행해 전투 규칙과 N 선택을 확인한다.

리뷰는 실제 arena 시전·피격 경직·표적 접근·타격/자폭을 실행한 9개 장면과 정면 비교 1장, 총 610장의 GPU 렌더다. `a_fuse`만 수명 변화를 보기 위해 게임 시간을 6배 진행하며 페이지에 표시한다. 나머지는 30fps의 실제 시간 진행이다. 성공 후 가만히 대기하는 장면의 원점 이동은 0m다. 렌더 실행은 exit 0이며 유일한 stderr는 작업 환경의 `user://` 셰이더 캐시 폴더 생성 불가 안내다. 게임 로직 오류로 통과 처리한 항목은 없다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_automaton_nodes_v1.ps1 -Phase test -Test automaton_variant_a
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_automaton_nodes_v1.ps1 -Phase test -Test automaton_variant_b
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_automaton_nodes_v1.ps1 -Phase test -Test automaton_node_art_regression
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_automaton_nodes_v1.ps1 -Phase review
python tools/package_automaton_nodes_v1.py
```

빌더는 `tools/build_automaton_nodes_v1.py`다. 이번 제작은 Blender MCP 자동 승인 검토가 시간 초과되어 별도 background Blender 5.1.1에서 실행했다. 열려 있던 Blender 작업 장면은 수정하지 않았다.

## 남은 범위

추가 장갑의 표면은 원본의 낡은 재질보다 단순하다. 현재 시험판 외형은 채택되었으며 최종 성능 예산은 아직 확정하지 않았다. 추가 분해 부품은 구운 낙하/바닥 반동 동작이며 부품끼리·벽과의 실시간 충돌은 아니다. 리뷰는 무음이며 게임은 기존 기계음을 재사용한다. 앞선 인형·포탑 매니페스트는 당시 기록이고, 현재 공유 코드의 검증 해시는 이번 매니페스트가 기록한다. 동시 작업자의 전투 코드·설정 변경을 보존한다.
