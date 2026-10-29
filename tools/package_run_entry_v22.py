"""Package the measured idle/run fix and actual arena captures; no asset reauthoring."""
from pathlib import Path
import hashlib
import json
import math
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'reports/run_entry_v22'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

tests = {}
for name in ['run_entry_v22', 'player_visual', 'player_motion_v18', 'bolt_cutter_v2']:
    result = read(REPORT / name / 'result.json')
    execution = read(REPORT / name / 'execution.json')
    assert result['passed'] and not result['failures']
    assert execution['exit_code'] == 0 and not execution['changed_inputs']
    assert execution['stderr_empty']
    tests[name] = {'checks': len(result['checks']), 'passed': True}
for name in [*tests, 'review']:
    recorded = read(REPORT / name / 'inputs_after.json')
    assert all(digest(ROOT / path) == expected for path, expected in recorded.items()), name
captures = read(REPORT / 'review/capture.json')
execution = read(REPORT / 'review/execution.json')
assert execution['exit_code'] == 0 and not execution['changed_inputs']
assert execution['stderr_empty'] or execution['workspace_cache_diagnostic_only']
assert captures['captures'] == 455
for seq in captures['sequences']:
    for frame in range(seq['frames']):
        assert (REPORT / f'review/{seq["id"]}/{frame:03d}.jpg').is_file()
comparison = {}
for view in ['front', 'quarter']:
    a, b = [next(s for s in captures['sequences'] if s['id'] == view + '_' + version) for version in ['before', 'after']]
    assert all(x[k] == y[k] for x, y in zip(a['samples'], b['samples']) for k in ['weight', 'phase', 'player_position', 'paused', 'yaw', 'turn_lag'])
    comparison[view] = {version: [min(r['tip'][0] for r in seq['samples'][12:24]), max(r['tip'][0] for r in seq['samples'][12:24])] for version, seq in zip(['before_x_range_m', 'after_x_range_m'], [a,b])}
