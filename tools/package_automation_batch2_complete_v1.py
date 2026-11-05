"""Package offline review, exact-input receipts and integration handoff."""
import json,hashlib,math,subprocess,shutil,html,re,gzip
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/automation_batch2_complete_v1';ASSETS=ROOT/'assets/actors/automation_batch2'
ACTORS=['beacon','giant','hound_armour','giant_armour']
NAMES={'beacon':'유인 신호기','giant':'거대 자동인형','hound_armour':'수렵견 · 중장 추적기','giant_armour':'거대 자동인형 · 단일 강화'}
DESCS={'beacon':'접이식 삼각대와 두 단계 기둥, 회전 셔터·종·신호등. 설치부터 소등과 파괴까지.',
 'giant':'아래부터 조립되고 마지막에 바이저가 켜진다. 묵직한 보행과 양손 내리치기, 부품 붕괴.',
 'hound_armour':'기존 수렵견에 머리 보호대·양쪽 어깨 장갑·톱니 턱을 추가. 기본 메시와 동작은 그대로.',
 'giant_armour':'기존 거대 인형에 어깨·팔뚝·주먹 덮개를 추가. 파괴할 때는 장갑이 따로 떨어진다.'}
CLIP_NAMES={'deploy':'설치','pulse':'신호','shutdown':'소등·회수','assemble':'조립','idle':'대기','walk':'보행','run':'달리기','bite':'물기','slam':'내리치기','hit':'경직','death':'파괴','spawn':'생성'}
def load(p):return json.loads(p.read_text(encoding='utf8'))
def dump(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,indent=2,ensure_ascii=False),encoding='utf8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def folder(a):return ASSETS/(a+('_v1' if a.endswith('_armour') else '_game_v1'))
def link(p):return p.relative_to(ROOT).as_posix()
def sheet(paths,labels,dest,cols=3,width=400):
    height=300;canvas=Image.new('RGB',(cols*width,math.ceil(len(paths)/cols)*(height+30)),(22,32,40));draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',18)
    for i,(path,label) in enumerate(zip(paths,labels)):
        im=Image.open(path).convert('RGB');im.thumbnail((width,height));x=(i%cols)*width;y=(i//cols)*(height+30)
        canvas.paste(im,(x+(width-im.width)//2,y+(height-im.height)//2));draw.text((x+12,y+height+4),label,font=font,fill=(213,229,231))
    canvas.save(dest,quality=92)
def video(src,dest,fps):
    dest.parent.mkdir(parents=True,exist_ok=True)
    if not dest.exists() or dest.stat().st_mtime<max(p.stat().st_mtime for p in src.glob('*.jpg')):
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-framerate',str(fps),'-i',str(src/'%03d.jpg'),'-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-movflags','+faststart',str(dest)],check=True)
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=width,height,nb_frames,r_frame_rate','-show_entries','format=duration','-of','json',str(dest)],text=True))
    assert int(probe['streams'][0]['nb_frames'])==len(list(src.glob('*.jpg')))
    return probe

catalog={'date':'2026-11-05','stage':'prepared art, not main-game integration','coordinate_system':'metres, Y up, -Z forward; instance scale applies to whole base+armour wrapper','actors':{}}
review_data={};parity={};productions={};videos={}
for a in ACTORS:
    base=folder(a);parts=load(base/'parts.json');runtime=load(OUT/a/'runtime/runtime_validation.json');assert runtime['passed']
    for name in ('source_qa','reimport_qa','saved_source','reimport','authoring_preservation'):
        record=load(OUT/a/f'validation/{name}.json');assert record.get('pass',record.get('passed',False)),(a,name)
    if a.endswith('_armour'):assert load(OUT/a/'validation/base_preservation.json')['passed']
    sample_path=OUT/a/'local/animation_samples.json'
    rows=load(sample_path) if sample_path.exists() else json.loads(gzip.decompress((base/'animation_samples.json.gz').read_bytes()).decode('utf8'))
    (base/'animation_samples.json.gz').write_bytes(gzip.compress(json.dumps(rows,separators=(',',':')).encode(),mtime=0))
    actual=load(OUT/a/'runtime/runtime_poses.json');maximum=0.;count=0
    for row in actual:
        expected=min(rows[row['clip']],key=lambda r:abs(r['time']-row['time']));assert abs(expected['time']-row['time'])<1e-6
        for n,p in row['bones'].items():
            m=expected['world'][n];want=np.array([m[0][3],m[2][3],-m[1][3]])
            maximum=max(maximum,float(np.linalg.norm(want-np.array(p))));count+=1
    assert maximum<3e-5,(a,maximum)
    parity[a]={'passed':True,'compared_bone_origins':count,'maximum_error_m':maximum}
    dump(OUT/a/'validation/runtime_parity.json',parity[a])
    videos[a]={}
    for clip,c in parts['clips'].items():
        videos[a][clip]=video(OUT/a/f'runtime/motion_{clip}',OUT/a/f'videos/{clip}.mp4',30 if c['loop'] else 24)
    sheet([OUT/a/f'geometry/{n}.png' for n in ('front','rear','profile','top','parts','wire')],['Front','Rear','Side','Top','Rigid groups','Wire'],OUT/a/'geometry_sheet.jpg')
    sheet([OUT/a/'runtime/poses_death'/f'{i:02}.jpg' for i in (0,1,3,5,6)],['Death '+str(i)+'/6' for i in (0,1,3,5,6)],OUT/a/'death_sheet.jpg',cols=5,width=300)
    sourceqa=load(OUT/a/'validation/source_qa.json');reimportqa=load(OUT/a/'validation/reimport_qa.json')
    production={'date':'2026-11-05','stage':'prepared art review candidate','actor':a,'triangles':parts['triangles'],'rigid_groups':parts['parts'],'bones':parts['bones'],
      'surface_count':runtime['metrics']['surfaces'],'clips':{n:{'seconds':v['seconds'],'loop':v['loop']} for n,v in parts['clips'].items()},
      'runtime_checks':runtime['checks'],'gpu_captures':runtime['captures'],'source_and_reimport_qa_pass':True,'parity':parity[a],
      'remaining_warnings':{'source':sourceqa['warnings'],'reimport':reimportqa['warnings']},
      'warning_adjudication':'UV/normal seams and rigid mating vertices stay separate; hidden opposing cap/panel faces and internal bearings are intentional. Source torso/shell boundaries remain open; no watertight or arbitrary contact claim. Rest support clearance is intentional.',
      'textures':'shared 1024 color/OpenGL normal/ORM, R=1 without AO; 128 emission for base actors; armour has one opaque material and no runtime glow',
      'source_blend':f'{a}_game_v1.blend','source_sha256':sha(base/f'{a}_game_v1.blend'),'runtime_glb':f'{a}_v1.glb','runtime_sha256':sha(base/f'{a}_v1.glb'),
      'limitations':['Prepared assets and review helpers only; no new targeting, damage, lifetime, resource or node-selection integration.','Baked destruction starts from its authored initial pose; arbitrary interruption/blend, inter-part/terrain collision and final performance are not certified.','Optional 1–3 number decals remain a future instance accessory; base meshes are reused without them.','Full compatible skeleton is duplicated for supplemental armour; further skeleton/instance optimization is deferred until gameplay integration.']}
    assert sha(ROOT/f'game/assets/actors/automation_batch2/{a}_v1/{a}_v1.glb')==production['runtime_sha256']
    productions[a]=production;dump(base/'production.json',production)
    (base/'.gitignore').write_text('*.blend1\n*_geometry.blend\n*_static.glb\n',encoding='utf8')
    table='\n'.join(f"| `{n}` | {v['seconds']:g}s | {'루프' if v['loop'] else '단발'} |" for n,v in parts['clips'].items())
    detail=("부품이 위에서 내려와 발→다리→몸통→팔→머리 순으로 맞물린다. 바이저는 1.10–1.20초에 켜진다. `slam` 피해 접점은 **0.55초**, 두 주먹의 최소 높이 12mm, 두 주먹 사이 `Socket_attack`이다. `walk` 1.2초 / 2.6m/s / **3.12m 주기 거리**. 손목 실린더와 로드는 고정 길이이며 미끄러질 뿐 늘어나지 않는다. 증기는 준비용 presentation helper의 6개 소형 빌보드다."
      if a=='giant' else "`pulse`의 **0초**에 망치가 종에 접근한다(측정 0.622mm, 반 주기에는 50.4mm 이격). 1초에 셔터가 한 바퀴 돈다. `deploy` 기둥은 0.20m를 슬라이드하고 다리는 40도 펴진다. 소등·시동 발광은 준비용 presentation helper가 처리한다. 6m 범위 고리·음파·종소리는 후속 게임 FX 범위다."
      if a=='beacon' else f"추가 부품만 담긴 GLB다. 기본 {'hound_v2' if a=='hound_armour' else 'giant_v1'}와 같은 원점에 놓고 **같은 클립·초 단위 시간**으로 두 AnimationPlayer를 샘플링한다. 전체 부모 노드를 **{parts['node_scale']:g}배**로 설정한다. 기본 메시·UV·노멀·웨이트·본 rest·6개 기존 동작은 별도 검증에서 일치한다. 평상시 본 위치는 기본과 같으며, `death` {parts['death_armour_detach_seconds']:g}초부터 장갑만 독립적으로 낙하한다. 추가 GLB의 소켓은 중복이므로 게임 접점은 기본 리그에서 읽는다.")
    readme=f"""# {NAMES[a]} v1

2026-11-05. **게임 연결 전 모델·모션 검토 후보**. [통합 검토](../../../../reports/automation_batch2_complete_v1/review.html), [parts.json](parts.json), [검증 기록](production.json).

{DESCS[a]}

- {parts['triangles']:,} 삼각형 / {parts['parts']} 강체 그룹 / {parts['bones']} 본 / {runtime['metrics']['surfaces']} 런타임 재질.
- 편집 원본: [{a}_game_v1.blend]({a}_game_v1.blend). 텍스처가 packed되어 있고 대기/신호 상태로 열린다.
- 게임용: `game/assets/actors/automation_batch2/{a}_v1/`의 GLB·parts·import 설정·post-import 스크립트를 함께 복사한다.
- Blender +Y 전방이 GLB/Godot −Z 전방으로 변환된다. 미터 단위, Y up, 바닥 중심 원점, 단위 오브젝트 배율.
- 정점별 하나의 본에 100% 연결. 삼각형은 그룹 경계를 넘지 않고 부품의 애니메이션 배율은 1이다.
- {'새 장갑의 절삭면·도장·황동 재질을' if a.endswith('_armour') else 'Tripo 원본 2K 재질을'} 1K 색·OpenGL 노멀·ORM으로 베이크했다. ORM R=1로 별도 AO 베이크는 없다. 기본형은 128px 발광 맵과 독립 발광 재질, 추가 장갑은 불투명 재질 하나다.

## 클립과 접점

| 클립 | 길이 | 방식 |
|---|---:|---|
{table}

{detail}

`parts.json`에 그룹별 본·부모·피벗, 소켓, 그림자 반경을 기록했다. **24fps + 정확한 이벤트/끝점/접지 subframe 키**를 보존해야 한다. 상수 트랙 유지, optimizer/compression 비활성화만으로는 Godot 재샘플링을 막을 수 없어 `import_exact_animation.gd`가 원본 GLB 키를 복원한다. 리뷰 MP4의 루프는 정확한 반복 길이를 위해 30fps로 촬영한 것이며 원본 클립 시간은 바뀌지 않는다.

기본형 발광·증기는 `game/tests/helpers/automation_batch2_visual.gd`의 `sample(model, actor, clip, seconds)`로 프레임을 지정한다. pause/seek에 결정적이며 매 인스턴스 발광 재질만 복사하고 텍스처·메시는 공유한다. 추가 장갑의 Blender 파일에는 기본 몸체 참고 리그도 들어 있다. 기본 리그의 `BasePreview_*`와 장갑 리그의 같은 이름 클립을 동일 시각에 샘플링해야 함께 움직인다.

## 검증과 범위

저장 원본·새 GLB import의 오류 0. 120Hz 바닥/강체/루프 검사, 정확한 키 복원과 Blender↔Godot 본 위치 비교, 실제 GPU 촬영을 통과했다. 현재 입력 해시는 [delivery_manifest.json](../../../../reports/automation_batch2_complete_v1/delivery_manifest.json)에 있다.

원본 외피의 열린 경계, UV·노멀 이음 정점, 내부 축·맞닿는 장갑 뒷면은 보존했다. 해당 경고의 실제 목록은 production.json을 따른다. 임의 자세 충돌·경사/벽·파편끼리의 물리 접촉·최종 성능·사용자 외형 승인은 이 검증에 포함되지 않는다. 붕괴는 지정 시작 자세에서 구운 동작이다. 게임 규칙·표적·실제 FX·노드 전환 연결은 별도 코드 작업이며 사양 문서는 수정하지 않았다.

생성/재현 스크립트는 `tools/build_{'automation_armour_v1' if a.endswith('_armour') else a+'_game_v1'}.py`, 애니메이션은 `{'tools/finish_automation_armour_v1.py' if a.endswith('_armour') else 'tools/animate_'+a+'_game_v1.py'}`, 공통 export/QA는 `tools/export_automation_actor.py`, `tools/validate_automation_actor.py`다. `*_geometry.blend`와 `*_static.glb`는 로컬 중간 산출물이며 최종 전달 파일은 위 packed 원본과 애니메이션 GLB다.
"""
    (base/'README.md').write_text(readme,encoding='utf8')
    review_data[a]={'name':NAMES[a],'description':DESCS[a],'parts':parts,'production':production,'videos':{c:{'url':f'{a}/videos/{c}.mp4','duration':v['seconds'],'loop':v['loop'],'label':CLIP_NAMES[c]} for c,v in parts['clips'].items()}}

catalog['actors']={
 'hound':{'base':'res://assets/actors/automation_batch2/hound_v2/hound_v2.glb','parts':'res://assets/actors/automation_batch2/hound_v2/parts.json','variants':{'base':{'scale':1.,'instances':1},'pack':{'scale':.8,'instances':3,'new_mesh':False},'heavy':{'scale':1.2,'armour':'res://assets/actors/automation_batch2/hound_armour_v1/hound_armour_v1.glb'}}},
 'beacon':{'base':'res://assets/actors/automation_batch2/beacon_v1/beacon_v1.glb','parts':'res://assets/actors/automation_batch2/beacon_v1/parts.json','variants':{'base':{'scale':1.,'instances':1}}},
 'giant':{'base':'res://assets/actors/automation_batch2/giant_v1/giant_v1.glb','parts':'res://assets/actors/automation_batch2/giant_v1/parts.json','variants':{'base':{'scale':1.,'instances':1},'multiple':{'scale':.75,'instances':3,'new_mesh':False},'enhanced':{'scale':1.1,'armour':'res://assets/actors/automation_batch2/giant_armour_v1/giant_armour_v1.glb'}}}}
catalog['presentation_helper']='res://tests/helpers/automation_batch2_visual.gd';dump(ASSETS/'catalog.json',catalog)
videos['multiple']=video(OUT/'combined/multiple',OUT/'combined/multiple.mp4',24)
dump(OUT/'video_validation.json',videos)
combined=load(OUT/'combined/runtime_validation.json');assert combined['passed']
events=load(OUT/'event_validation.json');assert all(x['passed'] for x in events.values())
old=load(ROOT/'reports/hound_game_v2/delivery_manifest.json');protected={p:v for p,v in old['files'].items() if p.startswith(('assets/actors/automation_batch2/hound_game_v2/','game/assets/actors/automation_batch2/hound_v2/'))}
assert all(sha(ROOT/p)==v['sha256'] for p,v in protected.items());dump(OUT/'hound_preservation.json',{'passed':True,'files_checked':len(protected),'files':protected})
raws={}
for a in ('beacon','giant'):
    source=ASSETS/f'{a}_tripo_v1';p=load(source/'production.json');raws[a]=p
    for n,h in p['source_hashes'].items():assert sha(source/'source'/n)==h
    inventory=load(OUT/f'{a}_source/segmented/inventory.json')
    (source/'README.md').write_text(f"# {NAMES[a]} · Tripo 생성 원본\n\n기존 원화 `concept_v1/{'lure_beacon_v1' if a=='beacon' else 'giant_automaton_v1'}.png`를 사용했다.\n\nTripo H3.1 HD, private, 80k 목표, PBR 2K, Ultra/AI completion off. 생성 30 + Fine 분할 40 = **70 크레딧**. 모델 ID `{p['model_id']}`. 원본과 실제 내려받은 분할 GLB, packed Blender import를 보존한다. `source/` GLB는 수정하지 않았다.\n\n게임용 파생물은 [../{a}_game_v1/README.md](../{a}_game_v1/README.md)다. 원본 QA는 AI 생성 외피의 이음·겹침 등을 보여 주는 진단 자료이며 원본 자체를 오류 0이라고 주장하지 않는다. 실제 분할 다운로드는 {'76 부품 / 76,236 삼각형' if a=='beacon' else '79 부품 / 77,782 삼각형'}이다. Tripo UI의 {'76,276' if a=='beacon' else '80 부품 / 77,870'} 표시와 내려받은 파일 수치가 달라 실제 파일을 기준으로 후속 작업했다.\n\n설정·원본 해시는 [production.json](production.json), 생성 화면 증거와 원본/파생물 비교는 [통합 검토](../../../../reports/automation_batch2_complete_v1/review.html)에 있다.\n",encoding='utf8')

checks=sum(p['runtime_checks'] for p in productions.values())+combined['checks'];captures=sum(p['gpu_captures'] for p in productions.values())+combined['captures']
summary={'current_runtime_checks':checks,'current_gpu_captures':captures,'saved_source_poses':sum(load(OUT/a/'validation/saved_source.json')['poses'] for a in ACTORS),'parity_bones':sum(p['compared_bone_origins'] for p in parity.values()),'tripo_credits_this_pass':140,'hound_base_files_preserved':len(protected)}
dump(OUT/'summary.json',summary)
data=json.dumps(review_data,ensure_ascii=False).replace('</','<\\/')
page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>자동화 2차 · 모델과 모션</title><style>
:root{color-scheme:dark;font-family:system-ui,"Malgun Gothic",sans-serif;background:#111a21;color:#dfe8e8}*{box-sizing:border-box}body{margin:0}main{max-width:1280px;margin:auto;padding:34px 22px 70px}h1{font-size:36px;margin:6px 0 14px}h2{font-size:26px;margin-top:42px}p{line-height:1.75;color:#b4c7cc}a{color:#73d9d1}small,.muted{color:#92a8b0}.tag{color:#d0b47a;letter-spacing:.16em;font-size:12px}.card{background:#1b2831;border:1px solid #344751;border-radius:14px;padding:20px;margin:20px 0}.wide{width:100%;display:block;border-radius:8px}video{width:100%;max-height:590px;background:#101a21;border-radius:8px}button,select{font:inherit;color:#dfe8e8;background:#273b46;border:1px solid #49616d;border-radius:7px;padding:8px 12px;margin:4px;cursor:pointer}button.active{background:#16534f;border-color:#60c3b4}.toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:4px;margin:10px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:12px;border-bottom:1px solid #344751}th{color:#9fb8c1}details{margin-top:16px}summary{cursor:pointer;color:#8fd8cb}code{color:#d6c18b}footer{margin-top:40px;color:#91a8b0}figure{margin:8px 0}figcaption{font-size:13px;color:#9bb0b6;margin-top:8px}@media(max-width:750px){.grid{grid-template-columns:1fr}h1{font-size:27px}main{padding:24px 12px}table{font-size:13px}}
</style><main><div class="tag">WITCH / AUTOMATION BATCH 02 / 2026.11.05</div><h1>세 소환체, 기본형부터 강화형까지</h1><p>Tripo 원본을 구동 단위로 나누고 경량화·강체 리깅·모션을 준비했다. 현재는 <b>게임 연결 전 아트 검토본</b>이다. 기존 수렵견 기본형은 그대로 보존하고, 신호기·거대 인형과 두 추가 장갑 세트를 완성했다.</p>
<nav class="toolbar"><a href="#scale">실제 크기</a> · <a href="#beacon">신호기</a> · <a href="#giant">거대 인형</a> · <a href="#hound_armour">중장 추적기</a> · <a href="#giant_armour">단일 강화</a> · <a href="#qa">검증·원본</a></nav>
<section id="scale"><h2>1.75배 게임 카메라</h2><p>1280×800, 현재 게임 카메라 크기와 기울기를 유지했다. 같은 조명 아래 마녀·기본 세 모델·기존 소환물·적을 비교한다. 조명은 검토용이며 본 게임 조명은 바꾸지 않았다.</p>
<img id="lineup" class="wide" src="combined/native_lineup_front.jpg"><div class="toolbar"><button onclick="document.querySelector('#lineup').src='combined/native_lineup_front.jpg'">정면 방향</button><button onclick="document.querySelector('#lineup').src='combined/native_lineup.jpg'">반대 방향</button></div>
<div class="card"><h3>기본형과 추가 장갑</h3><img class="wide" src="combined/enhanced_lineup_front.jpg"><p>중장 추적기 1.2배, 거대 단일 강화 1.1배. 추가 장갑만 별도 GLB로 겹치며 기본 정점·리그·동작은 보존한다.</p></div>
<div class="card"><h3>다수 운용 · 같은 기본 메시 공유</h3><video controls loop muted playsinline preload="metadata" src="combined/multiple.mp4" poster="combined/multiple/000.jpg"></video><p>사냥 무리 0.8배 × 3 / 거대 다수 운용 0.75배 × 3. 6초 영상은 두 보행 주기가 함께 제자리로 돌아오는 지점에서 반복한다. 개체 번호 표식은 후속 장식으로 남겨 두었다.</p></div></section>
<div id="actors"></div>
<section id="qa"><h2>검증과 넘겨줄 파일</h2><p>SUMMARY_PLACEHOLDER</p><table><thead><tr><th>모델</th><th>삼각형</th><th>강체 그룹 / 본</th><th>클립</th></tr></thead><tbody id="stats"></tbody></table>
<p>신호기 망치는 신호 시작에서 종까지 약 0.622mm, 반 주기에는 50.4mm 떨어진다. 거대 인형은 0.55초에 양쪽 주먹 최저점이 바닥 위 12mm에 이른다. 루프 끝점·단일 본 웨이트·고정 길이·120Hz 바닥 검사와 저장 원본↔Godot 위치 비교를 통과했다.</p>
<div class="grid"><figure><img class="wide" src="combined/slam_contact_front.jpg"><figcaption>거대 인형 · 0.55초 타격 접점</figcaption></figure><figure><img class="wide" src="combined/slam_contact_side.jpg"><figcaption>같은 시각 · 측면 접지</figcaption></figure></div>
<details><summary>Tripo 생성·분할 원본과 사용량</summary><p>두 모델 모두 기존 원화 → Tripo H3.1 HD / private / 2K PBR → Fine 분할. 모델당 생성 30 + 분할 40, 이번 작업 합계 140 크레딧. 원본 GLB는 수정하지 않았다. UI 수치와 다운로드 수치 차이는 각 원본 README에 기록했다.</p><div class="grid"><img class="wide" src="tripo/beacon_segmented_ui.png"><img class="wide" src="tripo/giant_segmented_ui.png"></div><p><a href="../../assets/actors/automation_batch2/beacon_tripo_v1/README.md">신호기 원본</a> · <a href="../../assets/actors/automation_batch2/giant_tripo_v1/README.md">거대 인형 원본</a></p></details>
<details><summary>남겨 둔 경고와 검증 범위</summary><p>AI 원본 외피의 열린 경계, UV/노멀 이음 정점, 내부 축, 숨겨진 맞댐 면은 보존했다. 새 QA의 오류는 0이며 경고의 실제 목록은 각 production.json에 남아 있다. 새 장갑은 기본 몸체와 함께 QA를 수행한다. 단독 장갑은 몸체에 붙여 쓰는 부품이다.</p><p>파괴는 지정된 시작 자세에서 구운 동작이다. 임의 취소·블렌드 자세, 파편끼리·경사·벽의 실시간 충돌과 최종 성능을 검증한 것은 아니다. 추가 장갑은 호환 본을 복제한 별도 리그다. 게임의 스킬 규칙·표적·피해·범위 FX·노드 전환 연결과 최종 외형 선택은 다음 단계다.</p></details>
<p><a href="../../assets/actors/automation_batch2/README.md">전체 인계 README</a> · <a href="../../assets/actors/automation_batch2/catalog.json">모델·노드 경로</a> · <a href="delivery_manifest.json">검증·입력 해시</a> · <a href="../hound_game_v2/review.html">기존 수렵견 기본형 검토</a></p></section><footer>PREPARED ART · 전체 GLB 폴더의 import 설정과 post-import 스크립트를 함께 유지한다. 커밋·푸시는 수행하지 않았다.</footer></main><script>
const actors=DATA_PLACEHOLDER;
for(const [key,a] of Object.entries(actors)){
 const section=document.createElement('section');section.id=key;section.className='card';
 section.innerHTML=`<h2>${a.name}</h2><p>${a.description}</p><div class="toolbar clips"></div><video controls loop muted playsinline preload="metadata" poster="${key}/runtime/front.jpg"></video><div class="toolbar"><button class="step">1 프레임 앞으로</button><span>속도</span><select><option value=".25">0.25×</option><option value=".5">0.5×</option><option value="1" selected>1×</option></select><span class="time"></span></div><p class="caption"></p><details><summary>확대 원본 · 부품 · 와이어</summary><img class="wide" loading="lazy" src="${key}/geometry_sheet.jpg"><img class="wide" loading="lazy" src="${key}/death_sheet.jpg"></details><p><a href="../../assets/actors/automation_batch2/${key}${key.endsWith('_armour')?'_v1':'_game_v1'}/README.md">편집 원본·게임 파일·클립 설명</a></p>`;
 document.querySelector('#actors').appendChild(section);const v=section.querySelector('video');let selected;
 for(const [clip,c] of Object.entries(a.videos)){const b=document.createElement('button');b.textContent=c.label;b.onclick=()=>{selected=c;v.src=c.url;v.load();section.querySelectorAll('.clips button').forEach(x=>x.classList.toggle('active',x===b));section.querySelector('.caption').textContent=`${clip} · 원본 ${c.duration}초 ${c.loop?'루프 / 검토 영상 30fps, 두 주기':'단발 / 앞뒤 정지 구간 포함'}`;};section.querySelector('.clips').appendChild(b);if(clip===(key==='beacon'?'pulse':key==='hound_armour'?'run':'slam'))b.click();}
 v.addEventListener('timeupdate',()=>{const t=Math.max(0,v.currentTime-(selected.loop?0:5/24));section.querySelector('.time').textContent=`클립 ${Math.min(selected.duration,selected.loop?t%selected.duration:t).toFixed(2)}초`;});
 section.querySelector('select').onchange=e=>v.playbackRate=Number(e.target.value);section.querySelector('.step').onclick=()=>{v.pause();v.currentTime+=1/(selected.loop?30:24);};
 const row=document.createElement('tr');row.innerHTML=`<td>${a.name}</td><td>${a.parts.triangles.toLocaleString()}</td><td>${a.parts.parts} / ${a.parts.bones}</td><td>${Object.keys(a.videos).length}</td>`;document.querySelector('#stats').appendChild(row);
}
</script></html>'''
page=page.replace('DATA_PLACEHOLDER',data).replace('SUMMARY_PLACEHOLDER',f"현재 파일 기준 게임 엔진 {checks:,}개 확인, GPU {captures:,}장 촬영. 저장 원본 {summary['saved_source_poses']:,}개 자세, 본 위치 {summary['parity_bones']:,}개 비교. 기존 수렵견 파일 {len(protected)}개 해시 일치.")
(OUT/'review.html').write_text(page,encoding='utf8')
(OUT/'.gitignore').write_text('local/\n**/local/\n**/runtime/motion_*/\n**/runtime/poses_*/\ncombined/multiple/\n',encoding='utf8')
# The multiple-video poster must remain in the offline package.
shutil.copy2(OUT/'combined/multiple/000.jpg',OUT/'combined/multiple_poster.jpg')
page=page.replace('poster="combined/multiple/000.jpg"','poster="combined/multiple_poster.jpg"');(OUT/'review.html').write_text(page,encoding='utf8')
dump(OUT/'production_summary.json',{'summary':summary,'production':productions,'raw_sources':raws})
print('PACKAGE_READY',json.dumps(summary),flush=True)
