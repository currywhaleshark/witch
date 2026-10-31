"""Finish local hair QA and outward overlap curves, then export the rest rig."""
import bpy,bmesh,math,json,sys,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/transformation_v27'
DEST=ROOT/'assets/characters/player/3d/source/middle_school_v1/transformation_v27'
GAME=ROOT/'game/assets/characters/player/transformation_v27'
sys.path.insert(0,'C:/Users/yurib/.agents/skills/blender-asset-qa/scripts')
import qa_check
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(DEST/'transformation_v27.blend'),load_ui=False,use_scripts=False)
hair=bpy.data.objects['Hair_Semilong_v27'];rig=bpy.data.objects['HairRig_v27'];body=bpy.data.objects['PlayerRig_v7']
contract=json.loads((GAME/'hair_contract.json').read_text(encoding='utf-8'))
bm=bmesh.new();bm.from_mesh(hair.data)
# Removing the old wire reveals one additional tiny isolated fragment.
unseen=set(bm.verts);remove=[]
while unseen:
    v=unseen.pop();island={v};todo=[v]
    while todo:
        for e in todo.pop().link_edges:
            for w in e.verts:
                if w in unseen:unseen.remove(w);island.add(w);todo.append(w)
    center=sum((v.co for v in island),Vector())/len(island)
    if len(island)==15:remove.extend(island)
if remove:bmesh.ops.delete(bm,geom=remove,context='VERTS')
bm.to_mesh(hair.data);bm.free();hair.data.update()
start=[v.co.copy() for v in hair.data.vertices];offset_records=[]
for iteration in range(4):
    hair.data.calc_loop_triangles()
    verts=[v.co.copy() for v in hair.data.vertices]
    tris=[tuple(t.vertices) for t in hair.data.loop_triangles]
    normals=[t.normal.copy() for t in hair.data.loop_triangles]
    bvh=BVHTree.FromPolygons(verts,tris);pairs=set()
    for i,tri in enumerate(tris):
        a,b,c=[verts[k] for k in tri];n=normals[i];center=(a+b+c)/3
        for p in [center,center.lerp(a,.6),center.lerp(b,.6),center.lerp(c,.6)]:
            for _,_,j,_ in bvh.find_nearest_range(p,.0002):
                if j==i or set(tri)&set(tris[j]) or n.dot(normals[j])<.999:continue
                d,e,f=[verts[k] for k in tris[j]];q=p-normals[j]*normals[j].dot(p-d)
                if qa_check._point_in_tri(q,d,e,f,normals[j]):pairs.add((min(i,j),max(i,j)))
    if not pairs:break
    chosen=set()
    for i,j in pairs:
        # Lift the smaller local patch by half a millimetre, keeping the larger
        # hair surface intact. No global remesh or texture re-projection.
        small=min((i,j),key=lambda k:hair.data.loop_triangles[k].area)
        chosen.add(small)
    offsets={}
    for i in chosen:
        for vi in tris[i]:offsets.setdefault(vi,[]).append(normals[i])
    for vi,ns in offsets.items():hair.data.vertices[vi].co+=sum(ns,Vector()).normalized()*.00055
    hair.data.update();offset_records.append({'pairs':len(pairs),'vertices_offset':len(offsets)})
# One additional near-collinear UV triangle collapses after glTF UV conversion.
target=Vector((-.0360155925,.1263950393,1.2034720977))
face=min(hair.data.polygons,key=lambda p:(p.center-target).length)
uv=hair.data.uv_layers.active
points=[uv.data[i].uv.copy() for i in face.loop_indices]
area=sum(points[i].x*points[(i+1)%3].y-points[(i+1)%3].x*points[i].y for i in range(3))
if abs(area)<1e-10:uv.data[face.loop_indices[-1]].uv.y+=.00025
# Export splits corner vertices at seams; separate the tiny crown patch whose
# shared corner otherwise masks its shallow coplanar overlap in the source QA.
for point in [(-.0450820364,-.0140498076,1.6904575825),(-.0474286452,-.0143443746,1.6894513369)]:
    v=min(hair.data.vertices,key=lambda v:(v.co-Vector(point)).length)
    if (v.co-Vector(point)).length<.00001:v.co.z+=.0007
