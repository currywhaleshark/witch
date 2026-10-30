"""Author a pull-back lunge thrust on the right-handed v21 family, in background Blender.

The staff is drawn back to the right hip while the torso coils, then the front
(left) foot steps in, the hips and chest uncoil and both hands drive the staff
forward along its own axis; it slides through the hands at release (0.5). The
other seven actions, every mesh, weight and the 107 rest bones are protected.
Run with ``--probe`` to only print the guard measurements used for the design.
"""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
PROBE = '--probe' in sys.argv
setup = (ROOT/'tools/build_combat_motion_v18.py').read_text(encoding='utf-8').split('src_rest,death_samples,provenance=import_death()')[0]
setup = setup.replace('combat_motion_v17/combat_motion_v17.blend', 'run_arm_v21/run_arm_v21.blend')
setup = setup.replace('5e2cd24cf4bae2a061fcea3a1f919c2250e0003c67dd80f69e028147926a2844', '80e04f5ec89e992ed351364095115b87fb3f8b98b2cd7a5833f2a7fda2d32ad7')
setup = setup.replace("/combat_motion_v18'", "/thrust_v23'")
# The v12 helper borrows two garment functions from an audit script that is not in the repository.
setup = setup.replace("exec(compile(helper,", "helper=helper.replace(\"ROOT/'reports/source_outfit_v11/cardigan_audit/build_cardigan_candidate.py'\",\"ROOT/'tools/cardigan_fit_helpers_v23.py'\")\nexec(compile(helper,", 1)
exec(compile(setup, str(ROOT/'tools/build_combat_motion_v18.py'), 'exec'), globals())

OLD = 'combat_thrust_rh_v20'
NEW = 'combat_thrust_rh_v23'
COUNT = 49
EVENT_FRAME = 25
guard, guard_basis = pose_source('combat_idle_rh_v20', 1)
GC = guard['DEF-hand.R'] @ OFFSET
GA = (guard['DEF-hand.R'].to_3x3() @ STAFF_LOCAL_AXIS).normalized()
GQ = {side: guard['DEF-hand.'+side].to_quaternion() for side in ('R', 'L')}
GS = (guard['DEF-hand.L'] @ LEFT_OFFSET - GC).dot(GA)


def describe(pose):
    center = pose['DEF-hand.R'] @ OFFSET
    axis = (pose['DEF-hand.R'].to_3x3() @ STAFF_LOCAL_AXIS).normalized()
    return {'center': [round(v, 4) for v in center], 'axis': [round(v, 4) for v in axis],
        'left_axial': round((pose['DEF-hand.L'] @ LEFT_OFFSET - center).dot(axis), 4),
        'pelvis': [round(v, 4) for v in pose['DEF-pelvis'].translation],
        'shoulder_R': [round(v, 4) for v in pose['DEF-upper_arm.R'].translation],
        'shoulder_L': [round(v, 4) for v in pose['DEF-upper_arm.L'].translation],
        'foot_L': [round(v, 4) for v in pose['DEF-foot.L'].translation],
        'foot_R': [round(v, 4) for v in pose['DEF-foot.R'].translation]}


if PROBE:
    print('GUARD', json.dumps(describe(guard)), 'spacing', round(GS, 4), 'reach', round(CHAIN['DEF-upper_arm.R'][1] + CHAIN['DEF-forearm.R'][1], 4), flush=True)
    for frame in (1, 4, 7, 10, 13, 16, 19, 22, 25):
        pose, _ = pose_source(OLD, frame)
        print('OLD', frame, json.dumps(describe(pose)), flush=True)
    raise SystemExit(0)

# Timeline (normalized). The right hand leads the shaft, so the chamber is on the
# left hip with the left (rear) hand at the hip; the right foot steps in.
GUARD_CENTER, GUARD_AXIS_V = tuple(GC), tuple(GA)
CENTERS = [(0, GUARD_CENTER), (.30, (.06, -.12, 1.0)), (.38, (.07, -.10, .99)), (.45, (0, -.40, 1.05)),
    (.50, (-.03, -.58, 1.08)), (.60, (-.03, -.59, 1.075)), (.76, (-.02, -.40, 1.09)), (1, GUARD_CENTER)]
