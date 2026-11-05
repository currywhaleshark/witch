"""Tripo hound -> rigid game geometry. Source files remain immutable.

Static fitting is baked into the derivative before rigging. Runtime parts never
scale. Semantic parts, filled mating rims and independently sliding pistons are
authored here; source materials are projected onto a new non-overlapping atlas.
"""
import bpy, bmesh, json, math, sys, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2'
OUT=ROOT/'reports/hound_game_v2'
SOURCE=ROOT/'assets/actors/automation_batch2/hound_tripo_v1/hound_working.blend'
for p in [BASE,BASE/'textures',OUT/'local',OUT/'geometry']:p.mkdir(parents=True,exist_ok=True)
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
sc=bpy.context.scene
source={int(o.name.rsplit('_',1)[1]):o for o in sc.objects if o.type=='MESH'}
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
sc.render.fps=24
for o in list(sc.objects):
    if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)

def mat(name,color,metal=.65,rough=.4,emit=False):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if emit:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=1.5
    return m
brass=mat('Author_Hinge_Brass',(.27,.155,.053),.78,.40)
steel=mat('Author_Piston_Steel',(.16,.20,.21),.84,.34)
dark=mat('Author_Joint_Recess',(.012,.035,.038),.55,.50)
cyan=mat('Author_Core_Cyan',(.035,.65,.56),.15,.28,True)

# Anatomical source dimensions differ from its antenna/tail bounding box.
# The static affine fit is applied to vertices, never animated or left as scale.
FIT=Matrix(((0,1.12,0,0),(-1.275,0,0,-.045),(0,0,1.12,0),(0,0,0,1)))
# Origin is the mean of the four support-pad centres, not the tail/head bbox.
support_centres=[]
for ids in ([21,48,51],[30],[41,42],[26,33]):
    ps=[source[n].matrix_world@v.co for n in ids for v in source[n].data.vertices]
    support_centres.append(Vector([(min(p[i] for p in ps)+max(p[i] for p in ps))/2 for i in range(3)]))
support_center=sum(support_centres,Vector())/4
FIT[0][3]=-1.12*support_center.y;FIT[1][3]=1.275*support_center.x
NECK_P=Vector((-.274,0,.361))
NECK_T=Matrix.Translation(NECK_P)@Matrix.Rotation(math.radians(-7),4,'Y')@Matrix.Translation(-NECK_P)
def pt(v,neck=False):return FIT@(NECK_T@Vector(v) if neck else Vector(v))
groups={}
provenance=[]
def extract(n,label,predicate=None,neck=False):
    o=source[n];old=o.data;world=o.matrix_world
    selected=[p for p in old.polygons if predicate is None or predicate(world@p.center)]
    if not selected:return
    used=sorted({v for p in selected for v in p.vertices});remap={v:i for i,v in enumerate(used)}
    mesh=bpy.data.meshes.new(label+'_source')
    transform=FIT@(NECK_T if neck else Matrix.Identity(4))@world
    mesh.from_pydata([transform@old.vertices[i].co for i in used],[],[[remap[i] for i in p.vertices] for p in selected])
    for m in old.materials:mesh.materials.append(m)
    uv=mesh.uv_layers.new(name='UVMap')
    norm_matrix=transform.to_3x3().inverted().transposed();norms=[]
    for a,b in zip(selected,mesh.polygons):
        b.use_smooth=True;b.material_index=a.material_index
        for ai,bi in zip(a.loop_indices,b.loop_indices):
            uv.data[bi].uv=old.uv_layers.active.data[ai].uv
            norms.append(tuple((norm_matrix@old.corner_normals[ai].vector).normalized()))
    mesh.normals_split_custom_set(norms)
    ob=bpy.data.objects.new(label+'_high_fragment',mesh);sc.collection.objects.link(ob)
    groups.setdefault(label,[]).append(ob)
    provenance.append({'part':n,'group':label,'triangles':len(selected)})
def many(nums,label,neck=False):
    for n in nums:extract(n,label,neck=neck)
