"""Whole-body field-entry gesture v26 on the preserved v25 rig; background Blender only.

v25 animated only the arms: every frame restored the idle's first pose, so the
pelvis, spine, head, legs and cloth supports never moved, and both hand moves
were single symmetric smoothsteps separated by dead holds. v26 keeps the same
runtime events (assembly 0.30-1.15s, grasp 1.40s, two hands 2.10s, outfit swap
2.40s, combat 3.00s) and the same floating staff frame, and adds:
- gaze: notices the assembly, follows it, looks at the grip, lifts the chin;
- body: breath, weight shifts, a planted half step toward the staff, a catch
  dip under the staff's weight, an anticipation crouch and rise at the swap;
- timing: keys interpolated by a C1 spline (motion flows through keys instead
  of stopping at each), anticipation/overshoot on the reach and swing, the left
  hand lagging the right.
Feet are held by leg IK. Cloth supports add only their change relative to the
guard pose, and the last 0.3s blend into the exact accepted guard basis.
"""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'assets/characters/player/3d/source/middle_school_v1/transformation_v25/transformation_v25.blend'
setup = (ROOT/'tools/build_combat_motion_v18.py').read_text(encoding='utf-8').split('src_rest,death_samples,provenance=import_death()')[0]
setup = setup.replace('combat_motion_v17/combat_motion_v17.blend', 'transformation_v25/transformation_v25.blend')
setup = setup.replace('5e2cd24cf4bae2a061fcea3a1f919c2250e0003c67dd80f69e028147926a2844', hashlib.sha256(BASE.read_bytes()).hexdigest())
setup = setup.replace("/combat_motion_v18'", "/transformation_v26'")
setup = setup.replace("CONTRACT=json.loads((INPUT.parent/'runtime_contract.json').read_text(encoding='utf-8'))", "CONTRACT=json.loads((INPUT.parent.parent/'thrust_v23/runtime_contract.json').read_text(encoding='utf-8'))")
setup = setup.replace("exec(compile(helper,", "helper=helper.replace(\"ROOT/'reports/source_outfit_v11/cardigan_audit/build_cardigan_candidate.py'\",\"ROOT/'tools/cardigan_fit_helpers_v23.py'\")\nexec(compile(helper,", 1)
exec(compile(setup, str(ROOT/'tools/build_combat_motion_v18.py'), 'exec'), globals())

CLIP = 'combat_transform_entry_v26'; COUNT = 73; DURATION = 3.0
V25 = json.loads((BASE.parent/'runtime_contract.json').read_text(encoding='utf-8'))
borrow(ROOT/'tools/build_run_arm_v21.py', {'hinge_frame', 'hinge_rotations'})
guard, guard_basis = pose_source('combat_idle_rh_v20', 1)

