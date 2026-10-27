"""Package the inspected run correction and its actual engine comparison."""
from pathlib import Path
import json,hashlib,re,subprocess
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/run_arm_v21'
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/run_arm_v21'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
names=['independent_validation.json','run_contact.json','glb_validation.json','godot_pose_parity.json','runtime_hand_validation.json','gameplay/player_visual_validation.json','review/capture.json']
reports={n:read(OUT/n) for n in names}
assert all(d['passed'] for d in reports.values())
project=read(OUT/'review_project_sources.json')
assert all(sha(ROOT/'game'/n)==h for n,h in project['game_files'].items())
previous=read(ROOT/'reports/heavy_swing_v20/delivery_manifest.json')
assert all(sha(ROOT/n)==h for n,h in previous['files'].items())
assert all(sha(ROOT/n)==h for n,h in previous['preserved_art_and_runtime_files'].items())
execution={phase:read(OUT/phase/'execution.json') for phase in ['import_initial','import_settings','import_final','parity','hands','gameplay','review']}
assert all(x['engine_exit_code']==0 and x['completion_marker'] for x in execution.values())
count=0
for seq in reports['review/capture.json']['sequences']:
    assert seq['frames']==49
    for i in range(49):
        for view in ['native','front','side','arms']:
            with Image.open(OUT/'review'/seq['folder']/f'{i:03}_{view}.png') as im:
                assert im.size==((360,320) if view=='native' else (800,800));im.verify()
            count+=1
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',20);frames=[]
for i in range(48):
    im=Image.new('RGB',(900,490),'#141c27');d=ImageDraw.Draw(im)
    for k,(kind,title) in enumerate([('previous','수정 전 · v20'),('run','수정 후 · v21')]):
        pic=Image.open(OUT/'review'/('civilian_'+kind)/f'{i:03}_front.png').convert('RGB').resize((450,450),Image.Resampling.LANCZOS)
        im.paste(pic,(450*k,40));d.text((450*k+16,8),title,font=font,fill='#dfeafa')
    frames.append(im)
