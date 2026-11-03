"""QA the four edited sleeve meshes against their untouched archive copies."""
import bpy,json,sys,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4'
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
s=bpy.data.scenes['ExoskeletonV4_Fit'];bpy.context.window.scene=s;m=json.loads(s['exoskeleton_v4_manifest'])
for o in s.objects:
 if o.type=='ARMATURE':o.data.pose_position='REST'
out={};new_errors=[]
for name in m['sleeve_tuck']:
 ob=bpy.data.objects[name];old=next(o for o in bpy.data.objects if o.name.startswith('V3_Original_') and o.data!=ob.data and (o.name.removeprefix('V3_Original_')==name or o.name.endswith(name)))
 rows={}
 for stage,obj in [('original',old),('fitted',ob)]:
  rows[stage]=qa_check.run(objects=[obj.name],profile='game',eps=.0002,tol=.006,uv=False,no_modifiers=True)
 def normalized(errors,obj):return {e.replace(obj.name,'MESH') for e in errors}
 added=normalized(rows['fitted']['errors'],ob)-normalized(rows['original']['errors'],old)
 new_errors.extend(sorted(added));rows['introduced_errors']=sorted(added)
 rows['topology_unchanged']=len(ob.data.vertices)==len(old.data.vertices) and all(tuple(a.vertices)==tuple(b.vertices) for a,b in zip(ob.data.polygons,old.data.polygons))
 rows['uv_unchanged']=len(ob.data.uv_layers)==len(old.data.uv_layers) and all((a.uv-b.uv).length<1e-7 for aa,bb in zip(ob.data.uv_layers,old.data.uv_layers) for a,b in zip(aa.data,bb.data))
 assert rows['topology_unchanged'] and rows['uv_unchanged'];out[name]=rows
 print('OUTFIT_QA',name,'new errors',list(added),flush=True)
result={'passed':not new_errors,'meshes':out,'scope':'Four fitted source garments compared with immutable source copies; inherited geometry warnings remain. Original UVs are compared exactly rather than rasterized. Canonical export skeleton/binary preservation is checked separately.'}
(R/'outfit_qa.json').write_text(json.dumps(result,indent=2));assert result['passed']