hair.data.update()
max_move=max((v.co-p).length for v,p in zip(hair.data.vertices,start))

def smooth(x):x=max(0,min(1,x));return x*x*(3-2*x)
head=[];body.animation_data.action=bpy.data.actions['combat_transform_entry_v26']
for f in range(1,74):
    bpy.context.scene.frame_set(f);head.append(body.pose.bones['DEF-head'].matrix.to_quaternion())
act=bpy.data.actions['hair_transform_overlap_v27'];rig.animation_data.action=act
rows=[]
for f in range(1,74):
    bpy.context.scene.frame_set(f);t=(f-1)/24
    flare=math.exp(-((t-2.44)/.19)**2)*smooth((3-t)/.25)
    lag=head[f-1].inverted()@head[max(0,f-5)]
    if lag.w<0:lag.negate()
    row={'seconds':t,'rotations':{}}
    for label in ('L','R','Back'):
        for i in range(2):
            n='DEF-hair.%02d.%s'%(i+1,label)
            inverse=rig.data.bones[n].matrix_local.to_quaternion().inverted()
            out=Vector((0,1,0)) if label=='Back' else Vector((1 if label=='L' else -1,0,0))
            axis=inverse@Vector((0,0,-1)).cross(out)
            local_lag=inverse@body.data.bones['DEF-head'].matrix_local.to_quaternion()@lag.axis
            q=Quaternion(axis.normalized(),flare*math.radians(4+2*i))@Quaternion(local_lag,min(lag.angle,.16)*(.22+.12*i)*smooth((3-t)/.22))
            p=rig.pose.bones[n];p.rotation_quaternion=q;p.keyframe_insert('rotation_quaternion',frame=f)
            row['rotations'][n]=[q.x,q.y,q.z,q.w]
    rows.append(row)
contract['entry_samples']=rows
for folder in (GAME,DEST):(folder/'hair_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
bpy.context.scene.frame_set(1)
qa=qa_check.run(objects=[hair.name],profile='game',no_modifiers=True,eps=.0002)
(OUT/'qa_hair.json').write_text(json.dumps(qa,indent=2,default=str),encoding='utf-8')
assert qa['pass'],qa['errors']
bpy.ops.wm.save_as_mainfile(filepath=str(DEST/'transformation_v27.blend'))
for p in rig.pose.bones:
    for c in p.constraints:c.mute=True
    p.matrix_basis=Matrix.Identity(4)
rig.animation_data.action=None
for ob in bpy.data.objects:ob.select_set(ob in (rig,hair))
bpy.context.view_layer.objects.active=rig
for m in hair.data.materials:
    if m and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type=='TEX_IMAGE' and n.image and max(n.image.size)>2048:n.image.scale(2048,2048)
target=GAME/'hair_semilong_v27.glb'
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=False,
    export_skins=True,export_def_bones=False,export_all_influences=True,export_morph=False,export_extras=False,export_image_format='AUTO')
report=json.loads((OUT/'build_validation.json').read_text(encoding='utf-8'))
report.update({'qa_passed':qa['pass'],'hair_triangles':len(hair.data.polygons),'hair_vertices':len(hair.data.vertices),
    'local_overlap_repairs':offset_records,'max_overlap_vertex_offset_m':max_move,'extra_fragment_vertices_removed':len(remove),
    'blend_sha256':hashlib.sha256((DEST/'transformation_v27.blend').read_bytes()).hexdigest(),
    'glb_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'glb_bytes':target.stat().st_size})
(OUT/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('HAIR_FINALIZED',json.dumps(report),flush=True)
