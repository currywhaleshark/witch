"""Audit portable links/media and write a scoped exact-input delivery manifest."""
import json,hashlib,re,subprocess,gzip,ast
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/automation_batch2_complete_v1';ASSETS=ROOT/'assets/actors/automation_batch2'
ACTORS=['beacon','giant','hound_armour','giant_armour']
def load(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def file_record(p):return {'bytes':p.stat().st_size,'sha256':sha(p)}
def rel(p):return p.relative_to(ROOT).as_posix()
def dump(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False),encoding='utf8')
def folder(a):return ASSETS/(a+('_v1' if a.endswith('_armour') else '_game_v1'))
summary=load(OUT/'summary.json');assert summary['current_runtime_checks']==134752 and summary['current_gpu_captures']==1455
for a in ACTORS:
    p=load(folder(a)/'production.json');assert sha(folder(a)/f'{a}_game_v1.blend')==p['source_sha256']
    assert sha(folder(a)/f'{a}_v1.glb')==p['runtime_sha256']
    exact=json.loads(gzip.decompress((folder(a)/'animation_samples.json.gz').read_bytes()).decode())
    assert sum(len(v) for v in exact.values())==load(OUT/a/'validation/saved_source.json')['poses']
    for kind in ('source_qa','reimport_qa','saved_source','reimport','authoring_preservation','runtime_parity'):
        check=load(OUT/a/f'validation/{kind}.json');assert check.get('pass',check.get('passed',False))
    assert load(OUT/a/'runtime/runtime_validation.json')['passed']
    assert load(OUT/a/'geometry/source_qa.json')['pass']
for a in ('hound_armour','giant_armour'):assert load(OUT/a/'validation/base_preservation.json')['passed']
protected=load(OUT/'hound_preservation.json');assert all(sha(ROOT/n)==v['sha256'] for n,v in protected['files'].items())
assert load(OUT/'combined/runtime_validation.json')['passed']
assert all(v['passed'] for v in load(OUT/'event_validation.json').values())

class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[]
    def handle_starttag(self,tag,attrs):
        for n,v in attrs:
            if n in ('href','src','poster') and v and not v.startswith(('#','http','data:')):self.links.append(v)
parser=Links();page=(OUT/'review.html').read_text(encoding='utf8');parser.feed(page)
checked=[]
for value in parser.links:
    path=(OUT/unquote(value)).resolve()
    if path.name=='delivery_manifest.json':continue
    assert path.is_file(),value;checked.append(rel(path))
for a in ACTORS:
    part=load(folder(a)/'parts.json')
    for clip in part['clips']:assert (OUT/a/f'videos/{clip}.mp4').is_file()
    for path in (folder(a)/'README.md',):
        for target in re.findall(r'\]\(([^)]+)\)',path.read_text(encoding='utf8')):
            if target.startswith(('http','#')):continue
            resolved=(path.parent/target.split('#')[0]).resolve()
            if resolved.name=='delivery_manifest.json':continue
            assert resolved.exists(),(rel(path),target)
dump(OUT/'offline_review_validation.json',{'passed':True,'html_link_count':len(checked),'html_files':checked,'model_readme_links':True,'videos_verified_by_ffprobe':'video_validation.json'})

tool_names=['automation_rigid_common.py','build_beacon_game_v1.py','animate_beacon_game_v1.py','build_giant_game_v1.py','animate_giant_game_v1.py','build_automation_armour_v1.py','finish_automation_armour_v1.py','export_automation_actor.py','validate_automation_actor.py','validate_automation_events_v1.py','validate_automation_armour_preservation_v1.py','finish_automation_authoring_v1.py','review_automation_geometry.py','review_automation_batch2_complete_v1.ps1','inspect_automation_remaining_v1.py','inspect_automation_remaining_parts.py','diagnose_automation_surface.py','package_automation_batch2_complete_v1.py','finalize_automation_batch2_v1.py']
for name in tool_names:
    if name.endswith('.py'):ast.parse((ROOT/'tools'/name).read_text(encoding='utf8'))
delivery=set()
for a in ACTORS:
    for base in (folder(a),ROOT/f'game/assets/actors/automation_batch2/{a}_v1'):
        for p in base.rglob('*'):
            if p.is_file() and not p.name.endswith(('.blend1','_geometry.blend','_static.glb')):delivery.add(p)
for a in ('beacon','giant'):
    for p in (ASSETS/f'{a}_tripo_v1').rglob('*'):
        if p.is_file() and not p.name.endswith('.blend1'):delivery.add(p)
