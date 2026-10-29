"""Package current material/source checks and actual Godot captures."""
from pathlib import Path
import json,hashlib,re

ROOT=Path(__file__).resolve().parents[1];REPORT=ROOT/'reports/staff_material_v3'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
build=read(REPORT/'build.json');source=read(REPORT/'source_validation.json');glb=read(REPORT/'glb_validation.json')
assert build['passed'] and source['passed'] and glb['passed']
assert source['blend_sha256']==build['blend_sha256']==sha(ROOT/'assets/weapons/staff_material_v3/authoring/staff_material_v3.blend')
assert glb['asset_sha256']==build['asset_sha256']==sha(ROOT/'game/assets/weapons/staff_material_v3/staff_parts.glb')
tests={}
for name in ('staff_material_v3','staff_visual','bolt_cutter_v2','review'):
    folder=REPORT/name;execution=read(folder/'execution.json')
    assert execution['exit_code']==0 and not execution['changed_inputs'],name
    assert execution['stderr_empty'] or execution['workspace_cache_diagnostic_only'],name
    for path,digest in read(folder/'inputs_after.json').items():assert sha(ROOT/path)==digest,(name,path)
    if name!='review':
        result=read(folder/'result.json');assert not result['failures']
        tests[name]={'checks':len(result['checks']),'execution':execution}

capture=read(REPORT/'review/capture.json');assert capture['passed']
plans=[];images=[];releases={}
for s in capture['sequences']:
    plans.append({k:s[k] for k in ('id','label','frames','fps')})
    for frame in range(s['frames']):
        file=REPORT/f'review/{s["id"]}/{frame:03}.jpg';assert file.exists() and file.stat().st_size>1000;images.append(file)
    if s['id'] in ('attack','grinder','chainsaw','native'):
        hit=next(i for i,x in enumerate(s['samples']) if x['hp']<10000)
        releases[s['id']]={'first_damage_capture':hit,'sample':s['samples'][hit]}
for name in ('pair_0','pair_1','pair_2','pair_3','cutter_detail','lineup','core_seal'):
    file=REPORT/f'review/{name}.jpg';assert file.exists();images.append(file)
assert len(images)==capture['captures']==298

baseline_staff=(REPORT/'baseline/staff_visual.gd').read_text(encoding='utf-8')
current_staff=(ROOT/'game/scripts/staff_visual.gd').read_text(encoding='utf-8')
assert current_staff.replace('staff_material_v3/','staff_transform_v2/')==baseline_staff
assert (REPORT/'baseline/player_visual.gd').read_bytes()==(ROOT/'game/scripts/player_visual.gd').read_bytes()
textures=[]
for path in (ROOT/'assets/weapons/staff_material_v3/textures').glob('*.png'):
    runtime=ROOT/'game/assets/weapons/staff_material_v3'/('staff_parts_'+path.name)
    assert runtime.read_bytes()==path.read_bytes(),runtime
    textures.extend((path,runtime))
files=[ROOT/p for p in ('game/scripts/staff_visual.gd','game/scripts/player_visual.gd','game/scripts/arena.gd',
    'game/data/trial.json','assets/weapons/staff_material_v3/authoring/staff_material_v3.blend',
    'assets/weapons/staff_material_v3/authoring/source_material_regions.json','assets/weapons/staff_material_v3/parts.json',
    'assets/weapons/staff_material_v3/exports/staff_parts.glb','game/assets/weapons/staff_material_v3/staff_parts.glb',
    'tools/build_staff_material_v3.py','tools/validate_staff_material_source_v3.py','tools/validate_staff_material_v3.py',
    'tools/run_staff_material_v3.ps1','tools/package_staff_material_v3.py',
    'game/tests/staff_material_v3.gd','game/tests/review_staff_material_v3.gd')]+textures
