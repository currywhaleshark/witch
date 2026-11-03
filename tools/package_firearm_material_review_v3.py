"""Package the current-input material review without changing game behavior."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'reports/firearm_material_v3';S=ROOT/'assets/weapons/firearm_material_v3';G=ROOT/'game/assets/weapons/firearm_material_v3'
LABELS={'matchlock':'화승총','rifle':'강선 장총','shotgun':'산탄총'}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return p.relative_to(ROOT).as_posix()

def main():
    models=read(S/'models.json');qa=read(R/'asset_qa.json');art=read(R/'material_test.json');cap=read(R/'review/capture.json')
    assert art['passed'] and cap['passed'] and read(R/'uv_intersections.json')['passed']
    assert read(R/'export_validation.json')['passed'] and read(R/'geometry_preservation.json')['passed']
    assert all(q['passed'] for stages in qa.values() for q in stages.values())
    regressions={}
    for key in ['firearm_matchlock','firearm_rifle']:
        rows=(R/(key+'.console.log')).read_text(encoding='utf-8-sig').splitlines()
        data=next(json.loads(x) for x in rows if x.startswith('{"checks"'))
        assert not data['failures'];(R/(key+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        regressions[key]={'passed':True,'checks':len(data['checks'])}
    shotgun=read(R/'shotgun_cast.json');assert shotgun['passed'];regressions['shotgun_cast']={'passed':True,'checks':shotgun['checks']}
    preserved={}
    for p,h in read(R/'baseline.json').items():
        if p in ['game/scripts/floating_gun.gd','game/scripts/shotgun_cast.gd']:continue
        assert sha(ROOT/p)==h,p
        preserved[p]=h
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',25)
    sheet=Image.new('RGB',(1500,390),'#101b23');draw=ImageDraw.Draw(sheet)
    compare=Image.new('RGB',(1500,370),'#101b23');cd=ImageDraw.Draw(compare)
    cards=[]
    for i,(key,label) in enumerate(LABELS.items()):
        im=Image.open(R/f'review/model_{key}.jpg').resize((500,320),Image.Resampling.LANCZOS)
        sheet.paste(im,(i*500,55));draw.text((i*500+20,14),label,font=font,fill='#e5efeb')
        im=Image.open(R/f'review/compare_{key}.jpg').resize((500,320),Image.Resampling.LANCZOS)
        compare.paste(im,(i*500,48));cd.text((i*500+16,10),label+' · 위: 이전 / 아래: 수정',font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',21),fill='#e5efeb')
        cards.append(f'<article><h2>{label}</h2><a href="review/model_{key}.jpg"><img src="review/model_{key}.jpg" alt="{label} 재질 수정"></a><details><summary>이전 재질과 비교</summary><a href="review/compare_{key}.jpg"><img src="review/compare_{key}.jpg" alt="같은 형상과 조명에서 비교"></a><p>위: 이전 / 아래: 수정 · 같은 형상·조명·배율</p></details></article>')
    sheet.save(R/'showcase.jpg',quality=94);compare.save(R/'comparison.jpg',quality=94)
    # Reuse the already-reviewed local sequence player, with the material-specific copy.
    old=(ROOT/'reports/firearm_tree_v2/review.html').read_text(encoding='utf-8')
    old=old.replace('화기 비율 수정 v2','화기 재질 수정 v3').replace('WITCH / FIREARM PROPORTIONS / 02','WITCH / FIREARM MATERIALS / 03')
    old=re.sub(r'<h1>.*?</h1><p>.*?</p></header>',
        '<h1>닳은 황동과 목재, 검게 처리한 총열</h1><p>선택한 길고 날씬한 비율을 유지하며 표면을 다듬었습니다. 화승총의 목재 결, 장총과 산탄총의 남색 도장, 황동의 변색과 가장자리 마모를 구분했습니다. 시험판에도 연결했습니다.</p></header>',old,count=1)
    old=re.sub(r'<section class="grid">.*?</section>','<section class="grid">'+''.join(cards)+'</section>',old,count=1)
    start=old.index('<details><summary>원본 및 검증</summary>');end=old.index('</details></main>',start)+len('</details>')
    notes=f'<details><summary>원본 및 검증</summary><p>세 총의 59개 부품·12,936삼각형과 총구·조립 순서는 유지했습니다. 1K 색/노멀, 512 ORM, 256 발광 텍스처를 세 총이 공유합니다. 재질·부품 검사 {art["checks"]}개, 기존 화기 검사 {sum(x["checks"] for x in regressions.values())}개와 GPU 캡처 {cap["captures"]}장을 확인했습니다.</p><p>기존 평면 캡·숨은 접합면·UV/노멀 경계 중복 정점은 유지합니다. 방아쇠 울의 UV 겹침은 수정했고 전체 아틀라스를 삼각형 교차로 검사했습니다. 마모는 고정 텍스처이며 실시간 손상이나 최종 성능 검증은 아닙니다.</p><a href="../../assets/weapons/firearm_material_v3/README.md">원본 안내</a> · <a href="delivery_manifest.json">검증 기록</a></details>'
    old=old[:start]+notes+old[end:]
    (R/'review.html').write_text(old,encoding='utf-8')
    scripts=re.findall(r'<script>(.*?)</script>',old,re.S);js=R/'review_script_check.js';js.write_text('\n'.join(scripts),encoding='utf-8')
    subprocess.run(['node','--check',str(js)],check=True,capture_output=True)
    frames=sorted((R/'review').rglob('*.jpg'));assert len(frames)==cap['captures']
    inputs=[S/'firearm_material_v3.blend',S/'models.json',S/'README.md',*S.glob('textures/*.png'),*S.glob('exports/*.glb'),*G.glob('*.glb'),*G.glob('*.json'),*G.glob('*.glb.import'),*G.glob('textures/*')]
    inputs += [ROOT/x for x in ['AGENTS.md','docs/godot_prototype.md','tools/build_firearm_material_v3.py','tools/qa_firearm_material_v3.py','tools/check_firearm_material_uv_v3.py','tools/package_firearm_material_assets_v3.py','tools/package_firearm_material_review_v3.py','game/scripts/floating_gun.gd','game/scripts/shotgun_cast.gd','game/tests/firearm_material_v3.gd','game/tests/review_firearm_material_v3.gd','game/tests/review_firearm_tree_v1.gd','game/tests/shotgun_cast.gd']]
    evidence=[R/x for x in ['asset_qa.json','material_test.json','export_validation.json','geometry_preservation.json','uv_intersections.json','texture_inventory.json','review/capture.json','review.html','showcase.jpg','comparison.jpg']]
    manifest={'date':'2026-11-03','status':'Material revision for user review; v2 proportions selected by user',
        'blender':'5.1.1; live MCP 1.8 protocol 15','models':art['models'],'parts':59,'triangles':12936,'asset_checks':art['checks'],
        'regressions':regressions,'captures':len(frames),'texture_sizes':{'color':1024,'normal':1024,'orm':512,'emission':256},
        'runtime_texture_sharing_verified':True,'uncompressed_RGBA8_full_mip_estimate_MiB':12.333333,
        'qa':qa,'preserved':preserved,'inputs':{rel(p):sha(p) for p in inputs},'evidence':{rel(p):sha(p) for p in evidence},'capture_hashes':{rel(p):sha(p) for p in frames},
        'accepted_warnings':['Planar cap n-gons are retained in editable source; export uses its exact triangle tessellation.',
            'Airborne muzzle-zero origins intentionally extend below local Y zero.',
            'Separate closed assembly pieces retain hidden opposite-facing contact surfaces.',
            'UV and normal seams require duplicate vertices after GLB reimport.',
            'Export sampler reuse warnings refer to identical linear/repeat image nodes.'],
        'limits':['Fixed authored wear; no dynamic damage material.','No new arbitrary wall/character-contact or final performance claim.','V3 material selection remains pending.'],
        'environment_diagnostics':(R/'gpu_review.err').read_text(encoding='utf-8-sig')}
    (R/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for link in re.findall(r'(?:href|src)=["\']([^"\']+)',old):
        if not link.startswith(('http:','https:','data:','#')):assert (R/link).exists(),link
    print(json.dumps({'material_checks':art['checks'],'regressions':sum(x['checks'] for x in regressions.values()),'captures':len(frames),'preserved_files':len(preserved)}))
if __name__=='__main__':main()
