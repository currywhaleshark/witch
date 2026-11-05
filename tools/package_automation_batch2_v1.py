"""Package the three original concepts and the first generated hound source review."""
from pathlib import Path
import hashlib
import json
from html import escape
from html.parser import HTMLParser

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/automation_batch2'
MODEL=BASE/'hound_tripo_v1'
OUT=ROOT/'reports/automation_batch2_v1'

def read(path):return json.loads(path.read_text(encoding='utf-8'))
def write(path,data):path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
verification=read(OUT/'working/verification.json')
assert verification['source_qa_pass'] and verification['fresh_glb_qa_pass']
raw=read(OUT/'raw/inventory.json')
seg=read(OUT/'segmented/inventory.json')
cleanup=read(OUT/'working/cleanup.json')
concepts=[('mechanical_hound_v1','기계 수렵견','빠른 추적 · 덫 모양 턱 · 사족 기계'),
          ('lure_beacon_v1','유인 신호기','호박색 신호등 · 종 · 접이식 삼각대'),
          ('giant_automaton_v1','거대 자동인형','큰 어깨 · 긴 팔 · 망치 주먹')]
production={
    'date':'2026-11-05','status':'concept and generated source review; no user appearance approval',
    'scope':'three image_gen concepts; Tripo hound generation, segmentation, source inspection and minimal cleanup',
    'image_generation':{'mode':'built-in image_gen','prompt_set':(BASE/'concept_v1/prompts.json').relative_to(ROOT).as_posix(),
        'images':[{'id':i,'path':(BASE/'concept_v1'/f'{i}.png').relative_to(ROOT).as_posix(),
                   'sha256':digest(BASE/'concept_v1'/f'{i}.png')} for i,_,_ in concepts]},
    'tripo':{'url':'https://studio.tripo3d.ai/ko/workspace/segmentation/af4d77b6-a9e6-4c5b-a45c-fe99ef1326d5',
        'model':'H3.1','mode':'HD','target_polygons':80000,'topology':'triangles','textures':'2K PBR',
        'input':(BASE/'concept_v1/mechanical_hound_v1.png').relative_to(ROOT).as_posix(),
        'private':True,'ultra':False,'ai_completion':False,'8k':False,
        'part_generation':False,'post_generation_segmentation':'fine (정밀)',
        'export_uv_packing':True,'credits':{'generation':30,'segmentation':40,'total':70,'before':2455,'after':2385},
        'ui_initial_segment_parts':61,'exported_parts':60,'missing_export_part_ids':[11],
        'ui_initial_segment_faces':76914,'exported_faces':76870,
        'export_note':'Tripo save/UV-packed export changed part/face count. Local GLB counts are authoritative; original unsegmented GLB is preserved.'},
    'tooling':{'blender':'5.1.1','execution':'background CLI; live MCP handshake unavailable',
               'render':'EEVEE PBR and Workbench part/wire review'},
    'working':{'blend':(MODEL/'hound_working.blend').relative_to(ROOT).as_posix(),
        'glb':(MODEL/'exports/hound_working.glb').relative_to(ROOT).as_posix(),
        'mesh_parts':60,'triangles':76862,'removed_overlap_triangles':8,'materials':1,
        'texture_images':3,'texture_resolution':2048,'bones':0,'clips':0,
        'qa_errors':0,'qa_warnings':64,'reimport_qa_errors':0,
        'normal_reencoding_max_vector_error':cleanup['max_corner_normal_vector_difference']},
    'limits':['Source units/facing not fitted to the gameplay specification.',
        '60 automatic pieces are not finalized rigid joints; interior caps/pistons/contact remain.',
        '5k-7k triangles, 1K atlas, separate emission faces, rig, clips, sockets and node attachments pending.',
        'Raw GLB QA: 2 errors. Raw segmented GLB QA: 8 errors. Working derivative: 0 errors.',
        '60 seam-vertex warnings and four hidden mating-face warnings retained intentionally at source stage.',
        'No game integration, gameplay tests, native-size comparison, performance approval or art selection.',
        'Beacon and giant automaton have concepts only.']}