AXES = [(0, GUARD_AXIS_V), (.30, (-.18, -.97, .12)), (.38, (-.18, -.97, .12)), (.45, (-.06, -.995, .08)),
    (.50, (0, -.997, .07)), (.60, (0, -.997, .07)), (.76, (-.20, -.90, .40)), (1, GUARD_AXIS_V)]
SLIDE = [(0, -.26), (.30, -.34), (.38, -.34), (.47, .09), (.50, .16), (.60, .16), (.80, -.20), (1, -.26)]
SPACING = [(0, -.26), (.38, -.26), (.50, -.20), (.62, -.20), (1, -.26)]
STEP = [(0, 0), (.38, 0), (.48, .36), (.66, .36), (.92, 0), (1, 0)]
LIFT = [(0, 0), (.38, 0), (.43, .05), (.48, 0), (.66, 0), (.78, .04), (.92, 0), (1, 0)]
PELVIS_Y = [(0, 0), (.36, .04), (.50, -.18), (.62, -.18), (.92, 0), (1, 0)]
PELVIS_Z = [(0, 0), (.36, -.04), (.50, -.09), (.62, -.085), (.92, 0), (1, 0)]
LEAN = [(0, 0), (.36, -5), (.50, 16), (.62, 16), (1, 0)]
YAW = [(0, 0), (.36, 26), (.50, -14), (.62, -12), (1, 0)]


