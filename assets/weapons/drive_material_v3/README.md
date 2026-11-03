# 구동 장비 재질 v3 — 2026-11-04

외골격을 제외한 구동 트리 준비 장비 8종의 재질 마무리본이다. 단두대 3종은 v2, 윈치·압착기·집행기·충격 흡수 프레임·광역 커터는 v1의 형상과 부품 구조를 사용한다.

- [수정 전후·동작·실제 표시 크기 리뷰](../../../reports/drive_material_v3/review.html)
- [Blender 작업본](drive_material_v3.blend) / [현재 자산 목록](catalog.json)
- [검증 명세](../../../reports/drive_material_v3/delivery_manifest.json)

## 재질

남색 도장과 미세한 모서리 마모, 차분한 황동과 부분 변색, 산화 강철, 가공 결이 있는 밝은 금속, 무광 호스와 청록 코어를 구분했다. Blender 노드 8종을 독립된 트림 사각형에 Cycles로 베이크했다. 물체에 반복 배치한 UV에 직접 고유 베이크를 수행한 것이 아니다.

224개 강체 메시 / 45,516 삼각형 / 각 부품 한 표면을 유지한다. 일반 표면과 발광 코어는 2개 재질이며, 전체 모델이 색 1K·OpenGL 노멀 1K·ORM 512·발광 256 텍스처를 공유한다. 색/발광은 sRGB, 노멀/ORM은 Non-Color. ORM은 R=1(새 AO 없음), G=거칠기, B=금속이다. 색에 그림자나 AO를 곱하지 않았다. RGBA8 전체 밉 기준 약 12.33MiB는 텍스처 추정치이며 측정 성능값이 아니다.

## 파일과 연결

`drive_material_v3.blend`에는 `DriveMaterialV3_<id>` 8개 장면, 전체 배치 `DriveMaterialV3_Review`, 편집 가능한 원본 노드를 가진 `DriveMaterialV3_Bake`가 있다. 텍스처를 내장했고, 다른 과거 장면은 최종 파일에서 제외했다. live MCP 작업 중의 전체 장면 사본은 로컬 백업이며 배포 대상이 아니다.

`exports/*.glb`는 텍스처 내장형, `game/assets/weapons/drive_material_v3/*.glb`는 옆 `textures/`를 참조하는 공유형이다. 목록의 `model`과 `metadata`를 함께 사용한다. 런타임 GLB는 이전 GLB의 BIN 청크와 모든 노드·메시·UV·노멀·탄젠트·인덱스를 그대로 두고 재질/이미지 선언만 변경했다. JSON의 재질 이름과 텍스처 세트 이름만 갱신했으며 부품·소켓·지연·부착 본·작동 명세는 동일하다.

`game/tests/helpers/drive_material_v3_demo.gd`는 v2/v1 동작 코드를 그대로 상속한다. 고정형의 선행 구속, 바닥까지의 칼날 낙하, 집행기 프레스 상승 후 톱 진입, 윈치 3분기와 광역 커터 닫힘을 유지한다. 새 스킬의 본편 판정/피해/장착 연결은 추가하지 않았다. 현재 외골격은 기존 `assets/equipment/exoskeleton_v4/`를 계속 사용한다.

## 검수

8종의 저장 원본과 새 GLB 재반입 형상 QA 오류 0건. 전체 QA를 시작한 뒤 마모 폭과 거칠기만 조정했으므로, 최종 저장본의 224개 메시·UV·코너 노멀·448개 행렬과 텍스처 연결/색 공간/내장을 추가로 재검사했다. Godot 재질/공유 텍스처와 이전 동작 비교 22,226개 검사, 실제 GPU 캡처 886장을 기록했다. 비교 화면은 양쪽에 같은 중성 반사 환경을 추가한 검토용 조명이며 게임 조명은 그대로다. 실제 표시 크기는 1280×800 / 기존 1.75× 카메라다.

기존 반복 트림 UV, 평면 캡, 숨은 접합면·칼라, UV/노멀 경계 중복 정점과 부착 원점의 지면 밖 위치는 이유를 붙여 허용했다. 충격 흡수 프레임의 기존 장착 간격도 유지한 재질 작업이다. 새 의상 간섭 해결, 실시간 충돌/천, 임의 포즈 및 최종 성능 검증으로 확대 해석하지 않는다. 상세 내용은 [검수 판정](../../../reports/drive_material_v3/qa_adjudication.json)에 있다.

## 재현 도구

`tools/author_drive_material_v3.py`는 live MCP에서 이전 장면을 복사하고 원본 노드를 만든다. `bake_drive_material_v3.py`는 별도 Blender에서 베이크·형상 보존을 검사하고 컴팩트한 원본을 저장한다. `package_drive_material_v3.py`는 GLB의 형상을 재수출하지 않고 새 맵을 연결한다. `finish_drive_material_v3.py`, `qa_drive_material_v3.py`, `validate_drive_material_v3_saved.py`와 `package_drive_material_review_v3.py`가 저장·검수·전달 자료를 담당한다.
