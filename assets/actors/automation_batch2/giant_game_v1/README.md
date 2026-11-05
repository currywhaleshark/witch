# 거대 자동인형 v1

2026-11-05. **게임 연결 전 모델·모션 검토 후보**. [통합 검토](../../../../reports/automation_batch2_complete_v1/review.html), [parts.json](parts.json), [검증 기록](production.json).

아래부터 조립되고 마지막에 바이저가 켜진다. 묵직한 보행과 양손 내리치기, 부품 붕괴.

- 15,943 삼각형 / 27 강체 그룹 / 33 본 / 2 런타임 재질.
- 편집 원본: [giant_game_v1.blend](giant_game_v1.blend). 텍스처가 packed되어 있고 대기/신호 상태로 열린다.
- 게임용: `game/assets/actors/automation_batch2/giant_v1/`의 GLB·parts·import 설정·post-import 스크립트를 함께 복사한다.
- Blender +Y 전방이 GLB/Godot −Z 전방으로 변환된다. 미터 단위, Y up, 바닥 중심 원점, 단위 오브젝트 배율.
- 정점별 하나의 본에 100% 연결. 삼각형은 그룹 경계를 넘지 않고 부품의 애니메이션 배율은 1이다.
- Tripo 원본 2K 재질을 1K 색·OpenGL 노멀·ORM으로 베이크했다. ORM R=1로 별도 AO 베이크는 없다. 기본형은 128px 발광 맵과 독립 발광 재질, 추가 장갑은 불투명 재질 하나다.

## 클립과 접점

| 클립 | 길이 | 방식 |
|---|---:|---|
| `assemble` | 1.2s | 단발 |
| `idle` | 2s | 루프 |
| `walk` | 1.2s | 루프 |
| `slam` | 1.8s | 단발 |
| `hit` | 0.3s | 단발 |
| `death` | 1.8s | 단발 |

부품이 위에서 내려와 발→다리→몸통→팔→머리 순으로 맞물린다. 바이저는 1.10–1.20초에 켜진다. `slam` 피해 접점은 **0.55초**, 두 주먹의 최소 높이 12mm, 두 주먹 사이 `Socket_attack`이다. `walk` 1.2초 / 2.6m/s / **3.12m 주기 거리**. 손목 실린더와 로드는 고정 길이이며 미끄러질 뿐 늘어나지 않는다. 증기는 준비용 presentation helper의 6개 소형 빌보드다.

`parts.json`에 그룹별 본·부모·피벗, 소켓, 그림자 반경을 기록했다. **24fps + 정확한 이벤트/끝점/접지 subframe 키**를 보존해야 한다. 상수 트랙 유지, optimizer/compression 비활성화만으로는 Godot 재샘플링을 막을 수 없어 `import_exact_animation.gd`가 원본 GLB 키를 복원한다. 리뷰 MP4의 루프는 정확한 반복 길이를 위해 30fps로 촬영한 것이며 원본 클립 시간은 바뀌지 않는다.

기본형 발광·증기는 `game/tests/helpers/automation_batch2_visual.gd`의 `sample(model, actor, clip, seconds)`로 프레임을 지정한다. pause/seek에 결정적이며 매 인스턴스 발광 재질만 복사하고 텍스처·메시는 공유한다. 추가 장갑의 Blender 파일에는 기본 몸체 참고 리그도 들어 있다. 기본 리그의 `BasePreview_*`와 장갑 리그의 같은 이름 클립을 동일 시각에 샘플링해야 함께 움직인다.

## 검증과 범위

저장 원본·새 GLB import의 오류 0. 120Hz 바닥/강체/루프 검사, 정확한 키 복원과 Blender↔Godot 본 위치 비교, 실제 GPU 촬영을 통과했다. 현재 입력 해시는 [delivery_manifest.json](../../../../reports/automation_batch2_complete_v1/delivery_manifest.json)에 있다.

원본 외피의 열린 경계, UV·노멀 이음 정점, 내부 축·맞닿는 장갑 뒷면은 보존했다. 해당 경고의 실제 목록은 production.json을 따른다. 임의 자세 충돌·경사/벽·파편끼리의 물리 접촉·최종 성능·사용자 외형 승인은 이 검증에 포함되지 않는다. 붕괴는 지정 시작 자세에서 구운 동작이다. 게임 규칙·표적·실제 FX·노드 전환 연결은 별도 코드 작업이며 사양 문서는 수정하지 않았다.

생성/재현 스크립트는 `tools/build_giant_game_v1.py`, 애니메이션은 `tools/animate_giant_game_v1.py`, 공통 export/QA는 `tools/export_automation_actor.py`, `tools/validate_automation_actor.py`다. `*_geometry.blend`와 `*_static.glb`는 로컬 중간 산출물이며 최종 전달 파일은 위 packed 원본과 애니메이션 GLB다.
