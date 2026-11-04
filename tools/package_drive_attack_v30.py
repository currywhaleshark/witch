"""Package actual Godot captures with playback controls and provenance."""
from pathlib import Path
import json,subprocess,shutil,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/drive_attack_v30';CAP=OUT/'capture'
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
qa=read(OUT/'source_validation.json');runtime=read(OUT/'validate/validation.json');capture=read(CAP/'validation.json')
assert runtime['passed'] and capture['passed']
specs=[('bolt','볼트커터 · 연속 찌르기','무료 창 모션에서 당기기와 찌르기를 가져와 발걸음과 준비 동작을 줄였습니다. 진입 → 3회 반복 → 복귀.'),
 ('grinder_sweep','그라인더 · 전방 반원','Mixamo Low Slash의 몸통 움직임을 줄여 적용하고, 공구는 허리 앞에서 반원을 지나갑니다.'),
 ('chainsaw_cut','전기톱 · 지속 절단','양손으로 날을 앞에 유지하며 체중을 싣는 새 반복 동작입니다. 진입 → 3회 반복 → 복귀.'),
 ('chainsaw_spin','전기톱 · 한 바퀴 휘두르기','Mixamo High Spin의 골반 회전과 발동작을 축소해 적용하고, 높이 들던 공구를 낮췄습니다.')]
font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',19)
sheet=Image.new('RGB',(1440,4*240),'#19212d');draw=ImageDraw.Draw(sheet)
for row,(key,title,description) in enumerate(specs):
 paths=sorted(CAP.glob(key+'_*.png'));assert paths
 ffmpeg=shutil.which('ffmpeg');assert ffmpeg
 subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','24','-i',str(CAP/(key+'_%04d.png')),
  '-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/(key+'.mp4'))],check=True)
 for col in range(6):
  index=round((len(paths)-1)*col/5);im=Image.open(paths[index]).convert('RGB')
  # Current transformed character at full rendered resolution, 6 different phases.
  im=im.crop((650,125,1150,625)).resize((235,205),Image.Resampling.LANCZOS)
  sheet.paste(im,(col*240,row*240+32))
 draw.text((8,row*240+5),title,font=font,fill='#e1eaf3')
sheet.save(OUT/'contact_sheet.jpg',quality=94)
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>구동 공격 모션 v30</title>
<style>*{box-sizing:border-box}body{margin:0;background:#111924;color:#e6edf5;font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1160px;padding:30px 22px;margin:auto}h1{margin:8px 0;font-size:30px}p{color:#b7c7d9}nav{display:flex;gap:8px;flex-wrap:wrap;margin:24px 0 12px}button,select{font:inherit;background:#263448;color:#edf4fc;border:1px solid #52677b;border-radius:7px;padding:7px 14px;cursor:pointer}button.active{background:#b9e2da;color:#14302e}video{width:100%;background:#202936;border-radius:10px}aside{padding:14px 20px;background:#1c2938;border-radius:9px}a{color:#9cdbda}.tag{color:#a5c9cf;font-size:12px;letter-spacing:.13em}.controls{display:flex;gap:12px;margin:12px 0;align-items:center;flex-wrap:wrap}details{margin-top:22px;color:#aebed1}summary{cursor:pointer}footer{color:#8e9eaf;font-size:13px;margin-top:24px}</style>
<main><div class="tag">WITCH · DRIVE MOTION · V30</div><h1>양손으로 공구를 다루는 네 가지 동작</h1><p>왼쪽은 평상복, 오른쪽은 변신복입니다. 현재 몸체·헤어·지팡이로 재생한 Godot 비교 시안입니다.</p><nav id="tabs"></nav>
<video id="movie" controls loop autoplay muted playsinline></video><div class="controls"><button id="restart">처음부터</button><button id="step">1프레임 앞으로</button><label>속도 <select id="speed"><option value=".25">0.25배</option><option value=".5">0.5배</option><option value="1" selected>1배</option></select></label></div>
<h2 id="title"></h2><p id="description"></p><aside>공격 동작의 인상과 양손 자세를 보는 시안입니다. 반복 속도·피해·판정·자원 소모는 아직 스킬 구현에 연결하지 않았습니다. 큰 날 절단은 요청대로 기존 공격 모션을 유지합니다.</aside>
<details><summary>원본과 확인 범위</summary><p>찌르기: <a href="https://kevdev.itch.io/human-melee-animatons-free">Kevin Iglesias · Human Melee Animations FREE</a>의 HumanF@AttackPolearm01. 반원/회전: <a href="https://www.mixamo.com/">Adobe Mixamo</a>의 Great Sword Low Slash / Great Sword High Spin Attack. 지속절단은 직접 만든 동작입니다. 다운로드한 원본은 로컬에 보관합니다.</p><p>107개 본과 기존 메시·기존 모션을 유지했습니다. 실제 저장/가져오기, 중간 프레임의 양손 그립 및 자세 연속성을 검사했습니다. 손가락과 자루의 완전한 밀착, 모든 옷·머리 접촉, 외골격의 새 동작 보정은 최종 검증 범위에 포함되지 않습니다.</p><p>모든 클립은 24fps에서 보간용 키를 충분히 저장하고, 이 화면은 별도로 기록한 시안 재생 시간에 맞춰 재생합니다. 실제 스킬 속도는 정하지 않았습니다.</p></details><footer>원본 무료 모션을 현재 캐릭터에 맞춘 첫 비교본 · 기본 게임 교체 전</footer>
<script>const clips=DATA;const v=document.querySelector('#movie'),tabs=document.querySelector('#tabs');let active=0;function choose(i){active=i;v.src=clips[i][0]+'.mp4';v.playbackRate=+document.querySelector('#speed').value;document.querySelector('#title').textContent=clips[i][1];document.querySelector('#description').textContent=clips[i][2];[...tabs.children].forEach((b,j)=>b.classList.toggle('active',i===j));v.play().catch(()=>{});}clips.forEach((c,i)=>{let b=document.createElement('button');b.textContent=c[1];b.onclick=()=>choose(i);tabs.append(b)});document.querySelector('#speed').onchange=e=>v.playbackRate=+e.target.value;document.querySelector('#restart').onclick=()=>{v.currentTime=0;v.play()};document.querySelector('#step').onclick=()=>{v.pause();v.currentTime+=1/24};choose(0);</script></main></html>'''
(OUT/'review.html').write_text(html.replace('DATA',json.dumps(specs,ensure_ascii=False)),encoding='utf-8')
manifest={'scope':'Prepared animation review; no main-game promotion','capture_count':capture['captures'],'runtime':runtime,'source':qa,
 'files':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [OUT/'review.html',OUT/'source_validation.json',OUT/'export.json',*[OUT/(key+'.mp4') for key,_,_ in specs]]}}
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('DRIVE_ATTACK_V30_PACKAGED',capture['captures'])
