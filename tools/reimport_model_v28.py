"""Reopen the saved delivery GLBs in a fresh Blender and validate skinning."""
from pathlib import Path
import bpy,json,math,sys
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/model_refinement_v28'
DIR=ROOT/'assets/characters/player/3d/exports/model_refinement_v28'
sys.path.insert(0,str(ROOT/'tools'))
from export_source_outfit_v11 import part_stats
result={'files':{},'sampled_poses':0,'passed':True}
for path in sorted(DIR.glob('*.glb')):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(path))
 rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE'];assert len(rigs)==1
 rig=rigs[0];assert len(rig.data.bones)==107
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
 stats={o.name:part_stats(o,rig,8 if o.name.startswith('SourceOutfit_') else 4) for o in meshes}
 actions=list(bpy.data.actions)
 for action in actions:
  rig.animation_data_create();rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
  lo,hi=action.frame_range
  for t in [0,.25,.5,.75,1]:
   bpy.context.scene.frame_set(int(round(lo+(hi-lo)*t)));bpy.context.view_layer.update()
   deps=bpy.context.evaluated_depsgraph_get()
   for ob in meshes:
    evaluated=ob.evaluated_get(deps)
    assert all(math.isfinite(c) for v in evaluated.data.vertices for c in v.co),(path.name,action.name)
   result['sampled_poses']+=1
 result['files'][path.name]={'parts':stats,'bones':107,'actions':len(actions),'all_imported_pose_vertices_finite':True}
(OUT/'blender_reimport.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('V28_REIMPORT',result['sampled_poses'],flush=True)
