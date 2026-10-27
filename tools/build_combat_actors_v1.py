"""Create reproducible game derivatives of the five preserved Tripo sources.

Blender 5.1: -b --factory-startup -t 4 -P tools/build_combat_actors_v1.py -- [ids...]
The authored short clips are prototype motions, not captured/retargeted animation.
"""
import bpy, math, json, sys, hashlib, shutil, heapq
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
from mathutils.kdtree import KDTree

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/combat_set_v1'
REPORT=ROOT/'reports/combat_actors_v1'
GAME=ROOT/'game/assets/actors/combat_set_v1'
SPEC=json.loads((BASE/'production.json').read_text(encoding='utf-8-sig'))
IDS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
TAU=math.tau

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)))
    return t*t*(3-2*t)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def run(spec):
    actor=spec['id']; H=spec['base_height_m']; budget=spec['target_triangles']
    out=REPORT/'build'/actor; out.mkdir(parents=True,exist_ok=True)
    GAME.mkdir(parents=True,exist_ok=True)
    work=BASE/'authoring'; work.mkdir(exist_ok=True)
    src=BASE/'source'/f'{actor}_tripo_h31_raw.glb'
    raw_hash=sha(src)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    scene=bpy.context.scene; scene.render.fps=24
    meshes=[o for o in scene.objects if o.type=='MESH']
    coords=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    low=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    high=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    source_tri=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    # Tripo humanoids and crow face -Y; the cannon actually faces -X.
    # Authoring +Y becomes glTF/Godot -Z.
    turn=Matrix.Rotation(-math.pi/2 if actor=='turret' else math.pi,4,'Z')
    origin=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
    scale=H/(high.z-low.z)
    for o in meshes:
        world=o.matrix_world.copy()
        for v in o.data.vertices: v.co=turn@((world@v.co-origin)*scale)
        o.parent=None; o.matrix_world=Matrix.Identity(4)
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    if len(meshes)>1:bpy.ops.object.join()
    obj=bpy.context.object; obj.name=f'{actor}_surface'
    # Keep all original UV islands, colours and PBR maps on the derivative.
    dec=obj.modifiers.new('Runtime reduction','DECIMATE')
    dec.ratio=min(1,budget/source_tri)
    dec.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=dec.name)
    for p in obj.data.polygons:p.use_smooth=True
    textures=[]
    for im in list(bpy.data.images):
        if im.type!='IMAGE':continue
        old_name=im.name
        im.scale(1024,1024)
        im.name=f'{actor}_{old_name.split("_raw_")[-1].rsplit(".",1)[0]}_1k'
        im.pack()
        textures.append({'name':im.name,'size':list(im.size)})
    for m in obj.data.materials:
        m.name=f'{actor}_aged_surface'
        bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        # Preserve generated maps; avoid a mirror-like metal response under arena lighting.
        if not bs.inputs['Roughness'].is_linked:bs.inputs['Roughness'].default_value=.7
    bones={}
    def bone(name,p,parent=None): bones[name]={'head':Vector(p)*H,'parent':parent}
    bone('root',(0,0,0))
    if actor=='turret':
        bone('carriage',(0,0,.43),'root')
        bone('barrel',(0,.15,.64),'carriage')
        bone('key',(0,-.42,.65),'carriage')
        bone('muzzle',(0,.61,.64),'barrel')
    elif actor=='crow':
        bone('torso',(0,0,.43),'root')
        bone('head',(0,.06,.68),'torso')
        bone('tail',(0,-.22,.33),'torso')
        for side,s in [('L',1),('R',-1)]:
            bone('wing_'+side,(s*.20,0,.53),'torso')
            bone('tip_'+side,(s*.57,0,.60),'wing_'+side)
            bone('leg_'+side,(s*.13,0,.23),'torso')
        bone('muzzle',(0,.31,.73),'head')
    else:
        dims={
            'rag':(.35,.60,.68,.27,.40,.46,.14,.19,.17,.075),
            'brute':(.40,.64,.77,.30,.46,.49,.16,.22,.18,.075),
            'automaton':(.30,.49,.65,.25,.36,.46,.15,.20,.14,.065),
        }[actor]
        hip,torso,neck,shoulder,elbow,ez,legx,kneex,kz,az=dims
        bone('torso',(0,0,torso),'root')
        bone('head',(0,.02,neck),'torso')
        for side,s in [('L',1),('R',-1)]:
            bone('arm_'+side,(s*shoulder,0,torso),'torso')
            bone('forearm_'+side,(s*elbow,.015,ez),'arm_'+side)
            bone('thigh_'+side,(s*legx,0,hip),'root')
            bone('shin_'+side,(s*kneex,.018,kz),'thigh_'+side)
            bone('foot_'+side,(s*kneex,.02,az),'shin_'+side)
        if actor=='automaton':bone('key',(0,-.16,.67),'torso')
        bone('muzzle',(.38,.12,.33),'forearm_L')
    rigdata=bpy.data.armatures.new(f'{actor}_rig')
    rig=bpy.data.objects.new(f'{actor}_rig',rigdata)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for name,b in bones.items():
        e=rigdata.edit_bones.new(name);e.head=b['head'];e.tail=e.head+Vector((0,0,.07*H))
        if b['parent']:e.parent=rigdata.edit_bones[b['parent']]
    bpy.ops.object.mode_set(mode='OBJECT')
    groups={n:obj.vertex_groups.new(name=n) for n in bones}
    arm_share=None
    if actor in ('rag','brute','automaton'):
        # Geodesic distances follow the actual surface, rather than confusing a
        # hanging hand/shield with the nearby leg. UV splits are welded only in
        # this calculation graph; the exported topology/UVs are untouched.
        import numpy as np
        positions=np.array([v.co[: ] for v in obj.data.vertices])/H
        _,first,ids=np.unique(np.round(positions,4),axis=0,return_index=True,return_inverse=True)
        pts=positions[first];adj=[[] for _ in pts]
        for e in obj.data.edges:
            i,j=[int(ids[v]) for v in e.vertices]
            if i==j:continue
            length=float(np.linalg.norm(pts[i]-pts[j]));adj[i].append((j,length));adj[j].append((i,length))
        a=np.abs(pts[:,0]);z=pts[:,2]
        arm_seed=(a>(.35 if actor=='automaton' else .42))&(z>.27)&(z<.49)
        body_seed=((a<.13)&(z>.30)&(z<.85))|((a<.28)&(z<.08))
        if actor=='rag':
            arm_seed=(a>.32)&(z<.49)
            body_seed|=(a<.26)&(z<.27)
        elif actor=='automaton':
            arm_seed=(a>.32)&(z>.26)&(z<.55)
            body_seed|=(a<.29)&(z<.27)
        def distances(seed):
            selected=np.where(seed)[0];assert len(selected)
            dist=np.full(len(pts),np.inf);heap=[]
            for i in selected:dist[i]=0;heapq.heappush(heap,(0,int(i)))
            while heap:
                d,i=heapq.heappop(heap)
                if d>dist[i]:continue
                for j,w in adj[i]:
                    if d+w<dist[j]:dist[j]=d+w;heapq.heappush(heap,(d+w,j))
            # Tiny disconnected trim components use nearest observed seed points.
            tree=KDTree(len(selected))
            for k,i in enumerate(selected):tree.insert(Vector(pts[i]),k)
            tree.balance()
            nearest=np.array([tree.find(Vector(p))[2] for p in pts])
            return dist,nearest
        arm_dist,arm_near=distances(arm_seed);body_dist,body_near=distances(body_seed)
        shares=np.zeros(len(pts));unvisited=set(range(len(pts)))
        while unvisited:
            start=unvisited.pop();component=[start];stack=[start]
            while stack:
                for j,_ in adj[stack.pop()]:
                    if j in unvisited:unvisited.remove(j);component.append(j);stack.append(j)
            has_arm=any(arm_seed[i] for i in component);has_body=any(body_seed[i] for i in component)
            if has_arm and has_body:
                for i in component:shares[i]=smooth(-.045,.045,float(body_dist[i]-arm_dist[i]))
            else:
                share=1. if has_arm else 0. if has_body else float(np.median(arm_near[component])<np.median(body_near[component]))
                shares[component]=share
        arm_share=shares[ids]
    counts={n:0 for n in bones};max_weights=0
    def add(w,n,value):
        if value>1e-5:w[n]=w.get(n,0)+value
    for v in obj.data.vertices:
        x,y,z=v.co/H; a=abs(x); side='L' if x>=0 else 'R'; w={}
        if actor=='turret':
            upper=smooth(.39,.45,z)
            barrel=upper*smooth(.16,.22,y)*(1-smooth(.19,.24,a))
            key=upper*(1-smooth(-.45,-.39,y))
            add(w,'root',1-upper);add(w,'barrel',barrel);add(w,'key',key)
            add(w,'carriage',upper-barrel-key)
        elif actor=='crow':
            wing=smooth(.18,.26,a)*smooth(.32,.43,z)
            tip=smooth(.53,.62,a)
            add(w,'wing_'+side,wing*(1-tip));add(w,'tip_'+side,wing*tip)
            rem=1-wing
            tail=(1-smooth(-.30,-.20,y))*(1-smooth(.48,.57,z))
            leg=1-smooth(.20,.28,z)
            head=smooth(.64,.73,z)
            add(w,'tail',rem*tail);rem*=1-tail
            add(w,'leg_'+side,rem*leg);rem*=1-leg
            add(w,'head',rem*head);add(w,'torso',rem*(1-head))
        else:
            hip,torso,neck,shoulder,elbow,ez,legx,kneex,kz,az=dims
            # Long hanging hands/door shields stay attached to the arm even below the hips.
            # A height-only cutoff incorrectly assigns their tips to the legs.
            arm=float(arm_share[v.index])
            elbow_blend=1-smooth(ez-.04,ez+.045,z)
            if actor=='automaton':arm*=1-smooth(.63,.68,z)
            if actor=='brute':
                # Keep the entire rigid door on the forearm; blend only at the upper hinge.
                elbow_blend=1-smooth(.56,.61,z)
            add(w,'arm_'+side,arm*(1-elbow_blend));add(w,'forearm_'+side,arm*elbow_blend)
            rem=1-arm
            leg=1-smooth(hip-.035,hip+.04,z)
            ankle=1-smooth(az+.015,az+.065,z)
            knee=1-smooth(kz-.025,kz+.035,z)
            add(w,'foot_'+side,rem*leg*ankle)
            add(w,'shin_'+side,rem*leg*(1-ankle)*knee)
            add(w,'thigh_'+side,rem*leg*(1-ankle)*(1-knee))
            rem*=1-leg
            key=smooth(.67,.72,z)*(1-smooth(-.13,-.09,y)) if actor=='automaton' else 0
            add(w,'key',rem*key);rem*=1-key
            head=smooth(neck-.025,neck+.025,z)
            add(w,'head',rem*head);add(w,'torso',rem*(1-head))
        # Four largest influences, explicitly normalized and reported.
        w=dict(sorted(w.items(),key=lambda p:p[1],reverse=True)[:4]);total=sum(w.values())
        assert total>0
        for name,value in w.items():groups[name].add([v.index],value/total,'REPLACE');counts[name]+=1
        max_weights=max(max_weights,len(w))
    obj.parent=rig
    arm=obj.modifiers.new('ActorSkin','ARMATURE');arm.object=rig;arm.use_deform_preserve_volume=False
    for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
    restq={b.name:b.matrix_local.to_quaternion() for b in rig.data.bones}
    def rot(name,x=0,y=0,z=0):
        q=Quaternion((0,0,1),math.radians(z))@Quaternion((0,1,0),math.radians(y))@Quaternion((1,0,0),math.radians(x))
        rig.pose.bones[name].rotation_quaternion=restq[name].inverted()@q@restq[name]
    def move(name,x=0,y=0,z=0):rig.pose.bones[name].location=restq[name].inverted()@Vector((x,y,z))*H
    def limb(side,phase,stride,lift):
        n=['thigh_'+side,'shin_'+side,'foot_'+side]
        p,k,f=[bones[b]['head'] for b in n]
        target=f+Vector((0,math.sin(phase)*stride,max(0,math.cos(phase))*lift))*H
        upper=(k-p).length;lower=(f-k).length;delta=target-p
        dist=min(delta.length,upper+lower-.00001);axis=delta.normalized()
        along=(upper*upper-lower*lower+dist*dist)/(2*dist)
        pole=Vector((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized()
        knee=p+axis*along+pole*math.sqrt(max(0,upper*upper-along*along))
        endpoint=p+axis*dist
        qu=(k-p).rotation_difference(knee-p)
        ql=(f-k).rotation_difference(endpoint-knee)
        for name,q in [(n[0],qu),(n[1],qu.inverted()@ql),(n[2],ql.inverted())]:
            rig.pose.bones[name].rotation_quaternion=restq[name].inverted()@q@restq[name]
    clips={'idle':49,'move':33 if actor=='brute' else 25,'attack':25,'hit':13,'death':31}
    if actor=='brute':clips['charge']=25
    if actor=='turret':clips.pop('move')
    rig.animation_data_create();minimums={};pose_samples={}
    for clip,count in clips.items():
        action=bpy.data.actions.new(clip);action.use_fake_user=True
        rig.animation_data.action=action;scene.frame_start=1;scene.frame_end=count
        minimums[clip]=[];pose_samples[clip]=[]
        for frame in range(1,count+1):
            scene.frame_set(frame);t=(frame-1)/(count-1);phase=t*TAU
            for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
            attack=math.sin(math.pi*smooth(0,.5,t)) if t<.5 else 1-smooth(.5,1,t)
            # Wind up slowly, snap forward at the common release fraction 0.5, recover.
            wind=smooth(0,.33,t)*(1-smooth(.36,.5,t))
            strike=smooth(.35,.5,t)*(1-smooth(.58,1,t))
            hit=math.sin(math.pi*t)
            if actor=='crow':
                flap=math.sin(phase*(2 if clip=='idle' else 3))
                if clip in ('attack','hit','death'):flap=math.sin(phase*2)
                move('root',z=.35+.025*math.sin(phase*2))
                for side,s in [('L',1),('R',-1)]:
                    rot('wing_'+side,y=-s*(24 if clip=='idle' else 36)*flap)
                    rot('tip_'+side,y=-s*12*math.sin(phase*2-.4))
                rot('tail',x=5*math.sin(phase));rot('head',z=4*math.sin(phase))
                if clip=='attack':rot('head',x=12*wind-28*strike);rot('torso',x=8*wind-10*strike)
                if clip=='hit':rot('torso',x=18*hit,z=12*hit)
            elif actor=='turret':
                if clip=='idle':rot('carriage',z=4*math.sin(phase));rot('key',y=8*math.sin(phase))
                if clip=='attack':move('barrel',y=-.06*strike);rot('carriage',x=3*strike);rot('key',y=35*strike)
                if clip=='hit':rot('carriage',x=-7*hit,z=4*hit)
            else:
                rot('torso',z=1.6*math.sin(phase));rot('head',z=-1.2*math.sin(phase))
                if actor=='automaton':rot('key',z=12*math.sin(phase))
                if clip in ('move','charge'):
                    stride=.065 if actor=='brute' else .09
                    for side,s in [('L',1),('R',-1)]:
                        limb(side,phase+(math.pi if s<0 else 0),stride,.045)
                        rot('arm_'+side,x=s*12*math.sin(phase))
                        rot('forearm_'+side,x=-5*max(0,s*math.sin(phase)))
                    rot('torso',z=3*math.sin(phase));rot('head',z=-2*math.sin(phase))
                    if clip=='charge':
                        rot('torso',x=-12)
                        for side in ['L','R']:rot('arm_'+side,x=48);rot('forearm_'+side,x=28)
                if clip=='attack':
                    rot('torso',x=5*wind-12*strike,z=6*wind-8*strike)
                    for side,s in [('L',1),('R',-1)]:
                        if actor=='brute':rot('arm_'+side,x=-42*wind+68*strike);rot('forearm_'+side,x=22*wind+25*strike)
                        elif actor=='automaton':rot('arm_'+side,x=-24*wind+62*strike,y=s*5*strike);rot('forearm_'+side,x=14*strike)
                        else:rot('arm_'+side,x=-18*wind+58*strike,y=s*8*wind);rot('forearm_'+side,x=15*strike)
                if clip=='hit':rot('torso',x=12*hit,z=7*hit);rot('head',x=5*hit)
            if clip=='death':
                collapse=smooth(.08,.88,t)
                rot('root',x=-86*collapse,z=8*collapse)
                if 'torso' in bones:rot('torso',x=-12*collapse)
                if actor=='turret':rot('carriage',x=-32*collapse)
                move('root',z=.35*(1-collapse) if actor=='crow' else 0)
            bpy.context.view_layer.update()
            # Keep the lowest visible vertex at ground for terrestrial clips and a settled corpse.
            if actor!='crow' or clip=='death':
                evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
                minimum=min(v.co.z for v in evaluated.data.vertices)
                current=restq['root']@rig.pose.bones['root'].location
                current.z-=min(0,minimum) if actor=='crow' else minimum
                rig.pose.bones['root'].location=restq['root'].inverted()@current
            bpy.context.view_layer.update()
            for pb in rig.pose.bones:
                pb.keyframe_insert('location',frame=frame,group=pb.name)
                pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name)
                pb.keyframe_insert('scale',frame=frame,group=pb.name)
            ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            minimums[clip].append(min(v.co.z for v in ev.data.vertices))
            if frame in (1,count//2+1,count):
                pose_samples[clip].append({'frame':frame,'bones':{pb.name:[list(row) for row in pb.matrix] for pb in rig.pose.bones}})
        action['loop']=clip in ('idle','move','charge');action['release_fraction']=.5 if clip=='attack' else -1
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    scene.frame_start=1;scene.frame_end=49;scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    glb=BASE/'exports'/f'{actor}_v1.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
        export_force_sampling=True,export_skins=True,export_def_bones=False,
        export_apply=False,export_extras=True,export_optimize_animation_size=False)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(work/f'{actor}_v1.blend'))
    shutil.copy2(glb,GAME/glb.name)
    info={'id':actor,'source_sha256':raw_hash,'source_triangles':source_tri,
          'runtime_triangles':sum(len(p.vertices)-2 for p in obj.data.polygons),
          'vertices':len(obj.data.vertices),'height_m':H,'front':'-Z in Godot',
          'bones':len(bones),'weighted_vertex_counts':counts,'max_influences':max_weights,
          'textures':textures,'clips':{n:{'frames':c,'seconds':(c-1)/24,'loop':n in ('idle','move','charge')} for n,c in clips.items()},
          'ground_min_z':{n:[min(v),max(v)] for n,v in minimums.items()},
          'glb_sha256':sha(glb),'glb_bytes':glb.stat().st_size,
          'limitations':['Prototype authored animation; no motion-capture source.',
            'UV-preserving decimation and region weights; not manually rebuilt deformation topology.',
            'Generated fused surfaces can compress at large joint angles; only the delivered clips are reviewed.']}
    (out/'build.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
    (out/'pose_samples.json').write_text(json.dumps(pose_samples),encoding='utf-8')
    assert sha(src)==raw_hash
    # Render the actual reduced, skinned mesh. Review materials do not alter the saved deliverable.
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=480;scene.render.resolution_y=480;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard'
    world=bpy.data.worlds.new('Review');world.use_nodes=True;scene.world=world
    world.node_tree.nodes.get('Background').inputs[0].default_value=(.055,.065,.08,1)
    for m in obj.data.materials:
        bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        tex=bs.inputs['Base Color'].links[0].from_socket
        em=m.node_tree.nodes.new('ShaderNodeEmission');output=next(n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
        m.node_tree.links.new(tex,em.inputs['Color']);m.node_tree.links.new(em.outputs[0],output.inputs['Surface'])
    camdata=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',camdata);scene.collection.objects.link(cam);scene.camera=cam
    camdata.type='ORTHO';camdata.ortho_scale=H*(2.35 if actor=='crow' else 1.65)
    target=Vector((0,0,H*(.72 if actor=='crow' else .5)))
    cam.location=target+Vector((2.3,4,1.4))*H;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    for clip,count in clips.items():
        action=bpy.data.actions[clip];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
        for f in sorted(set([1,count//4+1,count//2+1,count*3//4+1,count])):
            scene.frame_set(f);scene.render.filepath=str(out/f'{clip}_{f:03}.png');bpy.ops.render.render(write_still=True)
    print('COMBAT_ACTOR_BUILT',actor,json.dumps(info),flush=True)

for spec in SPEC['assets']:
    if not IDS or spec['id'] in IDS:run(spec)
print('COMBAT_ACTORS_BUILD_COMPLETE',flush=True)
