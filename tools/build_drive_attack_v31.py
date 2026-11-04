"""Prepared two-hand drive attacks on the fixed v29 character, not gameplay rules.

Read-only licensed FBX samples drive the polearm and Mixamo adaptations. Existing
meshes, binds and actions are protected. Execute in a fresh background Blender.
"""
from pathlib import Path
import bpy, math, json, sys, hashlib, ast
import numpy as np
from mathutils import Matrix, Quaternion, Vector
ROOT=Path(__file__).resolve().parents[1]
INPUT=ROOT/'assets/characters/player/3d/source/middle_school_v1/hand_rebuild_v29/hand_rebuild_v29.blend'
FOLDER=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v31'
REPORT_DIR=ROOT/'reports/drive_attack_v31'
for path in (FOLDER,REPORT_DIR):path.mkdir(parents=True,exist_ok=True)
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(INPUT),load_ui=False,use_scripts=False)
helper=(ROOT/'tools/build_combat_animations_v12.py').read_text(encoding='utf-8').split('CLIPS=')[0]
helper=helper.replace('source_outfit_v11/source_outfit_v11.blend','hand_rebuild_v29/hand_rebuild_v29.blend')
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
(REPORT_DIR/'protected_baseline.json').write_text(json.dumps(BASELINE),encoding='utf-8')
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

def drive_staff(center,axis,spacing,twists,settle,elbow_lift=0.):
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
  for _ in range(12):
   target=center+axis*ax-q@off;elbow,wrist=solve_ik(shoulder,target,CHAIN[an][1],CHAIN[fn][1],pole)
   hy=q@Vector((0,1,0));fy=(wrist-elbow).normalized();hp=hy-axis*hy.dot(axis);fp=fy-axis*fy.dot(axis)
   q=Quaternion(axis,math.atan2(axis.dot(hp.cross(fp)),hp.dot(fp))*.7*(1-settle))@q
  target=center+axis*ax-q@off;elbow,wrist=solve_ik(shoulder,target,CHAIN[an][1],CHAIN[fn][1],pole)
  qa,qb=hinge_rotations(side,shoulder,elbow,wrist)
  limb={};chain_desired(an,shoulder,elbow,qa,qb,limb,twists);chain_desired(fn,elbow,wrist,qb,q,limb,twists)
  for n,m in limb.items():desired[n]=Matrix.LocRotScale(m.translation,m.to_quaternion()@Quaternion().slerp(guard_residual[n],settle),Vector((1,1,1)))
  desired[hn]=Matrix.LocRotScale(wrist,q,Vector((1,1,1)));errors.append((wrist-target).length)
 apply_desired(desired)
 for side in ('R','L'):hands.apply_fingers(side,1.)
 bpy.context.view_layer.update()
 return max(errors),(center-requested).length

def source_data(key):
 path=ROOT/'reports/drive_attack_v30/local'/(key+'_source.json')
 if not path.exists():return None
 data=json.loads(path.read_text(encoding='utf-8'))
 data['rest']={n:Matrix(v) for n,v in data['rest'].items()}
 data['samples']=[{n:Matrix(v) for n,v in row.items()} for row in data['samples']]
 return data

SOURCES={k:source_data(k) for k in ('polearm','slash','spin')}
assert SOURCES['polearm']
for key in ('slash','spin'):
 data=SOURCES[key]
 if not data:continue
 data['rest']={n.split(':')[-1]:m for n,m in data['rest'].items()}
 forward=sum((data['rest'][side+'ToeBase'].translation-data['rest'][side+'Foot'].translation for side in ('Left','Right')),Vector())
 align=Matrix.Rotation(-math.pi/2-math.atan2(forward.y,forward.x),4,'Z')
 data['rest']={n:align@m for n,m in data['rest'].items()}
 data['samples']=[{n.split(':')[-1]:align@m for n,m in row.items()} for row in data['samples']]
 yaw=[]
 for row in data['samples']:
  fw=(row['Hips']@data['rest']['Hips'].inverted()).to_quaternion()@Vector((0,-1,0))
  value=math.atan2(fw.x,-fw.y)
  if yaw:
   while value-yaw[-1]>math.pi:value-=math.tau
   while value-yaw[-1]<-math.pi:value+=math.tau
  yaw.append(value)
 data['yaw_samples']=yaw

