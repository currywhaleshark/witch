"""Offline review, exact-input manifest and compact current-state handoff."""
import json, hashlib, subprocess, re, html
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2';OUT=ROOT/'reports/hound_game_v2';GAME=ROOT/'game/assets/actors/automation_batch2/hound_v2'
def read(p):return json.loads(p.read_text(encoding='utf8'))
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
geo=read(BASE/'geometry.json');rig=read(BASE/'rig.json');source=read(OUT/'validation/saved_source.json');run=read(OUT/'runtime/runtime_validation.json')
assert run['passed'] and read(OUT/'validation/source_qa.json')['pass'] and read(OUT/'validation/reimport_qa.json')['pass']
assert geo['triangles']==rig['triangles']==source['triangles']==run['metrics']['triangles']
assert (BASE/'hound_v2.glb').read_bytes()==(GAME/'hound_v2.glb').read_bytes()
expected=read(OUT/'local/animation_samples.json');actual=read(OUT/'runtime/runtime_poses.json');max_error=0.;count=0
for row in actual:
    wanted=min(expected[row['clip']],key=lambda r:abs(r['time']-row['time']))
    assert abs(wanted['time']-row['time'])<1e-6
    for name,p in row['bones'].items():
        v=np.asarray(wanted['world'][name])[:3,3];v=v[[0,2,1]]*np.array([1,1,-1])
        max_error=max(max_error,float(np.linalg.norm(np.asarray(p)-v)));count+=1
assert max_error<.000005,max_error
write(OUT/'validation/runtime_parity.json',{'passed':True,'bone_origin_comparisons':count,'maximum_error_m':max_error,'all_authored_contact_and_hit_times_preserved':True})
raw=ROOT/'assets/actors/automation_batch2/hound_tripo_v1/source'
original={f'hound_{label}.glb':read(ROOT/'reports/automation_batch2_v1'/folder/'inventory.json')['source_sha256'] for label,folder in [('raw','raw'),('segmented','segmented')]}
for name,want in original.items():assert sha(raw/name)==want

videos={}
for clip in ['spawn','idle','run','bite','hit','death','native_run']:
    folder=OUT/'runtime'/('motion_'+clip if clip!='native_run' else clip)
    dest=OUT/(clip+'.mp4')
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-framerate','24','-i',str(folder/'%03d.jpg'),
                    '-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-c:v','libx264','-preset','medium','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(dest)],check=True)
    videos[clip]={'path':dest.name,'frames':len(list(folder.glob('*.jpg'))),'fps':24,'bytes':dest.stat().st_size}

