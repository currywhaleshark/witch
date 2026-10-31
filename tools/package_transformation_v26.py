"""Package v26 entry checks and actual game frames, side by side with v25, for user review."""
from pathlib import Path
from datetime import datetime, timezone
import json, hashlib, re, subprocess
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]; OUT = ROOT/'reports/transformation_v26'; V25 = ROOT/'reports/transformation_v25'
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(name, data): (OUT/name).write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

HTML = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>마녀도시 · 입장 변신 v26</title>
<style>
:root{color-scheme:dark;--bg:#101b20;--panel:#192a30;--line:#34464a;--ink:#edf2ed;--muted:#a9bbb9;--teal:#96dfcc;--gold:#c8aa78}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1280px;margin:auto;padding:40px 24px 55px}header{display:flex;align-items:end;justify-content:space-between;gap:24px;margin-bottom:22px}.eyebrow{font-size:11px;letter-spacing:.16em;color:var(--gold)}h1{font-size:30px;font-weight:650;letter-spacing:-.04em;margin:8px 0}p{margin:0;color:var(--muted)}.badge{border:1px solid var(--line);border-radius:24px;padding:7px 16px;color:var(--teal);white-space:nowrap;font-size:13px}.viewer{border:1px solid var(--line);border-radius:16px;overflow:hidden;background:#0b1218}.pair{display:grid;grid-template-columns:1fr 1fr;gap:2px;background:var(--line)}.stage{position:relative;aspect-ratio:16/10;background:#12191c}.stage img{width:100%;height:100%;object-fit:cover;display:block}.tag{position:absolute;left:14px;top:12px;background:#101b20dd;border:1px solid var(--line);padding:3px 11px;border-radius:16px;font-size:12px}.tag.new{color:var(--teal);border-color:#8ed6c459}.phase{position:absolute;right:14px;top:12px;background:#101b20dd;padding:3px 11px;border-radius:16px;font-size:12px;color:var(--gold)}.controls{padding:14px 18px;background:var(--panel)}.toolbar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:12px}button,select{border:1px solid var(--line);border-radius:8px;background:#142228;color:var(--ink);font:inherit;font-size:13px;padding:8px 12px;cursor:pointer}button:hover,select:hover{border-color:var(--teal)}button:focus-visible,select:focus-visible,input:focus-visible{outline:2px solid var(--teal);outline-offset:3px}.primary{background:#96dfcc;color:#11272a;border-color:var(--teal);min-width:83px}.spacer{flex:1}.time{font:12px ui-monospace,monospace;color:var(--muted)}input[type=range]{width:100%;accent-color:var(--teal);cursor:pointer}label{font-size:12px;color:var(--muted)}.caption{font-size:13px;padding:12px 0}table{border-collapse:collapse;width:100%;font-size:13px;margin-top:10px}td,th{border-bottom:1px solid var(--line);padding:7px 8px;text-align:left;vertical-align:top}th{color:var(--gold);font-weight:600}details{border-top:1px solid var(--line);margin-top:20px;padding:16px 0;font-size:13px;color:var(--muted)}summary{cursor:pointer;color:var(--ink)}details p{margin-top:10px}a{color:var(--teal)}footer{font-size:12px;color:#809594;margin-top:24px}@media(max-width:760px){main{padding:20px 10px}header{display:block}h1{font-size:24px}.badge{display:inline-block;margin-top:10px}.pair{grid-template-columns:1fr}.spacer{display:none}}
</style><main><header><div><div class="eyebrow">WITCH / FIELD ENTRY / V26</div><h1>입장 변신 · 전신 연기 개선</h1><p>같은 게임 장면, 같은 시간축에서 이전(v25)과 개선(v26)을 나란히 봅니다.</p></div><span class="badge">3초 · 게임 입장에 연결됨</span></header>
<section class="viewer"><div class="pair"><div class="stage"><img id="old" alt="v25 입장 변신"><span class="tag">이전 v25</span></div><div class="stage"><img id="new" alt="v26 입장 변신"><span class="tag new">개선 v26</span><span class="phase" id="phase"></span></div></div>
<div class="controls"><div class="toolbar"><button id="play" class="primary">일시정지</button><button id="restart">처음부터</button><label for="scene">장면</label><select id="scene"></select><span class="spacer"></span><label for="speed">재생 속도</label><select id="speed"><option value=".25">0.25배</option><option value=".5" selected>0.5배</option><option value="1">1배</option></select><span class="time" id="time">0.00 s</span></div><label for="scrub" style="position:absolute;clip:rect(0,0,0,0)">프레임 탐색</label><input id="scrub" type="range" min="0" max="99" value="0"></div></section>
<p class="caption" id="caption"></p>
<table><tr><th>시간</th><th>v25</th><th>v26</th></tr>
<tr><td>0–0.3초</td><td>완전히 멈춤</td><td>도착해 들숨, 고개를 듦</td></tr>
<tr><td>0.3–1.15초</td><td>팔만 천천히 나감</td><td>조립을 알아채고 고개를 돌려 따라 봄, 상체가 돌고 체중을 옮김</td></tr>
<tr><td>1.0–1.4초</td><td>손이 지팡이 앞에서 대기</td><td>살짝 당겼다가 빠르게 뻗음, 오른발 반걸음, 몸을 기울임</td></tr>
<tr><td>1.4–1.6초</td><td>멈춤</td><td>지팡이 무게에 손목·무릎이 처짐</td></tr>
<tr><td>1.5–2.1초</td><td>일직선 이동, 양손 동시 출발</td><td>호를 그리며 대기 자세로, 가슴이 지나쳤다 돌아오고 왼손이 늦게 붙음</td></tr>
<tr><td>2.1–3.0초</td><td>0.9초 굳어 있음</td><td>살짝 웅크렸다가 2.40초 교체 순간 가슴을 펴고 턱을 든 뒤 안착</td></tr></table>
<details><summary>게임 연결과 확인 범위</summary><p>게임 이벤트 시점(조립 0.30–1.15초, 잡기 1.40초, 양손 2.10초, 교체 2.40초, 전투 3.00초)과 떠 있는 지팡이 위치는 v25와 같고, 입장 클립만 v26으로 바꿨습니다. 변신복 v4는 바이트 그대로입니다.</p><p>__CHECKS__개 런타임 검사, 저장 Blender 145개 자세, Python 외형 7개 검사, 실제 게임 663장을 기록했습니다. 변신 후 달리기·타격·캐스팅·경직·도약은 v26 쪽만 의미가 있으며 두 버전이 같은 동작입니다.</p><p>변신복의 국소 접촉·치마 접힘 한계는 그대로입니다. 실시간 천 물리나 모든 자세의 무관통 검증은 아닙니다. <a href="delivery_manifest.json">검증·해시</a> · <a href="../../assets/characters/player/3d/source/middle_school_v1/transformation_v26/README.md">제작·인계</a> · <a href="../transformation_v25/review.html">v25 단독 리뷰</a></p></details><footer>현재 게임 장면으로 촬영한 검토본 · 2026.10.31</footer></main>
<script>
const scenes=__SCENES__, byId=Object.fromEntries(scenes.map(s=>[s.id,s]));
const select=document.querySelector('#scene'), oldImg=document.querySelector('#old'), newImg=document.querySelector('#new'), scrub=document.querySelector('#scrub'), play=document.querySelector('#play'), speed=document.querySelector('#speed');
const phaseNames={civilian:'평상복 · 빈손',assembly:'지팡이 조립',grasp:'손에 쥐기',outfit:'의상 전환',ready:'전투 준비 완료'};
const captions={front:'앞쪽: 조립, 손잡기, 의상 교체.',native:'골목 시험 맵, 1.75배 기준 카메라의 실제 표시 크기.',back:'뒤쪽: 상체 회전과 의상 교체.',pause:'조립 도중 정지했다가 같은 자세에서 이어집니다.',run:'변신 후 달리기 (두 버전 동일 동작).',attack:'변신 후 기본 공격 (두 버전 동일 동작).',cast:'변신 후 캐스팅 (두 버전 동일 동작).',hit:'변신 후 경직 (두 버전 동일 동작).',jump:'변신 후 스프링 도약 (두 버전 동일 동작).'};
let scene=scenes[0], frame=0, playing=true, accumulator=0, last=performance.now();
for(const s of scenes){const o=document.createElement('option');o.value=s.id;o.textContent=s.label;select.append(o);}
function draw(){const n=String(frame).padStart(3,'0');const a=`../transformation_v25/review/${scene.id}/${n}.jpg`, b=`review/${scene.id}/${n}.jpg`;if(oldImg.getAttribute('src')!==a)oldImg.src=a;if(newImg.getAttribute('src')!==b)newImg.src=b;document.querySelector('#phase').textContent=(scene.paused[frame]?'일시정지 · ':'')+(phaseNames[scene.phases[frame]]||scene.label);document.querySelector('#time').textContent=(frame/scene.fps).toFixed(2)+' s';scrub.value=frame;}
function choose(id){scene=byId[id];select.value=id;frame=0;accumulator=0;scrub.max=scene.frames-1;document.querySelector('#caption').textContent=captions[id];draw();}
function setPlaying(v){playing=v;play.textContent=v?'일시정지':'재생';}
select.onchange=()=>choose(select.value);play.onclick=()=>setPlaying(!playing);document.querySelector('#restart').onclick=()=>{frame=0;accumulator=0;draw();setPlaying(true)};scrub.oninput=()=>{frame=Number(scrub.value);accumulator=0;setPlaying(false);draw()};
function tick(now){const d=Math.min((now-last)/1000,.1);last=now;if(playing&&!document.hidden){accumulator+=d*Number(speed.value);if(accumulator>=1/scene.fps){const skip=Math.floor(accumulator*scene.fps);accumulator-=skip/scene.fps;frame=(frame+skip)%scene.frames;draw();}}requestAnimationFrame(tick)}choose('front');requestAnimationFrame(tick);
</script></html>'''


def main():
    source = read(OUT/'source_validation.json'); export = read(OUT/'export.json'); build = read(OUT/'build_validation.json')
    assert source['passed'] and not source['failures'] and export['passed'] and build['passed']
    folder = 'assets/characters/player/3d/source/middle_school_v1/transformation_v26/'
    game = 'game/assets/characters/player/transformation_v26/'
    assert sha(ROOT/folder/'transformation_v26.blend') == source['source_sha256'] == export['source_sha256']
    assert sha(ROOT/game/'combat_transform_entry_v26.glb') == export['glb_sha256']
    outfit = ROOT/'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb'
    assert sha(outfit) == sha(ROOT/'assets/characters/player/3d/exports/transformed_fit_v4/outfit_transformed_v4.glb') == export['outfit_sha256']
    runs = {}; count = 0
    for name in ['import', 'transformation_v26', 'staff_visual', 'spring_jump_v24', 'player_visual', 'loadout_dash', 'review']:
        directory = OUT/name; execution = read(directory/'execution.json')
        assert execution['exit_code'] == 0 and not execution['changed_inputs'], (name, execution)
        assert execution['stderr_empty'] or execution['workspace_cache_diagnostic_only']
        inputs = read(directory/'inputs_after.json'); assert inputs == read(directory/'inputs_before.json')
        changed = [p for p, h in inputs.items() if sha(ROOT/p) != h]; assert not changed, (name, changed)
        runs[name] = {'execution': execution, 'inputs_current': True, 'inputs': inputs}
        if name not in ('import', 'review'):
            result = read(directory/'result.json'); assert not result['failures'] and result.get('passed', True)
            runs[name]['checks'] = len(result['checks']); count += len(result['checks'])
    test = subprocess.run(['python', '-m', 'unittest', 'tests.test_character_appearance'], cwd=ROOT, capture_output=True, text=True)
    assert test.returncode == 0, test.stderr
    save('appearance_validation.json', {'passed': True, 'exit_code': test.returncode, 'checks': 7, 'output': test.stdout+test.stderr,
         'inputs': {p: sha(ROOT/p) for p in ['tests/test_character_appearance.py', 'tools/character_appearance.py', 'assets/characters/player/3d/config/modular_character.spec.json']}})
    capture = read(OUT/'review/capture.json'); assert capture['passed'] and capture['captures'] == 663
    old = read(V25/'review/capture.json')
    scenes = []; images = []
    for scene in capture['sequences']:
        prior = next(s for s in old['sequences'] if s['id'] == scene['id']); assert prior['frames'] == scene['frames']
        for i in range(scene['frames']):
            p = OUT/'review'/scene['id']/f'{i:03}.jpg'
            with Image.open(p) as im: assert im.size == (1280, 800); im.verify()
            assert (V25/'review'/scene['id']/f'{i:03}.jpg').exists()
            images.append({'path': p.relative_to(OUT).as_posix(), 'sha256': sha(p)})
        scenes.append({'id': scene['id'], 'label': scene['label'], 'fps': scene['fps'], 'frames': scene['frames'],
                       'phases': [x['visual'].get('field_entry', {}).get('phase', 'ready') for x in scene['samples']], 'paused': [x['paused'] for x in scene['samples']]})
    assert len(images) == 663; save('capture_hashes.json', images)
    markup = HTML.replace('__SCENES__', json.dumps(scenes, ensure_ascii=False)).replace('__CHECKS__', str(count))
    (OUT/'review.html').write_text(markup, encoding='utf-8')
    (OUT/'review_syntax.js').write_text(re.search(r'<script>(.*?)</script>', markup, re.S).group(1), encoding='utf-8')
    subprocess.run(['node', '--check', str(OUT/'review_syntax.js')], check=True)
    for target in re.findall(r'(?:href|src)="([^"#]+)"', markup):
        if target != 'delivery_manifest.json': assert (OUT/target).exists(), target
    files = ['game/scripts/player_visual.gd', 'game/scripts/field_entry_transformation.gd', 'game/tests/transformation_v26.gd', 'game/tests/review_transformation_v26.gd',
             'assets/characters/player/3d/config/modular_character.spec.json', folder+'transformation_v26.blend', folder+'runtime_contract.json', folder+'README.md',
             'tools/build_transformation_v26.py', 'tools/finalize_transformation_v26.py', 'tools/render_transformation_v26_compare.py', 'tools/run_transformation_v26.ps1',
             'tools/package_transformation_v26.py', 'reports/transformation_v26/review.html', 'reports/transformation_v26/build_validation.json',
             'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb']
    files += [p.relative_to(ROOT).as_posix() for p in (ROOT/game).iterdir() if p.is_file()]
    save('delivery_manifest.json', {'id': 'transformation_v26', 'generated_utc': datetime.now(timezone.utc).isoformat(), 'passed': True,
        'status': 'Integrated into the main game entry; user art selection pending', 'replaces_clip': 'combat_transform_entry_v25',
        'build_checks': build['checks'], 'source_validation': {k: v for k, v in source.items() if k != 'rows'}, 'runtime_checks': count, 'appearance_checks': 7,
        'gpu_captures': 663, 'capture_scope': capture['scope'], 'runs': runs, 'hashes': {p: sha(ROOT/p) for p in files},
        'visually_inspected_frames': ['front/015.jpg', 'front/030.jpg', 'front/036.jpg', 'front/042.jpg', 'front/048.jpg', 'front/066.jpg', 'front/072.jpg', 'front/078.jpg', 'front/084.jpg', 'front/096.jpg',
                                      'back/036.jpg', 'back/048.jpg', 'back/066.jpg', 'back/084.jpg', 'back/096.jpg'],
        'limits': ['Only the entry clip changed; staff assembly, light/rings, outfit swap method, camera and audio are the v25 presentation.',
                   'Head turn is limited (34/20 degrees yaw, 32/14 pitch) because the eyes are painted; hair has no bones and follows the head.',
                   'Transformed v4 garment geometry/weights are unchanged; local cloth/hair contact remains. No live cloth or arbitrary-pose clearance.',
                   'The HTML script and image links were checked; browser interaction was not automated.']})
    print(json.dumps({'passed': True, 'runtime_checks': count, 'appearance_checks': 7, 'gpu_captures': 663, 'review': str(OUT/'review.html')}))


if __name__ == '__main__': main()
