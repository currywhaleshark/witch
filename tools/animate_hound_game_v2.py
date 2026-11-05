"""Rigid hound rig and six sampled clips; no game-rule changes."""
import bpy, json, math, sys, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2';OUT=ROOT/'reports/hound_game_v2'
sys.path.insert(0,str(ROOT/'tools'))
bpy.ops.wm.open_mainfile(filepath=str(BASE/'hound_geometry.blend'))
sc=bpy.context.scene;sc.render.fps=24
sc.name='Mechanical_Hound_Game_v2'
for key in list(sc.keys()):del sc[key]
sc['stage']='Optimized rigid hound art candidate; prepared asset, not gameplay integration'
mesh=bpy.data.objects['Hound_Rigid_Surface'];geo=json.loads((BASE/'geometry.json').read_text(encoding='utf8'))
FIT=Matrix(geo['static_fit_matrix']);NP=Vector((-.274,0,.361));NT=Matrix.Translation(NP)@Matrix.Rotation(math.radians(-7),4,'Y')@Matrix.Translation(-NP)
def pt(p,neck=False):return FIT@(NT@Vector(p) if neck else Vector(p))
def smooth(a,b,x):
    x=min(1,max(0,(x-a)/(b-a)));return x*x*(3-2*x)
def about(p,axis,angle):return Matrix.Translation(p)@Matrix.Rotation(angle,4,axis)@Matrix.Translation(-p)
I=Matrix.Identity(4)
spec={
 'root':(Vector((0,0,0)),None),'chest':(pt((-.15,0,.36)),'root'),'pelvis':(pt((.155,0,.35)),'chest'),
 'neck':(pt((-.274,0,.361)),'chest'),'head':(pt((-.337,0,.514),True),'neck'),
 'jaw':(pt((-.342,0,.505),True),'head'),'key':(pt((-.096,0,.451)),'chest'),
 'tail_01':(pt((.232,0,.366)),'pelvis'),'tail_02':(pt((.397,0,.385)),'tail_01'),
 'core':(Vector(geo['core']),'head'),'core_glow':(Vector(geo['core']),'head'),'tail_glow':(Vector(geo['tail_tip']),'tail_02')}
joints={k:[Vector(p) for p in ps] for k,ps in geo['joints'].items()}
for stem,js in joints.items():
    limb,side=stem.split('.');parent='chest' if limb=='fore' else 'pelvis'
    labels=['upper','lower','paw'] if limb=='fore' else ['upper','lower','hock','paw']
    for label,p in zip(labels,js):
        name=limb+'_'+label+'.'+side;spec[name]=(p,parent);parent=name
for ps in geo['pistons'].values():
    spec[ps['case']]=(Vector(ps['a']),ps['a_bone']);spec[ps['rod']]=(Vector(ps['b']),ps['b_bone'])
spec['Socket_attack']=(pt((-.492,0,.485),True),'head')
spec['Socket_core']=(Vector(geo['core']),'head')
spec['Socket_bar']=(Vector((0,.01,.80)),'root')
data=bpy.data.armatures.new('Hound_Rigid_Rig');rig=bpy.data.objects.new('Hound_Rigid_Rig',data);sc.collection.objects.link(rig)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for name,(p,parent) in spec.items():
    b=data.edit_bones.new(name);b.head=p;b.tail=p+Vector((0,.04,0))
    if parent:b.parent=data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
mesh.parent=rig;mod=mesh.modifiers.new('Single bone rigid parts','ARMATURE');mod.object=rig
for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
rig.animation_data_create()
rests={b.name:b.matrix_local.copy() for b in data.bones}
rest_local={n:(rests[spec[n][1]].inverted()@m if spec[n][1] else m) for n,m in rests.items()}
part_names=[g.name for g in mesh.vertex_groups]
part_points={n:[] for n in part_names}
for v in mesh.data.vertices:part_points[mesh.vertex_groups[v.groups[0].group].name].append(v.co.copy())
centers={n:sum(vs,Vector())/len(vs) for n,vs in part_points.items()}
sole={n:min(p.z for p in vs) for n,vs in part_points.items() if '_paw.' in n}
metrics={'ik_clamps':0,'maximum_unreachable_m':0.,'pistons':{k:{'min':1e6,'max':0} for k in geo['pistons']}}

def ik(a,c,l1,l2,pole):
    v=c-a;raw=v.length;d=min(l1+l2-.0001,max(abs(l1-l2)+.0001,raw))
    if raw>d+.00001:
        metrics['ik_clamps']+=1;metrics['maximum_unreachable_m']=max(metrics['maximum_unreachable_m'],raw-d)
    direction=v.normalized();c=a+direction*d
    x=(l1*l1-l2*l2+d*d)/(2*d);h=math.sqrt(max(0,l1*l1-x*x))
    bend=Vector(pole)-direction*Vector(pole).dot(direction)
    return a+direction*x+bend.normalized()*h,c
