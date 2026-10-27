"""Package the actual captured game models and reproducible handoff."""
import json,hashlib,html
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/combat_set_v1';OUT=ROOT/'reports/combat_actors_v1'
NAMES={'rag':'그을음 넝마귀','crow':'전선 까마귀','brute':'철문 아귀','automaton':'태엽인형','turret':'자동포탑'}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
production=read(BASE/'production.json');glb=read(OUT/'glb_validation.json');runtime=read(OUT/'runtime/result.json');capture=read(OUT/'review/capture.json')
assert glb['passed'] and runtime['passed'] and capture['passed']
source=[]
for spec in production['assets']:
    actor=spec['id'];item={'id':actor,'name':NAMES[actor],'tripo_job':spec['source_job'],'files':{}}
    for p in [BASE/'source'/f'{actor}_tripo_h31_raw.glb',BASE/'source'/f'{actor}_tripo_h31_raw.blend',BASE/'authoring'/f'{actor}_v1.blend',BASE/'exports'/f'{actor}_v1.glb',ROOT/'assets/reference/actors/combat_set_v1'/f'{actor}_concept_v1.png']:
        item['files'][p.relative_to(ROOT).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size}
    source.append(item)
regressions=[]
for name in ['enemy_types','boss','grades_hits','smoke_arena']:
    execution=read(OUT/name/'execution.json');assert execution['exit_code']==0
    regressions.append({'name':name,**execution})
manifest={'status':'integrated_review_candidate','art_approved':False,'source_scenario':production['source_scene'],
    'style':production['summon_style'],'assets':source,'glb_validation':glb,'runtime_validation':runtime,
    'regressions':regressions,'capture_count':sum(s['frames'] for s in capture['sequences'])+2,
    'execution':{p:read(OUT/p/'execution.json') for p in ['import','runtime','review']},
    'limitations':['Initial authored motions, not final art/animation approval.','Large local edge stretches still exist at some fused joints; see build/*/deformation.json. No arbitrary-pose or performance-budget approval.','Known workspace user:// shader/editor cache diagnostics are recorded; runtime and renderer checks exited 0.']}
