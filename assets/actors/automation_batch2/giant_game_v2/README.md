# 거대 자동인형 · 축 수정 v2

[비교 검토](../../../../reports/automation_motion_v2/review.html) · [parts.json](parts.json) · [giant_game_v2.blend](giant_game_v2.blend)

준비용 아트이며 주 게임 스킬·AI·피해·이동 코드는 바꾸지 않았다. 이전 버전과 Tripo 원본은 보존한다.

- 15,943 삼각형 / 27 강체 그룹 / 33 본 / 6개 클립.
- 게임 폴더: `game/assets/actors/automation_batch2/giant_v2/`. GLB, parts.json, import 설정, import_exact_animation.gd를 함께 사용한다.
- 상수 TRS, 단일 본 100% 웨이트, 미터·Godot −Z 정면. 24fps 타임라인과 추가 정확 시각 키를 보존한다.

고정 Y/Z 축 대신 메시의 실제 축으로 변경했다. 가슴 톱니는 약 **17.78°**, 태엽 목은 약 **10.99°** 기울어져 있었다. 거대 체형에 맞춘 비균등 배율 때문에 타원이 된 톱니도 원본 균등 배율로 복원한다. 동력 렌즈와 Socket_core를 새 허브에 맞춘다. [축·피벗 측정](mechanisms.json).

변경 정점은 gear/core 두 그룹뿐이다. 모든 면·UV·웨이트·재질과 다른 그룹 정점·자동 노멀은 정확히 유지한다. gear/key/core/Socket_core 네 rest 본의 원점이 바뀌므로 기존 v1 장갑 대신 v2 장갑을 쓴다. 기타 본의 변형은 0.002mm 미만 오차로 유지한다. 붕괴는 바뀐 부품의 새 지지점으로만 보정한다.

idle/walk 482개 시각에서 톱니·태엽의 축 중심 오차는 각각 0.001mm 미만이다. 이전 축의 회전 중 방향 변화는 약 35.56° / 21.98°였다. 새 기어는 Tripo 원형의 미세한 비대칭과 표면은 유지한다.

원본·재임포트 QA 오류 0. UV/노멀 이음 정점, 숨긴 접합면, 내부 베어링, 의도적 바닥 여유 경고는 유지한다. 전체 검증·현재 파일 해시·환경 진단과 한계는 [delivery_manifest.json](../../../../reports/automation_motion_v2/delivery_manifest.json)에 있다. 임의 포즈의 부품 간 충돌, 장갑 접촉, 실시간 파괴 물리나 최종 성능·외형 승인은 포함하지 않는다.
