"""Saved Blender source and independent GLB reimport checks for the hound."""
import bpy,json,sys,hashlib,math
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2';OUT=ROOT/'reports/hound_game_v2/validation';OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
def write(n,d):(OUT/n).write_text(json.dumps(d,indent=2),encoding='utf8')
bpy.ops.wm.open_mainfile(filepath=str(BASE/'hound_game_v2.blend'))
sc=bpy.context.scene;mesh=bpy.data.objects['Hound_Rigid_Surface'];rig=bpy.data.objects['Hound_Rigid_Rig']
q=qa_check.run(objects=[mesh.name],profile='game',eps=.00015,tol=.003);write('source_qa.json',q)
assert q['pass'],q['errors']
assert len(mesh.data.polygons)<=7000
assert all(len(v.groups)==1 and abs(v.groups[0].weight-1)<1e-7 for v in mesh.data.vertices)
assert all(len({mesh.data.vertices[i].groups[0].group for i in p.vertices})==1 for p in mesh.data.polygons)
assert rig.scale==Vector((1,1,1)) and mesh.scale==Vector((1,1,1))
assert len(rig.data.bones)==37 and len(mesh.vertex_groups)==33
rest={n:b.matrix_local.copy() for n,b in rig.data.bones.items()}
contract=json.loads((BASE/'rig.json').read_text(encoding='utf8'))
saved_samples=json.loads((ROOT/'reports/hound_game_v2/local/animation_samples.json').read_text(encoding='utf8'))
reopen_error=0.;loop_errors={};pose_count=0
for clip,rows in saved_samples.items():
    act=bpy.data.actions[clip];rig.animation_data.action=act;rig.animation_data.action_slot=act.slots[0]
    for row in rows:
        frame=1+row['time']*24;sc.frame_set(int(frame),subframe=frame%1);bpy.context.view_layer.update();pose_count+=1
        for n,mat in row['world'].items():
            p=rig.pose.bones[n].matrix;want=Matrix(mat)
            reopen_error=max(reopen_error,max(abs(p[r][c]-want[r][c]) for r in range(4) for c in range(4)))
            assert abs(p.to_3x3().determinant()-1)<.00001
    if clip in ('idle','run'):
        err=max(np.max(np.abs(np.array(rows[0]['world'][n])-np.array(rows[-1]['world'][n]))) for n in rest)
        loop_errors[clip]=float(err);assert err<1e-6
assert reopen_error<.000005
rig.animation_data.action=None
for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
sc.frame_set(1);bpy.context.view_layer.update()
positions=np.array([v.co[:] for v in mesh.data.vertices]);headgroups={mesh.vertex_groups[n].index for n in ['head','jaw','neck']}
bodypoints=[v.co for v in mesh.data.vertices if mesh.vertex_groups[v.groups[0].group].name not in ['tail_01','tail_02','tail_glow']]
# Antennae remain included in overall bounds; head roof uses original fitted skull landmarks.
measure={'bounds_blender':[positions.min(axis=0).tolist(),positions.max(axis=0).tolist()],
 'body_length_without_tail_m':max(p.y for p in bodypoints)-min(p.y for p in bodypoints),
 'shoulder_shell_height_m':max(v.co.z for v in mesh.data.vertices if mesh.vertex_groups[v.groups[0].group].name=='chest'),
 'core_center_height_m':contract['sockets']['Socket_core']['rest_blender'][2]}
images=[{'name':im.name,'size':list(im.size),'packed':bool(im.packed_file or im.packed_files),'colorspace':im.colorspace_settings.name} for im in bpy.data.images if im.name.startswith('Hound_')]
assert all(i['packed'] for i in images)
write('saved_source.json',{'passed':True,'poses':pose_count,'maximum_reopen_matrix_error':reopen_error,'loop_matrix_errors':loop_errors,'measurements':measure,'packed_images':images,
 'triangles':len(mesh.data.polygons),'bones':len(rig.data.bones),'parts':len(mesh.vertex_groups),'max_influences':1,
 'warnings_adjudication':'Coincident seam/contact vertices and hidden opposing mating-face pairs retained as reported in source_qa.json; rigid joint cores overlap intentionally. Torso shell boundaries are retained. This does not certify arbitrary inter-part collision.'})

bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(BASE/'hound_v2.glb'))
sc=bpy.context.scene;mesh=next(o for o in sc.objects if o.type=='MESH');rig=next(o for o in sc.objects if o.type=='ARMATURE')
rq=qa_check.run(objects=[mesh.name],profile='game',eps=.00015,tol=.003);write('reimport_qa.json',rq);assert rq['pass'],rq['errors']
actions=[a for a in bpy.data.actions if any(a.name==c or a.name.endswith('_'+c) for c in contract['clips'])]
assert len(actions)==6,(len(actions),[a.name for a in bpy.data.actions])
write('reimport.json',{'passed':True,'triangles':sum(len(p.vertices)-2 for p in mesh.data.polygons),'bones':len(rig.data.bones),'actions':[a.name for a in actions],
 'bytes':(BASE/'hound_v2.glb').stat().st_size,'sha256':hashlib.sha256((BASE/'hound_v2.glb').read_bytes()).hexdigest()})
print('HOUND_SOURCE_REIMPORT_QA_PASS',pose_count,reopen_error,flush=True)
