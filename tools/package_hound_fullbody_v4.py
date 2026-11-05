"""Portable offline whole-body comparison and exact input/output receipts."""
import json,gzip,hashlib,math,shutil,subprocess
from pathlib import Path
from html.parser import HTMLParser
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/hound_fullbody_v4';ASSETS=ROOT/'assets/actors/automation_batch2'
def read(p):return json.loads(p.read_text(encoding='utf8'))
def dump(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def base(a):return ASSETS/('hound_game_v4' if a=='hound' else 'hound_armour_v3')
def sheet(paths,dest,columns=3,width=400,height=250):
 im=Image.new('RGB',(columns*width,math.ceil(len(paths)/columns)*height),'#18252e')
 for i,p in enumerate(paths):
  tile=Image.open(p).convert('RGB');tile.thumbnail((width,height));im.paste(tile,((i%columns)*width+(width-tile.width)//2,(i//columns)*height+(height-tile.height)//2))
 im.save(dest,quality=92)
motion=read(OUT/'motion_validation.json');assert motion['passed'];h=motion['results']['hound']
validation={};warnings={};sourceposes=runtimechecks=0
for a in ['hound','hound_armour']:
 runtime=read(OUT/a/'runtime/runtime_validation.json');assert runtime['passed'];runtimechecks+=runtime['checks']
 for name in ['source_qa','reimport_qa','saved_source','reimport']:
  q=read(OUT/a/'validation'/f'{name}.json');assert q.get('pass',q.get('passed',False)),(a,name)
  if name.endswith('_qa'):warnings[a+'/'+name]=q['warnings']
  if name=='saved_source':sourceposes+=q['poses']
 expected=json.loads(gzip.decompress((base(a)/'animation_samples.json.gz').read_bytes()));observed=read(OUT/a/'runtime/runtime_poses.json');err=0.;count=0
 for row in observed:
  ref=min(expected[row['clip']],key=lambda x:abs(x['time']-row['time']));assert abs(ref['time']-row['time'])<1e-6
  for n,p in row['bones'].items():
   x,y,z=np.array(ref['world'][n])[:3,3];err=max(err,float(np.linalg.norm(np.array(p)-[x,z,-y])));count+=1
 assert err<.00003,(a,err)
 validation[a]={'passed':True,'bone_origins':count,'maximum_error_m':err}
 dump(OUT/a/'validation/godot_pose_parity.json',validation[a])

capture=read(OUT/'comparison/runtime_validation.json');assert capture['passed'];dump(OUT/'capture_receipt.json',capture)
(OUT/'videos').mkdir(exist_ok=True);videos={}
for name in ['side','front','rear','armour','native','travel']:
 dest=OUT/'videos'/f'{name}.mp4'
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-framerate','60','-i',str(OUT/'comparison'/name/'%03d.jpg'),'-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(dest)],check=True)
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=width,height,nb_frames,r_frame_rate','-show_entries','format=duration','-of','json',str(dest)],text=True));assert int(probe['streams'][0]['nb_frames'])==120
 videos[name]=probe;shutil.copy2(OUT/'comparison'/name/'000.jpg',OUT/'videos'/f'{name}.jpg')
shutil.copy2(OUT/'comparison/native_camera.jpg',OUT/'native_camera.jpg')
sheet([OUT/'hound/geometry'/f'{v}_{i:02}.png' for v in ['side','front'] for i in [0,2,4,6,8]],OUT/'source_poses.jpg',columns=5,width=320,height=220)
sheet([OUT/'hound/geometry/parts.png',OUT/'hound/geometry/wire.png'],OUT/'parts_wire.jpg',columns=2,width=600,height=400)
sheet([OUT/'comparison/side'/f'{i:03}.jpg' for i in [0,4,8,12]],OUT/'comparison_poses.jpg',columns=2,width=640,height=400)
speed=h['reference_playback_speed'];distance=h['distance_per_clip_m'];drift=max(max(v) for v in h['stance_world_drift_xyz_m'].values())
bodyread=f'''# 수렵견 · 전신 질주 v4

[이전/수정 비교](../../../../reports/hound_fullbody_v4/review.html) · [parts.json](parts.json) · [편집 원본](hound_game_v4.blend)

몸을 계속 108mm 낮추던 v3 보정을 제거했다. Quaternius CC0 Wolf/Gallop의 몸통·골반·목·머리·꼬리 월드 회전을 감쇠 없이 옮기고, 몸통 이동과 다리의 접힘·회수를 함께 맞췄다. 골반과 목은 기계 연결점에 고정한다. 기계 앞다리는 윗마디/아랫마디가 거의 1:1이고 늑대는 약 1:2.6이므로 회수할 때 위로 접히는 범위를 완화한다. 접지 IK는 원본 굽힘 평면의 방향을 유지해 무릎이 뒤집히지 않는다.

- 6,795 삼각형 / 33 강체 그룹 / 37 본 / 2 재질 / 기존 6 클립.
- 모든 rest 본·UV·토폴로지·웨이트·재질, 일반 부품 정점과 노멀은 동일하다. 앞 피스톤 케이스 2개, 정점 20개만 정적으로 최대 4.871mm 연장한다. 애니메이션 스케일은 없다.
- `run`을 교체하고, 변경 케이스의 `death` 바닥 지지만 보정한다. 다른 클립과 거대 인형은 유지한다.
- 등 윗면은 v3 약 39.3–43.0cm → v4 **42.3–52.0cm**. 검사한 팔꿈치 외피는 등보다 최소 **8.54cm 아래**다.
- 24fps 시간선 + **480Hz** 정확한 키/접지 시각. GLB, `parts.json`, import 설정과 `import_exact_animation.gd`를 함께 배포한다.

## 이동 속도 계약 변경

0.5초 클립에 두 번의 질주가 들어가며 실제 접지 보폭은 **{distance:.6f}m / clip**이다. 고정 재생 1배는 {distance/.5:.6f}m/s에 해당한다. **6.5m/s에는 재생 속도 {speed:.9f}배**를 사용한다. 일반식은 `speed_scale = actual_ground_speed / (run_cycle_distance_m / clip_seconds)`이며, 인스턴스가 커지면 분모에 전체 배율도 곱한다. 장갑도 같은 클립 시간을 사용한다. 이동 루트는 게임이 담당하며 이번 작업에서 게임 이동 속도나 AI는 바꾸지 않았다. 기존 3.25m/0.5초 메타데이터를 그대로 적용하지 않는다.

## 검증

1,920Hz 샘플에서 접지 후 이동 보상 오차 최대 {drift*1000:.3f}mm. 모든 관절 길이와 연결, 피스톤 삽입·끝단, 바닥, 루프 자세/속도, 저장 소스와 Godot 재생을 검사했다. 비교 영상은 동일 위상이며 ‘6.5m/s 이동’ 영상에서 보폭에 맞춘 재생을 확인할 수 있다. 원본/재임포트 QA 오류 0. UV·노멀 이음 정점과 내부 맞댐 면 경고는 의도적으로 유지한다.

기본/장갑 준비용 자산이며 주 게임 연결·임의 블렌드/중단 포즈·장갑 간 접촉·실시간 파편 충돌·최종 성능 및 외형 선택은 별도다. [현재 입력과 결과](../../../../reports/hound_fullbody_v4/delivery_manifest.json). 원본 Wolf.blend와 공식 CC0 License.txt는 [motion_sources/quaternius](../motion_sources/quaternius/README.md)에 보존한다.
'''
(base('hound')/'README.md').write_text(bodyread,encoding='utf8')
(base('hound_armour')/'README.md').write_text('''# 중장 추적기 장갑 v3

[전신 질주 검토](../../../../reports/hound_fullbody_v4/review.html) · [편집 원본](hound_armour_game_v3.blend) · [parts.json](parts.json)

1,388 삼각형 / 4 강체 그룹 / 기존 37 본 / 1 재질. v2 장갑의 정점·노멀·UV·토폴로지·웨이트·재질·rest와 독립 붕괴를 그대로 보존한다. 살아 있는 모든 클립은 **hound_v4**와 같은 시각에 샘플한다. 새 보폭/재생 속도도 기본형을 따른다. 전체 배율 1.2는 기본형+장갑 부모에 적용한다.

packed Blend에는 v4 기본형과 별도 장갑 리그가 들어 있다. 기본형 참고 액션은 Previous_*이고 장갑 리그는 같은 이름의 클립을 가진다. 원본/재임포트 QA 오류 0. UV·노멀 이음 및 숨겨진 맞댐 면은 유지한다. 임의 포즈의 접촉/물리나 주 게임 연결을 보장하는 파일은 아니다.
''',encoding='utf8')
catalog=read(ASSETS/'catalog.json');cat=catalog['actors']['hound']
cat['base']='res://assets/actors/automation_batch2/hound_v4/hound_v4.glb';cat['parts']='res://assets/actors/automation_batch2/hound_v4/parts.json';cat['variants']['heavy']['armour']='res://assets/actors/automation_batch2/hound_armour_v3/hound_armour_v3.glb'
cat['motion_review']='reports/hound_fullbody_v4/review.html';cat['run']={'clip_seconds':.5,'cycle_distance_m':distance,'reference_speed_mps':6.5,'reference_playback_speed':speed,'instance_scale_affects_stride':True}
dump(ASSETS/'catalog.json',catalog)

html='''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>수렵견 · 전신 질주 v4</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#111b23;color:#e4edf0;font:16px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1328px;margin:auto;padding:34px 24px 60px}h1{font-size:30px;line-height:1.3;margin:8px 0 14px}h2{font-size:21px;margin-top:36px}p{max-width:980px;color:#b9cbd0}a{color:#79ded4}nav,.controls{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}button{font:inherit;color:inherit;background:#20323d;border:1px solid #3a5360;border-radius:7px;padding:7px 15px;cursor:pointer}button[aria-pressed="true"]{background:#286f68;border-color:#70dacf;color:white}video,img{display:block;width:100%;border-radius:9px;background:#17252e}video{aspect-ratio:1280/800}.note{font-size:14px;color:#9fb4bb}input{width:100%}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:24px 0}.card{background:#1a2b35;padding:16px;border-radius:9px}.card strong{display:block;color:#89e0d7;font-size:22px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}summary{cursor:pointer;color:#83d8d0}footer{margin-top:36px;color:#9eb2ba;font-size:14px}@media(max-width:700px){main{padding:22px 12px}.cards,.grid{grid-template-columns:1fr}h1{font-size:25px}}
</style></head><body><main><div class="note">WITCH · AUTOMATION ART · V4</div><h1>수렵견, 몸 전체가 함께 달리도록</h1><p>몸통을 낮게 고정하던 보정을 걷어내고, 늑대 원본의 몸통·골반·목·머리·꼬리 움직임을 함께 적용했습니다. 다리 비율에 맞춰 앞다리 회수와 접지를 정리했습니다. <b>비교 화면 왼쪽이 새 v4, 오른쪽이 기존 v3</b>입니다.</p>
<nav id="tabs" aria-label="검토 각도"></nav><video id="movie" src="videos/side.mp4" poster="videos/side.jpg" controls muted autoplay loop playsinline></video>
<div class="controls" id="rates" aria-label="재생 속도"><button data-rate="1" aria-pressed="false">1배</button><button data-rate="0.5" aria-pressed="true">0.5배</button><button data-rate="0.25" aria-pressed="false">0.25배</button><button id="pause">일시 정지 / 재생</button></div><label class="note" for="seek">멈춰서 자세 보기</label><input type="range" id="seek" min="0" max="1.999" step="0.01666667" value="0" aria-label="영상 위치"><p class="note" id="viewnote"></p>
<div class="cards"><div class="card">등 높이<strong>42.3–52.0cm</strong><span>기존 39.3–43.0cm</span></div><div class="card">전신 동작<strong>몸통 + 골반 + 목 + 꼬리</strong><span>원본 회전량을 유지</span></div><div class="card">관절과 발<strong>굽힘 방향 · 접지 수정</strong><span>팔꿈치가 등 아래로 회수됨</span></div></div>
<h2>실제 표시 크기</h2><p>1.75배 게임 카메라에서 마녀와 함께 배치했습니다. 중장 추적기는 새 전신 동작에 맞춰 장갑도 따라갑니다.</p><img src="native_camera.jpg" alt="마녀와 새 수렵견, 기존 수렵견, 중장 추적기의 게임 표시 크기">
<h2>자세 비교</h2><img src="comparison_poses.jpg" alt="질주 네 구간의 새 전신 동작과 기존 동작 비교">
<details><summary>자산과 검증 기록</summary><p>수렵견은 6,795 삼각형·33 강체 그룹·37 본을 유지합니다. 장갑은 1,388 삼각형·4 그룹입니다. 모든 본의 기본 자세, 일반 부품, 재질은 유지하고 앞 피스톤 케이스 2개의 정적 길이만 소폭 맞췄습니다.</p><p>새 보폭은 <b>2.754772m / 0.5초 클립</b>입니다. 6.5m/s 이동에는 <b>1.179771배 재생</b>을 사용합니다. 장갑과 몸체는 같은 시간을 샘플합니다. 게임 AI·이동 규칙은 변경하지 않은 준비용 자산입니다.</p><p>저장 원본·GLB 재임포트 QA 오류 0. 접지·관절·피스톤·루프와 실제 Godot 재생을 검사했습니다. UV/노멀 이음과 내부 맞댐 면 경고는 유지합니다. 임의 블렌드나 실시간 충돌까지 검증한 것은 아닙니다.</p><div class="grid"><a href="source_poses.jpg"><img src="source_poses.jpg" alt="Blender 원본 자세 시트"></a><a href="parts_wire.jpg"><img src="parts_wire.jpg" alt="부품 분리와 와이어 검토"></a></div><p><a href="../../assets/actors/automation_batch2/hound_game_v4/README.md">몸체 편집·연결 안내</a> · <a href="../../assets/actors/automation_batch2/hound_armour_v3/README.md">장갑 안내</a> · <a href="delivery_manifest.json">검증·파일 해시</a></p></details>
<footer>동작 출처: <a href="https://quaternius.com/packs/ultimateanimatedanimals.html">Quaternius Ultimate Animated Animal Pack · CC0</a>, Wolf/Gallop. 모션 캡처가 아닌 배포된 애니메이션을 체형에 맞춰 적용했습니다. <a href="../automation_motion_v2/review.html">이전 거대 인형 축·수렵견 검토</a></footer></main>
<script>
const movie=document.getElementById('movie'),tabs=document.getElementById('tabs'),seek=document.getElementById('seek'),note=document.getElementById('viewnote');let rate=.5;
const views=[['side','옆 비교','같은 위상으로 재생합니다. 몸 높이, 골반 기울기와 앞다리 회수를 봐 주세요.'],['front','앞 비교','양쪽 앞다리와 목·머리 움직임을 확인합니다.'],['rear','뒤 비교','골반·뒷다리·꼬리가 함께 움직입니다.'],['armour','중장 추적기','장갑의 동작은 새 기본형과 같은 시간으로 재생합니다.'],['native','실제 크기','게임의 1.75배 카메라. 마녀 / 새 v4 / 기존 v3 / 중장 v4 순서입니다.'],['travel','6.5m/s 이동','실제 전진 6.5m/s, 1.179771배 모션. 바닥 줄은 0.5m 간격입니다. 아래 배속은 이 영상 자체의 재생 속도입니다.']];
for(const [id,title,description]of views){const b=document.createElement('button');b.textContent=title;b.dataset.id=id;b.setAttribute('aria-pressed',String(id==='side'));b.onclick=()=>{document.querySelectorAll('#tabs button').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));movie.src=`videos/${id}.mp4`;movie.poster=`videos/${id}.jpg`;note.textContent=description;movie.playbackRate=rate;movie.play().catch(()=>{});};tabs.appendChild(b);}note.textContent=views[0][2];
document.querySelectorAll('[data-rate]').forEach(b=>b.onclick=()=>{rate=Number(b.dataset.rate);movie.playbackRate=rate;document.querySelectorAll('[data-rate]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));});
movie.addEventListener('loadedmetadata',()=>movie.playbackRate=rate);movie.addEventListener('timeupdate',()=>seek.value=movie.currentTime);seek.oninput=()=>{movie.pause();movie.currentTime=Number(seek.value);};document.getElementById('pause').onclick=()=>movie.paused?movie.play().catch(()=>{}):movie.pause();movie.playbackRate=rate;
</script></body></html>'''
(OUT/'review.html').write_text(html,encoding='utf8')
(OUT/'.gitignore').write_text('local/\ncomparison/\n**/local/\n**/runtime/runtime_poses.json\n**/geometry/*.png\n',encoding='utf8')
links=[]
class Links(HTMLParser):
 def handle_starttag(self,tag,attrs):
  for k,v in attrs:
   if k in ('src','href','poster') and v and not v.startswith(('https:','http:','#')):links.append(v)
Links().feed(html)
js=html.split('<script>',1)[1].split('</script>',1)[0];(OUT/'local/review.js').write_text(js,encoding='utf8');subprocess.run(['node','--check',str(OUT/'local/review.js')],check=True)
sources=['tools/hound_fullbody_motion.py','tools/build_hound_fullbody_v4.py','tools/automation_motion_common.py','tools/prototype_hound_fullbody_v4.py','tools/export_automation_actor.py','tools/validate_automation_actor.py','tools/validate_hound_fullbody_v4.py','tools/review_automation_motion_v2.py','tools/review_hound_fullbody_v4.ps1','tools/package_hound_fullbody_v4.py','game/tests/review_automation_actor_v1.gd','game/tests/review_hound_fullbody_v4.gd','game/tests/review_automation_batch2_complete_v1.gd','game/tests/helpers/automation_batch2_visual.gd','assets/actors/automation_batch2/catalog.json','assets/actors/automation_batch2/README.md','assets/actors/automation_batch2/ART_REQUEST.md','AGENTS.md']
files=[ROOT/p for p in sources]
for folder in [base('hound'),base('hound_armour'),ROOT/'game/assets/actors/automation_batch2/hound_v4',ROOT/'game/assets/actors/automation_batch2/hound_armour_v3',ASSETS/'motion_sources/quaternius',OUT]:
 for p in folder.rglob('*'):
  if not p.is_file() or p.suffix=='.blend1' or p.name.endswith('_static.glb') or p.name=='delivery_manifest.json':continue
  rel=p.relative_to(folder)
  if folder==OUT and ('local' in rel.parts or 'comparison' in rel.parts or p.name=='runtime_poses.json' or ('geometry' in rel.parts and p.suffix=='.png')):continue
  files.append(p)
manifest={'task':'hound whole-body gallop v4','stage':'prepared art; no main-game integration or user art selection','assets':{'hound':'hound_game_v4 / runtime hound_v4','armour':'hound_armour_v3','giant':'unchanged giant_v2 + giant_armour_v2'},
 'source_poses':sourceposes,'godot_runtime_checks':runtimechecks,'independent_motion_checks':motion['checks'],'gpu_captures':capture['captures'],'godot_pose_parity':validation,'previous_asset_files_preserved':motion['previous_asset_files_preserved'],
 'motion_metrics':{k:v for k,v in h.items() if k!='loop_velocity'},'loop_velocity_ratio_max':max(v['ratio'] for v in h['loop_velocity'].values()),'videos':videos,'qa_warnings':warnings,
 'warning_adjudication':'Retained source UV/normal seams and hidden mating caps/internal bearings; exported loop vertices split on UV/normal boundaries. No same-facing visible duplicate surfaces were found. Floor clearance and opaque rigid materials remain intentional.',
 'visual_review':{'inspected':'material side/front/rear at multiple phases, heavy armour, native camera, parts colors and wireframe','observations':'higher cyclic trunk, head and pelvis follow original action, recovered elbow shell stays below back, no visible part detachment in sampled poses'},
 'environment':'Blender 5.1.1 isolated CLI because MCP handshake unavailable; Godot 4.6.2 gl_compatibility RTX2060; user:// shader-cache creation diagnostic remains; no model/load/playback errors.',
 'limits':['fullbody orientations copied; limb proportions/contact height/recovery adapted, not exact wolf geometry','prepared art only, integration must use updated stride/playback rate','no arbitrary pose blending/interruption/armour collision or live debris physics','no final performance or user motion selection'],
 'source_receipt':{'provider':'Quaternius','official_page':'https://quaternius.com/packs/ultimateanimatedanimals.html','license':'CC0 1.0','action':'Wolf/Gallop','unchanged_source_sha256':sha(ASSETS/'motion_sources/quaternius/Wolf.blend')},
 'files':{str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in sorted(set(files))}}
dump(OUT/'delivery_manifest.json',manifest)
assert all((OUT/l).exists() for l in links),[l for l in links if not (OUT/l).exists()]
print('HOUND_V4_PACKAGE',json.dumps({k:manifest[k] for k in ['source_poses','godot_runtime_checks','independent_motion_checks','gpu_captures','previous_asset_files_preserved']}),'files',len(manifest['files']))
