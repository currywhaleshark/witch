# 신규 아이템 바닥 모델 v3

2026-11-05. 새 폭약 부품과 고유 5종을 인벤토리 이미지와 같은 형태로 만든 정적 전리품이다.
기존 39종에 더해 현재 45개 정의를 모두 전용 프로필로 연결한다.

- [게임 비교/낙하/강조 리뷰](../../../reports/item_art_v2/review.html)
- [편집 원본: ground_loot_v3.blend](ground_loot_v3.blend) — 아이템별 독립 장면 6개, 개별 부품과 재질
- [수치와 GLB 해시](models.json), [게임 프로필·GLB](../../../game/assets/props/ground_loot_v3/)
- [생성기](../../../tools/build_ground_loot_v3.py), [저장본·재반입 검사](../../../tools/validate_ground_loot_v3.py)
- [인벤토리 PNG 및 생성 기록](../../ui/inventory_v2/README.md)

| 모델 | 삼각형 |
|---|---:|
| 폭약 부품 | 1,988 |
| 쌍둥이 포열핵 | 2,988 |
| 불붙은 심지 다발 | 8,264 |
| 녹슨 단두대 경첩 | 3,152 |
| 반격 경첩 | 4,812 |
| 무쇠 연골 | 3,572 |
| 합계 | 24,776 |

Blender 5.1.1 백그라운드에서 직접 작성한 메시다. 원본은 편집 가능한 부품으로 보존하며
GLB만 정점 색을 가진 하나의 메시, 최대 3개 불투명 PBR 표면으로 합친다. 새 텍스처는 없다.
심지의 불씨와 작은 불꽃은 고정된 장식이며 게임의 화약통 불길 효과를 실행하지 않는다.
의상은 접힌 형태라 바닥에서 차지하는 면적이 작다.

`ground_loot_visual.gd`는 v3의 통합 models.json을 읽는다. 기존 v1/v2의 39개 경로·높이·크기는
그대로 복사하여 이전 GLB를 직접 참조한다. 실제 정점의 중심을 회전축으로 잡고 바닥에서
12mm 위에 놓이며 수평 반경은 0.35m 미만이다. 기존 0.7m 간격, 0.4초 회전 낙하,
5초 라벨 숨김/Alt 임시 표시, 아이템·라벨 동시 강조와 습득 경로를 공유한다.

개별 소스 부품의 닫힌 모서리/퇴화 면, 저장본 부품 수, GLB 재반입 치수·정점 색·UV·중심·높이를
확인했다. 실제 GPU 검사에서 6종 각각 48개 낙하 시점의 바닥 통과 여부, 강조 재질 복원,
개별 인스턴스 분리 및 고유 ID를 보존한 습득을 확인했다. 이전 이미지/GLB와 게임 데이터는
보존했다. 전체 결과는 [delivery_manifest.json](../../../reports/item_art_v2/delivery_manifest.json).

의도적으로 맞물리는 고정 부품의 내부 접합면은 남겨 둔다. 이 검사는 임의 지형/벽과의
물리 충돌, 캐릭터 의상 장착, 전체 게임 성능 예산에 대한 검증이 아니다. 사용자는 검토 후
2026-11-05에 커밋을 요청하여 현재 외형을 프로토타입용으로 선택했다([기록](../../../reports/item_art_v2/approval.json)).

```powershell
& 'C:/path/to/blender.exe' -b --factory-startup --python-exit-code 1 -P tools/build_ground_loot_v3.py
& 'C:/path/to/blender.exe' -b --factory-startup --python-exit-code 1 -P tools/validate_ground_loot_v3.py
./tools/run_item_art_v2.ps1 -Phase import
./tools/run_item_art_v2.ps1 -Phase runtime
```
