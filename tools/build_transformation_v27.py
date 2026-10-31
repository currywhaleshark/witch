"""Blender 5.2: preserve the current v26 acting and add a replaceable hair rig.

Independent head/chest anchor bones preserve the old two-anchor hair deformation.
Only a derivative hair mesh receives six additional deform bones. The body rig,
all original meshes and all previous actions are retained without rebuilding v26.
"""
import bpy, bmesh, math, json, sys, hashlib
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/characters/player/3d/source/middle_school_v1/transformation_v26/transformation_v26.blend'
OUT=ROOT/'reports/transformation_v27'
DEST=ROOT/'assets/characters/player/3d/source/middle_school_v1/transformation_v27'
GAME=ROOT/'game/assets/characters/player/transformation_v27'
for p in (OUT,DEST,GAME): p.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
assert bpy.app.background and bpy.app.version >= (5,2,0)
bpy.ops.wm.open_mainfile(filepath=str(SRC),load_ui=False,use_scripts=False)
body=bpy.data.objects['PlayerRig_v7']; old=bpy.data.objects['Hair_Semilong_v7']
before=check.snapshot(body.name,set())
(OUT/'protected_baseline.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
source_sha=check.sha(SRC)

hair=old.copy(); hair.data=old.data.copy(); hair.name='Hair_Semilong_v27'
bpy.context.collection.objects.link(hair)
hair.hide_set(False);hair.hide_render=False;hair.hide_viewport=False
old.hide_set(True);old.hide_render=True
arm=bpy.data.armatures.new('HairRig_v27');rig=bpy.data.objects.new('HairRig_v27',arm)
bpy.context.collection.objects.link(rig)
rig.matrix_world=body.matrix_world.copy();rig.show_in_front=True
hair.parent=rig;hair.matrix_world=old.matrix_world.copy()
for m in hair.modifiers:
    if m.type=='ARMATURE': m.object=rig
for ob in bpy.context.selected_objects: ob.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
anchors=['DEF-head','DEF-chest']
for name in anchors:
    src=body.data.bones[name];b=arm.edit_bones.new(name)
    b.head=src.head_local;b.tail=src.tail_local
    b.matrix=src.matrix_local.copy();b.length=src.length
# Two side locks and a broad back section, two segments each.
chains={'L':[(.139,-.060,1.46),(.175,-.065,1.30),(.19,-.065,1.14)],
        'R':[(-.139,-.060,1.46),(-.175,-.065,1.30),(-.19,-.065,1.14)],
        'Back':[(0,.103,1.46),(0,.133,1.30),(0,.150,1.14)]}
for label,points in chains.items():
    parent=arm.edit_bones['DEF-head']
    for i in range(2):
        b=arm.edit_bones.new('DEF-hair.%02d.%s'%(i+1,label))
        b.head=points[i];b.tail=points[i+1];b.parent=parent
        b.use_connect=i>0;parent=b
bpy.ops.object.mode_set(mode='OBJECT')
for name in anchors:
    c=rig.pose.bones[name].constraints.new('COPY_TRANSFORMS')
    c.name='Follow preserved '+name;c.target=body;c.subtarget=name
weights=[]
for v in old.data.vertices:
    d={old.vertex_groups[g.group].name:g.weight for g in v.groups}
    weights.append((d.get('DEF-head',0),d.get('DEF-chest',0)))
hair.vertex_groups.clear()
groups={b.name:hair.vertex_groups.new(name=b.name) for b in arm.bones}
def smooth(x): x=max(0,min(1,x));return x*x*(3-2*x)
max_influences=0
for v,(wh,wc) in zip(hair.data.vertices,weights):
    x,y,z=v.co
    move=smooth((1.49-z)/.20)
    # The central fringe stays attached to the forehead.
    if y<-.06: move*=smooth((abs(x)-.045)/.065)
    tip=smooth((1.34-z)/.15)
    distance={k:(x-p[0][0])**2+(y-p[0][1])**2 for k,p in chains.items()}
    nearest=sorted(distance,key=distance.get)[:2]
    scores={k:math.exp(-distance[k]/.008) for k in nearest}
    total=sum(scores.values())
    ws={'DEF-head':wh*(1-move),'DEF-chest':wc}
    for k,s in scores.items():
        ws['DEF-hair.01.'+k]=wh*move*s/total*(1-tip)
        ws['DEF-hair.02.'+k]=wh*move*s/total*tip
    ws=dict(sorted(((n,w) for n,w in ws.items() if w>1e-5),key=lambda item:-item[1])[:4]);total=sum(ws.values())
    assert total>0
    for n,w in ws.items():groups[n].add([v.index],w/total,'REPLACE')
    max_influences=max(max_influences,len(ws))

# A small delayed response, with the garment-change updraft centered on 2.40s.
# Body action data are read, never regenerated or edited.
act=bpy.data.actions.new('hair_transform_overlap_v27');act.use_fake_user=True
rig.animation_data_create();rig.animation_data.action=act
body.animation_data.action=bpy.data.actions['combat_transform_entry_v26']
head=[]
for f in range(1,74):
    bpy.context.scene.frame_set(f);head.append(body.pose.bones['DEF-head'].matrix.to_quaternion())
curve_rows=[]
for f in range(1,74):
    bpy.context.scene.frame_set(f);t=(f-1)/24
    flare=math.exp(-((t-2.44)/.19)**2)*smooth((3-t)/.25)
    lag=head[f-1].inverted()@head[max(0,f-5)]
    if lag.w<0:lag.negate()
    angle=min(lag.angle,.16);axis=lag.axis
    row={'seconds':t,'rotations':{}}
    for label in chains:
        for i in range(2):
            name='DEF-hair.%02d.%s'%(i+1,label);p=rig.pose.bones[name]
            # Side locks move out; back lock lifts away from the cape.
            outward=Vector((0,1,0)) if label=='Back' else Vector((1 if label=='L' else -1,0,0))
            bone_axis=arm.bones[name].matrix_local.to_quaternion().inverted()@Vector((0,0,-1)).cross(outward)
            q=Quaternion(bone_axis.normalized(),flare*math.radians(4.0+2*i))
            lag_axis=arm.bones[name].matrix_local.to_quaternion().inverted()@body.data.bones['DEF-head'].matrix_local.to_quaternion()@axis
            q=q@Quaternion(lag_axis,angle*(.22+.12*i)*smooth((3-t)/.22))
            p.rotation_mode='QUATERNION';p.rotation_quaternion=q
            p.keyframe_insert('rotation_quaternion',frame=f)
            row['rotations'][name]=[q.x,q.y,q.z,q.w]
    curve_rows.append(row)
for fc in check.curves(act):
    for k in fc.keyframe_points:k.interpolation='LINEAR'
scene=bpy.context.scene;scene.render.fps=24;scene.frame_start=1;scene.frame_end=73;scene.frame_set(1)
after=check.snapshot(body.name,set())
assert before['rig']==after['rig']
assert all(before['meshes'][n]==after['meshes'][n] for n in before['meshes'])
assert all(before['actions'][n]==after['actions'][n] for n in before['actions'])
sig0=check.mesh_signature(old);sig1=check.mesh_signature(hair)
assert sig0['geometry_sha256']==sig1['geometry_sha256'] and sig0['uv_sha256']==sig1['uv_sha256']
# Local source cleanup on the derivative: stitch exact duplicate positions while
# retaining corner UVs, remove four tiny disconnected remnants and a wire edge,
# and give the single collapsed UV triangle a sub-pixel footprint.
bm=bmesh.new();bm.from_mesh(hair.data)
before_cleanup=(len(bm.verts),len(bm.faces))
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
unseen=set(bm.verts);remove=[]
targets=[Vector(p) for p in [(-.129,.040,1.155),(.009,.053,1.391),(.091,-.081,1.306),(.129,.040,1.156)]]
while unseen:
    seed=unseen.pop();island={seed};todo=[seed]
    while todo:
        v=todo.pop()
        for e in v.link_edges:
            w=e.other_vert(v)
            if w in unseen:unseen.remove(w);island.add(w);todo.append(w)
    center=sum((v.co for v in island),Vector())/len(island)
    if len(island)<25 and any((center-p).length<.003 for p in targets):remove.extend(island)
if remove:bmesh.ops.delete(bm,geom=remove,context='VERTS')
wire=[e for e in bm.edges if not e.link_faces]
if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
uv=bm.loops.layers.uv.active;fixed_uv=0
for face in bm.faces:
    ps=[l[uv].uv.copy() for l in face.loops]
    area=sum(ps[i].x*ps[(i+1)%len(ps)].y-ps[(i+1)%len(ps)].x*ps[i].y for i in range(len(ps)))
    if abs(area)<1e-12:
        center=sum(ps,Vector((0,0)))/len(ps)
        for i,l in enumerate(face.loops):l[uv].uv=center+Vector(((i==1)*.0001,(i==2)*.0001))
        fixed_uv+=1
bm.to_mesh(hair.data);bm.free();hair.data.update()
cleanup={'vertices_before':before_cleanup[0],'vertices_after':len(hair.data.vertices),
         'triangles_before':before_cleanup[1],'triangles_after':len(hair.data.polygons),
         'tiny_disconnected_vertices_removed':len(remove),'uv_faces_repaired':fixed_uv,
         'position_weld_tolerance_m':1e-7,'qa_contact_tolerance_m':.002,'qa_zfight_tolerance_m':.0002}
report={'blender':bpy.app.version_string,'source_sha256':source_sha,'body_bones':107,
        'hair_bones':len(arm.bones),'new_deform_chains':6,'preserved_actions':len(before['actions']),
        'preserved_original_meshes':len(before['meshes']),'hair_triangles':sum(len(p.vertices)-2 for p in hair.data.polygons),
        'maximum_influences':max_influences,'original_hair_unchanged':True,'derivative_cleanup':cleanup}
contract={'schema':1,'anchors':anchors,'body_rig':'player_humanoid_v11','hair_rig':'semilong_v27',
          'bones':[b.name for b in arm.bones],'chains':list(chains),'entry_samples':curve_rows,
          'max_sway_degrees':7.0,'source_sha256':source_sha,'bone_count':len(arm.bones)}
(GAME/'hair_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
(DEST/'hair_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(DEST/'transformation_v27.blend'))
report['blend_sha256']=check.sha(DEST/'transformation_v27.blend')

# Check the actual derivative with the installed QA skill, plus the unchanged
# source so inherited Tripo seams can be separated from introduced defects.
sys.path.insert(0,'C:/Users/yurib/.agents/skills/blender-asset-qa/scripts')
import qa_check
for ob,label in [(old,'baseline'),(hair,'hair')]:
    result=qa_check.run(objects=[ob.name],profile='game',no_modifiers=True,eps=.0002)
    (OUT/('qa_'+label+'.json')).write_text(json.dumps(result,indent=2,default=str),encoding='utf-8')

# Export static bind pose. Runtime uses the saved six-bone quaternion curve for
# entry, and bounded secondary motion for ordinary combat; anchors track the body.
for p in rig.pose.bones:
    for c in p.constraints:c.mute=True
    p.matrix_basis=Matrix.Identity(4)
rig.animation_data.action=None
for ob in bpy.data.objects:ob.select_set(ob in (rig,hair))
bpy.context.view_layer.objects.active=rig
# Runtime texture copy only; the packed source above retains its full images.
for m in hair.data.materials:
    if m and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type=='TEX_IMAGE' and n.image and max(n.image.size)>2048:n.image.scale(2048,2048)
target=GAME/'hair_semilong_v27.glb'
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,
    export_animations=False,export_skins=True,export_def_bones=False,export_all_influences=True,
    export_morph=False,export_extras=False,export_image_format='AUTO')
report['glb_sha256']=check.sha(target);report['glb_bytes']=target.stat().st_size
assert check.sha(SRC)==source_sha
(OUT/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('HAIR_V27_COMPLETE',json.dumps(report),flush=True)