def hinge_frame(direction, normal):
    y = direction.normalized()
    x = (normal - y*normal.dot(y)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()


def hinge_rotations(side, shoulder, elbow, wrist):
    # Upper arm and forearm share the actual elbow hinge plane (same rule as the v21 run).
    an, fn, hn = ['DEF-'+stem+'.'+side for stem in ('upper_arm', 'forearm', 'hand')]
    ra = REST[fn].translation-REST[an].translation
    rb = REST[hn].translation-REST[fn].translation
    rn = ra.cross(rb).normalized()
    a, b = elbow-shoulder, wrist-elbow
    n = a.cross(b).normalized()
    qa = (hinge_frame(a, n) @ hinge_frame(ra, rn).inverted()).to_quaternion() @ REST[an].to_quaternion()
    qb = (hinge_frame(b, n) @ hinge_frame(rb, rn).inverted()).to_quaternion() @ REST[fn].to_quaternion()
    return qa, qb


def lunge_body(t, twists):
    restore(guard_basis)
    step, lift, lean, yaw = scalar(t, STEP), scalar(t, LIFT), scalar(t, LEAN), scalar(t, YAW)
    pelvis = guard['DEF-pelvis'].copy()
    pelvis.translation += Vector((0, scalar(t, PELVIS_Y), scalar(t, PELVIS_Z)))
    pelvis = Matrix.LocRotScale(pelvis.translation, qworld(x=lean*.25, z=yaw*.35) @ pelvis.to_quaternion(), Vector((1, 1, 1)))
    ankles = {side: guard['DEF-foot.'+side].translation.copy() for side in ('L', 'R')}
    ankles['R'] += Vector((0, -step, lift))
    for _ in range(24):
        change = pelvis @ guard['DEF-pelvis'].inverted()
        excess = max((change @ guard['DEF-thigh.'+side].translation-ankles[side]).length-CHAIN['DEF-thigh.'+side][1]-CHAIN['DEF-shin.'+side][1]+.001 for side in ('L', 'R'))
        if excess <= 0:
            break
        pelvis.translation.z -= excess+.00001
    desired = {'DEF-pelvis': pelvis}
    # Chest carries the whole coil; neck and head turn part of it back to keep the eyes on target.
    for n, lean_gain, yaw_gain in [('DEF-spine', .35, .25), ('DEF-chest', .45, .40), ('DEF-neck', -.10, -.25), ('DEF-head', -.10, -.30), ('DEF-clavicle.L', 0, 0), ('DEF-clavicle.R', 0, 0)]:
        parent = r.data.bones[n].parent.name
        base = desired[parent] @ guard[parent].inverted() @ guard[n]
        desired[n] = Matrix.LocRotScale(base.translation, qworld(x=lean*lean_gain, z=yaw*yaw_gain) @ base.to_quaternion(), Vector((1, 1, 1)))
    clamps = []
    for side in ('L', 'R'):
        thigh, shin, foot, toe = ['DEF-'+n+'.'+side for n in ('thigh', 'shin', 'foot', 'toe')]
        hip = pelvis @ guard['DEF-pelvis'].inverted() @ guard[thigh].translation
        knee, end = solve_ik(hip, ankles[side], CHAIN[thigh][1], CHAIN[shin][1], Vector((-.08 if side == 'L' else .08, -1, 0)))
        qa = guard[thigh].to_quaternion(); qf = guard[shin].to_quaternion(); qfoot = guard[foot].to_quaternion()
        qa = (qa@Vector((0, 1, 0))).rotation_difference((knee-hip).normalized())@qa
        qf = (qf@Vector((0, 1, 0))).rotation_difference((end-knee).normalized())@qf
        chain_desired(thigh, hip, knee, qa, qf, desired, twists); chain_desired(shin, knee, end, qf, qfoot, desired, twists)
        desired[foot] = Matrix.LocRotScale(end, qfoot, Vector((1, 1, 1))); desired[toe] = desired[foot]@guard[foot].inverted()@guard[toe]
        clamps.append((end-ankles[side]).length)
    apply_desired(desired)
    return max(clamps)


def drive_staff(center, axis, spacing, twists):
    # Both hands keep the guard grip on one rigid shaft that is turned to the new axis.
    axis = axis.normalized()
    turn = GA.rotation_difference(axis)
    grips = [('R', turn@GQ['R'], 0., OFFSET), ('L', turn@GQ['L'], spacing, LEFT_OFFSET)]
    pose = current_pose()
    requested = center.copy()
    for _ in range(24):
        for side, q, ax, off in grips:
            an = 'DEF-upper_arm.'+side
            anchor = pose[an].translation-axis*ax+q@off
            radius = CHAIN[an][1]+CHAIN['DEF-forearm.'+side][1]-.025
            delta = center-anchor
            if delta.length > radius:
                center = anchor+delta.normalized()*radius
    chest = (pose['DEF-chest'] @ guard['DEF-chest'].inverted()).to_quaternion()
    desired = {}; clamps = []
    for side, q, ax, off in grips:
        an, fn, hn = ['DEF-'+stem+'.'+side for stem in ('upper_arm', 'forearm', 'hand')]
        shoulder = pose[an].translation
        pole = chest @ Vector((.40 if side == 'L' else -.40, .15, -1.0))
        # Roll the hand about the shaft so the wrist lines up with its forearm.
        for _ in range(12):
            target = center+axis*ax-q@off
            elbow, wrist = solve_ik(shoulder, target, CHAIN[an][1], CHAIN[fn][1], pole)
            hand_y = q@Vector((0, 1, 0)); fore_y = (wrist-elbow).normalized()
            hp = hand_y-axis*hand_y.dot(axis); fp = fore_y-axis*fore_y.dot(axis)
            q = Quaternion(axis, math.atan2(axis.dot(hp.cross(fp)), hp.dot(fp))*.7)@q
        target = center+axis*ax-q@off
        elbow, wrist = solve_ik(shoulder, target, CHAIN[an][1], CHAIN[fn][1], pole)
        qa, qb = hinge_rotations(side, shoulder, elbow, wrist)
        chain_desired(an, shoulder, elbow, qa, qb, desired, twists)
        chain_desired(fn, elbow, wrist, qb, q, desired, twists)
        desired[hn] = Matrix.LocRotScale(wrist, q, Vector((1, 1, 1)))
        clamps.append((wrist-target).length)
    apply_desired(desired)
    for side in ('R', 'L'):
        hands.apply_fingers(side, 1.)
    bpy.context.view_layer.update()
    return max(clamps), (center-requested).length


def thrust(t, twists):
    legclamp = lunge_body(t, twists)
    spacing = scalar(t, SPACING)
    clamp, correction = drive_staff(Vector(blend_stops(t, CENTERS)), Vector(blend_stops(t, AXES)), spacing, twists)
    continuous_attack_skirt(); collision_adjust(stride=3, iterations=5); fit_cardigan()
    if t in (0, 1):
        restore(guard_basis)
    return {'leg_ik_clamp_m': legclamp, 'arm_ik_clamp_m': clamp, 'staff_reach_correction_m': correction, 'slide_m': scalar(t, SLIDE), 'spacing_m': spacing}


twists = {}; values = []; rows = []
for i in range(COUNT):
    t = i/(COUNT-1)
    info = thrust(t, twists)
    info['frame'] = i+1
    rows.append(record(info)); values.append(current_basis())
    if i % 6 == 0:
        print('V23_THRUST', i+1, json.dumps({k: (round(v, 4) if isinstance(v, float) else v) for k, v in info.items() if k in ('arm_ik_clamp_m', 'staff_reach_correction_m', 'leg_ik_clamp_m', 'secondary_error_m', 'slide_m')}), flush=True)
values[-1] = {n: m.copy() for n, m in values[0].items()}
assert all(x['wrong_finger_curls'] == 0 for x in rows)
assert max(x['secondary_error_m'] for x in rows) < .001
assert max(x['leg_ik_clamp_m'] for x in rows) < .0001
action = write_action(NEW, values, [x['slide_m'] for x in rows])
action['event_normalized'] = .5; action['event_frame'] = EVENT_FRAME
after = check.snapshot(r.name, set())
assert BASELINE['meshes'] == after['meshes'] and BASELINE['rig'] == after['rig']
assert all(after['actions'][n] == h for n, h in BASELINE['actions'].items())
check.sample_action(r, bpy.data.actions['combat_idle_rh_v20'], 1); r['staff_slide_v18'] = -.26
s.frame_start = 1; s.frame_end = COUNT; s.render.fps = 24
output = FOLDER/'thrust_v23.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(output))
digest = hashlib.sha256(output.read_bytes()).hexdigest()
slides = [x['slide_m'] for x in rows]
report = {'passed': True, 'input_sha256': hashlib.sha256(INPUT.read_bytes()).hexdigest(), 'output_sha256': digest,
    'protected_meshes': len(BASELINE['meshes']), 'protected_actions': len(BASELINE['actions']), 'rest_bones': 107,
    'new_thrust': NEW, 'replaces': OLD, 'frames': COUNT, 'event_frame': EVENT_FRAME, 'rows': rows,
    'timeline': {'centers': CENTERS, 'axes': AXES, 'slide': SLIDE, 'spacing': SPACING, 'step_right_foot_m': STEP, 'lift': LIFT,
        'pelvis_y': PELVIS_Y, 'pelvis_z': PELVIS_Z, 'lean_degrees': LEAN, 'yaw_degrees': YAW},
    'method': 'Left-hip chamber with torso coil, right-foot lunge and uncoil; both hands IK-solved to one rigid shaft with the guard grip, v21 elbow hinge frames and wrist roll; v17 continuous skirt supports, v11 collision adjust and cardigan fit.'}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
contract = {**CONTRACT, 'source_blend': output.relative_to(ROOT).as_posix(), 'source_blend_sha256': digest}
contract['runtime_default_clips']['attack_thrust'] = NEW
contract['exported_clips'] = list(contract['exported_clips'])+[NEW]
contract['clips'][NEW] = {'frames': COUNT, 'loop': False, 'action_sha256': check.action_digest(action)}
contract['staff_slide_tracks'][NEW] = slides
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract, indent=2), encoding='utf-8')
print('THRUST_V23_COMPLETE', digest, flush=True)