many([0,1,12,13,14,18,24,39,43,44,46,52,54],'chest')
many([3,25,31,53,56,58,59],'pelvis')
many([5,23,47],'neck',True)
many([7,9,37,40,49],'head',True)
many([35,50,60],'jaw',True)
extract(36,'jaw',lambda p:p.x<-.38,True)
extract(36,'neck',lambda p:p.x>=-.38,True)
many([20],'key')
many([32],'tail_01');many([27],'tail_02')
many([4,38,57],'fore_upper.R');many([29],'fore_lower.R');many([21,48,51],'fore_paw.R')
many([2,45,55],'fore_upper.L');many([8],'fore_lower.L');many([30],'fore_paw.L')
extract(17,'fore_upper.L',lambda p:p.z>.326)
many([10],'hind_upper.R');many([15],'hind_lower.R');many([34],'hind_hock.R');many([41,42],'hind_paw.R')
many([6],'hind_upper.L');extract(28,'hind_lower.L',lambda p:p.z>.117)
extract(28,'hind_hock.L',lambda p:p.z<=.117);many([26,33],'hind_paw.L')

joint_src={
 'fore.R':[(-.267,-.086,.354),(-.227,-.098,.215),(-.270,-.120,.054)],
 'fore.L':[(-.267,.090,.354),(-.285,.106,.196),(-.343,.106,.052)],
 'hind.R':[(.157,-.089,.335),(.201,-.105,.211),(.279,-.127,.113),(.277,-.133,.034)],
 'hind.L':[(.154,.093,.335),(.168,.113,.208),(.201,.131,.119),(.125,.145,.029)],
}
joints={n:[pt(p) for p in v] for n,v in joint_src.items()}
landmarks={}
for label,ids,neck in [('shoulder',[0],False),('head_roof',[9],True),('nose',[7],True),('rump',[3],False)]:
    ps=[pt(source[n].matrix_world@v.co,neck) for n in ids for v in source[n].data.vertices]
    landmarks[label]={'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)]}
for o in source.values():bpy.data.objects.remove(o,do_unlink=True)

def join(obs,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    if len(obs)>1:bpy.ops.object.join()
    o=bpy.context.object;o.name=name
    return o
high={k:join(v,'HIGH_'+k) for k,v in groups.items()}
low={};budgets={
 'chest':1040,'pelvis':450,'neck':410,'head':490,'jaw':270,'key':160,'tail_01':85,'tail_02':75,
 'fore_upper.R':260,'fore_upper.L':270,'fore_lower.R':155,'fore_lower.L':160,'fore_paw.R':120,'fore_paw.L':130,
 'hind_upper.R':230,'hind_upper.L':230,'hind_lower.R':130,'hind_lower.L':130,'hind_hock.R':90,'hind_hock.L':100,'hind_paw.R':110,'hind_paw.L':110}
for name,h in high.items():
    o=h.copy();o.data=h.data.copy();sc.collection.objects.link(o);o.name='LOW_'+name
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000006)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000002)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(o.data);bm.free()
    bpy.context.view_layer.objects.active=o
    tri=sum(len(p.vertices)-2 for p in o.data.polygons)
    d=o.modifiers.new('Rigid silhouette reduction','DECIMATE');d.ratio=min(1,budgets[name]/tri);d.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=d.name)
    # Export/bake triangulation is now fixed. Recompute low shading for the new mesh.
    if o.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in o.data.polygons:p.use_smooth=True
    low[name]=o

def primitive(name,verts,faces,material):
    m=bpy.data.meshes.new(name);m.from_pydata(verts,[],faces);m.materials.append(material)
    for p in m.polygons:p.use_smooth=True
    o=bpy.data.objects.new(name,m);sc.collection.objects.link(o)
    return o
def cyl(name,a,b,r,material,segments=10,r2=None):
    a,b=Vector(a),Vector(b);d=(b-a).normalized();u=d.cross(Vector((0,0,1)))
    if u.length<.01:u=d.cross(Vector((1,0,0)))
    u.normalize();v=d.cross(u).normalized();r2=r if r2 is None else r2
    vs=[p+(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments))*rr for p,rr in [(a,r),(b,r2)] for i in range(segments)]
    fs=[]
    for i in range(segments):
        j=(i+1)%segments;fs += [(i,j,j+segments),(i,j+segments,i+segments)]
    fs += [tuple(reversed(range(segments))),tuple(range(segments,segments*2))]
    return primitive(name,vs,fs,material)
def add_geo(label,o):
    # Same analytic object belongs to both the high projection and low delivery.
    h=o.copy();h.data=o.data.copy();sc.collection.objects.link(h)
    if label in low:
        low[label]=join([low[label],o],'LOW_'+label);high[label]=join([high[label],h],'HIGH_'+label)
    else:
        o.name='LOW_'+label;h.name='HIGH_'+label;low[label]=o;high[label]=h
