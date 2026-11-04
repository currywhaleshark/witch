# 구동 공격 모션 v31 — 동작별 그립과 측면 찌르기

사용자 피드백: 넓은 양손 그립을 고정한 채 크게 휘두르면 부자연스럽다. 오른손을 자루 아래로 내려 휘두르고, 찌르기는 오른쪽 어깨를 앞세워 자루 뒤쪽이 왼쪽 옆구리로 빠지게 한다.

- 검토: `reports/drive_attack_v31/review.html`. 이전 v30과 별도로 보존한 비교 후보이다.
- 편집 원본: `drive_attack_v31.blend`, `tools/build_drive_attack_v31.py`.
- 엔진 준비 파일: `game/assets/characters/player/drive_attack_v31/`. 메인 게임의 player_visual, 스킬 시간·피해·판정에는 아직 연결하지 않았다.
- v29의 기존 34개 메시, 107개 rest 본, 64개 액션을 유지하며 8개 새 액션만 만든다. v30 원본/GLB와 현재 사용 중인 캐릭터 자산은 수정하지 않는다.

## 자세 변경

| 동작 | 작업 그립 | 변경 |
|---|---:|---|
| 볼트커터 연속 찌르기 | 26cm | 오른쪽 어깨를 앞세운 상체, 작은 오른발 준비 스텝, 왼쪽 옆구리 바깥의 뒤쪽 자루 경로 |
| 그라인더 반원 베기 | 13cm | 오른손이 아래로 내려가며 좁아지는 그립, 몸통 회전, 베기 후 오른쪽 팔꿈치와 날이 올라가는 후속 경로 |
| 전기톱 지속절단 | 22cm | 비스듬한 상체와 왼쪽 앞의 공구 위치, 몸통 바깥의 보조손 |
| 전기톱 회전 베기 | 11cm | 좁은 아래쪽 그립으로 전환 후 회전, 몸 앞에 유지되는 두 손 |

기존 대기자세의 오른손 위/앞·왼손 아래/뒤 순서는 유지한다. 그라인더는 날이 가드 쪽으로 돌아온 뒤에야 그립을 다시 넓힌다. 손을 따로 자루에서 떼는 수정이 아니라 두 손, 지팡이, 고정 길이 팔 IK, 팔꿈치와 상체를 함께 조정했다. 일반 대기/달리기/기존 공격 클립은 변경하지 않는다.

## 재생 계약

24fps, 상수 채널 유지, optimizer/compression 비활성. `duration`은 저장된 곡선 길이, `preview_duration`은 검토 화면의 재생 시간이다. **`clip_time = normalized_phase * duration`**으로 샘플한다. 실제 스킬 속도로 자동 채택하지 않는다.

`staff_slide_tracks`는 모든 클립에 적용해야 한다. `grip_spacing_tracks`는 같은 키 인덱스의 보조손 축 방향 위치이며 음수는 오른손 뒤쪽을 뜻한다. 간격 변화는 이미 본 키에 반영되어 있다. 접촉 검사나 향후 IK가 기존 -0.26m 상수를 재사용해서는 안 된다.

진입/복귀 각 25키, 볼트 loop 97키, 지속절단 loop 49키, 그라인더 145키, 회전 베기 97키. 검토 속도는 v30과 동일하다. 여러 캐릭터를 동시에 만드는 리뷰 도구는 AnimationLibrary를 각각 복제한다.

## 원본과 검증 범위

v30과 같은 로컬 원본을 사용한다: Kevin Iglesias `HumanF@AttackPolearm01`, Adobe Mixamo `Great Sword Low Slash`와 `Great Sword High Spin Attack`. 다운로드 원본과 원본 곡선은 기존 gitignored 폴더에 남는다. 지속절단은 직접 만든 동작이다.

최종 수치와 파일 해시는 `reports/drive_attack_v31/delivery_manifest.json`에서 확인한다. `source_validation.json`은 저장/보간 그립과 연속성, `hand_contact_final.json`은 실제 런타임 손 메시와 몸통·골반·두 의상 GLB의 접촉을 기록한다. 64-bit 연결 인덱스를 사용하며 몸통은 삼각형 교차에 더해 손 중심의 ray-parity 포함 검사를 수행한다. 이것은 연속 충돌이나 완전한 폐곡면 판정 인증이 아니다.

