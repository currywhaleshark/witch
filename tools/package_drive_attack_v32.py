"""Package actual Godot captures with playback controls and provenance."""
from pathlib import Path
import json,subprocess,shutil,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/drive_attack_v32';CAP=OUT/'capture'
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
qa=read(OUT/'source_validation.json');runtime=read(OUT/'validate/validation.json');capture=read(CAP/'validation.json')
assert runtime['passed'] and capture['passed']
specs=[('bolt','볼트커터 · 연속 찌르기','오른발을 앞으로 내딛어 런지 자세를 잡고, 뒷발(왼발)은 제자리에서 앞꿈치로 돌아 고정합니다. 찌를 때 뒷다리가 밀어 골반이 앞으로 나가고 뒤꿈치가 들리며, 26cm 그립으로 진입 → 3회 반복 → 복귀합니다.'),
 ('grinder_sweep','그라인더 · 전방 반원','왼발을 앞으로 내딛어 넓게 선 뒤 오른쪽으로 감았다가, 골반 → 어깨 → 공구 순으로 풀며 반원을 그립니다. 체중이 오른발에서 왼발로 넘어가고 오른발은 앞꿈치로 돌아갑니다. 그립은 13cm.'),
 ('chainsaw_cut','전기톱 · 지속 절단','왼발을 공구 쪽 앞으로 내딛고 오른발을 바깥으로 돌려 버티는 자세에서, 골반과 상체가 앞뒤로 작게 밀며 22cm 그립으로 지속 절단합니다.'),
 ('chainsaw_spin','전기톱 · 한 바퀴 휘두르기','오른발을 넓게 벌려 오른쪽으로 감은 뒤, 왼발 앞꿈치를 축으로 360도 돕니다. 축발은 제자리에 고정되고 오른발은 낮게 따라 돈 뒤 원래 자리에 착지합니다. 그립은 11cm.')]
# Contact sheet via ImageMagick (no Pillow dependency): 6 phases per clip, transformed outfit.
magick=shutil.which('magick');assert magick
ffmpeg=shutil.which('ffmpeg');assert ffmpeg
rows=[]
for row,(key,title,description) in enumerate(specs):
 paths=sorted(CAP.glob(key+'_*.png'));assert paths
 subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','24','-i',str(CAP/(key+'_%04d.png')),
  '-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/(key+'.mp4'))],check=True)
 tiles=[str(paths[round((len(paths)-1)*col/5)]) for col in range(6)]
 strip=OUT/('_strip_%d.png'%row)
 subprocess.run([magick,*tiles,'-crop','500x500+650+125','+repage','-resize','235x205!','-background','#19212d','-gravity','center','-extent','240x208',
  '+append','-gravity','northwest','-splice','0x32','-font','C:/Windows/Fonts/malgun.ttf','-pointsize','19','-fill','#e1eaf3','-annotate','+8+5',title,str(strip)],check=True)
 rows.append(str(strip))
