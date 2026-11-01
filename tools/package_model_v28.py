"""Package the saved v28 geometry, current-input checks and visual comparisons."""
from pathlib import Path
import json,hashlib,datetime,subprocess
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/model_refinement_v28'
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/model_refinement_v28'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
preserve=read(OUT/'preservation.json');glb=read(OUT/'glb_validation.json')
entry=read(OUT/'transformation_v27/result.json');combat=read(OUT/'player_visual/player_visual_validation.json')
capture=read(OUT/'review/capture.json');reimport=read(OUT/'blender_reimport.json')
assert preserve['rig_unchanged'] and preserve['actions_unchanged'] and all(preserve['protected_meshes'].values())
assert glb['passed'] and entry['passed'] and not combat['failures'] and capture['passed'] and reimport['passed']
assert preserve['source_sha256']==sha(SOURCE/'model_refinement_v28.blend')
qa=read(OUT/'asset_qa_separate_parts.json')
assert all(v['pass'] for v in qa.values())
for phase in ['transformation_v27','player_visual','review']:
 execution=read(OUT/phase/'execution.json');assert execution['exit_code']==0 and not execution['changed_inputs']
 for name,value in read(OUT/phase/'inputs_before.json').items():assert sha(ROOT/name).lower()==value.lower(),(phase,name,'input changed')
for name,info in glb['files'].items():
 export=ROOT/'assets/characters/player/3d/exports/model_refinement_v28'/name
 runtime=ROOT/'game/assets/characters/player/model_refinement_v28'/name
 assert sha(export)==sha(runtime)==info['sha256']
assert len(list((OUT/'review').rglob('*.jpg')))==capture['captures']
old_manifest=read(ROOT/'reports/transformation_v27/delivery_manifest.json')
preserved_runtime=['game/assets/characters/player/transformation_v26/combat_transform_entry_v26.glb','game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb','game/assets/characters/player/transformation_v27/hair_semilong_v27.glb']
for path in preserved_runtime:assert sha(ROOT/path)==old_manifest['hashes'][path],path

adjudication={
 'passed':True,'raw_report':'asset_qa.json','separate_part_report':'asset_qa_separate_parts.json',
 'accepted_findings':[
  'The combined left/right hand, sock and shoe objects intentionally contain two disconnected anatomical parts; each side passes separately.',
  'The raw shoe report flags two nearly coplanar pairs at duplicated UV-seam coordinates at 0.15mm tolerance. Calculation-only seam welding at 0.015mm produces no z-fighting errors on either side; exported topology and UV seams stay intact.',
  'A calculation-only welded left shoe has one wire edge; the unchanged source surface has no loose vertices, degenerate faces or inverted components. The helper is discarded.',
  'Hands, face and socks intentionally sit above the origin of a complete standing character.'
 ],
 'visual_review':'Material and wireframe front/side/three-quarter Blender inspection plus actual Godot comparisons. This does not prove arbitrary pose/cloth clearance.'}
(OUT/'qa_adjudication.json').write_text(json.dumps(adjudication,indent=2)+'\n',encoding='utf-8')

