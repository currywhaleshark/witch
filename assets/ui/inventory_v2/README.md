# 새 아이템 인벤토리 이미지 v2

2026-11-05 사용자의 “새 아이템 이미지와 바닥 모델 확인해서 추가하자” 요청으로,
임시 대체 그림을 쓰던 폭약 부품 1종과 고유 아이템 5종을 전용 이미지로 연결했다.

| ID | 이름 | 형태 |
|---|---|---|
| part_explosive | 폭약 부품 | 붉은 통, 황동 띠, 청록 마름모 |
| twin_barrel_core | 쌍둥이 포열핵 | 나란한 두 포구, 청록 후면 하우징 |
| bundled_fuse | 불붙은 심지 다발 | 꼬인 심지, 황동 묶음, 빨간 끈과 불씨 |
| rusted_guillotine_hinge | 녹슨 단두대 경첩 | 철제 경첩, 녹슨 가장자리와 청록 판 |
| counter_hinge | 반격 경첩 | 황동 경첩으로 보강한 아이보리 덧옷 |
| iron_cartilage | 무쇠 연골 | 철제 등뼈와 갈비 모양 지지대가 달린 청록 망토 |

- [비교 화면과 실제 게임 캡처](../../../reports/item_art_v2/review.html)
- [최종 프롬프트·생성 원본·프로젝트 경로](generation_manifest.json)
- [게임 PNG 6장](../../../game/assets/ui/inventory_v2/)
- [바닥 모델과 편집 원본](../../props/ground_loot_v3/README.md)

내장 `image_gen`으로 아이콘마다 한 번씩 생성했다. 투명 PNG의 원본 픽셀은 보존하고,
Godot import만 최대 변 256px·무손실·mipmap·알파 경계 보정으로 설정했다.
기존 `draw_art()`의 LINEAR_WITH_MIPMAPS와 알파 영역 중심 정렬을 공유한다.
`item_icon.gd`의 `art_path()`가 새 6종은 inventory_v2, 기존 35종은 inventory_v1로 찾는다.
현재 장비 기본 21 + 고유 7 + 물약 13 = 41종이 각각 전용 그림을 가진다.
미래의 미등록 고유 아이템에 대한 기본 아이템 그림 대체 동작은 유지한다.

의상 두 종의 그림은 아이템창 표시용이다. 캐릭터의 착용 메시를 교체하는 작업은 아니다.
사용자는 검토 후 2026-11-05에 커밋을 요청하여 새 6종의 그림과 바닥 모델을 프로토타입용으로 선택했다([기록](../../../reports/item_art_v2/approval.json)).

검증: Blender 저장본/GLB 86개, 실제 Godot GPU/연결 202개, 기존 드롭 55개,
자원 26개, 아이템 62개, 신규 옵션/고유 효과 37개, 합계 468개 최종 통과.
첫 병렬 아이템 회귀 실행에서 우클릭 GUI 검사 1개가 실패했으나 진단 실행과 단독 재실행은
동일 게임 코드에서 통과했다. 해당 기존 검사 자체는 변경하지 않았고 이 변동성을 숨기지 않는다.
게임 GPU 캡처는 13장이다. [검증 및 현재 입력 해시](../../../reports/item_art_v2/delivery_manifest.json).

재현(Windows PowerShell, Godot 4.6.2):

```powershell
./tools/run_item_art_v2.ps1 -Phase import -GodotPath 'C:/path/to/Godot.exe'
./tools/run_item_art_v2.ps1 -Phase runtime -GodotPath 'C:/path/to/Godot.exe'
./tools/run_item_art_v2.ps1 -Phase regressions -GodotPath 'C:/path/to/Godot.exe'
```

실행기는 GODOT_BIN 또는 PATH의 godot도 지원한다. 기존 보고서를 덮어쓰지 않도록 회귀
출력만 새 폴더로 바꾼 임시 검사 사본을 사용한다. 로그 경로를 프로젝트 안에 지정해야 이
PC에서 기본 user 로그 경로 권한으로 인한 시작 충돌을 피할 수 있다. 에디터 설정 및 shader
cache 권한 경고는 남지만 최종 실행과 이미지 캡처는 완료됐다.
