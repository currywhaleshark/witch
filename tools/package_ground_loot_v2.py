"""Build the complete loot review from actual engine captures and verified outputs."""
import hashlib,html,json,subprocess
from pathlib import Path
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/ground_loot_v2'
data=json.loads((ROOT/'assets/props/ground_loot_v2/models.json').read_text(encoding='utf-8'))
runtime=json.loads((OUT/'runtime.json').read_text(encoding='utf-8'))
assets=json.loads((OUT/'asset_validation.json').read_text(encoding='utf-8'))
items=json.loads((ROOT/'game/data/items.json').read_text(encoding='utf-8'))
trial=json.loads((ROOT/'game/data/trial.json').read_text(encoding='utf-8'))
qa=json.loads((OUT/'source_qa.json').read_text(encoding='utf-8'))
assert not runtime['failures'] and not assets['failures']
assert all(x['pass'] for g in qa.values() for x in g.values())
names={x['id']:x['name'] for x in items['bases']+items['uniques']}
names.update({k:v['name'] for k,v in trial['potions'].items()})
names.update({k:v['name'] for k,v in items['pieces'].items()})
names['currency']=items['currency']['name']
old={r['id'] for r in data['preserved_v1']}
records={r['id']:r for r in data['assets']+data['preserved_v1']}
for mode in ('material','wire'):
    sheet=Image.new('RGB',(1750,1350),'#14242c');draw=ImageDraw.Draw(sheet)
    for i,row in enumerate(data['assets']):
        im=Image.open(OUT/'authoring'/(row['id']+'_'+mode+'_three_quarter.png')).convert('RGB')
        im.thumbnail((244,244));x=(i%7)*250;y=(i//7)*270
        sheet.paste(im,(x+3,y+2));draw.text((x+7,y+246),row['id'],fill='#ffffff')
    sheet.save(OUT/('authoring_'+mode+'_sheet.jpg'),quality=92)

sheet=Image.new('RGB',(1820,1620),'#14242c');draw=ImageDraw.Draw(sheet)
(OUT/'thumbnails').mkdir(exist_ok=True)
for i,id in enumerate(runtime['scope']):
    im=Image.open(OUT/'details'/(id+'.png')).convert('RGB').crop((320,80,960,720))
    im.thumbnail((250,245));x=i%7*260;y=i//7*270
    im.save(OUT/'thumbnails'/(id+'.jpg'),quality=93)
    sheet.paste(im,(x+5,y+2));draw.text((x+8,y+248),id,fill='#ffffff')
sheet.save(OUT/'game_catalogue.jpg',quality=93)

categories={'mediums':'매개체·설계도','machines':'기계 부품·고유','clothing':'의상·장갑·신발','jewelry':'머리장식·장신구','health':'체력 물약','mana':'마나 물약','recovery':'회복·이동 물약','resources':'각인전·이름 조각'}
cards=[]
for group,ids in runtime['groups'].items():
    for id in ids:
        icon='../../game/assets/ui/inventory_v1/'+id+'.png'
        reference='<img class="icon" loading="lazy" src="'+icon+'" alt="인벤토리 그림">' if id not in ['currency','bel','rok','sha'] else '<span class="icon resource">각인·문양</span>'
        cards.append('<article data-group="'+group+'"><div class="caption"><strong>'+html.escape(names[id])+'</strong><span>'+('기존 v1 보존' if id in old else '신규')+'</span></div><div class="comparison">'+reference+'<a href="details/'+id+'.png"><img loading="lazy" class="model" src="thumbnails/'+id+'.jpg" alt="'+html.escape(names[id])+' 실제 게임 모델"></a></div><small>'+id+' · '+format(records[id]['triangles'],',')+' tris</small></article>')
options=''.join('<option value="'+k+'">'+v+'</option>' for k,v in categories.items())
page='''<!doctype html>
<html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>전리품 모델 · 전체 39종</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#101c23;color:#e6ebe5;font:16px/1.65 system-ui,sans-serif}main{max-width:1320px;margin:auto;padding:32px 24px 80px}h1{font-size:30px;margin:0}h2{font-size:21px;margin:34px 0 12px}p,small{color:#aebfc5}a{color:#dcbc80}select,button{font:inherit;padding:7px 13px;background:#223840;color:#ecf1ec;border:1px solid #45616b;border-radius:5px}button{cursor:pointer}button.active{border-color:#e0be7d;color:#f0d398}.controls{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0}.shot{width:100%;height:auto;display:block;border:1px solid #3b515a}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.cards article{background:#172b34;padding:14px;border:1px solid #304851;border-radius:8px}.caption{display:flex;justify-content:space-between;gap:10px}.caption span{font-size:12px;color:#c4a875;white-space:nowrap}.comparison{display:flex;align-items:center;height:180px;gap:8px;overflow:hidden}.comparison a{width:72%;height:170px;overflow:hidden;display:block}.model{width:100%;height:100%;object-fit:cover;object-position:center}.icon{width:27%;height:115px;object-fit:contain}.resource{font-size:12px;text-align:center}.muted{font-size:14px}.stat{display:inline-block;padding:7px 12px;background:#233942;color:#dfc69a;margin:10px 5px 0 0;border-radius:5px}details{margin-top:24px}summary{cursor:pointer;color:#dfc69a}[hidden]{display:none!important}@media(max-width:850px){.cards{grid-template-columns:repeat(2,1fr)}}@media(max-width:550px){.cards{grid-template-columns:1fr}main{padding:22px 12px}}
</style><main>
<h1>전리품 모델 · 전체 39종</h1>
<p>장비 22종 · 물약 13종 · 각인전과 이름 조각 4종. 기존에 선택한 4종을 보존하고 나머지 35종을 추가했습니다.</p>
<span class="stat">새 모델 35종</span><span class="stat">새 모델당 1메시 · 최대 3재질</span><span class="stat">기존 낙하·클릭 획득 유지</span>
<h2>실제 골목에서 보기</h2>
<p class="muted">기본 크기는 현재 게임의 1.75배 카메라입니다. 확대는 같은 시점·조명의 2.7배이며, 적은 비교 화면 밖으로 옮겼습니다.</p>
<div class="controls"><select id="group">OPTIONS</select><button data-state="native" class="active">기본 크기</button><button data-state="detail">2.7배 확대</button><button data-state="launch">낙하 시작</button><button data-state="tumble">회전 중</button><button data-state="hidden">라벨 숨김</button><button data-state="hover">선택 강조</button></div>
<img class="shot" id="preview" src="mediums_native.png" alt="선택한 전리품의 실제 게임 화면">
<p class="muted" id="order"></p>
<h2>인벤토리 그림과 모델 비교</h2><p class="muted">왼쪽은 기존 인벤토리 그림, 오른쪽은 게임에서 촬영한 바닥 모델입니다. 모델을 누르면 큰 원본을 볼 수 있습니다. 착용용 캐릭터 파츠가 아닌 바닥 전리품입니다.</p>
<div class="controls"><button id="all">전체 보기</button><button id="only">선택한 종류만</button></div>
<div class="cards">CARDS</div>
<details><summary>전체 모델·편집 원본과 검증</summary><p><a href="game_catalogue.jpg">게임 모델 전체 표</a> · <a href="authoring_material_sheet.jpg">Blender 제작본</a> · <a href="authoring_wire_sheet.jpg">와이어 검사</a> · <a href="delivery_manifest.json">검증 기록</a> · <a href="../../assets/props/ground_loot_v2/README.md">제작·인계 안내</a></p><p class="muted">반투명 유리 대신 불투명 색과 하이라이트로 구분합니다. 기존 고정 낙하 연출을 사용하며 임의 벽·계단 충돌이나 대량 드롭 성능을 새로 보증하지 않습니다. 중형·대형 물약은 기본 시점에서 단계별 크기가 커지는지 확인했습니다.</p></details>
</main><script>
const groups=GROUPS,names=NAMES;let state='native',filter=false;const select=document.getElementById('group');
function update(){document.getElementById('preview').src=select.value+'_'+state+'.png';document.getElementById('order').textContent='왼쪽부터: '+groups[select.value].map(x=>names[x]).join(' · ');document.querySelectorAll('[data-state]').forEach(b=>b.classList.toggle('active',b.dataset.state===state));document.querySelectorAll('article').forEach(c=>c.hidden=filter&&c.dataset.group!==select.value)}
select.onchange=update;document.querySelectorAll('[data-state]').forEach(b=>b.onclick=()=>{state=b.dataset.state;update()});document.getElementById('all').onclick=()=>{filter=false;update()};document.getElementById('only').onclick=()=>{filter=true;update()};update();
</script></html>
'''.replace('OPTIONS',options).replace('CARDS',''.join(cards)).replace('GROUPS',json.dumps(runtime['groups'],ensure_ascii=False)).replace('NAMES',json.dumps(names,ensure_ascii=False))
(OUT/'review.html').write_text(page,encoding='utf-8')

regressions={}
for name,file in [('ground_loot','report.json'),('loot_resources','resources.json'),('items','result.json')]:
    result=json.loads((OUT/'regressions'/name/file).read_text(encoding='utf-8'))
    assert not result['failures'],name
    regressions[name]=len(result['checks'])
execution=json.loads((OUT/'runtime/execution.json').read_text(encoding='utf-8'))
assert execution['exit_code']==0 and not execution['changed_inputs']
current=json.loads((OUT/'runtime/inputs_after.json').read_text(encoding='utf-8'))
assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in current.items()),'Inputs changed after GPU review'
protected=json.loads((OUT/'protected_inputs.json').read_text(encoding='utf-8'))
preservation={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in protected.items()}
# The shared label script has the documented precision correction; other protected inputs stay exact.
assert all(ok for p,ok in preservation.items() if p!='game/scripts/ground_loot.gd')
warnings={id:{group:row['warnings'] for group,row in result.items() if row['warnings']} for id,result in qa.items()}
manifest={'date':'2026-11-02','user_request':'전리품 모델 마저 만들게','status':'integrated_review_candidate',
    'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
    'new_models':len(data['assets']),'preserved_models':len(old),'total_models':len(runtime['scope']),
    'new_triangles':data['total_new_triangles'],'all_triangles':sum(r['triangles'] for r in records.values()),
    'new_glb_bytes':sum(p.stat().st_size for p in (ROOT/'game/assets/props/ground_loot_v2').glob('*.glb')),
    'asset_checks':len(assets['checks']),'runtime_checks':len(runtime['checks']),'regressions':regressions,'captures':len(runtime['captures']),
    'protected_inputs_preserved':preservation,'current_inputs':current,
    'source_qa_warnings':warnings,'warning_adjudication':{
        'ground_z':'Intentionally centered tumble pivot, not bottom pivot. Runtime rest_height places actual minimum vertices 12mm above the floor; checked in Blender and Godot.',
        'ngons':'Planar end caps and static slab faces; exported triangles counted and reimported. These are not deforming meshes.',
        'uv_overlap':'Orb_claw.001 smart UVs have a raster overlap warning. Color is an explicit constant vertex attribute, with no image/bake lookup; UVs require separate refinement before future unique texture baking.',
        'back_to_back':'Five cape/collar and five key/bridge hidden triangle pairs retained to keep the independent closed authoring pieces. No visible same-facing z-fighting; no topology errors.',
        'paired_parts':'Left/right shoes and gloves are intentional paired props. Each connected glove or shoe is independently passed to the unmodified QA game profile; global runtime dimensions and spacing cover the whole pair.'},
    'label_fix':'previous.rect.position + (anchor - previous.anchor), subtracting anchors first. Removes the measured 0.000031px drift at unchanged authored support heights without changing label layout rules.',
    'diagnostics':'Godot GPU logs retain the known shader-cache user:// warning; editor import retains the settings-save diagnostic. Final engine processes exit 0; no gameplay script errors in final runtime/regressions.',
    'limits':['Opaque bottles rather than transparent volume glass','Existing cosmetic tumble; no new rigid-body or arbitrary terrain/wall contact simulation','No final mass-drop performance or new user art approval']}
approval=ROOT/'assets/props/ground_loot_v2/approval.json'
if approval.exists():
    manifest['status']=json.loads(approval.read_text(encoding='utf-8'))['status']
    manifest['approval']=approval.relative_to(ROOT).as_posix()
    manifest['limits'][-1]='No final mass-drop performance approval'
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PACKAGED',manifest['total_models'],'models;',manifest['asset_checks']+manifest['runtime_checks']+sum(regressions.values()),'checks;',manifest['captures'],'captures')