frames[0].save(OUT/'run_comparison.gif',save_all=True,append_images=frames[1:],duration=40,loop=0,optimize=True)
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>달리기 팔꿈치 수정 · v21</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0e1520;color:#e3eaf3;font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1240px;margin:auto;padding:34px 24px 50px}.tag{font-size:12px;letter-spacing:.14em;color:#83bfd7}h1{font-size:32px;letter-spacing:-.04em;margin:8px 0}p{color:#adbbcc;margin:8px 0 20px}.controls{display:flex;flex-wrap:wrap;gap:14px;align-items:end;margin:24px 0}label{display:flex;flex-direction:column;gap:5px;color:#aebed0;font-size:13px}select,button{font:inherit;background:#1a2839;color:#edf3f8;border:1px solid #34485d;border-radius:8px;padding:9px 13px;cursor:pointer}button{min-width:110px}button:hover,select:hover{border-color:#81bad0}.panels{display:grid;grid-template-columns:1fr 1fr;gap:16px}.card{border:1px solid #2a3a4d;border-radius:12px;overflow:hidden;background:#1c2430}.cap{padding:12px 17px;background:#162231}.new{color:#9be4c4}.screen{height:520px;display:flex;align-items:center;justify-content:center;overflow:hidden}.screen img{width:100%;max-height:100%;object-fit:contain}.native .screen img{width:360px;height:320px;max-width:none;max-height:none}.timeline{display:flex;gap:16px;align-items:center;margin:20px 0}.timeline input{flex:1;accent-color:#97dbc4}.phase{font-size:13px;min-width:80px;text-align:right;color:#c2d0de}.notes{display:flex;gap:22px;flex-wrap:wrap;font-size:13px;color:#b8c9d9;padding:14px 0;border-bottom:1px solid #28384a}details{margin-top:25px;color:#94a7bc}details p{font-size:13px}a{color:#a3cee8}summary{cursor:pointer}footer{margin-top:26px;font-size:12px;color:#8294aa}@media(max-width:740px){main{padding:22px 12px}.panels{grid-template-columns:1fr}.screen{height:420px}h1{font-size:27px}}
</style><main><div class="tag">WITCH · RUN ARM REVIEW 21</div><h1>팔꿈치는 아래로, 손목은 편하게</h1>
<p>달릴 때 팔꿈치가 옆으로 들리고 비틀리던 동작을 수정했습니다.<br>오른손 위·왼손 아래를 유지하고, 기존 상체·하체 동작에 맞춰 양팔과 지팡이만 다시 잡았습니다.</p>
<div class="controls"><label>의상<select id="outfit"><option value="civilian">평상복</option><option value="transformed">변신복</option></select></label><label>시점<select id="view"><option value="front">정면 확대</option><option value="side">측면 확대</option><option value="arms">팔·손목 확대</option><option value="native">게임 표시 크기 1.75×</option></select></label><label>속도<select id="speed"><option value="1">1배속</option><option value="0.5" selected>0.5배속</option><option value="0.25">0.25배속</option></select></label><button id="toggle">일시 정지</button><button id="reset">처음으로</button></div>
<div class="panels" id="panels"><div class="card"><div class="cap"><strong>수정 전 · v20</strong></div><div class="screen"><img id="before" alt="수정 전 달리기"></div></div><div class="card"><div class="cap"><strong class="new">수정 후 · v21</strong></div><div class="screen"><img id="after" alt="팔꿈치와 손목을 수정한 달리기"></div></div></div>
<div class="timeline"><input id="scrub" aria-label="달리기 주기" type="range" min="0" max="48" value="0"><span class="phase" id="phase"></span></div>
<div class="notes"><span>오른손 위 · 왼손 아래</span><span>상체·발걸음·이동 거리 유지</span><span>기준 루프 1초 · 게임에서는 이동 속도 연동</span></div>
<details><summary>검증과 적용 범위</summary><p>분리된 게임 복사본에서 비교합니다. 본 게임 기본값은 v18이며, 공격·대기·캐스팅·경직·쓰러짐은 v20을 유지했습니다. 몸체·의상·107개 기준 뼈·기존 58개 동작을 보존했습니다. 반복 경계, 중간 포즈, 손 순서, 실제 엔진 재생과 선택한 지팡이 접촉을 검사했습니다. 임의 자세의 의상 접촉 전체를 보증하지는 않습니다.<br><a href="independent_validation.json">팔·손 검증</a> · <a href="run_contact.json">지팡이 접촉</a> · <a href="gameplay/player_visual_validation.json">게임 재생 검사</a> · <a href="delivery_manifest.json">최종 기록</a> · <a href="../heavy_swing_v20/review.html">기존 전체 동작</a></p></details><footer>실제 Godot 장면 캡처 · 같은 주기의 수정 전후 비교</footer></main>
<script>
const $=id=>document.getElementById(id);let playing=!matchMedia('(prefers-reduced-motion: reduce)').matches,phase=0,last=0;let cache=[];
function path(kind,i){return `review/${$('outfit').value}_${kind}/${String(i).padStart(3,'0')}_${$('view').value}.png`}
function preload(){cache=[];for(const kind of ['previous','run'])for(let i=0;i<49;i++){const im=new Image();im.src=path(kind,i);cache.push(im)}}
function draw(){const i=Math.min(48,Math.round(phase*48));$('before').src=path('previous',i);$('after').src=path('run',i);$('scrub').value=i;$('phase').textContent=`${Math.round(phase*100)}%`;$('panels').className='panels '+($('view').value==='native'?'native':'');$('toggle').textContent=playing?'일시 정지':'재생'}
for(const id of ['outfit','view'])$(id).onchange=()=>{preload();draw()};$('toggle').onclick=()=>{playing=!playing;draw()};$('reset').onclick=()=>{phase=0;draw()};$('scrub').oninput=()=>{playing=false;phase=Number($('scrub').value)/48;draw()};
function tick(now){const dt=Math.min((now-(last||now))/1000,.1);last=now;if(playing){phase=(phase+dt*Number($('speed').value))%1;draw()}requestAnimationFrame(tick)}preload();draw();requestAnimationFrame(tick);
</script></html>'''
(OUT/'review.html').write_text(html,encoding='utf-8')
(OUT/'review_ui_check.js').write_text(re.search(r'<script>([\s\S]*)</script>',html).group(1),encoding='utf-8')
subprocess.run(['node','--check',str(OUT/'review_ui_check.js')],check=True)
validation=reports['independent_validation.json'];contact=reports['run_contact.json'];contract=read(SOURCE/'runtime_contract.json')
readme=f'''# 달리기 팔·손목 수정 v21

시작 파일은 `run_arm_v21.blend`이며 SHA-256은 `{sha(SOURCE/'run_arm_v21.blend')}`다. [실제 엔진 비교](../../../../../../../reports/run_arm_v21/review.html)에서 일상복/변신복, 정면/측면/팔 확대/게임 표시 크기를 확인한다.

v20의 좌우 손 변경 후 남은 팔 회전을 그대로 재사용하지 않고, 실제 팔꿈치가 접히는 면으로 위팔과 아래팔 방향을 맞췄다. 봉의 축 주위에서 손 방향을 조절해 손목이 팔뚝과 이어지도록 했다. 달리기 중 몸통의 큰 기울기가 지팡이를 치마 쪽으로 떨어뜨리지 않도록 목표를 조절했다. 모든 작업은 새 `combat_run_rh_v21`에 한정한다.

