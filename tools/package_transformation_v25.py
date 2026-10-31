"""Package current-input entry checks and actual game frames for user review."""
from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,re,subprocess
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/transformation_v25'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(name,data):(OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

HTML='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>마녀도시 · 입장 변신</title>
<style>
:root{color-scheme:dark;--bg:#101b20;--panel:#192a30;--line:#34464a;--ink:#edf2ed;--muted:#a9bbb9;--teal:#96dfcc;--gold:#c8aa78}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1180px;margin:auto;padding:44px 28px 55px}header{display:flex;align-items:end;justify-content:space-between;gap:24px;margin-bottom:24px}.eyebrow{font-size:11px;letter-spacing:.16em;color:var(--gold)}h1{font-size:32px;font-weight:650;letter-spacing:-.04em;margin:8px 0}p{margin:0;color:var(--muted)}.badge{border:1px solid var(--line);border-radius:24px;padding:7px 16px;color:var(--teal);white-space:nowrap;font-size:13px}.viewer{border:1px solid var(--line);border-radius:16px;overflow:hidden;background:#0b1218}.stage{position:relative;aspect-ratio:16/10;background:#12191c}.stage img{width:100%;height:100%;object-fit:contain;display:block}.phase{position:absolute;left:18px;top:16px;background:#101b20dd;border:1px solid #8ed6c459;padding:4px 12px;border-radius:18px;font-size:12px;color:var(--teal)}.controls{padding:16px 20px;background:var(--panel)}.toolbar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:13px}button,select{border:1px solid var(--line);border-radius:8px;background:#142228;color:var(--ink);font:inherit;font-size:13px;padding:9px 12px;cursor:pointer}button:hover,select:hover{border-color:var(--teal)}button:focus-visible,select:focus-visible,input:focus-visible{outline:2px solid var(--teal);outline-offset:3px}.primary{background:#96dfcc;color:#11272a;border-color:var(--teal);min-width:83px}.spacer{flex:1}.time{font:12px ui-monospace,monospace;color:var(--muted)}input[type=range]{width:100%;accent-color:var(--teal);cursor:pointer}label{font-size:12px;color:var(--muted)}.steps{display:grid;grid-template-columns:repeat(4,1fr);gap:13px;margin:22px 0}.card{padding:0;text-align:left;overflow:hidden;background:var(--panel);border-radius:11px}.card img{width:100%;aspect-ratio:16/10;object-fit:cover;display:block}.card span{display:block;padding:12px 14px;font-size:13px}.card b{display:block;color:var(--gold);font-size:10px;letter-spacing:.1em;margin-bottom:4px}.caption{font-size:13px;padding:13px 0}details{border-top:1px solid var(--line);margin-top:22px;padding:18px 0;font-size:13px;color:var(--muted)}summary{cursor:pointer;color:var(--ink)}details p{margin-top:12px}a{color:var(--teal)}footer{font-size:12px;color:#809594;margin-top:26px}@media(max-width:700px){main{padding:22px 12px}header{display:block}h1{font-size:26px}.badge{display:inline-block;margin-top:12px}.steps{grid-template-columns:repeat(2,1fr)}.controls{padding:12px}.toolbar{gap:6px}.spacer{display:none}}
</style><main><header><div><div class="eyebrow">WITCH / FIELD ENTRY / V25</div><h1>입장, 그리고 변신</h1><p>빈손의 평상복에서 지팡이를 만들고 잡은 뒤, 변신복으로 전환합니다.</p></div><span class="badge">3초 · 게임 입장에 연결</span></header>
<section class="viewer"><div class="stage"><img id="frame" src="review/front/000.jpg" alt="평상복에서 시작하는 입장 변신"><span class="phase" id="phase">평상복 · 빈손</span></div><div class="controls"><div class="toolbar"><button id="play" class="primary">일시정지</button><button id="restart">처음부터</button><label for="scene">장면</label><select id="scene"></select><span class="spacer"></span><label for="speed">재생 속도</label><select id="speed"><option value=".25">0.25배</option><option value=".5">0.5배</option><option value="1" selected>1배</option></select><span class="time" id="time">0.00 s</span></div><label for="scrub" style="position:absolute;clip:rect(0,0,0,0)">프레임 탐색</label><input id="scrub" type="range" min="0" max="99" value="0"></div></section>
<p class="caption" id="caption">앞쪽에서 조립과 손잡기, 의상 변화를 확인합니다.</p>
<section class="steps"><button class="card" data-frame="0"><img src="review/front/000.jpg" alt="지팡이 없는 평상복"><span><b>01 / ARRIVAL</b>평상복 · 빈손</span></button><button class="card" data-frame="22"><img src="review/front/022.jpg" alt="빛 속에서 조립되는 지팡이"><span><b>02 / ASSEMBLY</b>빛과 함께 부품 조립</span></button><button class="card" data-frame="45"><img src="review/front/045.jpg" alt="완성된 지팡이를 잡은 오른손"><span><b>03 / GRASP</b>오른손으로 잡기</span></button><button class="card" data-frame="96"><img src="review/front/096.jpg" alt="변신복을 입고 양손으로 지팡이를 든 모습"><span><b>04 / TRANSFORMATION</b>변신복 · 전투 준비</span></button></section>
<details><summary>게임 연결과 확인 범위</summary><p>일반 게임 실행과 재입장에 자동으로 재생됩니다. 조립이 끝난 지팡이를 오른손으로 잡고 양손 자세로 가져온 뒤, 빛이 강해지는 순간 기존 평상복 슬롯을 완전한 변신복으로 교체합니다. 기존 얼굴·몸체·머리·눈과 의상 v4의 문양을 유지합니다.</p><p>연출 중 전투를 잠시 멈추며 Esc 정지/재개와 M 음소거를 사용할 수 있습니다. 실제 게임에서는 기존 기계음을 세 시점에 재사용합니다. 이 캡처 재생은 무음입니다.</p><p>__CHECKS__개 런타임 검사, 저장 Blender 145개 자세, Python 외형 7개 검사와 실제 게임 663장을 기록했습니다. 변신 후 달리기·타격·캐스팅·경직·도약도 장면 메뉴에서 볼 수 있습니다. 실제 크기는 골목 카메라, 상세 장면은 평지 시험 맵입니다. 타격 상세 화면은 표적의 외형만 숨겼습니다.</p><p>기존 의상의 국소 접촉·치마 접힘 한계는 남습니다. 실시간 천 물리, 모든 자세의 무관통 또는 최종 성능 예산 검증은 아닙니다. <a href="delivery_manifest.json">검증·해시</a> · <a href="../../assets/characters/player/3d/source/middle_school_v1/transformation_v25/README.md">제작·인계</a></p></details><footer>현재 게임 장면으로 촬영한 검토본 · 2026.10.31</footer></main>
<script>
const scenes=__SCENES__, byId=Object.fromEntries(scenes.map(s=>[s.id,s]));
const select=document.querySelector('#scene'), img=document.querySelector('#frame'), scrub=document.querySelector('#scrub'), play=document.querySelector('#play'), speed=document.querySelector('#speed');
const phaseNames={civilian:'평상복 · 빈손',assembly:'지팡이 조립',grasp:'손에 쥐기',outfit:'의상 전환',ready:'전투 준비 완료'};
const captions={front:'앞쪽에서 조립과 손잡기, 의상 변화를 확인합니다.',native:'현재 골목 시험 맵과 1.75배 기준 카메라의 실제 표시 크기입니다.',back:'기존 케이프와 주름, 부츠를 유지한 변신복의 뒷모습입니다.',pause:'지팡이 조립 도중 정지한 뒤, 같은 자세와 부품 위치에서 이어집니다.',run:'변신복을 입은 기존 달리기 동작입니다.',attack:'기존 실제 기본 공격입니다. 의상 확인을 위해 표적 외형만 숨겼습니다.',cast:'변신복의 한 손 캐스팅과 기존 태엽인형 소환입니다.',hit:'큰 피격에 따른 기존 경직 동작입니다.',jump:'선택한 스프링판과 낮은 도약을 변신복으로 확인합니다.'};
let scene=scenes[0], frame=0, playing=true, accumulator=0, last=performance.now();
for(const s of scenes){const o=document.createElement('option');o.value=s.id;o.textContent=s.label;select.append(o);}
function draw(){const url=`review/${scene.id}/${String(frame).padStart(3,'0')}.jpg`;if(img.getAttribute('src')!==url)img.src=url;img.alt=scene.label;document.querySelector('#phase').textContent=(scene.paused[frame]?'일시정지 · ':'')+(phaseNames[scene.phases[frame]]||scene.label);document.querySelector('#time').textContent=(frame/scene.fps).toFixed(2)+' s';scrub.value=frame;}
function choose(id){scene=byId[id];select.value=id;frame=0;accumulator=0;scrub.max=scene.frames-1;document.querySelector('#caption').textContent=captions[id];draw();}
function setPlaying(value){playing=value;play.textContent=value?'일시정지':'재생';}
select.onchange=()=>choose(select.value);play.onclick=()=>setPlaying(!playing);document.querySelector('#restart').onclick=()=>{frame=0;accumulator=0;draw();setPlaying(true)};scrub.oninput=()=>{frame=Number(scrub.value);accumulator=0;setPlaying(false);draw()};
for(const b of document.querySelectorAll('[data-frame]'))b.onclick=()=>{choose('front');frame=Number(b.dataset.frame);setPlaying(false);draw()};
function tick(now){const delta=Math.min((now-last)/1000,.1);last=now;if(playing&&!document.hidden){accumulator+=delta*Number(speed.value);if(accumulator>=1/scene.fps){const skip=Math.floor(accumulator*scene.fps);accumulator-=skip/scene.fps;frame=(frame+skip)%scene.frames;draw();}}requestAnimationFrame(tick)}choose('front');requestAnimationFrame(tick);
</script></html>'''

def main():
    source=read(OUT/'source_validation.json');export=read(OUT/'export.json')
    arm_fix=read(OUT/'arm_fix/after.json')
    assert arm_fix['passed'] and not arm_fix['failures']
    assert source['passed'] and not source['failures'] and export['passed']
    folder='assets/characters/player/3d/source/middle_school_v1/transformation_v25/'
    game='game/assets/characters/player/transformation_v25/'
    assert sha(ROOT/folder/'transformation_v25.blend')==source['source_sha256']==export['source_sha256']
    assert sha(ROOT/game/'combat_transform_entry_v25.glb')==export['glb_sha256']
    assert sha(ROOT/game/'outfit_transformed_v4.glb')==sha(ROOT/'assets/characters/player/3d/exports/transformed_fit_v4/outfit_transformed_v4.glb')==export['outfit_sha256']
    runs={};count=0
    for name in ['import','transformation_v25','staff_visual','spring_jump_v24','player_visual','loadout_dash','review']:
        directory=OUT/name;execution=read(directory/'execution.json')
        assert execution['exit_code']==0 and not execution['changed_inputs'],(name,execution)
        assert execution['stderr_empty'] or execution['workspace_cache_diagnostic_only']
        inputs=read(directory/'inputs_after.json');assert inputs==read(directory/'inputs_before.json')
        changed=[p for p,h in inputs.items() if sha(ROOT/p)!=h];assert not changed,(name,changed)
        runs[name]={'execution':execution,'inputs_current':True,'inputs':inputs}
        if name not in ('import','review'):
            result=read(directory/'result.json');assert not result['failures'] and result.get('passed',True)
            runs[name]['checks']=len(result['checks']);count+=len(result['checks'])
    test=subprocess.run(['python','-m','unittest','tests.test_character_appearance'],cwd=ROOT,capture_output=True,text=True)
    assert test.returncode==0,test.stderr
    save('appearance_validation.json',{'passed':True,'exit_code':test.returncode,'checks':7,'output':test.stdout+test.stderr,'inputs':{p:sha(ROOT/p) for p in ['tests/test_character_appearance.py','tools/character_appearance.py','assets/characters/player/3d/config/modular_character.spec.json']}})
    capture=read(OUT/'review/capture.json');assert capture['passed'] and capture['captures']==663
    scenes=[];images=[]
    for scene in capture['sequences']:
        for i in range(scene['frames']):
            p=OUT/'review'/scene['id']/f'{i:03}.jpg'
            with Image.open(p) as im:assert im.size==(1280,800);im.verify()
            images.append({'path':p.relative_to(OUT).as_posix(),'sha256':sha(p)})
        scenes.append({'id':scene['id'],'label':scene['label'],'fps':scene['fps'],'frames':scene['frames'],'phases':[x['visual'].get('field_entry',{}).get('phase','ready') for x in scene['samples']],'paused':[x['paused'] for x in scene['samples']]})
    assert len(images)==663;save('capture_hashes.json',images)
    markup=HTML.replace('__SCENES__',json.dumps(scenes,ensure_ascii=False)).replace('__CHECKS__',str(count))
    comparison='''<details><summary>시작 팔 자세 수정 전·후</summary><div class="steps" style="grid-template-columns:repeat(2,minmax(0,1fr))"><div class="card"><img src="arm_fix/before/front000.jpg" alt="수정 전 팔과 소매의 비틀림"><span>수정 전</span></div><div class="card"><img src="review/front/000.jpg" alt="팔을 편안히 내린 수정 자세"><span>수정 후 · 손바닥 안쪽, 팔꿈치 축 교정</span></div></div><p>전투 대기 자세의 팔 회전이 빈손 자세에 남던 문제를 수정했습니다. 팔꿈치 축을 기준으로 팔을 내리고 전완의 비틀림을 나누어 적용합니다. 지팡이를 잡는 순간과 마지막 양손 자세는 유지했습니다.</p></details>'''
    markup=markup.replace('<details><summary>게임 연결과 확인 범위</summary>',comparison+'<details><summary>게임 연결과 확인 범위</summary>')
    (OUT/'review.html').write_text(markup,encoding='utf-8')
    (OUT/'review_syntax.js').write_text(re.search(r'<script>(.*?)</script>',markup,re.S).group(1),encoding='utf-8')
    subprocess.run(['node','--check',str(OUT/'review_syntax.js')],check=True)
    for target in re.findall(r'(?:href|src)="([^"#]+)"',markup):
        if target!='delivery_manifest.json':assert (OUT/target).exists(),target
    baseline=read(OUT/'baseline.json')['hashes']
    protected=[p for p in baseline if p not in ['AGENTS.md','docs/09_character_art_pipeline.md','docs/godot_prototype.md','game/scripts/arena.gd','game/scripts/player_visual.gd','game/scripts/staff_visual.gd']]
    assert all(sha(ROOT/p)==baseline[p] for p in protected)
    files=['game/scripts/arena.gd','game/scripts/player_visual.gd','game/scripts/staff_visual.gd','game/scripts/field_entry_transformation.gd','game/tests/transformation_v25.gd','game/tests/review_transformation_v25.gd','assets/characters/player/3d/config/modular_character.spec.json','tests/test_character_appearance.py',folder+'transformation_v25.blend',folder+'runtime_contract.json',folder+'README.md','tools/build_transformation_v25.py','tools/finalize_transformation_v25.py','tools/run_transformation_v25.ps1','tools/package_transformation_v25.py','reports/transformation_v25/review.html','reports/transformation_v25/appearance_validation.json']
    files += [p.relative_to(ROOT).as_posix() for p in (ROOT/game).iterdir() if p.is_file()]
    files += ['tools/validate_transformation_arms_v25.py','reports/transformation_v25/arm_fix/before.json','reports/transformation_v25/arm_fix/after.json','reports/transformation_v25/arm_fix/before/front000.jpg']
    save('delivery_manifest.json',{'id':'transformation_v25','generated_utc':datetime.now(timezone.utc).isoformat(),'passed':True,'status':'Integrated review candidate; user art selection pending','source_validation':source,'runtime_checks':count,'appearance_checks':7,'gpu_captures':663,'capture_scope':capture['scope'],'runs':runs,'protected_baseline_files':{p:baseline[p] for p in protected},'hashes':{p:sha(ROOT/p) for p in files},'visually_inspected_frames':['front/000.jpg','front/021.jpg','front/042.jpg','front/081.jpg','front/096.jpg','back/096.jpg','native/090.jpg','attack/008.jpg','jump/004.jpg'],'limits':['The v4 garment geometry/weights/textures are unchanged; local cloth and hair contacts remain.','Outfit swap occurs atomically under light; no cloth morph/physics or undressing phase.','Auto enables normal game entry; scripted combat harnesses skip it. Entry tests/reviews explicitly use Always.','No final performance budget or arbitrary-pose clearance.','Audio reuses mechanical_impact.wav; no new generation or separate listening assessment.','The HTML script and images were checked; browser interaction was not automated.']})
    manifest=read(OUT/'delivery_manifest.json')
    manifest['visually_inspected_frames']=['front/000.jpg','front/021.jpg','front/042.jpg','front/057.jpg','front/096.jpg','back/000.jpg','native/000.jpg']
    manifest['entry_arm_fix']={k:v for k,v in arm_fix.items() if k!='rows'}
    manifest['entry_arm_fix']['source_sha256']=source['source_sha256']
    manifest['entry_arm_fix']['comparison']='arm_fix/before.json'
    save('delivery_manifest.json',manifest)
    print(json.dumps({'passed':True,'runtime_checks':count,'appearance_checks':7,'gpu_captures':663,'review':str(OUT/'review.html')}))

if __name__=='__main__':main()
