"""Derive two rigid automaton appearances from the accepted v2, without editing it."""
import bpy, bmesh, json, math, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/automaton_nodes_v1'
OUT=ROOT/'reports/automaton_nodes_v1'
GAME=ROOT/'game/assets/actors/automaton_nodes_v1'
SOURCE=ROOT/'assets/actors/summons_v2/authoring/automaton_v2.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source_hash=sha(SOURCE)
summaries=[]

def material(name,color,metal=.7,rough=.4):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m

def finish(obj,name,mat):
    obj.name=name;obj.data.materials.clear();obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    return obj

def box(name,pos,size,mat,bevel=.016):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
    o=bpy.context.object;o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    b=o.modifiers.new('Rounded plate edges','BEVEL');b.width=bevel;b.segments=2
    bpy.ops.object.modifier_apply(modifier=b.name)
    return finish(o,name,mat)

def cylinder(name,pos,radius,depth,mat,axis=(0,0,1),vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=pos)
    o=bpy.context.object;o.rotation_mode='QUATERNION';o.rotation_quaternion=Vector((0,0,1)).rotation_difference(Vector(axis))
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    return finish(o,name,mat)

def blade(name,center,mat):
    # Axle on X; a toothed steel silhouette, with a closed bevelled cutting rim.
    verts=[];faces=[];count=56;cy,cz=center[1],center[2]
    for x,scale in [(-.014,.91),(0,1),(.014,.91)]:
        for i in range(count):
            angle=math.tau*i/count;rad=.174*([.88,1,.98,.88][i%4])*scale
            verts.append((center[0]+x,cy+rad*math.sin(angle),cz+rad*math.cos(angle)))
    for ring in range(2):
        for i in range(count):j=(i+1)%count;faces.append((ring*count+i,ring*count+j,(ring+1)*count+j,(ring+1)*count+i))
    faces.extend([tuple(range(count-1,-1,-1)),tuple(range(2*count,3*count))])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o);mesh.materials.append(mat)
    return o

