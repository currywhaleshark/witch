"""Add solved midpoint keys to two fast clips, preserving their existing poses.

24fps import is retained; author time doubles and the preview time is unchanged.
No geometry, rest bone, accepted action or gameplay timing is edited.
"""
import bpy,math,json,sys,ast,hashlib
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
ROOT=Path(__file__).resolve().parents[1];FOLDER=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v30';REPORT=ROOT/'reports/drive_attack_v30'
bpy.ops.wm.open_mainfile(filepath=str(FOLDER/'drive_attack_v30.blend'),load_ui=False,use_scripts=False)
r=bpy.data.objects['PlayerRig_v7'];r.data.pose_position='POSE';s=bpy.context.scene
for tr in r.animation_data.nla_tracks:tr.mute=True
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
hands=AnatomicalHandRig(r);contract=json.loads((FOLDER/'runtime_contract.json').read_text())
OFFSET=Vector(contract['staff_attachment']['offset_bone_local']);BASIS=Matrix(contract['staff_attachment']['basis_columns_bone_local']).transposed();AXIS=BASIS@Vector((0,1,0))
LEFT=sum((hands.axes['L'][k]*OFFSET.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
REST={b.name:b.matrix_local.copy() for b in r.data.bones};INV={n:m.inverted() for n,m in REST.items()}
def borrow(file,names):
 nodes=[n for n in ast.parse((ROOT/'tools'/file).read_text(encoding='utf-8')).body if isinstance(n,ast.FunctionDef) and n.name in names]
 exec(compile(ast.Module(body=nodes,type_ignores=[]),file,'exec'),globals())
borrow('build_combat_animations_v12.py',{'solve_ik','apply_desired'})
borrow('build_combat_motion_v18.py',{'write_action'})
records={}
for name in ('drive_bolt_loop_v30','drive_grinder_sweep_v30'):
 spec=contract['clips'][name];action=bpy.data.actions[name];r.animation_data.action=action;r.animation_data.action_slot=action.slots[0]
 values=[];globals_pose=[];oldframes=spec['frames']
 for i in range((oldframes-1)*2+1):
  f=1+i*.5;s.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update()
  values.append({p.name:p.matrix_basis.copy() for p in r.pose.bones})
  globals_pose.append({p.name:p.matrix.copy() for p in r.pose.bones})
 for i in range(1,len(values)-1,2):
  r.animation_data.action=None
  for n,m in values[i].items():r.pose.bones[n].matrix_basis=m
  bpy.context.view_layer.update();pose=globals_pose[i];before=globals_pose[i-1];after=globals_pose[i+1]
  qr=before['DEF-hand.R'].to_quaternion().slerp(after['DEF-hand.R'].to_quaternion(),.5)
  ql=before['DEF-hand.L'].to_quaternion().slerp(after['DEF-hand.L'].to_quaternion(),.5)
  center=(before['DEF-hand.R']@OFFSET+after['DEF-hand.R']@OFFSET)*.5;axis=qr@AXIS
  desired={}
  for side,q,offset,spacing in [('R',qr,OFFSET,0.),('L',ql,LEFT,-.26)]:
   an,fn,hn=['DEF-'+n+'.'+side for n in ('upper_arm','forearm','hand')]
   a,b,c=[pose[n].translation for n in (an,fn,hn)]
   length1=(REST[fn].translation-REST[an].translation).length;length2=(REST[hn].translation-REST[fn].translation).length
   pole=((before[fn].translation-before[an].translation)+(after[fn].translation-after[an].translation))*.5
   target=center+axis*spacing-q@offset
   elbow,wrist=solve_ik(a,target,length1,length2,pole)
   for first,start,end,oldstart,oldend in [(an,a,elbow,a,b),(fn,elbow,wrist,b,c)]:
    swing=(oldend-oldstart).normalized().rotation_difference((end-start).normalized())
    for j,suffix in enumerate(('', '.001','.002')):
     n=first+suffix;desired[n]=Matrix.LocRotScale(start.lerp(end,j/3),swing@pose[n].to_quaternion(),Vector((1,1,1)))
   desired[hn]=Matrix.LocRotScale(wrist,q,Vector((1,1,1)))
  apply_desired(desired);values[i]={p.name:p.matrix_basis.copy() for p in r.pose.bones}
 # Replace only these newly authored candidate actions.
 r.animation_data.action=None
 for tr in list(r.animation_data.nla_tracks):
  if any(st.action==action for st in tr.strips):r.animation_data.nla_tracks.remove(tr)
 bpy.data.actions.remove(action)
 oldslide=contract['staff_slide_tracks'][name];slides=[]
 for i in range(len(values)):
  lo=i//2;hi=min(lo+1,len(oldslide)-1);slides.append((oldslide[lo]+oldslide[hi])*.5 if i%2 else oldslide[lo])
 a=write_action(name,values,slides);a['combat_loop']=spec['loop']
 spec['frames']=len(values);spec['duration']=(len(values)-1)/24;spec['action_sha256']=check.action_digest(a)
 contract['staff_slide_tracks'][name]=slides
 records[name]={'original_frames':oldframes,'frames':len(values),'solved_inserted_keys':oldframes-1,'original_integer_poses_preserved':True}
check.sample_action(r,bpy.data.actions['combat_idle_rh_v20'],1);s.render.fps=24
bpy.ops.wm.save_as_mainfile(filepath=str(FOLDER/'drive_attack_v30.blend'))
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
(REPORT/'midpoint_polish.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print('DRIVE_MIDPOINT_POLISH_COMPLETE',records,flush=True)