def interp_pose(data,frame):
 x=max(0.,min(len(data['samples'])-1.,frame-data['range'][0])); lo=int(x);hi=min(lo+1,len(data['samples'])-1);t=x-lo
 return {n:a.lerp(data['samples'][hi][n],t) for n,a in data['samples'][lo].items()}

def source_rot(pose,first,name,gain):
 q=pose[name].to_quaternion()@first[name].to_quaternion().inverted()
 if q.w<0:q.negate()
 return Quaternion().slerp(q,gain)

def body(lean=0.,yaw=0.,down=0.,forward=0.,step=0.,lift=0.,twists=None,source=None,phase=0.,spin=None):
 restore(guard_basis)
 twist=twists if twists is not None else {}
 pelvis=guard['DEF-pelvis'].copy();pelvis.translation+=Vector((0,-forward,-down))
 pelvis=Matrix.LocRotScale(pelvis.translation,qworld(x=lean*.25,z=yaw*.35)@pelvis.to_quaternion(),Vector((1,1,1)))
 ankles={side:guard['DEF-foot.'+side].translation.copy() for side in ('L','R')}
 ankles['R']+=Vector((0,-step,lift))
 foot_rot={side:guard['DEF-foot.'+side].to_quaternion() for side in ('L','R')}
 pole_rot=Quaternion()
 if spin:
  angle,pose,rest,env=spin;turn=Quaternion((0,0,1),angle);pole_rot=turn
  pelvis=Matrix.LocRotScale(pelvis.translation,turn@pelvis.to_quaternion(),Vector((1,1,1)))
  source_q=pose['Hips'].to_quaternion()@rest['Hips'].to_quaternion().inverted()
  fw=source_q@Vector((0,-1,0));src_angle=math.atan2(fw.x,-fw.y);remove=Quaternion((0,0,1),-src_angle)
  target_rot=turn.to_matrix().to_4x4()
  for side,long in [('L','Left'),('R','Right')]:
   local=remove@(pose[long+'Foot'].translation-pose['Hips'].translation)
   local.x=max(.065,abs(local.x)*.65)*(1 if side=='L' else -1)
   local.y=max(-.25,min(.25,local.y*.48))
   offset=turn@Vector((local.x,local.y,0))
   foot=guard['DEF-foot.'+side].translation.copy()
   foot.x=offset.x;foot.y=offset.y
   foot.z+=max(0.,pose[long+'Foot'].translation.z-rest[long+'Foot'].translation.z)*.35
   base=turn@guard['DEF-foot.'+side].translation
   ankles[side]=base.lerp(foot,env)
   fq=remove@(pose[long+'Foot'].to_quaternion()@rest[long+'Foot'].to_quaternion().inverted())
   if fq.w<0:fq.negate()
   foot_rot[side]=turn@Quaternion().slerp(fq,.35*env)@foot_rot[side]
 desired={'DEF-pelvis':pelvis}
 if source:
  pose,first,mapping,gain=source
  for target in ('DEF-pelvis',):
   q=source_rot(pose,first,mapping[target],gain)@desired[target].to_quaternion()
   desired[target]=Matrix.LocRotScale(desired[target].translation,q,Vector((1,1,1)))
  pelvis=desired['DEF-pelvis']
 for _ in range(20):
  dp=pelvis@guard['DEF-pelvis'].inverted()
  excess=max((dp@guard['DEF-thigh.'+side].translation-ankles[side]).length-CHAIN['DEF-thigh.'+side][1]-CHAIN['DEF-shin.'+side][1]+.001 for side in ('L','R'))
  if excess<=0:break
  pelvis.translation.z-=excess+.00001
 for n,lg,yg in [('DEF-spine',.35,.25),('DEF-chest',.4,.4),('DEF-neck',-.1,-.2),('DEF-head',-.1,-.2),('DEF-clavicle.L',0,0),('DEF-clavicle.R',0,0)]:
  parent=r.data.bones[n].parent.name;base=desired[parent]@guard[parent].inverted()@guard[n]
  q=qworld(x=lean*lg,z=yaw*yg)@base.to_quaternion()
  if source and n in mapping:q=source_rot(pose,first,mapping[n],gain*.35)@q
  desired[n]=Matrix.LocRotScale(base.translation,q,Vector((1,1,1)))
 errors=[]
 for side in ('L','R'):
  thigh,shin,foot,toe=['DEF-'+n+'.'+side for n in ('thigh','shin','foot','toe')]
  hip=pelvis@guard['DEF-pelvis'].inverted()@guard[thigh].translation
  knee,end=solve_ik(hip,ankles[side],CHAIN[thigh][1],CHAIN[shin][1],pole_rot@Vector((-.08 if side=='L' else .08,-1,0)))
  qa,qb=[pole_rot@guard[n].to_quaternion() for n in (thigh,shin)];qc=foot_rot[side]
  qa=(qa@Vector((0,1,0))).rotation_difference((knee-hip).normalized())@qa
  qb=(qb@Vector((0,1,0))).rotation_difference((end-knee).normalized())@qb
  chain_desired(thigh,hip,knee,qa,qb,desired,twist);chain_desired(shin,knee,end,qb,qc,desired,twist)
  desired[foot]=Matrix.LocRotScale(end,qc,Vector((1,1,1)));desired[toe]=desired[foot]@guard[foot].inverted()@guard[toe]
  errors.append((end-ankles[side]).length)
 apply_desired(desired)
 return max(errors)

