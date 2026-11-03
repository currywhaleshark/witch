"""Package current-input firearm source, runtime validation and the local art review."""
from pathlib import Path
import hashlib
import json
import subprocess
from html import escape
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/firearm_tree_v1'
SOURCE=ROOT/'assets/weapons/firearm_tree_v1'
GAME=ROOT/'game/assets/weapons/firearm_tree_v1'
LABELS={'matchlock':'화승총','rifle':'강선 장총','shotgun':'산탄총','powder_barrel':'화약통',
        'gatling':'회전 기관포','smoke_launcher':'연막 발사기','artillery_shell':'포격용 포탄',
        'naval_shell':'함포용 포탄','smoke_canister':'연막탄'}
DESCRIPTIONS={
    'matchlock':'긴 단총열 · 화승 장치 · 목재 개머리판',
    'rifle':'긴 정밀 총열 · 조준경 · 남색 몸체',
    'shotgun':'짧고 굵은 쌍총열 · 기존 조립/발사에 연결',
    'powder_barrel':'가로로 굴리는 몸통 · 8구간 심지 · 분리되는 판재',
    'gatling':'6개 총열 · 총열 묶음만 회전 · 고정 급탄 드럼',
    'smoke_launcher':'전차식 6관 발사기 · 개별 발사 연결점',
    'artillery_shell':'작은 포격용 탄체 · 황동 띠',
    'naval_shell':'큰 함포용 탄체 · 청록 식별 띠',
    'smoke_canister':'발사관에서 분리해서 쓸 수 있는 연막탄',
}

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def rel(path): return path.relative_to(ROOT).as_posix()
def git(*args): return subprocess.check_output(['git',*args],cwd=ROOT)

