"""Publish the prepared drive models and their actual Godot capture review."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib, html

ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'reports/drive_tree_v1'; S=ROOT/'assets/weapons/drive_tree_v1'; G=ROOT/'game/assets/weapons/drive_tree_v1'
LABELS={'guillotine':'낙하 단두대','guillotine_saw':'단두대 · 회전 톱날','guillotine_lock':'단두대 · 고정',
 'restraint_winch':'구속 윈치','hydraulic_press':'유압 압착기','compound_executor':'복합 집행기',
 'shock_frame':'충격 흡수 프레임','exoskeleton':'외골격','broad_cutter':'광역 볼트커터'}
DETAILS={'guillotine':'가이드레일을 따라 떨어지는 칼날', 'guillotine_saw':'천천히 내려오는 회전 톱날',
 'guillotine_lock':'양쪽 고정턱이 닫힌 뒤 칼날 낙하', 'restraint_winch':'단일 갈고리 / 여러 줄 끌기 / 여러 줄 구속',
 'hydraulic_press':'넓은 압착판과 2단 피스톤', 'compound_executor':'문 닫기 → 압착 → 양쪽 회전 톱팔',
 'shock_frame':'등·어깨·정강이에 붙는 가벼운 완충 장치', 'exoskeleton':'등·팔·정강이 보조 프레임, 손·허벅지는 비움',
 'broad_cutter':'별도 대형 날과 강체 링크, 벌어짐 → 빠른 닫힘'}
MOTIONS={'assembly':'조립 → 유지 → 해제','idle':'대기','run':'달리기','attack':'휘두르기','attack_thrust':'찌르기',
 'cast':'캐스팅','hit_react':'경직','spring_jump':'스프링 점프','collapse':'쓰러짐'}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return p.relative_to(ROOT).as_posix()

def main():
    models=read(S/'models.json'); qa=read(R/'asset_qa.json'); test=read(R/'art_test.json'); cap=read(R/'review/capture.json'); fit=read(R/'equipment_fit.json')
    assert test['passed'] and cap['passed'] and read(R/'export_validation.json')['passed']
    assert all(x['passed'] for a in qa.values() for s in a.values() for x in s.values())
    baseline=read(R/'baseline.json'); changed=[p for p,h in baseline.items() if sha(ROOT/p)!=h]
    (R/'preservation.json').write_text(json.dumps({'passed':not changed,'files':len(baseline),'changed':changed},indent=2),encoding='utf-8')
    assert not changed,changed
    catalogue={a:{'name':LABELS[a],'model':'res://assets/weapons/drive_tree_v1/'+a+'.glb',
       'metadata':'res://assets/weapons/drive_tree_v1/'+a+'.json','scene':'DriveV1_'+a,'status':'prepared_asset',
       'parts':models[a]['part_count'],'triangles':models[a]['triangles'],'mechanism':DETAILS[a]} for a in LABELS}
    (S/'catalog.json').write_text(json.dumps({'assets':catalogue,'existing_reuse':{
      'staff_tools':'res://assets/weapons/staff_material_v3/','shield':'res://assets/props/folding_shield_v1/',
      'spring_dash':'res://assets/props/spring_dash_v1/'},'scope':'Prepared models and review-only mechanisms; no new active skills.'},ensure_ascii=False,indent=2),encoding='utf-8')
    textures={p.name:{'pixels':list(Image.open(p).size),'bytes':p.stat().st_size,'sha256':sha(p)} for p in (G/'textures').glob('*.png')}
    (R/'texture_inventory.json').write_text(json.dumps(textures,indent=2),encoding='utf-8')
    adjudication={
      'geometry_errors':0,
      'intentional_uv_overlap':'Planar charts reuse the eight authored trim tiles. No unique texture bake is claimed.',
      'planar_ngons':'Flat hard-surface caps remain editable; exported mesh uses exact Blender loop triangles.',
      'seam_duplicates':'glTF split normals/UVs produce duplicate positions on reimport; source topology is retained.',
      'raised_origins':'Body equipment and staff head retain their attachment coordinate frame, not a ground pivot.',
      'enclosed_column_collars':'Two rear collars per press/executor are internal mounting pieces; not loose external parts.',
      'hidden_back_faces':'Blade/runner contacts and hydraulic tube seam faces are retained for independently assembled parts.',
      'group_scope':'Equipment source/reimport QA is grouped by attachment bone; detached body-mounted components are intentional.',
      'equipment_contact':{'poses':fit['pose_count'],'poses_with_garment_crossings':fit['poses_with_crossings'],
        'clear_motion_samples':['idle','run','hit_react'],'remaining':'Mostly thrust; also swing, cast, transformed jump and collapse.',
        'excluded':'Hair, bare body, arbitrary poses and continuous collision.'}}
    (R/'qa_adjudication.json').write_text(json.dumps(adjudication,ensure_ascii=False,indent=2),encoding='utf-8')
    # Every card uses a real engine capture, never a concept render.
    sheet=Image.new('RGB',(1500,1200),'#111e28'); draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',24); small=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',15)
    cards=[]
    for i,(a,label) in enumerate(LABELS.items()):
        suffix='_transformed_rear' if a=='shock_frame' else '_transformed' if a=='exoskeleton' else ''
        path=f'review/models/{a}{suffix}.jpg'; im=Image.open(R/path); im.thumbnail((500,340),Image.Resampling.LANCZOS)
        x=i%3*500;y=i//3*400;sheet.paste(im,(x+(500-im.width)//2,y+48));draw.text((x+18,y+10),label,font=font,fill='#edf4f0')
        draw.text((x+18,y+375),f"{models[a]['part_count']} 부품 · {models[a]['triangles']:,} 삼각형",font=small,fill='#aebfc8')
        views=[(suffix,'앞/전체'),(suffix+'_rear' if a not in ['shock_frame','exoskeleton'] else '_transformed_rear','뒷면')]
        if a in ['shock_frame','exoskeleton']:views=[('_transformed','변신복'),('_transformed_rear','등판'),('_civilian','평상복'),('_transformed_native','실제 표시 크기')]
        elif a=='broad_cutter':views+=[('_equipped','장착'),('_equipped_side','장착 옆면')]
        else:views+=[('_native','실제 표시 크기')]
        buttons=''.join(f'<button data-card="{a}" data-suffix="{s}">{t}</button>' for s,t in views)
        cards.append(f'<article><h2>{label}</h2><a id="link-{a}" href="{path}"><img id="img-{a}" src="{path}" alt="{label}" loading="lazy"></a><p>{DETAILS[a]}</p><div class="buttons">{buttons}</div></article>')
    sheet.save(R/'showcase.jpg',quality=94)
    sequences=cap['sequences']
    for s in sequences:
        s['label']=LABELS[s['asset']]+' · '+({'single':'한 줄 당기기','pull':'여러 줄 당기기','bind':'여러 줄 구속','base':'조립 → 작동 → 소멸'}.get(s.get('variant')) or MOTIONS[s['motion']])
    options=''.join(f'<option value="{a}">{label}</option>' for a,label in LABELS.items())
    fit_table=[]
    for form,label in [('civilian','평상복'),('transformed','변신복')]:
        for motion,motion_label in MOTIONS.items():
            if motion=='assembly':continue
            rows=[r for r in fit['poses'] if r['form']==form and r['motion']==motion]
            count=sum(bool(r['crossing_faces']) for r in rows)
            fit_table.append(f'<tr><td>{label}</td><td>{motion_label}</td><td class="{"warn" if count else "good"}">{count} / {len(rows)}</td></tr>')
    page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>구동 트리 · 준비 모델 v1</title><style>
:root{color-scheme:dark;font:16px/1.65 "Malgun Gothic",sans-serif;background:#101a22;color:#dce8e8}body{max-width:1500px;margin:auto;padding:32px}h1{font-size:38px;margin:0}h2{font-size:20px;margin:0 0 10px}p{color:#b5c9cd}a{color:#9ee0d1}button,select{font:inherit;background:#283c48;color:#f1f6f1;border:1px solid #4c626c;padding:7px 13px;border-radius:6px;cursor:pointer}button:hover{background:#3a5664}.buttons{display:flex;gap:7px;flex-wrap:wrap}header,.viewer,details{margin-bottom:28px}.tag{color:#8fdbcd;letter-spacing:.13em}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}article,.viewer,details{background:#192a35;border:1px solid #30434e;border-radius:12px;padding:18px}article img{width:100%;aspect-ratio:1.42;object-fit:contain;background:#101a22}article p{min-height:54px}#motion-image{width:100%;max-height:700px;object-fit:contain;background:#101a22}input[type=range]{width:100%;accent-color:#8fdcc9}.toolbar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:12px 0}#status{min-height:28px}.warn{color:#f2bb7d}.good{color:#9fd5ba}table{border-collapse:collapse;margin:12px 0}td,th{text-align:left;border-bottom:1px solid #40505a;padding:6px 22px 6px 0}.note{font-size:14px}summary{cursor:pointer;font-weight:bold}footer{padding:20px 0;color:#93a9b4}@media(max-width:950px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:650px){body{padding:15px}main{grid-template-columns:1fr}h1{font-size:28px}}
</style><header><div class="tag">WITCH / DRIVE TREE / 2026.11.03</div><h1>구동 장치 9종</h1><p>남색 강철 · 낡은 황동 · 청록 동력 코어. 조립과 작동을 위한 부품 분할, 회전축, 부착 본을 준비했습니다.</p><p>현재 화면은 새 모델의 검토 시안입니다. 신규 스킬의 피해·시전·적 구속 규칙은 아직 게임에 연결하지 않았습니다.</p></header>
<section class="viewer"><h2>조립과 움직임</h2><div class="toolbar"><select id="asset">__OPTIONS__</select><select id="form"><option value="transformed">변신복</option><option value="civilian">평상복</option></select><select id="motion"></select></div><img id="motion-image" alt="실제 Godot 동작 캡처"><input id="frame" type="range" min="0" value="0" step="1"><div class="toolbar"><button id="play">재생</button><button id="restart">처음부터</button><label>속도 <select id="speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option></select></label><span id="clock"></span></div><div id="status"></div><p class="note">장치는 검토용 조립 → 작동 → 소멸 순서입니다. 장착 모션은 현재 캐릭터 클립을 13개 시점으로 나눠 보여 주며 실제 전투 재생 시간과 다를 수 있습니다.</p></section>
<main>__CARDS__</main><details style="margin-top:25px"><summary>외골격의 의상 간섭 검사</summary><p>두 의상 × 8개 모션 × 13개 시점, 총 __POSES__개 실제 엔진 포즈를 사용했습니다. 엄격한 삼각형 교차가 있는 자세는 __CROSS__개입니다. 대기·달리기·경직은 검사한 시점에서 통과했고, 찌르기 등 팔을 몸 앞으로 모으는 자세에는 소매 관통이 남아 있습니다. 해당 모션을 선택하면 문제 시점이 표시됩니다.</p><table><thead><tr><th>의상</th><th>모션</th><th>관통 자세 / 검사 수</th></tr></thead><tbody>__FIT_TABLE__</tbody></table><p class="note">이 검사는 옷과 외골격 사이의 표면 교차입니다. 머리카락·맨몸·임의 포즈·연속 충돌 검사는 포함하지 않습니다. 충격 흡수 프레임은 외골격의 등·어깨·정강이 부품만 사용하는 별도 시안입니다.</p></details>
<details><summary>크기·재질·검증 범위</summary><p>장치 옆 캐릭터는 현재 1.5m 게임 캐릭터입니다. ‘실제 표시 크기’는 선택한 1.75× 카메라와 1280×800 캡처를 사용하며 사진을 클릭하면 원본 크기로 확인할 수 있습니다.</p><p>총 244개 강체 부품 / 50,204개 삼각형. 공통 색 1K·노멀 1K·ORM 512·발광 256. 저장 Blender와 GLB 재반입의 형상 QA 및 __CHECKS__개 런타임 검사를 통과했습니다. __CAPTURES__장 GPU 캡처를 생성했습니다. 반복 트림 UV·평면 캡·숨은 접합면·GLB 경계 중복 정점은 기록된 허용 사항입니다.</p><p>작동 시각은 검토용 값입니다. 장치와 적의 접촉, 케이블 충돌, 지형/벽 배치, 최종 성능과 전투 밸런스는 이번 검토 대상에 포함되지 않습니다.</p></details>
<footer><a href="../../assets/weapons/drive_tree_v1/README.md">원본·연결 안내</a> · <a href="../../assets/weapons/drive_tree_v1/catalog.json">모델 목록</a> · <a href="equipment_fit.json">의상 검사</a> · <a href="delivery_manifest.json">전달 명세</a></footer>
<script>
const SEQUENCES=__SEQUENCES__, FIT=__FIT__, LABELS=__LABELS__;
const asset=document.querySelector('#asset'),form=document.querySelector('#form'),motion=document.querySelector('#motion'),frame=document.querySelector('#frame'),pic=document.querySelector('#motion-image'),play=document.querySelector('#play'),clock=document.querySelector('#clock'),status=document.querySelector('#status'),speed=document.querySelector('#speed');
let seq=null,running=false,elapsed=0,last=0;
function draw(){let n=Number(frame.value);pic.src=`review/${seq.id}/${String(n).padStart(3,'0')}.jpg`;clock.textContent=`${n+1} / ${seq.frames}`;status.className='';status.textContent='';if(seq.asset==='exoskeleton' && seq.motion!=='assembly'){let r=FIT.find(x=>x.form===seq.form&&x.motion===seq.motion&&Math.abs(x.phase-n/12)<.001);let parts=r?Object.keys(r.crossing_faces):[];status.className=parts.length?'warn':'good';status.textContent=parts.length?'소매 교차가 남은 시점 · '+parts.join(', '):'이 시점에서 옷과 프레임 교차 없음';}}
function choose(){seq=SEQUENCES.find(s=>s.id===motion.value);frame.max=seq.frames-1;frame.value=0;elapsed=0;draw();}
function populate(){let equipment=['exoskeleton','shock_frame'].includes(asset.value);form.hidden=!equipment;motion.replaceChildren();for(let s of SEQUENCES.filter(s=>s.asset===asset.value&&(!equipment||s.form===form.value))){let o=document.createElement('option');o.value=s.id;o.textContent=s.label;motion.append(o);}choose();}
asset.onchange=populate;form.onchange=populate;motion.onchange=choose;frame.oninput=()=>{running=false;play.textContent='재생';draw();};play.onclick=()=>{running=!running;play.textContent=running?'일시정지':'재생';};document.querySelector('#restart').onclick=()=>{frame.value=0;elapsed=0;draw();};
for(let b of document.querySelectorAll('[data-card]'))b.onclick=()=>{let path=`review/models/${b.dataset.card}${b.dataset.suffix}.jpg`;document.querySelector('#img-'+b.dataset.card).src=path;document.querySelector('#link-'+b.dataset.card).href=path;};
function tick(now){if(running&&seq){elapsed+=Math.min(.1,(now-last)/1000)*Number(speed.value);let duration=1/seq.fps;if(elapsed>=duration){let step=Math.floor(elapsed/duration);elapsed-=step*duration;frame.value=(Number(frame.value)+step)%seq.frames;draw();}}last=now;requestAnimationFrame(tick);}populate();requestAnimationFrame(tick);
</script></html>'''
    tokens={'OPTIONS':options,'CARDS':''.join(cards),'FIT_TABLE':''.join(fit_table),'POSES':str(fit['pose_count']),
       'CROSS':str(fit['poses_with_crossings']),'CHECKS':f"{test['checks']:,}",'CAPTURES':f"{cap['captures']:,}",
       'SEQUENCES':json.dumps(sequences,ensure_ascii=False),'FIT':json.dumps(fit['poses']), 'LABELS':json.dumps(LABELS,ensure_ascii=False)}
    for k,v in tokens.items():page=page.replace('__'+k+'__',v)
    (R/'review.html').write_text(page,encoding='utf-8')
    inventory={rel(p):sha(p) for p in sorted((R/'review').rglob('*.jpg'))}
    assert len(inventory)==cap['captures'],(len(inventory),cap['captures'])
    (R/'capture_inventory.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    deliverables=[p for p in S.rglob('*') if p.is_file() and p.suffix!='.blend1']+[p for p in G.rglob('*') if p.is_file()]
    deliverables+=list((ROOT/'tools').glob('*drive*v1.py'))+[ROOT/'game/tests/helpers/drive_tree_demo.gd',ROOT/'game/tests/drive_tree_art.gd',ROOT/'game/tests/review_drive_tree_v1.gd']
    # Record the imported character/pose inputs separately from the new assets.
    dependency_dirs=['run_arm_v21','model_refinement_v28','hand_rebuild_v29','transformation_v25','transformation_v26','transformation_v27','spring_jump_v24']
    dependencies=[p for directory in dependency_dirs for p in (ROOT/'game/assets/characters/player'/directory).glob('*') if p.is_file() and p.suffix in ['.glb','.import','.json']]
    dependencies += [ROOT/'game/tests/review_firearm_tree_v1.gd',ROOT/'game/tests/helpers/firearm_review_world.gd',ROOT/'game/scripts/summon_assembly.gd',R/'rest_frames.json']
    evidence=[R/n for n in ['asset_qa.json','qa_adjudication.json','export_validation.json','art_test.json','equipment_fit.json','preservation.json','texture_inventory.json','capture_inventory.json','review/capture.json','review/poses.json','review.html','showcase.jpg']]
    manifest={'version':'drive_tree_v1','date':'2026-11-03','status':'prepared art and mechanism review; user selection pending',
      'tools':{'blender':'5.1.1','mcp':'1.8 protocol 15, live safe mode','godot':'4.6.2 Compatibility, RTX 2060'},
      'models':len(models),'parts':sum(v['part_count'] for v in models.values()),'triangles':sum(v['triangles'] for v in models.values()),
      'checks':test['checks'],'gpu_captures':cap['captures'],'sampled_garment_poses':fit['pose_count'],'poses_with_garment_crossings':fit['poses_with_crossings'],
      'preserved_baseline_files':len(baseline),'source_and_outputs':{rel(p):sha(p) for p in sorted(set(deliverables+evidence))},
      'unchanged_dependencies':{rel(p):sha(p) for p in sorted(set(dependencies))},
      'qa_run_scope':'All seven standalone props passed final_qa2; the two equipment models were rerun in equipment_final_qa after their last geometry/binding edits.',
      'diagnostics':['Godot user shader cache unavailable; captures rendered successfully.','Editor settings could not be saved in this environment.','Background Blender Tripo addon reports a WebSocket shutdown timeout after completed work.'],
      'limits':['No new active skill implementation or balance changes.','26 of 208 sampled exoskeleton poses retain garment crossings; mostly thrust.','No hair/body/continuous contact test or arbitrary terrain/wall clearance.','Review mechanisms have no enemy interaction or live rigid-body physics.','Shared planar trim textures, not unique bakes; draw-call and peak GPU performance unmeasured.']}
    (R/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('DRIVE_REVIEW_PACKAGED',manifest['models'],manifest['parts'],manifest['triangles'],manifest['gpu_captures'])

if __name__=='__main__':main()
