"""Package the validated jump integration without relabelling historical plate evidence."""
import hashlib, json, re, subprocess
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image
from package_spring_dash_v1 import HTML

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/spring_jump_v24'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(name,data):(OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    source=read(OUT/'source_validation.json');export=read(OUT/'export.json')
    assert source['passed'] and not source['failures'] and export['passed']
    asset='assets/characters/player/3d/source/middle_school_v1/spring_jump_v24/'
    game='game/assets/characters/player/spring_jump_v24/'
    assert sha(ROOT/asset/'spring_jump_v24.blend')==source['source_sha256']==export['source_sha256']
    assert sha(ROOT/game/'combat_spring_jump_v24.glb')==export['glb_sha256']
    runs={};count=0
    for name in ['spring_jump_v24','spring_plate_v1','loadout_dash','hit_block','player_visual','build_windows','review']:
        folder=OUT/name;execution=read(folder/'execution.json')
        assert execution['exit_code']==0 and not execution['changed_inputs'],(name,execution)
        assert execution['stderr_empty'] or execution['workspace_cache_diagnostic_only']
        inputs=read(folder/'inputs_after.json');assert inputs==read(folder/'inputs_before.json')
        mismatches=[p for p,h in inputs.items() if sha(ROOT/p)!=h];assert not mismatches,(name,mismatches)
        runs[name]={'execution':execution,'inputs_current':True,'inputs':inputs}
        if name!='review':
            result=read(folder/'result.json');assert not result['failures'] and result.get('passed',True)
            runs[name]['checks']=len(result['checks']);count+=len(result['checks'])
    capture=read(OUT/'review/capture.json');assert capture['passed'] and capture['captures']==488
    sequences=[];images=[]
    for seq in capture['sequences']:
        for i in range(seq['frames']):
            p=OUT/'review'/seq['id']/f'{i:03}.jpg'
            with Image.open(p) as im:assert im.size==(1280,800);im.verify()
            images.append({'path':p.relative_to(OUT).as_posix(),'sha256':sha(p)})
        sequences.append({'id':seq['id'],'label':seq['label'],'fps':seq['fps'],'frames':seq['frames'],
                          'modes':[s['visual']['spring_jump']['mode'] if s['visual']['spring_jump']['mode']!='idle' else ('preparing' if s['visual']['state']=='spring_jump' else 'idle') for s in seq['samples']],
                          'paused':[s['paused'] for s in seq['samples']]})
    assert len(images)==488;save('capture_hashes.json',images)
    markup=HTML.replace('__SEQUENCES__',json.dumps(sequences,ensure_ascii=False)).replace('__CHECKS__',str(count))
    markup=markup.replace('2026.10.30','2026.10.31').replace('스프링 돌진 · 바닥 발판','스프링 돌진 · 낮은 도약')
    markup=re.sub(r'<p class="intro">.*?</p>','<p class="intro">제공한 Unarmed Jump의 움츠림·무릎 접기·착지 흐름을 현재 캐릭터에 옮겼습니다. 스프링판을 박차고 낮은 포물선을 그리며 앞으로 도약하고, 두 손으로 지팡이를 잡은 채 착지합니다.</p>',markup)
    markup=re.sub(r'<div class="facts">.*?</div>','<div class="facts"><span>낮은 도약 <b>약 32cm</b></span><span>기존 돌진 <b>0.2초 유지</b></span><span>착지 자세 <b>0.12초</b></span><span><b>양손 지팡이</b> 유지</span></div>',markup)
    markup=markup.replace('review/dash/000.jpg','review/side/000.jpg')
    markup=markup.replace('review/mechanism/008.jpg','review/side/010.jpg').replace('review/mechanism/035.jpg','review/side/016.jpg').replace('review/mechanism/075.jpg','review/side/025.jpg')
    markup=markup.replace('data-keyframe="8"','data-keyframe="10"').replace('data-keyframe="35"','data-keyframe="16"').replace('data-keyframe="75"','data-keyframe="25"')
    markup=markup.replace('01 · 빠르게 조립','01 · 움츠리고 이륙').replace('바닥판 → 코일과 가이드 → 발판','스프링판 조립과 준비 자세를 함께 진행')
    markup=markup.replace('02 · 압축 해제','02 · 낮은 포물선').replace('코일과 가이드가 늘어나며 전방으로 기울어짐','무릎을 접고 두 손으로 지팡이를 고정')
    markup=markup.replace('03 · 출발 지점에서 소멸','03 · 착지와 복귀').replace('부품이 살짝 벌어지고 빛과 함께 사라짐','착지 충격을 받은 뒤 대기·이동으로 복귀')
    markup=markup.replace('바닥판과 스프링이 조립되는 모습','발판 위에서 도약을 준비하는 캐릭터').replace('스프링이 펴져 발판이 올라간 모습','낮게 뛰어오르는 캐릭터').replace('작동을 마친 부품들이 사라지는 모습','도약을 마치고 착지하는 캐릭터')
    markup=markup.replace("['dash','native','mechanism','fast','cancel','pause','raised']","['side','front','native','fast','short','cancel','pause','raised']")
    markup=markup.replace('byId.dash','byId.side').replace("selectScene('dash')","selectScene('side')").replace("selectScene('mechanism')","selectScene('side')")
    captions={'side':'측면에서 실제 돌진 경로와 낮은 도약을 확인합니다. 0.25배 재생으로 이륙과 착지를 자세히 볼 수 있습니다.',
              'front':'몸통과 함께 움직이는 오른손 위·왼손 아래의 양손 지팡이 자세입니다.',
              'native':'현재 게임 카메라의 실제 표시 크기입니다. 캐릭터만 올라가며 그림자와 바닥 장치가 높이를 보여 줍니다.',
              'fast':'시전 속도 40: 준비만 더 빨라지고 도약 구간은 기존 돌진 시간에 맞춥니다.',
              'short':'가까운 지점으로 도약해도 짧은 착지 동작을 유지합니다.',
              'cancel':'이륙 전 큰 피격으로 취소되면 공중으로 올라가지 않고 피격 자세를 따릅니다.',
              'pause':'공중에서 멈추면 높이·모션·돌진이 함께 정지하고 같은 시점부터 재개합니다.',
              'raised':'골목의 높은 지면을 기준으로 도약하고 착지합니다.'}
    markup=re.sub(r'const captions = .*?;\n','const captions = '+json.dumps(captions,ensure_ascii=False)+';\n',markup)
    markup=re.sub(r'const modes=\{.*?\};','const modes='+json.dumps({'idle':'지면 / 대기','preparing':'도약 준비','flight':'공중 도약','landing':'착지'},ensure_ascii=False)+';',markup)
    markup=re.sub(r'<p class="note" id="caption">.*?</p>','<p class="note" id="caption">'+captions['side']+'</p>',markup)
    details=f'''<details><summary>파일과 확인 범위</summary><p>사용자가 제공한 Unarmed Jump FBX의 몸통·다리 동작을 축소하고 현재 양손 지팡이 자세에 맞췄습니다. 원본의 이동 곡선은 게임에 적용하지 않고, 기존 지상 돌진 위에 시각적인 포물선을 더합니다. 기존 발동·마나·재사용 대기·거리·충돌·피격 판정은 유지합니다.</p><p>Blender 저장본 97개 정수/반 프레임, 런타임 {count}개 검사와 488장 실제 게임 렌더를 기록했습니다. 캡처 재생은 무음입니다. 이번 화면은 외형 검토용이며 임의 의상 접촉이나 최종 성능 승인을 뜻하지 않습니다.</p><p><a href="delivery_manifest.json">검증 및 해시</a> · <a href="../../{asset}README.md">작업 인계</a> · <a href="../spring_dash_v1/review.html">이전 발판 시안</a></p></details>'''
    markup=re.sub(r'<details>.*?</details>',details,markup,flags=re.S)
    markup=markup.replace('Blender 제작 원본과 게임용 GLB를 함께 보관했습니다. 외형은 이번 검토를 위한 첫 시안입니다.','기존 캐릭터와 모션은 보존하고, 점프 클립을 추가해 스프링 돌진에 연결했습니다.')
    (OUT/'review.html').write_text(markup,encoding='utf-8')
    (OUT/'review_syntax.js').write_text(re.search(r'<script>(.*?)</script>',markup,re.S).group(1),encoding='utf-8')
    subprocess.run(['node','--check',str(OUT/'review_syntax.js')],check=True)
    files=['game/scripts/arena.gd','game/scripts/player_visual.gd','game/scripts/spring_jump_motion.gd','game/tests/spring_jump_v24.gd','game/tests/review_spring_jump_v24.gd',game+'combat_spring_jump_v24.glb',game+'runtime_contract.json',game+'combat_spring_jump_v24.glb.import',asset+'spring_jump_v24.blend',asset+'runtime_contract.json',asset+'README.md','tools/build_spring_jump_v24.py','tools/finalize_spring_jump_v24.py','tools/run_spring_jump_v24.ps1','tools/package_spring_jump_v24.py','reports/spring_jump_v24/review.html','reports/spring_jump_v24/capture_hashes.json']
    manifest={'id':'spring_jump_v24','generated_utc':datetime.now(timezone.utc).isoformat(),'passed':True,'status':'Integrated review candidate; user selection pending','source':read(ROOT/asset/'runtime_contract.json')['source'],
              'source_validation':source,'runtime_checks':count,'gpu_captures':488,'runs':runs,'capture_scope':capture['scope'],'hashes':{p:sha(ROOT/p) for p in files},
              'integration_scope':read(OUT/'integration_scope.json'),
              'visually_inspected_frames':['side/010.jpg','side/016.jpg','side/025.jpg','front/016.jpg','front/026.jpg','native/016.jpg','raised/016.jpg'],
              'limits':['The parabola is visual. The combat body remains grounded with existing wall/damage rules.','Height is a 0.32m visual origin arc; foot clearance also includes the authored knee tuck.','The 0.12s landing is presentation only and does not lock later combat input.','Raw FBX stays local/gitignored; no Mixamo source redistribution.','No live cloth, arbitrary outfit clearance or final performance approval.','Browser interaction was not automated; generated page script syntax and image integrity were checked.']}
    if (OUT/'approval.json').exists():
        manifest['status']='Selected for the current prototype; recorded validation limits remain'
        manifest['approval']=read(OUT/'approval.json')
        manifest['hashes']['reports/spring_jump_v24/approval.json']=sha(OUT/'approval.json')
    save('delivery_manifest.json',manifest)
    for p in re.findall(r'(?:href|src)="([^"#]+)"',markup):assert (OUT/p).exists(),p
    print(json.dumps({'passed':True,'runtime_checks':count,'gpu_captures':488,'review':str(OUT/'review.html')}))

if __name__=='__main__':main()
