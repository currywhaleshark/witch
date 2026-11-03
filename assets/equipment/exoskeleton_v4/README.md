# 외골격 v4 · 소매·케이프 간섭과 종아리 고정

2026-11-04. [수정 전후 모션 리뷰](../../../reports/exoskeleton_v4/review.html).

사용자가 지적한 손목 소매·케이프 관통과 떠 있는 다리 장비를 다듬은 착용 자산이다. 기존 v2/v3, 본체·의상·모션 원본과 본 게임 스크립트는 유지한다. 신규 스킬 발동이나 장비 UI 연결 단계는 아니다.

## 시작 파일

- `exoskeleton_v4_animated.blend`: 현재 캐릭터와 외골격·헤어의 8개 모션을 함께 재생하는 편집본. `ExoskeletonV4_Fit` 장면에서 Space로 재생한다. `OUTFIT_Civilian` / `OUTFIT_Transformed` 컬렉션의 뷰포트·렌더 표시를 서로 바꿔 의상을 선택한다.
- `exoskeleton_v4.blend`: 정지 상태의 메시·보조 리그 작업본. `V4_ORIGINALS_ARCHIVE`에는 교체 전 위팔과 소매를 보관한다.
- `exports/exoskeleton_v4.glb`: 장비만 있는 55개 강체 메시 / 56개 보조 본 / 79,049 삼각형. 각 정점은 한 본에 100% 가중치이며 스케일 애니메이션을 사용하지 않는다.
- `exports/outfit_civilian_fit_v4.glb`: 외골격 전용 교복 소매 피팅 복사본.
- `exports/outfit_transformed_fit_v4.glb`: 기존 변신복 GLB와 파일 전체가 동일한 복사본.
- `parts.json`: 현재 부품·기준 좌표계·피팅 계보. 런타임은 이 파일을 기준으로 하며, GLB의 제작 당시 extras는 실행 계약이 아니다.
- `clearance_curves.json`: 기존 모션에서 옷을 피하는 장비 관절 보정 키. 본체 애니메이션이 아니다.
- [현재 파일 해시와 검사 기록](../../../reports/exoskeleton_v4/delivery_manifest.json).

## 바뀐 부분

어깨 덮개는 상완의 축 비틀림을 제외하고 팔 방향의 회전만 75% 따른다. 바깥·뒤·위로 기준 위치를 잡아 케이프 안으로 말려 들어가는 움직임을 줄였다. 등 동력부의 방향과 원본 재질은 유지했다.

위팔의 원본 양 끝 장착부는 남기고 가운데를 좌우 각각 8단의 금속 연결대로 바꿨다. 팔꿈치와 어깨 사이 거리가 달라져도 부품은 회전·이동만 하며 늘어나지 않는다. 등과 어깨 사이의 기존 7단 연결대도 새 어깨 위치에 맞췄다.

손목 쪽 기준 여유를 65mm에서 100mm로 늘리고, 교복 소매만 팔 축 쪽으로 부드럽게 모았다. 바뀐 정점은 3,534개, 최대 이동은 22mm이다. 교복의 POSITION/NORMAL만 원본 GLB에 반영해 107개 본·역바인드·가중치·UV·재질·텍스처를 그대로 유지했다. Blender 재수출로 본 roll이 바뀐 시도는 배포하지 않는다. 변신복 소매와 케이프는 원본 그대로다.

휘두르기·찌르기·캐스팅·쓰러짐의 일부 구간에는 장비의 아래팔 회전과 작은 위치 보정을 추가했다. 옷의 실제 스킨 포즈로 피팅한 키이며, 게임에서 매 프레임 메시 충돌을 계산하는 방식이 아니다. 원래 캐릭터 모션, 손과 지팡이 그립은 바뀌지 않는다. 정확한 손목 접촉·실제 기계 관절 구조까지 검증한 결과는 아니다.

종아리 장비는 15mm 몸 쪽으로 당기고 정강이 보호대를 78% 길이로 줄여 부츠 위에 여유를 줬다. 두 의상의 실제 종아리 표면을 따라 위·아래 고정 밴드를 만들고 앞쪽 장착부를 보호대까지 연결했다. 네 밴드와 정강이는 해당 정강이 본을 함께 따른다. 밴드 안쪽의 여유는 표본별 기록에 포함한다.

## 원본 유지와 검사 범위