def hinge(label,c,r,width):
    c=Vector(c);add_geo(label,cyl('joint_cap',c-Vector((width/2,0,0)),c+Vector((width/2,0,0)),r,brass,10))

# Recessed full axle volumes cover open source mating rims during articulation.
for stem,js in joints.items():
    limb,side=stem.split('.')
    hinge(limb+'_upper.'+side,js[0],.036 if limb=='fore' else .034,.047)
    hinge(limb+'_lower.'+side,js[1],.021,.044)
    if limb=='hind':hinge('hind_hock.'+side,js[2],.019,.038)
    hinge(limb+'_paw.'+side,js[-1],.015,.033)
hinge('jaw',pt((-.342,0,.505),True),.024,.074)
# Joint interiors use deliberate hidden overlapping volumes, not coplanar caps.
add_geo('neck',cyl('neck_inner',pt((-.272,0,.350)),pt((-.321,0,.438),True),.042,dark,12,r2=.030))
add_geo('pelvis',cyl('spine_bearing',pt((.10,0,.352)),pt((.185,0,.352)),.027,dark,10))
hinge('tail_01',pt((.231,0,.366)),.011,.025)
hinge('tail_02',pt((.397,0,.385)),.010,.021)

pistons={}
for stem,js in joints.items():
    limb,side=stem.split('.');s=-1 if side=='R' else 1
    a=js[0].lerp(js[1],.39)+Vector((s*.025, -.015, .004))
    b=js[1].lerp(js[2],.12)+Vector((s*.025, -.008, .004))
    axis=(b-a).normalized();length=(b-a).length
    barrel_len=length*.63;rod_len=length*.68
    outer=limb+'_piston_case.'+side;inner=limb+'_piston_rod.'+side
    add_geo(outer,cyl(outer,a,a+axis*barrel_len,.0125,brass,10))
    add_geo(inner,cyl(inner,b-axis*rod_len,b,.0052,steel,8))
    # Transverse mounting pins actually bridge each piston eye into the limb.
    add_geo(limb+'_upper.'+side,cyl('piston_mount_upper',a-Vector((s*.031,0,0)),a,.010,brass,8))
    add_geo(limb+'_lower.'+side,cyl('piston_mount_lower',b-Vector((s*.030,0,0)),b,.008,brass,8))
    pistons[stem]={'case':outer,'rod':inner,'a':list(a),'b':list(b),'barrel_length':barrel_len,'rod_length':rod_len,
                   'a_bone':limb+'_upper.'+side,'b_bone':limb+'_lower.'+side}

# The small cyan source paint is reinforced with actual separate emissive surfaces.
core=pt((-.409,0,.555),True);axis=(FIT.to_3x3()@NECK_T.to_3x3()@Vector((-.55,0,.84))).normalized()
add_geo('core',cyl('Optic_mount',core-axis*.005,core+axis*.002,.018,brass,12))
add_geo('core_glow',cyl('Optic_lens',core+axis*.0025,core+axis*.004,.014,cyan,12))
tail_tip=pt((.492,.001,.443))
add_geo('tail_glow',cyl('Tail_light',tail_tip-Vector((0,.005,0)),tail_tip+Vector((0,.005,0)),.0075,cyan,8))

