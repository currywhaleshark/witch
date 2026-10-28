"""Rigid game derivatives of the preserved Tripo boss, stake and door sources.
Blender -b --factory-startup -t 4 -P tools/build_boss_trial_v1.py -- [latch stake door]
All motion is authored/baked here; it is not mocap or a live physics simulation.
"""
import bpy, math, json, sys, hashlib, shutil
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/boss_trial_v1'
OUT=ROOT/'reports/boss_trial_v1/build'
GAME=ROOT/'game/assets/actors/boss_trial_v1'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def smooth(a,b,t):
    x=max(0.,min(1.,(t-a)/(b-a)));return x*x*(3-2*x)
def bounds(o):
    vs=[v.co for v in o.data.vertices]
    return Vector(tuple(min(v[i] for v in vs) for i in range(3))),Vector(tuple(max(v[i] for v in vs) for i in range(3)))
def q(axis,angle):return Quaternion(Vector(axis),math.radians(angle))

def build(actor):
    H,budget,tex={'latch':(2.,28000,2048),'stake':(2.6,6500,1024),'door':(2.3,9000,1024)}[actor]
    src=BASE/'source'/f'{actor}_tripo_{"h31_raw" if actor=="stake" else "segmented"}.glb'
    raw_hash=sha(src)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    scene=bpy.context.scene;scene.render.fps=24
    meshes=[o for o in scene.objects if o.type=='MESH']
    vs=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    lo=Vector(tuple(min(v[i] for v in vs) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    origin=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));factor=H/(hi.z-lo.z)
    turn=Matrix.Rotation(math.pi,4,'Z')
    source_tri=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    for o in meshes:
        world=o.matrix_world.copy()
        for v in o.data.vertices:v.co=turn@((world@v.co-origin)*factor)
        o.parent=None;o.matrix_world=Matrix.Identity(4)
        if actor=='door':
            for v in o.data.vertices:v.co.y+=.151*H
        if actor=='stake':
            # Keep all rock fragments inside the existing 0.96m square collider footprint.
            for v in o.data.vertices:v.co.x*=.92;v.co.y*=.92
        bpy.context.view_layer.objects.active=o
        dec=o.modifiers.new('Runtime UV preserving reduction','DECIMATE')
        dec.ratio=min(1.,budget/source_tri);dec.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=dec.name)
        if actor=='stake':
            # Decimation shifts a few rubble points below the original floor. Restore
            # a zero base and the requested height on this derivative only.
            a,b=bounds(o)
            for v in o.data.vertices:v.co.z=(v.co.z-a.z)*H/(b.z-a.z)
        for p in o.data.polygons:p.use_smooth=True
    for im in bpy.data.images:
        if im.type=='IMAGE':
            if list(im.size)!=[tex,tex]:im.scale(tex,tex)
            im.name=actor+'_'+im.name.rsplit('_',1)[-1];im.pack()
    for mat in bpy.data.materials:
        mat.name=actor+'_PBR'
        bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        bs.inputs['Emission Strength'].default_value=0
    bone_specs={'root':(Vector((0,0,0)),None)}
    def bone(name,p,parent='root'):bone_specs[name]=(Vector(p)*H,parent)
    legs={}
    if actor=='latch':
        bone('torso',(0,.02,.47))
        bone('arm_chain',(.27,.08,.77),'torso');bone('forearm_chain',(.414,.12,.54),'arm_chain');bone('weapon_chain',(.49,.20,.37),'forearm_chain')
        bone('arm_lock',(-.27,.08,.77),'torso');bone('forearm_lock',(-.41,.12,.56),'arm_lock');bone('weapon_lock',(-.49,.22,.40),'forearm_lock')
        bone('core',(-.04,.10,.75),'torso')
        for front in [True,False]:
            for side,s in [('L',1),('R',-1)]:
                label=('front_' if front else 'rear_')+side
                h=Vector((s*.155,.14 if front else -.12,.46))*H
                k=Vector((s*.215,.27 if front else -.27,.28))*H
                a=Vector((s*.255,.33 if front else -.35,.105))*H
                legs[label]=(h,k,a)
                for n,p in [('thigh_',h),('shin_',k),('foot_',a)]:bone_specs[n+label]=(p,'root')
    elif actor=='door':bone('hinge',(-.235,.044,.49))
    parts=[]
    for o in sorted(meshes,key=lambda o:o.name):
        part=int(o.name.rsplit('_',1)[-1]) if actor!='stake' else 0
        if actor=='latch' and part==77:
            # A small presentation adjustment on the derivative: expose the flame through
            # the cage from the game's oblique view. The immutable source is untouched.
            for vertex in o.data.vertices:vertex.co.y+=.06*H
            core=o.data.materials[0].copy();core.name='latch_core'
            bs=next(n for n in core.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
            bs.inputs['Emission Color'].default_value=(.24,.75,1.,1.)
            bs.inputs['Emission Strength'].default_value=4.
            o.data.materials[0]=core
        low,high=bounds(o);center=(low+high)/2;v=center/H
        parent='root'
        if actor=='latch':
            if part==77:parent='core'
            elif abs(v.x)>.29 and v.z>.29:
                side='chain' if v.x>0 else 'lock'
                parent=('arm_' if v.z>.64 else 'forearm_' if v.z>.41 else 'weapon_')+side
                if part==5:parent='weapon_chain'
                if part==1:parent='weapon_lock'
            elif v.z<.42 or part in [4,6,27,45,32,73,89,90,93]:
                label=('front_' if v.y>0 else 'rear_')+('L' if v.x>0 else 'R')
                parent=('foot_' if v.z<.15 else 'shin_' if v.z<.285 else 'thigh_')+label
            else:parent='torso'
        elif actor=='door':
            # Labels are checked against the saved part bounds; all moving planks/hardware
            # lie in front of the jamb, including three horizontal hinge straps.
            if high.y/H>.13 and center.x/H<-.18 and center.z/H<.86:parent='hinge'
        name='part_%03d'%part
        bone_specs[name]=(center,parent)
        parts.append({'bone':name,'source_part':part,'parent':parent,'object':o,'center':center.copy(),
                      'offsets':np.array([tuple(v.co-center) for v in o.data.vertices]),'triangles':len(o.data.polygons)})
        o.name=name+'_mesh';o['source_part']=part;o['rigid_parent']=parent
    arm=bpy.data.armatures.new(actor+'_rigid_v1');rig=bpy.data.objects.new(actor+'_rigid_v1',arm);scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    for name,(p,parent) in bone_specs.items():
        b=arm.edit_bones.new(name);b.head=p;b.tail=p+Vector((0,.04*H,0))
        if parent:b.parent=arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in parts:
        o=p['object'];g=o.vertex_groups.new(name=p['bone']);g.add(list(range(len(o.data.vertices))),1.,'REPLACE');o.parent=rig
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    if len(meshes)>1:bpy.ops.object.join()
    obj=bpy.context.object;obj.name=actor+'_rigid_surface'
    mod=obj.modifiers.new('Rigid part skin','ARMATURE');mod.object=rig
    for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
    def rot(n,x=0,y=0,z=0):rig.pose.bones[n].rotation_quaternion=q((0,0,1),z)@q((0,1,0),y)@q((1,0,0),x)
    def set_world(n,p,rotation):rig.pose.bones[n].matrix=Matrix.Translation(p)@rotation.to_matrix().to_4x4()
    def leg_pose(label,target,drop=0.):
        rest_h,k,a=legs[label];h=rest_h-Vector((0,0,drop));d=target-h;length=d.length;direction=d.normalized()
        l1=(k-rest_h).length;l2=(a-k).length
        dist=min(length,l1+l2-.00001);along=(l1*l1-l2*l2+dist*dist)/(2*dist)
        pole=(k-h)-(a-h).normalized()*(k-h).dot((a-h).normalized())
        pole=(pole-direction*pole.dot(direction)).normalized()
        knee=h+direction*along+pole*math.sqrt(max(0,l1*l1-along*along))
        set_world('thigh_'+label,h,(k-rest_h).rotation_difference(knee-h))
        set_world('shin_'+label,knee,(a-k).rotation_difference(target-knee))
        set_world('foot_'+label,target,Quaternion())
    trajectories=[]
    if actor=='latch':
        states=[]
        for i,p in enumerate(parts):
            angle=i*2.399963;direction=Vector((math.cos(angle),math.sin(angle),0))
            states.append({'pos':p['center'].copy(),'v':direction*(.12+.04*(i%6)), 'q':Quaternion(),
                'axis':Vector((math.sin(i+.4),math.cos(i*1.3),.3)).normalized(),'spin':1.4+(i%7)*.32})
        for step in range(241):
            if step%5==0:trajectories.append([(s['pos'].copy(),s['q'].copy()) for s in states])
            dt=1/120
            for p,s in zip(parts,states):
                s['v'].z-=6.5*dt;s['pos']+=s['v']*dt;s['q']=(Quaternion(s['axis'],s['spin']*dt)@s['q']).normalized()
                row=np.array(s['q'].to_matrix())[2,:];floor=-float(np.min(p['offsets']@row))+.002
                if s['pos'].z<floor:
                    s['pos'].z=floor;s['v'].z=max(0,-s['v'].z*.14) if s['v'].z<-.3 else 0
                    s['v'].x*=math.exp(-10*dt);s['v'].y*=math.exp(-10*dt);s['spin']*=math.exp(-12*dt)
    clips={'idle':49,'move':25,'sweep':49,'slam':49,'frames':49,'shockwave':49,'hit':13,'death':49} if actor=='latch' else {'idle':49,'open':25,'close':25} if actor=='door' else {'idle':49}
    rig.animation_data_create();samples={};minimums={};max_rigid_error=0.
    # One measurable triangle per part is independently evaluated after armature deformation.
    probes=[]
    for p in parts:
        gi=obj.vertex_groups[p['bone']].index
        poly=next(poly for poly in obj.data.polygons if all(any(g.group==gi for g in obj.data.vertices[v].groups) for v in poly.vertices))
        ids=list(poly.vertices)[:3];lengths=[(obj.data.vertices[ids[j]].co-obj.data.vertices[ids[(j+1)%3]].co).length for j in range(3)]
        probes.append((ids,lengths))
    for clip,count in clips.items():
        act=bpy.data.actions.new(clip);act.use_fake_user=True;rig.animation_data.action=act;samples[clip]=[];minimums[clip]=[]
        for f in range(1,count+1):
            scene.frame_set(f);t=(f-1)/(count-1);phase=math.tau*t
            for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
            wind=smooth(0,.30,t)*(1-smooth(.32,.5,t));strike=smooth(.32,.5,t)*(1-smooth(.55,1,t))
            if actor=='latch':
                if clip=='death':
                    bpy.context.view_layer.update()
                    for p,(pos,r) in zip(parts,trajectories[f-1]):set_world(p['bone'],pos,r)
                else:
                    for i,(label,(h,k,a)) in enumerate(legs.items()):
                        target=a.copy()
                        if clip=='move':
                            ph=phase+(math.pi if i in [1,2] else 0);target.y+=.10*H*math.cos(ph);target.z+=.055*H*max(0,math.sin(ph))
                        drop=H*strike*(.08 if clip=='slam' else .06 if clip=='shockwave' else 0.)
                        leg_pose(label,target,drop)
                    rig.pose.bones['torso'].location.z=-drop
                    if clip=='idle':
                        rot('torso',z=1.2*math.sin(phase));rot('forearm_chain',x=1.5*math.sin(phase+.5));rot('weapon_lock',x=2*math.sin(phase))
                    elif clip=='move':
                        rot('torso',z=2.2*math.sin(phase));rot('arm_chain',x=5*math.sin(phase));rot('arm_lock',x=-4*math.sin(phase))
                    elif clip=='sweep':
                        rot('torso',z=-14*wind+18*strike)
                        rot('arm_chain',y=-65*(wind+strike),z=-45*wind+80*strike)
                        rot('forearm_chain',y=-25*(wind+strike),z=15*strike);rot('weapon_chain',z=-20*strike)
                        rot('arm_lock',x=12*wind+8*strike)
                    elif clip=='slam':
                        rot('torso',x=7*wind-24*strike)
                        rot('arm_lock',x=145*wind+24*strike,y=-12*wind)
                        rot('forearm_lock',x=20*wind-8*strike);rot('weapon_lock',x=-12*wind-7*strike)
                        rot('arm_chain',x=18*wind-8*strike,y=-16*wind)
                    elif clip=='frames':
                        rot('torso',x=-5*wind)
                        rot('arm_chain',x=58*(wind+strike),y=-25*(wind+strike));rot('arm_lock',x=65*(wind+strike),y=20*(wind+strike))
                        rot('forearm_chain',x=-20*strike);rot('forearm_lock',x=-20*strike)
                    elif clip=='shockwave':
                        rot('torso',x=8*wind-20*strike)
                        rot('arm_lock',x=135*wind+22*strike);rot('arm_chain',x=110*wind+24*strike)
                        rot('forearm_lock',x=10*wind-12*strike);rot('forearm_chain',x=20*wind-10*strike)
                    elif clip=='hit':rot('torso',x=-7*math.sin(math.pi*t),z=3*math.sin(math.pi*t))
            elif actor=='door':
                angle=-90*(1-smooth(0,1,t)) if clip=='open' else -90*smooth(0,1,t) if clip=='close' else 0
                rot('hinge',z=angle)
            bpy.context.view_layer.update()
            for pb in rig.pose.bones:
                pb.keyframe_insert('location',frame=f,group=pb.name);pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name);pb.keyframe_insert('scale',frame=f,group=pb.name)
            deps=bpy.context.evaluated_depsgraph_get();ev=obj.evaluated_get(deps);em=ev.to_mesh()
            minimums[clip].append(min(v.co.z for v in em.vertices))
            for ids,lengths in probes:
                for j,length in enumerate(lengths):max_rigid_error=max(max_rigid_error,abs((em.vertices[ids[j]].co-em.vertices[ids[(j+1)%3]].co).length-length))
            if f in [1,(count+1)//2,count]:
                samples[clip].append({'phase':t,'bones':{pb.name:[list(r) for r in pb.matrix] for pb in rig.pose.bones}})
            ev.to_mesh_clear()
        act['loop']=clip in ['idle','move'];act['impact_fraction']=.5 if clip in ['sweep','slam','frames','shockwave'] else -1
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    scene.frame_start=1;scene.frame_end=49;scene.frame_set(1);bpy.context.view_layer.update()
    for d in [BASE/'authoring',BASE/'exports',GAME,OUT/actor]:d.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);obj.select_set(True);bpy.context.view_layer.objects.active=rig
    glb=BASE/'exports'/f'{actor}_v1.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_anim_slide_to_zero=True,export_force_sampling=True,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_optimize_animation_size=False)
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'authoring'/f'{actor}_v1.blend'));shutil.copy2(glb,GAME/glb.name)
    report={'id':actor,'source':str(src.relative_to(ROOT)),'source_sha256':raw_hash,'raw_unchanged':sha(src)==raw_hash,'source_triangles':source_tri,'runtime_triangles':sum(len(p.vertices)-2 for p in obj.data.polygons),'vertices':len(obj.data.vertices),'bones':len(bone_specs),'rigid_parts':len(parts),'max_influences':1,'texture_size':tex,'materials':len(obj.data.materials),'height_m':H,'front':'Godot -Z','glb_sha256':sha(glb),'clips':{c:{'frames':n,'seconds':(n-1)/24} for c,n in clips.items()},'sampled_rigid_edge_error_m':max_rigid_error,'ground_min_z':{c:[min(v),max(v)] for c,v in minimums.items()},'parts':[{'bone':p['bone'],'source_part':p['source_part'],'parent':p['parent'],'triangles':p['triangles']} for p in parts]}
    (OUT/actor/'build.json').write_text(json.dumps(report,indent=2),encoding='utf-8');(OUT/actor/'pose_samples.json').write_text(json.dumps(samples),encoding='utf-8')
    assert max_rigid_error<.00002 and report['raw_unchanged']
    # Preview after saving; base colour emission is only a diagnostic display material.
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard'
    scene.world=bpy.data.worlds.new('Review');scene.world.color=(.045,.055,.07)
    for mat in obj.data.materials:
        bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');color=bs.inputs['Base Color'].links[0].from_socket
        em=mat.node_tree.nodes.new('ShaderNodeEmission');out=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL');mat.node_tree.links.new(color,em.inputs['Color']);mat.node_tree.links.new(em.outputs[0],out.inputs['Surface'])
    cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=H*(1.7 if actor=='latch' else 1.25)
    target=Vector((0,0,H*.5))
    for clip in clips:
        rig.animation_data.action=bpy.data.actions[clip]
        for label,f in [('start',1),('impact',(clips[clip]+1)//2),('end',clips[clip])]:
            scene.frame_set(f);cam.location=target+Vector((1.1,3,1.0))*H;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(OUT/actor/f'{clip}_{label}.png');bpy.ops.render.render(write_still=True)
    print('BOSS_BUILD_COMPLETE',actor,json.dumps({k:v for k,v in report.items() if k!='parts'}))

for actor in (sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['latch','stake','door']):build(actor)
