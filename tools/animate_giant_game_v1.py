"""Rigid gorilla-like automaton: ground-aware IK, slam and staged assembly."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from automation_rigid_common import *
BASE=ROOT/'assets/actors/automation_batch2/giant_game_v1';OUT=ROOT/'reports/automation_batch2_complete_v1/giant'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'giant_geometry.blend'));sc=bpy.context.scene
mesh=next(o for o in sc.objects if o.type=='MESH');geo=json.loads((BASE/'geometry.json').read_text(encoding='utf8'))
p={n:Vector(v) for n,v in geo['pivots'].items()};joints={n:[Vector(p) for p in ps] for n,ps in geo['joints'].items()}
spec={'root':(Vector(),None),'pelvis':(p['pelvis'],'root'),'torso':(p['torso'],'pelvis')}
for n in ['head','gear','key','exhaust.L','exhaust.R']:spec[n]=(p[n],'torso')
spec['core']=(p['core'],'torso');spec['visor']=(p['visor'],'head')
for stem,js in joints.items():
    limb,side=stem.split('.');parent='torso' if limb=='arm' else 'pelvis'
    if limb=='arm':spec['shoulder.'+side]=(js[0],parent)
    names=['upper','forearm','fist'] if limb=='arm' else ['thigh','shin','foot']
    for n,j in zip(names,js):spec[n+'.'+side]=(j,parent);parent=n+'.'+side
for side,ps in geo['pistons'].items():
    spec['piston_case.'+side]=(Vector(ps['a']),'forearm.'+side);spec['piston_rod.'+side]=(Vector(ps['b']),'fist.'+side)
spec['Socket_attack']=(Vector((0,1.1,.012)),'root');spec['Socket_core']=(p['core'],'torso');spec['Socket_bar']=(Vector((0,0,3.08)),'root')
for side in ('L','R'):spec['Socket_exhaust.'+side]=(p['exhaust.'+side]+Vector((0,0,.33)),'exhaust.'+side)
rig=make_rig(mesh,spec,'Giant_Rigid_Rig');points=part_points(mesh)
clips={'assemble':(1.2,False),'idle':(2.,True),'walk':(1.2,True),'slam':(1.8,False),'hit':(.3,False),'death':(1.8,False)}
clamps=[]
def ik(a,c,l1,l2,pole):
    v=c-a;raw=v.length;dist=min(l1+l2-.001,max(abs(l1-l2)+.001,raw))
    if raw-dist>1e-4:clamps.append(raw-dist)
    direction=v.normalized();c=a+direction*dist;x=(l1*l1-l2*l2+dist*dist)/(2*dist)
    bend=Vector(pole)-direction*Vector(pole).dot(direction)
    return a+direction*x+bend.normalized()*math.sqrt(max(0,l1*l1-x*x)),c
def segment(a,b,aa,bb,old_normal,new_normal):
    def frame(v,n):
        y=v.normalized();x=n.normalized();z=x.cross(y).normalized();x=y.cross(z).normalized()
        return Matrix((x,y,z)).transposed()
    rot=frame(bb-aa,new_normal)@frame(b-a,old_normal).transposed()
    return Matrix.Translation(aa)@rot.to_4x4()@Matrix.Translation(-a)
def stage(n):
    if n.startswith('foot.'):return (0.,.25)
    if n.startswith('shin.'):return (.08,.4)
    if n.startswith('thigh.'):return (.18,.5)
    if n=='pelvis':return (.3,.63)
    if n=='torso':return (.42,.85)
    if n in ('head','visor','core'):return (.9,1.2)
    return (.55,1.05)
def pose(clip,t):
    duration=clips[clip][0];u=t/duration;wave=math.tau*u
    crouch=.055;forward=0.;pitch=0.;roll=0.;wind=0.;strike=0.
    if clip=='idle':crouch=.055+.012*math.sin(wave)
    if clip=='walk':crouch=.16+.025*math.sin(wave*2);roll=.035*math.sin(wave);pitch=-.025
    if clip=='slam':
        wind=smooth(0,.32,t)*(1-smooth(.32,.55,t));strike=smooth(.34,.55,t)*(1-smooth(.70,1.72,t))
        crouch=.055+.26*strike-.025*wind;forward=.12*strike;pitch=-.20*strike+.035*wind
    if clip=='hit':crouch=.055+.08*math.sin(math.pi*u);pitch=.07*math.sin(math.pi*u);forward=-.06*math.sin(math.pi*u)
    if clip=='death':
        crouch=.055+.18*smooth(0,.22,t);pitch=-.06*smooth(0,.22,t)
    pelvis=Matrix.Translation((0,forward,-crouch))@about(p['pelvis'],'Y',roll)
    torso=pelvis@about(p['torso'],'X',pitch);d={'root':I.copy(),'pelvis':pelvis,'torso':torso}
    for n in ['head','gear','key','exhaust.L','exhaust.R','core','visor']:d[n]=torso.copy()
    d['head']=torso@about(p['head'],'X',-pitch*.35);d['visor']=d['head'].copy()
    d['gear']=torso@about(p['gear'],'Y',wave if clip in ('idle','walk') else .25*math.sin(math.pi*u))
    d['key']=torso@about(p['key'],'Z',wave if clip=='idle' else .3*math.sin(wave))
    for side in ('L','R'):
        sign=1 if side=='L' else -1
        js=joints['leg.'+side];a=pelvis@js[0];target=js[2].copy();footname='foot.'+side
        target.z-=min(v.z for v in points[footname])-.008
        if clip=='walk':
            phase=(u-(0 if side=='L' else .5))%1;duty=.22
            if phase<duty:travel=3.12*(duty*.5-phase);lift=0.
            else:
                f=(phase-duty)/(1-duty);travel=3.12*duty*(smooth(0,1,f)-.5);lift=.16*math.sin(math.pi*f)**1.4
            target.y=js[0].y+.07+travel;target.z+=lift
        b,c=ik(a,target,(js[1]-js[0]).length,(js[2]-js[1]).length,(sign*.1,1.,.1))
        old=(js[1]-js[0]).cross(js[2]-js[1]);normal=(b-a).cross(c-b)
        d['thigh.'+side]=segment(js[0],js[1],a,b,old,normal);d['shin.'+side]=segment(js[1],js[2],b,c,old,normal)
        d[footname]=Matrix.Translation(c-js[2])
        js=joints['arm.'+side];a=torso@js[0];target=torso@js[2];fist='fist.'+side;angle=0.
        if clip=='idle':target.z+=.008*math.sin(wave+(0 if side=='L' else .6))
        if clip=='walk':target.y+=.12*math.sin(wave+(0 if side=='L' else math.pi));target.z+=.04*(1+math.sin(wave))
        if clip=='slam':
            raised=Vector((sign*.77,.57,2.55));impact=Vector((sign*.64,1.10,js[2].z-min(v.z for v in points[fist])+.012))
            target=target.lerp(raised,wind).lerp(impact,strike);angle=-.3*wind
        b,c=ik(a,target,(js[1]-js[0]).length,(js[2]-js[1]).length,(sign*1.0,-.7,.2))
        old=(js[1]-js[0]).cross(js[2]-js[1]);normal=(b-a).cross(c-b)
        upper=segment(js[0],js[1],a,b,old,normal);d['upper.'+side]=upper
        d['forearm.'+side]=segment(js[1],js[2],b,c,old,normal)
        d[fist]=Matrix.Translation(c)@Matrix.Rotation(angle,4,'X')@Matrix.Translation(-js[2])
        # Preserve a little clearance under the knuckles outside the impact pose.
        lowest=min((d[fist]@v).z for v in points[fist])
        if lowest<.008:d[fist]=Matrix.Translation((0,0,.008-lowest))@d[fist]
        localq=(torso.inverted()@upper).to_quaternion();q=Quaternion().slerp(localq,.25)
        d['shoulder.'+side]=torso@Matrix.Translation(js[0])@q.to_matrix().to_4x4()@Matrix.Translation(-js[0])
        ps=geo['pistons'][side];a0,b0=Vector(ps['a']),Vector(ps['b']);aa=d['forearm.'+side]@a0;bb=d[fist]@b0
        q=(b0-a0).rotation_difference(bb-aa)
        d['piston_case.'+side]=Matrix.Translation(aa)@q.to_matrix().to_4x4()@Matrix.Translation(-a0)
        d['piston_rod.'+side]=Matrix.Translation(bb)@q.to_matrix().to_4x4()@Matrix.Translation(-b0)
    if clip=='assemble':
        for i,n in enumerate(points):
            a,b=stage(n);f=1-smooth(a,b,t);pivot=spec[n][0]
            offset=Vector((math.sin(i*2.399)*.23,math.cos(i*2.399)*.23,.65+.18*(i%3)))*f
            d[n]=Matrix.Translation(offset)@about(pivot,'Z',.24*f*math.sin(i+1))@d[n]
    if clip=='death' and t>=.22:d.update(death[min(len(death)-1,round((t-.22)*120))])
    for n,(pivot,parent) in spec.items():
        if n.startswith('Socket_'):d[n]=d[parent].copy()
    return d
death=collapse(points,pose('death',.219),1.58,0.)
# Fit piston lengths once to the measured stroke, never by animated scale.
fits={}
for side,ps in geo['pistons'].items():
    lengths=[]
    for clip,(seconds,_) in clips.items():
        if clip in ('death','assemble'):continue
        for t in np.linspace(0,seconds,int(seconds*120)+1):
            d=pose(clip,float(t));lengths.append(((d['forearm.'+side]@Vector(ps['a']))-(d['fist.'+side]@Vector(ps['b']))).length)
    minimum,maximum=min(lengths),max(lengths);case=maximum-minimum+.035;rod=minimum-.012
    fits[side]={'min':minimum,'max':maximum,'case':case,'rod':rod,'overlap':case+rod-maximum}
    assert case<minimum,(side,fits[side])
    axis=(Vector(ps['b'])-Vector(ps['a'])).normalized()
    for n,anchor,old,new in [('piston_case.'+side,Vector(ps['a']),ps['case_length'],case),('piston_rod.'+side,Vector(ps['b']),ps['rod_length'],rod)]:
        gi=mesh.vertex_groups[n].index
        for v in mesh.data.vertices:
            if v.groups[0].group==gi:v.co+=axis*(v.co-anchor).dot(axis)*(new/old-1)
points=part_points(mesh);death=collapse(points,pose('death',.219),1.58,0.)
events={'slam':[.32,.45,.50,.525,.55,.575,.60,.70], 'death':[.22]}
events['walk']=sorted(set(round(((off+phase)%1)*1.2,8) for off in (0.,.5) for phase in (-.02,0,.04,.08,.12,.16,.20,.22,.24)))
report=write_actions('giant',BASE,OUT,mesh,rig,spec,clips,pose,events,metadata={'id':'giant_automaton','shadow_radius_m':.9,'collision_radius_m':.9,
 'slam_hit_seconds':.55,'walk_reference_speed_mps':2.6,'walk_cycle_distance_m':3.12,'piston_fits':fits,'ik_clamps_analysis':{'count':len(clamps),'maximum_m':max(clamps,default=0)},
 'assembly_stages':{n:list(stage(n)) for n in points},'variants':{'base':{'scale':1.,'instances':1},'multiple':{'scale':.75,'instances':3},'enhanced':{'scale':1.1,'equipment':'separate supplemental armour'}},
 'presentation_contract':{'core_on_seconds':1.10,'steam_sockets':['Socket_exhaust.L','Socket_exhaust.R'],'attack_fx':'Socket_attack at 0.55 s; range and damage unchanged'}})
print('GIANT_ANIMATED',report['bones'],'IK_CLAMPS',report['ik_clamps_analysis'],flush=True)
