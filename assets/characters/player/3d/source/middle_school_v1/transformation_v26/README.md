# 전투 필드 입장 변신 v26 — 전신 연기·타이밍 개선 후보

2026-10-31. 사용자가 v25 입장 변신이 "너무 뻣뻣하고 심심하다"고 해서, 분석 결과 1번 항목인 **전신 연기와 타이밍**을 개선했다. 사용자 요청으로 **게임 입장 클립을 v26으로 교체했다.** [실제 게임 v25·v26 나란히 보기](../../../../../../../reports/transformation_v26/review.html), [검증·해시](../../../../../../../reports/transformation_v26/delivery_manifest.json). 사용자 외형 선택 전 후보다.

## v25에서 무엇이 문제였나

- **몸이 굳어 있었다.** v25 작성 스크립트는 매 프레임 대기 자세 첫 프레임을 그대로 복원한 뒤 팔만 덮어썼다. 그래서 107개 뼈 중 팔·손가락 44개만 움직였고, 골반·척추·가슴·목·머리·다리·치마·가디건은 3초 내내 0mm였다.
- **멈춘 시간이 길었다.** 손이 움직이는 시간은 3초 중 1.13초였다. 0–0.33초, 1.21–1.5초, 2.13–3.0초(의상 교체 구간 전체)는 완전히 멈췄다.
- **동작이 기계적이었다.** 두 동작 모두 같은 대칭 smoothstep 하나라 예비동작·오버슈트·안착이 없었다. 양손이 같은 프레임에 출발하고 도착했다. 공용 `blend_stops`는 구간마다 smoothstep이라 키마다 완전히 멈춘다.

## v26에서 바꾼 것

런타임 이벤트(조립 0.30–1.15초, 잡기 1.40초, 양손 2.10초, 의상 교체 2.40초, 전투 3.00초)와 떠 있는 지팡이 프레임은 v25와 같다. 그래서 게임에 넣을 때는 클립 이름만 바꾸면 된다.

| 시간 | v26 연기 |
|---|---|
| 0–0.3초 | 도착 안착과 들숨, 고개를 든다 |
| 0.3–1.15초 | 조립 시작을 알아채고 고개가 빠르게 돌아간다. 조립 지점을 따라 보고, 상체를 살짝 돌리고, 왼다리로 체중을 옮긴다 |
| 1.0–1.4초 | 손을 살짝 당겼다가(예비동작) 빠르게 뻗고, 2cm 오버슈트했다가 돌아와 잡는다. 오른발 반걸음, 상체 기울임 |
| 1.42–1.64초 | 지팡이 무게가 손에 실린다. 손이 2.8cm, 손목이 7° 처지고 무릎이 굽는다 |
| 1.5–2.1초 | 지팡이를 호를 그리며 대기 자세로 가져온다. 가슴이 지나쳤다가 돌아오고, 왼손은 0.15초 늦게 따라 붙는다. 발은 원위치 |
| 2.1–3.0초 | 살짝 웅크렸다가(예비동작) 2.40초 교체 시점에 가슴을 펴고 턱을 든다. 그 뒤 대기 자세로 안착한다. 호흡은 2.45초부터 사라진다 |

- **키 보간:** Catmull-Rom 접선의 C1 3차 곡선을 써서 중간 키에서 멈추지 않고 흘러간다.
- **시선:** 눈은 텍스처라 움직일 수 없어서 머리가 대신 본다. 앞 카메라에서 얼굴이 보이도록 머리 방향을 오른쪽 34°/왼쪽 20°, 아래 32°/위 14°로 제한했다. 첫 시도에서는 59°까지 돌아가 뒤통수가 보였다.
- **발:** 다리 IK로 고정한다.
- **치마·가디건 보조 뼈:** 기존 다리 추종·충돌 보정 함수를 실행한 뒤, 대기 자세 대비 **변화분만** 대기 자세의 보조 뼈에 더한다.
- **마지막 0.3초:** 정확한 대기 자세 basis로 섞는다.

## 검증

[build_validation.json](../../../../../../../reports/transformation_v26/build_validation.json)

