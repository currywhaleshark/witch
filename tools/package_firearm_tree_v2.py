"""Assemble the same-scale v1/v2 gun comparison and current-input validation record."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib

ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'reports/firearm_tree_v2';S=ROOT/'assets/weapons/firearm_tree_v2';G=ROOT/'game/assets/weapons/firearm_tree_v2'
LABELS={'matchlock':'화승총','rifle':'강선 장총','shotgun':'산탄총'}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def relative(p):return p.relative_to(ROOT).as_posix()

def main():
    new=read(S/'models.json');old=read(ROOT/'assets/weapons/firearm_tree_v1/models.json')
    qa=read(R/'asset_qa.json');art=read(R/'firearm_tree_v2.json');capture=read(R/'review/capture.json')
    assert art['passed'] and capture['passed']
    assert all(q['passed'] for stages in qa.values() for q in stages.values())
    regressions={}
    for id in ['firearm_matchlock','firearm_rifle']:
        lines=(R/(id+'.console.log')).read_text(encoding='utf-8-sig').splitlines()
        d=next(json.loads(line) for line in lines if line.startswith('{"checks"'))
        assert not d['failures'];(R/(id+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
        regressions[id]={'passed':True,'checks':len(d['checks'])}
    shotgun=read(R/'shotgun_cast.json');assert shotgun['passed']
    regressions['shotgun_cast']={'passed':True,'checks':shotgun['checks']}
    previous=read(ROOT/'reports/firearm_tree_v1/delivery_manifest.json')
    preserved={}
    paths=['assets/weapons/firearm_tree_v1/firearm_tree_v1.blend','game/scripts/arena.gd','game/scripts/asset_warmup.gd']
    paths += [relative(p) for p in (ROOT/'game/assets/weapons/firearm_tree_v1').glob('*.glb')]
    for path in paths:
        preserved[path]={'sha256':sha(ROOT/path),'unchanged':sha(ROOT/path)==previous['inputs'][path]['sha256']}
        assert preserved[path]['unchanged'],path
    for path,data in previous['preserved'].items():
        preserved[path]={'sha256':sha(ROOT/path),'unchanged':sha(ROOT/path)==data['sha256']}
        assert preserved[path]['unchanged'],path
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',24)
    small=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',17)
    sheet=Image.new('RGB',(1500,420),'#101b23');draw=ImageDraw.Draw(sheet)
    cards=[];metrics={}
    for i,(id,label) in enumerate(LABELS.items()):
        im=Image.open(R/f'review/compare_{id}.jpg');im=im.resize((500,320),Image.Resampling.LANCZOS)
        sheet.paste(im,(i*500,48))
        draw.text((i*500+18,12),label+'  ·  위: 이전 / 아래: 수정',font=font,fill='#e5efeb')
        before=old[id]['dimensions'];after=new[id]['dimensions']
        longer=(after[2]/before[2]-1)*100;lower=(1-after[1]/before[1])*100
        draw.text((i*500+18,384),f'길이 +{longer:.0f}%  ·  높이 {lower:.0f}% 감소',font=small,fill='#a8d8c2')
        metrics[id]={'before':before,'after':after,'longer_percent':longer,'lower_percent':lower,'parts':new[id]['part_count'],'triangles':new[id]['triangles']}
        cards.append(f'<article><h2>{label}</h2><a href="review/compare_{id}.jpg"><img src="review/compare_{id}.jpg" alt="{label} 이전과 수정 비교"></a><p>위: 이전 / 아래: 수정 · 총구 정렬, 같은 배율</p><strong>길이 +{longer:.0f}% · 높이 −{lower:.0f}%</strong><a class="detail" href="review/model_{id}.jpg">입체 모습 ↗</a></article>')
    sheet.save(R/'comparison.jpg',quality=94)
    seq=capture['sequences']
    for s in seq:s['label']=LABELS[s['asset']]+' · '+('실제 게임 크기' if s['native'] else '확대 보기')
    html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>화기 비율 수정 v2</title><style>*{box-sizing:border-box}body{margin:0;background:#101b23;color:#e3eeea;font-family:"Malgun Gothic",sans-serif}main{max-width:1440px;margin:auto;padding:40px 26px 70px}h1{font-size:34px;margin:12px 0}header p{line-height:1.8;color:#b1c6c4;max-width:950px}.kicker{color:#91b4ab;font-size:12px;letter-spacing:.15em}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:15px;margin:28px 0}article{background:#192a33;border:1px solid #354b53;border-radius:10px;overflow:hidden}article h2{font-size:22px;padding:0 16px}article img{display:block;width:100%}article p,article strong{font-size:13px;padding:0 16px}article p{color:#a8bfbe}article strong{display:block;margin-bottom:12px;color:#a6d5bb}a{color:#bedbd2}.detail{display:block;padding:0 16px 18px;font-size:13px}.player{padding:18px;background:#192a33;border-radius:10px;border:1px solid #354b53}.bar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:14px}select,button{padding:9px 12px;font:inherit;background:#29444b;color:#e5eeeb;border:1px solid #476269;border-radius:5px}#frame{display:block;width:100%;aspect-ratio:1.6;object-fit:contain;background:#0c151b}input{accent-color:#a6d5bb;flex:1}.timeline{display:flex;gap:15px;align-items:center;margin-top:14px}.note{font-size:13px;line-height:1.8;color:#a7bfbe}details{margin-top:24px;border-top:1px solid #354b53;padding-top:18px;font-size:13px;line-height:1.8;color:#9eb6b5}summary{cursor:pointer;color:#dceae3}@media(max-width:900px){.grid{grid-template-columns:1fr}main{padding:24px 16px}article img{max-height:520px;object-fit:contain}}</style>
<main><header><div class="kicker">WITCH / FIREARM PROPORTIONS / 02</div><h1>길고 날씬한 비율로 수정</h1><p>세 총의 총열과 개머리판 비율을 다시 잡았습니다. 화승총은 길게 뻗은 단총열, 장총은 낮은 조준경과 긴 정밀 총열, 산탄총은 길어진 쌍총열을 유지합니다. 수정본은 시험판에도 연결했습니다.</p></header><section class="grid">__CARDS__</section>
<section class="player"><div class="bar"><select id="sequence"></select><button id="play">일시정지</button><select id="speed"><option value="1">1×</option><option value=".5">0.5×</option><option value=".25">0.25×</option></select></div><img id="frame" alt="수정된 화기의 게임 조립과 사격"><div class="timeline"><input id="seek" type="range" min="0" step="1"><span id="time"></span></div><p class="note">실제 게임의 조립·사격 장면입니다. 총구 위치, 시전/발사 시간, 사거리와 전투 수치는 유지했습니다.</p></section>
<details><summary>원본 및 검증</summary><p>3종 저장 원본과 GLB 재반입 QA 통과. 부품/소켓/치수 검사 __ART__개, 기존 화기 검사 __REG__개 통과. GPU 검토 __CAP__장. v1 원본과 다른 여섯 준비 자산은 보존했습니다. 기본 PBR 재질이며 최종 외형/성능 승인은 별도입니다.</p><p>허용된 정적 캡/접합면, UV·노멀 경계와 환경 로그 진단은 전달 명세에 기록했습니다.</p><a href="../../assets/weapons/firearm_tree_v2/README.md">원본 안내</a> · <a href="delivery_manifest.json">검증 기록</a> · <a href="../firearm_tree_v1/review.html">이전 9종 리뷰</a></details></main>
<script>const scenes=__SEQ__;const select=document.getElementById('sequence'),img=document.getElementById('frame'),seek=document.getElementById('seek'),btn=document.getElementById('play');let index=0,frame=0,playing=true,last=0,acc=0;scenes.forEach((s,i)=>{let o=document.createElement('option');o.value=i;o.textContent=s.label;select.append(o)});function draw(){const s=scenes[index];img.src='review/'+s.id+'/'+String(frame).padStart(3,'0')+'.jpg';seek.value=frame;document.getElementById('time').textContent=(frame/s.fps).toFixed(2)+' s'}function choose(){index=+select.value;frame=0;acc=0;seek.max=scenes[index].frames-1;draw()}select.onchange=choose;btn.onclick=()=>{playing=!playing;btn.textContent=playing?'일시정지':'재생'};seek.oninput=()=>{frame=+seek.value;playing=false;btn.textContent='재생';draw()};function tick(now){const dt=Math.min((now-last)/1000,.1);last=now;if(playing){const s=scenes[index];acc+=dt*Number(document.getElementById('speed').value);if(acc>=1/s.fps){frame=(frame+Math.floor(acc*s.fps))%s.frames;acc%=1/s.fps;draw()}}requestAnimationFrame(tick)}choose();requestAnimationFrame(tick);</script></html>'''
    html=html.replace('__CARDS__',''.join(cards)).replace('__SEQ__',json.dumps(seq,ensure_ascii=False))
    for token,value in [('ART',art['checks']),('REG',sum(x['checks'] for x in regressions.values())),('CAP',capture['captures'])]:html=html.replace('__'+token+'__',str(value))
    (R/'review.html').write_text(html,encoding='utf-8')
    inputs=[S/'firearm_tree_v2.blend',S/'models.json',S/'README.md',*G.glob('*.glb'),*G.glob('*.json'),*G.glob('*.glb.import')]
    inputs += [ROOT/p for p in ['AGENTS.md','docs/godot_prototype.md','tools/build_firearm_tree_v2.py','tools/qa_firearm_tree_v2.py','tools/package_firearm_tree_v2.py',
                               'game/scripts/floating_gun.gd','game/scripts/shotgun_cast.gd','game/tests/shotgun_cast.gd',
                               'game/tests/firearm_tree_v2.gd','game/tests/review_firearm_tree_v2.gd','game/tests/review_firearm_tree_v1.gd']]
    captures=sorted((R/'review').rglob('*.jpg'));assert len(captures)==capture['captures']
    manifest={'date':'2026-11-03','status':'proportion revision / user review pending','blender':'5.1.1 / live MCP addon 1.8 protocol 15',
              'models':metrics,'triangles':sum(d['triangles'] for d in new.values()),'parts':sum(d['part_count'] for d in new.values()),
              'glb_bytes':sum(p.stat().st_size for p in G.glob('*.glb')),'asset_checks':art['checks'],'regressions':regressions,'captures':len(captures),
              'qa':qa,'preserved':preserved,'inputs':{relative(p):sha(p) for p in inputs},
              'evidence':{relative(p):sha(p) for p in [R/'asset_qa.json',R/'firearm_tree_v2.json',R/'review/capture.json',R/'review.html',R/'comparison.jpg']},
              'capture_hashes':{relative(p):sha(p) for p in captures},
              'accepted_warnings':['Rigid planar end caps use n-gons in source; exported GLBs triangulate them.',
                                   'Airborne gun muzzle origins give intentional negative local heights.',
                                   'UV/normal splits duplicate vertices on GLB reimport.',
                                   'Opposing hidden hinge/body contact faces keep individual assembly parts closed.'],
              'limits':['Simple PBR materials; no new wear texture or user art approval.',
                        'No universal aiming/character/wall clearance or final performance claim.'],
              'environment_diagnostics':(R/'gpu_review.err').read_text(encoding='utf-8-sig') if (R/'gpu_review.err').exists() else ''}
    (R/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'models':metrics,'asset_checks':art['checks'],'regression_checks':sum(d['checks'] for d in regressions.values()),'captures':len(captures)},ensure_ascii=False))

if __name__=='__main__':main()