- 원본 v20의 29개 메시/UV/웨이트/107개 기준 뼈/58개 액션 보존. 나머지 6개 동작은 v20 그대로다.
- 상체·하체·의상 보조 뼈의 기존 동작, 3.242813140153885m 주기 거리 유지. 저작 97키/24fps/4초이며 기존 속도×클립 길이÷거리 재생 공식을 사용한다.
- 오른손 위, 왼손 -0.26m, 지팡이 축 이동 -0.26m 유지. 다른 동작까지 `staff_slide_tracks`를 반드시 사용한다.
- 독립 재개방 {validation['samples']}개 정수/반프레임 검사 통과. 루프 행렬 오차 {validation['loop_matrix_error']:.3g}, 최대 손 목표 오차 {validation['maximum_grip_error_m']*1000:.3f}mm. 실제 표면 25개 달리기 포즈 검사에서 지팡이 중심선 교차 0, 반경 포함 최소 여유 {contact['minimum_clearance_m']*1000:.3f}mm. 손 및 그립 ±45mm 소매 제외는 v20 기준과 같다.
- 완전한 5개 GLB는 `exports/run_arm_v21/`, 7개 현재 동작 + 이전 v20 달리기 1개다. `runtime_contract.json`이 파일/동작/지팡이 기준이다. 최대8 의상 웨이트 유지, 92,765삼각형.
- 별도 `reports/run_arm_v21/project_snapshot/`에서 GPU 포즈, 손 순서, 게임 재생을 검증했다. 본 게임/레지스트리는 v18 유지. {count}장 실제 엔진 캡처. 수치 통과는 사용자 아트 승인이나 모든 의상 접촉 해결을 뜻하지 않는다.

세부 범위·수치·파일 해시·실행 종료는 `reports/run_arm_v21/delivery_manifest.json`과 연결된 보고서를 따른다. Godot의 작업 폴더 캐시/프로파일러 진단은 execution에 명시하며 빈 stderr라고 표현하지 않는다. 이전 시작 관통 검사는 v20의 변경 없는 공격 액션과 계약에만 적용하며 새로 검사한 것처럼 세지 않는다. 원본 변신복 v4와 트윈테일 보관 파일은 그대로다.
'''
# Seven levels from the source directory to repository root.
(SOURCE/'README.md').write_text(readme,encoding='utf-8')
(SOURCE/'NEXT_OUTFIT.md').write_text('''# 다음 의상·모션 작업

`run_arm_v21.blend`와 `runtime_contract.json`에서 시작한다. `player_humanoid_v11` 107개 rest bone과 최대8 garment weight를 지킨다. v20 7개 동작 중 달리기만 `combat_run_rh_v21`로 바꾼 후보이며, 공격/대기/캐스팅/경직/쓰러짐과 기존 58개 액션을 보존한다. 현재 게임 기본값은 v18이며 승격 전에는 별도 비교본으로 다룬다.

변신복은 `transformed_v1/fit_v4/transformed_fit_v4.blend`와 해당 GLB, 분리 트윈테일은 `transformed_v1/hair_library/twintails_source_v1/`을 보존한다. 다른 rest family와 섞지 않는다. 새 클립은 관절면·연속 비틀림·의상 보조 뼈·양손 접촉·실제 엔진 표시를 다시 검토한다. 지팡이는 아직 임시 디자인이다.
''',encoding='utf-8')
files=[SOURCE/'run_arm_v21.blend',SOURCE/'runtime_contract.json',SOURCE/'README.md',SOURCE/'NEXT_OUTFIT.md',OUT/'review.html',OUT/'run_comparison.gif']+[OUT/n for n in names]+list((ROOT/'assets/characters/player/3d/exports/run_arm_v21').glob('*.glb'))
files += [ROOT/'tools'/n for n in ['build_run_arm_v21.py','validate_run_arm_v21.py','prepare_run_arm_review_v21.py','review_run_arm_v21.gd','run_run_arm_v21.ps1','package_run_arm_v21.py']]
manifest={'passed':True,'candidate_only':True,'source_sha256':sha(SOURCE/'run_arm_v21.blend'),'preserved_v20_delivery_files':len(previous['files']),'main_game_files_preserved':len(project['game_files']),'blender_run_samples':validation['samples'],'staff_surface_samples':25,'minimum_run_staff_clearance_m':contact['minimum_clearance_m'],'review_images':count,'runtime_hand_samples':reports['runtime_hand_validation.json']['samples'],'gameplay_checks':len(reports['gameplay/player_visual_validation.json']['checks']),'execution':execution,'files':{p.relative_to(ROOT).as_posix():sha(p) for p in files},'preserved_art_and_runtime_files':previous['preserved_art_and_runtime_files'],'scope':'Run-arm-only correction; six other actions preserved v20. Main game stays v18. Numeric checks and selected contact tests do not constitute user art approval or arbitrary-pose cloth clearance.'}
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('RUN_ARM_V21_PACKAGED',count,manifest['source_sha256'])