paths=[SOURCE/'model_refinement_v28.blend',SOURCE/'textures/hands_basecolor_v28.png']
paths+=list((ROOT/'game/assets/characters/player/model_refinement_v28').glob('*.glb'))
paths+=[ROOT/p for p in ['game/scripts/player_visual.gd','game/scripts/modular_character_runtime.gd','game/scripts/arena.gd','game/scripts/hair_motion.gd','game/scripts/field_entry_transformation.gd','game/data/trial.json','game/assets/characters/player/transformation_v26/combat_transform_entry_v26.glb','game/assets/characters/player/transformation_v27/hair_semilong_v27.glb','game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb']]
manifest={'version':'model_refinement_v28','status':'integrated_review_candidate_not_user_art_approval','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'changes':{'hands':'Original high-poly Tripo hand extraction, shape-preserving reduction, fitted onto unchanged finger rest chains; sleeve cuff removed; normalized skin weights; 14mm wrist coverage extension; one 512px color atlas.',
 'civilian_shoes':'21mm outward alignment per shoe; rigid same-side foot weights; 286 ankle-rim vertices smoothed (maximum additional local change 17.373mm). Sock bottom extends from z=0.105m to 0.078m with foot/shin blend.',
 'face':'Existing young v8 identity/paint retained; local cheek/jaw/nose/lip form correction up to 1.3742mm and softer skin specular response.'},
 'preserved':{'body_bones':107,'body_actions':63,'auxiliary_hair_bones':8,'auxiliary_hair_action':1,'protected_mesh_signatures':len(preserve['protected_meshes']),'bind_signature':glb['rig_bindings_sha256']},
 'metrics':{'hand_triangles_before':8588,'hand_triangles_after':7978,'hand_color_size':[512,512],'visible_civilian_triangles':92107},
 'validation':{'blender_reimport_poses':reimport['sampled_poses'],'runtime_entry_checks':entry['checks'],'runtime_combat_checks':len(combat['checks']),'gpu_captures':capture['captures'],'qa':'qa_adjudication.json'},
 'inputs':{str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in paths},
 'preserved_runtime_assets':{path:sha(ROOT/path) for path in preserved_runtime},
 'limits':['Face paint and painted gaze are unchanged; this is a subtle form pass, not a redesigned portrait or facial-expression rig.','Original garment folds, large-pose clothing intersections and imperfect source hair edges remain outside this local repair.','Review motion sequences sample imported clips; gameplay timing and cleanup are checked separately by existing arena tests.','No final physical hand/staff contact, arbitrary-pose clothing clearance or performance budget approval is implied.']}
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

source_readme='''# Model refinement v28 — shoes, original Tripo hands and local face forms

The user requested civilian shoe/ankle alignment, better hands using the original Tripo model if possible, and a face improvement. This derivative is integrated for review; no new user art approval is recorded.

Open `model_refinement_v28.blend`. The source is packed and preserves the accepted v27 hair, v26 entry gesture, 107 body rest bones and 63 body actions plus the independent eight-bone hair rig/action. Original models and prior deliveries remain intact. Start visual review at `reports/model_refinement_v28/review.html` from the repository root.

- **Hands:** extracted from the preserved 1,980,284-triangle Tripo raw GLB. The source cuff is removed, the palm/finger centerlines fit the existing rest skeleton and weights follow the existing animations. The new pair has 7,978 triangles (previous pair 8,588), up to four influences, and a 512×512 packed base-color atlas. A short forearm extension covers the sleeve/wrist join. This is fitted/reduced original geometry, not newly handcrafted quad topology.
- **Civilian shoes:** each moves outward 21mm onto the common ankle and follows its foot rigidly. Only the ankle-opening rim is smoothed; the loafer color/UVs and main shape remain. Sock bottoms extend 27mm into the shoes and blend into foot weights. Shoe UV seams are preserved; socks gain usable UVs.
- **Face:** the existing young face, painted eyes and UVs remain. Cheek/jaw transitions, soft chin, nose and lip relief change at most 1.3742mm; skin highlights are softened. This is intentionally a small form pass. A larger improvement in close-up expression would need separate face/eye texture and expression work.

The source keeps `ARCHIVE_*_pre_v28` comparison objects hidden. `TEMPLATE_CompleteCoveredBody_v8` is a preserved fitting reference, not an exported visible body. Do not unhide it for gameplay comparisons: it protrudes through source clothing and shoes.

Runtime replacements are only body, eyes and civilian outfit under `game/assets/characters/player/model_refinement_v28/`. The original v21 animation directory remains the motion/slide contract source; later v23/v24/v26 clips, v4 transformed outfit and v27 auxiliary hair remain external and unchanged. Both outfits use the same new hands/face. Garments keep up to eight weights.

Validation: three stored GLBs pass bind/UV/weight/animation checks; a fresh Blender reimport samples 40 poses. Current arena tests pass 3,104 entry/hair checks and 192 combat/presentation checks. Review contains 334 actual Godot frames. See the delivery manifest for exact hashes/scope and QA adjudication for intentional left/right separation and tiny source UV-seam reports. Existing large-pose garment contacts and hair edge artifacts are not repaired by this pass.

Authoring helpers: `tools/prepare_model_refinement_v28.py`, `refine_model_v28.py`, `finalize_model_v28.py`, `bake_hands_v28.py`; saved asset is authoritative. `finalize_model_v28.py` exports the selected saved derivative. Run `tools/run_model_v28.ps1` for import/test/review and `tools/package_model_v28.py` to refresh this package only after current-input validation.
'''
(SOURCE/'README.md').write_text(source_readme,encoding='utf-8')

