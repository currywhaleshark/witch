# 거대 강화 장갑 · 축 대응 v2

[비교 검토](../../../../reports/automation_motion_v2/review.html) · [parts.json](parts.json) · [giant_armour_game_v2.blend](giant_armour_game_v2.blend)

준비용 아트이며 주 게임 스킬·AI·피해·이동 코드는 바꾸지 않았다. 이전 버전과 Tripo 원본은 보존한다.

- 1,256 삼각형 / 6 강체 그룹 / 33 본 / 6개 클립.
- 게임 폴더: `game/assets/actors/automation_batch2/giant_armour_v2/`. GLB, parts.json, import 설정, import_exact_animation.gd를 함께 사용한다.
- 상수 TRS, 단일 본 100% 웨이트, 미터·Godot −Z 정면. 24fps 타임라인과 추가 정확 시각 키를 보존한다.

장갑 메시·UV·노멀·웨이트·재질은 이전 장갑과 동일하다. **giant_v2**와 같은 살아 있는 클립을 같은 초 단위 시간으로 샘플한다. 본/rest는 새 기본형과 맞추고, 기존 장갑의 독립 붕괴는 유지한다. packed 원본에는 현재 기본형과 장갑의 두 리그가 함께 들어 있다. 일반 동작에서는 같은 클립·시각으로 재생한다.

원본·재임포트 QA 오류 0. UV/노멀 이음 정점, 숨긴 접합면, 내부 베어링, 의도적 바닥 여유 경고는 유지한다. 전체 검증·현재 파일 해시·환경 진단과 한계는 [delivery_manifest.json](../../../../reports/automation_motion_v2/delivery_manifest.json)에 있다. 임의 포즈의 부품 간 충돌, 장갑 접촉, 실시간 파괴 물리나 최종 성능·외형 승인은 포함하지 않는다.
