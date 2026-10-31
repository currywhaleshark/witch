"""Measure the saved entry arm chains, independently of the authoring solver."""
import ast, json, math, sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig

args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
label = args[0] if args else 'after'
out = ROOT/'reports/transformation_v25/arm_fix'
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/characters/player/3d/source/middle_school_v1/transformation_v25/transformation_v25.blend'))
r = bpy.data.objects['PlayerRig_v7']
REST = {b.name:b.matrix_local.copy() for b in r.data.bones}
INV = {n:m.inverted() for n,m in REST.items()}
module = ast.parse((ROOT/'tools/build_run_arm_v21.py').read_text(encoding='utf-8'))
defs = [n for n in module.body if isinstance(n,ast.FunctionDef) and n.name in ('hinge_frame','hinge_rotations','arm_measure')]
exec(compile(ast.Module(body=defs,type_ignores=[]),'v21_hinge_metrics','exec'),globals())
hands = AnatomicalHandRig(r)
action = bpy.data.actions['combat_transform_entry_v25']
rows=[]; previous={}
for i in range(145):
    frame=1+i/2
    check.sample_action(r,action,int(frame))
    bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame))
    bpy.context.view_layer.update()
    pose={p.name:p.matrix.copy() for p in r.pose.bones}
    arms=arm_measure(pose)
    for side,arm in arms.items():
        hand=pose['DEF-hand.'+side].to_quaternion()
        arm['palm_inward_dot']=(hand@hands.axes[side]['palm']).dot(Vector((1 if side=='R' else -1,0,0)))
        changes=[]
        for stem in ('upper_arm','forearm','hand'):
            for suffix in (('',) if stem=='hand' else ('','.001','.002')):
                name='DEF-'+stem+'.'+side+suffix
                q=pose[name].to_quaternion()
                if name in previous:
                    changes.append(math.degrees(2*math.acos(min(1,abs(q.dot(previous[name]))))))
                previous[name]=q
        arm['max_half_frame_turn_degrees']=max(changes,default=0)
    rows.append({'seconds':(frame-1)/24,'arms':arms})
first=rows[0]['arms']
summary={'label':label,'samples':145,'first':first,
    'max_half_frame_turn_degrees':max(a['max_half_frame_turn_degrees'] for row in rows for a in row['arms'].values()),
    'max_wrist_deflection_degrees':max(a['wrist_deflection_degrees'] for row in rows for a in row['arms'].values()),
    'rows':rows}
if label=='after':
    failures=[]
    for side,arm in first.items():
        if abs(arm['humerus_hinge_roll_error_degrees'])>1: failures.append(side+': upper arm roll')
        if abs(arm['ulna_hinge_roll_error_degrees'])>1: failures.append(side+': elbow roll')
        if arm['palm_inward_dot']<.9: failures.append(side+': palm not inward')
        if arm['wrist_deflection_degrees']>30: failures.append(side+': bent resting wrist')
        if not 10<arm['flexion_degrees']<45: failures.append(side+': resting elbow flexion')
    if summary['max_half_frame_turn_degrees']>15: failures.append('arm discontinuity')
    summary.update(passed=not failures,failures=failures)
(out/(label+'.json')).write_text(json.dumps(summary,indent=2),encoding='utf-8')
print('ENTRY_ARM_AUDIT',json.dumps({k:v for k,v in summary.items() if k!='rows'}),flush=True)
if label=='after': assert summary['passed'],summary['failures']
