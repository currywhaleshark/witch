"""Publish the six prepared assets' local review and current-input delivery record."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'reports/firearm_material_v4';S=ROOT/'assets/weapons/firearm_material_v4';G=ROOT/'game/assets/weapons/firearm_material_v4'
LABELS={'powder_barrel':'심지 화약통','gatling':'회전기관포','smoke_launcher':'연막발사기','artillery_shell':'포격용 포탄','naval_shell':'함포용 포탄','smoke_canister':'독립 연막탄'}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return p.relative_to(ROOT).as_posix()

def main():
    models=read(S/'models.json');qa=read(R/'asset_qa.json');test=read(R/'material_test.json');capture=read(R/'review/capture.json')
    assert test['passed'] and capture['passed']
    for name in ['uv_intersections.json','uv_export_intersections.json','export_validation.json','geometry_preservation.json']:assert read(R/name)['passed']
    assert all(v['passed'] for stages in qa.values() for v in stages.values())
    baseline=read(R/'baseline.json')
    for name,digest in baseline.items():assert sha(ROOT/name)==digest,name
    catalogue={}
    for asset_id in ['matchlock','rifle','shotgun']+list(LABELS):
        folder='firearm_material_v4' if asset_id in LABELS else 'firearm_material_v3'
        data=read(ROOT/'game/assets/weapons'/folder/(asset_id+'.json'))
        catalogue[asset_id]={'model':'res://assets/weapons/'+folder+'/'+asset_id+'.glb','metadata':'res://assets/weapons/'+folder+'/'+asset_id+'.json',
            'status':'prepared_asset' if asset_id in LABELS else 'active_skill','parts':data['part_count'],'triangles':data['triangles']}
    (S/'catalog.json').write_text(json.dumps({'assets':catalogue,'scope':'Only the three existing gun skills are active; the other six are prepared assets.'},indent=2),encoding='utf-8')
    textures={}
    for p in (G/'textures').glob('*.png'):
        im=Image.open(p);textures[p.name]={'size':list(im.size),'bytes':p.stat().st_size,'sha256':sha(p)}
    (R/'texture_inventory.json').write_text(json.dumps(textures,indent=2),encoding='utf-8')
    sheet=Image.new('RGB',(1500,800),'#101b23');draw=ImageDraw.Draw(sheet);font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',25)
    cards=[]
    for i,(key,label) in enumerate(LABELS.items()):
        x=i%3*500;y=i//3*400
        photo=Image.open(R/f'review/models/{key}.jpg').resize((500,340),Image.Resampling.LANCZOS)
        sheet.paste(photo,(x,y+48));draw.text((x+20,y+12),label,font=font,fill='#e5efeb')
        buttons=''.join(f'<button data-asset="{key}" data-view="{suffix}">{text}</button>' for suffix,text in [('', '수정 재질'),('_before','이전 재질'),('_rear','뒷면')])
        cards.append(f'<article><h2>{label}</h2><a id="link-{key}" href="review/models/{key}.jpg"><img id="img-{key}" src="review/models/{key}.jpg" alt="{label}"></a><div class="buttons">{buttons}</div></article>')
    sheet.save(R/'showcase.jpg',quality=94)
    seq=capture['sequences']
    for s in seq:s['label']=LABELS[s['asset']]+' · '+{'powder_barrel':'조립 / 굴림 / 심지 / 비산','gatling':'조립 / 회전','smoke_launcher':'조립 / 탄체 발사'}[s['asset']]
    html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>나머지 화기 재질 v4</title>
<style>*{box-sizing:border-box}body{margin:0;background:#101b23;color:#e3eeea;font-family:"Malgun Gothic",sans-serif}main{max-width:1480px;margin:auto;padding:40px 26px 70px}.kicker{font-size:12px;letter-spacing:.14em;color:#a5c1b8}h1{font-size:34px;margin:12px 0}header p,.note{line-height:1.8;color:#afc6c1;max-width:1050px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin:28px 0}article,.player,.scale{background:#192a33;border:1px solid #354b53;border-radius:10px;overflow:hidden}article h2{font-size:22px;margin:16px}article img{display:block;width:100%}.buttons{display:flex;gap:8px;padding:12px;flex-wrap:wrap}button,select{background:#28434b;color:#e3eeea;border:1px solid #486269;border-radius:5px;padding:9px 12px;font:inherit;cursor:pointer}button:hover,button:focus-visible{background:#3a5c63}a{color:#b5daca}.player,.scale{padding:18px;margin-top:28px}.bar,.timeline{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:0 0 14px}#frame{display:block;width:100%;aspect-ratio:1000/680;object-fit:contain;background:#111b23}.timeline{margin:14px 0 0}input{flex:1;accent-color:#abd5c0}.note{font-size:13px;margin-bottom:0}.scale img{display:block;width:100%}.scale h2{margin-top:0}details{margin-top:26px;border-top:1px solid #354b53;padding-top:16px;font-size:13px;line-height:1.8;color:#a7bfbe}summary{cursor:pointer;color:#dceae3}@media(max-width:900px){.grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:600px){.grid{grid-template-columns:1fr}main{padding:24px 14px}h1{font-size:28px}}</style>
<main><header><div class="kicker">WITCH / FIREARM MATERIALS / 04</div><h1>나머지 여섯 자산도 같은 재질로</h1><p>화약통의 목재와 심지, 기관포·연막발사기의 금속과 남색 도장, 포탄과 연막탄의 식별 도장을 다듬었습니다. 아래 개별 사진은 확대 보기이며, 버튼으로 같은 조명에서 이전 재질과 비교할 수 있습니다.</p></header>
<section class="grid">__CARDS__</section>
<section class="player"><div class="bar"><select id="sequence" aria-label="작동 예시"></select><button id="play">일시정지</button><select id="speed" aria-label="재생 속도"><option value="1">1×</option><option value=".5">0.5×</option><option value=".25">0.25×</option></select></div><img id="frame" alt="준비 자산 작동 예시"><div class="timeline"><input id="seek" type="range" min="0" step="1" aria-label="프레임"><span id="time"></span></div><p class="note">후속 스킬 연결용 자산의 작동 예시입니다. 기존 조립·회전·굴림·심지 소모·분리 움직임을 새 재질로 확인합니다.</p></section>
<section class="scale"><h2>캐릭터 옆에서 보는 크기</h2><div class="bar"><button id="native">실제 게임 카메라</button><button id="close">확대</button></div><img id="scale" src="review/scale_native.jpg" alt="여섯 자산과 캐릭터 크기 비교"><p class="note">원래 크기의 자산을 게임 조명과 카메라에 정적으로 배치한 참고 화면입니다. 세 총은 선택한 v3로 유지되며, 이 여섯 자산의 신규 스킬 판정·효과 구현은 별도입니다.</p></section>
<details><summary>원본과 검증</summary><p>107개 독립 부품 / 28,640삼각형. 원본 형상·노멀·회전축·소켓 보존. 공통 1K 색/노멀 + 512 ORM + 256 발광 텍스처. 저장 원본과 재반입 QA 및 전체 UV 교차 검사 통과. 재질·리소스·동작 검사 __CHECKS__개, GPU 캡처 __CAPTURES__장.</p><p>정적 캡 n-gon, 공중 모델의 원점 높이, UV/노멀 경계 중복 정점은 유지했습니다. 고정 마모 표현이며 실제 충돌 물리·연막 규칙·최종 성능 검증은 아닙니다.</p><a href="../../assets/weapons/firearm_material_v4/README.md">편집 원본 안내</a> · <a href="../../assets/weapons/firearm_material_v4/catalog.json">전체 화기 자산 목록</a> · <a href="delivery_manifest.json">검증 기록</a> · <a href="../firearm_material_v3/review.html">선택한 세 총</a></details></main>
<script>const scenes=__SEQ__;const select=document.getElementById('sequence'),img=document.getElementById('frame'),seek=document.getElementById('seek'),btn=document.getElementById('play');let index=0,frame=0,playing=true,last=0,acc=0;scenes.forEach((s,i)=>{const o=document.createElement('option');o.value=i;o.textContent=s.label;select.append(o)});function draw(){const s=scenes[index];img.src='review/'+s.id+'/'+String(frame).padStart(3,'0')+'.jpg';seek.value=frame;document.getElementById('time').textContent=(frame/s.fps).toFixed(2)+' s'}function choose(){index=+select.value;frame=0;acc=0;seek.max=scenes[index].frames-1;draw()}select.onchange=choose;btn.onclick=()=>{playing=!playing;btn.textContent=playing?'일시정지':'재생'};seek.oninput=()=>{frame=+seek.value;playing=false;btn.textContent='재생';draw()};function tick(now){const dt=Math.min((now-last)/1000,.1);last=now;if(playing){const s=scenes[index];acc+=dt*Number(document.getElementById('speed').value);if(acc>=1/s.fps){frame=(frame+Math.floor(acc*s.fps))%s.frames;acc%=1/s.fps;draw()}}requestAnimationFrame(tick)}document.querySelectorAll('[data-asset]').forEach(b=>b.onclick=()=>{const path='review/models/'+b.dataset.asset+b.dataset.view+'.jpg';document.getElementById('img-'+b.dataset.asset).src=path;document.getElementById('link-'+b.dataset.asset).href=path});document.getElementById('native').onclick=()=>document.getElementById('scale').src='review/scale_native.jpg';document.getElementById('close').onclick=()=>document.getElementById('scale').src='review/scale_close.jpg';choose();requestAnimationFrame(tick);</script></html>'''
    html=html.replace('__CARDS__',''.join(cards)).replace('__SEQ__',json.dumps(seq,ensure_ascii=False)).replace('__CHECKS__',str(test['checks'])).replace('__CAPTURES__',str(capture['captures']))
    (R/'review.html').write_text(html,encoding='utf-8')
    js=R/'review_script_check.js';js.write_text('\n'.join(re.findall(r'<script>(.*?)</script>',html,re.S)),encoding='utf-8')
    subprocess.run(['node','--check',str(js)],check=True,capture_output=True)
    frames=sorted((R/'review').rglob('*.jpg'));assert len(frames)==capture['captures']
    for s in seq:
        for i in range(s['frames']):assert (R/'review'/s['id']/f'{i:03d}.jpg').is_file()
    inputs=[S/'firearm_material_v4.blend',S/'models.json',S/'README.md',S/'catalog.json',*S.glob('textures/*.png'),*S.glob('exports/*.glb'),*G.glob('*.glb'),*G.glob('*.json'),*G.glob('*.glb.import'),*G.glob('textures/*')]
    inputs += [ROOT/p for p in ['AGENTS.md','docs/godot_prototype.md','tools/build_firearm_material_v4.py','tools/qa_firearm_material_v4.py','tools/check_firearm_material_uv_v4.py','tools/package_firearm_material_assets_v4.py','tools/package_firearm_material_review_v4.py','game/tests/firearm_material_v4.gd','game/tests/review_firearm_material_v4.gd','game/tests/helpers/firearm_material_v4_demo.gd','game/tests/helpers/firearm_tree_demo.gd']]
    evidence=[R/x for x in ['asset_qa.json','material_test.json','export_validation.json','geometry_preservation.json','uv_intersections.json','uv_export_intersections.json','texture_inventory.json','review/capture.json','review.html','showcase.jpg']]
    if (S/'approval.json').exists(): inputs.append(S/'approval.json')
    manifest={'date':'2026-11-03','status':'Six prepared assets and v4 materials selected for prototype' if (S/'approval.json').exists() else 'Six remaining material candidates for user review; three-gun v3 selected',
        'blender':'5.1.1; live MCP addon 1.8 protocol 15','models':test['models'],'parts':107,'triangles':28640,'checks':test['checks'],'captures':len(frames),
        'runtime_state':'prepared assets only; no new active skills','shared_maps':test['shared_maps'],'uncompressed_RGBA8_full_mip_estimate_MiB':12.333333,
        'qa':qa,'preserved':baseline,'inputs':{rel(p):sha(p) for p in inputs},'evidence':{rel(p):sha(p) for p in evidence},'capture_hashes':{rel(p):sha(p) for p in frames},
        'accepted_warnings':['Planar source end caps retain n-gons; exact loop triangles are used for export.','Airborne muzzle/nose frames intentionally extend below local Y zero.','UV/normal seams require duplicate GLB vertices.','Identical linear/repeat image nodes share export samplers.'],
        'limits':['Fixed wear, not live damage.','Mechanism clips are review-only, not new gameplay.','No live debris/inter-part/wall physics, smoke-vision logic or final performance approval.'],
        'environment_diagnostics':(R/'gpu_review.err').read_text(encoding='utf-8-sig')}
    (R/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for link in re.findall(r'(?:href|src)=["\']([^"\']+)',html):
        if not link.startswith(('http:','https:','data:','#')):assert (R/link).exists(),link
    print(json.dumps({'checks':test['checks'],'captures':len(frames),'preserved_files':len(baseline),'parts':107,'triangles':28640}))
if __name__=='__main__':main()
