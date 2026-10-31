"""Read-only check of the saved source against the pre-task v26 snapshot."""
import bpy,json,sys,math,hashlib
from pathlib import Path
from mathutils import Quaternion
root=Path(__file__).resolve().parents[1];out=root/'reports/transformation_v27'
sys.path.insert(0,str(root/'tools'))
import validate_hand_motion_v13 as check
source=root/'assets/characters/player/3d/source/middle_school_v1/transformation_v27/transformation_v27.blend'
bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
baseline=json.loads((out/'protected_baseline.json').read_text(encoding='utf-8'))
current=check.snapshot('PlayerRig_v7',set())
failures=[]
if baseline['rig']!=current['rig']:failures.append('body rest changed')
for name,value in baseline['meshes'].items():
    if current['meshes'].get(name)!=value:failures.append('original mesh changed: '+name)
for name,value in baseline['actions'].items():
    if current['actions'].get(name)!=value:failures.append('original action changed: '+name)
body=bpy.data.objects['PlayerRig_v7'];hair=bpy.data.objects['Hair_Semilong_v27'];rig=bpy.data.objects['HairRig_v27']
contract=json.loads((root/'game/assets/characters/player/transformation_v27/hair_contract.json').read_text(encoding='utf-8'))
max_weight_error=max(abs(sum(g.weight for g in v.groups)-1) for v in hair.data.vertices)
max_influences=max(len(v.groups) for v in hair.data.vertices)
if max_weight_error>1e-5 or max_influences>4:failures.append('invalid hair skin weights')
rotation_error=0.0;anchor_error=0.0
for i,row in enumerate(contract['entry_samples']):
    bpy.context.scene.frame_set(i+1);bpy.context.view_layer.update()
    for name,values in row['rotations'].items():
        q=Quaternion((values[3],*values[:3]))
        rotation_error=max(rotation_error,rig.pose.bones[name].rotation_quaternion.rotation_difference(q).angle)
    for name in contract['anchors']:
        anchor_error=max(anchor_error,(rig.pose.bones[name].matrix.translation-body.pose.bones[name].matrix.translation).length)
if rotation_error>1e-4 or anchor_error>1e-5:failures.append('saved hair motion mismatch')
result={'passed':not failures,'failures':failures,'preserved_meshes':len(baseline['meshes']),
        'preserved_actions':len(baseline['actions']),'body_rest_bones':len(body.data.bones),
        'hair_bones':len(rig.data.bones),'samples':73,'max_weight_error':max_weight_error,
        'max_influences':max_influences,'max_rotation_error_rad':rotation_error,'max_anchor_error_m':anchor_error,
        'source_sha256':check.sha(source),'source_saved':False}
(out/'source_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('V27_SOURCE_CHECK',json.dumps(result),flush=True)
assert not failures,failures