manifest={'passed':True,'date':'2026-10-30','user_material_approved':False,'build':build,'source_validation':source,
    'glb_validation':glb,'tests':tests,'assertions':sum(t['checks'] for t in tests.values()),'captures':capture['captures'],
    'release_observations':releases,'runtime_code_scope':'Staff asset path only; player_visual byte-identical to pre-material baseline.',
    'hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in files},
    'image_hashes':{p.relative_to(REPORT).as_posix():sha(p) for p in images},
    'limits':['Material review candidate; no final user selection or performance approval.',
              'Texture memory is an uncompressed RGBA8+mips estimate, not measured peak memory.',
              'Studio adds identical lighting to both specimens; arena lighting is unchanged.',
              'UV and material assignments change; rigid geometry, vertex normals and mechanism data are preserved.',
              'Earlier broad combat checks remain historical; this run covers material import, staff behavior and cutter timing.']}
(REPORT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>지팡이 재질 v3 · 황동과 강철</title><style>
:root{color-scheme:dark;font-family:system-ui,"Malgun Gothic",sans-serif;background:#101b23;color:#e5eced}*{box-sizing:border-box}body{margin:0}main{max-width:1180px;margin:auto;padding:38px 24px 60px}h1{font-size:clamp(28px,4vw,42px);margin:10px 0 16px}h2{font-size:22px;margin:34px 0 14px}p{color:#b9cbd0;line-height:1.7}.eyebrow{color:#87cfba;font-size:12px;letter-spacing:.15em}.panel{background:#192a33;border:1px solid #30454e;border-radius:14px;padding:16px}img{display:block;width:100%;background:#101d25;border-radius:9px}.controls{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:10px 0}button,select{background:#203640;color:#e7eeee;border:1px solid #46616a;border-radius:7px;padding:9px 12px;cursor:pointer}button[aria-pressed=true]{background:#d0b17d;border-color:#d0b17d;color:#18262d}input[type=range]{flex:1;min-width:150px;accent-color:#d0b17d}.labels{display:grid;grid-template-columns:1fr 1fr;text-align:center;color:#b5c6cd;font-size:13px;padding:6px 0}.note{font-size:13px;color:#a7bdc5}a{color:#91dbcb}.swatches{display:flex;gap:9px;flex-wrap:wrap}.swatches span{padding:6px 12px;border:1px solid #3a5158;border-radius:30px;font-size:13px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:720px){main{padding:24px 14px}.grid{grid-template-columns:1fr}}
</style><main><div class="eyebrow">MACHINERY WITCH / MATERIAL STUDY / V3</div><h1>황동, 도장, 강철의 표면을 구분했습니다</h1><p>남색 도장의 은은한 광택, 황동의 변색과 작은 모서리 마모, 차분한 강철과 밝은 절삭면을 함께 조정했습니다. 코어는 원래의 청록색을 살리고 표면에 깊이를 더했습니다.</p><div class="swatches"><span>남색 반광 도장</span><span>낡은 황동</span><span>연마된 절삭면</span><span>청록 동력 코어</span></div>
<h2>같은 조명에서 비교</h2><div class="panel"><div class="controls" id="comparisons"></div><div class="labels"><span>기존 재질</span><span>다듬은 재질</span></div><img id="comparison" src="review/cutter_detail.jpg" alt="왼쪽 기존 재질, 오른쪽 다듬은 재질"><p class="note">형태와 자세, 조명을 동일하게 두었습니다. 날의 개폐 구조는 선택한 v2 그대로입니다.</p></div>
<h2>회전과 실제 게임 동작</h2><div class="panel"><div class="controls" id="tabs"></div><img id="frame" alt="실제 Godot 렌더링"><div class="controls"><button id="play">일시정지</button><select id="speed" aria-label="재생 속도"><option value="1">1배</option><option value=".5">0.5배</option><option value=".25">0.25배</option></select><input id="scrub" type="range" min="0" value="0" aria-label="프레임"><span id="stamp"></span></div><p class="note">회전 보기는 재질 확인용 조명입니다. 전투·이동·실제 크기 보기는 게임의 기존 조명을 그대로 사용합니다.</p></div>
<h2>공통 자루와 장식에도 같은 재질</h2><img src="review/lineup.jpg" alt="재질을 다듬은 기본 지팡이, 볼트커터, 그라인더, 전기톱"><div class="grid" style="margin-top:18px"><img src="review/core_seal.jpg" alt="청록 코어와 황동 받침, 남색 도장, 인장 장식"><div><p>전체 공구가 같은 텍스처 묶음을 공유합니다. 코어의 발광은 원래 발광하던 면에만 적용해 금속 부품으로 번지지 않게 했습니다.</p><p>형상과 동작은 유지하면서 UV와 재질을 정리했습니다. 새 재질의 마모량과 광택은 이번 비교 화면에서 검토할 수 있습니다.</p></div></div>
<p class="note">'''+f'{manifest["assertions"]}개 검사 · 실제 GPU 캡처 {capture["captures"]}장. '+'''<a href="delivery_manifest.json">검증과 파일 해시</a> · <a href="../../assets/weapons/staff_material_v3/README.md">작업 원본과 인계</a> · <a href="../bolt_cutter_v2/review.html">이전 볼트커터 시안</a><br>최종 재질 선택과 GPU 성능 검토는 별도입니다.</p></main><script>
const comparisons=[['기본 지팡이','pair_0'],['볼트커터','pair_1'],['그라인더','pair_2'],['전기톱','pair_3'],['날 확대','cutter_detail']];
comparisons.forEach(([label,id],index)=>{let b=document.createElement('button');b.textContent=label;b.setAttribute('aria-pressed',index===4);b.onclick=()=>{document.getElementById('comparison').src=`review/${id}.jpg`;document.querySelectorAll('#comparisons button').forEach((x,i)=>x.setAttribute('aria-pressed',i===index))};document.getElementById('comparisons').appendChild(b)});
const plans='''+json.dumps(plans,ensure_ascii=False)+''';let choice=0,position=0,playing=true,last=0;
const picture=document.getElementById('frame'),slider=document.getElementById('scrub'),stamp=document.getElementById('stamp'),play=document.getElementById('play');
function draw(){let p=plans[choice],f=Math.min(p.frames-1,Math.floor(position));picture.src=`review/${p.id}/${String(f).padStart(3,'0')}.jpg`;slider.value=f;stamp.textContent=`${(f/p.fps).toFixed(2)}초 · ${f+1}/${p.frames}`}
function select(i){choice=i;position=0;slider.max=plans[i].frames-1;document.querySelectorAll('#tabs button').forEach((b,n)=>b.setAttribute('aria-pressed',n===i));draw()}
plans.forEach((p,i)=>{let b=document.createElement('button');b.textContent=p.label;b.onclick=()=>select(i);document.getElementById('tabs').appendChild(b)});play.onclick=()=>{playing=!playing;play.textContent=playing?'일시정지':'재생'};slider.oninput=()=>{position=+slider.value;playing=false;play.textContent='재생';draw()};
function tick(t){if(last&&playing){let p=plans[choice],old=Math.floor(position);position=(position+Math.min((t-last)/1000,.1)*p.fps*+document.getElementById('speed').value)%p.frames;if(Math.floor(position)!==old)draw()}last=t;requestAnimationFrame(tick)}select(0);requestAnimationFrame(tick);
</script></html>'''
(REPORT/'review.html').write_text(html,encoding='utf-8')
(REPORT/'review_syntax.js').write_text(html.split('<script>',1)[1].split('</script>',1)[0],encoding='utf-8')
for reference in re.findall(r'(?:src|href)="([^"#]+)"',html):assert (REPORT/reference).exists(),reference
print(json.dumps({'passed':True,'assertions':manifest['assertions'],'captures':capture['captures'],'page':str(REPORT/'review.html')}))
