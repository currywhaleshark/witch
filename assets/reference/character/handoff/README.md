# 마녀도시 — 캐릭터 아트 / Codex 인계 자산

이 패키지는 이미지와 시안 샘플을 **코덱스가 작업할 로컬 저장소에 복사하기 위한** 자산 묶음이다.

## 시작

1. `currywhaleshark/witch`를 로컬에 체크아웃한다.
2. 이 ZIP의 `assets/` 디렉터리를 저장소 루트 `assets/`에 복사한다. `experiments/`는 필요할 때만 보관한다.
3. GitHub [`docs/09_character_art_pipeline.md`](https://github.com/currywhaleshark/witch/blob/main/docs/09_character_art_pipeline.md)부터 읽는다.
4. `assets/reference/character/scg`는 원화/실험 참조이고 `assets/characters/player/scg/layers`는 **아직 제작되지 않은** 실제 레이어 자리다.
5. 첫 구현은 이 시안의 리소스를 조립하는 구조/검증부터. 전투 필드 MVP에 SCG·커스터마이징을 끼워 넣지 않는다.

## 이미지 참고

- `assets/reference/character/scg/semilong_reference.png` — 세미롱 기준 원화
- `assets/reference/character/scg/twintails_reference.png` — 트윈테일 변화 참조
- `assets/reference/character/scg/hair_swap_comparison.png` — 실패/한계가 나타나는 델타 합성 실험
- `assets/reference/character/scg/dialogue_ui_reference.png` — 비주얼 노벨풍 대화 SCG 구도

## 현재 상태와 하지 않은 일

- RGB 완성 원화 2장이 있고, 머리/눈/옷 색상 마스크 실험과 헤어 교체 델타 패치 실험이 있다.
- **공통 헤어리스 base_body·독립 교체형 머리 PNG·라이브2D용 PSD·Tripo 3D 모델·의상 리깅 파일은 아직 없다.**
- 데모 HTML의 겉보기 전환을 **정식 파츠 교체 성공**으로 오해하지 않는다.
- 상세 사양 및 Codex 작업 항목은 GitHub 문서가 단일 원본이다.
