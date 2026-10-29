"""Package recorded geometry/runtime checks and actual GPU frames only."""
from pathlib import Path
import hashlib, json, re

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/bolt_cutter_v2'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

source=read(REPORT/'source_validation.json');glb=read(REPORT/'glb_validation.json');build=read(REPORT/'build.json')
assert source['passed'] and glb['passed'] and build['passed']
assert source['source_sha256']==sha(ROOT/'assets/weapons/staff_transform_v2/authoring/staff_transform_v2.blend')
assert glb['asset_sha256']==sha(ROOT/'game/assets/weapons/staff_transform_v2/staff_parts.glb')
tests={}
for name in ('bolt_cutter_v2','staff_visual','tool_switch','player_visual','player_motion_v18','review'):
    directory=REPORT/name;execution=read(directory/'execution.json')
    assert execution['exit_code']==0 and not execution['changed_inputs'],name
    assert execution['stderr_empty'] or execution['workspace_cache_diagnostic_only'],name
    for path,digest in read(directory/'inputs_after.json').items():
        assert sha(ROOT/path)==digest,(name,path,'changed since validation')
    if name!='review':
        result=read(directory/'result.json')
        assert not result['failures'],name
        tests[name]={'checks':len(result['checks']),'execution':execution}
capture=read(REPORT/'review/capture.json');assert capture['passed']
plans=[];release_frames={};image_paths=[]
for s in capture['sequences']:
    plans.append({k:s[k] for k in ('id','label','frames','fps')})
    for i in range(s['frames']):
        p=REPORT/f'review/{s["id"]}/{i:03}.jpg';assert p.is_file() and p.stat().st_size>1000;image_paths.append(p)
    if s['id']!='assembly':
        first=next(i for i,x in enumerate(s['samples']) if x['hp']<10000)
        sample=s['samples'][first]
        assert sample['staff']['jaw_opening_degrees']==0.0
        release_frames[s['id']]={'first_capture_with_damage':first,'sample':sample}
for still in ('comparison','closed','open','bevel','staff'):
    p=REPORT/f'review/{still}.jpg';assert p.is_file();image_paths.append(p)
assert len(image_paths)==capture['captures']==357
files=['game/scripts/staff_visual.gd','game/scripts/player_visual.gd','game/scripts/arena.gd',
       'game/data/trial.json','assets/weapons/staff_transform_v1/authoring/staff_transform_v1.blend',
       'assets/weapons/staff_transform_v1/exports/staff_parts.glb',
       'assets/weapons/staff_transform_v2/authoring/staff_transform_v2.blend',
       'assets/weapons/staff_transform_v2/exports/staff_parts.glb','assets/weapons/staff_transform_v2/parts.json',
       'game/assets/weapons/staff_transform_v2/staff_parts.glb','game/assets/weapons/staff_transform_v2/parts.json',
       'tools/build_staff_transform_v2.py','tools/validate_staff_source_v2.py','tools/validate_staff_glb_v2.py',
       'tools/run_bolt_cutter_v2.ps1','tools/package_bolt_cutter_v2.py',
       'game/tests/bolt_cutter_v2.gd','game/tests/review_bolt_cutter_v2.gd']
manifest={'passed':True,'date':'2026-10-29','user_art_approved':False,'build':build,
          'source_validation':source,'glb_validation':glb,'tests':tests,
          'assertions':sum(x['checks'] for x in tests.values()),'captures':capture['captures'],
          'actual_release_observations':release_frames,'hashes':{p:sha(ROOT/p) for p in files},
          'image_hashes':{p.relative_to(REPORT).as_posix():sha(p) for p in image_paths},
          'limits':['Original stylized Blender geometry, not a physical bolt-cutter simulation.',
                    'Inspection camera excludes enemies and FX and adds light. Other views use ordinary game rendering.',
                    'No arbitrary-pose body/clothing/world clearance or final material/performance/user approval.',
                    'Very high IAS may skip anticipation samples, but actual release still closes the assembled jaws.',
                    'Older v1 and unrelated broad regressions remain historical.'],
          'reference_provenance':'Two user-provided bolt-cutter photos copied without changes; not generated game textures.'}
