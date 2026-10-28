"""Build the review page and delivery manifest from saved validation evidence."""
import json,hashlib,html
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/boss_trial_v1'
REPORT=ROOT/'reports/boss_trial_v1'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
glb=read(REPORT/'glb_validation.json')
capture=read(REPORT/'review/capture.json')
labels={'idle':'대기','move':'네 다리 보행','sweep':'사슬 휩쓸기','slam':'자물쇠 내려찍기','frames':'문 소환','shockwave':'충격파','hit':'피격','death':'부품 붕괴','open':'문 열기','close':'문 닫기'}
actor_names={'latch':'빗장 보스','stake':'유인 말뚝','door':'교차 사격 문'}
seq=[]
for s in capture['sequences']:
    if s['actor']=='combat':continue
    s=dict(s);s['label']=actor_names[s['actor']]+' · '+labels[s['clip']];seq.append(s)
cards=''.join(f'<figure><a href="../../assets/reference/actors/boss_trial_v1/{k}_concept_v1.png"><img src="../../assets/reference/actors/boss_trial_v1/{k}_concept_v1.png" alt="{v} 제작 기준 원화" loading="lazy"></a><figcaption>{v} · 제작 기준 원화</figcaption></figure>' for k,v in actor_names.items())
table=''.join(f'<tr><td>{actor_names[f["id"]]}</td><td>{f["triangles"]:,}</td><td>{read(REPORT/"build"/f["id"]/"build.json")["rigid_parts"]}</td><td>{"2K · 2재질" if f["id"]=="latch" else "1K · 1재질"}</td></tr>' for f in glb['files'])
page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>빗장 보스 · 말뚝 · 문 — 게임 자산 v1</title>
<style>:root{color-scheme:dark;--bg:#0d171c;--panel:#17262d;--line:#31464d;--text:#e6eee9;--muted:#aabbbd;--teal:#8edacb;--gold:#dfb76e}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.65 "Malgun Gothic",sans-serif}main{max-width:1180px;margin:auto;padding:40px 28px 80px}h1{font-size:34px;letter-spacing:-1px;line-height:1.3;margin:10px 0 16px}h2{font-size:22px;margin:40px 0 14px}p{color:var(--muted);margin:12px 0}.eyebrow{font-size:12px;letter-spacing:2px;color:var(--gold)}.badge{display:inline-block;padding:3px 11px;border:1px solid var(--line);border-radius:5px;font-size:13px;margin-right:7px;color:var(--teal)}a{color:var(--teal)}figure{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden}img{display:block;width:100%;height:auto}figcaption{font-size:14px;padding:12px 16px;color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.controls{display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:15px 0}select,button{background:var(--panel);color:var(--text);border:1px solid var(--line);border-radius:5px;font:inherit;padding:8px 12px}button{cursor:pointer}button:hover{border-color:var(--teal)}input[type=range]{flex:1;min-width:140px;accent-color:var(--teal)}#pose{max-width:640px;margin:auto}.viewer{background:#101e24;padding:0;border:1px solid var(--line);border-radius:10px}.row{display:grid;grid-template-columns:1fr 1fr;gap:18px}.note{border-left:3px solid var(--gold);padding:10px 18px;background:var(--panel)}table{width:100%;border-collapse:collapse;background:var(--panel)}td,th{padding:10px 15px;text-align:left;border-bottom:1px solid var(--line)}th{font-size:13px;color:var(--gold)}details{margin-top:24px;border:1px solid var(--line);padding:16px;border-radius:7px}summary{cursor:pointer;color:var(--teal)}.links{display:flex;flex-wrap:wrap;gap:20px;margin-top:24px}#count,#chaincount{font-variant-numeric:tabular-nums;color:var(--muted);font-size:13px}@media(max-width:700px){main{padding:24px 14px}.grid,.row{grid-template-columns:1fr}h1{font-size:27px}.controls{gap:8px}select{max-width:100%}}</style>
<main><div class="eyebrow">WITCH / BOSS ASSET STUDY 01</div><h1>덜컥거리는 빗장의 이름</h1><p>낡은 문틀과 자물쇠로 된 보스, 검은 유인 말뚝, 교차 사격용 문을 Tripo 모델에서 게임 자산으로 만들었습니다.</p><span class="badge">게임 연결 완료</span><span class="badge">외형 검토 후보</span><span class="badge">1.75배 카메라 기준</span>
<h2>실제 표시 크기</h2><figure><img src="review/native_assets.png" alt="골목 C에서 마녀와 보스, 말뚝, 문 크기 비교"><figcaption>실제 골목 C · 1280 × 800 · 카메라 20 / 1.75. 보스는 기존 등급 배율을 적용한 높이 4.48m, 말뚝 2.6m, 문 2.3m입니다. 비교를 위해 보스 정면과 소환 문을 함께 배치했습니다.</figcaption></figure>
<h2>실제 전투 연계</h2><figure><img id="chain" src="review/combat_chain/000.png" alt="실제 전투의 휩쓸기와 이어지는 내려찍기"><figcaption>시험장 전투를 실제로 진행한 장면입니다. 휩쓸기 판정과 다음 내려찍기 준비가 같은 순간 일어나도 앞 동작의 타격 자세를 표시합니다.</figcaption></figure><div class="controls"><button id="chainplay" type="button">일시정지</button><input id="chainscrub" aria-label="전투 연계 프레임" type="range" min="0" max="67" value="0"><span id="chaincount"></span></div>
<h2>동작 확대 검토</h2><div class="controls"><label for="motion">동작</label><select id="motion"></select><button id="play" type="button">일시정지</button><label for="speed">속도</label><select id="speed"><option value="1">1배</option><option value="0.5">0.5배</option></select></div><div class="viewer"><img id="pose" src="review/latch_idle/000.png" alt="선택한 모델 동작"></div><div class="controls"><input id="scrub" aria-label="확대 동작 프레임" type="range" min="0" max="24" value="0"><span id="count"></span></div><p>게임에 들어간 모델을 대표 프레임으로 재생합니다. 나무·자물쇠·경첩은 부품별로 움직이며, 보스 사망 시에는 부품이 따로 무너집니다.</p>
<h2>문에서 나오는 교차 사격</h2><div class="row"><figure><img src="review/crossfire_24.png" loading="lazy" alt="문 열림과 사격 경고"><figcaption>양옆 문 열림 · 기존 경고 시간 유지</figcaption></figure><figure><img src="review/crossfire_53.png" loading="lazy" alt="문에서 발사된 구체"><figcaption>기존 발사 시점에 구체 2발 · 종료 후 문 정리</figcaption></figure></div>
<h2>제작 기준</h2><div class="grid">__CARDS__</div><p>원본 GLB와 분할 원본은 보존했습니다. 보스는 Tripo의 98부품, 문은 60부품 분할을 사용합니다. 보스 가슴의 불씨만 게임 시점에서 잘 보이도록 앞쪽으로 12cm 옮기고 발광 재질을 부여했습니다.</p>
<table><thead><tr><th>자산</th><th>삼각형</th><th>강체 부품</th><th>텍스처·재질</th></tr></thead><tbody>__TABLE__</tbody></table>
<p class="note">잔해는 중력과 바닥 접촉을 미리 구운 연출입니다. 부품끼리·벽과의 실시간 충돌은 포함하지 않습니다. 확대하면 자동 생성 모델의 면과 부품 경계가 거칠 수 있습니다. 이 검토본은 최종 외형·성능 예산 승인과 별개입니다.</p>
<details><summary>검증 범위와 작업 파일</summary><p>GLB 구조·단일 강체 가중치·텍스처·상수 트랙, Blender 저장본 재열기와 재임포트, Godot에서 36개 기준 자세의 뼈 위치를 확인했습니다. 실제 전투의 4패턴 타격 시점, 연계, 일시정지, 문 정리, 사망 시작 자세·충돌 제거·잔해 정리를 검사했습니다. 기존 보스·맵 이동·전투 자산·소환물 회귀 결과는 아래 매니페스트에 기록합니다.</p><p>새 동작은 Blender에서 작성한 시험판용 동작이며 외부 모션 캡처가 아닙니다. 플레이어 v21, 전투 수치, 지도 충돌·내비게이션 데이터는 유지했습니다.</p><div class="links"><a href="delivery_manifest.json">최종 검증·파일 해시</a><a href="../../assets/actors/boss_trial_v1/README.md">작업 파일 인계</a><a href="../../assets/actors/boss_trial_v1/authoring/latch_v1.blend">보스 Blender</a><a href="tripo_completion.png">Tripo 분할 저장 기록</a></div></details></main>
<script>const data=__DATA__,sel=document.querySelector('#motion'),pose=document.querySelector('#pose'),scrub=document.querySelector('#scrub'),counter=document.querySelector('#count'),play=document.querySelector('#play');let active=data[0],elapsed=0,running=true,old=performance.now(),last=-1,chainTime=0,chainRunning=true,chainLast=-1;for(const s of data)sel.add(new Option(s.label,s.folder));function show(f){if(f!==last){pose.src='review/'+active.folder+'/'+String(f).padStart(3,'0')+'.png';last=f}scrub.value=f;counter.textContent=(f+1)+' / '+active.frames+' · '+(f/(active.frames-1)*active.seconds).toFixed(2)+'초'}function select(){active=data.find(s=>s.folder===sel.value);elapsed=0;last=-1;scrub.max=active.frames-1;show(0);for(let i=0;i<active.frames;i++){const p=new Image;p.src='review/'+active.folder+'/'+String(i).padStart(3,'0')+'.png'}}sel.onchange=select;play.onclick=()=>{running=!running;play.textContent=running?'일시정지':'재생'};scrub.oninput=()=>{running=false;play.textContent='재생';elapsed=Number(scrub.value)/(active.frames-1)*active.seconds;show(Number(scrub.value))};const chain=document.querySelector('#chain'),cs=document.querySelector('#chainscrub'),cp=document.querySelector('#chainplay');function showChain(f){if(f!==chainLast){chain.src='review/combat_chain/'+String(f).padStart(3,'0')+'.png';chainLast=f}cs.value=f;document.querySelector('#chaincount').textContent=(f+1)+' / 68 · 실제 전투'}cp.onclick=()=>{chainRunning=!chainRunning;cp.textContent=chainRunning?'일시정지':'재생'};cs.oninput=()=>{chainRunning=false;cp.textContent='재생';chainTime=Number(cs.value)/67*4.5;showChain(Number(cs.value))};function tick(now){const dt=Math.min(.2,(now-old)/1000);old=now;if(running){elapsed+=dt*Number(document.querySelector('#speed').value);show(Math.min(active.frames-1,Math.floor((elapsed%(active.seconds+.4))/active.seconds*(active.frames-1))))}if(chainRunning){chainTime+=dt;showChain(Math.min(67,Math.floor((chainTime%5.1)/4.5*67)))}requestAnimationFrame(tick)}select();showChain(0);requestAnimationFrame(tick);</script></html>'''
page=page.replace('__CARDS__',cards).replace('__TABLE__',table).replace('__DATA__',json.dumps(seq,ensure_ascii=False))
door_fit=ROOT/'reports/door_fit_v2/fit_validation.json'
if door_fit.exists():
    page=page.replace('<h2>실제 표시 크기</h2>','<p class="note">문 닫힘 수정: 문짝과 연결 철물의 폭을 문틀에 맞췄습니다. <a href="../door_fit_v2/review.html">수정 전후 · 여닫기 비교</a></p><h2>실제 표시 크기</h2>')
(REPORT/'review.html').write_text(page,encoding='utf-8')
checks={}
for phase in ['boss_art','boss','map_nav','combat_actors','summons_v2']:
    result=read(REPORT/phase/'result.json');execution=read(REPORT/phase/'execution.json')
    count=result['checks'] if isinstance(result['checks'],int) else len(result['checks'])
    checks[phase]={'passed':not result['failures'] and execution['exit_code']==0,'checks':count,'result':str((REPORT/phase/'result.json').relative_to(ROOT)),'execution':execution}
checks['glb']={'passed':glb['passed'],'result':'reports/boss_trial_v1/glb_validation.json'}
checks['saved_blender']={'passed':read(REPORT/'saved_file_validation.json')['passed'],'result':'reports/boss_trial_v1/saved_file_validation.json'}
checks['gpu_review']={'passed':capture['passed'] and read(REPORT/'review/execution.json')['exit_code']==0,'captures':capture['captures'],'execution':read(REPORT/'review/execution.json')}
if door_fit.exists():
    checks['door_fit']={'passed':read(door_fit)['passed'],'result':'reports/door_fit_v2/fit_validation.json'}
files=[]
for folder in [BASE,ROOT/'game/assets/actors/boss_trial_v1',ROOT/'assets/reference/actors/boss_trial_v1']:
    for p in sorted(folder.rglob('*')):
        if p.is_file() and p.suffix.lower() in ['.blend','.glb','.png','.jpg']:
            files.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p)})
manifest={'version':'boss_trial_v1','passed':all(c['passed'] for c in checks.values()),'user_art_approved':False,'checks':checks,'runtime':glb['files'],'files':files,'known_limits':['Authored prototype animation, not mocap.','UV-preserving decimation, not manual retopology.','Baked collapse with local flat-floor support; no live inter-part/wall collision.','Source gaps and local roughness remain visible in closeup.','Final performance budget and user art approval remain open.'],'source_credit':'ImageGen concepts, private Tripo H3.1 generations and segmentation; 170 Tripo credits.'}
if door_fit.exists():
    manifest['revision']='door_fit_v2'
    manifest['revision_verification']={'rerun':['glb','saved_blender','boss_art','gpu_review','door_fit'],
        'historical_unchanged_scope':['boss','map_nav','combat_actors','summons_v2']}
    manifest['known_limits'][3]='Weathered panel holes and local surface roughness remain; the large latch-side door/frame gap was corrected.'
(REPORT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
production=read(BASE/'production.json');production['status']='integrated_review_candidate';production['authoring']='Blender 5.1.1 background authoring; immutable Tripo sources, rigid skinned parts, authored frame-baked clips; not manual retopology or mocap.'
production['delivery_manifest']='reports/boss_trial_v1/delivery_manifest.json';production['runtime_triangles']=glb['total_triangles'];production['game_height_m']={'latch':4.48,'stake':2.6,'door':2.3};production['user_art_approved']=False
if door_fit.exists():
    production['door_fit_v2']={'leaf_rest_width_factor':1.28,'hinge_frame_and_animation_unchanged':True,
        'validation':'reports/door_fit_v2/fit_validation.json','review':'reports/door_fit_v2/review.html'}
(BASE/'production.json').write_text(json.dumps(production,ensure_ascii=False,indent=2),encoding='utf-8')
assert manifest['passed'],checks
print('BOSS_PACKAGE_COMPLETE',json.dumps({'checks':sum(c.get('checks',0) for c in checks.values()),'captures':capture['captures'],'files':len(files),'passed':manifest['passed']}))