html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>캐릭터 모델 보정 v28</title>
<style>body{margin:0;background:#121b21;color:#e7eef2;font:16px/1.6 system-ui,sans-serif}main{max-width:1440px;margin:auto;padding:30px}h1{font-size:30px;margin-bottom:8px}h2{margin-top:34px;font-size:23px}p{color:#bdcbd4;max-width:1050px}.controls{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:16px 0}select,button{font:inherit;background:#243640;color:#fff;border:1px solid #476171;border-radius:6px;padding:8px 14px}button{cursor:pointer}.pair{display:grid;grid-template-columns:1fr 1fr;gap:14px}figure{margin:0;background:#1b2932;border-radius:8px;overflow:hidden}figcaption{padding:8px 14px;color:#a9d9ce}img{display:block;width:100%;height:auto}.single{max-width:1100px}input[type=range]{width:min(500px,60vw)}small{color:#9fb1bd}a{color:#9cdbd1}details{margin-top:30px} @media(max-width:760px){.pair{grid-template-columns:1fr}main{padding:16px}}</style>
<main><h1>구두 · 손 · 얼굴 보정</h1><p>구두와 발목 중심을 맞추고, 원본 Tripo 손을 기존 리그에 맞춰 교체했습니다. 얼굴은 기존 어린 인상을 유지하며 볼·턱·코·입의 형태를 조금 다듬었습니다. 현재 게임에도 연결된 검토본입니다.</p>
<h2>같은 자세에서 전후 비교</h2><div class="controls"><label>부위 <select id="part"><option value="shoes">교복 구두·발목</option><option value="hands">지팡이를 쥔 손</option><option value="face">얼굴</option><option value="full">전체</option></select></label><label>각도 <select id="angle"><option value="three_quarter">사선</option><option value="front">정면</option><option value="side">옆면</option></select></label></div>
<div class="pair"><figure><figcaption>이전</figcaption><img id="before" alt="수정 전"></figure><figure><figcaption>v28</figcaption><img id="after" alt="수정 후"></figure></div>
<h2>펼친 손에서 지팡이를 잡기까지</h2><div class="controls"><label>자세 <select id="grip"><option value="0_0">처음 · 손을 내림</option><option value="0_85">지팡이로 손 뻗기</option><option value="1_4">오른손으로 잡기</option><option value="2_1">양손으로 잡기</option></select></label></div><div class="pair"><figure><figcaption>이전</figcaption><img id="gripBefore" alt="이전 손"></figure><figure><figcaption>원본 Tripo 기반 손</figcaption><img id="gripAfter" alt="새 손"></figure></div>
<h2>교복·변신복 동작 확인</h2><div class="controls"><select id="form"><option value="civilian">교복</option><option value="transformed">변신복</option></select><select id="action"><option value="idle">대기</option><option value="run">달리기</option><option value="attack">타격</option><option value="cast">캐스팅</option><option value="hit_react">경직</option><option value="spring_jump">도약 모션</option></select><button id="play">재생</button><input id="frame" type="range" min="0" max="24" value="0"><span id="counter"></span></div><figure class="single"><img id="motion" alt="동작 검토"></figure><small>게임에 가져온 동작을 처음부터 끝까지 고르게 샘플링한 화면입니다. 도약의 실제 이동·포물선, 스킬 이펙트는 이 모델 비교 화면에서 재생하지 않습니다.</small>
<h2>기존 1.75배 게임 카메라</h2><div class="pair"><figure><figcaption>교복</figcaption><img src="review/civilian_native.jpg" alt="실제 크기 교복"></figure><figure><figcaption>변신복</figcaption><img src="review/transformed_native.jpg" alt="실제 크기 변신복"></figure></div>
<p>얼굴 변화는 작은 형태 보정입니다. 눈과 입에 그려진 표현은 기존 텍스처를 유지합니다. 확대 연출용 표정·눈 표현과 원본 머리카락 가장자리, 큰 동작의 옷 접촉은 별도 개선 대상으로 남아 있습니다.</p>
<details><summary>검증 자료</summary><p>몸체 107본과 기존 모션, 별도 헤어 8본 유지. 손 7,978삼각형 · 512px 색 텍스처. 변신/헤어 3,104개와 전투/표현 192개 검사 통과, GLB 재불러오기 40자세, Godot 캡처 334장.</p><a href="delivery_manifest.json">입력 해시·검증 범위</a> · <a href="qa_adjudication.json">모델 QA 기록</a></details>
<script>
const $=id=>document.getElementById(id);const sequences=SEQUENCES;
function pair(){const stem=$('part').value+'_'+$('angle').value;$('before').src='review/'+stem+'_before.jpg';$('after').src='review/'+stem+'_after.jpg'}
function grip(){for(const [id,version] of [['gripBefore','before'],['gripAfter','after']])$(id).src='review/grip_'+$('grip').value+'_'+version+'.jpg'}
function motion(){let i=+$('frame').value;$('motion').src='review/'+$('form').value+'_'+$('action').value+'/'+String(i).padStart(3,'0')+'.jpg';$('counter').textContent=(i+1)+' / 25'}
let timer=null;function stop(){clearInterval(timer);timer=null;$('play').textContent='재생'}
$('play').onclick=()=>{if(timer){stop();return}let id=$('form').value+'_'+$('action').value;let fps=sequences.find(x=>x.id===id).fps;timer=setInterval(()=>{$('frame').value=(+$('frame').value+1)%25;motion()},1000/fps);$('play').textContent='일시정지'};
for(const id of ['part','angle'])$(id).onchange=pair;$('grip').onchange=grip;for(const id of ['form','action'])$(id).onchange=()=>{stop();$('frame').value=0;motion()};$('frame').oninput=()=>{stop();motion()};pair();grip();motion();
</script></main></html>'''.replace('SEQUENCES',json.dumps(capture['sequences']))
(OUT/'review.html').write_text(html,encoding='utf-8')

registry_path=ROOT/'assets/characters/player/3d/config/modular_character.spec.json';registry=read(registry_path)
registry['status']='combat_prototype_model_refinement_v28_review'
registry['rig']['asset']='exports/model_refinement_v28/body_standard_v28.glb'
for section,key,filename in [('bodies','standard_v1','body_standard_v28.glb'),('eyes','neutral_v1','eyes_neutral_v28.glb'),('outfits','civilian_v1','outfit_civilian_v28.glb')]:
 record=registry[section][key]
 if record['asset']!='exports/model_refinement_v28/'+filename:record['previous_asset']=record['asset']
 record['asset']='exports/model_refinement_v28/'+filename;record['runtime_asset']='res://assets/characters/player/model_refinement_v28/'+filename;record['sha256']=glb['files'][filename]['sha256'];record['status']='validated';record['art_status']='review_candidate';record['validation_report']='reports/model_refinement_v28/delivery_manifest.json'
registry['validation']['visible_civilian_triangles']=92107
registry['validation']['model_refinement_v28']='reports/model_refinement_v28/delivery_manifest.json'
registry['validation'].setdefault('previous_motion_validation_report',registry['validation']['report'])
registry['validation']['scope']='v28_local_model_repair_with_unchanged_motion_and_auxiliary_hair'
registry['validation']['report']='reports/model_refinement_v28/delivery_manifest.json'
registry['validation']['visual_approval']='The previously selected motion family and v27 transformation/hair remain. The new v28 shoe/hand/face appearance is an integrated review candidate awaiting user selection.'
registry_path.write_text(json.dumps(registry,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
appearance=subprocess.run(['python','-m','unittest','tests.test_character_appearance'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
assert appearance.returncode==0,appearance.stdout+appearance.stderr
(OUT/'appearance_validation.json').write_text(json.dumps({'passed':True,'output':appearance.stdout+appearance.stderr,'registry_sha256':sha(registry_path)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
manifest['validation']['appearance_checks']=7
manifest['inputs'][str(registry_path.relative_to(ROOT)).replace('\\','/')]=sha(registry_path)
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('V28_PACKAGED',manifest['validation'])
