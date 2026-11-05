# 자동화 2차 · 모델과 모션

2026-11-05. 사용자가 확인을 기다리지 말고 나머지까지 진행하도록 요청하여, 세 원화에 기반한 모델·분할·강체 리그·클립·강화 부품을 준비했다. [ART_REQUEST.md](ART_REQUEST.md)가 제작 사양이며 게임 규칙 문서는 변경하지 않았다.

**[최신 수렵견 전신 질주 v4](../../../reports/hound_fullbody_v4/review.html)** — 낮게 고정하던 몸통 보정을 제거하고 CC0 늑대의 몸통·골반·목·머리·꼬리까지 함께 적용했다. 화면 왼쪽이 수정본이다. 거대 인형의 축 수정은 [회전축·질주 v2 검토](../../../reports/automation_motion_v2/review.html), 최초 모델과 전체 클립은 [이전 통합 검토](../../../reports/automation_batch2_complete_v1/review.html)에 보존한다. 게임 연결 전 아트 검토본이며 최종 외형 선택을 뜻하지 않는다.

| 자산 | 삼각형 | 강체 그룹 / 본 | 클립 | 상태 |
|---|---:|---:|---:|---|
| [수렵견 기본형 v4](hound_game_v4/README.md) | 6,795 | 33 / 37 | 6 | 전신 질주·높아진 몸통·앞다리 회수·접지 |
| [유인 신호기 v1](beacon_game_v1/README.md) | 4,237 | 16 / 21 | 5 | 새 Tripo 모델·분할·경량화·리그 |
| [거대 자동인형 v2](giant_game_v2/README.md) | 15,943 | 27 / 33 | 6 | 톱니·태엽의 실제 축, 허브·렌즈 정렬 |
| [중장 추적기 장갑 v3](hound_armour_v3/README.md) | +1,388 | +4 / 별도 37 | 6 | 전신 질주 v4 대응, 전체 1.2배 |
| [단일 강화 장갑 v2](giant_armour_v2/README.md) | +1,256 | +6 / 별도 33 | 6 | 새 기본형 rest 대응, 전체 1.1배 |

신호기와 거대 인형은 기존 [원화](concept_v1/prompts.json)를 Tripo H3.1 HD/private/2K PBR로 생성하고 Fine 분할했다. 생성·분할 비용은 모델당 70, 이번 추가 작업 총 **140 크레딧**이다. [신호기 원본](beacon_tripo_v1/README.md), [거대 인형 원본](giant_tripo_v1/README.md)과 기존 [수렵견 원본](hound_tripo_v1/README.md)을 보존했다. 고밀도 원본의 열린 경계·겹침 등은 진단 상태로 남기고, 게임용 파생물에서 구동 경계와 주요 오류를 정리했다.

## 연결 계약

- 경로와 변형 배율: [catalog.json](catalog.json). 런타임 모델은 `game/assets/actors/automation_batch2/`에 준비되어 있다.
- 각 폴더의 **GLB·parts.json·import 설정·import_exact_animation.gd**를 함께 유지한다. 24fps에 정확한 타격/접지/끝점 키와 상수 트랙을 보존한다. Godot 기본 재샘플링만 쓰면 짧은 접지 키가 손실된다.
- Blender +Y → Godot −Z 전방, 미터, Y up, 바닥 원점, 모델 배율 1. 변형 배율은 기본+장갑을 묶은 부모에 적용한다.
- 장갑은 기본형과 같은 클립을 같은 초 단위 시간으로 재생한다. 살아 있을 때 본 위치는 일치한다. `death`는 수렵견 0.18초 / 거대 인형 0.22초부터 추가 장갑이 독립적으로 떨어진다. 수렵견은 **기본 v4 + 장갑 v3**, 거대 인형은 **기본 v2 + 장갑 v2** 조합이다. 장갑 메시와 독립 붕괴는 유지한다. 거대 인형의 gear/key/core/Socket_core 네 rest 원점이 바뀌었으므로 v1 장갑을 새 기본형과 혼용하지 않는다.
- 사냥 무리는 **0.8배 × 3**, 거대 다수 운용은 **0.75배 × 3**. 같은 메시 리소스를 공유한다. 1~3 번호 표식은 후속 인스턴스 장식으로 남겨 두었다.
- 타격 접점: 수렵견 `bite` **0.30초**, 신호기 `pulse` **0초**, 거대 인형 `slam` **0.55초**. 수렵견 v4 주기 거리는 **2.754772m / 0.5초 클립**(0.25초 질주 두 번)이다. **6.5m/s 이동에는 1.179771배 재생**을 사용하며 전체 배율도 보폭에 곱한다. v3의 3.25m 계약은 v4에 적용하지 않는다. 거대 인형은 **3.12m / 1.2초 / 2.6m/s**를 유지한다. 루트 이동은 게임이 담당한다.
- 발광·증기: `game/tests/helpers/automation_batch2_visual.gd`의 `sample(model, "beacon" 또는 "giant", clip, seconds)`. 신호기 시동/소등, 거대 조립 끝 바이저와 배기관 증기를 제공하는 준비용 보조 코드다. 신호 범위·음파·종소리·내리치기 먼지는 후속 게임 FX 범위다.