def segment(a,b,aa,bb):
    q=(b-a).rotation_difference(bb-aa)
    return Matrix.Translation(aa)@q.to_matrix().to_4x4()@Matrix.Translation(-a)

def pose(clip,t):
    duration={'spawn':.4,'idle':1.,'run':.5,'bite':.6,'hit':.25,'death':1.2}[clip]
    u=t/duration;wave=math.tau*u
    z=-.006+.003*math.sin(wave);pitch=math.radians(.7)*math.sin(wave)
    forward=0.;crouch=0.;jaw=math.radians(10);head=-.01*math.sin(wave);foot_shift={}
    if clip=='spawn':
        crouch=.125*(1-smooth(0,.83,u));z=0.;pitch=math.radians(5)*(1-smooth(0,.85,u))
    elif clip=='run':
        z=-.081+.012*math.sin(wave*2-.6);pitch=math.radians(2.0)*math.sin(wave)
        head=-pitch*.6;jaw=math.radians(6+3*math.sin(wave))
    elif clip=='bite':
        wind=smooth(0,.32,u)*(1-smooth(.32,.5,u));strike=smooth(.30,.50,u)*(1-smooth(.57,1,u))
        crouch=.075*wind+.080*strike;forward=.065*strike;z=-.006;pitch=math.radians(6)*wind-math.radians(5)*strike
        head=math.radians(8)*wind-math.radians(7)*strike
        jaw=math.radians(10-31*wind+4*strike)
    elif clip=='hit':
        w=math.sin(math.pi*u);pitch=math.radians(-7)*w;forward=-.025*w;crouch=.065*w;z=-.006;head=math.radians(5)*w
    elif clip=='death':z=0;pitch=0
    body=Matrix.Translation((0,forward,z-crouch))@about(spec['chest'][0],'X',pitch)
    d={'root':I.copy(),'chest':body,'pelvis':body.copy()}
    d['neck']=body@about(spec['neck'][0],'X',head*.45)
    d['head']=d['neck']@about(spec['head'][0],'X',head)
    d['jaw']=d['head']@about(spec['jaw'][0],'X',jaw)
    # A full shaft turn has an identical first/last transform.
    keyangle=wave if clip=='idle' else (wave*2 if clip=='run' else .35*math.sin(wave))
    d['key']=body@about(spec['key'][0],'Z',keyangle)
    d['tail_01']=d['pelvis']@about(spec['tail_01'][0],'Z',math.radians(8)*math.sin(wave-.3))
    d['tail_02']=d['tail_01']@about(spec['tail_02'][0],'Z',math.radians(13)*math.sin(wave-1.0))
    for n,parent in [('core','head'),('core_glow','head'),('tail_glow','tail_02'),('Socket_attack','head'),('Socket_core','head'),('Socket_bar','root')]:d[n]=d[parent].copy()
    contacts={}
    for stem,js in joints.items():
        limb,side=stem.split('.');parent='chest' if limb=='fore' else 'pelvis';a=d[parent]@js[0]
        paw=limb+'_paw.'+side;target=js[-1].copy();target.z-=sole[paw]-.004
        pawpitch=0.;contact=True
        if clip=='run':
            offset={'fore.R':.0,'fore.L':.13,'hind.R':.48,'hind.L':.61}[stem]
            phase=(u-offset)%1;duty=.105;stride=3.25
            # Forward is +Y in Blender. Stance sweeps backwards at 6.5 m/s.
            if phase<duty:
                travel=stride*(duty*.5-phase);lift=0.
            else:
                f=(phase-duty)/(1-duty);travel=(-stride*duty*.5)+(stride*duty)*smooth(0,1,f)
                lift=.145*math.sin(math.pi*f)**1.3;contact=False
                pawpitch=math.radians(-26)*math.sin(math.pi*f)
            target.y=(js[0].y+.015 if limb=='fore' else js[0].y+(js[-1]-js[-2]).y)+travel
            target.z+=lift
        elif clip=='bite':
            stride=.105*smooth(.26,.52,u)*(1-smooth(.67,1,u)) if limb=='fore' else 0
            target.y+=stride
            lift=.07*math.sin(math.pi*smooth(.18,.53,u)) if u<.53 and limb=='fore' else 0
            if u>.67 and limb=='fore':lift=.045*math.sin(math.pi*smooth(.67,1,u))
            target.z+=lift;contact=lift<.0001
        elif clip=='spawn':pawpitch=math.radians(3)*(1-smooth(0,.8,u))
        if limb=='hind':
            hock_q=Quaternion((1,0,0),pawpitch*.5)
            hock_vec=hock_q@(js[3]-js[2]);cgoal=target-hock_vec
            b,c=ik(a,cgoal,(js[1]-js[0]).length,(js[2]-js[1]).length,(0,1,0))
            target=c+hock_vec
            d['hind_hock.'+side]=segment(js[2],js[3],c,target)
        else:
            b,target=ik(a,target,(js[1]-js[0]).length,(js[2]-js[1]).length,(0,-1,0));c=target
        d[limb+'_upper.'+side]=segment(js[0],js[1],a,b)
        d[limb+'_lower.'+side]=segment(js[1],js[2],b,c)
        d[paw]=Matrix.Translation(target)@Matrix.Rotation(pawpitch,4,'X')@Matrix.Translation(-js[-1])
        contacts[stem]=contact
    for stem,p in geo['pistons'].items():
        a0,b0=Vector(p['a']),Vector(p['b']);a=d[p['a_bone']]@a0;b=d[p['b_bone']]@b0
        q=(b0-a0).rotation_difference(b-a).to_matrix().to_4x4()
        d[p['case']]=Matrix.Translation(a)@q@Matrix.Translation(-a0)
        d[p['rod']]=Matrix.Translation(b)@q@Matrix.Translation(-b0)
        met=metrics['pistons'][stem];met['min']=min(met['min'],(b-a).length);met['max']=max(met['max'],(b-a).length)
    return d,contacts

