"""Run-only arm correction on the preserved v20 source, in background Blender.

The staff is transported by the chest instead of reflecting an animated world
trajectory. Both humerus and ulna frames share the actual elbow hinge plane;
only forearm pronation is distributed toward the unchanged anatomical grip.
"""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
setup = (ROOT/'tools/build_combat_motion_v18.py').read_text(encoding='utf-8').split('src_rest,death_samples,provenance=import_death()')[0]
setup = setup.replace('combat_motion_v17/combat_motion_v17.blend', 'heavy_swing_v20/heavy_swing_v20.blend').replace('5e2cd24cf4bae2a061fcea3a1f919c2250e0003c67dd80f69e028147926a2844', 'eaf2239448135c9e87306a3c8d6118b9b4ddead9e1d4eb0639af45e47cfef436').replace("/combat_motion_v18'", "/run_arm_v21'")
exec(compile(setup, str(ROOT/'tools/build_combat_motion_v18.py'), 'exec'), globals())

ARM_BONES = {p.name for p in r.pose.bones if any(p.name.startswith('DEF-'+stem+'.') for stem in ('upper_arm','forearm','hand','thumb','index','middle','ring','pinky'))}
OLD_RUN = 'combat_run_rh_v20'
NEW_RUN = 'combat_run_rh_v21'
COUNT = 97
STAFF_FOLLOW = .50
RUN_CENTER_OFFSET = Vector((0,-.070,-.020))
guard, guard_basis = pose_source('combat_idle_rh_v20', 1)
guard_center = guard['DEF-hand.R'] @ OFFSET
guard_axis = (guard['DEF-hand.R'].to_3x3() @ STAFF_LOCAL_AXIS).normalized()
guard_q = {side:guard['DEF-hand.'+side].to_quaternion() for side in ('R','L')}
guard_chest = guard['DEF-chest']

