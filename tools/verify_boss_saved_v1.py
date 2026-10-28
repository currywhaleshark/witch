"""Read saved deliverables in a separate Blender process; never modify them."""
import bpy,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/boss_trial_v1'
REPORT=ROOT/'reports/boss_trial_v1'
errors=[];files=[]
def check(ok,text):
    if not ok:errors.append(text)
def inspect(actor,format):
    path=BASE/('authoring' if format=='blend' else 'exports')/f'{actor}_v1.{format}'
    before=hashlib.sha256(path.read_bytes()).hexdigest()
    if format=='blend':bpy.ops.wm.open_mainfile(filepath=str(path))
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(path))
    expected=json.loads((REPORT/'build'/actor/'build.json').read_text())
    rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
    scene_meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    check(len(rigs)==1,f'{actor}/{format}: one rig')
    rig=rigs[0];check(len(rig.data.bones)==expected['bones'],f'{actor}/{format}: bone count')
    custom_shapes={b.custom_shape for b in rig.pose.bones if b.custom_shape}
    # Blender's importer creates an 80-triangle bone display shape. It is not
    # exported model geometry; distinguish it through actual custom_shape references.
    meshes=[o for o in scene_meshes if o not in custom_shapes]
    tri=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    check(tri==expected['runtime_triangles'],f'{actor}/{format}: triangles')
    names={a.name for a in bpy.data.actions};check(set(expected['clips']).issubset(names),f'{actor}/{format}: clips')
    images=[i for i in bpy.data.images if i.type=='IMAGE']
    if format=='blend':check(all(i.packed_file for i in images),f'{actor}: packed texture files')
    maximum_error=0.;samples=0
    for name,clip in expected['clips'].items():
        action=bpy.data.actions[name];rig.animation_data_create();rig.animation_data.action=action
        start,end=action.frame_range
        for f in [start,(start+end)/2,end]:
            bpy.context.scene.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
            for b in rig.pose.bones:
                maximum_error=max(maximum_error,abs(b.matrix.to_3x3().determinant()-1))
            samples+=1
    check(maximum_error<.00001,f'{actor}/{format}: rigid evaluated transforms')
    check(before==hashlib.sha256(path.read_bytes()).hexdigest(),f'{actor}/{format}: file unchanged by inspection')
    files.append({'id':actor,'format':format,'sha256':before,'triangles':tri,'bones':len(rig.data.bones),'images':len(images),'importer_bone_display_shapes':[o.name for o in scene_meshes if o in custom_shapes],'sampled_poses':samples,'max_determinant_error':maximum_error})
for actor in ['latch','stake','door']:
    for format in ['blend','glb']:inspect(actor,format)
result={'passed':not errors,'errors':errors,'files':files}
(REPORT/'saved_file_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('BOSS_SAVED_VALIDATION',json.dumps(result))
if errors:raise RuntimeError(errors)
