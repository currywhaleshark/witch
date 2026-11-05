"""Saved source, exact pose data and independent GLB reimport review gate."""
import bpy,json,sys,math,hashlib,gzip
import numpy as np
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];actor=sys.argv[sys.argv.index('--')+1]
version=int(next((a.split('=',1)[1] for a in sys.argv if a.startswith('--version=')),'1'))
report=next((a.split('=',1)[1] for a in sys.argv if a.startswith('--report=')),'reports/automation_batch2_complete_v1')
BASE=ROOT/f"assets/actors/automation_batch2/{actor}{'_v' if actor.endswith('_armour') else '_game_v'}{version}";OUT=ROOT/report/actor/'validation'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
def write(n,d):(OUT/n).write_text(json.dumps(d,indent=2),encoding='utf8')
bpy.ops.wm.open_mainfile(filepath=str(BASE/f'{actor}_game_v{version}.blend'))
sc=bpy.context.scene;mesh=next(o for o in sc.objects if o.type=='MESH' and o.find_armature() and (actor.lower() in o.name.lower()));rig=mesh.find_armature()
contract=json.loads((BASE/'rig.json').read_text(encoding='utf8'))
sample_path=OUT.parent/'local/animation_samples.json'
samples=json.loads(sample_path.read_text(encoding='utf8') if sample_path.exists() and '--portable-samples' not in sys.argv else gzip.decompress((BASE/'animation_samples.json.gz').read_bytes()).decode('utf8'))
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
if actor.endswith('_armour'):
 for reference in [o for o in sc.objects if o.type=='ARMATURE' and o!=rig]:
  reference.animation_data.action=None
  for track in reference.animation_data.nla_tracks:track.mute=True
  for pb in reference.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
qa_meshes=[o for o in sc.objects if o.type=='MESH'] if actor.endswith('_armour') else [mesh]
q=qa_check.run(objects=[o.name for o in qa_meshes],profile='game',eps=.00015,tol=.003);write('source_qa.json',q);assert q['pass'],q['errors']
assert len(mesh.data.polygons)<=(2000 if actor.endswith('_armour') else 7000 if actor=='hound' else 4500 if actor=='beacon' else 16000)
assert all(len(v.groups)==1 and abs(v.groups[0].weight-1)<1e-7 for v in mesh.data.vertices)
assert all(len({mesh.data.vertices[i].groups[0].group for i in p.vertices})==1 for p in mesh.data.polygons)
assert mesh.scale==Vector((1,1,1)) and rig.scale==Vector((1,1,1))
assert len(rig.data.bones)==contract['bones'] and len(mesh.vertex_groups)==contract['parts']
inverse={n:b.matrix_local.inverted() for n,b in rig.data.bones.items()}
points={g.name:np.array([tuple(v.co)+ (1.,) for v in mesh.data.vertices if v.groups[0].group==g.index]) for g in mesh.vertex_groups}
err=0.;worst_matrix={};loop_errors={};floors={};pose_count=0
for clip,rows in samples.items():
 a=bpy.data.actions[clip];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0]
 for row in rows:
  frame=1+row['time']*24;sc.frame_set(int(frame),subframe=frame%1);bpy.context.view_layer.update();pose_count+=1
  for n,mat in row['world'].items():
   actual=rig.pose.bones[n].matrix;e=max(abs(actual[i][j]-mat[i][j]) for i in range(4) for j in range(4))
   if e>err:err=e;worst_matrix={'clip':clip,'time':row['time'],'bone':n,'error':e,'actual':[list(r) for r in actual],'want':mat}
   assert abs(actual.to_3x3().determinant()-1)<.00002
 if contract['clips'][clip]['loop']:
  e=max(float(np.max(np.abs(np.array(rows[0]['world'][n])-np.array(rows[-1]['world'][n])))) for n in rows[0]['world']);loop_errors[clip]=e;assert e<2e-6
 lowest=1e6;worst={};duration=contract['clips'][clip]['seconds']
 for t in np.linspace(0,duration,math.ceil(duration*120)+1):
  frame=1+t*24;sc.frame_set(int(frame),subframe=frame%1);bpy.context.view_layer.update()
  for n,ps in points.items():
   mat=np.array(rig.pose.bones[n].matrix@inverse[n]);z=float((ps@mat.T)[:,2].min())
   if z<lowest:lowest=z;worst={'time':float(t),'part':n}
 floors[clip]={'min_z':lowest,'worst':worst}
write('floors.json',floors);write('matrix_diagnostic.json',worst_matrix);assert err<(3e-5 if actor.endswith('_armour') else 1e-5),worst_matrix
assert min(v['min_z'] for v in floors.values())>-.001,floors
write('saved_source.json',{'passed':True,'poses':pose_count,'maximum_matrix_error':err,'loops':loop_errors,'floors':floors,'triangles':len(mesh.data.polygons),'parts':contract['parts'],'bones':contract['bones'],
 'warnings_adjudication':'Source shells retain open boundaries; seam/contact vertices, hidden opposing mating faces and intentionally enclosed joint bearings are retained. Positive rest clearance is intentional. No arbitrary inter-part/live collision claim.'})
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(BASE/f'{actor}_v{version}.glb'))
if actor.endswith('_armour'):
 base_actor=actor.split('_')[0]
 base_version=Path(contract['base_asset']).stem.rsplit('_',1)[-1] if contract.get('base_asset') else (('v3' if base_actor=='hound' else 'v2') if version==2 else ('v2' if base_actor=='hound' else 'v1'))
 bpy.ops.import_scene.gltf(filepath=str(ROOT/f'assets/actors/automation_batch2/{base_actor}_game_{base_version}/{base_actor}_{base_version}.glb'))
for arm in [o for o in bpy.context.scene.objects if o.type=='ARMATURE']:
 if arm.animation_data:
  arm.animation_data.action=None
  for track in arm.animation_data.nla_tracks:track.mute=True
 for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
# glTF importer may create an unmaterialed Icosphere custom bone display shape.
# It is not an exported actor surface; inspect only actual skinned asset meshes.
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
assert len(meshes)==(2 if actor.endswith('_armour') else 1)
rq=qa_check.run(objects=[o.name for o in meshes],profile='game',eps=.00015,tol=.003);write('reimport_qa.json',rq);assert rq['pass'],rq['errors']
assert len(bpy.data.actions)==len(contract['clips'])*(2 if actor.endswith('_armour') else 1)
write('reimport.json',{'passed':True,'actions':[a.name for a in bpy.data.actions],'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),'sha256':hashlib.sha256((BASE/f'{actor}_v{version}.glb').read_bytes()).hexdigest()})
print('ACTOR_SOURCE_QA_PASS',actor,pose_count,err,flush=True)