CLIPS={'spawn':.4,'idle':1.,'run':.5,'bite':.6,'hit':.25,'death':1.2}
for clip,duration in CLIPS.items():
    if clip=='death':continue
    old_clamps=metrics['ik_clamps'];metrics['maximum_unreachable_m']=0.
    for t in np.linspace(0,duration,int(duration*240)+1):pose(clip,float(t))
    print('IK_CLIP',clip,metrics['ik_clamps']-old_clamps,metrics['maximum_unreachable_m'],flush=True)
print('HOUND_MOTION_ANALYSIS',json.dumps(metrics),flush=True)
if '--analyze' in sys.argv:
    (OUT/'local/motion_analysis.json').write_text(json.dumps(metrics,indent=2),encoding='utf8')
    raise SystemExit(0)

# Adjust the two analytic piston lengths once in the rest mesh, not per frame.
# The telescoping rod always remains inside the closed cylinder at minimum stroke.
piston_fits=[]
for stem,p in geo['pistons'].items():
    a,b=Vector(p['a']),Vector(p['b']);axis=(b-a).normalized();met=metrics['pistons'][stem]
    case_len=met['max']-met['min']+.018;rod_len=met['min']-.006
    assert case_len<met['min']-.004,(stem,met,'piston cannot telescope with two pieces')
    for name,anchor,old,new,is_case in [(p['case'],a,p['barrel_length'],case_len,True),(p['rod'],b,p['rod_length'],rod_len,False)]:
        gi=mesh.vertex_groups[name].index
        for v in mesh.data.vertices:
            if v.groups[0].group!=gi:continue
            along=(v.co-anchor).dot(axis);v.co+=axis*along*(new/old-1)
    piston_fits.append({'name':stem,'minimum_distance':met['min'],'maximum_distance':met['max'],'case_length':case_len,'rod_length':rod_len,
                        'minimum_overlap':case_len+rod_len-met['max'],'minimum_rod_rear_clearance':met['min']-rod_len})
part_points={n:[] for n in part_names}
for v in mesh.data.vertices:part_points[mesh.vertex_groups[v.groups[0].group].name].append(v.co.copy())
centers={n:sum(vs,Vector())/len(vs) for n,vs in part_points.items()}

# Deterministic baked gravity with support from the actual rotated part vertices.
# No explosion, no combat colliders and no random-number consumption at runtime.
initial,_=pose('idle',0)
states={};death=[]
for i,n in enumerate(part_names):
    c=centers[n];D=initial[n];p=D@c;q=D.to_quaternion()
    angle=i*2.399963
    states[n]={'p':p,'q':q,'v':Vector((math.cos(angle)*(.13+.03*(i%4)),math.sin(angle)*(.13+.03*(i%4)),.03)),
               'axis':Vector((math.sin(i*1.37+.3),math.cos(i*2.14),.25)).normalized(),'spin':1.5+.6*(i%5),'delay':.012*(i%7)}