subprocess.run([magick,*rows,'-append','-quality','94',str(OUT/'contact_sheet.jpg')],check=True)
for strip in rows:Path(strip).unlink()
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>구동 공격 모션 v32</title>
<style>*{box-sizing:border-box}body{margin:0;background:#111924;color:#e6edf5;font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1160px;padding:30px 22px;margin:auto}h1{margin:8px 0;font-size:30px}p{color:#b7c7d9}nav{display:flex;gap:8px;flex-wrap:wrap;margin:24px 0 12px}button,select{font:inherit;background:#263448;color:#edf4fc;border:1px solid #52677b;border-radius:7px;padding:7px 14px;cursor:pointer}button.active{background:#b9e2da;color:#14302e}video{width:100%;background:#202936;border-radius:10px}aside{padding:14px 20px;background:#1c2938;border-radius:9px}a{color:#9cdbda}.tag{color:#a5c9cf;font-size:12px;letter-spacing:.13em}.controls{display:flex;gap:12px;margin:12px 0;align-items:center;flex-wrap:wrap}details{margin-top:22px;color:#aebed1}summary{cursor:pointer}footer{color:#8e9eaf;font-size:13px;margin-top:24px}</style>
<main><div class="tag">WITCH · DRIVE MOTION · V32</div><h1>디딤발과 체중 이동을 다시 잡은 공격 모션</h1><p>왼쪽은 평상복, 오른쪽은 변신복입니다. <a href="../drive_attack_v31/review.html">이전 v31 보기</a></p><nav id="tabs"></nav>
<video id="movie" controls loop autoplay muted playsinline></video><div class="controls"><button id="restart">처음부터</button><button id="step">1프레임 앞으로</button><label>속도 <select id="speed"><option value=".25">0.25배</option><option value=".5">0.5배</option><option value="1" selected>1배</option></select></label></div>
<h2 id="title"></h2><p id="description"></p><aside>공격 동작의 인상과 양손 자세를 보는 시안입니다. 반복 속도·피해·판정·자원 소모는 아직 스킬 구현에 연결하지 않았습니다. 큰 날 절단은 요청대로 기존 공격 모션을 유지합니다.</aside>
<details><summary>손과 자루 경로 확대</summary><p>정면과 캐릭터 왼쪽에서 본 찌르기 준비 자세, 그라인더 후속 동작입니다.</p><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px"><a href="details/transformed_bolt_ready_front.png"><img style="width:100%" src="details/transformed_bolt_ready_front.png" alt="찌르기 정면"></a><a href="details/transformed_bolt_ready_left.png"><img style="width:100%" src="details/transformed_bolt_ready_left.png" alt="찌르기 왼쪽"></a><a href="details/civilian_grinder_follow_front.png"><img style="width:100%" src="details/civilian_grinder_follow_front.png" alt="그라인더 평상복"></a><a href="details/transformed_grinder_follow_left.png"><img style="width:100%" src="details/transformed_grinder_follow_left.png" alt="그라인더 변신복"></a></div></details>
<details><summary>원본과 확인 범위</summary><p>v32의 네 동작은 모두 발 위치·골반·상체를 직접 지정해 만든 동작입니다. 발은 항상 고정(앞꿈치 회전 허용)되거나 들어 올려 내딛으며 바닥에서 미끄러지지 않습니다. 그립 간격과 자루 미끄럼 규칙은 v31과 같습니다.</p><p>107개 본과 기존 메시·기존 모션을 유지했습니다. 저장된 자세와 중간 프레임의 양손 그립, 자세 연속성, 실제 손 메시와 몸통·골반의 관통을 검사했습니다. 의상 접촉도 별도로 기록하며 기존 손목/소매 경계의 겹침은 남아 있습니다. 손가락과 자루의 완전한 밀착, 머리 접촉, 외골격의 새 동작 보정은 최종 검증 범위에 포함되지 않습니다.</p><p>모든 클립은 24fps에서 보간용 키를 충분히 저장하고, 이 화면은 별도로 기록한 시안 재생 시간에 맞춰 재생합니다. 실제 스킬 속도는 정하지 않았습니다.</p></details><footer>디딤발·체중 이동 수정본 · 기본 게임 교체 전</footer>
<script>const clips=DATA;const v=document.querySelector('#movie'),tabs=document.querySelector('#tabs');let active=0;function choose(i){active=i;v.src=clips[i][0]+'.mp4';v.playbackRate=+document.querySelector('#speed').value;document.querySelector('#title').textContent=clips[i][1];document.querySelector('#description').textContent=clips[i][2];[...tabs.children].forEach((b,j)=>b.classList.toggle('active',i===j));v.play().catch(()=>{});}clips.forEach((c,i)=>{let b=document.createElement('button');b.textContent=c[1];b.onclick=()=>choose(i);tabs.append(b)});document.querySelector('#speed').onchange=e=>v.playbackRate=+e.target.value;document.querySelector('#restart').onclick=()=>{v.currentTime=0;v.play()};document.querySelector('#step').onclick=()=>{v.pause();v.currentTime+=1/24};choose(0);</script></main></html>'''
(OUT/'review.html').write_text(html.replace('DATA',json.dumps(specs,ensure_ascii=False)),encoding='utf-8')
manifest={'scope':'Prepared animation review; no main-game promotion','capture_count':capture['captures'],'runtime':runtime,'source':qa,
 'files':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [OUT/'review.html',OUT/'source_validation.json',OUT/'export.json',*[OUT/(key+'.mp4') for key,_,_ in specs]]}}
contact=read(OUT/'hand_contact_final.json')
assert all(v['body_crossing_or_inside_poses']==0 for v in contact['summary'].values()),contact['summary']
assert all(v['hand_to_hand_crossing_poses']==0 for v in contact['summary'].values()),contact['summary']
opposite_sleeve=sum(bool(row['contacts'].get('transformed',{}).get('TF_sleeve_'+other+'_v4',{}).get(side)) for row in contact['poses'] for side,other in [('L','R'),('R','L')])
assert opposite_sleeve==0,opposite_sleeve
manifest['hand_body_contact']={'scope':contact['scope'],'summary':contact['summary']}
manifest['hand_body_contact']['opposite_sleeve_contact_poses']=opposite_sleeve
manifest['remaining_contacts']='Whole-wrist/own-sleeve and inner sleeve coverage contacts remain, with some proximal wrist intersections at blouse/cape edges. No all-garment or exact finger/shaft clearance claim.'
for name in ('final_preservation.json','reimport_asset_qa.json','carrier_asset_qa.json','details/validation.json','validate/execution.json','capture/execution.json'):
 manifest[name]=read(OUT/name)
baseline=read(OUT/'task_baseline.json')
assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in baseline.items())
manifest['protected_task_inputs']=baseline
paths=[*OUT.glob('*.json'),*OUT.glob('*.html'),*OUT.glob('*.jpg'),*OUT.glob('*.mp4'),*(OUT/'details').glob('*.png'),
 * (ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v32').glob('*'),
 * (ROOT/'game/assets/characters/player/drive_attack_v32').glob('*'),
 * (ROOT/'tools').glob('*v32*'),* (ROOT/'game/tests').glob('*v32.gd')]
for p in paths:
 if p.is_file() and p.suffix not in ('.blend1','.uid') and p.name not in ('delivery_manifest.json','pose_probe.json'):
  manifest['files'][p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('DRIVE_ATTACK_V32_PACKAGED',capture['captures'])
