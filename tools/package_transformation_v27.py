"""Package current v27 checks and actual game frames without claiming art approval."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports/transformation_v27'
OLD = ROOT / 'reports/transformation_v26'
SOURCE = 'assets/characters/player/3d/source/middle_school_v1/transformation_v27/'
GAME = 'game/assets/characters/player/transformation_v27/'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


HTML = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>마녀도시 · 변신 v27</title>
<style>
:root{color-scheme:dark;--bg:#101b20;--panel:#192a30;--line:#34464a;--ink:#edf2ed;--muted:#a9bbb9;--teal:#96dfcc;--gold:#c8aa78}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1440px;margin:auto;padding:32px 24px 48px}header{display:flex;align-items:end;justify-content:space-between;gap:24px;margin-bottom:20px}.eyebrow{font-size:11px;letter-spacing:.16em;color:var(--gold)}h1{font-size:29px;letter-spacing:-.04em;margin:7px 0}p{margin:0;color:var(--muted)}.badge{border:1px solid var(--line);border-radius:24px;padding:7px 16px;color:var(--teal);white-space:nowrap;font-size:13px}.viewer{border:1px solid var(--line);border-radius:14px;overflow:hidden;background:#0b1218}.pair{display:grid;grid-template-columns:1fr 1fr;gap:2px;background:var(--line)}.stage{position:relative;aspect-ratio:16/10;background:#12191c}.stage img{width:100%;height:100%;object-fit:contain;display:block}.tag{position:absolute;left:12px;top:10px;background:#101b20e8;border:1px solid var(--line);padding:3px 10px;border-radius:16px;font-size:12px}.tag.new{color:var(--teal)}.phase{position:absolute;right:12px;top:10px;background:#101b20e8;padding:3px 10px;border-radius:16px;font-size:12px;color:var(--gold)}.controls{padding:14px 18px;background:var(--panel)}.toolbar{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:10px}button,select{border:1px solid var(--line);border-radius:8px;background:#142228;color:var(--ink);font:inherit;font-size:13px;padding:8px 11px;cursor:pointer}button:hover,select:hover{border-color:var(--teal)}button:focus-visible,select:focus-visible,input:focus-visible{outline:2px solid var(--teal);outline-offset:3px}.primary{background:var(--teal);color:#11272a;min-width:83px}.spacer{flex:1}.time{font:12px ui-monospace,monospace;color:var(--muted)}input[type=range]{width:100%;accent-color:var(--teal)}label{font-size:12px;color:var(--muted)}.caption{font-size:13px;padding:12px 0}.notes{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-top:8px}.notes h2{font-size:15px;color:var(--gold);margin:0 0 6px}.notes p{font-size:13px}details{border-top:1px solid var(--line);margin-top:22px;padding-top:16px;font-size:13px;color:var(--muted)}summary{cursor:pointer;color:var(--ink)}details p{margin-top:9px}a{color:var(--teal)}footer{font-size:12px;color:#809594;margin-top:22px}.single .pair{grid-template-columns:1fr}.single #oldStage{display:none}@media(max-width:760px){main{padding:20px 10px}header{display:block}h1{font-size:24px}.badge{display:inline-block;margin-top:10px}.pair,.notes{grid-template-columns:1fr}.spacer{display:none}}
</style><main><header><div><div class="eyebrow">WITCH / TRANSFORMATION / V27</div><h1>의상은 빛을 따라, 머리는 한 박자 늦게</h1><p>지팡이를 잡는 v26 동작을 유지하고 의상 전환과 헤어 움직임을 다듬었습니다.</p></div><span class="badge">게임 기본값에 연결 · 검토본</span></header>
<section class="viewer" id="viewer"><div class="pair"><div class="stage" id="oldStage"><img id="old" alt="v26 기존 의상 전환"><span class="tag">이전 v26 · 일괄 교체</span></div><div class="stage"><img id="new" alt="v27 점진적인 의상 전환과 헤어 움직임"><span class="tag new">현재 v27 · 빛의 경계를 따라 교체</span><span class="phase" id="phase"></span></div></div>
<div class="controls"><div class="toolbar"><button id="play" class="primary">일시정지</button><button id="restart">처음부터</button><button id="outfit">의상 전환부터</button><button id="compare">현재만 크게</button><label for="scene">장면</label><select id="scene"></select><span class="spacer"></span><label for="speed">속도</label><select id="speed"><option value=".25">0.25배</option><option value=".5" selected>0.5배</option><option value="1">1배</option></select><span class="time" id="time"></span></div><input id="scrub" aria-label="프레임 탐색" type="range" min="0" max="99" value="0"></div></section>
<p class="caption" id="caption"></p><div class="notes"><div><h2>발끝에서 어깨로 올라가는 의상 전환</h2><p>2.12–2.85초 동안 빛이 지난 부분부터 바뀝니다. 교복과 변신복의 재질·문양을 유지합니다. 오른손 잡기 1.40초, 양손 정렬 2.10초, 전투 시작 3.00초는 그대로입니다.</p></div><div><h2>좌우·뒤쪽, 각각 두 마디 헤어 본</h2><p>두피와 앞머리는 안정시키고 아래 가닥이 고개를 늦게 따라오도록 했습니다. 변신 때 약하게 들렸다 가라앉으며, 달리기·타격에도 작은 반응을 줍니다. 몸체의 107본은 그대로입니다.</p></div></div>
<details><summary>확인 범위와 제작 자료</summary><p>런타임 __CHECKS__개 검사, 저장 Blender의 원래 29메시·107본·63액션 보존 및 헤어 73프레임, 재반입 GLB QA, 외형 레지스트리 7개 검사, 실제 게임 663장을 기록했습니다. 의상 전환 재질도 같은 자세·조명에서 원래 의상과 비교했습니다.</p><p>본 동작에 의한 보조 움직임입니다. 실시간 천/머리 충돌이나 모든 자세의 무관통, 최종 성능 승인은 아닙니다. 기존 치마/케이프 접촉 한계가 남아 있으며 새 치마 물리는 추가하지 않았습니다.</p><p><a href="delivery_manifest.json">검증·파일 해시</a> · <a href="../../assets/characters/player/3d/source/middle_school_v1/transformation_v27/README.md">작성 파일·인계</a> · <a href="../transformation_v26/review.html">이전 v26 리뷰</a></p></details><footer>실제 게임 렌더 · 별도 스튜디오 조명 없음 · 사용자 외형 검토 대기</footer></main>
<script>
const scenes=__SCENES__, byId=Object.fromEntries(scenes.map(s=>[s.id,s]));
const el=id=>document.getElementById(id), select=el('scene'), oldImg=el('old'), newImg=el('new'), scrub=el('scrub'), play=el('play'), speed=el('speed');
const captions={front:'앞쪽: 잡기 동작은 동일하며, 의상 전환과 머리 끝 움직임을 비교합니다.',native:'골목 시험 맵 · 사용자가 선택한 1.75배 카메라의 실제 표시 크기. 현재만 크게 버튼으로 확인할 수 있습니다.',back:'뒤쪽: 빛이 올라가며 케이프가 나타나고, 뒤쪽 머리가 늦게 따라옵니다.',pause:'조립 도중 일시정지했다가 이어지는 장면.',run:'변신 후 달리기 · 기존 달리기 모션에 헤어 보조 움직임.',attack:'변신 후 기본 공격 · 기존 공격 동작 유지.',cast:'변신 후 한 손 캐스팅 · 헤어와 케이프 접촉 확인.',hit:'변신 후 경직 · 몸체 동작에 대한 헤어 반응.',jump:'변신 후 스프링 도약 · 기존 점프 동작 유지.'};
const phases={civilian:'평상복 · 빈손',assembly:'지팡이 조립',grasp:'손에 쥐기',outfit:'의상 전환',ready:'전투 준비 완료'};
let scene=scenes[0], frame=0, playing=true, accumulator=0, last=performance.now();
for(const s of scenes){const o=document.createElement('option');o.value=s.id;o.textContent=s.label;select.append(o);}
function draw(){const n=String(frame).padStart(3,'0');const a=`../transformation_v26/review/${scene.id}/${n}.jpg`,b=`review/${scene.id}/${n}.jpg`;if(oldImg.getAttribute('src')!==a)oldImg.src=a;if(newImg.getAttribute('src')!==b)newImg.src=b;el('phase').textContent=(scene.paused[frame]?'일시정지 · ':'')+(phases[scene.phases[frame]]||scene.label);el('time').textContent=(frame/scene.fps).toFixed(2)+' s';scrub.value=frame;}
function choose(id){scene=byId[id];select.value=id;frame=0;accumulator=0;scrub.max=scene.frames-1;el('caption').textContent=captions[id];draw();}
function setPlaying(value){playing=value;play.textContent=value?'일시정지':'재생';}
select.onchange=()=>choose(select.value);play.onclick=()=>setPlaying(!playing);el('restart').onclick=()=>{frame=0;accumulator=0;draw();setPlaying(true)};el('outfit').onclick=()=>{if(!['front','native','back'].includes(scene.id))choose('front');frame=62;accumulator=0;draw();setPlaying(true)};
el('compare').onclick=()=>{const single=el('viewer').classList.toggle('single');el('compare').textContent=single?'이전과 나란히':'현재만 크게';};
scrub.oninput=()=>{frame=Number(scrub.value);accumulator=0;setPlaying(false);draw()};
function tick(now){const dt=Math.min((now-last)/1000,.1);last=now;if(playing&&!document.hidden){accumulator+=dt*Number(speed.value);if(accumulator>=1/scene.fps){const skip=Math.floor(accumulator*scene.fps);accumulator-=skip/scene.fps;frame=(frame+skip)%scene.frames;draw();}}requestAnimationFrame(tick)}choose('front');requestAnimationFrame(tick);
</script></html>'''


def main():
    build = read(OUT / 'build_validation.json')
    source = read(OUT / 'source_validation.json')
    qa = read(OUT / 'qa_exported_hair.json')
    assert source['passed'] and qa['pass'] and not qa['errors']
    assert sha(ROOT / SOURCE / 'transformation_v27.blend') == source['source_sha256'] == build['blend_sha256']
    assert sha(ROOT / GAME / 'hair_semilong_v27.glb') == build['glb_sha256']
    for name in ['hair_semilong_v27.glb', 'hair_contract.json']:
        assert (ROOT / GAME / name).read_bytes() == (ROOT / 'assets/characters/player/3d/exports/transformation_v27' / name).read_bytes()
    protected = ['game/assets/characters/player/transformation_v26/combat_transform_entry_v26.glb',
                 'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb']
    previous = read(OLD / 'delivery_manifest.json')
    for path in protected:
        assert sha(ROOT / path) == previous['hashes'][path]
    assert sha(ROOT / 'assets/characters/player/3d/source/middle_school_v1/transformation_v26/transformation_v26.blend') == build['source_sha256']
    runs = {}
    for name in ['transformation_v27', 'transformation_v27_regression', 'outfit_material_parity_v27', 'review']:
        directory = OUT / name
        execution = read(directory / 'execution.json')
        assert execution['exit_code'] == 0 and not execution['changed_inputs'] and not execution['stderr'], (name, execution)
        inputs = read(directory / 'inputs_before.json')
        changed = [path for path, value in inputs.items() if sha(ROOT / path).lower() != value.lower()]
        assert not changed, (name, changed)
        result = read(directory / ('capture.json' if name == 'review' else 'result.json'))
        assert result.get('passed', True) and not result.get('failures', []), (name, result)
        runs[name] = {'execution': execution, 'inputs_current': True, 'inputs': inputs,
                      'result': directory.relative_to(ROOT).as_posix() + ('/capture.json' if name == 'review' else '/result.json')}
    checks = read(OUT / 'transformation_v27/result.json')['checks'] + len(read(OUT / 'transformation_v27_regression/result.json')['checks'])
    test = subprocess.run(['python', '-m', 'unittest', 'tests.test_character_appearance'], cwd=ROOT, capture_output=True, text=True)
    assert test.returncode == 0, test.stderr
    save('appearance_validation.json', {'passed': True, 'checks': 7, 'output': test.stdout + test.stderr,
         'inputs': {path: sha(ROOT / path) for path in ['tests/test_character_appearance.py', 'tools/character_appearance.py', 'assets/characters/player/3d/config/modular_character.spec.json']}})
    capture = read(OUT / 'review/capture.json')
    assert capture['captures'] == 663
    prior = read(OLD / 'review/capture.json')
    scenes, images = [], []
    for scene in capture['sequences']:
        old_scene = next(s for s in prior['sequences'] if s['id'] == scene['id'])
        assert old_scene['frames'] == scene['frames']
        for i in range(scene['frames']):
            path = OUT / 'review' / scene['id'] / f'{i:03}.jpg'
            with Image.open(path) as picture:
                assert picture.size == (1280, 800)
                picture.verify()
            assert (OLD / 'review' / scene['id'] / f'{i:03}.jpg').is_file()
            images.append({'path': path.relative_to(OUT).as_posix(), 'sha256': sha(path)})
        scenes.append({'id': scene['id'], 'label': scene['label'], 'fps': scene['fps'], 'frames': scene['frames'],
                       'phases': [s['visual'].get('field_entry', {}).get('phase', 'ready') for s in scene['samples']],
                       'paused': [s['paused'] for s in scene['samples']]})
    save('capture_hashes.json', images)
    markup = HTML.replace('__SCENES__', json.dumps(scenes, ensure_ascii=False)).replace('__CHECKS__', str(checks))
    approval_path = OUT / 'approval.json'
    approval = read(approval_path) if approval_path.exists() else None
    if approval:
        markup = markup.replace('게임 기본값에 연결 · 검토본', '시험판용 선택 · 게임에 연결됨')
        markup = markup.replace('사용자 외형 검토 대기', '2026.11.01 사용자 선택 · 기록된 검증 한계 유지')
    (OUT / 'review.html').write_text(markup, encoding='utf-8')
    (OUT / 'review_syntax.js').write_text(re.search(r'<script>(.*?)</script>', markup, re.S).group(1), encoding='utf-8')
    subprocess.run(['node', '--check', str(OUT / 'review_syntax.js')], check=True)
    for target in re.findall(r'(?:href|src)="([^"#]+)"', markup):
        if target != 'delivery_manifest.json': assert (OUT / target).is_file(), target
    files = [SOURCE + 'transformation_v27.blend', SOURCE + 'README.md',
             'game/scripts/player_visual.gd', 'game/scripts/modular_character_runtime.gd',
             'game/scripts/field_entry_transformation.gd', 'game/scripts/outfit_reveal.gd',
             'game/scripts/hair_motion.gd', 'game/shaders/outfit_reveal.gdshader',
             'tools/character_appearance.py', 'tests/test_character_appearance.py',
             'assets/characters/player/3d/config/modular_character.spec.json',
             'reports/transformation_v27/review.html', 'reports/transformation_v27/source_validation.json',
             'reports/transformation_v27/qa_exported_hair.json', 'reports/transformation_v27/build_validation.json',
             'AGENTS.md', 'docs/09_character_art_pipeline.md'] + protected
    files += [p.relative_to(ROOT).as_posix() for p in (ROOT / GAME).iterdir() if p.is_file()]
    files += [p.relative_to(ROOT).as_posix() for p in (ROOT / 'tools').glob('*transformation_v27*') if p.is_file()]
    files += ['tools/check_hair_v27.py']
    files += ['game/tests/' + name + '.gd' for name in ['transformation_v27', 'transformation_v27_regression', 'review_transformation_v27', 'outfit_material_parity_v27']]
    if approval:
        files.append('reports/transformation_v27/approval.json')
    save('delivery_manifest.json', {'id': 'transformation_v27', 'generated_utc': datetime.now(timezone.utc).isoformat(),
        'passed': True, 'status': 'User-selected prototype presentation; integrated game default' if approval else 'Integrated game default; user art selection pending',
        'approval': approval,
        'default_game': 'v26 body/grasp clip with v27 clothed reveal and independent hair rig',
        'body_bones': 107, 'hair_bones': 8, 'hair_deform_segments': 6, 'hair_triangles': 25161,
        'source_validation': source, 'asset_qa': {'passed': True, 'report': 'qa_exported_hair.json', 'warnings': qa['warnings']},
        'runtime_checks': checks, 'appearance_checks': 7, 'gpu_material_comparisons': 2, 'gpu_captures': 663,
        'capture_scope': capture['scope'], 'runs': runs, 'hashes': {path: sha(ROOT / path) for path in files},
        'preserved_runtime_assets': {path: sha(ROOT / path) for path in protected},
        'visually_inspected_frames': ['front/066.jpg', 'front/071.jpg', 'front/075.jpg', 'front/078.jpg', 'front/087.jpg',
                                      'back/078.jpg', 'back/084.jpg', 'native/078.jpg', 'run/014.jpg', 'attack/015.jpg',
                                      'cast/012.jpg', 'hit/006.jpg', 'jump/004.jpg'],
        'limits': ['Hair uses bounded authored/inertial rotation, not live cloth or hair/cape collision.',
                   'Existing outfit geometry, weights and contact limits remain; no new skirt flare or arbitrary-pose clearance.',
                   'Temporary outgoing/incoming outfit previews add draw cost during 0.73 seconds; final performance budget not measured.',
                   'Previous v26 side-by-side frames are historical captures; current v27 includes concurrent unrelated arena work.',
                   'HTML syntax and all image paths checked; automatic file:// browser navigation was denied by browser policy, so browser interaction is unverified.',
                   'Earlier memory-failed and intermediate QA attempts are not final validation evidence.']})
    print(json.dumps({'passed': True, 'runtime_checks': checks, 'gpu_captures': 663, 'review': str(OUT / 'review.html')}))


if __name__ == '__main__':
    main()
