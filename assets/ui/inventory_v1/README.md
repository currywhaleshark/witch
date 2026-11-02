# 인벤토리 이미지 v1

2026-11-02 사용자 요청으로 제작한 장비 22종(기본 20 + 고유 2), 물약 13종의 아이템창 이미지다. 내장 `image_gen`으로 각 아이콘을 따로 생성했다. 낡은 놋쇠·짙은 청록 기계 부품, 일상 의류, 색과 병 모양으로 구분하는 물약을 사용한다.

- [이미지 전체와 실제 게임 화면](../../../reports/inventory_art_v1/review.html)
- [최종 생성 프롬프트·수정 프롬프트·원본 경로](generation_manifest.json)
- [원본 PNG 35장](../../../game/assets/ui/inventory_v1/)
- [현재 소스 크기·알파·SHA-256](../../../reports/inventory_art_v1/source_assets.json)
- [게임 로딩·GPU 캡처 검사](../../../reports/inventory_art_v1/report.json)

## 연결

`game/scripts/item_icon.gd`가 아이템 기본 ID, 고유 아이템 ID, 물약 ID에 맞는 PNG를 캐시한다. 알파가 있는 영역을 비율에 맞춰 가방·착용 칸·커서에 그린다. 희귀도 배경/테두리, 소켓과 이름 파편, 물약 등급/수량은 기존 데이터로 별도 표시한다. 이미지가 없는 새 정의는 기존 도형으로 표시한다. 하단 전투 HUD의 물약 퀵슬롯도 같은 이미지를 쓴다.

원본 픽셀은 수정하지 않았다. Godot `.import`는 최대 변 256px, 무손실, mipmap, 알파 경계 보정으로 설정했다. 현재 35종의 RGBA mip 데이터 합계는 12,115,700바이트(약 11.55MiB)이며 전체 게임 메모리 측정은 아니다. `game/tests/prepare_inventory_art.gd`로 이 설정과 소스 목록을 갱신한 뒤 에디터에서 import한다.

물약의 소·중·대는 둥근 병·긴 병·넓은 병, 완전 회복은 각진 수정병이다. 색은 체력 빨강, 마나 파랑, 동시 회복 보라, 속도 초록이다. `prompts.json`은 최초 요청 기록이고, 실제 최종 입력은 `generation_manifest.json`에 있다. 설계도 두 장의 초기 생성은 거절되어 구조 설명 없는 장식 표식으로 바꿨으며, 전기톱 표식을 길쭉하게 수정하고 탄도 부품의 배경을 제거했다. 모든 생성 원본은 도구의 원래 저장 위치에 보존했다.

### 축소 표시 보정 (2026-11-02)

사용자가 작은 아이콘의 자글거림과 소형 물약이 중형보다 커 보이는 문제를 지적했다. import에서 mipmap을 생성했지만 그리는 CanvasItem은 일반 필터를 사용하고 있었다. 공통 `draw_art()`에서 `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`를 사용하도록 바꾸고, `health_s`·`mana_s`·`rejuv_s`의 표시 가로·세로를 기존의 72%로 줄였다. 가방·착용 칸·커서·하단 물약 슬롯에 공통 적용하며 원본 PNG와 import 설정은 보존했다. 실제 게임 캡처에서 잡음 감소와 크기 차이를 확인했다. [적용 전후 1:1 비교](../../../reports/inventory_filter_v1/review.html), [Godot 필터 설명](https://docs.godotengine.org/en/4.6/classes/class_canvasitem.html#enum-canvasitem-texturefilter).

## 검증

Godot 4.6.2 / Windows / OpenGL Compatibility에서 아이콘 누락·알파·import 크기·mipmap·배치와 네 GPU 캡처를 포함해 97항목을 통과했다. 1280×800 게임 화면에서 장비·고유 아이템·물약 가방·퀵슬롯을 직접 확인했다. 전체 이미지 표는 별도 검토용 CanvasLayer다.

기존 물약 가방 GPU 입력 검사 43항목, 분해 모드 26항목, 아이템 61항목도 통과했다. 기존 가방/분해 리뷰는 보존하고 이번 결과는 `reports/inventory_art_v1/*_regression.json`에 별도로 두었다. 사용자는 축소 필터와 소형 물약 크기 보정 후 2026-11-02에 커밋을 요청하여 현재 외형을 프로토타입용으로 선택했다([기록](approval.json)).

재현: `godot --path game --resolution 1280x800 --script res://tests/inventory_art.gd -- --capture`. 화면 없는 로딩 검사는 `--headless`를 추가하고 `--capture`를 뺀다.
