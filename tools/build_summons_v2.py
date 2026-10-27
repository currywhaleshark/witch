"""Build rigid segmented summons and bake controlled gravity/scatter destruction.

Each triangle belongs to one rigid part/bone. Ground contact is baked; this is
not a live rigid-body solver and pieces do not participate in combat collision.
"""
import bpy, bmesh, math, json, hashlib, shutil, sys
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/summons_v2'
OUT=ROOT/'reports/summons_v2/build'
GAME=ROOT/'game/assets/actors/summons_v2'
IDS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['automaton','turret']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def bounds(o):
    pts=[v.co for v in o.data.vertices]
    lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
    return lo,hi

def build(actor):
    H=.85 if actor=='automaton' else .9
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.render.fps=24
    src=BASE/'source'/f'{actor}_segmented_v2.glb';src_hash=sha(src)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes=[o for o in scene.objects if o.type=='MESH']
    coords=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    low=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    high=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    origin=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
    turn=Matrix.Rotation(-math.pi/2 if actor=='turret' else math.pi,4,'Z')
    source_tri=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    for o in meshes:
        mat=o.matrix_world.copy()
        for v in o.data.vertices:v.co=turn@((mat@v.co-origin)*(H/(high.z-low.z)))
        o.parent=None;o.matrix_world=Matrix.Identity(4)
        o['source_part']=int(o.name.rsplit('_',1)[-1])
    # Tripo assigned both disconnected leg shafts to part 8. Keep its immutable
    # download; split this working copy at the empty centre between the shafts.
    if actor=='automaton':
        o=next(o for o in meshes if o['source_part']==8)
        for side,positive in [('L',True),('R',False)]:
            copy=o.copy();copy.data=o.data.copy();scene.collection.objects.link(copy)
            bm=bmesh.new();bm.from_mesh(copy.data)
            remove=[v for v in bm.verts if (v.co.x<0 if positive else v.co.x>=0)]
            bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(copy.data);bm.free()
            copy.name='tripo_part_8_'+side;copy['side']=side;meshes.append(copy)
        meshes.remove(o);bpy.data.objects.remove(o,do_unlink=True)
    for o in meshes:
        # glTF splits positions at normals/UV seams. Weld coincident positions
        # only inside this one part; UVs stay on their independent face loops.
        # Collapsing the disconnected seam copies produced jagged metal flakes.
        bm=bmesh.new();bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000005)
        bm.to_mesh(o.data);bm.free()
        tri=sum(len(p.vertices)-2 for p in o.data.polygons)
        # Many small closed metal parts need more boundary triangles than v1's
        # fused surface; keep the turret's gear teeth and part rims readable.
        budget=max(24,math.floor((17640 if actor=='turret' else 9800)*tri/source_tri))
        bpy.context.view_layer.objects.active=o
        dec=o.modifiers.new('Separate part reduction','DECIMATE');dec.ratio=min(1,budget/tri);dec.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=dec.name)
        for p in o.data.polygons:p.use_smooth=True
    atlas_dir=BASE/'textures'/actor
    atlas=json.loads((atlas_dir/'atlas.json').read_text(encoding='utf-8'))
    material=bpy.data.materials.new(actor+'_rigid_atlas');material.use_nodes=True
    bs=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    texnodes={}
    for label in ['color','metal_rough','normal']:
        im=bpy.data.images.load(str(atlas_dir/f'{label}.png'));im.pack()
        if label!='color':im.colorspace_settings.name='Non-Color'
        node=material.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;texnodes[label]=node
    links=material.node_tree.links;links.new(texnodes['color'].outputs['Color'],bs.inputs['Base Color'])
    separate=material.node_tree.nodes.new('ShaderNodeSeparateColor');links.new(texnodes['metal_rough'].outputs['Color'],separate.inputs['Color'])
    links.new(separate.outputs['Green'],bs.inputs['Roughness']);links.new(separate.outputs['Blue'],bs.inputs['Metallic'])
    normal=material.node_tree.nodes.new('ShaderNodeNormalMap');links.new(texnodes['normal'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    for o in meshes:
        for poly in o.data.polygons:
            original=o.data.materials[poly.material_index].name
            tile=atlas['materials'][original];size=atlas['size']
            for index in poly.loop_indices:
                uv=o.data.uv_layers.active.data[index].uv
                uv.x=(tile['x']+uv.x*tile['size'])/size
                uv.y=1-(tile['y']+(1-uv.y)*tile['size'])/size
            poly.material_index=0
        o.data.materials.clear();o.data.materials.append(material)
    for mat in list(bpy.data.materials):
        if mat!=material and mat.users==0:bpy.data.materials.remove(mat)
    for im in list(bpy.data.images):
        if im.users==0:bpy.data.images.remove(im)
    bone_specs={'root':((0,0,0),None)}
    def bone(name,point,parent='root'):bone_specs[name]=(tuple(Vector(point)*H),parent)
    if actor=='turret':
        bone('carriage',(0,.063,.40));bone('barrel',(0,.25,.72),'carriage')
        bone('drive_gear',(0,-.207,.719),'carriage');bone('key',(0,-.39,.71),'carriage')
        bone('muzzle',(0,.65,.723),'barrel')
    else:
        bone('torso',(0,0,.37));bone('head',(.012,.06,.63),'torso')
        bone('key',(-.04,-.17,.69),'torso')
        for side,s in [('L',1),('R',-1)]:
            bone('arm_'+side,(s*.245,.025,.57),'torso')
            bone('forearm_'+side,(s*.33,.025,.405),'arm_'+side)
            bone('leg_'+side,(s*.18,.016,.30));bone('foot_'+side,(s*.20,.06,.075),'leg_'+side)
        bone('muzzle',(.39,.24,.34),'forearm_L')
    parts=[]
    for o in sorted(meshes,key=lambda o:o.name):
        part=int(o['source_part']);lo,hi=bounds(o);center=(lo+hi)/2
        if actor=='turret':
            if part in [1,28,48,52,79]:parent='barrel'
            elif part==0:parent='drive_gear'
            elif part in [16,25,26,27,30,55]:parent='key'
            elif part==6 or center.z/H>.41:parent='carriage'
            else:parent='root'
        else:
            parent={0:'torso',1:'forearm_L',2:'head',3:'foot_R',4:'forearm_R',5:'foot_L',6:'key',9:'arm_L',10:'arm_R',11:'head',13:'torso'}.get(part,'leg_'+str(o.get('side','L')))
        name='part_%03d'%part+('_'+o['side'] if 'side' in o else '')
        bone_specs[name]=(tuple(center),parent)
        parts.append({'bone':name,'source_part':part,'parent':parent,'center':center.copy(),'object':o,
                      'offsets':[v.co-center for v in o.data.vertices], 'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)})
        o.name=name+'_mesh'
    armature=bpy.data.armatures.new(actor+'_rigid_parts_v2');rig=bpy.data.objects.new(actor+'_rigid_parts_v2',armature);scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    for name,(point,parent) in bone_specs.items():
        b=armature.edit_bones.new(name);b.head=point;b.tail=Vector(point)+Vector((0,.055*H,0))
        if parent:b.parent=armature.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in parts:
        o=p['object'];g=o.vertex_groups.new(name=p['bone']);g.add(list(range(len(o.data.vertices))),1.,'REPLACE')
        o.parent=rig
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=actor+'_rigid_surface_v2'
    mod=obj.modifiers.new('Rigid part skin','ARMATURE');mod.object=rig
    for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
    rig['source']='User Tripo segmentation';rig['rigid_part_count']=len(parts)
    rig.animation_data_create()
    def rot(n,axis,angle):rig.pose.bones[n].rotation_quaternion=Quaternion(Vector(axis),math.radians(angle))
    def mov(n,x=0,y=0,z=0):rig.pose.bones[n].location=Vector((x,y,z))*H
    # Fixed 240 Hz integration yields reproducible gravity and damped floor bounces.
    # Rotated actual part vertices determine support height, not a large sphere.
    trajectories={}
    for mode in ['death']+(['explode'] if actor=='automaton' else []):
        results=[]
        states=[]
        for i,p in enumerate(parts):
            center=p['center'];angle=math.atan2(center.y-.02,center.x)+.3*math.sin(i*3.1)
            if math.hypot(center.x,center.y)<.10:angle=i*2.399963
            speed=(1.4+.16*(i%7)) if mode=='explode' else (.20+.075*(i%5))
            direction=Vector((math.cos(angle),math.sin(angle),0))
            v=direction*speed;v.z=(1.7+.15*(i%6)) if mode=='explode' else (.06+.05*(i%3))
            axis=Vector((math.sin(i*2.31+.5),math.cos(i*1.73),.4*math.sin(i+.3))).normalized()
            states.append({'p':center.copy(),'v':v,'q':Quaternion(),'axis':axis,'spin':(7.0+i%5) if mode=='explode' else (2.2+(i%5)*.7), 'delay':0 if mode=='explode' else .018*(i%7)})
        for step in range(481):
            if step%10==0:results.append([(s['p'].copy(),s['q'].copy()) for s in states])
            if step==480:break
            t=step/240;dt=1/240
            for p,s in zip(parts,states):
                if t<s['delay']:continue
                s['v'].z-=6.5*dt;s['p']+=s['v']*dt
                s['q']=(Quaternion(s['axis'],s['spin']*dt)@s['q']).normalized()
                floor=-min((s['q']@offset).z for offset in p['offsets'])+.001
                if s['p'].z<=floor:
                    s['p'].z=floor
                    if s['v'].z<0:s['v'].z=-s['v'].z*.16 if s['v'].z<-.35 else 0
                    drag=math.exp(-8*dt);s['v'].x*=drag;s['v'].y*=drag;s['spin']*=math.exp(-9*dt)
        trajectories[mode]=results
    clips={'idle':49,'attack':25,'hit':13,'death':49}
    if actor=='automaton':clips={'idle':49,'move':25,'attack':25,'hit':13,'death':49,'explode':49}
    for clip,count in clips.items():
        action=bpy.data.actions.new(clip);action.use_fake_user=True;rig.animation_data.action=action
        for frame in range(1,count+1):
            scene.frame_set(frame);t=(frame-1)/(count-1);phase=math.tau*t
            for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
            wind=smooth(0,.33,t)*(1-smooth(.36,.5,t));strike=smooth(.35,.5,t)*(1-smooth(.58,1,t))
            if clip in trajectories:
                bpy.context.view_layer.update()
                for p,(pos,q) in zip(parts,trajectories[clip][frame-1]):
                    rig.pose.bones[p['bone']].matrix=Matrix.Translation(pos)@q.to_matrix().to_4x4()
            elif actor=='turret':
                if clip=='idle':
                    rot('carriage',(0,0,1),4*math.sin(phase));rot('key',(0,1,0),18*math.sin(phase));rot('drive_gear',(0,1,0),-5*math.sin(phase))
                if clip=='attack':mov('barrel',y=-.055*strike);rot('key',(0,1,0),32*strike);rot('drive_gear',(0,1,0),-9*strike)
                if clip=='hit':rot('carriage',(1,0,0),-2.5*math.sin(math.pi*t))
            else:
                rot('torso',(0,0,1),1.3*math.sin(phase));rot('head',(0,0,1),-1.2*math.sin(phase));rot('key',(0,1,0),12*math.sin(phase))
                if clip=='move':
                    for side,s in [('L',1),('R',-1)]:
                        wave=s*math.sin(phase);lift=max(0,s*math.cos(phase))
                        rot('leg_'+side,(1,0,0),15*wave);rot('foot_'+side,(1,0,0),-15*wave)
                        mov('leg_'+side,z=.024*lift);rot('arm_'+side,(1,0,0),-10*wave)
                    mov('torso',z=.006*(1-math.cos(phase*2)))
                if clip=='attack':
                    rot('torso',(1,0,0),4*wind-8*strike)
                    for side in ['L','R']:
                        rot('arm_'+side,(1,0,0),-20*wind+52*strike);rot('forearm_'+side,(1,0,0),14*strike)
                if clip=='hit':rot('torso',(1,0,0),8*math.sin(math.pi*t))
            bpy.context.view_layer.update()
            for pb in rig.pose.bones:
                pb.keyframe_insert('location',frame=frame,group=pb.name)
                pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name)
                pb.keyframe_insert('scale',frame=frame,group=pb.name)
        action['loop']=clip in ('idle','move')
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    scene.frame_start=1;scene.frame_end=49;scene.frame_set(1);bpy.context.view_layer.update()
    for folder in [BASE/'authoring',BASE/'exports',GAME,OUT/actor]:folder.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);obj.select_set(True);bpy.context.view_layer.objects.active=rig
    glb=BASE/'exports'/f'{actor}_v2.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_anim_slide_to_zero=True,export_force_sampling=True,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_optimize_animation_size=False)
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'authoring'/f'{actor}_v2.blend'))
    shutil.copy2(glb,GAME/glb.name)
    report={'id':actor,'source_sha256':src_hash,'source_triangles':source_tri,'source_part_count':12 if actor=='automaton' else 86,'rigid_parts':len(parts),'runtime_triangles':sum(len(p.vertices)-2 for p in obj.data.polygons),'bones':len(bone_specs),'max_influences':1,'clips':{c:{'frames':n,'seconds':(n-1)/24} for c,n in clips.items()},'parts':[{'bone':p['bone'],'source_part':p['source_part'],'parent':p['parent'],'center':list(p['center']),'triangles':p['triangles']} for p in parts],'sha256':sha(glb),'bytes':glb.stat().st_size,'raw_unchanged':sha(src)==src_hash,'destruction':'Baked separate rigid transforms, gravity, damped floor bounce; no inter-part collision solver.'}
    (OUT/actor/'build.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    # Actual mesh previews after the saved delivery is complete.
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard'
    scene.world=bpy.data.worlds.new('Preview');scene.world.color=(.05,.065,.08)
    for mat in obj.data.materials:
        if not mat.node_tree:continue
        bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        if not bs.inputs['Base Color'].is_linked:continue
        color=bs.inputs['Base Color'].links[0].from_socket;em=mat.node_tree.nodes.new('ShaderNodeEmission');output=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
        mat.node_tree.links.new(color,em.inputs['Color']);mat.node_tree.links.new(em.outputs[0],output.inputs['Surface'])
    camera=bpy.data.objects.new('PreviewCamera',bpy.data.cameras.new('PreviewCamera'));scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
    for clip,count in clips.items():
        action=bpy.data.actions[clip];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
        target=Vector((0,0,.35));camera.data.ortho_scale=5.2 if clip=='explode' else (1.9 if clip=='death' else 1.45)
        camera.location=target+Vector((2.4,4,2.4));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        for f in sorted(set([1,count//4+1,count//2+1,count*3//4+1,count])):
            scene.frame_set(f);scene.render.filepath=str(OUT/actor/f'{clip}_{f:03}.png');bpy.ops.render.render(write_still=True)
    print('SUMMON_V2_BUILT',actor,report['runtime_triangles'],len(parts),flush=True)

for actor in IDS:build(actor)
print('SUMMONS_V2_BUILD_COMPLETE',flush=True)