- 원본 78,474개 면 중 73,673개 면을 현재 장비에서 유지하며, UV 최대 차이는 0이다. 교체한 위팔 중간의 4,801개 면은 숨긴 원본에 남는다. 새 연결대·밴드는 총 5,376개 삼각형이다. 원본 2K 이미지 3장은 byte-identical이다.
- 정지 저장본과 새 GLB 반입의 장비 QA는 오류 없이 통과했다. 기존 UV/노멀 이음, 좁은 열린 경계와 원본 내부 접합면 경고는 유지한다. 새 단색 금속 부품은 반복 UV를 사용하므로 개별 텍스처 베이킹용 UV는 아니다.
- 교복 메시 QA는 수정 전후 동일한 기존 항목을 보고한다: 4개 초과 가중치 정점, 11쌍의 작은 공면 보고와 소수 원본 분리 조각. 이번 피팅으로 추가된 오류는 없다. 기존 최대 8개 가중치를 임의로 줄이지 않았다. [의상 검사](../../../reports/exoskeleton_v4/outfit_qa.json), [바인드·버퍼 보존](../../../reports/exoskeleton_v4/outfit_preservation.json).
- 400개 Godot 자세 / 48,005개 리그 검사, 별도 800개 키 표본 / 96,005개 검사, 1,928개 연속 자세 / 580개 검사를 사용한다. 실제 최종 통과 여부는 [검사 기록](../../../reports/exoskeleton_v4/delivery_manifest.json)에 있다. 대기·달리기 끝점과 연결대 이동 범위도 검사한다.
- [400개 자세 의상 교차](../../../reports/exoskeleton_v4/equipment_fit.json), [더 촘촘한 800개 표본](../../../reports/exoskeleton_v4/equipment_fit_800.json), [같은 검사기로 다시 측정한 v3](../../../reports/exoskeleton_v4/baseline_fit.json). 모든 의상의 인덱스를 64비트로 확장해 65,535개를 넘는 결합 정점에서 오버플로가 생기지 않도록 했다.
- Blender에 구운 400개 포즈를 검증하고 저장 파일을 다시 열어 동기화된 NLA 목록을 확인한다. 실제 GPU 리뷰는 두 의상 × 8개 모션 × 앞·뒤 × 49장과 측면·표시 크기 4장을 사용한다.

교차 검사는 표본 시점의 장비/의상 삼각형 검사다. 관통 깊이, 모든 중간 시점, 새 모션, 공격 중단·블렌드, 머리카락·맨몸·지면·장비 부품 사이의 실시간 충돌을 보장하지 않는다. 게임의 최종 경량화/LOD, 성능 예산이나 사용자 아트 승인도 별도다.

## 연결과 재현

`game/tests/helpers/exoskeleton_v4.gd`는 현재 캐릭터의 `Skeleton3D` 아래에 붙인다. `initialize(skeleton)` 후 `fit_form(player, form)`으로 해당 의상 복사본을 선택한다. 캐릭터 모션을 샘플링한 **다음** `sync_pose_for_motion(motion_name, normalized_phase)`를 호출한다. `attack_thrust`는 독립 모션 이름이다. 이름·위상을 전달하지 않는 `sync_pose()`만 호출하면 해당 구간의 보정이 빠진다. 기존 캐릭터 `MODEL_SCALE`을 상속하며 별도 추가 축 회전·스케일을 적용하지 않는다.

제작은 v3 정지 파일에서 `build_exoskeleton_v4.py`, `seat_exoskeleton_v4_calf_mounts.py`, `retain_exoskeleton_v4_transformed_sleeves.py`를 한 번씩 적용했다. 완성 파일에 재적용하지 않는다. `package_exoskeleton_v4_assets.py`와 `package_exoskeleton_v4_outfits.py`로 배포한다. 후자는 반드시 원본 GLB를 읽어 교복 위치/노멀만 패치하며, 변신복은 파일 그대로 복사한다.

보정 키는 `fit_exoskeleton_v4_clearance_curves.py` → `package_exoskeleton_v4_clearance_curves.py` 순으로 만든다. 게임에서 `exoskeleton_v4_art.gd`와 `-- --bake` 모드를 각각 실행한 뒤 `check_exoskeleton_v4_fit.py`와 `-- --bake` 모드로 확인한다. 800개 표본에서 필요한 중간 키는 피팅 도구의 `--augment` 모드로 추가하며 기존 검사 키를 보존한다. 추가 후 원래 패키저를 실행하면 보완 키가 사라지므로 주의한다.

`bake_exoskeleton_v4_preview.py`가 편집본을 만들고 `validate_exoskeleton_v4_saved_preview.py`가 다시 열어 검사한다. `review_exoskeleton_v4.gd -- --output=<절대 review 폴더>`로 GPU 화면을 만들고 `package_exoskeleton_v4_review.py`로 오프라인 HTML을 만든다. Blender 5.1.1 / MCP 1.8 protocol 15 / Godot 4.6.2를 사용했다.
