"""Drive attacks v32: planted stances, weight transfer and body-driven thrust/swing.

The v31 review found the support feet unstable (feet slid with the body or stayed in
the narrow guard width with nearly straight knees) and the thrust/swing driven by the
arms alone. v32 keeps v31's grip rules (right hand forward/above, 26/13/22/11cm
spacing, slide tracks) and rebuilds every frame from explicit foot placements:

* each foot is either planted (ball fixed on the ground, may pivot on the ball with a
  raised heel) or stepping (lift arc); no planted foot ever translates;
* knees track over the toes, the pelvis drops into a real stance and carries the
  weight between the feet;
* thrust is a lunge (rear leg drives, pelvis travels forward, shoulder line turns);
  the semicircle and full turn are hip-led with shoulders and tool lagging.

Existing meshes, binds and actions stay protected. Execute in a fresh background
Blender. ``--preview DIR`` renders review stills without saving; ``--fast`` skips the
cloth support fitting for quicker iteration.
"""
from pathlib import Path
import bpy, math, json, sys, hashlib
import numpy as np
from mathutils import Matrix, Quaternion, Vector
ROOT=Path(__file__).resolve().parents[1]
INPUT=ROOT/'assets/characters/player/3d/source/middle_school_v1/hand_rebuild_v29/hand_rebuild_v29.blend'
FOLDER=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v32'
REPORT_DIR=ROOT/'reports/drive_attack_v32'
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
PREVIEW=Path(ARGS[ARGS.index('--preview')+1]) if '--preview' in ARGS else None
FAST='--fast' in ARGS
ONLY=ARGS[ARGS.index('--only')+1].split(',') if '--only' in ARGS else None
if not PREVIEW:
 for path in (FOLDER,REPORT_DIR):path.mkdir(parents=True,exist_ok=True)
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(INPUT),load_ui=False,use_scripts=False)
helper=(ROOT/'tools/build_combat_animations_v12.py').read_text(encoding='utf-8').split('CLIPS=')[0]
helper=helper.replace('source_outfit_v11/source_outfit_v11.blend','hand_rebuild_v29/hand_rebuild_v29.blend')
# The shared helper creates its own output folders; point them at existing v31 paths
# so preview runs leave no new directories behind.
helper=helper.replace('middle_school_v1/combat_animation_v12','middle_school_v1/drive_attack_v31')
helper=helper.replace('reports/combat_animation_v12/animation_agent','reports/drive_attack_v31')
helper=helper.replace("ROOT/'reports/source_outfit_v11/cardigan_audit/build_cardigan_candidate.py'","ROOT/'tools/cardigan_fit_helpers_v23.py'")
helper=helper.replace("baseline_meshes={o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'};baseline_rig=rig_signature();baseline_actions={a.name:action_digest(a) for a in bpy.data.actions}","")
exec(compile(helper,str(ROOT/'tools/build_combat_animations_v12.py'),'exec'),globals())
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
hands=AnatomicalHandRig(r)
BASELINE=check.snapshot(r.name,set())
CONTRACT=json.loads((ROOT/'assets/characters/player/3d/source/middle_school_v1/run_arm_v21/runtime_contract.json').read_text(encoding='utf-8'))
OFFSET=Vector(CONTRACT['staff_attachment']['offset_bone_local'])
STAFF_BASIS=Matrix(CONTRACT['staff_attachment']['basis_columns_bone_local']).transposed()
STAFF_LOCAL_AXIS=STAFF_BASIS@Vector((0,1,0))
LEFT_OFFSET=sum((hands.axes['L'][k]*OFFSET.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
borrow(ROOT/'tools/build_two_hand_v16.py',{'restore','pose_source','cage_center'})
borrow(ROOT/'tools/build_combat_motion_v18.py',{'current_basis','current_pose','scalar','record','write_action'})
borrow(ROOT/'tools/build_thrust_v23.py',{'hinge_frame','hinge_rotations'})
borrow(ROOT/'tools/build_combat_motion_v17.py',{'continuous_attack_skirt'})
guard,guard_basis=pose_source('combat_idle_rh_v20',1)
GC=guard['DEF-hand.R']@OFFSET
GA=(guard['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
GQ={side:guard['DEF-hand.'+side].to_quaternion() for side in ('R','L')}
HAND_FRAMES={side:check.hand_frame(r,side,Vector((-1,0,0))) for side in ('L','R')}
guard_chain={};GUARD_TWISTS={}
for side in ('R','L'):
 an,fn,hn=['DEF-'+n+'.'+side for n in ('upper_arm','forearm','hand')]
 shoulder,elbow,wrist=[guard[n].translation for n in (an,fn,hn)]
 qa,qb=hinge_rotations(side,shoulder,elbow,wrist)
 chain_desired(an,shoulder,elbow,qa,qb,guard_chain,GUARD_TWISTS)
 chain_desired(fn,elbow,wrist,qb,guard[hn].to_quaternion(),guard_chain,GUARD_TWISTS)
guard_residual={n:m.to_quaternion().inverted()@guard[n].to_quaternion() for n,m in guard_chain.items()}

# ---------------------------------------------------------------- arms / staff
def drive_staff(center,axis,spacing,twists,settle,elbow_lift=0.,roll_limit=None):
 """Unchanged v31 two-hand fixed-length arm solve around one staff frame."""
 axis=axis.normalized();turn=GA.rotation_difference(axis)
 grips=[('R',turn@GQ['R'],0.,OFFSET),('L',turn@GQ['L'],spacing,LEFT_OFFSET)]
 pose=current_pose();requested=center.copy();chest=(pose['DEF-chest']@guard['DEF-chest'].inverted()).to_quaternion()
 for _ in range(20):
  for side,q,ax,off in grips:
   an='DEF-upper_arm.'+side;anchor=pose[an].translation-axis*ax+q@off
   radius=CHAIN[an][1]+CHAIN['DEF-forearm.'+side][1]-.025;delta=center-anchor
   if delta.length>radius:center=anchor+delta.normalized()*radius
 desired={};errors=[]
 for side,q,ax,off in grips:
  an,fn,hn=['DEF-'+n+'.'+side for n in ('upper_arm','forearm','hand')]
  shoulder=pose[an].translation
  pole=(chest@Vector((.40 if side=='L' else -.40,.15,-1.))).normalized()
  pole=pole.lerp(chest@(guard[fn].translation-guard[an].translation).normalized(),settle)
  if side=='R' and elbow_lift:
   pole=pole.lerp(chest@Vector((-.85,.03,-.20)).normalized(),elbow_lift).normalized()
  for iteration in range(12):
   target=center+axis*ax-q@off;elbow,wrist=solve_ik(shoulder,target,CHAIN[an][1],CHAIN[fn][1],pole)
   hy=q@Vector((0,1,0));fy=(wrist-elbow).normalized();hp=hy-axis*hy.dot(axis);fp=fy-axis*fy.dot(axis)
   # The roll target is undefined when the forearm runs along the shaft; fade it
   # out there instead of letting the hand flip between frames (v32 windups).
   defined=min(1.,fp.length/.35)
   angle=math.atan2(axis.dot(hp.cross(fp)),hp.dot(fp))
   if iteration==0:
    # Near +-180 degrees the shortest roll changes sign between frames; keep the
    # branch nearest the previous frame of this clip.
    key='_roll_'+side;previous=twists.get(key,angle)
    while angle-previous>math.pi:angle-=math.tau
    while angle-previous<-math.pi:angle+=math.tau
    twists[key]=angle
   q=Quaternion(axis,angle*.7*(1-settle)*defined)@q
  # Every correction above is a roll about the shaft. Rate-limit that total roll per
  # authored frame so linear key interpolation keeps the hand on the grip.
  base=turn@GQ[side];rel=q@base.inverted()
  if rel.w<0:rel.negate()
  roll=2*math.atan2(Vector((rel.x,rel.y,rel.z)).dot(axis),rel.w);key='_roll_total_'+side
  if key in twists and roll_limit:
   previous=twists[key]
   while roll-previous>math.pi:roll-=math.tau
   while roll-previous<-math.pi:roll+=math.tau
   limit=math.radians(roll_limit)+settle*math.pi
   roll=max(previous-limit,min(previous+limit,roll))
  twists[key]=roll;q=Quaternion(axis,roll)@base
  target=center+axis*ax-q@off;elbow,wrist=solve_ik(shoulder,target,CHAIN[an][1],CHAIN[fn][1],pole)
  qa,qb=hinge_rotations(side,shoulder,elbow,wrist)
  limb={};chain_desired(an,shoulder,elbow,qa,qb,limb,twists);chain_desired(fn,elbow,wrist,qb,q,limb,twists)
  for n,m in limb.items():desired[n]=Matrix.LocRotScale(m.translation,m.to_quaternion()@Quaternion().slerp(guard_residual[n],settle),Vector((1,1,1)))
  desired[hn]=Matrix.LocRotScale(wrist,q,Vector((1,1,1)));errors.append((wrist-target).length)
 apply_desired(desired)
 for side in ('R','L'):hands.apply_fingers(side,1.)
 bpy.context.view_layer.update()
 return max(errors),(center-requested).length

# ---------------------------------------------------------------- legs / body
Z=Vector((0,0,1))
def rz(deg):return Quaternion(Z,math.radians(deg))
GBALL={s:guard['DEF-toe.'+s].translation.copy() for s in 'LR'}
GANKLE={s:guard['DEF-foot.'+s].translation.copy() for s in 'LR'}
GUARD_FEET={s:(GBALL[s].x,GBALL[s].y,0.,0.,0.) for s in 'LR'}
GUARD_KNEE_DIR={}
for sd in 'LR':
 hip=guard['DEF-thigh.'+sd].translation;mid=(hip+GANKLE[sd])*.5
 d=guard['DEF-shin.'+sd].translation-mid;GUARD_KNEE_DIR[sd]=Vector((d.x,d.y,0)).normalized()
LEG_BONES=[e[0] for s in 'LR' for first in ('thigh','shin') for e in CHAIN['DEF-'+first+'.'+s][0]]+['DEF-foot.L','DEF-foot.R','DEF-toe.L','DEF-toe.R']

def leg_rotations(side,hip,knee,ankle,pole):
 tn,sn,fn=['DEF-'+n+'.'+side for n in ('thigh','shin','foot')]
 ra=REST[sn].translation-REST[tn].translation;rb=REST[fn].translation-REST[sn].translation;rn=ra.cross(rb).normalized()
 a,b=knee-hip,ankle-knee;n=a.cross(b)
 fallback=Vector((pole.x,pole.y,0)).normalized().cross(Vector((0,0,-1)))
 n=n.normalized() if n.length>1e-4 else fallback
 if n.dot(fallback)<0:n=-n
 qa=(hinge_frame(a,n)@hinge_frame(ra,rn).inverted()).to_quaternion()@REST[tn].to_quaternion()
 qb=(hinge_frame(b,n)@hinge_frame(rb,rn).inverted()).to_quaternion()@REST[sn].to_quaternion()
 return qa,qb

def foot_frame(side,spec,orbit):
 """spec=(ball x, ball y, yaw deg, heel deg, lift m). Ball stays fixed when heel rises."""
 x,y,yaw,heel,lift=spec
 qz=rz(yaw);rot=qz@Quaternion((1,0,0),math.radians(heel))
 ball=Vector((x,y,GBALL[side].z))
 ankle=ball+rot@(GANKLE[side]-GBALL[side])+Vector((0,0,lift))
 ball=ball+Vector((0,0,lift))
 foot_q=rot@guard['DEF-foot.'+side].to_quaternion()
 w=max(0.,min(1.,lift/.025))
 toe_q=qz@Quaternion((1,0,0),math.radians(heel*w))@guard['DEF-toe.'+side].to_quaternion()
 forward=qz@Vector((0,-1,0))
 if orbit:
  om,oq=orbit;ankle=om@ankle;ball=om@ball;foot_q=oq@foot_q;toe_q=oq@toe_q;forward=oq@forward
 return ankle,ball,foot_q,toe_q,forward

def lean_q(deg,yaw_deg):
 return Quaternion(rz(yaw_deg)@Vector((1,0,0)),math.radians(deg))

def body(st,twists):
 """Pelvis, spine, head and both legs from one stance description."""
 restore(guard_basis)
 settle=st.get('settle',0.)
 px,py,drop,pyaw,lean,roll=st['pelvis']
 orbit=None;base_yaw=0.
 if st.get('orbit'):
  (ox,oy),angle=st['orbit'];oq=rz(angle);pivot=Vector((ox,oy,0))
  om=Matrix.Translation(pivot)@oq.to_matrix().to_4x4()@Matrix.Translation(-pivot);orbit=(om,oq);base_yaw=angle
 g=guard['DEF-pelvis']
 q=rz(pyaw)@lean_q(lean*.3,pyaw)@Quaternion(rz(pyaw)@Vector((0,-1,0)),math.radians(roll))@g.to_quaternion()
 pelvis=Matrix.LocRotScale(g.translation+Vector((px,py,-drop)),q,Vector((1,1,1)))
 if orbit:pelvis=Matrix.LocRotScale(orbit[0]@pelvis.translation,orbit[1]@pelvis.to_quaternion(),Vector((1,1,1)))
 feet={s:foot_frame(s,st['feet'][s],orbit) for s in 'LR'}
 for _ in range(30):
  dp=pelvis@g.inverted()
  excess=max((dp@guard['DEF-thigh.'+s].translation-feet[s][0]).length-CHAIN['DEF-thigh.'+s][1]-CHAIN['DEF-shin.'+s][1]+.004 for s in 'LR')
  if excess<=0:break
  pelvis.translation.z-=excess+.00001
 desired={'DEF-pelvis':pelvis}
 yaw_now=pyaw+base_yaw
 spine_yaw,chest_yaw,head_yaw=st.get('spine_yaw',0.),st.get('chest_yaw',0.),st.get('head_yaw',0.)
 for n,dyaw,dlean in [('DEF-spine',spine_yaw,lean*.35),('DEF-chest',chest_yaw,lean*.35),('DEF-neck',head_yaw*.45,-lean*.4),('DEF-head',head_yaw*.55,-lean*.4),('DEF-clavicle.L',0,0),('DEF-clavicle.R',0,0)]:
  parent=r.data.bones[n].parent.name;base=desired[parent]@guard[parent].inverted()@guard[n]
  if not n.startswith('DEF-clavicle'):yaw_now+=dyaw
  q=rz(dyaw)@lean_q(dlean,yaw_now)@base.to_quaternion()
  desired[n]=Matrix.LocRotScale(base.translation,q,Vector((1,1,1)))
 errors=[]
 for s in 'LR':
  thigh,shin,foot,toe=['DEF-'+n+'.'+s for n in ('thigh','shin','foot','toe')]
  ankle,ball,foot_q,toe_q,forward=feet[s]
  hip=pelvis@g.inverted()@guard[thigh].translation
  outward=Vector((forward.y,-forward.x,0))*(1 if s=='R' else -1)
  pole=(forward+outward*.07).normalized()
  pole=pole.lerp(GUARD_KNEE_DIR[s],settle)
  knee,end=solve_ik(hip,ankle,CHAIN[thigh][1],CHAIN[shin][1],pole)
  qa,qb=leg_rotations(s,hip,knee,end,pole)
  chain_desired(thigh,hip,knee,qa,qb,desired,twists);chain_desired(shin,knee,end,qb,foot_q,desired,twists)
  desired[foot]=Matrix.LocRotScale(end,foot_q,Vector((1,1,1)))
  desired[toe]=Matrix.LocRotScale(desired[foot]@guard[foot].inverted()@guard[toe].translation,toe_q,Vector((1,1,1)))
  errors.append((end-ankle).length)
 if settle>0:
  for n in LEG_BONES:
   m=desired[n];desired[n]=Matrix.LocRotScale(m.translation,m.to_quaternion().slerp(guard[n].to_quaternion(),settle),Vector((1,1,1)))
 apply_desired(desired)
 return max(errors)

# ---------------------------------------------------------------- authored states
def mix(a,b,t):return a+(b-a)*t
def lerp_tuple(a,b,t):return tuple(mix(x,y,t) for x,y in zip(a,b))
def keyed(t,stops):
 """Smoothstep-eased keys; values may be scalars or tuples."""
 if t<=stops[0][0]:return stops[0][1]
 for (a,va),(b,vb) in zip(stops,stops[1:]):
  if a<=t<=b:
   u=sm((t-a)/(b-a))
   return lerp_tuple(va,vb,u) if isinstance(va,tuple) else mix(va,vb,u)
 return stops[-1][1]
def step(t,t0,t1,a,b,height,heel_peak=10.):
 """Foot spec moving from a to b with a lift arc; planted (exact a/b) outside."""
 u=max(0.,min(1.,(t-t0)/(t1-t0)))
 x,y,yaw,heel,lift=lerp_tuple(a,b,sm(u))
 arc=math.sin(math.pi*u) if 0<u<1 else 0.
 return (x,y,yaw,heel+heel_peak*arc,lift+height*arc)
def direction(a_deg,e_deg=0.):
 a,e=math.radians(a_deg),math.radians(e_deg)
 return Vector((math.sin(a)*math.cos(e),-math.cos(a)*math.cos(e),math.sin(e)))
GUARD_A=math.degrees(math.atan2(GA.x,-GA.y));GUARD_E=math.degrees(math.asin(GA.z))
L0,R0=GUARD_FEET['L'],GUARD_FEET['R']

def guard_state():
 return {'pelvis':(0.,0.,0.,0.,0.,0.),'feet':{'L':L0,'R':R0},'center':GC.copy(),'axis':GA.copy(),
  'slide':-.26,'spacing':-.26,'settle':1.,'spine_yaw':0.,'chest_yaw':0.,'head_yaw':0.,'phase':0.}

def blend_to(state,amount,feet=None):
 """Upper body/hip blend between guard and an authored state; feet set explicitly."""
 g=guard_state();out=dict(state)
 out['pelvis']=lerp_tuple(g['pelvis'],state['pelvis'],amount)
 for k in ('spine_yaw','chest_yaw','head_yaw'):out[k]=state.get(k,0.)*amount
 out['center']=GC.lerp(state['center'],amount);out['axis']=GA.lerp(state['axis'],amount).normalized()
 out['slide']=mix(-.26,state['slide'],amount);out['spacing']=mix(-.26,state['spacing'],amount)
 out['settle']=max(state.get('settle',0.),1-amount)
 if feet:out['feet']=feet
 return out

# Bolt cutter: right-lead lunge. Left (rear) ball pivots in place, right foot steps
# forward. The rear leg drives the hips forward; heel rises at full extension.
BOLT_L=(L0[0],L0[1],48.,0.,0.);BOLT_R=(-.135,-.50,-6.,0.,0.)
BOLT_KEYS={
 # pelvis(x,y,drop,yaw,lean,roll), spine, chest, head, rear heel, center, axis, slide
 'ready':((-.010,-.245,.028,38.,4.,0.),6.,6.,-26.,0.,(.17,-.60,1.06),(-.22,-1.,.04),-.04),
 'chamber':((.005,-.205,.022,33.,1.,-2.),5.,5.,-22.,0.,(.20,-.47,1.08),(-.26,-1.,.08),-.07),
 'extend':((-.030,-.395,.048,46.,13.,2.),8.,10.,-34.,24.,(.09,-.99,1.10),(-.14,-1.,.02),.05),
 'hold':((-.028,-.385,.046,45.,12.,2.),8.,9.,-34.,22.,(.10,-.97,1.10),(-.15,-1.,.03),.04),
}
def bolt_pose(name):
 pel,sp,ch,hd,heel,c,a,slide=BOLT_KEYS[name]
 return {'pel':pel,'sp':sp,'ch':ch,'hd':hd,'heel':heel,'c':c,'a':a,'slide':slide}
def bolt_state(t):
 stops=[(0,'ready'),(.24,'chamber'),(.43,'extend'),(.53,'hold'),(.88,'ready'),(1,'ready')]
 vals={k:keyed(t,[(x,tuple(bolt_pose(n)[k]) if isinstance(bolt_pose(n)[k],tuple) else bolt_pose(n)[k]) for x,n in stops]) for k in ('pel','sp','ch','hd','heel','c','a','slide')}
 return {'pelvis':vals['pel'],'spine_yaw':vals['sp'],'chest_yaw':vals['ch'],'head_yaw':vals['hd'],
  'feet':{'L':(BOLT_L[0],BOLT_L[1],BOLT_L[2],vals['heel'],0.),'R':BOLT_R},
  'center':Vector(vals['c']),'axis':Vector(vals['a']).normalized(),'slide':vals['slide'],'spacing':-.26,'settle':0.,'phase':t}
def bolt_enter(t):
 target=bolt_state(0.);amount=sm(t)
 feet={'L':(L0[0],L0[1],48.*sm((t-.05)/.75),0.,0.),'R':step(t,.10,.78,R0,BOLT_R,.045,8.)}
 out=blend_to(target,amount,feet);out['phase']=t;return out

# Chainsaw sustained cut: braced, left foot forward toward the tool, right pivots out.
CUT_L=(.20,-.35,18.,0.,0.);CUT_R=(R0[0],R0[1],-38.,0.,0.)
def saw_state(t):
 p=math.tau*t
 return {'pelvis':(.030,-.150+.014*math.sin(p),.042+.005*math.sin(2*p),22.+2.*math.sin(p),7.+1.5*math.sin(p),1.),
  'spine_yaw':6.,'chest_yaw':6.+1.5*math.sin(p),'head_yaw':-20.,
  'feet':{'L':CUT_L,'R':CUT_R},
  'center':Vector((.18+.012*math.sin(p),-.54-.022*math.sin(p),1.10+.020*math.cos(p))),
  'axis':Vector((-.22+.025*math.sin(p),-1,.07-.035*math.cos(p))).normalized(),
  'slide':.03,'spacing':-.22,'settle':0.,'phase':t}
def saw_enter(t):
 target=saw_state(0.);amount=sm(t)
 feet={'L':step(t,.08,.72,L0,CUT_L,.045,8.),'R':(R0[0],R0[1],-38.*sm((t-.05)/.8),0.,0.)}
 out=blend_to(target,amount,feet);out['phase']=t;return out

# Grinder: wide stance, hip-led semicircle right -> left; right heel pivots through.
GR_L=(.21,-.37,22.,0.,0.)
def grinder_state(t):
 # tool horizontal angle/elevation relative to world forward
 a=keyed(t,[(0,GUARD_A),(.16,-96.),(.27,-118.),(.31,-114.),(.43,0.),(.52,92.),(.61,124.),(.73,62.),(.86,GUARD_A),(1,GUARD_A)])
 e=keyed(t,[(0,GUARD_E),(.16,10.),(.27,14.),(.31,12.),(.43,4.),(.52,8.),(.61,24.),(.73,68.),(.86,GUARD_E),(1,GUARD_E)])
 chest=keyed(t,[(0,0.),(.16,-44.),(.27,-62.),(.31,-60.),(.43,14.),(.52,56.),(.61,76.),(.73,48.),(.86,8.),(1,0.)])
 pyaw=keyed(t,[(0,0.),(.16,-24.),(.27,-34.),(.31,-30.),(.41,30.),(.52,44.),(.61,48.),(.73,32.),(.86,6.),(1,0.)])
 px=keyed(t,[(0,0.),(.16,-.005),(.27,-.035),(.31,-.032),(.43,.045),(.52,.065),(.61,.065),(.73,.045),(.84,.03),(.98,0.),(1,0.)])
 py=keyed(t,[(0,0.),(.16,-.10),(.27,-.085),(.31,-.09),(.43,-.18),(.52,-.20),(.61,-.20),(.73,-.17),(.84,-.12),(.98,0.),(1,0.)])
 drop=keyed(t,[(0,0.),(.16,.035),(.27,.048),(.31,.048),(.43,.060),(.52,.055),(.61,.048),(.73,.035),(.84,.022),(1,0.)])
 lean=keyed(t,[(0,0.),(.16,4.),(.27,5.),(.43,11.),(.52,10.),(.61,8.),(.73,4.),(1,0.)])
 roll=keyed(t,[(0,0.),(.27,-3.),(.43,3.),(.61,2.),(.86,0.),(1,0.)])
 rheel=keyed(t,[(0,0.),(.31,0.),(.47,26.),(.61,30.),(.75,8.),(.84,0.),(1,0.)])
 ryaw=keyed(t,[(0,0.),(.16,-32.),(.31,-32.),(.50,4.),(.61,8.),(.80,-10.),(.92,0.),(1,0.)])
 env=sm(t/.15)*sm((1-t)/.16)
 # hands sit ahead of the chest, pulled toward the tool side
 chest_dir=direction(pyaw+chest)
 tool=direction(a,e)
 h=(chest_dir*.55+Vector((tool.x,tool.y,0))*.45);h.z=0;h.normalize()
 z=keyed(t,[(0,1.20),(.16,1.11),(.27,1.10),(.43,1.02),(.52,1.04),(.61,1.10),(.73,1.16),(.86,1.22),(1,1.22)])
 reach=keyed(t,[(0,.30),(.31,.30),(.43,.38),(.55,.36),(.66,.31),(1,.30)])
 center=Vector((px,py,0))+h*reach+Vector((0,0,z))+tool*.06
 grip=sm(t/.16)*sm((1-t)/.12)
 L=step(t,.02,.15,L0,GR_L,.05,10.) if t<.5 else step(t,.84,.98,GR_L,L0,.045,10.)
 R=(R0[0],R0[1],ryaw,rheel,0.)
 state={'pelvis':(px,py,drop,pyaw,lean,roll),'spine_yaw':(chest-pyaw)*.45,'chest_yaw':(chest-pyaw)*.55,
  'head_yaw':-max(-30.,min(30.,chest*.55)),'feet':{'L':L,'R':R},
  'center':GC.lerp(center,env),'axis':GA.lerp(tool,env).normalized(),
  'slide':-.26+.41*grip,'spacing':-.26+.13*grip,'settle':1-env,'phase':t,
  'elbow_lift':env*sm((t-.40)/.12)*(1-sm((t-.70)/.14))}
 return state

# Chainsaw full turn: right foot widens, then a 360 degree pivot on the left ball.
SPIN_R=(-.205,.02,-34.,0.,0.)
SPIN_PIVOT=(L0[0],L0[1])
def spin_state(t):
 turn=360.*sm((t-.28)/.44)
 u=max(0.,min(1.,(t-.30)/.40))
 a_rel=keyed(t,[(0,GUARD_A),(.18,-94.),(.25,-102.),(.28,-102.),(.40,-24.),(.62,-14.),(.72,-52.),(.86,GUARD_A),(1,GUARD_A)])
 e=keyed(t,[(0,GUARD_E),(.18,8.),(.28,10.),(.40,6.),(.62,8.),(.72,18.),(.86,GUARD_E),(1,GUARD_E)])
 chest=keyed(t,[(0,0.),(.18,-40.),(.28,-54.),(.40,-8.),(.62,-4.),(.72,-22.),(.86,0.),(1,0.)])
 pyaw=keyed(t,[(0,0.),(.18,-20.),(.28,-26.),(.40,4.),(.62,2.),(.72,-6.),(.86,0.),(1,0.)])
 px=keyed(t,[(0,0.),(.18,.010),(.28,.035),(.72,.035),(.86,.01),(1,0.)])
 py=keyed(t,[(0,0.),(.18,-.020),(.28,-.035),(.72,-.035),(.86,-.01),(1,0.)])
 drop=keyed(t,[(0,0.),(.18,.035),(.28,.048),(.50,.055),(.72,.045),(.86,.022),(1,0.)])
 lean=keyed(t,[(0,0.),(.18,4.),(.28,6.),(.50,8.),(.72,5.),(1,0.)])
 lheel=keyed(t,[(0,0.),(.28,0.),(.36,16.),(.66,16.),(.74,0.),(1,0.)])
 env=sm(t/.14)*sm((1-t)/.16)
 if t<.5:R=step(t,.03,.17,R0,SPIN_R,.04,8.)
 else:R=step(t,.84,.98,SPIN_R,R0,.04,8.)
 if .30<t<.70:
  # flight: tuck toward the pivot and skim low
  arc=math.sin(math.pi*u);tuck=.15*arc
  R=(mix(SPIN_R[0],SPIN_PIVOT[0],tuck),mix(SPIN_R[1],SPIN_PIVOT[1],tuck)+.03*arc,SPIN_R[2]+10*arc,14*arc,.065*arc)
 chest_dir=direction(pyaw+chest);tool=direction(a_rel,e)
 h=(chest_dir*.6+Vector((tool.x,tool.y,0))*.4);h.z=0;h.normalize()
 local_center=Vector((px,py,0))+h*.30+Vector((0,0,1.09))+tool*.05
 oq=rz(turn);pivot=Vector((SPIN_PIVOT[0],SPIN_PIVOT[1],0))
 world_center=oq@(local_center-pivot)+pivot
 grip=sm(t/.18)*sm((1-t)/.14)
 return {'pelvis':(px,py,drop,pyaw,lean,0.),'spine_yaw':(chest-pyaw)*.45,'chest_yaw':(chest-pyaw)*.55,
  'head_yaw':-max(-28.,min(28.,chest*.5)),'feet':{'L':(L0[0],L0[1],0.,lheel,0.),'R':R},
  'orbit':(SPIN_PIVOT,turn),
  'center':(oq@(GC-pivot)+pivot).lerp(world_center,env),'axis':(oq@GA).lerp(oq@tool,env).normalized(),
  'slide':-.26+.44*grip,'spacing':-.26+.15*grip,'settle':1-env,'phase':t,'spin':turn,'roll_limit':9.}

# ---------------------------------------------------------------- bake
def apply_state(state,twists,cloth=True):
 leg=body(state,twists)
 global GA,GQ
 old_axis,old_q=GA,GQ
 if state.get('spin'):
  turn=rz(state['spin']);GA=turn@old_axis;GQ={side:turn@q for side,q in old_q.items()}
 try:
  arm,reach=drive_staff(state['center'].copy(),state['axis'],state['spacing'],twists,state.get('settle',0.),state.get('elbow_lift',0.),state.get('roll_limit'))
 finally:
  GA,GQ=old_axis,old_q
 if cloth:
  continuous_attack_skirt();collision_adjust(stride=4,iterations=3);fit_cardigan()
 return {'leg_ik_clamp_m':leg,'arm_ik_clamp_m':arm,'staff_reach_correction_m':reach,
  'slide_m':state['slide'],'spacing_m':state['spacing'],'source_frame':None}

LOOPS=[('bolt',bolt_state,bolt_enter,97),('chainsaw_cut',saw_state,saw_enter,49)]
SINGLES=[('grinder_sweep',grinder_state,145),('chainsaw_spin',spin_state,97)]
PREVIEW_SECONDS={'bolt_enter':.3333333333,'bolt_loop':.8333333333,'bolt_exit':.3333333333,
 'chainsaw_cut_enter':.3333333333,'chainsaw_cut_loop':1.,'chainsaw_cut_exit':.3333333333,
 'grinder_sweep':1.6666666667,'chainsaw_spin':2.}

def settle_winding(values,raw_end):
 restore(raw_end);end_pose=current_pose();correction={}
 for n in guard_chain:
  rel=end_pose[n].to_quaternion().inverted()@guard[n].to_quaternion()
  twist=rel.to_swing_twist('Y')[1]
  if abs(twist)>.02:correction[n]=Quaternion((0,1,0),twist)
 if not correction:return
 for i,bases in enumerate(values):
  t=i/(len(values)-1);weight=sm((t-.55)/.45)
  if weight<=0:continue
  restore(bases);pose=current_pose();desired={}
  for n in guard_chain:
   m=pose[n];q=m.to_quaternion()
   if n in correction:q=q@Quaternion().slerp(correction[n],weight)
   desired[n]=Matrix.LocRotScale(m.translation,q,Vector((1,1,1)))
  for side in ('R','L'):desired['DEF-hand.'+side]=pose['DEF-hand.'+side]
  apply_desired(desired);values[i]=current_basis()
 values[-1]={n:m.copy() for n,m in guard_basis.items()}

# ---------------------------------------------------------------- preview stills
def preview(directory):
 directory.mkdir(parents=True,exist_ok=True)
 scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH'
 scene.display.shading.light='STUDIO';scene.display.shading.color_type='TEXTURE'
 scene.render.resolution_x,scene.render.resolution_y=360,440;scene.render.film_transparent=False
 world=scene.world or bpy.data.worlds.new('w');scene.world=world
 outfit='--transformed' in ARGS
 for ob in bpy.data.objects:
  if ob.type!='MESH':continue
  ob.hide_render=ob.hide_get() or ob.name.startswith('PROP_')
  if ob.name=='Hair_Semilong_v27':ob.hide_render=True
  if ob.name=='Hair_Semilong_v7':ob.hide_render=False
 bpy.ops.mesh.primitive_cylinder_add(radius=.012,depth=1.0,vertices=10);shaft=bpy.context.active_object
 bpy.ops.mesh.primitive_cube_add(size=.09);head=bpy.context.active_object
 bpy.ops.mesh.primitive_plane_add(size=6);floor=bpy.context.active_object
 for ob,col in ((shaft,(.1,.1,.12,1)),(head,(.9,.55,.1,1)),(floor,(.55,.58,.62,1))):
  mat=bpy.data.materials.new(ob.name);mat.diffuse_color=col;ob.data.materials.append(mat)
 # foot markers show planted ball positions (green when the ball is on the floor)
 cams=[]
 for name,loc,rot in [('front',(2.6,-3.6,2.2),(math.radians(68),0,math.radians(36))),('side',(4.2,-.25,1.0),(math.radians(86),0,math.radians(90))),('top',(0,-.15,4.8),(0,0,0)),('face',(0,-4.,1.0),(math.radians(90),0,0))]:
  cd=bpy.data.cameras.new(name);cd.type='ORTHO';cd.ortho_scale=2.3 if name!='top' else 1.8
  cam=bpy.data.objects.new(name,cd);scene.collection.objects.link(cam);cam.location=loc;cam.rotation_euler=rot;cams.append(cam)
 jobs=[]
 for key,state_fn,enter_fn,count in LOOPS:
  jobs.append((key+'_enter',enter_fn,6));jobs.append((key+'_loop',state_fn,8))
 for key,state_fn,count in SINGLES:jobs.append((key,state_fn,12))
 report={}
 for clip,fn,n in jobs:
  if ONLY and not any(clip.startswith(o) for o in ONLY):continue
  twists=GUARD_TWISTS.copy();rows=[]
  for i,t in enumerate(np.linspace(0,1,n)):
   state=fn(float(t));info=apply_state(state,twists,cloth=not FAST)
   hand=r.pose.bones['DEF-hand.R'].matrix;center=r.matrix_world@(hand@OFFSET)
   axis=(r.matrix_world.to_3x3()@hand.to_3x3()@STAFF_LOCAL_AXIS).normalized()
   lo,hi=-.80,.78+state['slide']
   rot=Vector((0,0,1)).rotation_difference(axis)
   shaft.matrix_world=Matrix.LocRotScale(center+axis*((lo+hi)*.5+state['slide']*0),rot,Vector((1,1,hi-lo)))
   head.matrix_world=Matrix.LocRotScale(center+axis*hi,rot,Vector((1,1,1)))
   feet={s:list(r.pose.bones['DEF-toe.'+s].head) for s in 'LR'}
   knees={}
   for sd in 'LR':
    hp=r.pose.bones['DEF-thigh.'+sd].head;kn=r.pose.bones['DEF-shin.'+sd].head;an=r.pose.bones['DEF-foot.'+sd].head
    ax=(an-hp).normalized();off=(kn-hp)-ax*(kn-hp).dot(ax);fw=r.pose.bones['DEF-foot.'+sd].matrix.to_3x3()@Vector((0,1,0));fw.z=0;fw.normalize()
    o=off.copy();o.z=0;o=o.normalized() if o.length>1e-6 else o
    knees[sd]={'bend_m':off.length,'dot_foot_fwd':o.dot(fw),'lateral_out':o.x*(1 if sd=='L' else -1)}
   rows.append({'knees':knees,'t':float(t),'reach':info['staff_reach_correction_m'],'arm':info['arm_ik_clamp_m'],'leg':info['leg_ik_clamp_m'],'ball':feet,
    'pelvis_z':r.pose.bones['DEF-pelvis'].head.z})
   for cam in cams:
    if '--views' in ARGS and cam.name not in ARGS[ARGS.index('--views')+1].split(','):continue
    scene.camera=cam;scene.render.filepath=str(directory/f'{clip}_{i:02d}_{cam.name}.png')
    bpy.ops.render.render(write_still=True)
  report[clip]=rows;print('PREVIEW',clip,max(x['reach'] for x in rows),max(x['leg'] for x in rows),flush=True)
 (directory/'preview.json').write_text(json.dumps(report,indent=1),encoding='utf-8')

if PREVIEW:
 preview(PREVIEW);print('V32_PREVIEW_COMPLETE',flush=True);raise SystemExit(0)

# ---------------------------------------------------------------- full bake
reports={};saved={}
def bake(name_key,fn,count,twists,loop=False,settle_end=False,force_guard=()):
 values=[];rows=[];raw_end=None
 for i in range(count):
  t=i/(count-1);state=fn(t);info=apply_state(state,twists)
  if i==count-1:raw_end=current_basis()
  if i in force_guard:restore(guard_basis)
  info['frame']=i+1;rows.append(record(info));values.append(current_basis())
  if i%8==0:print('DRIVE_POSE',name_key,i+1,round(info['staff_reach_correction_m'],5),flush=True)
 if loop:values[-1]={n:m.copy() for n,m in values[0].items()};rows[-1]=dict(rows[0],frame=count)
 if settle_end:settle_winding(values,raw_end)
 return values,rows
def store(key,values,rows,loop):
 name='drive_'+key+'_v32';a=write_action(name,values,[row['slide_m'] for row in rows]);a['combat_loop']=loop
 reports[name]={'frames':len(values),'duration':(len(values)-1)/24,'preview_duration':PREVIEW_SECONDS[key],'loop':loop,'rows':rows,'action_sha256':check.action_digest(a)}
 assert max(row['secondary_error_m'] for row in rows)<.001,(key,'grip')
 assert max(row['leg_ik_clamp_m'] for row in rows)<.001,(key,'legs')
 (REPORT_DIR/'build_progress.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
for key,state_fn,enter_fn,count in LOOPS:
 twists=GUARD_TWISTS.copy()
 enter_values,enter_rows=bake(key+'_enter',enter_fn,25,twists,force_guard=(0,))
 # The loop continues the entry's twist branch; the exit is the exact reversed entry.
 loop_values,loop_rows=bake(key+'_loop',state_fn,count,twists,loop=True)
 loop_values[0]={n:m.copy() for n,m in enter_values[-1].items()};loop_values[-1]={n:m.copy() for n,m in enter_values[-1].items()}
 store(key+'_enter',enter_values,enter_rows,False)
 store(key+'_loop',loop_values,loop_rows,True)
 store(key+'_exit',list(reversed(enter_values)),[dict(row,frame=i+1) for i,row in enumerate(reversed(enter_rows))],False)
for key,state_fn,count in SINGLES:
 twists=GUARD_TWISTS.copy()
 values,rows=bake(key,state_fn,count,twists,settle_end=True,force_guard=(0,count-1))
 store(key,values,rows,False)
after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][n]==h for n,h in BASELINE['actions'].items())
restore(guard_basis);sc=bpy.context.scene;sc.frame_start=1;sc.frame_end=121;sc.render.fps=24
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(FOLDER/'drive_attack_v32.blend'))
order=['bolt_enter','bolt_loop','bolt_exit','grinder_sweep','chainsaw_cut_enter','chainsaw_cut_loop','chainsaw_cut_exit','chainsaw_spin']
reports={'drive_'+k+'_v32':reports['drive_'+k+'_v32'] for k in order}
report={'passed':True,'source_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),
 'protected_meshes':len(BASELINE['meshes']),'protected_actions':len(BASELINE['actions']),'rest_bones':len(r.data.bones),
 'clips':reports,'scope':'Prepared animation review; no gameplay clock, hitbox, cost or skill implementation.'}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
contract={'fps':24,'staff_attachment':CONTRACT['staff_attachment'],'clips':{n:{k:v for k,v in data.items() if k!='rows'} for n,data in reports.items()},
 'staff_slide_tracks':{n:[row['slide_m'] for row in data['rows']] for n,data in reports.items()},
 'grip_spacing_tracks':{n:[row['spacing_m'] for row in data['rows']] for n,data in reports.items()},
 'grip_note':'Right hand remains forward/above left. Swing preparation slides the right grip toward the butt: grinder 13cm and spin 11cm. Thrust keeps 26cm with the right shoulder leading; sustained cut uses 22cm.',
 'stance_note':'Feet are planted or stepping, never sliding: bolt right-foot lunge step, grinder/cut left step, spin pivots 360 degrees on the left ball. Visual step travel is local to the skeleton and returns exactly to the guard.'}
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
print('DRIVE_ATTACK_V32_BUILT',len(reports),flush=True)
