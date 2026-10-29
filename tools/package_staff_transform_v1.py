"""Package actual Godot captures, source hashes and recorded checks (no rendered images synthesized)."""
from pathlib import Path
import json
import hashlib

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/staff_transform_v1'
capture=json.loads((REPORT/'review/capture.json').read_text(encoding='utf-8-sig'))
build=json.loads((REPORT/'build.json').read_text(encoding='utf-8-sig'))
source_validation=json.loads((REPORT/'source_validation.json').read_text(encoding='utf-8-sig'))
glb_validation=json.loads((REPORT/'glb_validation.json').read_text(encoding='utf-8-sig'))
assert source_validation['passed'] and glb_validation['passed']
tests={}
for name in ('staff_visual','tool_switch','player_visual','player_motion_v18','hit_block','hold_input'):
    folder=REPORT/name
    result=json.loads((folder/'result.json').read_text(encoding='utf-8-sig'))
    execution=json.loads((folder/'execution.json').read_text(encoding='utf-8-sig'))
    n=result.get('checks',[])
    tests[name]={'checks':len(n) if isinstance(n,list) else n,'failures':result.get('failures',[]),
                 'execution':execution}
    assert not tests[name]['failures'] and execution['exit_code']==0 and not execution['changed_inputs'],name
    recorded=json.loads((folder/'inputs_after.json').read_text(encoding='utf-8-sig'))
    for path,digest in recorded.items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest, (name,path,'input differs from current file')
review_execution=json.loads((REPORT/'review/execution.json').read_text(encoding='utf-8-sig'))
assert capture['passed'] and review_execution['exit_code']==0 and not review_execution['changed_inputs']
for path,digest in json.loads((REPORT/'review/inputs_after.json').read_text(encoding='utf-8-sig')).items():
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest, ('review',path)
files=['game/scripts/staff_visual.gd','game/scripts/player_visual.gd','game/scripts/arena.gd','game/data/trial.json',
       'game/assets/weapons/staff_transform_v1/staff_parts.glb','game/assets/weapons/staff_transform_v1/parts.json',
       'assets/weapons/staff_transform_v1/authoring/staff_transform_v1.blend',
       'assets/weapons/staff_transform_v1/exports/staff_parts.glb','assets/weapons/staff_transform_v1/parts.json',
       'tools/build_staff_transform_v1.py','tools/run_staff_transform_v1.ps1','game/tests/staff_visual.gd','game/tests/review_staff_visual.gd']
hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files}
manifest={'passed':True,'date':'2026-10-29','build':build,'source_validation':source_validation,
    'glb_validation':glb_validation,'tests':tests,'review_captures':capture['captures'],
    'assertions':sum(t['checks'] for t in tests.values()),'hashes':hashes,
    'user_selected_direction':'aged brass / navy shaft / small teal power core',
    'user_art_approved':False,'scope':'Integrated prototype candidate; independent modular meshes and one optional equipment seal; no equipment UI or new combat rules.',
    'limits':['Simple material finish; no texture wear pass or final performance budget.',
        'Reserved shaft dimensions verified; arbitrary-pose head/body/cloth clearance not certified.',
        'Immediate tool toggles persist through hit stun. The assembly is cosmetic, not an interruptible new cast.',
        'The current cosmetic equipment example is an API/asset contract; no item-to-appearance database or inventory UI.']}