for variant in ['A','B']:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene=bpy.context.scene;scene.render.fps=24
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    original=next(o for o in scene.objects if o.type=='MESH')
    rig.animation_data.action=None
    for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
    scene.frame_set(1);bpy.context.view_layer.update()
    rest={b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones}
    original_vertices=hashlib.sha256(b''.join(__import__('struct').pack('<3f',*v.co) for v in original.data.vertices)).hexdigest()
    brass=material('Node aged brass',(.42,.26,.085),.8,.36)
    teal=material('Node enamel teal',(.027,.14,.13),.55,.38)
    steel=material('Node cutting steel',(.42,.48,.50),.87,.29)
    copper=material('Node copper casing',(.36,.105,.033),.74,.43)
    rope=material('Node fuse cord',(.24,.15,.065),.05,.82)
    extras=[]
    def part(name,parent,objects,delay=.34):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects:o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        o=bpy.context.object;o.name=name+'_mesh'
        pts=[o.matrix_world@v.co for v in o.data.vertices]
        center=Vector(tuple((min(p[i] for p in pts)+max(p[i] for p in pts))/2 for i in range(3)))
        extras.append({'name':name,'parent':parent,'object':o,'center':center,'delay':delay})
    if variant=='B':
        armor=[box('Breastplate',(.01,.171,.42),(.29,.061,.206),teal,.028)]
        armor += [box('Chest brass rail '+str(s),(.01+s*.127,.207,.42),(.025,.018,.17),brass,.006) for s in [-1,1]]
        armor += [cylinder('Chest rivet',(.01+s*.10,.212,.42+t*.07),.014,.012,brass,(0,1,0),10) for s in [-1,1] for t in [-1,1]]
        part('node_chest','part_000',armor,.22)
        for side,x,parent in [('L',.236,'part_009'),('R',-.215,'part_010')]:
            objects=[box('Pauldrons '+side,(x,.025,.495),(.205,.205,.115),teal,.034),box('Shoulder edging '+side,(x,.126,.481),(.18,.024,.072),brass,.012)]
            part('node_shoulder_'+side,parent,objects,.29)
        for side,x,parent in [('L',.155,'part_008_L'),('R',-.128,'part_008_R')]:
            part('node_shin_'+side,parent,[box('Leg guard '+side,(x,.078,.18),(.118,.062,.15),teal,.015),box('Leg brass toe '+side,(x,.113,.15),(.098,.012,.025),brass,.005)],.14)
        part('node_wrist_guard','part_004',[box('Offhand guard',(-.334,.083,.30),(.14,.105,.16),teal,.025)],.36)
        part('node_blade_mount','part_001',[cylinder('Saw drive',(.39,.112,.296),.059,.155,brass,(1,0,0)),box('Saw motor',(.346,.10,.31),(.105,.13,.12),teal,.018)],.39)
        part('node_blade','part_001',[blade('Cutting wheel',(.465,.112,.296),steel),cylinder('Blade hub',(.485,.112,.296),.047,.022,brass,(1,0,0)),cylinder('Blade axle',(.501,.112,.296),.018,.016,teal,(1,0,0),10)],.48)
    else:
        objects=[cylinder('Copper charge',(.01,.182,.404),.112,.24,copper,(1,0,0),20)]
        objects += [cylinder('Charge binding '+str(s),(.01+s*.106,.182,.404),.119,.027,brass,(1,0,0),20) for s in [-1,1]]
        objects += [box('Charge retaining bridge',(.01,.284,.404),(.18,.022,.055),teal,.009)]
        part('node_charge','part_000',objects,.23)
        part('node_igniter','part_002',[cylinder('Fuse socket',(.055,.08,.785),.038,.055,brass),cylinder('Igniter collar',(.055,.08,.81),.024,.018,copper)],.46)
        controls=[Vector(v) for v in [(.055,.08,.816),(.067,.08,.877),(.115,.085,.935),(.183,.10,.966),(.245,.115,.949)]]
        path=[]
        for i in range(13):
            t=i/12*4;idx=min(3,int(t));path.append(controls[idx].lerp(controls[idx+1],t-idx))
        for i in range(12):
            a,b=path[i:i+2];delta=b-a
            part('fuse_%02d'%i,'part_002',[cylinder('Cord %02d'%i,(a+b)/2,.013,delta.length*1.04,rope,delta.normalized(),8)],.49+i*.003)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
    for e in extras:
        b=rig.data.edit_bones.new(e['name']);b.head=e['center'];b.tail=e['center']+Vector((0,.045,0));b.parent=rig.data.edit_bones[e['parent']]
    bpy.ops.object.mode_set(mode='OBJECT')
    for e in extras:
        o=e['object'];g=o.vertex_groups.new(name=e['name']);g.add(list(range(len(o.data.vertices))),1,'REPLACE')
        o.parent=rig;mod=o.modifiers.new('Rigid node attachment','ARMATURE');mod.object=rig
        rig.pose.bones[e['name']].rotation_mode='QUATERNION'
    actions={a.name:a for a in bpy.data.actions}
    for clip,action in actions.items():
        rig.animation_data.action=action;first,last=map(int,action.frame_range)
        states=[]
        for i,e in enumerate(extras):
            angle=i*2.399963;explode=clip=='explode'
            states.append({'p':e['center'].copy(),'q':Quaternion(),'v':Vector((math.cos(angle),math.sin(angle),0))*(1.55 if explode else .28)+Vector((0,0,1.8 if explode else .1)),
                'axis':Vector((math.sin(i+1),math.cos(i*1.73),.4)).normalized(),'spin':8 if explode else 2.5,
                'offsets':[v.co-e['center'] for v in e['object'].data.vertices]})
        for frame in range(first,last+1):
            scene.frame_set(frame);bpy.context.view_layer.update()
            for e,state in zip(extras,states):
                pb=rig.pose.bones[e['name']];pb.matrix_basis=Matrix.Identity(4)
                if clip in ['death','explode']:
                    if frame>first:
                        for sub in range(10):
                            dt=1/240;state['v'].z-=6.5*dt;state['p']+=state['v']*dt
                            state['q']=(Quaternion(state['axis'],state['spin']*dt)@state['q']).normalized()
                            floor=-min((state['q']@offset).z for offset in state['offsets'])+.002
                            if state['p'].z<floor:
                                state['p'].z=floor;state['v'].z=max(0,-state['v'].z*.1) if state['v'].z<-.4 else 0
                                state['v'].x*=math.exp(-8*dt);state['v'].y*=math.exp(-8*dt);state['spin']*=math.exp(-9*dt)
                    pb.matrix=Matrix.Translation(state['p'])@state['q'].to_matrix().to_4x4()
                for channel in ['location','rotation_quaternion','scale']:pb.keyframe_insert(channel,frame=frame,group=pb.name)
    rig.animation_data.action=None
    for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
    scene.frame_set(1);bpy.context.view_layer.update()
    assert all([list(row) for row in rig.data.bones[name].matrix_local]==value for name,value in rest.items())
    assert hashlib.sha256(b''.join(__import__('struct').pack('<3f',*v.co) for v in original.data.vertices)).hexdigest()==original_vertices
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);original.select_set(True)
    for e in extras:e['object'].select_set(True)
    bpy.context.view_layer.objects.active=rig
    name='automaton_'+variant.lower()
    out=BASE/'exports'/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_anim_slide_to_zero=True,export_force_sampling=True,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_optimize_animation_size=False)
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'authoring'/(name+'.blend')))
    shutil.copy2(out,GAME/out.name)
    # A separate static copy preserves the same rigid boundaries for cast assembly.
    rig.animation_data.action=actions['idle'];scene.frame_set(1);bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get();static=[];part_info=[]
    for obj in [original]+[e['object'] for e in extras]:
        evaluated=obj.evaluated_get(dg);posed=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=dg)
        groups={g.index:g.name for g in obj.vertex_groups}
        membership={v.index:groups[max(v.groups,key=lambda g:g.weight).group] for v in obj.data.vertices}
        for group in sorted(set(membership.values())):
            mesh=posed.copy();bm=bmesh.new();bm.from_mesh(mesh);bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm,geom=[v for v in bm.verts if membership[v.index]!=group],context='VERTS');bm.to_mesh(mesh);bm.free()
            pts=[obj.matrix_world@v.co for v in mesh.vertices]
            c=Vector(tuple((min(p[i] for p in pts)+max(p[i] for p in pts))/2 for i in range(3)))
            mesh.transform(Matrix.Translation(-c)@obj.matrix_world)
            part_obj=bpy.data.objects.new(group,mesh);scene.collection.objects.link(part_obj);part_obj.location=c;static.append(part_obj)
            part_info.append({'name':group,'triangles':sum(len(p.vertices)-2 for p in mesh.polygons),'delay':next((e['delay'] for e in extras if e['name']==group),None)})
    bpy.ops.object.select_all(action='DESELECT')
    for o in static:o.select_set(True)
    bpy.context.view_layer.objects.active=static[0]
    static_out=BASE/'exports'/(name+'_parts.glb')
    bpy.ops.export_scene.gltf(filepath=str(static_out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False)
    shutil.copy2(static_out,GAME/static_out.name)
    metadata={'variant':variant,'parts':part_info,'triangles':sum(p['triangles'] for p in part_info),'bones':len(rig.data.bones),
        'source':str(SOURCE.relative_to(ROOT)).replace('\\','/'),'source_sha256':source_hash,'source_unchanged':sha(SOURCE)==source_hash,
        'base_vertices_unchanged':True,'base_rest_bones_preserved':len(rest),'glb_sha256':sha(out),'parts_sha256':sha(static_out)}
    if variant=='A':
        # Convert Blender world rest points to Godot, then into the existing head part rest frame.
        head=rig.data.bones['part_002'].matrix_local
        metadata['fuse_points_head_local']=[list(head.inverted()@p) for p in path]
    else:
        metadata['blade_axis_local']=list(rig.data.bones['node_blade'].matrix_local.to_3x3().inverted()@Vector((1,0,0)))
    (BASE/(name+'.json')).write_text(json.dumps(metadata,indent=2),encoding='utf-8');summaries.append(metadata)
    # Keep Blender on a clean, fully rigged delivery, without the temporary static export objects.
    for o in static:bpy.data.objects.remove(o,do_unlink=True)
    rig.animation_data.action=actions['idle'];scene.frame_set(1);bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'authoring'/(name+'.blend')))
assert sha(SOURCE)==source_hash
(OUT/'build.json').write_text(json.dumps(summaries,indent=2),encoding='utf-8')
print('AUTOMATON_NODE_MODELS_COMPLETE',[(s['variant'],s['triangles'],len(s['parts']),s['bones']) for s in summaries])
