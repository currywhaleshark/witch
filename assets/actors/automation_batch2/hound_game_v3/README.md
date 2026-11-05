# 기계 수렵견 · 늑대 질주 v3

[비교 검토](../../../../reports/automation_motion_v2/review.html) · [parts.json](parts.json) · [hound_game_v3.blend](hound_game_v3.blend)

준비용 아트이며 주 게임 스킬·AI·피해·이동 코드는 바꾸지 않았다. 이전 버전과 Tripo 원본은 보존한다.

- 6,795 삼각형 / 33 강체 그룹 / 37 본 / 6개 클립.
- 게임 폴더: `game/assets/actors/automation_batch2/hound_v3/`. GLB, parts.json, import 설정, import_exact_animation.gd를 함께 사용한다.
- 상수 TRS, 단일 본 100% 웨이트, 미터·Godot −Z 정면. 24fps 타임라인과 추가 정확 시각 키를 보존한다.

Quaternius의 **CC0 Wolf / Gallop**을 실제로 받아 원본 IK가 평가된 발·몸통·머리·꼬리 궤적과 뒷발목 움직임을 옮겼다. [출처와 원본](../motion_sources/quaternius/README.md). 원형 모델은 기존 Tripo 수렵견을 사용한다.

짧은 다리로 6.5m/s를 맞추기 위해 0.5초 클립에 **두 번의 질주**를 넣는다. 한 번에 0.25초·1.625m, 전체 0.5초·3.25m다. 접지 순서는 앞 L → 앞 R → 뒤 L → 뒤 R이며, 발 회수와 뒷발목은 원본에서 가져오고 접지는 일정 속도로 보정한다. 240Hz 키와 접지 시각을 추가하며 게임 이동은 기존 루트가 담당한다. 공중 발 궤적의 최대 도달 보정은 32.8mm다.

모든 37개 rest 본, 일반 부품 정점·UV·토폴로지·웨이트·재질은 동일하다. 피스톤 6개 그룹의 정적 길이만 가동 범위에 맞춰 조정한다(애니메이션 스케일 없음). run을 교체하고 death는 바뀐 피스톤의 바닥 지지만 보정한다. 나머지 클립 변형은 오차 0.001mm 미만으로 유지한다.

1,920Hz 검토에서 접지 중 이동 보상 후 발 위치 변화는 최대 2.917mm, 관절 끝점 오차는 0.00017mm다. 뒤 R 피스톤의 가장 좁은 삽입 여유는 약 0.402mm다. 이는 지정 클립의 시각적 유지 범위이며 임의 혼합·중단·물리 접촉 보장은 아니다.

원본·재임포트 QA 오류 0. UV/노멀 이음 정점, 숨긴 접합면, 내부 베어링, 의도적 바닥 여유 경고는 유지한다. 전체 검증·현재 파일 해시·환경 진단과 한계는 [delivery_manifest.json](../../../../reports/automation_motion_v2/delivery_manifest.json)에 있다. 임의 포즈의 부품 간 충돌, 장갑 접촉, 실시간 파괴 물리나 최종 성능·외형 승인은 포함하지 않는다.