def hinge_frame(direction, normal):
    y = direction.normalized()
    x = (normal - y*normal.dot(y)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()

def hinge_rotations(side, shoulder, elbow, wrist):
    an, fn, hn = ['DEF-'+stem+'.'+side for stem in ('upper_arm','forearm','hand')]
    ra = REST[fn].translation-REST[an].translation
    rb = REST[hn].translation-REST[fn].translation
    rn = ra.cross(rb).normalized()
    a, b = elbow-shoulder, wrist-elbow
    n = a.cross(b).normalized()
    qa = (hinge_frame(a,n) @ hinge_frame(ra,rn).inverted()).to_quaternion() @ REST[an].to_quaternion()
    qb = (hinge_frame(b,n) @ hinge_frame(rb,rn).inverted()).to_quaternion() @ REST[fn].to_quaternion()
    return qa, qb

def arm_measure(pose):
    result = {}
    chest_rotation = (pose['DEF-chest'] @ INV['DEF-chest']).to_quaternion()
    down = chest_rotation @ Vector((0,0,-1))
    for side in ('R','L'):
        an, fn, hn = ['DEF-'+stem+'.'+side for stem in ('upper_arm','forearm','hand')]
        a,b,c = [pose[n].translation for n in (an,fn,hn)]
        qa,qb = hinge_rotations(side,a,b,c)
        def axial_error(expected, actual):
            return math.degrees((expected.inverted() @ actual).to_swing_twist('Y')[1])
        result[side] = {'shoulder':list(a), 'elbow':list(b), 'wrist':list(c),
            'flexion_degrees':math.degrees((b-a).angle(c-b)),
            'wrist_deflection_degrees':math.degrees((c-b).angle(pose[hn].to_quaternion()@Vector((0,1,0)))),
            'upper_arm_from_down_degrees':math.degrees((b-a).angle(down)),
            'upper_arm_from_world_down_degrees':math.degrees((b-a).angle(Vector((0,0,-1)))),
            'humerus_hinge_roll_error_degrees':axial_error(qa,pose[an].to_quaternion()),
            'ulna_hinge_roll_error_degrees':axial_error(qb,pose[fn].to_quaternion())}
    return result

def solve_run(t, pose, twists):
    chest_delta = pose['DEF-chest'] @ guard_chest.inverted()
    forward = chest_delta.to_quaternion() @ Vector((0,-1,0))
    chest_q = Quaternion((0,0,1),math.atan2(forward.x,-forward.y)*STAFF_FOLLOW)
    # Half of the chest yaw provides give while its large forward tilt stays
    # in the original torso animation, avoiding a staff drop into the skirt.
    sway = Quaternion((0,0,1), math.radians(2.0)*math.sin(math.tau*t))
    rotation = chest_q @ sway
    center = pose['DEF-chest'].translation + chest_q @ (guard_center-guard_chest.translation)
    center += chest_q @ (RUN_CENTER_OFFSET+Vector((.004*math.sin(math.tau*t),0,.003*math.cos(2*math.tau*t))))
    axis = (rotation @ guard_axis).normalized()
    qr = rotation @ guard_q['R']
    ql = rotation @ guard_q['L']
    grips = [('R',qr,0.,OFFSET), ('L',ql,-.26,LEFT_OFFSET)]
    requested = center.copy()
    for _ in range(24):
        for side,q,ax,off in grips:
            an = 'DEF-upper_arm.'+side
            anchor = pose[an].translation - axis*ax + q@off
            radius = CHAIN[an][1]+CHAIN['DEF-forearm.'+side][1]-.025
            delta = center-anchor
            if delta.length>radius:center=anchor+delta.normalized()*radius
    desired={}
    for side,q,ax,off in grips:
        an,fn,hn = ['DEF-'+stem+'.'+side for stem in ('upper_arm','forearm','hand')]
        shoulder = pose[an].translation
        pole = chest_q @ Vector((.28 if side=='L' else -.28,.12,-1.0))
        # A cylindrical grip permits axial hand roll. Choose the roll that
        # brings the wrist into line with its own forearm, rather than copying
        # the attack's sleeve-clearance roll into a very different run pose.
        for _ in range(12):
            target=center+axis*ax-q@off
            elbow,wrist=solve_ik(shoulder,target,CHAIN[an][1],CHAIN[fn][1],pole)
            hand_y=q@Vector((0,1,0));fore_y=(wrist-elbow).normalized()
            hp=hand_y-axis*hand_y.dot(axis);fp=fore_y-axis*fore_y.dot(axis)
            angle=math.atan2(axis.dot(hp.cross(fp)),hp.dot(fp))
            q=Quaternion(axis,angle*.7)@q
        target = center+axis*ax-q@off
        elbow,wrist = solve_ik(shoulder,target,CHAIN[an][1],CHAIN[fn][1],pole)
        qa,qb = hinge_rotations(side,shoulder,elbow,wrist)
        chain_desired(an,shoulder,elbow,qa,qb,desired,twists)
        chain_desired(fn,elbow,wrist,qb,q,desired,twists)
        desired[hn] = Matrix.LocRotScale(wrist,q,Vector((1,1,1)))
    apply_desired(desired)
    for side in ('R','L'):hands.apply_fingers(side,1.)
    return (center-requested).length

values=[];rows=[];old_rows=[];twists={};non_arm=0.
for i in range(COUNT):
    pose,basis = pose_source(OLD_RUN,i+1)
    old_rows.append(arm_measure(pose))
    restore(basis)
    correction=solve_run(i/(COUNT-1),pose,twists)
    value=current_basis();new_pose=current_pose()
    non_arm=max(non_arm,max(abs(value[n][x][y]-basis[n][x][y]) for n in value if n not in ARM_BONES for x in range(4) for y in range(4)))
    rc=new_pose['DEF-hand.R']@OFFSET;lc=new_pose['DEF-hand.L']@LEFT_OFFSET
    axis=(new_pose['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
    rows.append({'frame':i+1,'arms':arm_measure(new_pose),'reach_correction_m':correction,'grip_error_m':(lc-rc+axis*.26).length,'left_axial_m':(lc-rc).dot(axis),'staff_axis':list(axis)})
    values.append(value)
    if i%24==0:print('V21_RUN_FRAME',i+1,rows[-1]['arms'],flush=True)
values[-1]=values[0]
action=write_action(NEW_RUN,values,[-.26]*COUNT)
action['combat_loop']=True
after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][n]==h for n,h in BASELINE['actions'].items())
assert non_arm<1e-5 and max(row['grip_error_m'] for row in rows)<.001
check.sample_action(r,action,1);r['staff_slide_v18']=-.26
s.frame_start=1;s.frame_end=COUNT;s.render.fps=24
output=FOLDER/'run_arm_v21.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(output))
digest=hashlib.sha256(output.read_bytes()).hexdigest()
report={'passed':True,'input_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),'output_sha256':digest,'protected_meshes':len(BASELINE['meshes']),'protected_actions':len(BASELINE['actions']),'rest_bones':107,'new_run':NEW_RUN,'frames':COUNT,'non_arm_basis_max_error':non_arm,'rows':rows,'before':old_rows,'method':'Chest-relative compact staff target; rest-calibrated elbow hinge frame; continuous forearm twist. Run arms only; original 58 actions preserved.'}
report['target_parameters']={'chest_yaw_follow':STAFF_FOLLOW,'chest_pitch_follow':0,'offset_m':list(RUN_CENTER_OFFSET),'wrist_roll':'Minimum deflection while preserving axial grip; twelve damped iterations','pole_direction':[.28,.12,-1]}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
contract={**CONTRACT,'source_blend':output.relative_to(ROOT).as_posix(),'source_blend_sha256':digest}
contract['runtime_default_clips']['run']=NEW_RUN
contract['exported_clips']=list(contract['runtime_default_clips'].values())+[OLD_RUN]
contract['clips'][NEW_RUN]={'frames':COUNT,'loop':True,'action_sha256':check.action_digest(action)}
contract['staff_slide_tracks'][NEW_RUN]=[-.26]*COUNT
contract['candidate_status']='Run arm correction candidate; six other motions preserve v20; main game remains v18'
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
print('RUN_ARM_V21_COMPLETE',digest,'non_arm',non_arm,flush=True)