POLE_MAP=dict(zip(['DEF-pelvis','DEF-spine','DEF-chest','DEF-neck','DEF-head'],['B-hips','B-spine','B-chest','B-neck','B-head']))
pole=SOURCES['polearm'];pole_first=interp_pose(pole,29)

def bolt_state(t):
 # The recovered frame is joined to a reduced original chamber, thrust and recoil.
 frame=scalar(t,[(0,29),(.22,9),(.50,17),(.82,29),(1,29)])
 pose=interp_pose(pole,frame)
 mid=(pose['B-hand.L'].translation+pose['B-hand.R'].translation)*.5-pose['B-hips'].translation
 ref=(pole_first['B-hand.L'].translation+pole_first['B-hand.R'].translation)*.5-pole_first['B-hips'].translation
 travel=mid-ref
 # Right shoulder leads while the butt passes outside the left waist. The
 # tool still points down the combat forward axis, not along the chest facing.
 center=Vector((.195,-.385,1.12))+Vector((travel.x*.06,travel.y*.23,travel.z*.06))
 extension=max(0.,min(1.,(-travel.y)/.30))
 return {'center':center,'axis':Vector((-.25,-1,.06)).normalized(),'lean':6+extension*6,'yaw':48+extension*5,
  'down':.025+extension*.015,'forward':.02+extension*.018,'step':.12,'lift':0.,'slide':-.04+extension*.06,'spacing':-.26,
  'source':(pose,pole_first,POLE_MAP,.15),'source_frame':frame,'phase':t}

def saw_state(t):
 phase=math.tau*t
 return {'center':Vector((.18+.012*math.sin(phase),-.40-.010*math.sin(phase*2),1.13+.023*math.cos(phase))),
  'axis':Vector((-.22+.025*math.sin(phase),-1,.07-.035*math.cos(phase))).normalized(),
  'lean':8+1.4*math.sin(phase),'yaw':34+3*math.sin(phase),'down':.035+.003*math.sin(phase*2),
  'forward':.03,'step':.10,'lift':0.,'slide':.03,'spacing':-.22,'source':None,'source_frame':None,'phase':t}

def blend_state(state,amount):
 result=dict(state)
 result['center']=GC.lerp(state['center'],amount)
 result['axis']=GA.lerp(state['axis'],amount).normalized()
 for n in ('lean','yaw','down','forward','step','lift'):result[n]=state[n]*amount
 result['slide']=-.26+(state['slide']+.26)*amount
 result['spacing']=-.26+(state.get('spacing',-.26)+.26)*amount
 result['settle']=1-amount
 if result['source']:
  po,fi,ma,ga=result['source'];result['source']=(po,fi,ma,ga*amount)
 return result

def apply_state(state,twists):
 leg=body(**{k:state[k] for k in ('lean','yaw','down','forward','step','lift','source')},twists=twists,spin=state.get('spin'))
 # Rotating the whole-body frame before solving keeps the hands' axial roll continuous.
 global GA,GQ
 old_axis,old_q=GA,GQ
 if state.get('spin'):
  turn=Quaternion((0,0,1),state['spin'][0]);GA=turn@old_axis;GQ={side:turn@q for side,q in old_q.items()}
 arm,reach=drive_staff(state['center'].copy(),state['axis'],state['spacing'],twists,state.get('settle',0.),state.get('elbow_lift',0.))
 GA,GQ=old_axis,old_q
 # The existing supports follow the reduced planted-leg motion.
 if '--pose-probe' not in sys.argv:
  continuous_attack_skirt();collision_adjust(stride=4,iterations=3);fit_cardigan()
 return {'leg_ik_clamp_m':leg,'arm_ik_clamp_m':arm,'staff_reach_correction_m':reach,
  'slide_m':state['slide'],'spacing_m':state['spacing'],'source_frame':state['source_frame']}

