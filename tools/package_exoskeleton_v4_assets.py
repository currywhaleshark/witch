"""Read the saved auxiliary rig, preserve lineage, and package the engine artifact."""
import bpy,json,shutil,hashlib,sys
from pathlib import Path
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4';S=ROOT/'assets/equipment/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4'
scene=bpy.data.scenes['ExoskeletonV4_Fit'];bpy.context.window.scene=scene
m=json.loads(scene['exoskeleton_v4_manifest']);rig=bpy.data.objects['ExoskeletonRig_v4']
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
m['mechanism_rest_godot']={n:[list(r) for r in C@Matrix(v)] for n,v in m['rig_rest_frames'].items()}
m['body_rest_godot']={n:[list(r) for r in C@Matrix(v)@C.inverted()] for n,v in m['body_rest_frames'].items()}
m['rig_bones']=len(rig.data.bones);m['max_influences']=1
for part in m['parts']:
 if part['role'].startswith('calf_cuff_'):
  ob=bpy.data.objects[part['name']]
  part['contact_samples_blender']=[list((ob.data.vertices[i*8].co+ob.data.vertices[i*8+7].co)*.5) for i in range(48)]
for obj in scene.objects:
 if not obj.name.startswith('ExoV4_'):continue
 assert len(obj.vertex_groups)==1
 assert all(len(v.groups)==1 and abs(v.groups[0].weight-1)<1e-7 for v in obj.data.vertices)
for path in [S/'parts.json',G/'parts.json']:path.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
for p in (S/'exports').glob('*.glb'):shutil.copy2(p,G/p.name)
print('V4_ASSETS',m['rig_bones'],len(m['parts']),m['triangles'],flush=True)