# Fill only tiny boundary loops. Large mechanical mouths remain covered by axles.
# This preserves intentional open shells rather than spanning unrelated rims.
cap_count=0
topology_repairs=[]
for name,o in low.items():
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001)
    removed=[]
    # Collapsing the original segmented seam fans can leave three-face edges.
    # Retain the two largest surfaces; only discard the extra thin flap.
    while True:
        bad=next((e for e in bm.edges if len(e.link_faces)>2),None)
        if bad is None:break
        f=min(bad.link_faces,key=lambda f:f.calc_area())
        removed.append({'area_m2':f.calc_area(),'center':list(f.calc_center_median())})
        bmesh.ops.delete(bm,geom=[f],context='FACES_ONLY')
    wire=[e for e in bm.edges if not e.link_faces]
    if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
    loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    if name.startswith(('fore_','hind_')) and 'piston' not in name:
        boundary=[e for e in bm.edges if e.is_boundary]
        caps=bmesh.ops.holes_fill(bm,edges=boundary,sides=0).get('faces',[])
        if caps:
            # Add the matching recessed metal cap to the bake source as well.
            cap_verts=[];cap_faces=[]
            cap_total=0
            for face in list(caps):
                vs=list(face.verts);face.normal_update()
                center=face.calc_center_median()-face.normal*.0015
                bmesh.ops.delete(bm,geom=[face],context='FACES_ONLY')
                cv=bm.verts.new(center)
                for i in range(len(vs)):
                    verts=[vs[i],vs[(i+1)%len(vs)],cv]
                    new=bm.faces.new(verts)
                    ids=[]
                    for v in verts:ids.append(len(cap_verts));cap_verts.append(tuple(v.co))
                    cap_faces.append(ids);cap_total+=1
            cap=primitive('HIGH_joint_caps_'+name,cap_verts,cap_faces,dark)
            high[name]=join([high[name],cap],'HIGH_'+name)
            cap_count+=cap_total
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(o.data);bm.free()
    if removed:topology_repairs.append({'group':name,'removed_flaps':removed})

