# 입장 변신 v27 — 의상 전환·헤어 본

2026-11-01. 사용자가 수정한 v26 지팡이 잡기/전신 동작을 보존하고, 의상이 바뀌는 연출과 세미롱 헤어 움직임을 추가했다. 사용자가 현재 변신 연출과 헤어 본 작업을 시험판용으로 선택하고 커밋을 요청했다. [선택 기록](../../../../../../../reports/transformation_v27/approval.json)의 범위와 아래 검증 한계를 따른다.

- 작성본: `transformation_v27.blend` (Blender 5.2.3 LTS, 텍스처 패킹)
- [실제 게임 비교](../../../../../../../reports/transformation_v27/review.html)
- [검증·현재 파일 해시](../../../../../../../reports/transformation_v27/delivery_manifest.json)
- 게임 헤어: `game/assets/characters/player/transformation_v27/hair_semilong_v27.glb`
- 제작용 내보내기 사본: `assets/characters/player/3d/exports/transformation_v27/`

## 의상 전환

2.12–2.85초 동안 발끝에서 어깨 위로 올라가는 빛의 경계가 평상복을 지우고 변신복을 드러낸다. 양쪽 모두 완성된 의상 메시를 같은 현재 몸체 자세에 연결한다. 두 메시의 상보적인 불투명 클리핑을 사용하므로 반투명 정렬에 의존하지 않는다. 기존 몸체 가림 영역은 유지한다.

논리적인 의상 교체는 기존 2.40초, 전투 시작은 3.00초다. 지팡이 조립 0.30–1.15초, 오른손 잡기 1.40초, 양손 정렬 2.10초와 떠 있는 지팡이 좌표도 그대로다. 취소·죽음·초기화는 임시 메시를 지우고 해당 시점의 완성 의상을 복구한다. 정지는 경계와 헤어 자세를 함께 멈춘다.

`outfit_reveal.gd`와 `outfit_reveal.gdshader`가 재질의 색·노멀·거칠기·금속성 텍스처 및 채널을 유지한다. `field_entry_transformation.gd`는 경계와 광환 위치를 같은 시간축으로 진행한다. 원래 v4 의상 GLB, 웨이트, 32개 천 보조 본과 클립은 수정하지 않았다. 새 치마 펄럭임이나 천 시뮬레이션을 추가한 것은 아니다.

## 헤어 구조

공통 몸체의 107개 rest 본은 바꾸지 않았다. 새 헤어는 별도 `HairRig_v27`의 8개 본을 사용한다.

| 종류 | 본 |
|---|---|
| 몸체 연결 | `DEF-head`, `DEF-chest` — 기존 전역 rest와 동일한 두 독립 루트 |
| 왼쪽 | `DEF-hair.01.L`, `DEF-hair.02.L` |
| 오른쪽 | `DEF-hair.01.R`, `DEF-hair.02.R` |
| 뒤쪽 | `DEF-hair.01.Back`, `DEF-hair.02.Back` |

두피·앞머리를 고정하고 아래 가닥에만 2단 변형을 준다. 원래 가슴 웨이트도 보존해 목 아래 연결이 갑자기 떨어지지 않게 했다. 최대 4웨이트다. 변신은 24fps/73표본의 `hair_transform_overlap_v27`를 사용하며 고개를 늦게 따라오고 의상 전환 때 약하게 바깥으로 들렸다가 가라앉는다. 이후 동작에서는 고개 회전에 대한 작은 감쇠 반응을 사용한다. 이는 제한된 보조 움직임이며 머리/케이프 충돌 물리가 아니다.

`Hair_Semilong_v7` 원본은 숨긴 채 그대로 보존했다. 파생 헤어만 작은 독립 조각 62정점/48삼각형을 제거하고 겹침 26정점을 최대 0.7mm 보정했으며 UV 2면을 고쳤다. 최종 작성 메시 19,931정점/25,161삼각형, 내보낸 헤어는 UV·노멀 분할로 20,886정점이다. 텍스처 원본은 보존하고 런타임은 2K다. GLB는 약 5.61MiB다.

`modular_character_runtime.gd`는 명시적인 `auxiliary_hair: true`인 헤어만 이 별도 뼈대 방식으로 받는다. 8본 이름·부모·연결 rest·스킨 bind를 검사한다. 일반 몸체/눈/의상의 엄격한 공통 뼈대 검사는 그대로다. 기존 v21 헤어로 돌아갔다가 v27을 다시 장착하는 교체와 실패 시 이전 파츠 유지도 검사했다. 커스터마이징 UI나 트윈테일 완성 작업은 포함하지 않았다.

## 검증과 재현

저장된 Blender 파일을 다시 열어 원래 29메시·107본 rest·63액션의 서명을 대조했다. 새 헤어 73프레임의 본 회전/연결, 웨이트 합계/최대 영향 수도 검사했다. 실제 GLB를 Blender로 재반입해 설치한 `blender-asset-qa` 검사를 통과했다. UV/노멀 경계의 중복 정점과 머리 높이에 있는 파츠라는 경고는 의도된 것이다.

게임은 30·60·120fps에서 헤어 연결, 점진 전환, 정지/취소/죽음/교체를 검사했다. 기존 v26 지팡이/전투 시계 회귀 검사, 실제 의상과 전환 재질의 GPU 비교, 외형 레지스트리 검사도 포함한다. 총계와 파일 해시는 전달 매니페스트를 따른다. 실제 게임 663장: 앞/뒤/1.75배 기준 카메라/일시정지와 변신 후 달리기·타격·캐스팅·경직·스프링 도약.

```powershell
./tools/run_transformation_v27.ps1 -Test transformation_v27
./tools/run_transformation_v27.ps1 -Test transformation_v27_regression
./tools/run_transformation_v27.ps1 -Phase gpu_test -Test outfit_material_parity_v27
./tools/run_transformation_v27.ps1 -Phase review
python tools/package_transformation_v27.py
```

원본에서 재작성하려면 `build_transformation_v27.py` 후 `finalize_transformation_v27.py`를 사용한다. 현재 최종 작성본은 초기 빌드 뒤 MCP로 국소 수정한 파일이며 저장 파일 검증과 실제 GLB 재반입 결과가 최종 기준이다. `qa_hair.json` 등 초기 실패/메모리 부족 시도의 중간 기록을 최종 통과 결과로 인용하지 않는다. 최종 QA는 `qa_exported_hair.json`이다.

본 작업은 게임 기본값이다. 비교가 필요하면 `debug/entry_polish_v27=false`로 기존 헤어/일괄 교체를 볼 수 있다. v26 동작 클립과 v4 의상 파일은 두 경우 동일하다. 원본 의상의 접촉 한계, 모든 임의 자세의 무관통, 실제 성능 예산은 이번 검증 범위 밖이다. 이전 작업과 다른 작업자의 전투·성능 변경을 되돌리지 않는다.