(REPORT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
plans=[{k:v for k,v in s.items() if k!='samples'} for s in capture['sequences']]
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>기본 지팡이 · 공구 조립 v1</title><style>
*{box-sizing:border-box}body{margin:0;background:#101b22;color:#e3e8e8;font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1200px;margin:40px auto;padding:0 24px}h1{font-size:34px;margin:5px 0}h2{font-size:22px;margin:34px 0 12px}.eyebrow{color:#7fd6bd;letter-spacing:.15em;font-size:12px}p{color:#b8c8ce;max-width:920px}.panel{background:#172832;border:1px solid #314651;border-radius:12px;padding:18px;margin-top:16px}img{display:block;width:100%;border-radius:8px;background:#101d25}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.grid p{margin:5px;font-size:13px}.controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:12px 0}button,select{background:#243e49;color:#e5efef;border:1px solid #45616b;border-radius:6px;padding:9px 13px;font:inherit;cursor:pointer}button[aria-pressed=true]{border-color:#78d6be;background:#305a5a}input{flex:1;min-width:180px;accent-color:#80d9bd}small,.muted{color:#9eafb7}a{color:#8fdfc5}table{border-collapse:collapse;width:100%}td,th{padding:9px 12px;text-align:left;border-bottom:1px solid #344a54}.note{border-left:3px solid #bb9b64;padding-left:15px}#stamp{min-width:135px;font-variant-numeric:tabular-nums}@media(max-width:720px){.grid{grid-template-columns:repeat(2,1fr)}h1{font-size:27px}}
</style><main><div class="eyebrow">MACHINERY WITCH / STAFF v1</div><h1>하나의 지팡이, 세 가지 공구</h1>
<p>황동·남색 자루와 청록 동력 코어를 공통으로 유지합니다. 공구 부품은 빛과 함께 나타나 결합하고, 매개체 장식은 별도 부착부에 남습니다. 선택한 방향으로 만든 첫 3D 검토 후보입니다.</p>
<img src="review/lineup.jpg" alt="기본형, 볼트커터, 그라인더, 전기톱의 실제 모델 비교">
<h2>실제 시험판에서 보기</h2><div class="panel"><div class="controls" id="tabs"></div><img id="frame" alt="실제 게임 연출 프레임"><div class="controls"><button id="play">일시정지</button><select id="speed" aria-label="재생 속도"><option value="1">1배</option><option value=".5">0.5배</option><option value=".25">0.25배</option></select><input id="scrub" type="range" min="0" value="0" aria-label="프레임"><span id="stamp"></span></div><small>물리 시뮬레이션 60Hz · 실제 캡처 30fps. 느린 재생은 검토 페이지에서만 적용됩니다.</small></div>
<h2>형태와 장식 부착부</h2><div class="grid">'''
for i,label in enumerate(('기본형 · 자루와 코어','볼트커터 · 복합 지렛대와 집게','그라인더 · 원판과 덮개','전기톱 · 모터와 가이드 바')):
    html+=f'<div><a href="review/model_{i}.jpg"><img src="review/model_{i}.jpg" alt="{label}"></a><p>{label}</p></div>'
html+='''</div><div class="panel"><img src="review/ornament.jpg" alt="코어 아래 별도 매개체 인장 장식"><p>예제 인장 장식은 코어 아래에 붙습니다. 공구를 바꾸거나 마나가 소진되어도 남고, 손이 미끄러지는 자루 구간에는 들어가지 않습니다. 좌우 추가 부착 지점도 데이터로 예약했습니다.</p></div>
<h2>이번 후보의 기준</h2><table><tr><th>부분</th><th>역할</th></tr><tr><td>공통 자루 · 코어</td><td>기존 오른손 부착점·양손 간격·미끄러짐 트랙 유지</td></tr><tr><td>공구 부품</td><td>약 0.22초 생성·조립 / 약 0.16초 해체·소멸</td></tr><tr><td>빠른 공격</td><td>기존 타격 시점까지 조립만 앞당김; 공격 시간·피해·비용 유지</td></tr><tr><td>매개체 장식</td><td>공구와 독립된 외형 프로필; 장비 UI·아이템 연결은 후속 작업</td></tr></table>
<p class="note">즉시 공구 전환 규칙에 맞춘 표현입니다. 피격으로 취소되는 새 시전 기술을 추가하지 않았습니다. 기존 공격 모션을 재사용하며, 큰 공구와 몸·옷의 모든 자세에서의 접촉 검증 및 최종 재질 작업은 남아 있습니다.</p>
<p id="validation">'''+f'{manifest["assertions"]}개 검사 · 실제 GPU 캡처 {capture["captures"]}장. '+'''<a href="delivery_manifest.json">검증·파일 해시</a> · <a href="../../assets/weapons/staff_transform_v1/README.md">제작 구조와 인계</a></p></main><script>
const plans='''+json.dumps(plans,ensure_ascii=False)+''';let choice=0,position=0,playing=true,last=0;const picture=document.getElementById('frame'),slider=document.getElementById('scrub'),stamp=document.getElementById('stamp'),play=document.getElementById('play');
function draw(){let p=plans[choice],f=Math.min(p.frames-1,Math.floor(position));picture.src=`review/${p.id}/${String(f).padStart(3,'0')}.jpg`;slider.value=f;stamp.textContent=`${(f/p.fps).toFixed(2)}초 · ${f+1}/${p.frames}`}
function select(i){choice=i;position=0;slider.max=plans[i].frames-1;document.querySelectorAll('#tabs button').forEach((b,n)=>b.setAttribute('aria-pressed',n===i));draw()}
plans.forEach((p,i)=>{let b=document.createElement('button');b.textContent=p.label;b.onclick=()=>select(i);document.getElementById('tabs').appendChild(b)});play.onclick=()=>{playing=!playing;play.textContent=playing?'일시정지':'재생'};slider.oninput=()=>{position=+slider.value;playing=false;play.textContent='재생';draw()};
function tick(t){if(last&&playing){let p=plans[choice];let old=Math.floor(position);position=(position+Math.min((t-last)/1000,.1)*p.fps*+document.getElementById('speed').value)%p.frames;if(Math.floor(position)!==old)draw()}last=t;requestAnimationFrame(tick)}select(0);requestAnimationFrame(tick);
</script></html>'''
(REPORT/'review.html').write_text(html,encoding='utf-8')
print(json.dumps({'passed':True,'assertions':manifest['assertions'],'captures':capture['captures'],'page':str(REPORT/'review.html')}))
