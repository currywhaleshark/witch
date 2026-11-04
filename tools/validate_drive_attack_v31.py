"""Read-only saved-action continuity, contact proxies and engine pose reference."""
from pathlib import Path
import bpy,json,math,sys,gzip
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v31'
REPORT=ROOT/'reports/drive_attack_v31'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'drive_attack_v31.blend'),load_ui=False,use_scripts=False)
rig=bpy.data.objects['PlayerRig_v7'];rig.data.pose_position='POSE'
for tr in rig.animation_data.nla_tracks:tr.mute=True
contract=json.loads((SOURCE/'runtime_contract.json').read_text())
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
hands=AnatomicalHandRig(rig)
off=Vector(contract['staff_attachment']['offset_bone_local'])
left_off=sum((hands.axes['L'][k]*off.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
axis_local=Matrix(contract['staff_attachment']['basis_columns_bone_local']).transposed()@Vector((0,1,0))
report={};reference={};contact_reference=[];endpoints={};failures=[]
for name,spec in contract['clips'].items():
 action=bpy.data.actions[name];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
 rows=[];poses=[];bases=[];max_grip=0.;max_delta=(0.,'');scale_error=0.
 for i in range((spec['frames']-1)*2+1):
  frame=1+i*.5;bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
  pose={p.name:p.matrix.copy() for p in rig.pose.bones};basis={p.name:p.matrix_basis.copy() for p in rig.pose.bones}
  poses.append(pose);bases.append(basis)
  center=pose['DEF-hand.R']@off;axis=pose['DEF-hand.R'].to_3x3()@axis_local
  spacing_track=contract['grip_spacing_tracks'][name]
  lo=int(frame-1);hi=min(lo+1,len(spacing_track)-1);blend=frame-1-lo
  spacing=spacing_track[lo]*(1-blend)+spacing_track[hi]*blend
  grip=(pose['DEF-hand.L']@left_off-center-axis*spacing).length
  max_grip=max(max_grip,grip)
  if grip>.01:print('BAD_GRIP',name,frame,grip,list(center),list(pose['DEF-hand.L']@left_off),list(axis),flush=True)
  for n,m in basis.items():
   scale_error=max(scale_error,max(abs(v-1) for v in m.to_scale()))
   if i:
    angle=math.degrees(bases[-2][n].to_quaternion().rotation_difference(m.to_quaternion()).angle)
    if angle>180:angle=360-angle
    if angle>max_delta[0]:max_delta=(angle,n)
  rows.append({'time':(frame-1)/24,'heads':{n:[m.translation.x,m.translation.z,-m.translation.y] for n,m in pose.items()}})
  contact_reference.append({'clip':name,'phase':(frame-1)/(spec['frames']-1),'frame':frame,
   'bones_blender':{n:[list(row) for row in m] for n,m in pose.items()}})
 reference[name]=rows
 endpoints[name]=(bases[0],bases[-1])
 seam=max((poses[0][n].translation-poses[-1][n].translation).length for n in poses[0])
 velocity_seam=max(((poses[1][n].translation-poses[0][n].translation)-(poses[-1][n].translation-poses[-2][n].translation)).length*48 for n in poses[0])
 report[name]={'samples':len(rows),'maximum_secondary_grip_error_m':max_grip,'maximum_local_half_frame_degrees':max_delta,
  'maximum_scale_error':scale_error,'endpoint_head_difference_m':seam,'loop':spec['loop'],'loop_velocity_seam_m_per_author_second':velocity_seam if spec['loop'] else None}
 if max_grip>=.004:failures.append([name,'grip',max_grip])
 if scale_error>=.0001:failures.append([name,'scale',scale_error])
 # A permissive numeric bound still rejects a flipped elbow or a whole turn in one sample.
 if max_delta[0]>=65:failures.append([name,'step_angle',max_delta])
 if spec['loop'] and seam>=.00001:failures.append([name,'seam',seam])
 if spec['loop'] and velocity_seam>=.15:failures.append([name,'velocity_seam',velocity_seam])
for label in ('bolt','chainsaw_cut'):
 names=['drive_'+label+'_'+part+'_v31' for part in ('enter','loop','exit')]
 for a,b in zip(names,names[1:]):
  error=max(abs(endpoints[a][1][n][i][j]-endpoints[b][0][n][i][j]) for n in endpoints[a][1] for i in range(4) for j in range(4))
  if error>=.0001:failures.append([a,b,'join',error])
report['scope']='Saved authored samples and half-frame interpolation; joint/shaft proxies, not all triangle contacts.'
(REPORT/'source_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
(REPORT/'pose_reference.json').write_text(json.dumps(reference),encoding='utf-8')
with gzip.open(REPORT/'contact_pose_reference.json.gz','wt',encoding='utf-8') as f:json.dump(contact_reference,f)
assert not failures,failures
check.sample_action(rig,bpy.data.actions['combat_idle_rh_v20'],1)
from drive_animation_carrier_v30 import create
carrier=create(rig)
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
qa=qa_check.run(objects=[carrier.name],profile='game',no_modifiers=True)
(REPORT/'carrier_asset_qa.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
assert qa['pass'],qa['errors']
print('DRIVE_ATTACK_SOURCE_QA',len(reference),'clips',carrier.name,qa['warnings'],flush=True)
