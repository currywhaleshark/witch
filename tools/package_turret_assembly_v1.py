"""Package actual gameplay captures and validation for the assembly effect."""
from pathlib import Path
import json,hashlib,subprocess,struct,shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/turret_assembly_v1'
BASE=ROOT/'assets/actors/turret_assembly_v1'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def execution_passed(execution):
    return execution['exit_code']==0 and not execution.get('changed_inputs',[]) and (execution['stderr_empty'] or execution['workspace_cache_diagnostic_only'])
capture=read(OUT/'review/capture.json')
checks={}
for phase in ['turret_assembly','automaton_assembly','automaton_spawn_anchor']:
    result=read(OUT/phase/'result.json');execution=read(OUT/phase/'execution.json')
    checks[phase]={'passed':not result['failures'] and execution_passed(execution),
        'checks':result['checks'] if isinstance(result['checks'],int) else len(result['checks']),
        'result':str((OUT/phase/'result.json').relative_to(ROOT)).replace('\\','/'),'execution':execution}
for seq in capture['sequences']:
    images=list((OUT/'review'/seq['id']).glob('*.jpg'))
    assert len(images)==seq['frames'],seq['id']
    if seq['cancel_at_fraction']<0:
        assert max(s['allies'] for s in seq['samples'])==1,seq['id']
        assert all(s['allies']==0 for s in seq['samples'] if s['seconds']<seq['release_seconds']-1e-6),seq['id']
        assert all(s['anchor_drift_m']<1e-5 and s['ally_visual_state']=='idle' for s in seq['samples'] if s['allies']),seq['id']
    else:
        assert all(s['allies']==0 for s in seq['samples']),seq['id']
        assert any(s.get('mode')=='collapse' for s in seq['samples']),seq['id']
checks['gpu_capture']={'passed':capture['passed'] and execution_passed(read(OUT/'review/execution.json')),
    'captures':capture['captures'],'sequences':len(capture['sequences']),'execution':read(OUT/'review/execution.json')}
parts=read(BASE/'parts.json')
for phase in ['turret_assembly','automaton_assembly','automaton_spawn_anchor','review']:
    before=read(OUT/phase/'inputs_before.json');after=read(OUT/phase/'inputs_after.json')
    assert before==after,phase
    assert all(sha(ROOT/path)==digest for path,digest in after.items()),phase
assert sha(ROOT/parts['source'])==parts['source_sha256']
export=BASE/'exports/turret_parts.glb';runtime=ROOT/'game/assets/actors/turret_assembly_v1/turret_parts.glb'
assert sha(export)==sha(runtime)==parts['export_sha256']
data=export.read_bytes();length=struct.unpack_from('<I',data,12)[0];gltf=json.loads(data[20:20+length])
checks['static_parts']={'passed':len(gltf['meshes'])==86 and len(gltf.get('skins',[]))==0 and len(gltf.get('animations',[]))==0,
    'meshes':len(gltf['meshes']),'triangles':parts['triangles'],'materials':len(gltf['materials']),'source_unchanged':True}
files=[BASE/'parts.json',BASE/'authoring/turret_parts.blend',export,runtime,
    ROOT/'game/scripts/summon_assembly.gd',ROOT/'game/scripts/turret_assembly.gd',ROOT/'game/scripts/automaton_assembly.gd',ROOT/'game/scripts/arena.gd',ROOT/'game/data/trial.json',
    ROOT/'game/scripts/player_visual.gd',ROOT/'game/scripts/actor_visual.gd',ROOT/'game/audio/mechanical_impact.wav',
    ROOT/'game/tests/turret_assembly.gd',ROOT/'game/tests/automaton_assembly.gd',ROOT/'game/tests/automaton_spawn_anchor.gd',ROOT/'game/tests/review_turret_assembly.gd']