몸통 관통과 손목/소매 경계 겹침은 별도로 구분한다. 기존 가드의 소매가 손목을 덮는 부분, 손목을 굽힐 때의 소매 겹침 및 일부 블라우스/케이프 가장자리와 손목 뿌리의 교차는 남아 있다. 이를 삭제하거나 검사에서 숨기지 않았다. 손가락과 자루의 완전한 밀착, 임의 phase의 피격/취소, 헤어/외골격/모든 의상 간 충돌, 최종 성능과 사용자 모션 선택은 후속 범위다.

최종 저장/중간 자세 **968개**에서 양손과 몸통·골반, 양손 서로, 반대쪽 소매의 교차는 0건이다. 그립 기준점 최대 오차 3.498mm, 기존 34메시/107 rest/64액션 보존, 8 GLB 재가져오기 QA 오류 0. 실제 Godot는 272,971 검사를 통과했고 bone-head 차이는 최대 0.003525mm이다. 두 의상 동작 300장과 확대 24장의 실제 GPU 캡처를 검토했다. 전달 전용 12삼각형 carrier의 12개 seam 정점 중복은 유지하며 플레이어에 표시하지 않는다. Blender thumbnail 및 Godot user:// cache/profiler 권한 진단은 로그에 남겼다.

## 재현

### 다른 PC에서 검토·수정

이번 커밋은 **원격 검토용 체크포인트**이며 최종 모션 선택이나 게임 연결 승인이 아니다.

- 저장소를 pull한 뒤 `reports/drive_attack_v31/review.html`을 브라우저에서 연다. MP4 4개와 확대 PNG 24개가 함께 들어 있으므로 Blender/Godot 없이 볼 수 있다. 이전 v30 비교 페이지도 포함한다.
- 직접 고칠 때는 이 폴더의 `drive_attack_v31.blend`를 열고 `PlayerRig_v7`의 `drive_*_v31` 액션을 편집한다. 파일 텍스처 6개는 모두 packed 상태이며, 다운로드 원본 FBX는 이 편집에 필요하지 않다. 새 액션과 계약의 키 수/길이를 바꿨다면 `runtime_contract.json`도 맞춘다.
- 수정한 저장 파일에서 `export_drive_attack_v31.py`로 내보내고 `prepare_drive_attack_v31.py`로 리뷰 프로젝트를 만든다. `run_drive_attack_v31.ps1 -Phase import -GodotPath '설치된 Godot 콘솔 exe 경로'`를 실행한 뒤 validate/capture/details도 같은 엔진으로 실행한다. 기존 로컬 portable engine, PATH의 godot/godot4 또는 `GODOT_BIN`도 지원한다.
- 원본부터 다시 만드는 build는 별도 단계이다. 다운로드 FBX/원본 curve JSON, 임시 프로젝트, Blender 백업과 전체 PNG 프레임은 로컬에 남기며 커밋하지 않는다. 현재 편집 가능한 blend, GLB, 리뷰 영상, 검증 결과와 도구를 사용한다.

### 원본부터 재생성

1. `build_drive_attack_v31.py` — 별도 background Blender, 기존 v30 로컬 source JSON 필요. v30의 midpoint polish를 다시 실행하지 않는다.
2. `finalize_drive_attack_v31.py`, `polish_drive_attack_v31.py`로 이름과 지속절단 연결을 정리한 뒤 `validate_drive_attack_v31.py`, `check_drive_preservation_v31.py`, `drive_hand_contact_v31.py -- --final`.
3. `export_drive_attack_v31.py`, `reimport_drive_attack_v31.py`.
4. `prepare_drive_attack_v31.py` 후 `run_drive_attack_v31.ps1 -Phase import/validate/capture/details`를 순서대로 실행한다.
5. import가 생성한 v31 `.glb.import` 메타데이터를 게임 폴더로 복사한 뒤 `package_drive_attack_v31.py`.

현재 live Blender의 다른 작업 장면은 유지한다. 새 Blender source와 테스트 전용 Godot project만 별도로 연다.