| 항목 | 결과 |
|---|---|
| 1.40초 잡기를 감싸는 33·34프레임의 손-떠 있는 지팡이 중심 오차 / 축 오차 | 0.0007mm / 0° |
| 2.10초 이후 양손 지팡이 간격 오차 | 최대 0.007mm |
| 고정된 왼발 미끄러짐 / 오른발 IK 오차 | 최대 0.05mm / 0.44mm |
| 팔·다리 IK 도달 부족 | 0.0001mm 미만 |
| 마지막 프레임과 `combat_idle_rh_v20` 첫 자세의 basis 차이 | 2.3e-7 |
| 손가락 반대 방향 굽힘 | 0 |
| 움직이는 뼈 | 107개 중 105개(v25 44개) |
| 오른손 / 머리 / 가슴 / 골반이 움직이는 시간 | 2.75 / 2.92 / 2.88 / 2.83초(v25 오른손 1.13초, 나머지 0초) |

- **보존:** 29개 메시, 107개 rest 뼈, 기존 62개 액션(v25 입장 클립 포함)의 해시가 그대로다.
- **비교 화면:** [게임 시점 GIF](../../../../../../../reports/transformation_v26/compare_game_small.gif), [옆 GIF](../../../../../../../reports/transformation_v26/compare_side_small.gif), [게임 시점 띠](../../../../../../../reports/transformation_v26/compare_game_strip.png), [옆 띠](../../../../../../../reports/transformation_v26/compare_side_strip.png). Blender 평상복 렌더이며, 0.30초부터 지팡이를 떠 있는 위치에 보이고 1.40초부터 손에 붙인다. 의상 교체는 화면에 표시만 한다.

## 게임 연결

- **바뀐 것:** `game/scripts/player_visual.gd`의 입장 클립 폴더(`transformation_v26/`)와 이름(`combat_transform_entry_v26`)만 바꿨다. 게임 폴더에는 클립 GLB와 런타임 계약만 넣었다.
- **그대로인 것:** 변신복은 기존 `transformation_v25/outfit_transformed_v4.glb`(v4 바이트 그대로)를 계속 쓴다. 레지스트리의 입장 항목은 v26 클립과 이 보고서를 가리킨다.
- **임포트 설정:** 새 클립은 기본값이 30fps·불변 트랙 제거·최적화 켬이라, v25와 같은 24fps·불변 트랙 유지·압축/최적화 끔으로 맞췄다.
- **검사:** 입장 검사 63개(30/60/120fps, 전투 정지·입력·정지/재개·재입장·사망·음소거, 뼈 오차 0.0024mm, 그립 0.0003mm, 부착 점프 0.008mm), 지팡이·스프링 도약·캐릭터 표시·로드아웃 회귀를 합쳐 런타임 검사 489개가 통과했다. 저장 Blender 145개 자세, Python 외형 7개 검사, 실제 게임 663장을 기록했다. 모든 실행의 입력 해시는 실행 전후 같다.

## 남은 범위

- **변신복:** 국소 소매·망토·머리 접촉 한계는 v25와 같다. 663장 중 앞·뒤 15장을 눈으로 확인했고 눈에 띄는 깨짐은 없었다. 모든 자세의 무관통 검증은 아니다.
- **이번 범위 밖:** 지팡이 조립 연출, 의상이 점차 드러나는 효과, 치마 펄럭임, 카메라, 효과음은 분석의 2–5번 항목이며 v25 연출 그대로다.
- **머리카락:** 전용 뼈가 없어 머리 회전을 그대로 따른다.

## 다시 실행

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup -P tools/build_transformation_v26.py
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup -P tools/finalize_transformation_v26.py
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b assets/characters/player/3d/source/middle_school_v1/transformation_v26/transformation_v26.blend -P tools/render_transformation_v26_compare.py -- reports/transformation_v26/compare_frames
& tools/run_transformation_v26.ps1 -Phase import
& tools/run_transformation_v26.ps1 -Test transformation_v26
& tools/run_transformation_v26.ps1 -Test staff_visual
& tools/run_transformation_v26.ps1 -Test spring_jump_v24
& tools/run_transformation_v26.ps1 -Test player_visual
& tools/run_transformation_v26.ps1 -Test loadout_dash
& tools/run_transformation_v26.ps1 -Phase review
python tools/package_transformation_v26.py
```

- **빌드 주의:** 빌드는 결과 blend를 새로 만든다. blend를 직접 손봤다면 빌드는 건너뛰고 finalize부터 실행한다.
- **패키지 단계:** 모든 실행 기록, 입력 해시, 캡처 수를 다시 확인한 뒤 매니페스트와 리뷰 페이지를 만든다.
