"""Package captured Godot frames and verified runtime evidence for spring dash art."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/spring_dash_v1"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name: str, value):
    (REPORT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    build = read(REPORT / "build.json")
    source = read(REPORT / "source_validation.json")
    scope = read(REPORT / "integration_scope.json")
    assert source["passed"] and scope["passed"]
    assert build["part_count"] == source["saved_meshes"] == 29
    assert build["triangles"] == source["source_and_glb_triangles"] == 5964
    assert sha(ROOT / "assets/props/spring_dash_v1/authoring/spring_plate.blend") == source["blend_sha256"]
    for path in ["assets/props/spring_dash_v1/exports/spring_plate.glb", "game/assets/props/spring_dash_v1/spring_plate.glb"]:
        assert sha(ROOT / path) == source["glb_sha256"]
    assert (ROOT / "assets/props/spring_dash_v1/parts.json").read_bytes() == (ROOT / "game/assets/props/spring_dash_v1/parts.json").read_bytes()

    runs = {}
    total = 0
    for name in ["spring_plate_v1", "loadout_dash", "hit_block", "review"]:
        folder = REPORT / name
        execution = read(folder / "execution.json")
        assert execution["exit_code"] == 0 and not execution["changed_inputs"], (name, execution)
        assert execution["stderr_empty"] or execution["workspace_cache_diagnostic_only"]
        hashes = read(folder / "inputs_after.json")
        assert hashes == read(folder / "inputs_before.json"), name
        mismatches = [p for p, expected in hashes.items() if sha(ROOT / p) != expected]
        assert not mismatches, (name, mismatches)
        runs[name] = {"execution": execution, "inputs_current": True, "inputs": hashes}
        if name != "review":
            result = read(folder / "result.json")
            assert not result["failures"] and result.get("passed", True)
            runs[name]["checks"] = len(result["checks"])
            total += len(result["checks"])

    focused = read(REPORT / "spring_plate_v1/result.json")
    assert focused["runtime_part_triangles"] == 5972
    capture = read(REPORT / "review/capture.json")
    assert capture["passed"] and capture["captures"] == 487
    frames = []
    sequence_meta = []
    for seq in capture["sequences"]:
        assert seq["frames"] == len(seq["samples"])
        for i in range(seq["frames"]):
            path = REPORT / "review" / seq["id"] / f"{i:03}.jpg"
            with Image.open(path) as im:
                assert im.size == (1280, 800)
                im.verify()
            frames.append({"path": path.relative_to(REPORT).as_posix(), "sha256": sha(path)})
        sequence_meta.append({"id": seq["id"], "label": seq["label"], "fps": seq["fps"], "frames": seq["frames"],
                              "modes": [s["plate"]["mode"] for s in seq["samples"]],
                              "paused": [s.get("paused", False) for s in seq["samples"]]})
    assert len(frames) == 487
    save("capture_hashes.json", frames)

    markup = HTML.replace("__SEQUENCES__", json.dumps(sequence_meta, ensure_ascii=False)).replace("__CHECKS__", str(total))
    (REPORT / "review.html").write_text(markup, encoding="utf-8")
    js = re.search(r"<script>(.*?)</script>", markup, re.S).group(1)
    (REPORT / "review_syntax.js").write_text(js, encoding="utf-8")
    subprocess.run(["node", "--check", str(REPORT / "review_syntax.js")], check=True)
    files = [
        "game/scripts/arena.gd", "game/scripts/spring_plate.gd", "game/scripts/spring_plate.gd.uid",
        "game/assets/props/spring_dash_v1/spring_plate.glb", "game/assets/props/spring_dash_v1/spring_plate.glb.import",
        "game/assets/props/spring_dash_v1/parts.json", "game/tests/spring_plate_v1.gd", "game/tests/review_spring_plate_v1.gd",
        "assets/props/spring_dash_v1/authoring/spring_plate.blend", "assets/props/spring_dash_v1/exports/spring_plate.glb",
        "assets/props/spring_dash_v1/parts.json", "assets/props/spring_dash_v1/README.md",
        "tools/build_spring_dash_v1.py", "tools/validate_spring_dash_source_v1.py", "tools/run_spring_dash_v1.ps1",
        "tools/package_spring_dash_v1.py", "reports/spring_dash_v1/review.html", "reports/spring_dash_v1/capture_hashes.json",
    ]
    manifest = {
        "id": "spring_dash_v1", "generated_utc": datetime.now(timezone.utc).isoformat(), "passed": True,
        "status": "Integrated review candidate; no user art selection recorded yet",
        "asset": {"parts": 29, "materials": 6, "source_glb_triangles": 5964, "runtime_part_triangles": 5972,
                  "origin": "Original Blender modeling", "runtime_triangle_difference": "Two procedural coil end caps add eight triangles."},
        "timing_seconds": {"existing_release_fcr_0": .06, "existing_release_fcr_40": focused["cases"][1]["release_seconds"],
                           "extension_after_release": .085, "extended_hold": .055, "dissolve": .24, "total_after_release": .38},
        "validation": {"runtime_assertions": total, "gpu_captures": len(frames), "runs": runs,
                       "wire_radius_max_error_m": focused["wire_radius_max_error_m"],
                       "anchor_max_error_m": focused["anchor_max_error_m"],
                       "minimum_guide_overlap_m": focused["minimum_guide_overlap_m"],
                       "blender_reopen_passed": True, "review_js_syntax_passed": True,
                       "image_size_integrity_passed": True, "browser_interaction_tested": False},
        "integration_scope": scope, "audio": read(REPORT / "audio_validation.json"),
        "capture_scope": capture["scope"],
        "visually_inspected_frames": ["mechanism/035.jpg", "mechanism/062.jpg", "dash/014.jpg", "native/014.jpg", "cancel/012.jpg", "raised/014.jpg"],
        "limits": ["Cosmetic springs and fragments; no physics or collision changes.",
                   "Existing player cast/dash animation is retained; feet are not constrained to the moving deck.",
                   "Flat and raised floor anchors checked; whole-footprint clearance at arbitrary edges is not validated.",
                   "Simple PBR materials; no new worn texture bake or final performance budget.",
                   "The 240Hz mechanism sequence adds inspection lighting. Six arena sequences retain game lighting.",
                   "Review captures are silent; the existing mechanical cue trigger and mute were tested without listening review."],
        "hashes": {p: sha(ROOT / p) for p in files},
    }
    save("delivery_manifest.json", manifest)
    for src in re.findall(r'(?:src|href)="([^"#]+)"', markup):
        if src.startswith(("http:", "https:")):
            continue
        assert (REPORT / src).exists(), src
    print(json.dumps({"passed": True, "runtime_assertions": total, "captures": len(frames), "review": str(REPORT / 'review.html')}, ensure_ascii=False))


HTML = r'''<!doctype html>
<html lang="ko">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>스프링 돌진 · 바닥 발판 v1</title>
<style>
:root{color-scheme:dark;--bg:#101b20;--panel:#17272d;--line:#344a51;--ink:#edf2ee;--muted:#b4c5c6;--gold:#dcc18a;--teal:#81d4c7}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.65 'Segoe UI','Malgun Gothic',sans-serif}main{max-width:1180px;margin:auto;padding:40px 24px 70px}
.eyebrow{color:var(--gold);font-size:12px;letter-spacing:.16em}h1{font-size:clamp(26px,4vw,40px);line-height:1.25;margin:12px 0}p{margin:12px 0}.intro{max-width:880px;color:var(--muted)}
.facts{display:flex;flex-wrap:wrap;gap:12px;margin:22px 0 28px}.facts span{padding:7px 13px;border:1px solid var(--line);border-radius:6px;font-size:14px}.facts b{color:var(--teal)}
.viewer{border:1px solid var(--line);border-radius:12px;overflow:hidden;background:var(--panel)}.toolbar{display:flex;flex-wrap:wrap;gap:12px;align-items:center;padding:16px}label{font-size:13px;color:var(--muted)}select,button{background:#24373e;color:var(--ink);border:1px solid #52676d;border-radius:5px;padding:9px 11px;font:inherit;cursor:pointer}select{max-width:100%}button:hover{border-color:var(--teal)}button:focus-visible,select:focus-visible,input:focus-visible{outline:2px solid var(--teal);outline-offset:3px}
.screen{position:relative;background:#0b1317}.screen img{width:100%;display:block;aspect-ratio:8/5;object-fit:contain}.badge{position:absolute;left:14px;top:14px;padding:4px 9px;background:#10252de8;border-radius:4px;font-size:13px;color:#d9eee6}.timeline{padding:12px 16px 18px}.timeline input{width:100%;accent-color:var(--teal);cursor:pointer}.time{display:flex;justify-content:space-between;color:var(--muted);font-size:13px}.note{font-size:14px;color:var(--muted);margin:16px 0 28px}
.stages{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.stage{background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden;text-align:left;padding:0}.stage img{display:block;width:100%;aspect-ratio:8/5}.stage span{display:block;padding:12px 14px}.stage strong{display:block;color:var(--gold);font-size:15px}.stage small{color:var(--muted)}details{margin-top:28px;padding:15px 18px;border:1px solid var(--line);border-radius:8px;color:var(--muted);font-size:14px}summary{cursor:pointer;color:var(--ink)}a{color:var(--teal)}footer{margin-top:22px;color:var(--muted);font-size:13px} @media(max-width:700px){main{padding:25px 14px}.stages{grid-template-columns:1fr}.toolbar{gap:8px;padding:12px}.toolbar label:first-child{width:100%}}
</style></head><body><main>
<div class="eyebrow">WITCH / SKILL ART / 2026.10.30</div>
<h1>스프링 돌진 · 바닥 발판</h1>
<p class="intro">발밑으로 부품이 모여 스프링판을 만들고, 돌진이 시작되는 순간 발판이 튀어 오릅니다. 장치는 출발 지점에 남았다가 빛과 함께 사라집니다.</p>
<div class="facts"><span>기본 발동 <b>0.06초 유지</b></span><span>작동 후 <b>0.38초에 소멸</b></span><span><b>29개</b> 독립 부품</span><span>발동 전 경직 시 <b>조립 취소</b></span></div>
<section class="viewer" aria-label="게임 연출 재생">
<div class="toolbar"><label>장면 <select id="scene" aria-label="장면 선택"></select></label><label>속도 <select id="speed" aria-label="재생 속도"><option value="1">실제 속도</option><option value="0.5">0.5배</option><option value="0.25">0.25배</option><option value="0.1">0.1배</option></select></label><button id="play">일시정지</button><button id="restart">처음부터</button></div>
<div class="screen"><img id="frame" src="review/dash/000.jpg" alt="스프링 돌진 실제 게임 화면"><span class="badge" id="stage">대기</span></div>
<div class="timeline"><input id="scrub" type="range" min="0" max="60" value="0" step="1" aria-label="프레임 이동"><div class="time"><span id="time">0.000초</span><span id="count">1 / 61</span></div></div>
</section>
<p class="note" id="caption">현재 게임의 돌진을 확대해서 촬영했습니다. 빠른 조립은 0.25배 재생으로 확인할 수 있습니다.</p>
<div class="stages">
<button class="stage" data-keyframe="8"><img src="review/mechanism/008.jpg" alt="바닥판과 스프링이 조립되는 모습"><span><strong>01 · 빠르게 조립</strong><small>바닥판 → 코일과 가이드 → 발판</small></span></button>
<button class="stage" data-keyframe="35"><img src="review/mechanism/035.jpg" alt="스프링이 펴져 발판이 올라간 모습"><span><strong>02 · 압축 해제</strong><small>코일과 가이드가 늘어나며 전방으로 기울어짐</small></span></button>
<button class="stage" data-keyframe="75"><img src="review/mechanism/075.jpg" alt="작동을 마친 부품들이 사라지는 모습"><span><strong>03 · 출발 지점에서 소멸</strong><small>부품이 살짝 벌어지고 빛과 함께 사라짐</small></span></button>
</div>
<details><summary>연결과 확인 범위</summary>
<p>게임에 연결된 시안입니다. S 스킬창에서 스프링 돌진을 슬롯에 넣어 사용합니다. 비교 화면은 Q에 배치했습니다. 기존 마나·재사용 대기·돌진 거리·충돌과 캐릭터 모션은 유지합니다.</p>
<p>신규 및 기존 회귀 __CHECKS__개 검사와 487장 게임 렌더를 기록했습니다. 정지·재개, 경직/마나 부족/슬롯 변경/사망에 의한 취소, 초기화·맵 이동, 높은 바닥과 연속 장치 제거를 확인했습니다.</p>
<p>기구 확대만 별도 조명과 240Hz 샘플을 사용합니다. 나머지는 기존 게임 조명과 60Hz 시뮬레이션입니다. 캡처 재생은 무음이며, 게임에서는 기존 기계 타격음을 사용합니다. 코일과 파편은 시각 연출로, 실제 발판 충돌이나 발 접촉을 시뮬레이션하지 않습니다.</p>
<p><a href="delivery_manifest.json">검증 및 해시</a> · <a href="../../assets/props/spring_dash_v1/README.md">제작 파일과 인계</a></p>
</details>
<footer>Blender 제작 원본과 게임용 GLB를 함께 보관했습니다. 외형은 이번 검토를 위한 첫 시안입니다.</footer>
</main><script>
const sequences = __SEQUENCES__;
const byId = Object.fromEntries(sequences.map(s=>[s.id,s]));
const scene = document.getElementById('scene'), speed = document.getElementById('speed');
const frame = document.getElementById('frame'), scrub = document.getElementById('scrub');
const play = document.getElementById('play'), time = document.getElementById('time'), count = document.getElementById('count');
const stage = document.getElementById('stage'), caption = document.getElementById('caption');
const captions = {dash:'현재 게임의 돌진을 확대해서 촬영했습니다. 빠른 조립은 0.25배 재생으로 확인할 수 있습니다.',native:'선택된 1.75배 게임 카메라의 실제 표시 크기입니다.',mechanism:'기구 확대: 별도 조명, 240Hz 세부 샘플. 눌린 코일이 펴지며 발판과 가이드가 함께 움직입니다.',fast:'시전 속도 40: 기존 약 0.038초 발동에 맞춰 조립만 더 빠르게 진행합니다.',cancel:'발동 전 큰 피격으로 취소: 현재 나타난 부품만 사라지며 스프링은 작동하지 않습니다.',pause:'작동 중 일시정지하면 부품과 소멸도 멈춥니다. 재개하면 같은 시점부터 이어집니다.',raised:'골목의 1.2m 높은 바닥에서 실제 지면 높이에 맞춰 생성합니다.'};
['dash','native','mechanism','fast','cancel','pause','raised'].forEach(id=>{const o=document.createElement('option');o.value=id;o.textContent=byId[id].label;scene.append(o)});
let current=byId.dash, pos=0, playing=true, last=performance.now(), shown=-1, endWait=0;
const modes={assembling:'부품 조립',launched:'작동 · 소멸',cancelled:'조립 취소',gone:'대기 / 소멸 완료'};
const nextImages=[new Image(),new Image(),new Image()];
function render(){
  const i=Math.min(current.frames-1,Math.max(0,Math.floor(pos)));
  if(i!==shown){frame.src=`review/${current.id}/${String(i).padStart(3,'0')}.jpg`;shown=i;
    nextImages.forEach((im,n)=>{const ahead=Math.min(current.frames-1,i+n+1);im.src=`review/${current.id}/${String(ahead).padStart(3,'0')}.jpg`})}
  scrub.value=i;time.textContent=(i/current.fps).toFixed(3)+'초';count.textContent=`${i+1} / ${current.frames}`;
  stage.textContent=current.paused[i]?'게임 일시정지':(modes[current.modes[i]]||current.modes[i]);
  play.textContent=playing?'일시정지':'재생';
}
function selectScene(id){current=byId[id];scene.value=id;pos=0;endWait=0;shown=-1;last=performance.now();scrub.max=current.frames-1;caption.textContent=captions[id];frame.alt=current.label;render()}
scene.addEventListener('change',()=>selectScene(scene.value));
speed.addEventListener('change',()=>{last=performance.now();endWait=0});
play.addEventListener('click',()=>{playing=!playing;last=performance.now();render()});
document.getElementById('restart').addEventListener('click',()=>{pos=0;endWait=0;playing=true;last=performance.now();render()});
scrub.addEventListener('input',()=>{playing=false;pos=Number(scrub.value);endWait=0;render()});
document.querySelectorAll('[data-keyframe]').forEach(button=>button.addEventListener('click',()=>{selectScene('mechanism');playing=false;pos=Number(button.dataset.keyframe);render();document.querySelector('.viewer').scrollIntoView({behavior:'smooth',block:'start'})}));
document.addEventListener('visibilitychange',()=>{last=performance.now()});
function tick(now){const dt=Math.min(.1,(now-last)/1000);last=now;
  if(playing&&!document.hidden){if(pos>=current.frames-1){endWait+=dt;if(endWait>.65){pos=0;endWait=0}}else{pos=Math.min(current.frames-1,pos+dt*current.fps*Number(speed.value))}render()}
  requestAnimationFrame(tick)
}
selectScene('dash');requestAnimationFrame(tick);
</script></body></html>'''


if __name__ == "__main__":
    main()