for step in range(289):
    row={}
    for n,s in states.items():row[n]=Matrix.Translation(s['p'])@s['q'].to_matrix().to_4x4()@Matrix.Translation(-centers[n])
    row['root']=I.copy()
    for n in ['Socket_attack','Socket_core']:row[n]=row['head'].copy()
    row['Socket_bar']=I.copy();death.append(row)
    if step==288:break
    t=step/240;dt=1/240
    for n,s in states.items():
        if t<s['delay']:continue
        s['v'].z-=7.8*dt;s['p']+=s['v']*dt
        s['q']=(Quaternion(s['axis'],s['spin']*dt)@s['q']).normalized()
        support=-min((s['q']@(p-centers[n])).z for p in part_points[n])+.005
        if s['p'].z<support:
            s['p'].z=support;s['v'].z=max(0,-s['v'].z*.12) if s['v'].z<-.3 else 0
            s['v'].x*=math.exp(-14*dt);s['v'].y*=math.exp(-14*dt);s['spin']*=math.exp(-15*dt)
        if t>.90:s['spin']*=math.exp(-15*dt)

samples={};actions={};poses_for_export={}
for clip,duration in CLIPS.items():
    times=sorted(set([round(i/24,8) for i in range(int(duration*24)+1)]+[duration]+([.3] if clip=='bite' else [])))
    if clip=='run':
        # Preserve exact stance contacts between the 24 Hz timeline samples.
        # A fast gallop has only 52.5 ms of stance per leg; integer frames alone
        # interpolate the hierarchical knee/wrist through the ground.
        for offset in (0.,.13,.48,.61):
            for phase in (-.025,0.,.013125,.02625,.039375,.0525,.065625,.07875,.091875,.105,.130):
                times.append(round(((offset+phase)%1)*duration,8))
        times=sorted(set(times))
    action=bpy.data.actions.new(clip);action.use_fake_user=True;rig.animation_data.action=action
    previous={};records=[]
    for t in times:
        frame=1+t*24;sc.frame_set(int(frame),subframe=frame%1)
        d=death[min(288,round(t*240))] if clip=='death' else pose(clip,t)[0]
        world={n:d[n]@rests[n] for n in spec}
        for n,pb in rig.pose.bones.items():
            parent=spec[n][1];local=world[parent].inverted()@world[n] if parent else world[n]
            basis=rest_local[n].inverted()@local
            loc,q,scale=basis.decompose()
            if n in previous and q.dot(previous[n])<0:q.negate()
            previous[n]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=(1,1,1)
            for prop in ('location','rotation_quaternion','scale'):pb.keyframe_insert(prop,frame=frame,group=n)
        bpy.context.view_layer.update()
        records.append({'time':t,'world':{n:[list(r) for r in m] for n,m in world.items()}})
        err=max((rig.pose.bones[n].matrix.translation-world[n].translation).length for n in spec)
        assert err<.000005,(clip,t,err)
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    for k in fc.keyframe_points:k.interpolation='LINEAR'
    action['duration_seconds']=duration;action['loop']=clip in ('idle','run')
    actions[clip]=action;samples[clip]=times;poses_for_export[clip]=records
    track=rig.animation_data.nla_tracks.new();track.name='CLIP_'+clip;track.mute=True
    strip=track.strips.new(clip,1,action);strip.action_slot=action.slots[0]
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=I
sc.frame_set(1);bpy.context.view_layer.update()
sc.frame_start=1;sc.frame_end=30
rig['rigid_parts']=len(part_names);rig['fps']=24;rig['forward']='Blender +Y / Godot -Z'
rig['run_cycle_distance_m']=3.25;rig['bite_hit_seconds']=.3
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'hound_game_v2.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(BASE/'hound_static.glb'),export_format='GLB',use_selection=True,export_animations=False,
 export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_yup=True,export_tangents=True)
report={'clips':{n:{'seconds':d,'times':samples[n],'loop':n in ('idle','run')} for n,d in CLIPS.items()},'bones':len(spec),'parts':len(part_names),
 'triangles':len(mesh.data.polygons),'piston_fits':piston_fits,'analysis':metrics,'joints':geo['joints'],
 'parts_metadata':{n:{'bone':n,'parent':spec[n][1],'pivot_blender':list(spec[n][0]),'vertices':len(part_points[n])} for n in part_names},
 'sockets':{n:{'parent':spec[n][1],'rest_blender':list(spec[n][0])} for n in spec if n.startswith('Socket_')},
 'run_cycle_distance_m':3.25,'run_reference_speed_mps':6.5,'hit_seconds':.3,'shadow_radius_m':.43,
 'rest_world':{n:[list(r) for r in m] for n,m in rests.items()}}
(BASE/'rig.json').write_text(json.dumps(report,indent=2),encoding='utf8')
(OUT/'local/animation_samples.json').write_text(json.dumps(poses_for_export),encoding='utf8')
print('HOUND_RIG_COMPLETE',len(spec),len(part_names),len(mesh.data.polygons),flush=True)