SPECS=[]
for label,state_fn,count in [('bolt',bolt_state,97),('chainsaw_cut',saw_state,49)]:
 SPECS += [(label+'_enter',25,False,lambda t,fn=state_fn:blend_state(fn(0),sm(t))),
           (label+'_loop',count,True,state_fn),
           (label+'_exit',25,False,lambda t,fn=state_fn:blend_state(fn(0),1-sm(t)))]

MIX_MAP=dict(zip(['DEF-pelvis','DEF-spine','DEF-chest','DEF-neck','DEF-head'],['Hips','Spine','Spine2','Neck','Head']))
def slash_state(t):
 data=SOURCES['slash'];frame=scalar(t,[(0,1),(.28,21),(.40,25),(.54,29),(.66,34),(.80,43),(1,56)])
 pose=interp_pose(data,frame);first=data['samples'][0];env=sm(t/.24)*sm((1-t)/.22)
 arc=scalar(t,[(0,-85),(.28,-90),(.40,-60),(.54,0),(.68,90),(1,90)])
 angle=math.radians(arc)
 axis=Vector((math.sin(angle),-math.cos(angle),.10+.65*sm((t-.54)/.14))).normalized()
 mid=(pose['LeftHand'].translation+pose['RightHand'].translation)*.5-pose['Hips'].translation
 midpoint=Vector((axis.x*.14,-.31+axis.y*.06,1.19+max(-.03,min(.03,mid.z*.08))))
 state={'center':midpoint+axis*.065,
  'axis':axis,'lean':6,'yaw':arc*.50,'down':.033,'forward':.025,'step':.08*sm(t/.28)*sm((1-t)/.22),'lift':.035*math.sin(math.pi*min(1,t/.28)) if t<.28 else (.035*math.sin(math.pi*(t-.78)/.22) if t>.78 else 0),
  'slide':.15,'spacing':-.13,'source':(pose,first,MIX_MAP,.26),'source_frame':frame,'phase':t}
 result=blend_state(state,env)
 # Keep the narrow grip through follow-through; widen only after the blade has
 # returned toward the upright guard. The upper right elbow clears the rear hand.
 grip_env=sm(t/.24)*sm((1-t)/.12)
 result['spacing']=-.26+.13*grip_env
 result['slide']=-.26+.41*grip_env
 result['elbow_lift']=env*sm((t-.50)/.15)
 return result

def spin_state(t):
 data=SOURCES['spin'];frame=scalar(t,[(0,1),(.12,5),(.28,13),(.70,33),(.86,45),(1,57)])
 pose=interp_pose(data,frame);x=frame-1;lo=int(x);hi=min(lo+1,len(data['samples'])-1)
 yaw=data['yaw_samples'][lo]*(1-(x-lo))+data['yaw_samples'][hi]*(x-lo)
 angle=(yaw-data['yaw_samples'][0])/(data['yaw_samples'][-1]-data['yaw_samples'][0])*math.tau
 env=sm(t/.20)*sm((1-t)/.18);turn=Quaternion((0,0,1),angle)
 work_axis=Vector((-.08,-.99,.11)).normalized()
 local_center=GC.lerp(Vector((0.,-.37,1.20))+work_axis*.055,env)
 local_axis=GA.lerp(Vector((-.08,-.99,.11)).normalized(),env).normalized()
 return {'center':turn@local_center,'axis':turn@local_axis,'lean':5*env,'yaw':0.,'down':.045*env,'forward':0.,'step':0.,'lift':0.,
  'slide':-.26+.44*env,'spacing':-.26+.15*env,'source':None,'source_frame':frame,'phase':t,'settle':1-env,'spin':(angle,pose,data['rest'],env)}

if SOURCES['slash']:SPECS.append(('grinder_sweep',145,False,slash_state))
if SOURCES['spin']:SPECS.append(('chainsaw_spin',97,False,spin_state))

