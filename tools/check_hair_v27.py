"""Low-memory QA on the actual exported hair, independently reimported."""
import bpy,json,sys,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'reports/transformation_v27'
assert bpy.app.background
for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
path=root/'game/assets/characters/player/transformation_v27/hair_semilong_v27.glb'
bpy.ops.import_scene.gltf(filepath=str(path))
sys.path.insert(0,'C:/Users/yurib/.agents/skills/blender-asset-qa/scripts')
import qa_check
meshes=[o.name for o in bpy.data.objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
from mathutils import Vector
from mathutils.bvhtree import BVHTree
diagnostics=[]
for name in meshes:
    mesh=bpy.data.objects[name].data;mesh.calc_loop_triangles();uv=mesh.uv_layers.active
    for p in mesh.polygons:
        pts=[uv.data[i].uv for i in p.loop_indices]
        area=sum(pts[i].x*pts[(i+1)%len(pts)].y-pts[(i+1)%len(pts)].x*pts[i].y for i in range(len(pts)))
        if abs(area)<1e-12:diagnostics.append({'uv_face':p.index,'uv':[list(x) for x in pts],'coords':[list(mesh.vertices[i].co) for i in p.vertices]})
    vs=[v.co.copy() for v in mesh.vertices];ts=[tuple(t.vertices) for t in mesh.loop_triangles];ns=[t.normal.copy() for t in mesh.loop_triangles];tree=BVHTree.FromPolygons(vs,ts);pairs=set()
    for i,tri in enumerate(ts):
        a,b,c=[vs[k] for k in tri];center=(a+b+c)/3
        for p in [center,center.lerp(a,.6),center.lerp(b,.6),center.lerp(c,.6)]:
            for _,_,j,_ in tree.find_nearest_range(p,.0002):
                if j==i or set(tri)&set(ts[j]) or ns[i].dot(ns[j])<.999:continue
                d,e,f=[vs[k] for k in ts[j]];q=p-ns[j]*ns[j].dot(p-d)
                if qa_check._point_in_tri(q,d,e,f,ns[j]):pairs.add((min(i,j),max(i,j)))
    for i,j in pairs:diagnostics.append({'overlap':[i,j],'coords':[[list(vs[k]) for k in ts[v]] for v in (i,j)]})
(out/'export_diagnostics.json').write_text(json.dumps(diagnostics,indent=2),encoding='utf-8')
qa=qa_check.run(objects=meshes,profile='game',no_modifiers=True,eps=.0002)
(out/'qa_exported_hair.json').write_text(json.dumps(qa,indent=2,default=str),encoding='utf-8')
r=json.loads((out/'build_validation.json').read_text(encoding='utf-8'))
r['qa_passed']=qa['pass'];r['glb_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();r['glb_bytes']=path.stat().st_size
source=root/'assets/characters/player/3d/source/middle_school_v1/transformation_v27/transformation_v27.blend'
r['blend_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
(out/'build_validation.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
print('EXPORTED_HAIR_QA',json.dumps({'passed':qa['pass'],'errors':qa['errors'],'warnings':qa['warnings']}),flush=True)
assert qa['pass'],qa['errors']