runtime = ['game/scripts/player_visual.gd', 'game/scripts/staff_locomotion_blend.gd', 'game/scripts/staff_visual.gd', 'game/tests/run_entry_v22.gd', 'game/tests/probe_run_entry_v22.gd', 'game/tests/review_run_entry_v22.gd', 'tools/run_run_entry_v22.ps1', 'reports/run_entry_v22/player_visual_before.gd']
assets = list((ROOT/'game/assets/characters/player/run_arm_v21').glob('*.glb')) + list((ROOT/'game/assets/weapons/staff_material_v3').glob('*'))
manifest = {
    'date': '2026-10-30', 'passed': True, 'prior_staff_commit': 'a8b8cfb',
    'tests': tests, 'checks': sum(x['checks'] for x in tests.values()), 'captures': captures['captures'],
    'transition_metrics': read(REPORT/'run_entry_v22/result.json')['metrics'],
    'actual_arena_comparison': comparison,
    'matching_gameplay_inputs_and_positions': True,
    'runtime_sha256': {p: digest(ROOT/p) for p in runtime},
    'asset_sha256': {p.relative_to(ROOT).as_posix(): digest(p) for p in assets if p.is_file()},
    'method': 'One skeleton-space staff frame and both hand targets; two-bone arm reach with blended elbow poles and rigid-length twist segments, only during partial idle/run blending.',
    'preserved': 'All 7 authored clips/GLBs, 93 other local bone channels, steady run, lower-body/cloth, movement/turn/phase clocks, combat rules and material v3.',
    'limits': 'Current civilian game and the sampled phase grid. Not a new transformed-outfit inspection, arbitrary-pose garment clearance or a performance budget. The sole GPU stderr is the known workspace shader-cache diagnostic.',
}
(REPORT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

html = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>지팡이 이동 전환 수정 · v22</title>
<style>
:root{color-scheme:dark;font-family:"Segoe UI","Malgun Gothic",sans-serif;background:#111c23;color:#dfe8e8}*{box-sizing:border-box}body{max-width:1480px;margin:0 auto;padding:28px}h1{font-size:27px;line-height:1.4;margin:6px 0 12px}p{line-height:1.75;color:#b9cacc;margin:8px 0}small,.muted{color:#8ea7ac}.badge{color:#e6bd79;font-size:12px;letter-spacing:.12em}.controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:23px 0 14px}button,select{font:inherit;background:#23333c;border:1px solid #45606b;color:#e8f3f3;border-radius:5px;padding:9px 12px;cursor:pointer}button:hover{background:#304853}button.primary{background:#b99557;color:#142029;border:0;font-weight:600}.pair{display:grid;grid-template-columns:1fr 1fr;gap:14px}.pair.native{grid-template-columns:1fr}figure{margin:0;background:#0b161c;border:1px solid #31454f;border-radius:7px;overflow:hidden}figure[hidden]{display:none}figcaption{padding:11px 16px;font-size:14px}.new figcaption{color:#93ddd0}img{display:block;width:100%;height:auto}input[type=range]{width:100%;accent-color:#e6bd79}.timeline{margin:14px 0 8px}.ticks{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}.ticks button{font-size:12px;padding:6px 9px}.status{min-height:26px;font-variant-numeric:tabular-nums}.notes{border-top:1px solid #31454f;margin-top:25px;padding-top:14px}a{color:#91d5cf}details{margin-top:16px;color:#b9cacc}summary{cursor:pointer}code{font-size:.9em}@media(max-width:800px){body{padding:16px}.pair{grid-template-columns:1fr}h1{font-size:23px}}
</style>
<div class="badge">WITCH · MOTION REVIEW 22</div><h1>이동을 시작할 때 지팡이가 반대로 도는 현상 수정</h1>
<p>팔의 비틀림이 다른 대기·달리기 자세를 뼈별로 섞으면서, 중간에 지팡이가 크게 한 바퀴 돌았습니다.<br>전환 중에는 지팡이 방향과 양손의 위치를 함께 연결합니다. 기존 대기와 달리기 동작은 그대로입니다.</p>
<div class="controls"><label>시점 <select id="view"><option value="quarter">비스듬히 · 볼트커터</option><option value="front">정면 · 기본 지팡이</option><option value="native">실제 게임 크기 · 수정 후</option></select></label><label>속도 <select id="speed"><option value=".25">0.25배</option><option value=".5" selected>0.5배</option><option value="1">1배</option></select></label><button class="primary" id="restart">처음부터 재생</button><button id="play">재생</button><button id="back">이전 프레임</button><button id="next">다음 프레임</button></div>
<div class="pair" id="pair"><figure id="old"><figcaption>수정 전 · 기존 자세 혼합</figcaption><img id="before" alt="수정 전 실제 게임 프레임" src="review/quarter_before/017.jpg"></figure><figure class="new"><figcaption>수정 후 · 양손과 지팡이 방향을 함께 연결</figcaption><img id="after" alt="수정 후 실제 게임 프레임" src="review/quarter_after/017.jpg"></figure></div>
<div class="timeline"><input id="scrub" type="range" min="0" max="90" value="17" step="1" aria-label="프레임 이동"><p class="status" id="status" aria-live="polite">비교 장면 불러오는 중…</p><div class="ticks"><button data-frame="0">대기</button><button data-frame="12">이동 시작</button><button data-frame="17">전환 중간</button><button data-frame="33">정지</button><button data-frame="44">짧게 재출발</button><button data-frame="62">재출발 / 방향 전환</button><button data-frame="78">일시정지</button><button data-frame="84">재개</button></div></div>
<div class="notes"><p><strong>확인한 내용</strong> · 1,514개 전환 샘플에서 손 간격 오차 최대 0.052mm. 팔 길이와 하체·의상 동작 유지.<br>신규 검사와 기존 공격·캐스팅·경직·쓰러짐·볼트커터 회귀 <strong>1,271개</strong> 통과, 실제 엔진 <strong>455장</strong> 캡처.</p><p>기본 지팡이·공구·재질은 <code>a8b8cfb</code>로 커밋했습니다. 이 이동 전환 수정은 사용자가 선택한 시험판 수정본입니다.</p><details><summary>검증 범위와 기록</summary><p>두 버전은 실제 게임에서 같은 이동 입력과 위치·방향·재생 시계를 사용했습니다. 정면과 비스듬한 시점은 확대 비교, 실제 크기는 기존 1.75배 카메라입니다. 기존 게임 조명을 사용합니다. 비교 재생은 마지막 프레임에서 멈춥니다.</p><p>변신복을 새로 촬영한 검사, 모든 의상 접촉 해결, 최종 성능 검증은 포함하지 않습니다. <a href="delivery_manifest.json">검증 매니페스트</a> · <a href="run_entry_v22/result.json">전환 검사</a> · <a href="review/capture.json">실제 게임 프레임 기록</a></p></details></div>
<script>
const $=id=>document.getElementById(id),cache=new Map();let frame=17,playing=false,ready=false,last=0,token=0;
function path(view,version,i){return `review/${view}_${version}/${String(i).padStart(3,'0')}.jpg`}
function eventAt(i){if(i>=84)return '일시정지 후 재개';if(i>=78)return '일시정지';if(i>=62)return '재출발 / 비스듬한 시점은 방향 전환';if(i>=47)return '짧은 이동 후 정지';if(i>=44)return '짧게 재출발';if(i>=33)return '정지로 전환';if(i>=12)return '이동 시작';return '대기'}
function draw(){const v=$('view').value,i=Math.min(90,Math.max(0,Math.round(frame))),native=v==='native';$('pair').classList.toggle('native',native);$('old').hidden=native;if(!native)$('before').src=path(v,'before',i);$('after').src=path(v,'after',i);$('scrub').value=i;$('play').textContent=playing?'일시정지':'재생';if(ready)$('status').textContent=`${i} / 90 F · ${(i/60).toFixed(2)}초 · ${eventAt(i)}${i===90?' · 재생 완료':''}`}
async function loadView(){ready=false;playing=false;const id=++token,v=$('view').value;$('status').textContent='비교 장면 불러오는 중…';draw();try{await Promise.all((v==='native'?['after']:['before','after']).flatMap(ver=>Array.from({length:91},(_,i)=>{const p=path(v,ver,i);if(cache.has(p))return cache.get(p);const task=new Promise((resolve,reject)=>{const img=new Image();img.onload=()=>resolve(img);img.onerror=()=>reject(new Error(p));img.src=p});cache.set(p,task);return task})));if(id===token){ready=true;last=0;draw()}}catch(e){$('status').textContent='프레임을 불러오지 못했습니다: '+e.message}}
function jump(i){playing=false;frame=i;draw()}
$('view').onchange=loadView;$('play').onclick=()=>{if(!ready)return;if(frame>=90)frame=0;playing=!playing;last=0;draw()};$('restart').onclick=()=>{if(!ready)return;frame=0;playing=true;last=0;draw()};$('back').onclick=()=>jump(Math.max(0,Math.round(frame)-1));$('next').onclick=()=>jump(Math.min(90,Math.round(frame)+1));$('scrub').oninput=()=>jump(Number($('scrub').value));document.querySelectorAll('[data-frame]').forEach(b=>b.onclick=()=>jump(Number(b.dataset.frame)));
function tick(now){if(last&&playing&&ready){frame+=Math.min(.1,(now-last)/1000)*60*Number($('speed').value);if(frame>=90){frame=90;playing=false}draw()}last=now;requestAnimationFrame(tick)}loadView();requestAnimationFrame(tick);
</script></html>'''
(REPORT/'review.html').write_text(html,encoding='utf-8')
javascript = re.search(r'<script>(.*?)</script>',html,re.S).group(1)
(REPORT/'review_syntax.js').write_text(javascript,encoding='utf-8')
subprocess.run(['node','--check',str(REPORT/'review_syntax.js')],check=True)
inspected = ['front_before/017.jpg','front_after/017.jpg','quarter_after/018.jpg','quarter_after/037.jpg','quarter_after/048.jpg','native_after/017.jpg']
qa = {'passed':True,'captures':455,'checks':manifest['checks'],'javascript_syntax':'node --check passed','browser_interaction_tested':False,'manual_images_inspected':{p:digest(REPORT/'review'/p) for p in inspected}}
(REPORT/'qa.json').write_text(json.dumps(qa,indent=2)+'\n',encoding='utf-8')
print('RUN_ENTRY_PACKAGE_COMPLETE',manifest['checks'],'checks',manifest['captures'],'captures')
