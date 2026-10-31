"""A covered field-entry gesture on the preserved v24 rig; background Blender only."""
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/characters/player/3d/source/middle_school_v1/spring_jump_v24/spring_jump_v24.blend'
setup=(ROOT/'tools/build_combat_motion_v18.py').read_text(encoding='utf-8').split('src_rest,death_samples,provenance=import_death()')[0]
setup=setup.replace('combat_motion_v17/combat_motion_v17.blend','spring_jump_v24/spring_jump_v24.blend')
setup=setup.replace('5e2cd24cf4bae2a061fcea3a1f919c2250e0003c67dd80f69e028147926a2844',hashlib.sha256(BASE.read_bytes()).hexdigest())
setup=setup.replace("/combat_motion_v18'","/transformation_v25'")
setup=setup.replace("CONTRACT=json.loads((INPUT.parent/'runtime_contract.json').read_text(encoding='utf-8'))","CONTRACT=json.loads((INPUT.parent.parent/'thrust_v23/runtime_contract.json').read_text(encoding='utf-8'))")
setup=setup.replace("exec(compile(helper,", "helper=helper.replace(\"ROOT/'reports/source_outfit_v11/cardigan_audit/build_cardigan_candidate.py'\",\"ROOT/'tools/cardigan_fit_helpers_v23.py'\")\nexec(compile(helper,",1)
exec(compile(setup,str(ROOT/'tools/build_combat_motion_v18.py'),'exec'),globals())