land=geo['fitted_source_landmarks'];bodylength=land['nose']['max'][1]-land['rump']['min'][1]
production={
 'stage':'prepared base hound art/motion candidate; not main-game skill integration',
 'user_source_direction_selection':'좋구만 / 이어가보자 (2026-11-05); source concept direction accepted, this new motion pass remains a review candidate',
 'triangles':geo['triangles'],'original_working_triangles':76862,'rigid_groups':rig['parts'],'meshes':1,'materials':2,'bones':rig['bones'],'clips':rig['clips'],
 'source_process':'Blender 5.1.1 background CLI; live MCP get_addon_status reported Not connected to Blender; no new Tripo generation or credits',
 'fitting':{'body_nose_to_rump_m':bodylength,'shoulder_shell_height_m':land['shoulder']['max'][2],'head_roof_excluding_antennas_m':land['head_roof']['max'][2],
             'overall_bounds_blender':source['measurements']['bounds_blender'],'origin':'floor, average of four paw-pad bbox centres','forward':'Blender +Y -> Godot -Z'},
 'rig':'one full bone influence per vertex and triangle; 33 independent rigid groups merged into two material surfaces; unit scale in all authored tracks',
 'geometry_changes':{'source_parts':60,'semantic_groups':33,'limb_cap_triangles':geo['limb_cap_triangles'],'source_pistons_replaced':geo['source_pistons_replaced'],
        'topology_repairs':geo['topology_repairs'],'static_fit_matrix':geo['static_fit_matrix'],'neck_rest_tilt_degrees':-7},
 'textures':{'color':1024,'normal_OpenGL':1024,'orm':1024,'emission':64,'orm_ao_channel':'1.0 neutral, not a separate AO bake','runtime_materials':2},
 'piston_fits':rig['piston_fits'],'videos':videos,
 'validation':{'runtime_checks':run['checks'],'gpu_captures':run['captures'],'source_reopened_poses':source['poses'],'runtime_origin_comparisons':count,'runtime_origin_max_error_m':max_error,
        'source_errors':len(read(OUT/'validation/source_qa.json')['errors']),'reimport_errors':len(read(OUT/'validation/reimport_qa.json')['errors']),'floor_metrics':run['metrics']['floors']},
 'limits':['Base hound and shared 0.8x pack preview only; heavy tracker armour remains unbuilt.',
 'No hound gameplay rules/targets/FX/node selection integration and no beacon/giant model generation in this pass.',
 'Baked collapse starts from the authored idle pose; arbitrary interruptions and arbitrary blended poses are not contact-certified.',
 'No live inter-part/debris/terrain collision, visual or performance approval.',
 'Torso/source shell boundaries and intentional internal joint overlaps remain; source QA retains 22 seam/contact duplicate vertices and two hidden opposing-face pairs.',
 'Piston length adjustment is a one-time rest-mesh fit. Mesh parts never scale during playback.',
 'Native comparison uses the actual 1.75x camera settings and current assets with shared studio lighting; main game lighting is unchanged.'],
 'technical_references':['https://docs.godotengine.org/en/stable/classes/class_editorscenepostimport.html','https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/advanced_import_settings.html'],
 'immutable_download_hashes':original}
write(BASE/'production.json',production)

labels={'spawn':'등장','idle':'대기','run':'질주','bite':'물기','hit':'피격','death':'붕괴'}
buttons=''.join(f'<button data-clip="{c}" class="'+('selected' if c=='run' else '')+f'">{label}</button>' for c,label in labels.items())
notes={'spawn':'0.4초 · 낮게 웅크린 뒤 일어남','idle':'1초 루프 · 가슴, 태엽 열쇠와 꼬리','run':'0.5초 루프 · 기준 6.5m/s / 한 주기 3.25m · 제자리 클립',
       'bite':'0.6초 · 0.3초에 턱 닫힘 · 영상 앞뒤에는 검토용 정지 구간이 있음','hit':'0.25초 · 짧은 피격 반응','death':'1.2초 · 폭발 없이 부품 낙하 · 바닥 접촉은 미리 구운 동작'}