## 편집·검증·재현

각 버전의 최종 Blend는 packed 상태로 대기/신호가 선택되어 열린다. 장갑 파일에는 기본 몸체와 별도 장갑 리그가 함께 들어 있다. 새 v2 장갑의 기본 참고 리그는 `Previous_*`, 과거 v1은 `BasePreview_*`이며 장갑 리그의 같은 이름 클립과 함께 샘플링한다. `animation_samples.json.gz`에 정확한 검증 시각과 본 행렬도 보관한다.

수렵견 전신 v4는 [접지·전신·보존 검증](../../../reports/hound_fullbody_v4/motion_validation.json)과 [현재 입력 해시·검증](../../../reports/hound_fullbody_v4/delivery_manifest.json)을 기준으로 한다. 781개 저장 자세, 49,769개 엔진 확인과 GPU 캡처 721장을 기록했다. source/reimport QA 오류는 0이다. 이전 회전축·질주의 [143,501개 엔진 확인·961장 캡처](../../../reports/automation_motion_v2/delivery_manifest.json), 최초 통합본의 [134,752개 확인·1,455장 캡처](../../../reports/automation_batch2_complete_v1/delivery_manifest.json)는 당시 입력의 기록이다.

다른 PC의 Godot 4.6에서 재촬영:

```powershell
./tools/review_hound_fullbody_v4.ps1 -GodotPath 'C:/path/to/Godot.exe'
# 렌더링 없이 데이터·플레이백 확인만:
./tools/review_hound_fullbody_v4.ps1 -GodotPath 'C:/path/to/Godot.exe' -ChecksOnly
```

Blender 소스 재생성은 `build_beacon_game_v1.py` / `animate_beacon_game_v1.py`, `build_giant_game_v1.py` / `animate_giant_game_v1.py` 순서다. 장갑은 `build_automation_armour_v1.py -- hound|giant` 다음 `finish_automation_armour_v1.py -- hound|giant`를 실행한다. 공통 export는 `export_automation_actor.py beacon|giant|hound_armour|giant_armour`다. Blender 5.1.1에서 실행했다. 전체 로그·중간 Blend·개별 영상 프레임은 로컬에, 최종 packed Blend·GLB·PBR·영상·검증 JSON은 전달 대상으로 분리했다.

## 남은 범위

원본 외피의 열린 경계, UV/노멀 이음 정점, 숨겨진 맞댐 면과 내부 축을 보존했다. 실제 경고 목록과 이유는 각 production.json에 있다. 파괴는 지정 시작 자세의 구운 동작이며 임의 취소·블렌드·실시간 파편 충돌·경사/벽과의 접촉을 보장하지 않는다. 추가 장갑은 호환 리그를 복제하므로 실제 게임 연결 후 본/인스턴스 비용 최적화가 남는다.

**스킬 규칙·표적·실제 FX·노드 전환 연결, 최종 외형 선택과 성능 확인은 다음 단계**다. 이번 작업은 game/assets와 game/tests의 준비 자산이며 본 게임 스크립트·기존 캐릭터·스킬 문서는 수정하지 않았다. 커밋·푸시는 수행하지 않았다.