def settle_winding(values,raw_end):
 # An axial 2*pi branch is invisible at a hand but differs by 120 degrees in
 # each of its three twist sections. Transport the terminal branch into the
 # accepted guard gradually in WORLD pose space; keep every joint/hand point.
 restore(raw_end);end_pose=current_pose()
 correction={}
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

if '--probe' in sys.argv:
 print('GUARD',list(GC),list(GA),len(BASELINE['meshes']),len(BASELINE['actions']),flush=True)
 raise SystemExit(0)
if '--pose-probe' in sys.argv:
 probe=[]
 for key,count,loop,state_fn in SPECS:
  if '--probe-grinder' in sys.argv and key!='grinder_sweep':continue
  twists=GUARD_TWISTS.copy()
  for t in np.linspace(0,1,9):
   state=state_fn(float(t));info=apply_state(state,twists)
   probe.append({'clip':'drive_'+key+'_v31','phase':float(t),'bones_blender':{n:[list(row) for row in m] for n,m in current_pose().items()},'info':info})
 (REPORT_DIR/'pose_probe.json').write_text(json.dumps(probe),encoding='utf-8')
 print('V31_POSE_PROBE_COMPLETE',len(probe),flush=True)
 raise SystemExit(0)
reports={};saved={}
for key,count,loop,state_fn in SPECS:
 twists=GUARD_TWISTS.copy();values=[];rows=[];raw_end=None
 for i in range(count):
  t=i/(count-1);state=state_fn(t)
  info=apply_state(state,twists)
  if i==count-1:raw_end=current_basis()
  if (key.endswith('_enter') and i==0) or (key.endswith('_exit') and i==count-1) or (key in ('grinder_sweep','chainsaw_spin') and i in (0,count-1)):restore(guard_basis)
  info['frame']=i+1;rows.append(record(info));values.append(current_basis())
  if i%8==0:print('DRIVE_POSE',key,i+1,round(info['staff_reach_correction_m'],5),flush=True)
 if loop:values[-1]={n:m.copy() for n,m in values[0].items()};rows[-1]=dict(rows[0],frame=count)
 if key in ('grinder_sweep','chainsaw_spin') or key.endswith('_exit'):settle_winding(values,raw_end)
 name='drive_'+key+'_v31';a=write_action(name,values,[row['slide_m'] for row in rows]);a['combat_loop']=loop
 preview=.3333333333 if key.endswith(('_enter','_exit')) else ({'bolt_loop':.8333333333,'chainsaw_cut_loop':1.,'grinder_sweep':1.6666666667,'chainsaw_spin':2.}[key])
 reports[name]={'frames':count,'duration':(count-1)/24,'preview_duration':preview,'loop':loop,'rows':rows,'action_sha256':check.action_digest(a)}
 saved[key]=values
 assert max(row['secondary_error_m'] for row in rows)<.001,(key,'grip')
 assert max(row['leg_ik_clamp_m'] for row in rows)<.001,(key,'legs')
 (REPORT_DIR/'build_progress.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][n]==h for n,h in BASELINE['actions'].items())
restore(guard_basis);s.frame_start=1;s.frame_end=121;s.render.fps=24
bpy.ops.wm.save_as_mainfile(filepath=str(FOLDER/'drive_attack_v31.blend'))
report={'passed':True,'source_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),
 'protected_meshes':len(BASELINE['meshes']),'protected_actions':len(BASELINE['actions']),'rest_bones':len(r.data.bones),
 'clips':reports,'provenance':{k:{n:v for n,v in data.items() if n not in ('samples','rest')} for k,data in SOURCES.items() if data},
 'scope':'Prepared animation review; no gameplay clock, hitbox, cost or skill implementation.'}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
contract={'fps':24,'staff_attachment':CONTRACT['staff_attachment'],'clips':{n:{k:v for k,v in data.items() if k!='rows'} for n,data in reports.items()},
 'staff_slide_tracks':{n:[row['slide_m'] for row in data['rows']] for n,data in reports.items()},
 'grip_spacing_tracks':{n:[row['spacing_m'] for row in data['rows']] for n,data in reports.items()},
 'grip_note':'Right hand remains forward/above left. Swing preparation slides the right grip toward the butt: grinder 13cm and spin 11cm. Thrust keeps 26cm with the right shoulder leading; sustained cut uses 22cm.'}
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
print('DRIVE_ATTACK_V31_BUILT',len(reports),flush=True)
