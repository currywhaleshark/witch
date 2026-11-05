import bpy,sys,json
from pathlib import Path
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
ROOT=Path(__file__).resolve().parents[1];actor=sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'assets/actors/automation_batch2/{actor}_game_v1/{actor}_geometry.blend'))
ob=next(o for o in bpy.context.scene.objects if o.type=='MESH');me=ob.data;vs=[v.co.copy() for v in me.vertices];ps=list(me.polygons)
bvh=BVHTree.FromPolygons(vs,[list(p.vertices) for p in ps],all_triangles=True);pairs=set()
for i,f in enumerate(ps):
 a,b,c=[vs[j] for j in f.vertices];cen=(a+b+c)/3;n=f.normal
 for p in (cen,cen.lerp(a,.6),cen.lerp(b,.6),cen.lerp(c,.6)):
  for _,_,j,_ in bvh.find_nearest_range(p,.00015):
   if j==i or set(f.vertices)&set(ps[j].vertices) or n.dot(ps[j].normal)<.999:continue
   a2,b2,c2=[vs[k] for k in ps[j].vertices];n2=ps[j].normal;q=p-n2*n2.dot(p-a2)
   if qa_check._point_in_tri(q,a2,b2,c2,n2):pairs.add(tuple(sorted((i,j))))
for pair in sorted(pairs):
 print('PAIR',[(i,ob.vertex_groups[me.vertices[ps[i].vertices[0]].groups[0].group].name,ps[i].area,list(ps[i].center)) for i in pair],flush=True)