def main():
    models=read(SOURCE/'models.json'); qa=read(REPORT/'asset_qa.json')
    art=read(REPORT/'art_test.json'); capture=read(REPORT/'review/capture.json')
    assert art['passed'] and capture['passed']
    assert all(v[s]['passed'] for v in qa.values() for s in ('source','reimport'))
    regressions={}
    for name in ('firearm_matchlock','firearm_rifle'):
        rows=(REPORT/(name+'.console.log')).read_text(encoding='utf-8-sig').splitlines()
        result=next(json.loads(line) for line in rows if line.startswith('{"checks"'))
        assert not result['failures']
        regressions[name]={'passed':True,'checks':len(result['checks'])}
        (REPORT/(name+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    shotgun=read(REPORT/'shotgun_cast.json');assert shotgun['passed']
    regressions['shotgun_cast']={'passed':True,'checks':shotgun['checks']}
    # Source and review duplicates are never exported: one asset scene per runtime GLB.
    stats={'models':len(models),'parts':sum(x['part_count'] for x in models.values()),
           'triangles':sum(x['triangles'] for x in models.values()),
           'glb_bytes':sum(p.stat().st_size for p in GAME.glob('*.glb')),'new_texture_files':0}
    preserved={}
    for path in ['game/assets/actors/shotgun_cast_v1/shotgun_parts.glb',
                 'game/assets/actors/shotgun_cast_v1/parts.json','game/data/trial.json',
                 'game/scripts/player_visual.gd','game/scripts/shotgun_geometry.gd','game/scripts/summon_assembly.gd']:
        p=ROOT/path
        if not p.exists(): continue
        old=git('show','HEAD:'+path)
        # Text compare ignores checkout EOL conversion; binary compare is exact.
        current=p.read_bytes()
        same=current==old if p.suffix=='.glb' else current.replace(b'\r\n',b'\n')==old.replace(b'\r\n',b'\n')
        preserved[path]={'unchanged_from_head':same,'sha256':digest(p),'comparison':'byte' if p.suffix=='.glb' else 'LF-normalized text'}
        assert same,path
    font_path='C:/Windows/Fonts/malgun.ttf'
    font=ImageFont.truetype(font_path,24); small=ImageFont.truetype(font_path,17)
    sheet=Image.new('RGB',(1440,1110),'#101b23'); draw=ImageDraw.Draw(sheet)
    for i,id in enumerate(LABELS):
        x=(i%3)*480;y=(i//3)*370
        im=Image.open(REPORT/f'review/models/{id}.jpg').convert('RGB');im.thumbnail((468,292))
        sheet.paste(im,(x+(480-im.width)//2,y+7))
        draw.text((x+19,y+303),LABELS[id],font=font,fill='#eff2ed')
        suffix='게임 연결' if id in ('matchlock','rifle','shotgun') else '준비 자산'
        draw.text((x+19,y+339),f'{suffix}  ·  {models[id]["part_count"]} 부품  ·  {models[id]["triangles"]:,} tris',font=small,fill='#93acae')
    sheet.save(REPORT/'lineup.jpg',quality=94)
    sequences=capture['sequences']
    for s in sequences:
        id=s['asset'];kind=s['kind']
        s['label']=LABELS[id]+' · '+('게임 / 실제 크기' if s.get('native') else '게임 / 확대') if kind=='actual_game' else LABELS[id]+' · 조립/작동 예시'
    ordered=sorted(sequences,key=lambda s:(s['kind']!='actual_game',list(LABELS).index(s['asset']),not s.get('native',False)))
    cards=[]
    for id,label in LABELS.items():
        item=models[id];status='게임 연결' if id in ('matchlock','rifle','shotgun') else '준비 자산'
        cards.append(f'<article><a href="review/models/{id}.jpg"><img loading="lazy" src="review/models/{id}.jpg" alt="{label}"></a><div class="cardbody"><small>{status}</small><h3>{label}</h3><p>{DESCRIPTIONS[id]}</p><div class="metric">{item["part_count"]} 부품 · {item["triangles"]:,} tris <a href="review/models/{id}_side.jpg">옆모습 ↗</a></div></div></article>')
    page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>화기 트리 — 모델링 v1</title>
<style>*{box-sizing:border-box}body{margin:0;background:#0d171e;color:#e5eeeb;font-family:"Malgun Gothic",sans-serif}main{max-width:1320px;margin:0 auto;padding:48px 28px 80px}header{border-bottom:1px solid #33464d;padding-bottom:26px;margin-bottom:28px}.eyebrow{letter-spacing:.15em;color:#94b5ac;font-size:12px}h1{font-size:38px;margin:14px 0}header p{line-height:1.8;color:#b2c6c5;max-width:930px}.tag{display:inline-block;background:#203b3c;color:#bce5d5;padding:6px 11px;margin:6px 5px 0 0;font-size:13px;border-radius:4px}.player{background:#15252e;border:1px solid #334950;border-radius:12px;padding:18px;margin:30px 0}.toolbar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:14px}button,select{background:#243c44;color:#e4eeeb;border:1px solid #456067;padding:9px 13px;border-radius:5px;font:inherit}select{max-width:100%}input{accent-color:#9bcbbb}#frame{width:100%;aspect-ratio:1.6;object-fit:contain;background:#0b1217;display:block;border-radius:5px}.timeline{display:flex;gap:12px;margin-top:14px;align-items:center}#seek{flex:1}.note{font-size:13px;color:#a9bfc0;line-height:1.7}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}article{background:#172830;border:1px solid #32484f;border-radius:10px;overflow:hidden}article img{width:100%;display:block}.cardbody{padding:16px 18px 20px}.cardbody small{color:#9bd1bc}h3{font-size:21px;margin:9px 0}.cardbody p{color:#b9c8c8;font-size:14px;min-height:40px;line-height:1.7}.metric{font-size:12px;color:#849c9f;display:flex;justify-content:space-between}a{color:#b3d5d0}h2{font-size:24px;margin:32px 0 18px}details{margin-top:30px;padding:18px;border:1px solid #32464e;line-height:1.9;color:#a9bbbe}summary{cursor:pointer;color:#cfe0dc}code{color:#dfc392}footer{margin-top:28px;color:#6f898f;font-size:12px}@media(max-width:850px){.grid{grid-template-columns:repeat(2,1fr)}h1{font-size:30px}main{padding:28px 16px}}@media(max-width:520px){.grid{grid-template-columns:1fr}}</style>
<main><header><div class="eyebrow">WITCH / FIREARM TREE / MODEL STUDY 01</div><h1>화기 트리 모델링</h1><p>화승총·강선 장총·산탄총은 시험판의 전용 모델로 교체했습니다. 화약통·회전 기관포·연막 발사기는 조립과 구동에 사용할 독립 부품으로 준비했습니다. 포격·함포는 탄체만 제작했습니다.</p><span class="tag">9종</span><span class="tag">3종 게임 연결</span><span class="tag">Blender MCP 제작</span><span class="tag">황동 · 남색 · 청록</span></header>
<section class="player"><div class="toolbar"><select id="sequence"></select><button id="play">일시정지</button><select id="speed"><option value="1">1×</option><option value=".5">0.5×</option><option value=".25">0.25×</option></select></div><img id="frame" alt="화기 모델 동작 검토"><div class="timeline"><input id="seek" type="range" min="0" value="0" step="1"><span id="time"></span></div><p id="description" class="note"></p></section>
<h2>모델 9종</h2><section class="grid">__CARDS__</section>
<details><summary>검증 및 다음 연결을 위한 자료</summary><p>9종 Blender 원본 및 GLB 재반입 검사 통과. 새 자산 검사 734개, 기존 화승총·장총·산탄총 검사 __REGRESSIONS__개 통과. GPU 검토 이미지 __CAPTURES__장. 총 __TRIANGLES__삼각형 / __PARTS__부품, 신규 텍스처 없음.</p><p>미구현 스킬의 조립·회전·굴림·발사·부품 비산은 이 페이지의 독립적인 시각 예시입니다. 스킬 수치, 물리 충돌, 연막의 시야 차단, 포격 판정은 아직 연결하지 않았습니다. 반동 도약은 기존 산탄총 자산을 재사용할 수 있습니다.</p><p>단순 PBR 재질의 모델 시안입니다. 표면 마모 텍스처, 성능 예산, 사용자 최종 외형 승인은 별도입니다. 정적 평면 끝막음 n-gon, 공중 자산의 총구/탄두 원점, GLB UV·노멀 경계 중복 정점은 용도를 확인하여 허용했습니다. GPU 셰이더 캐시/에디터 설정 경로 진단은 검증 로그에 남겼습니다.</p><a href="../../assets/weapons/firearm_tree_v1/README.md">원본·부품 계약 안내</a> · <a href="delivery_manifest.json">검증 기록</a></details><footer>2026-11-03 · Prototype review candidate · Original Blender-authored assets</footer></main>
<script>const seqs=__SEQUENCES__;let selected=0,frame=0,playing=true,last=0,acc=0;const q=document.getElementById('sequence'),img=document.getElementById('frame'),seek=document.getElementById('seek'),play=document.getElementById('play');seqs.forEach((s,i)=>{let o=document.createElement('option');o.value=i;o.textContent=s.label;q.append(o)});function draw(){let s=seqs[selected];img.src='review/'+s.id+'/'+String(frame).padStart(3,'0')+'.jpg';seek.value=frame;document.getElementById('time').textContent=(frame/s.fps).toFixed(2)+'s / '+((s.frames-1)/s.fps).toFixed(2)+'s'}function choose(){selected=+q.value;frame=0;acc=0;seek.max=seqs[selected].frames-1;let s=seqs[selected];document.getElementById('description').textContent=s.kind==='actual_game'?'실제 시험판의 조립·발사 장면입니다. 캐릭터와 기존 전투 규칙은 유지했습니다.':'준비 자산의 조립·작동 미리보기입니다. 화약통의 굴림/심지/비산, 기관포 회전, 연막탄 분리는 후속 스킬 연결을 위한 예시입니다.';draw()}q.onchange=choose;play.onclick=()=>{playing=!playing;play.textContent=playing?'일시정지':'재생'};seek.oninput=()=>{frame=+seek.value;playing=false;play.textContent='재생';draw()};function tick(now){let dt=Math.min((now-last)/1000,.1);last=now;if(playing){let s=seqs[selected];acc+=dt*Number(document.getElementById('speed').value);if(acc>=1/s.fps){frame=(frame+Math.floor(acc*s.fps))%s.frames;acc%=1/s.fps;draw()}}requestAnimationFrame(tick)}choose();requestAnimationFrame(tick);</script></html>'''
    count=sum(x['checks'] for x in regressions.values())
    page=page.replace('__CARDS__',''.join(cards)).replace('__SEQUENCES__',json.dumps(ordered,ensure_ascii=False))
    page=page.replace('검사 734개','검사 '+str(art['checks'])+'개')
    page=page.replace('GPU 셰이더 캐시/에디터 설정 경로 진단은 검증 로그에 남겼습니다.',
                      'GPU 셰이더 캐시·에디터 설정 경로 진단과 전체 시작 준비를 포함한 리뷰 종료의 RefCounted 1개 경고는 검증 로그에 남겼습니다.')
    for key,value in {'REGRESSIONS':count,'CAPTURES':capture['captures'],'TRIANGLES':f'{stats["triangles"]:,}','PARTS':stats['parts']}.items(): page=page.replace('__'+key+'__',str(value))
    (REPORT/'review.html').write_text(page,encoding='utf-8')
    tracked_inputs=[SOURCE/'firearm_tree_v1.blend',SOURCE/'models.json',SOURCE/'README.md',ROOT/'AGENTS.md',ROOT/'docs/godot_prototype.md',
                    *GAME.glob('*.glb'),*GAME.glob('*.json'),*GAME.glob('*.glb.import')]
    tracked_inputs += [ROOT/p for p in ['tools/build_firearm_tree_v1.py','tools/qa_firearm_tree_v1.py','tools/package_firearm_tree_v1.py',
                    'game/scripts/arena.gd','game/scripts/floating_gun.gd','game/scripts/shotgun_cast.gd','game/scripts/asset_warmup.gd',
                    'game/tests/firearm_rifle.gd','game/tests/shotgun_cast.gd','game/tests/firearm_tree_art.gd',
                    'game/tests/helpers/firearm_tree_demo.gd','game/tests/helpers/firearm_review_world.gd','game/tests/review_firearm_tree_v1.gd']]
    inputs={rel(p):{'sha256':digest(p),'bytes':p.stat().st_size} for p in tracked_inputs if p.exists()}
    warnings={k:{stage:value['warnings'] for stage,value in v.items()} for k,v in qa.items()}
    evidence=[REPORT/'asset_qa.json',REPORT/'art_test.json',REPORT/'review/capture.json',REPORT/'review.html',REPORT/'lineup.jpg',
              *[REPORT/(name+'.json') for name in regressions]]
    screenshot_paths=sorted((REPORT/'review').rglob('*.jpg'))
    assert len(screenshot_paths)==capture['captures']
    manifest={'date':'2026-11-03','status':'integrated art review candidate, no new user selection',
              'head':git('rev-parse','HEAD').decode().strip(),'blender':'5.1.1 / live MCP addon 1.8 protocol 15',
              'authoring':'Live bpy-safe-mode modelling, explicit scene-per-asset export; separate saved-file and GLB-reimport QA',
              'stats':stats,'integration':['matchlock','rifle','shotgun'],
              'prepared_only':['powder_barrel','gatling','smoke_launcher','artillery_shell','naval_shell','smoke_canister'],
              'regressions':regressions,'asset_checks':art['checks'],'gpu_captures':len(screenshot_paths),
              'qa':{'source_and_reimport_all_passed':True,'warnings':warnings,
                    'accepted_reasons':['Source planar n-gon end caps are rigid, triangulated in exported GLBs.',
                                        'Floating guns and shells use muzzle/tip origins, intentionally below-ground local bounds.',
                                        'Reimport duplicate vertices encode UV/normal splits; no loose vertices.',
                                        'Shotgun hinge backs touch receiver with opposing hidden faces; closed separate parts retained for assembly.']},
              'preserved':preserved,'inputs':inputs,'evidence':{rel(p):digest(p) for p in evidence},
              'capture_hashes':{rel(p):digest(p) for p in screenshot_paths},
              'environment_diagnostics':['GPU: shader cache folder user:// unavailable; rendering completed.',
                                         'Editor import: cannot save editor settings to empty path; import completed.',
                                         'GPU warmup review exit: one RefCounted with reference count 0 reported by ObjectDB; no claim about live-game leak/performance.'],
              'limits':['Future skill effects are deterministic review helpers only, no new gameplay.',
                        'No live debris/terrain/wall collision, smoke vision obstruction, final performance budget or final art approval.',
                        'Simple solid PBR palette; unique baked wear textures are not part of this pass.']}
    (REPORT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'stats':stats,'asset_checks':art['checks'],'regression_checks':count,'captures':len(screenshot_paths)},ensure_ascii=False))

if __name__=='__main__': main()
