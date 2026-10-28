"""Verify the recorded checkout and package the floating scatter-cannon review."""
from pathlib import Path
import hashlib, json, struct, shutil, subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/shotgun_cast_v1'
BASE=ROOT/'assets/actors/shotgun_cast_v1'
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def execution_ok(execution):
    return execution['exit_code']==0 and not execution['changed_inputs'] and (execution['stderr_empty'] or execution['workspace_cache_diagnostic_only'])

checks={}
phases=['shotgun_cast','hit_block','hold_input','grades_hits','approach_cast','tool_switch']
for phase in phases:
    result=read(OUT/phase/'result.json');execution=read(OUT/phase/'execution.json')
    checks[phase]={'passed':not result['failures'] and execution_ok(execution),
                   'assertions':result['checks'] if isinstance(result['checks'],int) else len(result['checks']),
                   'result':f'{phase}/result.json','execution':execution}
for phase in phases+['review']:
    before=read(OUT/phase/'inputs_before.json');after=read(OUT/phase/'inputs_after.json')
    assert before==after,phase
    assert all(sha(ROOT/path)==value for path,value in after.items()),phase
capture=read(OUT/'review/capture.json')
for seq in capture['sequences']:
    assert len(list((OUT/'review'/seq['id']).glob('*.jpg')))==seq['frames']
    assert all(not s['fired'] and s['target_hp']==1000 for s in seq['samples'] if s['seconds']<seq['release_seconds']-1e-6)
    if seq['cancelled']:
        assert all(not s['fired'] and s['target_hp']==1000 and s['mana']==60 for s in seq['samples'])
        assert any(s.get('mode')=='dissolving' for s in seq['samples'])
    else:
        assert any(s['fired'] for s in seq['samples'])
        assert seq['samples'][-1]['mana']==50
        assert seq['samples'][-1]['target_hp']==(1000 if seq['wall'] else 970)
    assert 'mode' not in seq['samples'][-1],seq['id']
assert capture['captures']==sum(s['frames'] for s in capture['sequences'])+1==344
checks['gpu_review']={'passed':capture['passed'] and execution_ok(read(OUT/'review/execution.json')),
                      'captures':344,'sequences':7,'model_stills':1,'execution':read(OUT/'review/execution.json')}

metadata=read(BASE/'parts.json')
assert metadata['source_unchanged'] and sha(ROOT/metadata['source'])==metadata['source_sha256']
export=BASE/'exports/shotgun_parts.glb';runtime=ROOT/'game/assets/actors/shotgun_cast_v1/shotgun_parts.glb'
assert sha(export)==sha(runtime)==metadata['export_sha256']
assert sha(BASE/'parts.json')==sha(ROOT/'game/assets/actors/shotgun_cast_v1/parts.json')
blob=export.read_bytes();size=struct.unpack_from('<I',blob,12)[0];gltf=json.loads(blob[20:20+size])
triangles=sum(gltf['accessors'][p['indices']]['count']//3 for m in gltf['meshes'] for p in m['primitives'])
checks['model']={'passed':len(gltf['meshes'])==40 and triangles==8732 and not gltf.get('skins') and not gltf.get('animations'),
                 'parts':40,'triangles':triangles,'materials':len(gltf['materials']),'source_unchanged':True,
                 'method':metadata['method']}
files=[BASE/'authoring/shotgun_parts.blend',BASE/'parts.json',export,runtime]
files.extend(ROOT/p for p in ['game/scripts/arena.gd','game/scripts/shotgun_cast.gd','game/scripts/shotgun_geometry.gd',
    'game/scripts/summon_assembly.gd','game/scripts/automaton_assembly.gd','game/scripts/turret_assembly.gd',
    'game/scripts/player_visual.gd','game/scripts/combat_rules.gd','game/scripts/field_map.gd','game/data/trial.json',
    'game/audio/mechanical_impact.wav','game/tests/shotgun_cast.gd','game/tests/review_shotgun_cast.gd',
    'tools/build_shotgun_cast_v1.py','tools/run_shotgun_cast_v1.ps1','tools/package_shotgun_cast_v1.py'])
total=sum(c.get('assertions',0) for c in checks.values())
manifest={'version':'shotgun_cast_v1','passed':all(bool(c['passed']) for c in checks.values()),
          'user_art_approved':False,'runtime_assertions':total,'checks':checks,
          'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
          'files':[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in files],
          'muzzle':{'local':[0,0,0],'default_forward_m':.62,'default_right_m':.52,'default_height_m':1.12,
                    'close_targets':'Pull back and raise; prefer right, then clear left/overhead positions near walls.',
                    'range':'8m from the player; cone and wall rays start at the actual muzzle.'},
          'timing':{'release_seconds_fcr0':.125,'release_seconds_fcr40':.0788461538461538,'disappear_after_release_seconds':.45},
          'limits':['Cone vertex changed from player center to muzzle, so edge-of-fan/cover outcomes can differ; damage, mana, cooldown, maximum player-relative range and release timing are preserved.',
                    'Wall placement samples the barrel center and two side rays; not a swept-volume guarantee for every corner or pose.',
                    'Floating gun reuses the accepted turret upper surfaces; no new Tripo generation or new motion capture.',
                    'Airborne dissolve is presentation only, without part collision.',
                    'Existing mechanical audio reused; review captures are silent.',
                    'Browser UI interaction was not performed; local file policy had blocked that capability. Renderer images and static page syntax/links are checked separately.',
                    'Concurrent combat-worker changes retained; per-run input source copies and hashes identify the tested checkout.']}
assert manifest['passed'],checks
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'verified_stills').mkdir(exist_ok=True)
for name,path in [('assembly','success_close/004.jpg'),('fire','success_close/008.jpg'),('dissolve','success_close/024.jpg'),('model','model.jpg'),('near','near/008.jpg'),('native','success_native/008.jpg')]:
    shutil.copy2(OUT/'review'/path,OUT/'verified_stills'/f'{name}.jpg')

