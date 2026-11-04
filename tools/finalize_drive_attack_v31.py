"""Canonicalize the prepared v31 clip names without changing motion channels.

Idempotent: a fresh build already uses these names. This also handles the first
review bake, which retained v30 suffixes while its replacement script was fixed.
"""
from pathlib import Path
import bpy,sys,json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v31'
REPORT=ROOT/'reports/drive_attack_v31'
contract=json.loads((SOURCE/'runtime_contract.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'drive_attack_v31.blend'),load_ui=False,use_scripts=False)
renames={n:n.removesuffix('_v30')+'_v31' for n in contract['clips'] if n.endswith('_v30')}
for old,new in renames.items():
    assert new not in bpy.data.actions
    bpy.data.actions[old].name=new
for ob in bpy.data.objects:
    if not ob.animation_data:continue
    for track in ob.animation_data.nla_tracks:
        if track.name in renames:track.name=renames[track.name]
        for strip in track.strips:
            if strip.name in renames:strip.name=renames[strip.name]
for field in ('clips','staff_slide_tracks','grip_spacing_tracks'):
    contract[field]={renames.get(n,n):value for n,value in contract[field].items()}
for n,spec in contract['clips'].items():spec['action_sha256']=check.action_digest(bpy.data.actions[n])
contract['grip_note']='Right hand stays forward/above left. Swing preparation slides the right grip toward the butt: grinder 13cm, spin 11cm. Thrust keeps 26cm with the right shoulder leading; sustained cut uses 22cm.'
if renames:
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'drive_attack_v31.blend'))
(SOURCE/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
for name in ('build_validation.json','build_progress.json'):
    path=REPORT/name;data=json.loads(path.read_text(encoding='utf-8'))
    clips=data['clips'] if 'clips' in data else data
    clips={renames.get(n,n):value for n,value in clips.items()}
    for n,spec in clips.items():spec['action_sha256']=contract['clips'][n]['action_sha256']
    if 'clips' in data:data['clips']=clips
    else:data=clips
    path.write_text(json.dumps(data,indent=2),encoding='utf-8')
print('V31_NAMES_READY',list(contract['clips']),flush=True)