page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>기계 수렵견 · v2</title>
<style>*{box-sizing:border-box}body{margin:0;background:#0d181e;color:#dfe7e8;font:16px/1.7 system-ui,sans-serif}main{max-width:1160px;margin:auto;padding:42px 24px}h1{font-size:38px;line-height:1.2;margin:10px 0}h2{font-size:23px;margin:38px 0 12px}p{color:#b5c5ca}a{color:#8cded0}small,.eyebrow{color:#c4a76c}.eyebrow{letter-spacing:.1em;font-size:13px}.facts{display:flex;gap:24px;flex-wrap:wrap;margin:24px 0}.facts b{font-size:25px;color:#eee1bf}.facts span{font-size:13px;display:block;color:#8ea4ae}.panel{background:#15242c;border:1px solid #30444c;border-radius:14px;padding:16px;margin:15px 0}.tabs{display:flex;gap:7px;flex-wrap:wrap}button{cursor:pointer;border:1px solid #49626c;border-radius:7px;background:#20343e;color:#d6e3e8;padding:9px 16px;font-size:15px}button.selected{border-color:#b9a06c;background:#4b4938;color:#fff0c9}video,img{display:block;width:100%;height:auto;border-radius:8px}#motion{background:#263a44}#note{margin:10px 0 0;min-height:28px}.toolbar{display:flex;gap:12px;align-items:center;margin:12px 0}.toolbar select{background:#1c3039;color:#e4edee;border:1px solid #53717a;padding:6px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}.native{overflow:auto}.native.actual img{width:1280px;max-width:none}ul{padding-left:23px;color:#b7c8cf}table{width:100%;border-collapse:collapse;font-size:14px}td,th{text-align:left;padding:10px;border-bottom:1px solid #31444c}.muted{font-size:14px;color:#96adb7}.links{display:flex;gap:20px;flex-wrap:wrap}@media(max-width:700px){h1{font-size:29px}.grid{grid-template-columns:1fr}main{padding:25px 14px}}</style>
<main><div class="eyebrow">AUTOMATION / PREPARED ART / 2026.11.05</div><h1>기계 수렵견, 움직임을 붙이다</h1>
<p>선택한 Tripo 원본을 관절 단위로 정리하고, 게임용 경량화·리깅·기본 동작을 준비했다. 턱·다리·피스톤은 금속 부품으로 움직인다.</p>
<div class="facts"><div><b>TRIS</b><span>76,862 → 경량화</span></div><div><b>33 부품</b><span>1 메시 / 2 재질</span></div><div><b>37 본</b><span>정점당 1 본, 100%</span></div><div><b>6 동작</b><span>24fps + 접지·타격 보조 키</span></div></div>
<section class="panel"><div class="tabs">BUTTONS</div><div class="toolbar"><label>재생 속도 <select id="speed"><option value=".5">0.5×</option><option value="1" selected>1×</option><option value="1.5">1.5×</option></select></label><span class="muted">실제 Godot 렌더 · 영상에는 소리가 없음</span></div>
<video id="motion" src="run.mp4" poster="runtime/front.jpg" controls autoplay loop muted playsinline></video><p id="note"></p></section>
<h2>형태와 관절</h2><div class="panel"><div class="tabs" id="angles"><button data-img="runtime/front.jpg" class="selected">앞</button><button data-img="runtime/side.jpg">옆</button><button data-img="runtime/rear.jpg">뒤</button><button data-img="runtime/top.jpg">위</button><button data-img="geometry/parts.png">부품 구분</button><button data-img="geometry/wire.png">와이어</button></div><img id="still" src="runtime/front.jpg" loading="lazy"></div>
<p>몸길이 약 0.955m, 어깨 약 0.497m, 안테나를 제외한 머리 높이 약 0.628m. 다리 마디의 빈 안쪽을 막고, 회전축과 피스톤 연결 핀을 보강했다. 원본 파일은 보존했다.</p>
<h2>실제 표시 크기</h2><p>1280 × 800 / 기존 1.75배 카메라. 왼쪽부터 마녀 · 수렵견 · 태엽인형 · 포탑 · 적 3종. 조명은 동일한 검토용 조명이다.</p>
<button id="nativeToggle">원본 픽셀 크기 전환</button><div class="native panel" id="native"><img src="runtime/native_lineup.jpg" loading="lazy"></div>
<div class="grid"><section class="panel"><h3>게임 크기의 달리기</h3><video src="native_run.mp4" controls loop muted playsinline preload="metadata"></video></section><section class="panel"><h3>사냥 무리 크기</h3><img src="runtime/pack.jpg" loading="lazy"><p class="muted">0.8배 세 마리. 같은 기본 메시·재질을 재사용한다.</p></section></div>
<h2>검사와 다음 연결</h2><table><tr><th>항목</th><th>현재 결과</th></tr><tr><td>저장본 / GLB 재임포트</td><td>메시 QA 오류 0 / 0, 6개 액션 유지</td></tr><tr><td>Godot 재생</td><td>CHECKS 검사 통과 · CAPTURES GPU 캡처</td></tr><tr><td>바닥·강체</td><td>촘촘한 샘플에서 바닥 위 유지, 스케일·시어 없음, 루프 양 끝 자세 일치</td></tr><tr><td>교환 파일</td><td>packed Blender · GLB · 부품/소켓 계약 · 전용 임포트 스크립트</td></tr></table>
<p class="muted">몸통 원본 쉘의 열린 경계, 숨겨진 접합면과 관절 내부 겹침은 남아 있다. 전 자세의 부품 충돌이나 실시간 물리 검증은 아니다. 붕괴는 대기 자세에서 시작하는 사전 제작 동작이다.</p>
<p>이번 범위는 수렵견 기본형과 동작 시안이다. 중장 추적기 추가 장갑, 스킬 규칙·표적·FX 연결, 신호기·거대 자동인형 모델은 후속 작업으로 남아 있다.</p>
<div class="links"><a href="../../assets/actors/automation_batch2/hound_game_v2/README.md">인계 설명</a><a href="../../assets/actors/automation_batch2/hound_game_v2/hound_game_v2.blend">Blender 원본</a><a href="../../game/assets/actors/automation_batch2/hound_v2/hound_v2.glb">게임용 GLB</a><a href="../automation_batch2_v1/review.html">원화·Tripo 원본</a><a href="delivery_manifest.json">검증 기록</a></div>
<script>const notes=NOTES;const v=document.querySelector('#motion'),note=document.querySelector('#note');note.textContent=notes.run;document.querySelectorAll('[data-clip]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-clip]').forEach(x=>x.classList.toggle('selected',x===b));v.src=b.dataset.clip+'.mp4';v.playbackRate=+document.querySelector('#speed').value;v.play();note.textContent=notes[b.dataset.clip]});document.querySelector('#speed').onchange=e=>v.playbackRate=+e.target.value;document.querySelectorAll('[data-img]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-img]').forEach(x=>x.classList.toggle('selected',x===b));document.querySelector('#still').src=b.dataset.img});document.querySelector('#nativeToggle').onclick=()=>document.querySelector('#native').classList.toggle('actual');</script></main></html>'''
page=page.replace('TRIS',f"{geo['triangles']:,} tris").replace('BUTTONS',buttons).replace('CHECKS',f"{run['checks']:,}").replace('CAPTURES',str(run['captures'])).replace('NOTES',json.dumps(notes,ensure_ascii=False))
(OUT/'review.html').write_text(page,encoding='utf8')

paths=[]
local_captures={}
for folder in [BASE,GAME,OUT]:
    for p in folder.rglob('*'):
        if not p.is_file() or 'local' in p.parts or p.name.endswith('.blend1') or p.name in ('delivery_manifest.json','hound_static.glb'):continue
        if any(s.startswith(('motion_','poses_')) or s=='native_run' for s in p.parts):
            local_captures[p.relative_to(ROOT).as_posix()]=sha(p);continue
        paths.append(p)
for name in ['inspect_hound_joints_v2.py','build_hound_game_v2.py','animate_hound_game_v2.py','export_hound_game_v2.py','review_hound_geometry_v2.py','validate_hound_game_v2.py','finish_hound_authoring_v2.py','package_hound_game_v2.py']:
    paths.append(ROOT/'tools'/name)
paths += [ROOT/'game/tests/review_hound_game_v2.gd',ROOT/'assets/actors/automation_batch2/ART_REQUEST.md']
manifest={'date':'2026-11-05','passed':True,'stage':production['stage'],'production':'../../assets/actors/automation_batch2/hound_game_v2/production.json',
 'source_hashes':original,'runtime_checks':run['checks'],'gpu_captures':run['captures'],'scope_limits':production['limits'],
 'local_capture_frames':{'not_required_for_offline_review':True,'count':len(local_captures),'sha256':local_captures},
 'files':{p.relative_to(ROOT).as_posix():{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(set(paths))}}
write(OUT/'delivery_manifest.json',manifest)
missing=[]
for link in re.findall(r'(?:href|src)="([^"]+)"',page):
    if link.startswith(('http','#')):continue
    if not (OUT/link).exists():missing.append(link)
assert not missing,missing
print('HOUND_PACKAGE_PASS',len(paths),'files',count,'bone origins, max error m',max_error)