page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>산탄 — 공중 조립 · 발사 · 소멸</title>
<style>:root{color-scheme:dark;--bg:#101b20;--panel:#1a2b31;--line:#365059;--teal:#92daca}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#e8efeb;font:16px/1.65 "Malgun Gothic",sans-serif}main{max-width:1180px;margin:auto;padding:36px 26px 65px}h1{font-size:32px;letter-spacing:-1px;line-height:1.3;margin:10px 0 16px}h2{font-size:21px;margin-top:32px}p,small{color:#aec2c3}a{color:var(--teal)}.eyebrow{color:#dcb77d;letter-spacing:2px;font-size:12px}.badge{display:inline-block;border:1px solid var(--line);border-radius:5px;padding:4px 12px;margin:0 8px 8px 0;color:var(--teal);font-size:13px}.controls{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:15px 0}select,button{background:var(--panel);color:#e8efeb;border:1px solid #4e6871;border-radius:6px;padding:8px 12px;font:inherit}button{cursor:pointer}button:hover{border-color:var(--teal)}input[type=range]{flex:1;min-width:150px;accent-color:var(--teal)}figure{margin:0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--panel)}img{width:100%;display:block}figcaption{padding:11px 16px;color:#b4c9c9}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:15px}.note{border-left:3px solid #cba873;padding:12px 18px;background:var(--panel)}#frame{font-variant-numeric:tabular-nums;color:#b4c9c9;min-width:150px;font-size:14px}details{margin-top:30px;border:1px solid var(--line);padding:16px;border-radius:8px}summary{cursor:pointer;color:var(--teal)}@media(max-width:720px){main{padding:24px 14px}.grid{grid-template-columns:1fr}h1{font-size:27px}select{max-width:100%}}</style>
<main><div class="eyebrow">WITCH / SCATTER CANNON 01</div><h1>허공에서 조립하고, 발사한 뒤 사라집니다</h1><p>마녀 오른쪽 앞에 약실·톱니·포신이 빠르게 모이고, 완성된 총구에서 산탄이 나갑니다. 짧은 반동 뒤 부품이 빛으로 흩어집니다.</p><span class="badge">우클릭 산탄에 연결</span><span class="badge">40개 분할 부품</span><span class="badge">총구와 발사 원점 일치</span>
<div class="controls"><label for="sequence">장면</label><select id="sequence"></select><button id="play">일시정지</button><label for="speed">속도</label><select id="speed"><option value="1">1배</option><option value="0.5">0.5배</option><option value="0.25">0.25배</option></select></div><figure><img id="preview" src="review/success_close/000.jpg" alt="공중 산탄포 조립과 발사"><figcaption id="caption"></figcaption></figure><div class="controls"><input id="scrub" type="range" aria-label="동작 시점" min="0" max="48" value="0"><span id="frame"></span></div>
<p class="note">기본 배치의 <strong>우클릭</strong>으로 시험할 수 있습니다. 기본 발동은 기존과 같은 <strong>0.125초</strong>이며, 발사 후 약 <strong>0.45초</strong>에 총기가 사라집니다. 조립을 자세히 보려면 0.25배 재생을 선택하세요.</p>
<h2>생성 → 발사 → 소멸</h2><div class="grid"><figure><img src="verified_stills/assembly.jpg" alt="총기 부품이 모이는 중"><figcaption>약실과 구동부부터 빠르게 조립</figcaption></figure><figure><img src="verified_stills/fire.jpg" alt="완성 총구에서 산탄 발사"><figcaption>총구 섬광과 짧은 산탄 궤적</figcaption></figure><figure><img src="verified_stills/dissolve.jpg" alt="발사 뒤 총기 소멸"><figcaption>반동 뒤 빛으로 해체</figcaption></figure></div>
<h2>발사 위치</h2><p>평소에는 앞쪽 0.62m·오른쪽 0.52m, 높이 1.12m를 기준으로 둡니다. 가까운 적이 있으면 총구를 뒤로 당기고 높여 적을 지나쳐 생성하지 않게 합니다. 오른쪽이 벽에 막히면 왼쪽이나 위쪽 위치를 확인합니다.</p><p>산포각의 시작점과 벽 차단 판정은 실제 총구를 따릅니다. 최대 사거리는 플레이어 기준 8m로 유지하며, 탄선도 벽에서 끊깁니다. 시전 중 강한 피격으로 중단되면 생성된 부품만 해체되고 발사·마나 소모가 일어나지 않습니다.</p>
<details><summary>총기 외형과 검증</summary><figure><img src="verified_stills/model.jpg" alt="포탑의 황동 청록 포신부에서 만든 공중 총기"><figcaption>기존 포탑의 상부를 분리한 8,732삼각형 사본 · 원본과 질감 보존</figcaption></figure><p>총구·피해·탄선 연결, 빠른 시전, 취소/실패/일시정지/재시작, 근접 대상과 벽을 검사했습니다. 기존 누르기/연타·경직/막기·명중/치명·접근 시전·공구 연계 회귀까지 __CHECKS__개 검사 통과. 실제 게임 7장면과 외형 1장, 총 344장 렌더입니다. 이 페이지는 무음이며 게임은 기존 기계음을 사용합니다.</p><p>피해량·비용·쿨다운·발동 시점은 유지합니다. 다만 부채꼴 꼭짓점이 캐릭터 중심에서 총구로 옮겨져 가장자리와 엄폐물 근처의 명중 결과는 달라질 수 있습니다. 모든 모서리·자세에서 총기 전체의 충돌 여유를 보장하는 검사는 아닙니다.</p><p><a href="delivery_manifest.json">검증과 파일 해시</a> · <a href="../../assets/actors/shotgun_cast_v1/README.md">작업 인계</a></p></details></main>
<script>const sequences=__SEQUENCES__,select=document.querySelector('#sequence'),image=document.querySelector('#preview'),scrub=document.querySelector('#scrub'),button=document.querySelector('#play');let active,clock=0,running=true,last=performance.now(),lastFrame=-1;for(const item of sequences)select.add(new Option(item.label,item.id));select.value='success_close';function show(f){if(lastFrame!==f){image.src='review/'+active.id+'/'+String(f).padStart(3,'0')+'.jpg';lastFrame=f}scrub.value=f;document.querySelector('#frame').textContent=(f/active.fps).toFixed(3)+'초 · '+(f+1)+' / '+active.frames}function choose(){active=sequences.find(s=>s.id===select.value);clock=0;lastFrame=-1;scrub.max=active.frames-1;document.querySelector('#caption').textContent=active.label+(active.cancelled?' — 발사 없이 시전 중단':' — 발동 '+active.release_seconds.toFixed(3)+'초');show(0);for(let i=0;i<active.frames;i++){const p=new Image;p.src='review/'+active.id+'/'+String(i).padStart(3,'0')+'.jpg'}}select.onchange=choose;button.onclick=()=>{running=!running;button.textContent=running?'일시정지':'재생'};scrub.oninput=()=>{running=false;button.textContent='재생';clock=Number(scrub.value)/active.fps;show(Number(scrub.value))};function tick(now){const dt=Math.min(.15,(now-last)/1000);last=now;if(running){clock=(clock+dt*Number(document.querySelector('#speed').value))%((active.frames-1)/active.fps+.4);show(Math.min(active.frames-1,Math.floor(clock*active.fps)))}requestAnimationFrame(tick)}choose();requestAnimationFrame(tick);</script></html>'''
page=page.replace('__CHECKS__',str(total)).replace('__SEQUENCES__',json.dumps([{k:v for k,v in s.items() if k!='samples'} for s in capture['sequences']],ensure_ascii=False))
(OUT/'review.html').write_text(page,encoding='utf-8')
print('SHOTGUN_PACKAGE_COMPLETE',json.dumps({'passed':manifest['passed'],'checks':total,'captures':capture['captures']}))