(REPORT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
head=next(p for p in plans if p['id']=='head')
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>볼트커터 v2 · 날과 타격 개폐</title>
<style>
:root{color-scheme:dark;font-family:system-ui,"Malgun Gothic",sans-serif;background:#101b23;color:#e5eced}*{box-sizing:border-box}body{margin:0}main{max-width:1200px;margin:auto;padding:36px 24px 60px}h1{font-size:clamp(27px,4vw,42px);margin:8px 0 16px}h2{margin:34px 0 14px;font-size:22px}p{line-height:1.7;color:#b8cbd0}.eyebrow{color:#86d7c4;letter-spacing:.13em;font-size:12px}img{display:block;width:100%;border-radius:10px;background:#101b23}.panel{background:#182933;padding:16px;border:1px solid #2c414a;border-radius:14px}.controls{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:12px 0}button,select{background:#1e3640;color:#e5eced;border:1px solid #45616b;border-radius:7px;padding:9px 12px;cursor:pointer}button[aria-pressed=true]{background:#86d7c4;color:#102128;border-color:#86d7c4}input[type=range]{flex:1;min-width:140px;accent-color:#86d7c4}a{color:#91dece}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}.live{display:grid;grid-template-columns:1.6fr 1fr;gap:12px}.live.solo{grid-template-columns:1fr}.live img{height:100%;object-fit:contain}.note{font-size:13px}#detail[hidden]{display:none}.tags{display:flex;gap:8px;flex-wrap:wrap}.tags span{padding:6px 12px;border:1px solid #36525a;border-radius:30px;font-size:13px;color:#c1d4d7}@media(max-width:760px){main{padding:24px 14px}.pair,.live{grid-template-columns:1fr}h1{font-size:28px}}
</style><main><div class="eyebrow">MACHINERY WITCH / BOLT CUTTER / V2</div><h1>크게 벌리고, 타격 순간 닫히는 날</h1><p>사진의 볼트커터 구조를 바탕으로 긴 쐐기형 날과 직선 절삭면을 만들었습니다. 준비 동작에서 양쪽 날이 크게 열리고, 실제 피해가 들어가는 순간 빠르게 맞물립니다.</p>
<div class="tags"><span>직선 절삭면</span><span>좌우 합계 64° 개방</span><span>휘두르기 · 찌르기 동기화</span><span>강체 연결봉</span></div>
<h2>이전 형태와 비교</h2><img src="review/comparison.jpg" alt="왼쪽 이전 집게형, 중앙 새 날 닫힘, 오른쪽 새 날 64도 열림">
<h2>실제 공격에서 보기</h2><div class="panel"><div class="controls" id="tabs"></div><div class="live" id="live"><img id="frame" alt="실제 시험판 동작"><div id="detail"><img id="detailFrame" alt="동일 시각의 날 확대"></div></div><div class="controls"><button id="play">일시정지</button><select id="speed" aria-label="재생 속도"><option value="1">1배</option><option value=".5">0.5배</option><option value=".25">0.25배</option></select><input type="range" id="scrub" min="0" value="0" aria-label="프레임 위치"><span id="stamp"></span><button id="impact">타격 순간</button></div><p class="note">물리 시뮬레이션은 실제 60Hz입니다. 확대 보기에서는 실제 손에 부착된 공구만 보이도록 적·타격 섬광을 제외하고 조명을 추가했습니다. 0.5배·0.25배는 이 페이지의 재생 속도만 바꿉니다.</p></div>
<h2>날과 구동부</h2><div class="pair"><div><a href="review/open.jpg"><img src="review/open.jpg" alt="길고 날카로운 날을 넓게 연 모습"></a><p>32도씩 벌어지는 날과 길이를 유지하는 연결봉.</p></div><div><a href="review/closed.jpg"><img src="review/closed.jpg" alt="중앙에서 나란히 닫힌 직선 절삭면"></a><p>직선 절삭면이 중앙에서 닫힙니다. 양쪽 메시가 교차하지 않도록 작은 간격을 남겼습니다.</p></div></div>
<p class="note">''' + f'{manifest["assertions"]:,}개 검사 · 실제 GPU 캡처 {capture["captures"]}장. ' + '''<a href="delivery_manifest.json">검증 기록</a> · <a href="../../assets/weapons/staff_transform_v2/README.md">제작 파일과 인계</a> · <a href="../staff_transform_v1/review.html">이전 지팡이 시안</a><br>새 형태는 검토 후보입니다. 임의 자세의 접촉, 실제 절삭 물리와 최종 재질·성능 검토는 별도입니다.</p></main><script>
const plans='''+json.dumps(plans,ensure_ascii=False)+''';
const impacts='''+json.dumps({k:v['first_capture_with_damage'] for k,v in release_frames.items()})+''';
const head=plans.find(p=>p.id==='head');let choice=0,position=0,playing=true,last=0;
const picture=document.getElementById('frame'),slider=document.getElementById('scrub'),stamp=document.getElementById('stamp'),play=document.getElementById('play'),detail=document.getElementById('detail'),detailFrame=document.getElementById('detailFrame'),live=document.getElementById('live'),impact=document.getElementById('impact');
function src(p,f){return `review/${p.id}/${String(f).padStart(3,'0')}.jpg`}
function draw(){let p=plans[choice],f=Math.min(p.frames-1,Math.floor(position));picture.src=src(p,f);slider.value=f;stamp.textContent=`${(f/p.fps).toFixed(2)}초 · ${f+1}/${p.frames}`;let paired=['swing','swing_side','native'].includes(p.id);detail.hidden=!paired;live.classList.toggle('solo',!paired);if(paired)detailFrame.src=src(head,Math.min(head.frames-1,Math.round(f/p.fps*head.fps)));impact.disabled=!(p.id in impacts)}
function select(i){choice=i;position=0;slider.max=plans[i].frames-1;document.querySelectorAll('#tabs button').forEach((b,n)=>b.setAttribute('aria-pressed',n===i));draw()}
plans.forEach((p,i)=>{let b=document.createElement('button');b.textContent=p.label;b.onclick=()=>select(i);document.getElementById('tabs').appendChild(b)});
function pause(){playing=false;play.textContent='재생'}
play.onclick=()=>{playing=!playing;play.textContent=playing?'일시정지':'재생'};slider.oninput=()=>{position=+slider.value;pause();draw()};impact.onclick=()=>{position=impacts[plans[choice].id]||0;pause();draw()};
function tick(t){if(last&&playing){let p=plans[choice],old=Math.floor(position);position=(position+Math.min((t-last)/1000,.1)*p.fps*+document.getElementById('speed').value)%p.frames;if(Math.floor(position)!==old)draw()}last=t;requestAnimationFrame(tick)}select(0);requestAnimationFrame(tick);
</script></html>'''
(REPORT/'review.html').write_text(html,encoding='utf-8')
js=html.split('<script>',1)[1].split('</script>',1)[0]
(REPORT/'review_syntax.js').write_text(js,encoding='utf-8')
for ref in re.findall(r'(?:src|href)="([^"#]+)"',html):
    assert (REPORT/ref).exists(),ref
print(json.dumps({'passed':True,'assertions':manifest['assertions'],'captures':len(image_paths),'page':str(REPORT/'review.html')}))