for p in OUT.rglob('*'):
    if not p.is_file() or 'local' in p.relative_to(OUT).parts:continue
    relative=p.relative_to(OUT).as_posix()
    if re.search(r'/(motion_|poses_)',relative) or relative.startswith('combined/multiple/'):continue
    if p.name in ('delivery_manifest.json','scoped_diff_check.txt'):continue
    delivery.add(p)
for name in tool_names:delivery.add(ROOT/'tools'/name)
for name in ('game/tests/review_automation_actor_v1.gd','game/tests/review_automation_actor_v1.gd.uid','game/tests/review_automation_batch2_complete_v1.gd','game/tests/review_automation_batch2_complete_v1.gd.uid','game/tests/helpers/automation_batch2_visual.gd','game/tests/helpers/automation_batch2_visual.gd.uid'):
    p=ROOT/name
    if p.exists():delivery.add(p)
delivery.update([ROOT/'AGENTS.md',ASSETS/'README.md',ASSETS/'catalog.json'])

# Current comparison inputs, recorded separately from files owned by this pass.
inputs={ASSETS/'ART_REQUEST.md',ROOT/'game/project.godot'}
inputs.update(p for p in (ROOT/'game/scripts').rglob('*') if p.suffix in ('.gd','.gdshader','.json'))
for sub in ('run_arm_v21','model_refinement_v28','hand_rebuild_v29','transformation_v25','transformation_v26','transformation_v27','spring_jump_v24','drive_attack_v32'):
    inputs.update(p for p in (ROOT/'game/assets/characters/player'/sub).rglob('*') if p.is_file())
for sub in ('combat_set_v1','summons_v2','automaton_nodes_v1'):
    inputs.update(p for p in (ROOT/'game/assets/actors'/sub).rglob('*') if p.is_file())
inputs.update(p for p in (ROOT/'game/assets/weapons/staff_material_v3').rglob('*') if p.is_file())
inputs.update(ROOT/p for p in protected['files'])
frames=[p for p in OUT.rglob('*.jpg') if '/runtime/motion_' in p.as_posix() or '/runtime/poses_' in p.as_posix() or '/combined/multiple/' in p.as_posix()]
manifest={'date':'2026-11-05','passed':True,'stage':'prepared model/motion review; no new main-game skill integration','summary':summary,
 'tools':{'blender':'5.1.1 CLI; live MCP unavailable','godot':'4.6.2 Compatibility / RTX 2060','animation':'24fps plus exact events and end samples','review_video':'30fps loop capture / 24fps non-loop and native pack'},
 'qa_scope':['Saved-source and fresh GLB reimport geometry/material/weights. Additive armour checked together with its preserved base.','120Hz fixed-length transforms, floor support and exact loop endpoints; actual event contact checks.','Base vertices/topology/UV/normals/weights/rests/actions retained; 26 historical hound files byte-identical.','Four-asset GPU movies and current 1.75x camera comparison with existing witch, automaton, turret and three enemies.'],
 'scope_limits':['Prepared assets/helpers only; game skill rules, targets, lifetime, resource handling, range FX and node selection remain separate.','Open source shell boundaries, UV/normal seam/contact vertices, hidden mating cap/panel faces and internal bearings remain intentionally documented in each production.json.','Raw immutable Tripo sources retain diagnostic errors; zero-error QA applies to prepared derivatives, not unmodified raw sources.','Baked destruction begins at its authored initial pose; no arbitrary interrupted/blended pose, live inter-part/debris/terrain/wall collision certification.','Optional per-instance numbers are not made. Compatible armour skeleton duplication is retained for later gameplay optimization.','No final performance or user appearance approval; no commit or push.'],
 'environment_diagnostics':['Blender user thumbnail write denial and optional HIP/NVIDIA library notice; no output loss.','Godot user:// settings/shader-cache location warnings; explicit report log paths and actual GPU rendering succeeded.'],
 'files':{rel(p):file_record(p) for p in sorted(delivery)},'comparison_input_snapshot':{rel(p):file_record(p) for p in sorted(inputs)},
 'local_capture_frames':{'excluded_from_offline_package':True,'count':len(frames),'sha256':{rel(p):sha(p) for p in sorted(frames)}}}
dump(OUT/'delivery_manifest.json',manifest)
print('DELIVERY_VALIDATED',len(delivery),'files',round(sum(p.stat().st_size for p in delivery)/1048576,1),'MiB',summary,flush=True)
