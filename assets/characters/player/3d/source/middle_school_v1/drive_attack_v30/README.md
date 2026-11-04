# 구동 공격 모션 v30 — 비교 시안

사용자 요청: 무료 모션으로 볼트커터 연속찌르기, 그라인더 반원 휘두르기, 전기톱 지속절단/한 바퀴 휘두르기를 시험한다. 큰 날 절단은 기존 모션을 유지한다.

- 검토: `reports/drive_attack_v30/review.html` — 실제 Godot GPU 캡처 300장, 두 의상 동시 재생, 4개 MP4, 0.25/0.5/1배속·프레임 이동.
- 편집 원본: `drive_attack_v30.blend` (Blender 5.1.1). 기존 34개 메시, 107개 본의 rest/weights, 64개 액션을 최종 재개봉 후 그대로 확인했다. 8개 새 액션만 추가했다.
- 엔진 준비 파일: `game/assets/characters/player/drive_attack_v30/`. 메인 player_visual/스킬 로직에는 아직 매핑하지 않았다.

## 동작과 원본

볼트커터는 Kevin Iglesias Human Melee Animations FREE의 `HumanF@AttackPolearm01` FBX에서 몸통과 손 중심의 당기기/찌르기 변화를 축소했다. 발은 작은 준비 스텝 후 반복 중에 고정한다. 가디건/치마의 기존 보조 본을 사용한다.

그라인더는 공식 Mixamo `Great Sword Slash` 중 설명이 **Great Sword Low Slash**인 모션의 몸통 곡선을 축소하고, 공구 궤적을 전방 반원으로 맞췄다. `Great Sword High Spin Attack`은 실제 골반 회전과 발 상대 위치에서 이동을 제거·축소하고, 날을 낮춰 전기톱 회전으로 바꿨다. 손/공구는 그대로 옮긴 것이 아니라 기존 오른손 위·왼손 아래 26cm 그립으로 재해석했다. 지속절단은 앞에 날을 유지하는 새 반복 동작이다.

원본 FBX와 추출된 원본 곡선은 gitignored `reports/drive_motion_research_v1/local/` 및 `reports/drive_attack_v30/local/`에만 보관한다. 출처/다운로드 설정/해시는 research candidates, `mixamo_downloads.json`, build report에 있다. Kevin .blend의 순환 IK 경고를 피하기 위해 baked FBX를 사용했다.

## 재생 계약

모든 파일은 **24fps**, 상수 채널 유지, optimizer/compression 비활성이다. 모든 107본에 translation/rotation/scale 321채널이 있다. 빠른 구간의 접촉 오차를 줄이려고 author 시간에 키를 더 저장했다. **`duration`은 저장된 곡선의 길이, `preview_duration`은 이 비교 화면의 재생 시간**이다. 엔진에는 `clip_time = phase * duration`을 전달한다. 이를 그대로 게임 속도로 결정하면 안 된다. 향후 실제 스킬 시간에 phase를 매핑해야 한다.

| 클립 | 키 수 | 저장 길이(s) | 시안 길이(s) |
|---|---:|---:|---:|
| drive_bolt_enter_v30 | 25 | 1.000 | 0.333 |
| drive_bolt_loop_v30 | 97 | 4.000 | 0.833 |
| drive_bolt_exit_v30 | 25 | 1.000 | 0.333 |
| drive_chainsaw_cut_enter_v30 | 25 | 1.000 | 0.333 |
| drive_chainsaw_cut_loop_v30 | 25 | 1.000 | 1.000 |
| drive_chainsaw_cut_exit_v30 | 25 | 1.000 | 0.333 |
| drive_grinder_sweep_v30 | 145 | 6.000 | 1.667 |
| drive_chainsaw_spin_v30 | 73 | 3.000 | 2.000 |

진입 → loop 3회 → 복귀가 리뷰 순서다. 커터 닫힘은 loop phase 0.5에 맞춘 시각 연출이며 피해 이벤트를 만들지 않는다. 임의 phase에서 취소/피격/회전 입력을 처리하는 게임 컨트롤러는 아직 연결하지 않았다.

`staff_slide_tracks`를 모든 클립에 적용한다. 절대로 기존 idle의 -0.26m를 새 모션 전체에 고정하면 안 된다. 기존 가드의 팔 비틀림 잔여값을 진입/복귀에 보정하고, 베기의 복귀 구간은 본의 월드 위치를 유지하면서 twist winding을 정리했다. bolt loop와 grinder sweep에는 양손/팔 IK를 풀어 넣은 중간 키가 추가됐다. 여러 캐릭터를 나란히 보는 도구는 AnimationLibrary를 캐릭터마다 복제해야 한다. 같은 라이브러리에 새 액션을 중복 추가하면 이번 엔진 버전에서 재생 전환 중 native crash가 발생했다.

## 확인 결과와 한계

- 새 액션 8개 / 정수·중간 자세 872개: 유한값, 단위 스케일, 양손 그립, 연결 자세 및 loop pose/velocity seam 확인. 최대 보조손 접촉 기준점 오차 **2.615mm**.
- 최종 저장 원본 보호 데이터: 메시 34개, 기존 액션 64개, rest 본 107개 동일. SHA-256 `74c885daec8e0ebb739004f131233af960b91e5b009a308a6833b74d6e15d370`.
- 8 GLB: 107-joint skin, 321채널, 동일 inverse-bind bytes. Blender 재가져오기 asset QA 오류 0. 애니메이션 전달 전용 12-triangle cube는 실제 플레이어에서 표시하지 않는다. 재가져오기 duplicate 12 vertices는 cube의 정상/UV seam이므로 유지했다.
- 최종 Godot import/검증: 252,331 assertions, 최대 bone-head 오차 0.003626mm. GPU 비교: 두 의상, 300장 / 65,151 checks. 리뷰 스튜디오만 약한 조명을 사용하며 메인 게임 조명은 바꾸지 않았다.
- source의 옷 보조 본을 활용했지만 모든 옷/머리/손가락의 triangle 접촉을 인증한 것은 아니다. 발판 접지·원본 mocap의 정확한 foot lock·외골격 v4의 새 자세 clearance·실제 공격 판정·성능은 후속 범위다. 사용자 모션 선택 전의 비교 후보이다.
- Blender 썸네일 디렉터리와 Godot user:// shader-cache/profiler 디렉터리 권한 경고는 로그에 보존했다. 출력 자산 및 GPU 캡처는 저장됐으며 해당 경고를 빈 stderr로 보고하지 않는다.

## 재현 순서

1. `inspect_drive_motion_v30.py` (로컬 원본 FBX 필요)
2. `build_drive_attack_v30.py`
3. `polish_drive_attack_v30.py` (build 후 한 번만 실행)
4. `validate_drive_attack_v30.py`, `check_drive_preservation_v30.py`
5. `export_drive_attack_v30.py`, `reimport_drive_attack_v30.py`
6. `prepare_drive_attack_v30.py`
7. `run_drive_attack_v30.ps1 -Phase import`, `-Phase validate`, `-Phase capture`
8. `package_drive_attack_v30.py`

Blender 스크립트는 별도 background 프로세스와 `--disable-autoexec --python-exit-code 1`로 실행한다. 원본/다른 작업자의 파일을 열어 덮어쓰지 않는다. 현 live MCP 소재 작업 장면은 유지했다.