write(MODEL/'production.json',production)
cards=''.join(f'<article class="card"><a href="../../assets/actors/automation_batch2/concept_v1/{i}.png"><img src="../../assets/actors/automation_batch2/concept_v1/{i}.png" alt="{name} 원화"></a><h3>{name}</h3><p>{desc}</p></article>' for i,name,desc in concepts)
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>자동화 소환체 · 원화와 수렵견 v1</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#111b21;color:#e9efee;font:16px/1.65 system-ui,"Malgun Gothic",sans-serif}main{max-width:1320px;margin:auto;padding:44px 28px 70px}h1{font-size:34px;line-height:1.25;margin:8px 0 16px}h2{font-size:24px;margin:42px 0 16px}h3{margin:14px 18px 2px;font-size:19px}p{color:#b7c6c8;margin:8px 0}a{color:#8cd6cb}a:hover{color:#e9c583}.eyebrow{color:#c6a878;letter-spacing:.13em;font-size:13px}.chips{display:flex;gap:9px;flex-wrap:wrap;margin:20px 0}.chips span{border:1px solid #415951;border-radius:30px;padding:4px 14px;color:#bfe3d9}.concepts{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}.card{background:#1b2a31;border:1px solid #30464b;border-radius:14px;overflow:hidden}.card img{width:100%;height:340px;object-fit:contain;background:#faf7f2;display:block}.card p{margin:3px 18px 18px;font-size:14px}.model{display:grid;grid-template-columns:2fr 1fr;gap:24px;align-items:start}.viewer{background:#27323c;border:1px solid #3e5058;border-radius:14px;overflow:hidden}.viewer img{display:block;width:100%;aspect-ratio:3/2;object-fit:contain}.buttons{padding:12px;display:flex;flex-wrap:wrap;gap:8px;background:#18262d}button{background:#293b43;color:#dde9e8;border:1px solid #496069;border-radius:8px;padding:8px 14px;cursor:pointer;font:inherit;font-size:14px}button[aria-pressed=true]{color:#102421;background:#9dd2c0}.facts{background:#1b2a31;padding:22px;border-radius:14px}.facts strong{font-size:24px;color:#d8bd8d}.facts dl{display:grid;grid-template-columns:auto 1fr;gap:8px 16px;font-size:14px}.facts dt{color:#98b3b6}.facts dd{margin:0}.notice{border-left:3px solid #c8a96d;background:#243238;padding:16px 20px;margin:20px 0}.links{display:flex;gap:18px;flex-wrap:wrap;margin-top:22px}details{background:#18262d;border-radius:10px;padding:16px;margin-top:18px}summary{cursor:pointer;color:#c8dcd9}table{border-collapse:collapse;width:100%;font-size:14px;margin:16px 0}td,th{text-align:left;border-bottom:1px solid #344b52;padding:10px}footer{color:#89a4a8;font-size:13px;margin-top:40px}@media(max-width:900px){.concepts,.model{grid-template-columns:1fr}.card img{height:420px}h1{font-size:28px}}
</style><main><div class="eyebrow">WITCH / AUTOMATION / 2026.11.05</div><h1>자동화 소환체<br>세 종의 원화와 첫 수렵견 모델</h1><p>낡은 황동과 깊은 청록. 신호등만 호박색으로 구분했습니다.</p><div class="chips"><span>3종 원화</span><span>수렵견 Tripo 생성</span><span>60개 내보낸 파트</span><span>리깅 전 원형</span></div>
<section aria-label="세 종의 원화" class="concepts">__CARDS__</section>
<h2>기계 수렵견 · 생성 모델</h2><div class="model"><div class="viewer"><a id="full" href="working/three_quarter.png"><img id="model-image" src="working/three_quarter.png" alt="수렵견 작업용 모델 사선"></a><div class="buttons"><button data-view="working/three_quarter.png" aria-pressed="true">사선</button><button data-view="working/opposite.png" aria-pressed="false">반대편</button><button data-view="working/profile.png" aria-pressed="false">측면</button><button data-view="working/top.png" aria-pressed="false">위에서</button><button data-view="segmented/random.png" aria-pressed="false">파트 구분</button><button data-view="working/wire.png" aria-pressed="false">메시</button></div></div>
<aside class="facts"><strong>60 파트 · 76,862 삼각형</strong><p>원화의 외형을 보존한 고해상도 작업용 원형입니다.</p><dl><dt>생성</dt><dd>Tripo H3.1 HD</dd><dt>분할</dt><dd>정밀 분할 후 저장·내보내기</dd><dt>재질</dt><dd>공유 PBR 1개 · 2K 이미지 3장</dd><dt>리그 / 모션</dt><dd>아직 없음</dd><dt>최소 정리</dt><dd>작은 겹침 면 8개 제거</dd><dt>검사</dt><dd>작업본·새 GLB 임포트 오류 0</dd><dt>생성 비용</dt><dd>모델 30 + 분할 40 크레딧</dd></dl><p>뼈에 연결할 관절 단위는 다음 단계에서 정리합니다. 자동 분할 조각 전체가 독립 구동부인 것은 아닙니다.</p></aside></div>
<div class="notice">다음 작업: 관절별 묶기와 안쪽 면·피스톤 정리 → 크기와 정면 맞춤 → 5~7천 삼각형·1K 재질 → 강체 리깅과 모션. 현재 게임에는 연결하지 않았습니다.</div>
<div class="links"><a href="../../assets/actors/automation_batch2/hound_tripo_v1/hound_working.blend">작업용 Blender</a><a href="../../assets/actors/automation_batch2/hound_tripo_v1/exports/hound_working.glb">작업용 GLB</a><a href="../../assets/actors/automation_batch2/README.md">제작 기록</a><a href="../../assets/actors/automation_batch2/concept_v1/prompts.json">원화 프롬프트</a><a href="https://studio.tripo3d.ai/ko/workspace/segmentation/af4d77b6-a9e6-4c5b-a45c-fe99ef1326d5">Tripo 작업실</a></div>
<details><summary>원본 보존과 검증 범위</summary><table><tr><th>단계</th><th>메시</th><th>삼각형</th><th>검사 오류</th></tr><tr><td>생성 직후 원본</td><td>1</td><td>76,914</td><td>2</td></tr><tr><td>분할 GLB 원본</td><td>60</td><td>76,870</td><td>8</td></tr><tr><td>최소 정리 작업본</td><td>60</td><td>76,862</td><td>0</td></tr></table><p>Tripo 분할 직후 화면에는 61개였으나 저장·내보낸 GLB는 60개입니다. 11번 파트가 없고 면 수도 달라져, 원본의 정확한 면 분할이라고 간주하지 않습니다. 원본과 분할 다운로드 파일은 각각 보존했습니다.</p><p>작업본은 남은 위치·면 연결·UV·부품 변환·재질을 유지합니다. UV/노멀 경계의 분리 정점과 숨겨진 접합면 경고 64개는 원형 단계에서 유지합니다. 실제 관절 접촉·폐곡면·게임 크기·성능 검사는 이후 단계입니다.</p><p><a href="working/verification.json">검증 결과</a> · <a href="working/source_qa.json">작업본 QA</a> · <a href="working/reimport_qa.json">GLB 재임포트 QA</a> · <a href="delivery_manifest.json">파일 해시</a></p></details>
<details><summary>Tripo 생성·분할 화면</summary><p>생성 결과와 정밀 분할 직후의 실제 작업 화면입니다.</p><a href="tripo_generated.jpg"><img src="tripo_generated.jpg" alt="Tripo 수렵견 생성 결과" style="width:100%"></a><a href="tripo_segmented.jpg"><img src="tripo_segmented.jpg" alt="Tripo 정밀 분할 직후 61개 파트" style="width:100%"></a></details>
<footer>원화는 built-in image_gen, 모델은 Tripo, 검토 이미지는 Blender 5.1.1에서 만들었습니다. 첫 외형 후보이며 신호기와 거대 자동인형은 원화 단계입니다.</footer></main>
<script>for(const b of document.querySelectorAll('[data-view]'))b.addEventListener('click',()=>{document.querySelector('#model-image').src=b.dataset.view;document.querySelector('#model-image').alt='수렵견 모델 '+b.textContent;document.querySelector('#full').href=b.dataset.view;for(const x of document.querySelectorAll('[data-view]'))x.setAttribute('aria-pressed',String(x===b));});</script></html>'''.replace('__CARDS__',cards)
(OUT/'review.html').write_text(html,encoding='utf-8')

files=set(BASE.rglob('*'))|set(OUT.rglob('*'))|{ROOT/'tools'/n for n in
    ['inspect_automation_batch2_v1.py','prepare_automation_hound_v1.py','package_automation_batch2_v1.py']}
files=sorted(p for p in files if p.is_file() and 'local' not in p.parts and
             p.name!='delivery_manifest.json' and not p.name.endswith('.blend1'))
manifest={'date':'2026-11-05','scope':production['scope'],'status':production['status'],
    'verification':verification,'limits':production['limits'],
    'source_counts':{'raw':{'meshes':raw['mesh_count'],'triangles':raw['triangles']},
                     'segmented':{'meshes':seg['mesh_count'],'triangles':seg['triangles']},
                     'working':{'meshes':60,'triangles':76862}},
    'files':{p.relative_to(ROOT).as_posix():{'bytes':p.stat().st_size,'sha256':digest(p)} for p in files}}
write(OUT/'delivery_manifest.json',manifest)

class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[]
    def handle_starttag(self,tag,attrs):
        for key,value in attrs:
            if key in ('src','href','data-view'):self.links.append(value)
parser=Links();parser.feed(html)
for link in parser.links:
    if link.startswith(('https:','#')):continue
    assert (OUT/link).resolve().is_file(),link
assert len(read(BASE/'concept_v1/prompts.json')['prompts'])==3
assert all(p.stat().st_size>0 for p in files)
print(json.dumps({'review':str(OUT/'review.html'),'manifest_files':len(files),
                  'local_links_verified':len(parser.links),'production':str(MODEL/'production.json')},ensure_ascii=False))