manifest={'version':'turret_assembly_v1','passed':all(v['passed'] for v in checks.values()),
    'user_art_approved':False,'checks':checks,'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    'files':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(p),'bytes':p.stat().st_size} for p in files],
    'scope':'Turret cast assembly at the captured cursor-ground location. Existing timing/cost/cooldown and accepted v2 summon preserved; automaton assembly now shares the presentation implementation.',
    'placement':{'maximum_drift_m':max(m['maximum_drift_m'] for m in read(OUT/'turret_assembly/result.json')['metrics']['anchors']),
        'physics_rates':[30,60],'fcr_scores':[0,40]},
    'limits':['Fixed-step cosmetic gravity with local floor support, not RigidBody inter-part/wall collision.',
        '86 static part meshes during casting; final performance budget not approved.',
        'Review is silent renderer captures; existing mechanical cue is connected in the game.',
        'Concurrent automaton A/B changes are preserved. This task edits presentation; per-run input hashes identify the combined tested checkout.']}
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
assert manifest['passed'],checks
(OUT/'verified_stills').mkdir(exist_ok=True)
for name,source in [('assembly','success_close/007.jpg'),('complete','success_close/016.jpg'),('collapse','cancel_middle/021.jpg')]:
    shutil.copy2(OUT/'review'/source,OUT/'verified_stills'/f'{name}.jpg')
