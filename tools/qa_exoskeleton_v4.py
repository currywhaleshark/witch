"""Saved/rest skin and exported mesh QA; body-mounted shin groups are checked separately."""
import bpy,sys,json
from mathutils import Matrix
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4'
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
scene=bpy.data.scenes['ExoskeletonV4_Fit'];bpy.context.window.scene=scene
manifest=json.loads(scene['exoskeleton_v4_manifest']);rig=bpy.data.objects['ExoskeletonRig_v4'];rig.data.pose_position='REST'
groups={'upper':[], 'shin_L':[], 'shin_R':[]}
for p in manifest['parts']:
 group='shin_'+p['role'][-1] if p['role'].startswith(('knee_','shin_','calf_cuff_')) else 'upper'
 groups[group].append(p['name'])
out={'source':{},'reimport':{},'skin':{'bone_count':len(rig.data.bones),'max_influences':1,'rigid_normalized':True}}
original=bpy.data.objects['ExoskeletonV2_WorkingMesh'].data
covered=[];max_position_error=0.;max_uv_error=0.
for part in manifest['parts']:
 ob=bpy.data.objects[part['name']]
 if 'source_polygon_ids' not in ob:continue
 ids=list(ob['source_polygon_ids']);covered.extend(ids);fit=Matrix(part['fit_matrix'])
 for src_id,dst in zip(ids,ob.data.polygons):
  src=original.polygons[src_id]
  for a,b in zip(src.loop_indices,dst.loop_indices):
   va=fit@original.vertices[original.loops[a].vertex_index].co;vb=ob.data.vertices[ob.data.loops[b].vertex_index].co
   max_position_error=max(max_position_error,(va-vb).length)
   max_uv_error=max(max_uv_error,(original.uv_layers.active.data[a].uv-ob.data.uv_layers.active.data[b].uv).length)
out['source_lineage']={'faces':len(covered),'retained_faces_unique':len(covered)==len(set(covered)), 'original_faces':len(original.polygons), 'excluded_middle_faces_archived':len(original.polygons)-len(covered),'max_fitted_position_error_m':max_position_error,'max_uv_error':max_uv_error}
assert out['source_lineage']['retained_faces_unique'] and max_position_error<1e-5 and max_uv_error<1e-7
for group,names in groups.items():
 q=qa_check.run(objects=names,profile='game',eps=.0002,tol=.006,uv=False);out['source'][group]=q
 print('V4_QA_SOURCE',group,q['pass'],q['errors'],flush=True)
for p in manifest['parts']:
 ob=bpy.data.objects[p['name']]
 assert all(len(v.groups)==1 and abs(v.groups[0].weight-1)<1e-7 for v in ob.data.vertices)
 assert ob.vertex_groups[0].name==p['bone']
fresh=bpy.data.scenes.new('QA_ExoV4_Reimport');bpy.context.window.scene=fresh
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/equipment/exoskeleton_v4/exports/exoskeleton_v4.glb'))
for group,names in groups.items():
 imported=[o.name for o in fresh.objects if o.type=='MESH' and any(o.name==n or o.name.startswith(n+'.') for n in names)]
 q=qa_check.run(objects=imported,profile='game',eps=.0002,tol=.006,uv=False);out['reimport'][group]=q
 print('V4_QA_REIMPORT',group,q['pass'],q['errors'],flush=True)
out['passed']=all(q['pass'] for stage in ['source','reimport'] for q in out[stage].values())
(R/'asset_qa.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('V4_QA_DONE',out['passed'],flush=True)

