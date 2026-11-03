"""Read the saved auxiliary rig, preserve lineage, and package the engine artifact."""
import bpy,json,shutil,hashlib,sys
from pathlib import Path
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v3';S=ROOT/'assets/equipment/exoskeleton_v3';G=ROOT/'game/assets/equipment/exoskeleton_v3'
scene=bpy.data.scenes['ExoskeletonV3_Fit'];bpy.context.window.scene=scene
m=json.loads(scene['exoskeleton_v3_manifest']);rig=bpy.data.objects['ExoskeletonRig_v3']
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
m['mechanism_rest_godot']={n:[list(r) for r in C@Matrix(v)] for n,v in m['rig_rest_frames'].items()}
m['body_rest_godot']={n:[list(r) for r in C@Matrix(v)@C.inverted()] for n,v in m['body_rest_frames'].items()}
m['rig_bones']=len(rig.data.bones);m['max_influences']=1
for obj in scene.objects:
 if not obj.name.startswith('ExoV3_'):continue
 assert len(obj.vertex_groups)==1
 assert all(len(v.groups)==1 and abs(v.groups[0].weight-1)<1e-7 for v in obj.data.vertices)
for path in [S/'parts.json',G/'parts.json']:path.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copy2(S/'exports/exoskeleton_v3.glb',G/'exoskeleton_v3.glb')
print('V3_ASSETS',m['rig_bones'],len(m['parts']),m['triangles'],flush=True)
