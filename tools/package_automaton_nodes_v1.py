"""Package the two automaton node models and actual gameplay captures."""
from pathlib import Path
import hashlib
import json
import math
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports/automaton_nodes_v1'
BASE = ROOT / 'assets/actors/automaton_nodes_v1'
RUNTIME = ROOT / 'game/assets/actors/automaton_nodes_v1'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execution_passed(execution):
    return (execution['exit_code'] == 0 and not execution['changed_inputs']
            and (execution['stderr_empty'] or execution['workspace_cache_diagnostic_only']))


def glb_audit(path, metadata, static=False):
    blob = path.read_bytes()
    size = struct.unpack_from('<I', blob, 12)[0]
    doc = json.loads(blob[20:20 + size])
    binary = blob[28 + size:]

    def values(index):
        accessor = doc['accessors'][index]
        view = doc['bufferViews'][accessor['bufferView']]
        fmt = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[accessor['componentType']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[accessor['type']]
        packed = struct.Struct('<' + fmt * width)
        offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        stride = view.get('byteStride', packed.size)
        divisor = {5121: 255, 5123: 65535}.get(accessor['componentType'], 1) if accessor.get('normalized') else 1
        return [tuple(v / divisor for v in packed.unpack_from(binary, offset + i * stride))
                for i in range(accessor['count'])]

    triangles = sum(doc['accessors'][p['indices']]['count'] // 3
                    for m in doc['meshes'] for p in m['primitives'])
    assert triangles == metadata['triangles'], path
    result = {'passed': True, 'triangles': triangles, 'meshes': len(doc['meshes']),
              'materials': len(doc['materials'])}
    if static:
        assert len(doc['meshes']) == len(metadata['parts']), path
        assert not doc.get('skins') and not doc.get('animations'), path
        result['rigid_parts'] = len(doc['meshes'])
    else:
        assert len(doc['skins']) == 1 and len(doc['skins'][0]['joints']) == metadata['bones'], path
        assert sorted(a['name'] for a in doc['animations']) == ['attack', 'death', 'explode', 'hit', 'idle', 'move'], path
        vertex_count = 0
        for mesh in doc['meshes']:
            for primitive in mesh['primitives']:
                weights = values(primitive['attributes']['WEIGHTS_0'])
                assert all(all(math.isfinite(w) for w in row) and abs(sum(row) - 1) < 1e-6
                           and sum(w > 1e-6 for w in row) == 1 for row in weights), path
                vertex_count += len(weights)
        result.update(bones=metadata['bones'], clips=6, weighted_vertices=vertex_count, maximum_influences=1)
    return result


checks = {}
phases = ['automaton_variant_a', 'automaton_variant_b', 'automaton_assembly',
          'turret_assembly', 'automaton_node_art_regression']
for phase in phases:
    result = read(OUT / phase / 'result.json')
    execution = read(OUT / phase / 'execution.json')
    checks[phase] = {'passed': not result['failures'] and execution_passed(execution),
                     'checks': result['checks'] if isinstance(result['checks'], int) else len(result['checks']),
                     'result': f'{phase}/result.json', 'execution': execution}
    if 'metrics' in result:
        checks[phase]['metrics'] = result['metrics']

for phase in phases + ['review']:
    before = read(OUT / phase / 'inputs_before.json')
    after = read(OUT / phase / 'inputs_after.json')
    assert before == after, phase
    # Early headless records also fingerprinted an unused GPU capture driver.
    # It was subsequently polished; it is a dependency only of the review run.
    relevant = {p: h for p, h in after.items()
                if phase == 'review' or p != 'game/tests/review_automaton_variants.gd'}
    assert all(sha(ROOT / path) == digest for path, digest in relevant.items()), phase

capture = read(OUT / 'review/capture.json')
for seq in capture['sequences']:
    assert len(list((OUT / 'review' / seq['id']).glob('*.jpg'))) == seq['frames'], seq['id']
    samples = seq['samples']
    assert all(s['allies'] == 0 for s in samples
               if s['simulation_seconds'] < seq['release_seconds'] - 1e-6), seq['id']
    if seq['cancel_at_fraction'] >= 0:
        assert all(s['allies'] == 0 for s in samples), seq['id']
        assert any(s.get('mode') == 'collapse' for s in samples), seq['id']
    else:
        live = [s for s in samples if s['allies']]
        assert live and all(s['appearance']['appearance_node'] == seq['variant'] for s in live), seq['id']
        if not seq['fight']:
            assert all(s['anchor_drift_m'] < 1e-5 and s['ally_visual_state'] == 'idle' for s in live), seq['id']
        if seq['variant'] == 'A':
            consumed = [s['appearance']['node_effects']['consumed'] for s in live]
            assert consumed == sorted(consumed), seq['id']
assert (OUT / 'review/lineup.jpg').is_file()
assert capture['captures'] == sum(s['frames'] for s in capture['sequences']) + 1 == 610
checks['gpu_capture'] = {'passed': capture['passed'] and execution_passed(read(OUT / 'review/execution.json')),
                         'captures': 610, 'sequences': 9, 'lineup_stills': 1,
                         'execution': read(OUT / 'review/execution.json'),
                         'time_scale_note': 'a_fuse advances simulation at 6x; other sequences are 1x.'}

files = []
for letter in ['a', 'b']:
    metadata = read(BASE / f'automaton_{letter}.json')
    assert sha(ROOT / metadata['source']) == metadata['source_sha256']
    assert metadata['source_unchanged'] and metadata['base_vertices_unchanged']
    assert metadata['base_rest_bones_preserved'] == 26
    for suffix, hash_key in [('', 'glb_sha256'), ('_parts', 'parts_sha256')]:
        filename = f'automaton_{letter}{suffix}.glb'
        export, runtime = BASE / 'exports' / filename, RUNTIME / filename
        assert sha(export) == sha(runtime) == metadata[hash_key]
        checks[filename] = glb_audit(export, metadata, bool(suffix))
        files.extend([export, runtime])
    assert sha(BASE / f'automaton_{letter}.json') == sha(RUNTIME / f'automaton_{letter}.json')
    files.extend([BASE / f'automaton_{letter}.json', RUNTIME / f'automaton_{letter}.json',
                  BASE / 'authoring' / f'automaton_{letter}.blend'])
files.extend(ROOT / path for path in [
    'game/scripts/actor_visual.gd', 'game/scripts/automaton_node_effects.gd',
    'game/scripts/automaton_assembly.gd', 'game/scripts/summon_assembly.gd',
    'game/scripts/turret_assembly.gd', 'game/scripts/arena.gd', 'game/data/trial.json',
    'game/scripts/hud.gd', 'game/scripts/player_visual.gd',
    'game/tests/automaton_variants.gd', 'game/tests/review_automaton_variants.gd',
    'game/tests/automaton_variant_a.gd', 'game/tests/automaton_variant_b.gd',
    'game/tests/automaton_node.gd', 'game/tests/automaton_node_art_regression.gd',
    'tools/build_automaton_nodes_v1.py', 'tools/run_automaton_nodes_v1.ps1',
    'tools/package_automaton_nodes_v1.py'])
manifest = {
    'version': 'automaton_nodes_v1', 'passed': all(v['passed'] for v in checks.values()),
    'user_art_approved': False, 'checks': checks,
    'runtime_assertions': sum(c.get('checks', 0) for c in checks.values()),
    'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'files': [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p), 'bytes': p.stat().st_size} for p in files],
    'scope': 'A copper charge and burning fuse; B reinforced teal/brass armor and rotating saw. Existing node combat behavior, accepted base automaton and turret are preserved.',
    'controls': {'node': 'N', 'summon': 'W'},
    'source': {'path': metadata['source'], 'sha256': metadata['source_sha256'], 'unchanged': True},
    'limits': [
        'Appearance follows the concurrent node rules, including B durability/damage multipliers; art introduces no additional bonuses.',
        'Fuse consumption follows lifetime/approach as anticipation; arena owns the actual explosion trigger.',
        'Additional debris uses baked floor trajectories, not live inter-part/wall collision.',
        'This review has no audio; gameplay reuses the existing mechanical cues.',
        'Level-dependent appearance is deferred at the user request.',
        'First integrated art candidates; no final art or performance-budget approval.',
        'Tests run against the combined checkout including the concurrent node implementation; per-run hashes are retained.'
    ]}
assert manifest['passed'], checks
(OUT / 'delivery_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')

(OUT / 'verified_stills').mkdir(exist_ok=True)
for dest, source in [('lineup_final', 'lineup.jpg'), ('a_final', 'a_assemble/030.jpg'),
                     ('b_final', 'b_assemble/030.jpg'), ('b_attack_final', 'b_attack/030.jpg')]:
    shutil.copy2(OUT / 'review' / source, OUT / 'verified_stills' / f'{dest}.jpg')

page = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>태엽인형 — 자폭형과 절삭형</title>
<style>:root{color-scheme:dark;--bg:#101b20;--panel:#1a2b31;--line:#365059;--teal:#92daca}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#e8efeb;font:16px/1.65 "Malgun Gothic",sans-serif}main{max-width:1180px;margin:auto;padding:36px 26px 65px}h1{font-size:32px;letter-spacing:-1px;line-height:1.3;margin:10px 0 16px}h2{font-size:21px;margin-top:32px}p,small{color:#aec2c3}a{color:var(--teal)}.eyebrow{color:#dcb77d;letter-spacing:2px;font-size:12px}.badge{display:inline-block;border:1px solid var(--line);border-radius:5px;padding:4px 12px;margin:0 8px 16px 0;color:var(--teal);font-size:13px}.controls{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:15px 0}select,button{background:var(--panel);color:#e8efeb;border:1px solid #4e6871;border-radius:6px;padding:8px 12px;font:inherit}button{cursor:pointer}button:hover{border-color:var(--teal)}input[type=range]{flex:1;min-width:150px;accent-color:var(--teal)}figure{margin:0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--panel)}img{width:100%;display:block}figcaption{padding:11px 16px;color:#b4c9c9}.grid{display:grid;grid-template-columns:1fr 1fr;gap:15px}.note{border-left:3px solid #cba873;padding:12px 18px;background:var(--panel)}#frame{font-variant-numeric:tabular-nums;color:#b4c9c9;min-width:160px;font-size:14px}details{margin-top:30px;border:1px solid var(--line);padding:16px;border-radius:8px}summary{cursor:pointer;color:var(--teal)}@media(max-width:720px){main{padding:24px 14px}.grid{grid-template-columns:1fr}h1{font-size:27px}select{max-width:100%}}</style>
<main><div class="eyebrow">WITCH / AUTOMATON NODES 01</div><h1>태엽인형, 두 가지 역할</h1><p>자폭형은 구리색 폭약통과 타들어가는 심지로, 절삭형은 두꺼운 청록 장갑과 회전 칼날로 구분했습니다. 기본 인형을 바탕으로 부품을 더해 같은 기계장치 계열의 모습으로 연결합니다.</p><span class="badge">현재 시험판 연결</span><span class="badge">조립 · 시전 중단 · 전투</span>
<figure><img src="verified_stills/lineup_final.jpg" alt="왼쪽 기본형, 가운데 자폭형 A, 오른쪽 절삭형 B"><figcaption>왼쪽부터 기본형 · A 자폭형 · B 절삭형</figcaption></figure>
<h2>동작 확인</h2><div class="controls"><label for="sequence">장면</label><select id="sequence"></select><button id="play">일시정지</button><label for="speed">재생 속도</label><select id="speed"><option value="1">1배</option><option value="0.5">0.5배</option><option value="0.25">0.25배</option></select></div><figure><img id="preview" src="review/b_assemble/000.jpg" alt="태엽인형 노드별 동작"><figcaption id="caption"></figcaption></figure><div class="controls"><input id="scrub" aria-label="동작 시점" type="range" min="0" max="36" value="0"><span id="frame"></span></div>
<p class="note">게임에서 <strong>N</strong>으로 기본 → A → B를 선택하고 <strong>W</strong>로 소환합니다. 이미 소환된 인형은 자신의 노드와 외형을 유지합니다.</p>
<div class="grid"><section><h2>A · 자폭형</h2><p>소환이 끝나면 심지에 불이 붙고, 수명과 적에게 접근하는 정도에 따라 짧아집니다. 기존 노드 판정으로 자폭하며 폭약통을 포함한 부품이 흩어집니다.</p></section><section><h2>B · 절삭형</h2><p>가슴·어깨·정강이 장갑을 더하고 손에 회전 칼날을 장착했습니다. 반복 공격 때 칼날 회전과 작은 불꽃이 보입니다. 성능은 현재 시험판의 B 노드 규칙을 따릅니다.</p></section></div>
<p>두 버전 모두 부품이 빛 속에서 조립됩니다. 시전 중 경직으로 끊기면 현재까지 생성된 부품만 그 자리에서 무너집니다. 기본 인형의 레벨별 외형 변화는 다음 작업으로 남겨 두었습니다.</p>
<details><summary>검증 및 작업 파일</summary><p>노드별 시전·취소, 정점 연결, 심지·칼날, 기존 인형/포탑 회귀와 노드 전투 규칙까지 __ASSERTIONS__개 검사를 통과했습니다. 9개 동작 장면과 정면 비교 1장, 총 610장의 실제 게임 렌더를 사용합니다. 심지 전체 수명 장면만 게임 시간을 6배로 진행하며 화면에 따로 표시합니다.</p><p>A는 10,583삼각형·27개 분할 부품, B는 11,827삼각형·21개 분할 부품입니다. 기존 원본 파일은 보존했습니다. 새로운 장갑 표면은 기존 원본보다 단순한 재질의 첫 외형 후보입니다. 붕괴는 바닥 낙하 연출이며 부품끼리·벽과 충돌하는 물리 시뮬레이션은 아닙니다. 이 페이지는 무음이고 게임은 기존 기계음을 사용합니다.</p><p><a href="delivery_manifest.json">검증과 파일 해시</a> · <a href="../../assets/actors/automaton_nodes_v1/README.md">작업 인계</a></p></details></main>
<script>const sequences=__SEQUENCES__,select=document.querySelector('#sequence'),image=document.querySelector('#preview'),scrub=document.querySelector('#scrub'),button=document.querySelector('#play');let active,clock=0,running=true,last=performance.now(),lastFrame=-1;for(const item of sequences)select.add(new Option(item.label,item.id));select.value='b_assemble';function show(f){if(lastFrame!==f){image.src='review/'+active.id+'/'+String(f).padStart(3,'0')+'.jpg';lastFrame=f}scrub.value=f;document.querySelector('#frame').textContent=(f/active.fps).toFixed(2)+'초 · '+(f+1)+' / '+active.frames}function choose(){active=sequences.find(s=>s.id===select.value);clock=0;lastFrame=-1;scrub.max=active.frames-1;document.querySelector('#caption').textContent=active.label+(active.time_scale===6?' — 게임 시간 6배 진행':active.cancel_at_fraction>=0?' — 피격 경직으로 중단':active.fight?' — 실제 노드 전투':' — 기존 발동 시점에 완성');show(0);for(let i=0;i<active.frames;i++){const p=new Image;p.src='review/'+active.id+'/'+String(i).padStart(3,'0')+'.jpg'}}select.onchange=choose;button.onclick=()=>{running=!running;button.textContent=running?'일시정지':'재생'};scrub.oninput=()=>{running=false;button.textContent='재생';clock=Number(scrub.value)/active.fps;show(Number(scrub.value))};function tick(now){const dt=Math.min(.15,(now-last)/1000);last=now;if(running){clock=(clock+dt*Number(document.querySelector('#speed').value))%((active.frames-1)/active.fps+.55);show(Math.min(active.frames-1,Math.floor(clock*active.fps)))}requestAnimationFrame(tick)}choose();requestAnimationFrame(tick);</script></html>'''
page = page.replace('__SEQUENCES__', json.dumps([{k: v for k, v in s.items() if k != 'samples'}
                                               for s in capture['sequences']], ensure_ascii=False))
page = page.replace('__ASSERTIONS__', format(manifest['runtime_assertions'], ','))
(OUT / 'review.html').write_text(page, encoding='utf-8')
print('AUTOMATON_NODES_PACKAGE_COMPLETE', json.dumps({'passed': manifest['passed'],
      'checks': manifest['runtime_assertions'], 'captures': capture['captures']}))