# Explode paired objects for a projection bake without neighbouring part bleed.
# UVs are newly unwrapped on the low delivery, then restored to assembly positions.
offsets={};verts_before={};part_sizes={}
for i,(name,o) in enumerate(low.items()):
    offset=Vector(((i%7)*2,(i//7)*2,0));offsets[name]=list(offset)
    for ob in (o,high[name]):
        for v in ob.data.vertices:v.co+=offset
    for uv in list(o.data.uv_layers):o.data.uv_layers.remove(uv)
    o.data.uv_layers.new(name='UVMap')
    g=o.vertex_groups.new(name=name);g.add(list(range(len(o.data.vertices))),1.,'REPLACE')
    o['rigid_group']=name;part_sizes[name]=len(o.data.polygons)
lo=join(list(low.values()),'Hound_Bake_Low')
bpy.context.view_layer.objects.active=lo
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.002,area_weight=.0,correct_aspect=True,scale_to_bounds=True)
bpy.ops.uv.pack_islands(rotate=True,margin=.006,shape_method='AABB')
bpy.ops.object.mode_set(mode='OBJECT')
hi=join(list(high.values()),'Hound_Bake_High')
hi.hide_render=False
sc.render.engine='CYCLES';sc.cycles.samples=16
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='CUDA';prefs.get_devices()
    for d in prefs.devices:d.use=d.type!='CPU'
    sc.cycles.device='GPU'
except Exception:sc.cycles.device='CPU'
sc.render.bake.use_selected_to_active=True;sc.render.bake.cage_extrusion=.018;sc.render.bake.max_ray_distance=.045
sc.render.bake.margin=5;sc.render.bake.use_clear=True
targetmat=bpy.data.materials.new('Bake_Target');targetmat.use_nodes=True
lo.data.materials.clear();lo.data.materials.append(targetmat)
for p in lo.data.polygons:p.material_index=0
targetnode=targetmat.node_tree.nodes.new('ShaderNodeTexImage');targetmat.node_tree.nodes.active=targetnode
# Preserve original shader output; expose selected PBR fields through emission.
source_mats=list({m for m in hi.data.materials if m is not None})
original_links={}
for m in source_mats:
    ns=m.node_tree.nodes;out=next(n for n in ns if n.type=='OUTPUT_MATERIAL')
    original_links[m]=out.inputs['Surface'].links[0].from_socket
def bake(label,kind):
    im=bpy.data.images.new('Hound_'+label,width=1024,height=1024,alpha=False)
    im.colorspace_settings.name='sRGB' if label=='color' else 'Non-Color'
    if label=='normal':im.generated_color=(.5,.5,1,1)
    targetnode.image=im
    for m in source_mats:
        ns=m.node_tree.nodes;ls=m.node_tree.links;out=next(n for n in ns if n.type=='OUTPUT_MATERIAL')
        if kind=='NORMAL':ls.new(original_links[m],out.inputs['Surface']);continue
        bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED');em=ns.new('ShaderNodeEmission')
        if label=='color':
            s=bs.inputs['Base Color']
            if s.is_linked:ls.new(s.links[0].from_socket,em.inputs['Color'])
            else:em.inputs['Color'].default_value=s.default_value
        else:
            comb=ns.new('ShaderNodeCombineColor');comb.inputs['Red'].default_value=1
            for labelin,sock in [('Green','Roughness'),('Blue','Metallic')]:
                s=bs.inputs[sock]
                if s.is_linked:ls.new(s.links[0].from_socket,comb.inputs[labelin])
                else:comb.inputs[labelin].default_value=s.default_value
            ls.new(comb.outputs['Color'],em.inputs['Color'])
        ls.new(em.outputs[0],out.inputs['Surface'])
    bpy.ops.object.select_all(action='DESELECT');hi.select_set(True);lo.select_set(True);bpy.context.view_layer.objects.active=lo
    bpy.ops.object.bake(type=kind)
    im.filepath_raw=str(BASE/'textures'/('hound_'+label+'.png'));im.file_format='PNG';im.save();im.pack()
    print('BAKED',label,flush=True)
    return im
images={label:bake(label,kind) for label,kind in [('color','EMIT'),('orm','EMIT'),('normal','NORMAL')]}
for m in source_mats:
    out=next(n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL');m.node_tree.links.new(original_links[m],out.inputs['Surface'])
bpy.data.objects.remove(hi,do_unlink=True)

# A real small emission image is used only on dedicated lens surfaces.
emission=bpy.data.images.new('Hound_emission',width=64,height=64,alpha=False)
emission.generated_color=(.035,.65,.56,1);emission.colorspace_settings.name='sRGB'
emission.filepath_raw=str(BASE/'textures/hound_emission.png');emission.file_format='PNG';emission.save();emission.pack()
def runtime_mat(name,glow=False):
    m=bpy.data.materials.new(name);m.use_nodes=True;ns=m.node_tree.nodes;ls=m.node_tree.links
    bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED')
    tex={}
    for label,im in images.items():
        node=ns.new('ShaderNodeTexImage');node.image=im;tex[label]=node
    ls.new(tex['color'].outputs['Color'],bs.inputs['Base Color'])
    sep=ns.new('ShaderNodeSeparateColor');ls.new(tex['orm'].outputs['Color'],sep.inputs['Color'])
    ls.new(sep.outputs['Green'],bs.inputs['Roughness']);ls.new(sep.outputs['Blue'],bs.inputs['Metallic'])
    n=ns.new('ShaderNodeNormalMap');ls.new(tex['normal'].outputs['Color'],n.inputs['Color']);ls.new(n.outputs['Normal'],bs.inputs['Normal'])
    if glow:
        e=ns.new('ShaderNodeTexImage');e.image=emission;ls.new(e.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=1.1
    return m
lo.data.materials.clear();lo.data.materials.append(runtime_mat('M_Hound_Surface'));lo.data.materials.append(runtime_mat('M_Hound_Core',True))
for p in lo.data.polygons:
    gn=lo.vertex_groups[lo.data.vertices[p.vertices[0]].groups[0].group].name
    p.material_index=int(gn in ('core_glow','tail_glow'))
for v in lo.data.vertices:
    gn=lo.vertex_groups[v.groups[0].group].name;v.co-=Vector(offsets[gn])
lo.name='Hound_Rigid_Surface'
lo.data.update()
sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1.0
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'hound_geometry.blend'),compress=True)
report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':source_hash,'source_unchanged':source_hash==hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
 'triangles':sum(len(p.vertices)-2 for p in lo.data.polygons),'rigid_groups':list(low),'part_triangles':part_sizes,
 'static_fit_matrix':[[float(v) for v in r] for r in FIT],'support_center_source':list(support_center),'neck_rest_tilt_degrees':-7,'fitted_source_landmarks':landmarks,'joints':{k:[list(v) for v in vs] for k,vs in joints.items()},
 'pistons':pistons,'core':list(core),'tail_tip':list(tail_tip),'provenance':provenance,'topology_repairs':topology_repairs,'limb_cap_triangles':cap_count,
 'source_pistons_replaced':[16,19,22,'17 lower portion'],'bake':'Exploded semantic high/low pairs, new packed UVs, Cycles color/ORM/tangent normal 1024, separate 64px emission',
 'coordinates':'Blender +Y front / Z up -> glTF and Godot -Z front / Y up; explicit runtime check required'}
(BASE/'geometry.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('HOUND_GEOMETRY_COMPLETE',report['triangles'],len(low),flush=True)
