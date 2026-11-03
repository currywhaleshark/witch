"""Package the final Godot material comparisons and their current-input evidence."""
import json
import hashlib
import re
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / 'reports/drive_material_v3'
S = ROOT / 'assets/weapons/drive_material_v3'
G = ROOT / 'game/assets/weapons/drive_material_v3'
LABELS = {'guillotine': '낙하 단두대', 'guillotine_saw': '회전 톱날형', 'guillotine_lock': '고정 단두대',
          'restraint_winch': '구속 윈치', 'hydraulic_press': '유압 압착기', 'compound_executor': '복합 집행기',
          'shock_frame': '충격 흡수 프레임', 'broad_cutter': '광역 볼트커터'}


def read(p): return json.loads(p.read_text(encoding='utf-8'))
def write(p, data): p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p): return p.relative_to(ROOT).as_posix()


def main():
    cap, qa, art, exported, saved = [read(R / name) for name in ['review/capture.json', 'asset_qa.json', 'art_test.json', 'export_validation.json', 'saved_source_validation.json']]
    assert all(v['passed'] for v in [cap, qa, art, exported, saved])
    assert art['checks'] == 22226 and art['failures'] == []
    assert exported['parts'] == 224 and exported['triangles'] == 45516
    captures = sorted((R / 'review').rglob('*.jpg'))
    assert len(captures) == cap['captures'] == 886
    for sequence in cap['sequences']:
        assert all((R / 'review' / sequence['id'] / f'{frame:03}.jpg').is_file() for frame in range(sequence['frames']))
    capture_hashes = {rel(p): sha(p) for p in captures}
    write(R / 'capture_hashes.json', capture_hashes)
    baseline = read(R / 'baseline.json')
    changed = [p for p, h in baseline.items() if sha(ROOT / p) != h]
    assert not changed, changed
    write(R / 'preservation.json', {'passed': True, 'unchanged_files': len(baseline), 'changed': changed,
        'scope': 'Prior drive assets, selected exoskeleton v4, existing gameplay scripts, user skill document and project settings'})
    warnings = sorted(set(w for a in qa['models'].values() for st in a.values() for g in st.values() for w in g['warnings']))
    classifications = {
        'UV overlap': 'Intentional reusable planar trim charts. Bake target is eight disjoint rectangles, not the repeated mesh UVs.',
        'n-gons': 'Unchanged flat rigid caps; canonical GLB triangles are byte-identical to accepted v1/v2.',
        'duplicate verts': 'Unchanged UV and normal seam splits in the canonical GLBs.',
        'fully enclosed': 'Existing hidden hydraulic column collars, retained to preserve independently assembled pieces.',
        'hidden back-to-back faces': 'Existing hidden mating faces on independent closed parts and hose caps; no newly added geometry.',
        'asset lowest point': 'Staff-mounted cutter and character-mounted shock modules retain their attachment origins.'}
    assert all(any(k in warning for k in classifications) for warning in warnings)
    write(R / 'qa_adjudication.json', {'geometry_errors': 0, 'accepted_warning_classes': classifications,
        'warning_counts': {k: sum(k in w for w in warnings) for k in classifications},
        'visual_review': ['All eight assets in live Blender material and wireframe multi-angle views',
                          'Same-light Godot before/after, rear, close and selected 1.75x scale',
                          'Assembly/mechanisms, winch three branches and both outfits running with shock frame'],
        'remaining': ['The existing shock-frame attachment spacing is retained; this is not a new equipment-fitting pass.',
                      'No new gameplay skill integration, live collision/cloth or final performance claim.'],
        'environment_diagnostics': ['Read-only user thumbnail/cache/editor-settings locations emitted warnings; source saves, all requested images and validations completed.',
                                    'Initial Godot default-log startup failed; explicit workspace log paths completed normally.']})
    texture_metrics = {}
    for key in ['color', 'normal', 'orm', 'emission']:
        p = S / 'textures' / f'drive_v3_{key}.png'
        image = Image.open(p)
        texture_metrics[key] = {'size': list(image.size), 'bytes': p.stat().st_size,
                                'color_space': 'sRGB' if key in ['color', 'emission'] else 'Non-Color'}
        assert sha(p) == sha(G / 'textures' / p.name)
    write(S / 'production.json', {'date': '2026-11-04', 'status': 'material-complete prototype review candidate',
        'source': 'Blender-authored procedural materials and Cycles self-baked trim atlas; no new AI generation',
        'scope': list(LABELS), 'exoskeleton_changed': False, 'parts': 224, 'triangles': 45516,
        'runtime_materials': 2, 'surfaces': 224, 'editable_source_materials': 8, 'textures': texture_metrics,
        'blender': '5.1.1', 'mcp': '1.8 / protocol 15', 'godot': '4.6.2 / OpenGL compatibility',
        'selected_shape_preserved': True, 'mechanism_metadata_preserved': True, 'active_skill_integration': False,
        'user_material_approval': False, 'review': 'reports/drive_material_v3/review.html',
        'approx_rgba8_full_mips_mib': 12.33, 'memory_note': 'Texture estimate only, not measured peak memory or performance approval.'})
    options = ''.join(f'<option value="{a}">{label}</option>' for a, label in LABELS.items())
    cards = ''.join(f'<a class="card" href="review/{"compare/shock_frame_transformed" if a=="shock_frame" else "close/"+a}.jpg"><img loading="lazy" src="review/{"compare/shock_frame_transformed" if a=="shock_frame" else "close/"+a}.jpg" alt="{label} 재질"><span>{label}</span></a>' for a, label in LABELS.items())
    page = '''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>구동 장비 · 재질 v3</title>
<style>:root{color-scheme:dark;font:16px/1.65 "Malgun Gothic",sans-serif;background:#101c24;color:#e3e9eb}*{box-sizing:border-box}body{max-width:1400px;margin:auto;padding:28px}h1{font-size:34px;margin:8px 0}h2{font-size:23px}.eyebrow{color:#c5aa75;letter-spacing:.12em;font-size:13px}p,.note{color:#aabec7}a{color:#a4ded1}.panel{background:#192a35;border:1px solid #344b58;padding:20px;border-radius:10px;margin:22px 0}.toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:10px}select,button{font:inherit;background:#29414e;color:#eff7f5;border:1px solid #586d78;border-radius:5px;padding:7px 12px;cursor:pointer}select:focus-visible,button:focus-visible,input:focus-visible{outline:2px solid #b8e6d9;outline-offset:3px}.picture{position:relative;margin-top:18px;background:#15232c}.picture img{width:100%;display:block}.badge{position:absolute;top:12px;background:#132f36e8;padding:4px 12px;border-radius:4px}.left{left:12px;color:#bdecdc}.right{right:12px;background:#373e43e8}input[type=range]{width:100%;accent-color:#a8d7c8;margin:18px 0 8px}#clock{margin-left:auto;font-variant-numeric:tabular-nums}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}.card{background:#1b2c37;border:1px solid #344b58;border-radius:8px;overflow:hidden;text-decoration:none}.card img{width:100%;display:block}.card span{display:block;padding:10px 12px}.note{font-size:14px}.facts{display:flex;gap:24px;flex-wrap:wrap;color:#ccdbdf}.facts b{color:#e5dbc5}.foot{margin:25px 0}summary{cursor:pointer}#stage{min-height:26px} @media(max-width:800px){body{padding:14px}.grid{grid-template-columns:repeat(2,1fr)}h1{font-size:27px}.panel{padding:12px}.badge{font-size:12px;padding:2px 7px}}</style></head><body>
<header><div class="eyebrow">WITCH / DRIVE MATERIAL / 2026.11.04</div><h1>황동, 도장, 가공 금속</h1><p>단두대부터 대형 커터까지 8종의 재질을 다듬었습니다. 차분한 황동 반사, 남색 도장과 작은 모서리 마모, 칼날·피스톤의 가공 결을 구분했습니다.</p><div class="facts"><span><b>8종</b> 구동 장비</span><span><b>224개</b> 강체 부품</span><span><b>45,516</b> 삼각형 유지</span></div></header>
<section class="panel"><h2>수정 전후 비교</h2><div class="toolbar"><label for="asset">장비</label><select id="asset">__OPTIONS__</select><label for="view">보기</label><select id="view"><option value="still">재질 비교</option><option value="motion">움직임 비교</option><option value="native">실제 표시 크기</option></select><label id="variant-label" for="variant">형태</label><select id="variant"></select></div>
<div class="picture"><img id="pic" src="review/compare/guillotine.jpg" alt="낙하 단두대 재질: 왼쪽 수정, 오른쪽 이전"><span id="left" class="badge left">수정 v3</span><span id="right" class="badge right">이전 v1/v2</span></div>
<div id="controls"><label for="frame" class="note">동작 시점</label><input id="frame" type="range" min="0" max="83" value="16"><div class="toolbar"><button id="play" type="button">재생</button><button id="restart" type="button">처음부터</button><label for="speed">속도</label><select id="speed"><option value="0.25">0.25×</option><option value="0.5">0.5×</option><option value="1" selected>1×</option></select><span id="clock"></span></div><p id="stage"></p></div>
<p class="note" id="caption">왼쪽이 수정 재질입니다. 두 모델에 같은 조명과 중성 반사 환경을 적용했습니다.</p><p class="note">게임 표시 크기는 기존 1.75× 카메라의 1280×800 캡처입니다. 재질 비교용 반사 환경만 더했으며 본 게임 조명은 바꾸지 않았습니다. 충격 흡수 프레임은 기존 장착 위치를 유지했습니다.</p></section>
<section><h2>8종 살펴보기</h2><div class="grid">__CARDS__</div></section>
<section class="panel"><h2>작업 파일</h2><p><a href="../../assets/weapons/drive_material_v3/drive_material_v3.blend">Blender 작업본</a> · <a href="../../assets/weapons/drive_material_v3/catalog.json">모델 목록</a> · <a href="../../assets/weapons/drive_material_v3/README.md">연결 안내</a></p><p>일반 표면과 청록 발광을 분리하고 4장 텍스처를 공유합니다. 외골격 v4는 그대로이며, 수정한 모델은 후속 스킬 구현에 쓸 준비 자산입니다.</p><details><summary>검수 결과</summary><p>원본·GLB 재반입 검사 오류 0건. 최종 저장본에서 224개 메시의 형상·UV·노멀·좌표를 재확인했고, Godot 재질·동작 비교 22,226개 검사를 통과했습니다. 실제 GPU 캡처 886장을 포함합니다.</p><p>반복 트림 UV, 평면 캡, 숨은 부품 접합면과 UV/노멀 경계의 중복 정점은 기존 구조를 유지한 항목입니다. 독립 장비의 부착 원점과 기존 충격 흡수 프레임 간격도 그대로입니다. 신규 스킬 판정·실시간 접촉·최종 성능 검증은 포함하지 않습니다.</p><p><a href="qa_adjudication.json">검수 판정</a> · <a href="delivery_manifest.json">검증 명세</a></p></details></section>
<script>
const labels=__LABELS__,seqs=__SEQUENCES__;
const $=s=>document.querySelector(s),asset=$('#asset'),view=$('#view'),variant=$('#variant'),frame=$('#frame'),pic=$('#pic'),play=$('#play'),speed=$('#speed');
let running=false,last=0,elapsed=0;
function stop(){running=false;play.textContent='재생';elapsed=0;}
function sequence(){return seqs.find(s=>s.asset===asset.value&&(asset.value==='shock_frame'?s.variant===variant.value:asset.value==='restraint_winch'?s.variant===variant.value:true));}
function draw(){const id=asset.value,mode=view.value;const shock=id==='shock_frame';let path='';$('#controls').hidden=mode!=='motion';$('#left').textContent=mode==='native'?'1.75× 표시 크기':'수정 v3';$('#right').hidden=mode==='native';if(mode==='motion'){const s=sequence(),n=Math.min(Number(frame.value),s.frames-1);frame.max=s.frames-1;path=`${s.id}/${String(n).padStart(3,'0')}.jpg`;$('#clock').textContent=`${(n/s.fps).toFixed(2)}초 / ${((s.frames-1)/s.fps).toFixed(2)}초`;$('#stage').textContent=shock?'기존 달리기 모션에 장착':id==='compound_executor'?'조립 → 문 닫힘 → 압착 → 프레스 상승 → 톱 진입 → 소멸':id==='guillotine_lock'?'구속구 생성·고정 → 본체 조립 → 칼날 낙하 → 소멸':'기존 조립·작동·소멸 동작';}else{path=`${mode==='native'?'native':'compare'}/${id}${shock?'_'+variant.value:''}.jpg`;}pic.src='review/'+path;pic.alt=labels[id]+' · '+(mode==='native'?'선택한 게임 표시 크기':'왼쪽 수정 v3, 오른쪽 이전 재질');$('#caption').textContent=mode==='native'?'수정 모델과 현재 캐릭터의 크기를 비교할 수 있습니다.':'왼쪽이 수정 재질입니다. 두 모델에 같은 조명과 중성 반사 환경을 적용했습니다.';}
function choose(){stop();variant.replaceChildren();const opts=asset.value==='shock_frame'?[['transformed','변신복'],['civilian','평상복']]:asset.value==='restraint_winch'?[['single','한 줄 당김'],['pull','여러 줄 당김'],['bind','여러 줄 구속']]:[['base','기본']];for(const [v,t]of opts){const o=document.createElement('option');o.value=v;o.textContent=t;variant.append(o);}variant.hidden=opts.length===1;$('#variant-label').hidden=opts.length===1;frame.value=16;draw();}
asset.onchange=choose;variant.onchange=()=>{stop();frame.value=16;draw();};view.onchange=()=>{stop();draw();};frame.oninput=()=>{stop();draw();};play.onclick=()=>{running=!running;play.textContent=running?'일시정지':'재생';};$('#restart').onclick=()=>{stop();frame.value=0;draw();};document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
function tick(now){if(running){const s=sequence();elapsed+=Math.min(.1,(now-last)/1000)*Number(speed.value);const steps=Math.floor(elapsed*s.fps);if(steps){elapsed-=steps/s.fps;frame.value=(Number(frame.value)+steps)%s.frames;draw();}}last=now;requestAnimationFrame(tick);}choose();requestAnimationFrame(tick);
</script></body></html>'''.replace('__OPTIONS__', options).replace('__CARDS__', cards).replace('__LABELS__', json.dumps(LABELS, ensure_ascii=False)).replace('__SEQUENCES__', json.dumps(cap['sequences'], ensure_ascii=False))
    (R / 'review.html').write_text(page, encoding='utf-8')
    (R / 'review_syntax.js').write_text(re.search(r'<script>(.*?)</script>', page, re.S).group(1), encoding='utf-8')
    class Links(HTMLParser):
        paths = []
        def handle_starttag(self, tag, attrs):
            for key, value in attrs:
                if key in ['src', 'href'] and value and not value.startswith(('http', '#')): self.paths.append(value)
    links = Links()
    links.feed(page)
    # The manifest itself is written just below.
    assert all((R / unquote(p)).exists() for p in links.paths if p != 'delivery_manifest.json'), links.paths
    files = set()
    for folder in [S, G]:
        files.update(p for p in folder.rglob('*') if p.is_file() and not p.name.endswith('.blend1') and 'live_authoring' not in p.name)
    files.update(R / name for name in ['baseline.json', 'preservation.json', 'asset_qa.json', 'qa_adjudication.json', 'source_preservation.json', 'saved_source_validation.json', 'art_test.json', 'export_validation.json', 'bake.json', 'capture_hashes.json', 'review/capture.json', 'review.html'])
    files.update((ROOT / 'tools').glob('*drive_material*v3*.py'))
    files.update([ROOT / 'game/tests/helpers/drive_material_v3_demo.gd', ROOT / 'game/tests/drive_material_v3_art.gd', ROOT / 'game/tests/review_drive_material_v3.gd'])
    write(R / 'delivery_manifest.json', {'date': '2026-11-04', 'status': 'prepared material derivative, user review pending',
        'checks': {'full_asset_qa': qa['passed'], 'final_saved_source': saved['passed'], 'runtime_assertions': art['checks'],
                   'gpu_captures': len(captures), 'preserved_files': len(baseline), 'native_image_dimensions': [1280, 800]},
        'models': exported['models'], 'textures': texture_metrics,
        'source_and_outputs': {rel(p): sha(p) for p in sorted(files)},
        'geometry_scope': saved['note'], 'rendering': cap['lighting'],
        'limits': ['Prepared review assets, no new active-skill integration.', 'Exoskeleton v4 and existing equipment fitting unchanged.',
                   'Shared trim detail, no per-object unique damage maps.', 'No new live collision or final performance approval.']})
    print('DRIVE_MATERIAL_DELIVERY_COMPLETE', len(captures), art['checks'], len(files))


if __name__ == '__main__': main()