manifest['code_sha256']={p:sha(ROOT/p) for p in ['game/scripts/actor_visual.gd','game/scripts/shapes.gd','game/scripts/arena.gd','game/scripts/combat_rules.gd','game/data/trial.json','game/scripts/player_visual.gd','game/tests/combat_actors.gd','game/tests/review_combat_actors.gd','tools/build_combat_actors_v1.py']}
manifest['baseline_note']='Integration preserves the concurrent boss commit 595e858; initial production.json game hashes predate that worker commit.'
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
production['status']='integrated_review_candidate';production['art_approved']=False;production['runtime_dir']='game/assets/actors/combat_set_v1';production['review']='reports/combat_actors_v1/review.html';production['validation']='reports/combat_actors_v1/delivery_manifest.json'
(BASE/'production.json').write_text(json.dumps(production,ensure_ascii=False,indent=2),encoding='utf-8')
prompt_path=ROOT/'assets/reference/actors/combat_set_v1/prompts.json';prompts=read(prompt_path);prompts['status']='concepts_used_for_completed_tripo_models';prompt_path.write_text(json.dumps(prompts,ensure_ascii=False,indent=2),encoding='utf-8')
rows=''.join(f'<tr><td>{NAMES[f["id"]]}</td><td>{f["triangles"]:,}</td><td>{f["bones"]}</td><td>{len(f["animations"])}</td></tr>' for f in glb['files'])
concepts=''.join(f'<figure><img src="../../assets/reference/actors/combat_set_v1/{a}_concept_v1.png"><figcaption>{name}</figcaption></figure>' for a,name in NAMES.items())
data=json.dumps({'names':NAMES,'sequences':capture['sequences']},ensure_ascii=False)
page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>몬스터·소환물 5종 — 게임 연결 v1</title>
<style>:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#151c21;color:#e9eee9;font:16px/1.65 system-ui,'Malgun Gothic',sans-serif}main{max-width:1120px;margin:auto;padding:40px 24px}h1{font-size:32px;margin:8px 0}h2{font-size:23px;margin-top:42px}p{color:#b9c9c8;max-width:880px}a{color:#8fdbc8}.eyebrow{color:#c6a66c;letter-spacing:.15em;font-size:13px}.hero{width:100%;border:1px solid #3b4e52;border-radius:12px}figure{margin:0}.concepts{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}.concepts img{width:100%;border-radius:8px}figcaption{font-size:14px;margin:6px 0;color:#c4d3d2}.viewer{display:grid;grid-template-columns:minmax(300px,512px) 1fr;gap:28px;background:#202b31;padding:20px;border-radius:12px}.viewer img{width:100%;background:#314243}.controls{display:flex;flex-direction:column;gap:14px}label{font-size:14px;color:#a7c6c0}select,button{background:#2a4146;color:#fff;border:1px solid #58726f;border-radius:6px;padding:10px;font:inherit}button{cursor:pointer}input{width:100%;accent-color:#91d2c2}.note{border-left:3px solid #b99b63;padding:12px 18px;background:#242b30}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #35464b;text-align:left;padding:10px}.links{display:flex;gap:20px;flex-wrap:wrap}small{color:#aebfbd}@media(max-width:760px){.viewer{grid-template-columns:1fr}.concepts{grid-template-columns:repeat(2,1fr)}main{padding:24px 16px}}</style>
<main><div class="eyebrow">WITCH · COMBAT ACTORS · V1</div><h1>몬스터 3종과 태엽 소환물</h1><p>시나리오 초안 6장의 넝마귀·전선 까마귀·철문 아귀, 그리고 낡은 황동·청록의 태엽인형·자동포탑입니다. 실제 Tripo 모델을 경량화하고 현재 전투 시험판에 연결했습니다.</p>
<h2>선택한 1.75배 카메라에서</h2><img class="hero" src="review/native_lineup.png" alt="게임 카메라에서 마녀와 다섯 모델의 크기 비교"><p>왼쪽부터 넝마귀, 까마귀, 철문 아귀, 태엽인형, 포탑. 1280×800 실제 게임 캡처이며 페이지 폭에 맞춰 축소 표시됩니다. <a href="review/native_lineup.png" target="_blank">원래 해상도로 보기</a></p>
<h2>동작 확인</h2><div class="viewer"><img id="frame" alt="실제 Godot 동작 캡처"><div class="controls"><label>종류 <select id="actor"></select></label><label>동작 <select id="clip"></select></label><label>속도 <select id="speed"><option value="1">1배</option><option value="0.5">0.5배</option></select></label><button id="play">일시정지</button><input id="scrub" type="range" min="0" max="16" step="1" value="0"><small id="counter"></small><p>확대 화면도 실제 게임 자산과 동일한 재질·관절·애니메이션을 사용합니다. 공격 판정은 기존 전투 시계가 정하며, 포탑의 실제 조준은 상부 관절만 회전시킵니다.</p></div></div>
<h2>현재 전투 화면</h2><img class="hero" src="review/gameplay.png" alt="새 몬스터와 소환물이 연결된 현재 전투 시험판">
<h2>모델링에 사용한 원화</h2><div class="concepts">CONCEPTS</div>
<h2>게임용 자산</h2><table><thead><tr><th>종류</th><th>삼각형</th><th>뼈</th><th>클립</th></tr></thead><tbody>ROWS</tbody></table><p>원본 GLB와 2K 텍스처를 별도 보존했습니다. 게임용은 1K PBR 텍스처, 최대 4개 뼈 영향, 합계 TOTAL개 삼각형입니다.</p>
<p class="note">첫 연결본입니다. 원본이 붙어 있는 일부 관절의 접힘·늘어남은 남아 있습니다. 현재 클립을 실제 표시 크기로 확인한 상태이며, 최종 아트 승인·임의 자세 검증·최종 성능 예산 확정은 별도입니다.</p>
<p>GPU 런타임 CHECKS개 검사, 25개 클립·반복 끝점·타격 시점·일시정지·사망 처리와 적 종류/보스/등급·피해/기본 실행 회귀를 확인했습니다. 기존 공격력·마나·이동 속도·충돌·AI 규칙은 유지합니다.</p><div class="links"><a href="delivery_manifest.json">검증·원본 해시</a><a href="../../assets/actors/combat_set_v1/README.md">다음 작업 인계</a><a href="tripo_completion.png">Tripo 생성 증빙</a></div></main>
<script>const data=DATA;const a=document.querySelector('#actor'),c=document.querySelector('#clip'),img=document.querySelector('#frame'),scrub=document.querySelector('#scrub'),counter=document.querySelector('#counter');const names={idle:'대기',move:'이동',attack:'공격',charge:'돌진',hit:'피격',death:'쓰러짐'};let sequence,playing=true,elapsed=0,previous=performance.now();for(const[id,n]of Object.entries(data.names)){a.add(new Option(n,id))}function show(i){scrub.value=i;img.src='review/'+sequence.folder+'/'+String(i).padStart(3,'0')+'.png';counter.textContent=(i+1)+' / '+sequence.frames+' 프레임 · '+sequence.seconds.toFixed(2)+'초 원본'}function select(){sequence=data.sequences.find(s=>s.actor===a.value&&s.clip===c.value);elapsed=0;for(let i=0;i<sequence.frames;i++){let p=new Image;p.src='review/'+sequence.folder+'/'+String(i).padStart(3,'0')+'.png'}show(0)}function actor(){c.innerHTML='';for(const s of data.sequences.filter(s=>s.actor===a.value))c.add(new Option(names[s.clip]||s.clip,s.clip));c.value=c.querySelector('option[value="move"]')?'move':'idle';select()}a.onchange=actor;c.onchange=select;document.querySelector('#play').onclick=()=>{playing=!playing;document.querySelector('#play').textContent=playing?'일시정지':'재생'};scrub.oninput=()=>{playing=false;document.querySelector('#play').textContent='재생';show(Number(scrub.value))};function tick(now){if(playing&&sequence){elapsed+=(now-previous)/1000*Number(document.querySelector('#speed').value);show(Math.floor(elapsed%sequence.seconds/sequence.seconds*16))}previous=now;requestAnimationFrame(tick)}actor();requestAnimationFrame(tick);</script></html>'''
page=page.replace('CONCEPTS',concepts).replace('ROWS',rows).replace('TOTAL',f'{glb["total_triangles"]:,}').replace('CHECKS',str(runtime['checks'])).replace('DATA',data)
(OUT/'review.html').write_text(page,encoding='utf-8')
print('COMBAT_ACTORS_PACKAGE_COMPLETE',glb['total_triangles'],runtime['checks'],manifest['capture_count'])
