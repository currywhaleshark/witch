# 언덕길 골목 장식 v1

2026-10-28 사용자의 「그대로 시행」 요청에 따라 GENERATION_SPEC 1–8장과 진행 중 추가된 13–15장을 적용했다. **69종 원본, 게임용 PNG 80개(흑백 마스크의 RGBA 파생본 11개 포함)**를 제공한다. 게임용 PNG는 합계 13.38 MiB다.

- [적용 전후와 전체 이미지 검토](../../../reports/alley_decals_v1/review.html)
- [생성·가공·이용 조건·해시 기록](provenance.json)
- [저장 파일 검증](../../../reports/alley_decals_v1/validation.json)
- [GPU 통합 검사](../../../reports/alley_decals_v1/review/result.json), [기존 맵 검사](../../../reports/alley_decals_v1/map_nav/result.json)

## 보관과 재현

`source/`는 고른 생성 원본 그대로다. `raw/`에는 탈락 후보를 포함한 75개 PNG가 남아 있다. `generation/selection.json`은 선택한 후보, 장별 receipt JSON은 실제 사용한 프롬프트와 참조 이미지 기록이다. `requests.json`은 최초 제작 지시이며 후속 수정의 실제 지시는 receipt를 우선한다. 도구는 내장 `image_gen.imagegen`; 모델 버전과 시드는 도구가 공개하지 않아 추측해 넣지 않았다. 사진 참조를 생성기에 넣지 않았다.

`python tools/package_alley_decals_v1.py`가 원본을 보존하면서 판 자르기, 마젠타 제거/가장자리 보정, 희미한 알파 잔여물 제거, 빈 캔버스 자르기, 지정 크기 축소, RGB 20–235 정리, 마스크/반복 경계와 깨진 유리 투명도를 처리한다. 글자는 수동으로 덧그리지 않았고, 잘못된 글자/구두점은 ImageGen으로 수정했다. 패키징 후에는 검증 상태가 다시 pending이 되며 아래 검사를 실행해야 한다.

```powershell
python tools/package_alley_decals_v1.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_alley_decals_v1.ps1 -Phase import
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_alley_decals_v1.ps1 -Phase map_nav
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_alley_decals_v1.ps1 -Phase review
python tools/finalize_alley_decals_v1.py
```

## 실제 적용 범위

장식 배치는 `game/data/maps/alley_decals_v1.json`, 구현은 `game/scripts/alley_decoration.gd`이다. 기본 맵의 치수·충돌·적 스폰은 그대로 두고 `field_map.gd`에서 호출한다. 가로 간판은 생성 이미지의 중앙 70%를 일정 폭으로 유지하고 양 끝만 가게 폭에 맞춘다. 기존 맵에서 실제 간판이 있는 네 가게는 세탁소·슈퍼·철물점·폐문방구다. 다른 여섯 가로 간판은 재사용용으로 보관한다. 돌출 간판은 상층/인접 업종 장식으로 별도 지정했다.

**2026-10-28 사용자 수정 반영(개발 쪽):**
- **간판:** 한 건물에 업종이 다른 간판이 달리지 않게 했다.
  - 가게의 돌출 간판·입간판은 그 가게의 업종을 따른다(복덕방→`sign_v_realty`·`aframe_realty`, 약국→`sign_v_pharmacy`, 분식→`aframe_snack`). 입간판은 영업 중인 가게에만 선다.
  - 집은 레이아웃의 `home_signs`에 적은 철학관·여인숙만 단다.
  - 이를 위해 `alley_v2.json`에서 집 세 필지를 복덕방·약국·분식으로 바꿨다. 그래서 실제 간판이 있는 가게는 일곱 곳이다.
  - `sign_v_gukbap`과 `sign_v_sundries`는 맞는 가게가 없어 지금은 쓰지 않는다.
- **벽면 설비:** 스티커처럼 보이던 `wall_gas_pipe`·`wall_cables` 평면을 걷어 냈다. 대신 창 없는 건물 모서리에 노란 가스관(층마다 가지관)·가스 계량기·전기 계량기 함(`box_meter` 텍스처를 앞면에 씀)·인입선을 모형으로 붙였고, 인입선은 가장 가까운 전봇대에서 내려온다.
- **전봇대:** 담장 안쪽에서 골목 쪽으로 옮겼다. 전봇대 광고 띠와 번호판도 같이 옮겼다.

별도 필지 시드로 현재 영업/거주 11필지, 폐업 15필지, 빈집 12필지를 나눈다. 이것은 외형 분류이며 NPC·상점 기능이 아니다. 폐업/빈집의 조명을 끄고 시트지·막음판을 붙인다. 현수막은 먼 쪽 가장자리에만 배치하며 잘린 필지에서는 높이를 낮춘다. A자 다리, 간판 브래킷, 처진 전선, 기존 소품 충돌 범위 안의 상자·마대·폐목재 조각을 추가했다. 장식은 부모 필지와 함께 투명해진다. 침식의 임시 단색 사각형 표시는 새 장식으로 대체했다. 바닥 톱니는 완전한 원본 이미지와 덮개를 분리했으며 현재는 정지 상태다.

## 검증과 한계

Godot 4.6.2 Compatibility/RTX 2060 실제 GPU 검사 1171개, 기존 맵 검사 43개, 1280×800 캡처 15장이 통과했다. 충돌체 전체·네비메시 꼭짓점·필지 배치·전투 RNG 보존, 모든 텍스처 밉맵, 필지 알파 복귀, 평지 전환과 재로드를 검사했다. GPU stderr에는 이 환경의 `user://` 셰이더 캐시 폴더 진단이 있으며 로그를 보존했다. 렌더 오류와 테스트 실패는 없다. 전투 규칙 전체 스위트를 반복 실행한 것은 아니며 최종 아트/플레이 감각/성능 예산 승인을 뜻하지 않는다.

간판 15종은 생성된 판의 긴 변이 요청한 2048px보다 작다. 원본은 바꾸지 않았고, 판을 잘라 지정된 게임용 크기로 리샘플했다. 실제 픽셀 수는 provenance/validation에 기록했다. 원본 해상도 조건까지 충족했다고 취급하지 않는다.

이용 조건은 [OpenAI Terms of Use — Content/Ownership](https://openai.com/policies/terms-of-use/) 기준으로 기록했다. 상업용 게임과 저장소 보관용 생성 결과이며 CC0로 표시하지 않는다. 별도 CC0 반복 표면 재질의 출처는 기존 `alley_v1/README.md`에 유지된다.
