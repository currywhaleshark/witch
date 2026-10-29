# 태엽인형 공격 위치·모션 v1 (2026-10-29)

사용자 요청: 태엽인형이 적에게서 너무 멀리 떨어져 공격하고 모션이 심심하다.

## 바뀐 것

- **공격 위치(규칙):** 이동형 소환체가 멈추는 거리를 적 중심에서 고정 1.6m 대신
  `0.45 + 0.5 × 적 크기`로 바꿨다(`arena.gd` `automaton_reach`). 넝마귀 0.81m, 까마귀 0.875m,
  철문 아귀 1.1m. 공격 가능 거리는 멈춤 거리 + 0.2m(기존 고정 1.8m). 보스는 몸체가 문틀이라 1.6m를 유지한다.
  A 노드의 접근 자폭 거리(1.8m)와 피해·쿨다운·명중 규칙은 그대로다.
- **모션(표현 전용, `actor_visual.gd`):** 공격 클립 위에 절차적 층을 얹었다. 쿨다운 마지막 0.3초 동안 태엽 열쇠를
  빠르게 감으며 몸을 젖히고 팔을 뒤로 당긴 뒤, 판정 순간 0.2m 앞으로 뛰어들며 팔을 곧게 내지른다.
  기본형은 좌우 팔을 번갈아 쓰고, B 노드는 톱 팔로 크게 휘둘러 벤다. 판정 시점(클립 0.5)은 그대로이며
  게임플레이 노드는 움직이지 않는다(돌진은 시각 노드 오프셋).
- **태엽 열쇠:** 평소에는 천천히, 감을 때는 빠르게 축을 따라 돈다. 회전축은 칼라 중심 → 손잡이 중심을 잇는
  약 22° 기운 실제 축이다. 기존 v2 클립은 `key` 뼈를 축에서 벗어난 원점으로 앞뒤축 ±12° 흔들어
  와이퍼처럼 보였으므로, 이 층이 적용되는 클립에서는 `key` 뼈를 휴지 자세로 고정한다(사망·자폭 클립은 원본 그대로).
- **열쇠 옆 손잡이 분리:** 분할 원본에서 열쇠 부품(`part_006`)에 바로 아래 작은 뒤쪽 손잡이가 붙어 있어,
  런타임에 그 삼각형만 몸통 껍데기(`part_000`)에 다시 연결한다. GLB 원본 파일은 바꾸지 않았다.
- **이펙트:** 기본형의 청록 탄환 사격 이펙트를 주먹 위치의 피스톤 펀치(섬광·전방 불꽃·뒤로 빠지는 증기)로 바꿨다.
  포탑 사격과 B 톱 불꽃은 그대로다.

## 확인

- `review/strike_*_sheet.png`: 실제 아레나 코드로 넝마귀·까마귀·철문 아귀 상대 기본형과 B 노드를 2틱 간격 근접 촬영,
  각 `_native.png`는 게임 배율. `captures_strike.json`에 최종 중심 거리와 멈춤 거리를 기록했다.
  재촬영: `review_combat_vfx.gd -- --output=... --only=strike`.
- `review/key_spin_axis.png`: 축에 수직인 두 방향과 축 방향에서 본 열쇠 회전(대기 클립 위상 변화 포함).
  `review/key_knob_closeup.png`: 손잡이 분리 근접 확인.
- 회귀 27종(smoke_arena, boss, boss_art, enemy_types, hit_block, grades_hits, bleed, tool_switch, shotgun_cast,
  potions, approach_cast, hold_input, automaton_assembly, automaton_node, automaton_variants, automaton_variant_a/b,
  automaton_spawn_anchor, turret_assembly, map_nav, mana_a5, replay_rules, combat_actors, summons_v2, player_visual,
  player_motion_v18, automaton_node_art_regression) 모두 exit 0, 실패 0, 스크립트 오류 0.

## 남은 한계

- 매우 근접(약 10배)에서 칼라 아래 손잡이 경계에 1~2mm 조각이 열쇠와 함께 돈다. 게임 배율에서는 1픽셀 미만.
- 화면 확인은 밝은 평지 시험장에서만 했다. 표적이 움직이는 중에는 감기 동작 없이 바로 내지를 수 있다.
- 소환체끼리·적 몸체와의 실제 충돌은 여전히 없다. 플레이 감각·최종 밸런스 승인은 아니다.
