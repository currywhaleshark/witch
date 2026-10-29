# 지팡이 · 공구 재질 v3

2026-10-30. 사용자가 선택한 볼트커터 v2 형태와 개폐 동작을 유지하면서 기본 지팡이·볼트커터·그라인더·전기톱·인장 장식의 재질을 다듬었다. 기존 형상 선택은 `../staff_transform_v2/approval.json`에 기록했다. 사용자가 「좋아 커밋하고」로 이 재질을 시험판용으로 선택했으며 `approval.json`에 기록했다.

- 시작 파일: `authoring/staff_material_v3.blend` — 텍스처를 내부에 포함한다.
- 런타임 출력: `exports/staff_parts.glb`와 `game/assets/weapons/staff_material_v3/staff_parts.glb`는 동일하다.
- 비교와 실제 게임 재생: `reports/staff_material_v3/review.html`.
- 부품·피벗·공구 동작·소켓: `parts.json`. 메커니즘 수치와 부품 목록은 v2와 동일하다.

## 표면 방향

남색 도장은 은은한 반광, 황동은 따뜻한 색 변화와 작은 모서리 마모, 검은 강철은 차분한 표면, 절삭면은 밝은 연마면으로 나눈다. 그립은 거친 무광이고, 청록 코어는 낮은 발광과 표면 변화로 구분한다. 틈의 오염은 부품 내부의 국소 음영을 사용한다. 넓은 날 면이 얼룩덜룩해지지 않도록 강한 마모는 작은 모서리·베벨 면에 제한했다.

재질은 기존 Blender 원본에서 만든 절차적 셰이더를 UV 텍스처로 베이크했다. 이미지 생성 서비스나 Tripo 재생성을 사용하지 않았다. 기준 조명은 게임의 현재 색상 환경광과 방향광이다. 재질을 보여주기 위해 게임 전역 조명·노출을 변경하지 않았다.

## 저장 구조와 비용

52개 강체 메시, 7,316개 삼각형을 그대로 유지한다. 모든 메시의 좌표·폴리곤·정점 법선·피벗·상위 노드와 공구 개폐/회전/조립 데이터가 v2와 같다. UV와 재질 할당은 새 공통 아틀라스에 맞춰 변경했다.

| 지도 | 크기 | 용도 |
|---|---:|---|
| `staff_color.png` | 1024² | 도장, 황동, 강철, 국소 마모 |
| `staff_orm.png` | 512² | R: 국소 음영 / G: 거칠기 / B: 금속성 |
| `staff_normal.png` | 1024² | 얕은 모서리 반사와 미세한 표면 |
| `staff_emission.png` | 256² | 원래 청록 코어 면의 발광 |

`Staff_PBR_v3`와 `Staff_Core_v3` 두 재질이 이 지도 묶음을 공유한다. 일반 표면은 발광을 사용하지 않는다. 코어와 일반 면을 별도 재질로 분리해 작은 밉맵에서 청록 발광이 황동으로 번지는 것을 막았다. 전체 GLB의 재질별 표면 구획은 86개에서 55개로 줄었다. 이것을 실제 프레임 드로콜이나 성능 측정값으로 해석하지 않는다.

현재 가져오기는 무손실 압축과 밉맵을 사용한다. 지도 전체의 미압축 RGBA8+전체 밉 기준 크기는 약 **12.3MiB**로 추산한다. 이는 GPU/CPU 총 메모리 실측이나 최종 성능 예산이 아니다. 공통 텍스처는 장착한 공구끼리 재사용한다. 원본과 런타임 파일 크기는 검증 매니페스트에 있다.

7개 원본 절차적 재질은 Blender에 남겨 두었으며 `authoring/source_material_regions.json`이 원래 면별 재질 구역을 기록한다. `WearRegion`은 베이크용 모서리 마모 속성이고, `FinishNormal`은 날의 날카로운 면에 불필요한 둥근 반사가 들어가지 않게 한다. 블렌더의 원본 n-gon을 바꾸지 않고, 게임 가져오기에서 UV와 법선으로 탄젠트를 생성한다. 실제 엔진의 모든 표면에 탄젠트가 생성되는지 별도로 검사했다.

## 검증과 이어서 작업하기

최종 **448개 검사와 298장 GPU 캡처**가 통과했다. 해시는 `reports/staff_material_v3/delivery_manifest.json`을 따른다. 저장 Blender 재개방, GLB의 52개 메시 형상·법선·변환 대조, 네 지도·채널·코어 발광 제한, 실제 Godot 가져오기, 기존 조립/교체/일시정지/정리와 30/60fps의 볼트커터 타격 동기화를 확인했다. 리뷰는 동일 조명의 전후 비교 7장, 회전 보기, 실제 게임 5개 시퀀스를 포함한다. 절삭면과 검은 강철 등 원래 재질 경계는 UV 영역도 분리해 색 경계의 계단 현상을 줄였다.

런타임 코드는 `staff_visual.gd`의 자산 경로만 바꾼다. 캐릭터 v21, 동작 클립, 공격 속도·피해·비용과 기존 v2 개폐 곡선을 수정하지 않는다. 원본 v2와 이전 리뷰는 보존한다.

재생성: `tools/build_staff_material_v3.py`를 별도 Blender의 `--background --factory-startup --python-exit-code 1`로 실행한다. 사용자 Blender에서 실행하지 않는다. `validate_staff_material_source_v3.py`와 `validate_staff_material_v3.py`가 저장 원본과 GLB를 검사한다. `tools/run_staff_material_v3.ps1`의 import/test/review와 `tools/package_staff_material_v3.py`가 게임 검증과 리뷰를 만든다.

현재 마모량·광택은 시험판용으로 선택되었다. 대기에서 이동할 때 지팡이가 좌우로 돌아가는 현상은 별도 후속 수정이다. 임의 자세에서의 접촉과 최종 GPU 성능 측정은 별도다. 이번에는 큰 찌그러짐·깊은 손상이나 추가 형상을 만들지 않았다.

## 형식 참고

거칠기/금속성과 국소 음영은 [Blender glTF 내보내기 문서](https://docs.blender.org/manual/en/dev/addons/scene_gltf2.html)의 이미지 채널 규약을 따른다. 실제 런타임 재질은 [Godot의 표준 3D 재질](https://docs.godotengine.org/en/4.5/tutorials/3d/standard_material_3d.html)로 가져온다.