# Same floating staff frame as v25 (build_transformation_v25.py).
axis = (guard['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
float_axis = Vector((.06, -.08, .995)).normalized()
float_center = Vector((-.30, -.27, 1.13))
float_q = axis.rotation_difference(float_axis)@guard['DEF-hand.R'].to_quaternion()
float_wrist = float_center-float_q@OFFSET
staff_origin = float_center-float_axis*.26
relaxed = {}
for side in ('R', 'L'):
    sign = -1 if side == 'R' else 1
    relaxed[side] = (Vector((sign*.25, -.045, .835)), hands.orientation(side, (sign*.10, -.24, -.965), (-sign, 0, 0)))

guard_chain = {}; guard_twists = {}
for side in ('R', 'L'):
    an, fn, hn = ['DEF-'+n+'.'+side for n in ('upper_arm', 'forearm', 'hand')]
    shoulder, elbow, wrist = [guard[n].translation for n in (an, fn, hn)]
    qa, qb = hinge_rotations(side, shoulder, elbow, wrist)
    chain_desired(an, shoulder, elbow, qa, qb, guard_chain, guard_twists)
    chain_desired(fn, elbow, wrist, qb, guard[hn].to_quaternion(), guard_chain, guard_twists)
guard_residual = {n: m.to_quaternion().inverted()@guard[n].to_quaternion() for n, m in guard_chain.items()}
GUARD_CHEST = guard['DEF-chest']
GUARD_GAZE = Vector((0, -1, -.35)).normalized()
GUARD_GRIP = guard['DEF-hand.R']@OFFSET
GAZE_LOCAL = guard['DEF-head'].to_quaternion().inverted()@GUARD_GAZE
CLOTH = [n for n in guard_basis if n.startswith(('DEF-skirt', 'DEF-cardigan'))]


# ---------------------------------------------------------------- curves
def spline(t, keys):
    """C1 cubic Hermite through keys (Catmull-Rom tangents, flat ends): motion
    passes through intermediate keys instead of stopping at each."""
    ts = [k[0] for k in keys]; vs = [np.array(k[1], dtype=float) for k in keys]
    if t <= ts[0]: return vs[0]
    if t >= ts[-1]: return vs[-1]
    i = max(j for j in range(len(ts)-1) if ts[j] <= t)
    h = ts[i+1]-ts[i]; s = (t-ts[i])/h
    m0 = np.zeros_like(vs[i]) if i == 0 else (vs[i+1]-vs[i-1])/(ts[i+1]-ts[i-1])
    m1 = np.zeros_like(vs[i]) if i+1 == len(ts)-1 else (vs[i+2]-vs[i])/(ts[i+2]-ts[i])
    return (2*s**3-3*s**2+1)*vs[i]+(s**3-2*s**2+s)*h*m0+(-2*s**3+3*s**2)*vs[i+1]+(s**3-s**2)*h*m1


def f1(t, keys): return float(spline(t, [(a, [b]) for a, b in keys])[0])
def ease_out(x): x = max(0., min(1., x)); return 1-(1-x)**3
def qpow(q, f): return Quaternion().slerp(q, f)


PELVIS = [(0, [0, 0, -.012]), (.25, [0, 0, .004]), (.55, [.012, 0, 0]), (.95, [.018, .004, -.006]), (1.25, [-.034, -.024, -.012]),
          (1.45, [-.031, -.022, -.026]), (1.62, [-.024, -.015, -.011]), (1.95, [.004, .002, -.004]), (2.18, [0, 0, -.022]),
          (2.40, [0, 0, .010]), (2.62, [0, 0, -.005]), (3.0, [0, 0, 0])]
PELVIS_YAW = [(0, 0), (.55, -4), (.95, -2), (1.25, -12), (1.45, -12), (1.95, 2), (2.15, 0), (3.0, 0)]
PELVIS_ROLL = [(0, 0), (.55, 1.5), (.95, 2), (1.25, -2.5), (1.62, -2), (1.95, 0), (3.0, 0)]
CHEST_YAW = [(0, 0), (.5, -6), (.95, -3), (1.25, -16), (1.45, -14), (1.80, 5), (2.05, -1), (2.3, 0), (3.0, 0)]
CHEST_LEAN = [(0, 2), (.25, -2), (.6, 1), (.95, -1), (1.25, 7), (1.45, 9), (1.80, 2), (2.18, 4), (2.40, -6), (2.65, 1), (3.0, 0)]
CHEST_SIDE = [(0, 0), (.95, 1), (1.25, -5), (1.45, -4), (1.80, 2), (2.10, 0), (3.0, 0)]
SHRUG = [(0, 0), (.25, 3), (.60, 0), (2.18, -1), (2.40, 4), (2.70, 0), (3.0, 0)]
BREATH = 0.8   # degrees of chest pitch at ~0.45 Hz, fading out before the guard
STEP = [(0, [0, 0, 0]), (1.0, [0, 0, 0]), (1.12, [-.055, -.045, .032]), (1.26, [-.085, -.065, 0]), (1.62, [-.085, -.065, 0]),
        (1.77, [-.045, -.032, .028]), (1.93, [0, 0, 0]), (3.0, [0, 0, 0])]
STEP_YAW = [(0, 0), (1.0, 0), (1.26, -10), (1.62, -10), (1.93, 0), (3.0, 0)]


def gaze_amount(t): return f1(t, [(0, .45), (.28, .55), (.42, .85), (2.55, .85), (2.85, .3), (3.0, 0)])


# Painted eyes cannot move, so the head does the looking; keep the face toward
# the front camera (v26 first pass turned the head 59 degrees and showed its back).
GAZE_YAW = (-34, 20)      # degrees, negative = her right
GAZE_PITCH = (-32, 14)


def clamp_gaze(d):
    yaw = max(GAZE_YAW[0], min(GAZE_YAW[1], math.degrees(math.atan2(d.x, -d.y))))
    pitch = max(GAZE_PITCH[0], min(GAZE_PITCH[1], math.degrees(math.asin(max(-1, min(1, d.z))))))
    y, p = math.radians(yaw), math.radians(pitch)
    return Vector((math.sin(y)*math.cos(p), -math.cos(y)*math.cos(p), math.sin(p)))


def staff_point(t):
    p = max(0., min(1., (t-.30)/.85))
    return staff_origin+float_axis*(.12+.40*p)   # follow the assembly, but not up to the head


# ---------------------------------------------------------------- body
def body(t, twists):
    restore(guard_basis)
    off = Vector(spline(t, PELVIS)); yaw = f1(t, PELVIS_YAW); roll = f1(t, PELVIS_ROLL)
    pelvis = guard['DEF-pelvis'].copy()
    pelvis = Matrix.LocRotScale(pelvis.translation+off, qworld(y=roll, z=yaw)@pelvis.to_quaternion(), Vector((1, 1, 1)))
    step = Vector(spline(t, STEP)); syaw = f1(t, STEP_YAW)
    ankles = {side: guard['DEF-foot.'+side].translation.copy() for side in ('L', 'R')}
    ankles['R'] += step
    for _ in range(32):
        dp = pelvis@guard['DEF-pelvis'].inverted()
        excess = max((dp@guard['DEF-thigh.'+side].translation-ankles[side]).length-CHAIN['DEF-thigh.'+side][1]-CHAIN['DEF-shin.'+side][1]+.001 for side in ('L', 'R'))
        if excess <= 0: break
        pelvis.translation.z -= excess+.00001
    desired = {'DEF-pelvis': pelvis}
    fade = 1-sm((t-2.45)/.45)
    breath = BREATH*math.sin(math.tau*.45*t)*fade
    qc = qworld(x=f1(t, CHEST_LEAN)+breath, y=f1(t, CHEST_SIDE), z=f1(t, CHEST_YAW))
    for n, share in (('DEF-spine', .4), ('DEF-chest', .6)):
        parent = r.data.bones[n].parent.name; base = desired[parent]@guard[parent].inverted()@guard[n]
        desired[n] = Matrix.LocRotScale(base.translation, qpow(qc, share)@base.to_quaternion(), Vector((1, 1, 1)))
    shrug = f1(t, SHRUG)
    for side, sign in (('L', 1), ('R', -1)):
        n = 'DEF-clavicle.'+side; base = desired['DEF-chest']@guard['DEF-chest'].inverted()@guard[n]
        desired[n] = Matrix.LocRotScale(base.translation, qworld(y=-sign*shrug)@base.to_quaternion(), Vector((1, 1, 1)))
    # Gaze: turn neck and head toward a blended look target.
    head_base = desired['DEF-chest']@guard['DEF-chest'].inverted()@guard['DEF-neck']
    head_pos = (head_base@guard['DEF-neck'].inverted()@guard['DEF-head']).translation
    eye = head_pos+Vector((0, -.06, .07))
    forward = (Vector((0, -3.0, 1.42))-eye).normalized()
    up = (Vector((0, -3.0, 1.80))-eye).normalized()
    to_asm = (staff_point(t)-eye).normalized()
    # grip path approximated without the hand solver (which itself needs this body pose)
    grip = Vector(spline(t, [(1.42, float_center), (1.78, float_center.lerp(GUARD_GRIP, .5)+Vector((0, -.06, .07))), (2.10, GUARD_GRIP)]))
    to_grip = (grip-eye).normalized()
    w_asm = f1(t, [(.28, 0), (.42, 1), (1.08, 1), (1.20, 0)])
    w_grip = f1(t, [(1.08, 0), (1.20, 1), (1.55, 1), (1.78, 0)])
    w_up = f1(t, [(2.05, 0), (2.30, 1), (2.55, 1), (2.80, 0)])
    rest = max(0., 1-w_asm-w_grip-w_up)
    d = clamp_gaze((forward*rest+to_asm*w_asm+to_grip*w_grip+up*w_up).normalized())
    neck = Matrix.LocRotScale(head_base.translation, head_base.to_quaternion(), Vector((1, 1, 1)))
    current = (neck@guard['DEF-neck'].inverted()@guard['DEF-head']).to_quaternion()@GAZE_LOCAL
    R = current.rotation_difference(d)
    angle = min(R.angle, math.radians(65))
    R = Quaternion(R.axis, angle*gaze_amount(t)) if R.angle > 1e-6 else Quaternion()
    desired['DEF-neck'] = Matrix.LocRotScale(neck.translation, qpow(R, .4)@neck.to_quaternion(), Vector((1, 1, 1)))
    hb = desired['DEF-neck']@guard['DEF-neck'].inverted()@guard['DEF-head']
    desired['DEF-head'] = Matrix.LocRotScale(hb.translation, qpow(R, .6)@hb.to_quaternion(), Vector((1, 1, 1)))
    clamps = []
    for side in ('L', 'R'):
        thigh, shin, foot, toe = ['DEF-'+n+'.'+side for n in ('thigh', 'shin', 'foot', 'toe')]
        hip = pelvis@guard['DEF-pelvis'].inverted()@guard[thigh].translation
        knee, end = solve_ik(hip, ankles[side], CHAIN[thigh][1], CHAIN[shin][1], Vector((-.08 if side == 'L' else .08, -1, 0)))
        qa = guard[thigh].to_quaternion(); qf = guard[shin].to_quaternion()
        qfoot = (qworld(z=syaw) if side == 'R' else Quaternion())@guard[foot].to_quaternion()
        qa = (qa@Vector((0, 1, 0))).rotation_difference((knee-hip).normalized())@qa
        qf = (qf@Vector((0, 1, 0))).rotation_difference((end-knee).normalized())@qf
        chain_desired(thigh, hip, knee, qa, qf, desired, twists); chain_desired(shin, knee, end, qf, qfoot, desired, twists)
        desired[foot] = Matrix.LocRotScale(end, qfoot, Vector((1, 1, 1))); desired[toe] = desired[foot]@guard[foot].inverted()@guard[toe]
        clamps.append((end-ankles[side]).length)
    apply_desired(desired)
    return max(clamps), ankles


# ---------------------------------------------------------------- hands
CHEST_NOW = {}


def chest_at(t):
    """Chest matrix of the body pose at time t (cached), for chest-relative and lagged hand targets."""
    key = round(t, 5)
    if key not in CHEST_NOW:
        saved = {pb.name: pb.matrix_basis.copy() for pb in r.pose.bones}
        body(max(0., t), {})
        CHEST_NOW[key] = r.pose.bones['DEF-chest'].matrix.copy()
        restore(saved)
    return CHEST_NOW[key]


def in_chest(world_pos, world_q, chest):
    rel = GUARD_CHEST.inverted()@Matrix.LocRotScale(world_pos, world_q, Vector((1, 1, 1)))
    m = chest@rel
    return m.translation, m.to_quaternion()


def right_target(t):
    chest = chest_at(t)
    lag = chest_at(t-.06)
    rp, rq = in_chest(*relaxed['R'], lag)
    gp, gq = in_chest(guard['DEF-hand.R'].translation, guard['DEF-hand.R'].to_quaternion(), chest)
    r0p, _ = in_chest(*relaxed['R'], chest_at(1.0))
    reach = (float_wrist-r0p).normalized()
    arc = float_wrist.lerp(gp, .5)+Vector((0, -.06, .07))
    over = (gp-arc).normalized()*.012
    keys = [(0, rp), (.88, rp), (1.0, rp+Vector((.008, .02, .035))), (1.27, float_wrist+reach*.018), (1.31, float_wrist), (1.35, float_wrist), (1.42, float_wrist), (1.46, float_wrist),
            (1.62, float_wrist+Vector((-.01, -.02, -.005))), (1.78, arc), (2.02, gp+over), (2.10, gp), (3.0, gp)]
    pos = Vector(spline(t, keys))
    # Catch: the staff's weight lands in the hand. Exactly zero through 1.42s so
    # both frames bracketing the 1.40s attach hold the floating frame.
    if t > 1.42:
        pos += Vector((0, -.010, -.028))*f1(t, [(1.42, 0), (1.49, 1), (1.64, 0)])
    if t <= .95:
        q = rq
    elif t < 1.40:
        q = rq.slerp(float_q, sm((t-.95)/.37))
    elif t < 1.49:
        q = float_q.copy()
    elif t < 2.06:
        q = float_q.slerp(gq, sm((t-1.49)/.57))
    else:
        q = gq
    dip = f1(t, [(1.42, 0), (1.49, 7), (1.64, 0)]) if t > 1.42 else 0.
    q = qworld(x=dip)@q
    return pos, q


REL_L = guard['DEF-hand.R'].inverted()@guard['DEF-hand.L']


def left_target(t):
    lp, lq = in_chest(*relaxed['L'], chest_at(t-.10))
    rp, rq = right_target(t)
    held = Matrix.LocRotScale(rp, rq, Vector((1, 1, 1)))@REL_L
    w = ease_out((t-1.62)/.44)
    pos = lp.lerp(held.translation, w)+Vector((0, -.03, .02))*math.sin(math.pi*w)
    q = lq.slerp(held.to_quaternion(), sm((t-1.62)/.40))
    return pos, q, w


def arm(side, wrist, q, reach, settle, twists):
    an, fn, hn = ['DEF-'+n+'.'+side for n in ('upper_arm', 'forearm', 'hand')]
    shoulder = r.pose.bones[an].matrix.translation.copy()
    sign = -1 if side == 'R' else 1
    pole = Vector((sign*.14, .70, -.12)).normalized().lerp(Vector((sign*.28, .12, -1)).normalized(), reach)
    pole = pole.lerp((guard[fn].translation-guard[an].translation).normalized(), settle)
    elbow, end = solve_ik(shoulder, wrist, CHAIN[an][1], CHAIN[fn][1], pole)
    qa, qb = hinge_rotations(side, shoulder, elbow, end)
    desired = {}
    chain_desired(an, shoulder, elbow, qa, qb, desired, twists)
    chain_desired(fn, elbow, end, qb, q, desired, twists)
    for name, matrix in desired.items():
        desired[name] = Matrix.LocRotScale(matrix.translation, matrix.to_quaternion()@Quaternion().slerp(guard_residual[name], settle), Vector((1, 1, 1)))
    desired[hn] = Matrix.LocRotScale(end, q, Vector((1, 1, 1)))
    apply_desired(desired)
    return (end-wrist).length


# Cloth supports respond to the moving legs/arms; only their change relative to
# the guard pose is added onto the guard's own supports.
restore(guard_basis); continuous_attack_skirt(); collision_adjust(stride=3, iterations=5); fit_cardigan()
CLOTH_AT_GUARD = {n: r.pose.bones[n].matrix_basis.copy() for n in CLOTH}

values = [None]*COUNT; rows = [None]*COUNT; twists = guard_twists.copy()
for i in reversed(range(COUNT)):
    t = i/24
    legclamp, ankles = body(t, twists)
    reach_r = sm((t-.95)/.37); settle_r = sm((t-1.49)/.57)
    rp, rq = right_target(t)
    lp, lq, wl = left_target(t)
    clamps = [arm('R', rp, rq, reach_r, settle_r, twists), arm('L', lp, lq, wl, wl, twists)]
    hands.apply_fingers('R', float(np.clip(f1(t, [(0, .20), (.92, .20), (1.10, 0.0), (1.30, .05), (1.40, 1.0), (3.0, 1.0)]), 0, 1)))
    hands.apply_fingers('L', float(np.clip(f1(t, [(0, .20), (1.85, .15), (2.05, 1.0), (3.0, 1.0)]), 0, 1)))
    bpy.context.view_layer.update()
    continuous_attack_skirt(); collision_adjust(stride=3, iterations=5); fit_cardigan()
    for n in CLOTH:
        pb = r.pose.bones[n]; pb.matrix_basis = guard_basis[n]@CLOTH_AT_GUARD[n].inverted()@pb.matrix_basis
    bpy.context.view_layer.update()
    basis = current_basis()
    w_end = sm((t-2.70)/.30)
    if w_end > 0:
        for n, m in basis.items():
            a, b = m.decompose(), guard_basis[n].decompose()
            basis[n] = Matrix.LocRotScale(a[0].lerp(b[0], w_end), a[1].slerp(b[1], w_end), a[2].lerp(b[2], w_end))
        restore(basis)
    pose = current_pose()
    rc = pose['DEF-hand.R']@OFFSET; ax = (pose['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
    lc = pose['DEF-hand.L']@LEFT_OFFSET
    rows[i] = {'frame': i+1, 'seconds': t, 'arm_clamp_m': max(clamps), 'leg_clamp_m': legclamp,
               'right_float_error_m': (rc-float_center).length, 'right_float_axis_deg': math.degrees(ax.angle(float_axis)),
               'two_hand_error_m': (lc-rc+ax*.26).length,
               'foot_error_m': {side: (pose['DEF-foot.'+side].translation-ankles[side]).length for side in ('L', 'R')},
               'right_step_m': (ankles['R']-guard['DEF-foot.R'].translation).length,
               'pelvis_m': list(pose['DEF-pelvis'].translation), 'head_quat': list(pose['DEF-head'].to_quaternion()),
               'wrong_finger_curls': sum(len(check.anatomy_sample(r, side, HAND_FRAMES[side], 3, 0)['wrong_direction_joints']) for side in ('L', 'R'))}
    values[i] = basis
    if i % 8 == 0: print('V26_POSE', i+1, flush=True)

grasp = max(rows[33], rows[34], key=lambda x: x['right_float_error_m'])   # 1.375s / 1.417s bracket the 1.40s attach
end_diff = max(abs(values[-1][n][a][b]-guard_basis[n][a][b]) for n in guard_basis for a in range(4) for b in range(4))
checks = {
    'arm_clamp_max_m': max(x['arm_clamp_m'] for x in rows),
    'leg_clamp_max_m': max(x['leg_clamp_m'] for x in rows),
    'grasp_center_error_m': grasp['right_float_error_m'], 'grasp_axis_error_deg': grasp['right_float_axis_deg'],
    'two_hand_error_after_2_10_max_m': max(x['two_hand_error_m'] for x in rows if x['seconds'] >= 2.10),
    'planted_left_foot_max_m': max(x['foot_error_m']['L'] for x in rows),
    'right_foot_ik_max_m': max(x['foot_error_m']['R'] for x in rows),
    'end_basis_max_abs_diff': end_diff,
    'wrong_finger_curls': sum(x['wrong_finger_curls'] for x in rows),
}
print('V26_CHECKS', json.dumps(checks), flush=True)
assert checks['arm_clamp_max_m'] < .001 and checks['leg_clamp_max_m'] < .0001, checks
assert checks['grasp_center_error_m'] < .0005 and checks['grasp_axis_error_deg'] < .2, checks
assert checks['two_hand_error_after_2_10_max_m'] < .003, checks
assert checks['end_basis_max_abs_diff'] < 1e-6, checks
assert checks['wrong_finger_curls'] == 0, checks
action = write_action(CLIP, values, [-.26]*COUNT)
after = check.snapshot(r.name, set())
assert BASELINE['meshes'] == after['meshes'] and BASELINE['rig'] == after['rig']
assert all(after['actions'][name] == digest for name, digest in BASELINE['actions'].items())
check.sample_action(r, action, 1); r['staff_slide_v18'] = -.26
s.frame_start = 1; s.frame_end = COUNT; s.render.fps = 24
output = FOLDER/'transformation_v26.blend'; bpy.ops.wm.save_as_mainfile(filepath=str(output))
contract = {**V25, 'clip': CLIP, 'staff_slide_tracks': {CLIP: [-.26]*COUNT},
            'source_blend': output.relative_to(ROOT).as_posix(), 'source_blend_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'authoring': 'Whole-body entry: gaze, breath, weight shift, planted half step, catch dip, anticipation/overshoot; same v25 events and floating staff frame.'}
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract, indent=2), encoding='utf-8')
(REPORT_DIR/'build_validation.json').write_text(json.dumps({'passed': True, 'checks': checks, 'preserved_meshes': len(BASELINE['meshes']),
    'preserved_actions': len(BASELINE['actions']), 'rest_bones': len(r.data.bones), 'rows': rows, 'source_sha256': contract['source_blend_sha256']}, indent=2), encoding='utf-8')
print('TRANSFORMATION_V26_BUILD_COMPLETE', json.dumps(checks), flush=True)