page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>자동포탑 — 조립과 시전 중단</title>
<style>:root{color-scheme:dark;--bg:#101b20;--panel:#1a2b31;--line:#365059;--teal:#92daca}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#e8efeb;font:16px/1.65 "Malgun Gothic",sans-serif}main{max-width:1180px;margin:auto;padding:36px 26px 65px}h1{font-size:32px;letter-spacing:-1px;line-height:1.3;margin:10px 0 16px}h2{font-size:21px;margin-top:32px}p,small{color:#aec2c3}a{color:var(--teal)}.eyebrow{color:#dcb77d;letter-spacing:2px;font-size:12px}.badge{display:inline-block;border:1px solid var(--line);border-radius:5px;padding:4px 12px;margin-right:8px;color:var(--teal);font-size:13px}.controls{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:15px 0}select,button{background:var(--panel);color:#e8efeb;border:1px solid #4e6871;border-radius:6px;padding:8px 12px;font:inherit}button{cursor:pointer}button:hover{border-color:var(--teal)}input[type=range]{flex:1;min-width:150px;accent-color:var(--teal)}figure{margin:0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--panel)}img{width:100%;display:block}figcaption{padding:11px 16px;color:#b4c9c9}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:15px}.note{border-left:3px solid #cba873;padding:12px 18px;background:var(--panel)}#frame{font-variant-numeric:tabular-nums;color:#b4c9c9;min-width:135px;font-size:14px}details{margin-top:30px;border:1px solid var(--line);padding:16px;border-radius:8px}summary{cursor:pointer;color:var(--teal)}@media(max-width:720px){main{padding:24px 14px}.grid{grid-template-columns:1fr}h1{font-size:27px}select{max-width:100%}}</style>
<main><div class="eyebrow">WITCH / TURRET CAST 01</div><h1>빛 속에서 조립되는 자동포탑</h1><p>지정한 바닥에 받침대가 먼저 자리를 잡고, 회전부·포신·톱니·태엽이 차례로 모입니다. 시전이 끊기면 그때까지 나타난 부품만 그 자리에서 무너집니다.</p><span class="badge">현재 시험판 연결</span><span class="badge">86개 분할 부품</span><span class="badge">성공 · 중도 취소 비교</span>
<div class="controls"><label for="sequence">장면</label><select id="sequence"></select><button id="play">일시정지</button><label for="speed">속도</label><select id="speed"><option value="1">1배</option><option value="0.5">0.5배</option><option value="0.25">0.25배</option></select></div><figure><img id="preview" src="review/success_close/000.jpg" alt="자동포탑 시전 연출"><figcaption id="caption"></figcaption></figure><div class="controls"><input id="scrub" aria-label="동작 시점" type="range" min="0" max="36" value="0"><span id="frame"></span></div>
<p class="note">게임에서는 기본 배치의 <strong>E</strong>로 시험할 수 있습니다. 기본 시전은 0.6초이며 기존 발동 시점인 0.51초에 조립이 끝납니다. 빠른 시전에서도 발동 시점에 맞춰 짧아집니다.</p>
<p class="note">커서로 지정한 자리에 조립하고 완성 뒤에도 그 위치를 유지합니다. 멀리 지정하면 사거리까지 접근한 뒤 조립을 시작합니다.</p><h2>생성 → 조립 → 중단 시 붕괴</h2><div class="grid"><figure><img src="verified_stills/assembly.jpg" alt="빛으로 나타나 조립되는 부품"><figcaption>생성된 부품이 각 자리로 이동</figcaption></figure><figure><img src="verified_stills/complete.jpg" alt="조립을 마친 자동포탑"><figcaption>완성 순간부터 실제 포탑으로 조준·사격</figcaption></figure><figure><img src="verified_stills/collapse.jpg" alt="시전 취소 후 무너지는 부품"><figcaption>경직으로 끊기면 현재 자세에서 낙하</figcaption></figure></div>
<p>작은 피격과 방패 막기는 시전을 유지합니다. 강한 피격 경직·사망·발동 실패 때는 조립을 중단합니다. 취소된 부품은 공격하거나 자폭하지 않습니다.</p>
<details><summary>검증 및 작업 파일</summary><p>실제 게임 시전과 경직을 실행해 7개 장면, 370프레임을 촬영했습니다. 실제 표시 크기와 확대 화면, 기본 속도와 FCR 40을 장면 목록에서 비교할 수 있습니다. 이 페이지는 무음이며 게임에서는 기존 기계음을 조립과 낙하에 사용합니다.</p><p>성공/취소, 마나·쿨다운, 약한 피격·막기·일시정지, 사망·설치 지점 점유·재시작·맵 교체, 재시전을 검사했습니다. 완성된 분리 표면은 기존 포탑 스킨 모델과 CPU 정점 좌표를 대조했습니다. 30/60fps와 FCR 0/40에서 완성 후 위치 이동도 검사했습니다. 기존 태엽인형 조립·중단과 소환 후 위치 검사도 다시 통과했습니다.</p><p>부품 낙하는 바닥 높이를 따르는 표시용 계산입니다. 부품끼리·벽과의 충돌을 해결하는 물리 시뮬레이션은 아닙니다.</p><p><a href="delivery_manifest.json">검증과 파일 해시</a> · <a href="../../assets/actors/turret_assembly_v1/README.md">수정 시작 파일</a></p></details></main>
<script>const sequences=__SEQUENCES__,select=document.querySelector('#sequence'),image=document.querySelector('#preview'),scrub=document.querySelector('#scrub'),button=document.querySelector('#play');let active,clock=0,running=true,last=performance.now(),lastFrame=-1;for(const item of sequences)select.add(new Option(item.label,item.id));select.value='success_close';function show(f){if(lastFrame!==f){image.src='review/'+active.id+'/'+String(f).padStart(3,'0')+'.jpg';lastFrame=f}scrub.value=f;document.querySelector('#frame').textContent=(f/active.fps).toFixed(2)+'초 · '+(f+1)+' / '+active.frames}function choose(){active=sequences.find(s=>s.id===select.value);clock=0;lastFrame=-1;scrub.max=active.frames-1;document.querySelector('#caption').textContent=active.label+(active.cancel_at_fraction<0?' — 기존 발동 시점에 완성':' — 피격 경직으로 시전 중단');show(0);for(let i=0;i<active.frames;i++){const p=new Image;p.src='review/'+active.id+'/'+String(i).padStart(3,'0')+'.jpg'}}select.onchange=choose;button.onclick=()=>{running=!running;button.textContent=running?'일시정지':'재생'};scrub.oninput=()=>{running=false;button.textContent='재생';clock=Number(scrub.value)/active.fps;show(Number(scrub.value))};function tick(now){const dt=Math.min(.15,(now-last)/1000);last=now;if(running){clock=(clock+dt*Number(document.querySelector('#speed').value))%((active.frames-1)/active.fps+.55);show(Math.min(active.frames-1,Math.floor(clock*active.fps)))}requestAnimationFrame(tick)}choose();requestAnimationFrame(tick);</script></html>'''
page=page.replace('__SEQUENCES__',json.dumps([{k:v for k,v in s.items() if k!='samples'} for s in capture['sequences']],ensure_ascii=False))
(OUT/'review.html').write_text(page,encoding='utf-8')
print('TURRET_PACKAGE_COMPLETE',json.dumps({'passed':manifest['passed'],'checks':sum(c.get('checks',0) for c in checks.values()),'captures':capture['captures']}))