CLIP='combat_transform_entry_v25';COUNT=73;DURATION=3.0
borrow(ROOT/'tools/build_run_arm_v21.py',{'hinge_frame','hinge_rotations'})
guard,guard_basis=pose_source('combat_idle_rh_v20',1)
center=guard['DEF-hand.R']@OFFSET
axis=(guard['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
float_axis=Vector((.06,-.08,.995)).normalized()
float_center=Vector((-.30,-.27,1.13))
float_q=axis.rotation_difference(float_axis)@guard['DEF-hand.R'].to_quaternion()
float_wrist=float_center-float_q@OFFSET
unarmed={}
for side in ('R','L'):
    sign=-1 if side=='R' else 1
    unarmed[side]=(Vector((sign*.25,-.045,.835)),hands.orientation(side,(sign*.10,-.24,-.965),(-sign,0,0)))

# Calibrate a hinge-consistent chain at the accepted endpoint. Ease only its
# residual rolls back in as the hands settle, instead of transporting the combat
# guard's large humerus/ulna rolls down into the empty-handed standing pose.
guard_chain={};guard_twists={}
for side in ('R','L'):
    an,fn,hn=['DEF-'+n+'.'+side for n in ('upper_arm','forearm','hand')]
    shoulder,elbow,wrist=[guard[n].translation for n in (an,fn,hn)]
    qa,qb=hinge_rotations(side,shoulder,elbow,wrist)
    chain_desired(an,shoulder,elbow,qa,qb,guard_chain,guard_twists)
    chain_desired(fn,elbow,wrist,qb,guard[hn].to_quaternion(),guard_chain,guard_twists)
guard_residual={n:m.to_quaternion().inverted()@guard[n].to_quaternion() for n,m in guard_chain.items()}

def mix_transform(a,b,t):
    return (a[0].lerp(b[0],t),a[1].slerp(b[1],t))

def arm(side,wrist,q,reach,settle,twists):
    an,fn,hn=['DEF-'+n+'.'+side for n in ('upper_arm','forearm','hand')]
    shoulder=guard[an].translation
    sign=-1 if side=='R' else 1
    pole=Vector((sign*.14,.70,-.12)).normalized().lerp(Vector((sign*.28,.12,-1)).normalized(),reach)
    pole=pole.lerp((guard[fn].translation-shoulder).normalized(),settle)
    elbow,end=solve_ik(shoulder,wrist,CHAIN[an][1],CHAIN[fn][1],pole)
    qa,qb=hinge_rotations(side,shoulder,elbow,end)
    desired={}
    chain_desired(an,shoulder,elbow,qa,qb,desired,twists)
    chain_desired(fn,elbow,end,qb,q,desired,twists)
    for name,matrix in desired.items():
        correction=Quaternion().slerp(guard_residual[name],settle)
        desired[name]=Matrix.LocRotScale(matrix.translation,matrix.to_quaternion()@correction,Vector((1,1,1)))
    desired[hn]=Matrix.LocRotScale(end,q,Vector((1,1,1)))
    apply_desired(desired)
    return (end-wrist).length

values=[None]*COUNT;rows=[None]*COUNT;twists=guard_twists.copy()
# Follow winding backwards from the immutable accepted endpoint. Local slerps
# between separately wound forearms previously caused a rolled sleeve at entry.
for i in reversed(range(COUNT)):
    sec=i/24;restore(guard_basis)
    right_reach=sm((sec-.35)/.85)
    settle=sm((sec-1.50)/.60)
    right=mix_transform(unarmed['R'],(float_wrist,float_q),right_reach)
    right=mix_transform(right,(guard['DEF-hand.R'].translation,guard['DEF-hand.R'].to_quaternion()),settle)
    left=mix_transform(unarmed['L'],(guard['DEF-hand.L'].translation,guard['DEF-hand.L'].to_quaternion()),sm((sec-1.50)/.60))
    clamps=[arm('R',*right,right_reach,settle,twists),arm('L',*left,settle,settle,twists)]
    hands.apply_fingers('R',.20+.80*sm((sec-1.20)/.20))
    hands.apply_fingers('L',.20+.80*sm((sec-1.65)/.45))
    bpy.context.view_layer.update()
    # Legs, skirt and cardigan supports retain the quiet accepted idle. Only the
    # upper sleeves follow the authored arm gesture; no whole-skirt flare is added.
    if sec>=2.10:restore(guard_basis)
    pose=current_pose()
    right_center=pose['DEF-hand.R']@OFFSET
    world_axis=(pose['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
    left_center=pose['DEF-hand.L']@LEFT_OFFSET
    rows[i]={'frame':i+1,'seconds':sec,'arm_clamp_m':max(clamps),'right_float_error_m':(right_center-float_center).length,'two_hand_error_m':(left_center-right_center+world_axis*.26).length}
    values[i]=current_basis()
assert max(row['arm_clamp_m'] for row in rows)<.001,rows
action=write_action(CLIP,values,[-.26]*COUNT)
after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][name]==digest for name,digest in BASELINE['actions'].items())
check.sample_action(r,action,1);r['staff_slide_v18']=-.26
s.frame_start=1;s.frame_end=COUNT;s.render.fps=24
output=FOLDER/'transformation_v25.blend';bpy.ops.wm.save_as_mainfile(filepath=str(output))
# Matrix values below are glTF/Godot Y-up in the skeleton's space.
convert=Matrix.Rotation(-math.pi/2,4,'X')
frame_blender=Matrix.LocRotScale(float_center-float_axis*.26,float_q,Vector((1,1,1)))
frame_blender=Matrix.LocRotScale(frame_blender.translation,float_q,Vector((1,1,1)))
rotation_blender=float_q.to_matrix()@STAFF_BASIS
frame_blender=rotation_blender.to_4x4();frame_blender.translation=float_center-float_axis*.26
# Blender Z-up -> glTF Y-up: (x,z,-y).
conversion=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
frame=conversion@frame_blender
contract={'rig_id':'player_humanoid_v11','clip':CLIP,'fps':24,'frames':COUNT,'duration_seconds':DURATION,'assembly_start':.30,'assembly_end':1.15,'grasp_seconds':1.40,'two_hand_seconds':2.10,'outfit_begin':2.12,'outfit_swap':2.40,'outfit_end':2.85,'staff_slide_tracks':{CLIP:[-.26]*COUNT},'staff_attachment':ATTACHMENT,'floating_staff_frame':{'origin':list(frame.translation),'basis_columns':[list(frame.col[i].xyz) for i in range(3)]},'source_blend':output.relative_to(ROOT).as_posix(),'source_blend_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'outfit_source':'assets/characters/player/3d/exports/transformed_fit_v4/outfit_transformed_v4.glb','hide_body_regions':['torso','arms','lowerlegs','feet'],'authoring':'Authored restrained reach/grasp/settle; no new external motion or raw FBX import.'}
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
(REPORT_DIR/'build_validation.json').write_text(json.dumps({'passed':True,'preserved_meshes':len(BASELINE['meshes']),'preserved_actions':len(BASELINE['actions']),'rest_bones':len(r.data.bones),'rows':rows,'source_sha256':contract['source_blend_sha256']},indent=2),encoding='utf-8')
print('TRANSFORMATION_BUILD_COMPLETE',json.dumps(rows[0]),json.dumps(contract['floating_staff_frame']),flush=True)
