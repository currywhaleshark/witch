"""Reopen the run correction: preservation, hinge plane, grip and loop checks."""
from pathlib import Path
import bpy,sys,json,math,hashlib
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/run_arm_v21';sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
import staff_contact_v20 as contact
source=ROOT/'assets/characters/player/3d/source/middle_school_v1/run_arm_v21/run_arm_v21.blend'
assert bpy.app.background;bpy.ops.wm.open_mainfile(filepath=str(source));r=bpy.data.objects['PlayerRig_v7'];scene=bpy.context.scene
baseline=json.loads((OUT/'protected_baseline.json').read_text());after=check.snapshot(r.name,set())
assert baseline['meshes']==after['meshes'] and baseline['rig']==after['rig']
assert len(baseline['actions'])==58 and all(after['actions'][n]==h for n,h in baseline['actions'].items())
contract=json.loads((source.parent/'runtime_contract.json').read_text())
hands=AnatomicalHandRig(r);off=Vector(contract['staff_attachment']['offset_bone_local']);axis_local=Matrix(contract['staff_attachment']['basis_columns_bone_local']).transposed()@Vector((0,1,0))
leftoff=sum((hands.axes['L'][k]*off.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
frames={side:check.hand_frame(r,side,Vector((-1,0,0))) for side in ('L','R')}
arm_names={p.name for p in r.pose.bones if any(p.name.startswith('DEF-'+stem+'.') for stem in ('upper_arm','forearm','hand','thumb','index','middle','ring','pinky'))}

def sample(name,f):
    check.sample_action(r,bpy.data.actions[name],int(f));scene.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update()
    return {p.name:p.matrix.copy() for p in r.pose.bones}

def geometry(pose):
    arms={}
    chest=r.pose.bones['DEF-chest'].matrix.to_quaternion() @ r.data.bones['DEF-chest'].matrix_local.to_quaternion().inverted()
    for side in ('R','L'):
        an,fn,hn=['DEF-'+stem+'.'+side for stem in ('upper_arm','forearm','hand')]
        a,b,c=[pose[n].translation for n in (an,fn,hn)]
        ra,rb,rc=[r.data.bones[n].matrix_local.translation for n in (an,fn,hn)]
        rest_normal=(rb-ra).cross(rc-rb).normalized();normal=(b-a).cross(c-b).normalized()
        hinge_errors=[]
        for n in (an,fn):
            transformed=pose[n].to_quaternion() @ r.data.bones[n].matrix_local.to_quaternion().inverted() @ rest_normal
            hinge_errors.append(math.degrees(transformed.angle(normal)))
        arms[side]={'flexion_degrees':math.degrees((b-a).angle(c-b)),
            'upper_arm_from_down_degrees':math.degrees((b-a).angle(chest@Vector((0,0,-1)))),
            'upper_arm_from_world_down_degrees':math.degrees((b-a).angle(Vector((0,0,-1)))),
            'wrist_deflection_degrees':math.degrees((c-b).angle(pose[hn].to_quaternion()@Vector((0,1,0)))),
            'hinge_normal_errors_degrees':hinge_errors,'elbow':list(b)}
    return arms

rows=[];failures=[];first=None;nonarm_max=0.;largest_step=0.;largest_rotation=0.;previous=None;previous_pose=None
for i in range(193):
    f=1+i/2
    old=sample('combat_run_rh_v20',f);old_geometry=geometry(old)
    pose=sample('combat_run_rh_v21',f);g=geometry(pose)
    right=pose['DEF-hand.R']@off;left=pose['DEF-hand.L']@leftoff;axis=(pose['DEF-hand.R'].to_3x3()@axis_local).normalized()
    nonarm=max(abs(pose[n][a][b]-old[n][a][b]) for n in pose if n not in arm_names for a in range(4) for b in range(4));nonarm_max=max(nonarm_max,nonarm)
    wrong=sum(len(check.anatomy_sample(r,side,frames[side],3,0)['wrong_direction_joints']) for side in ('R','L'))
    row={'frame':f,'new':g,'before':old_geometry,'grip_error_m':(left-right+axis*.26).length,'left_axial_m':(left-right).dot(axis),'wrong_finger_curls':wrong,'non_arm_world_matrix_error':nonarm,'slide_m':float(r['staff_slide_v18'])}
    if previous:
        row['maximum_elbow_step_m']=max((Vector(g[side]['elbow'])-Vector(previous[side]['elbow'])).length for side in ('R','L'))
        largest_step=max(largest_step,row['maximum_elbow_step_m'])
        angles=[math.degrees(previous_pose[n].to_quaternion().rotation_difference(pose[n].to_quaternion()).angle) for n in arm_names]
        row['maximum_arm_rotation_step_degrees']=max(min(a,360-a) for a in angles)
        largest_rotation=max(largest_rotation,row['maximum_arm_rotation_step_degrees'])
    if first is None:first=pose
    if i==192:loop_error=max(abs(pose[n][a][b]-first[n][a][b]) for n in pose for a in range(4) for b in range(4))
    if wrong or row['grip_error_m']>.003 or row['left_axial_m']>-.25 or abs(row['slide_m']+.26)>1e-5:failures.append([f,'hand/shaft'])
    if any(max(g[side]['hinge_normal_errors_degrees'])>.5 or g[side]['upper_arm_from_world_down_degrees']>55 or g[side]['wrist_deflection_degrees']>55 or g[side]['flexion_degrees']>140 for side in ('R','L')):failures.append([f,'arm articulation',g])
    if not all(check.finite_matrix(m) for m in pose.values()):failures.append([f,'nonfinite'])
    rows.append(row);previous=g;previous_pose=pose
    if i%48==0:print('V21_REOPEN_POSE',f,flush=True)
if nonarm_max>2e-5 or loop_error>1e-5 or largest_step>.015 or largest_rotation>20:failures.append(['preservation/continuity',nonarm_max,loop_error,largest_step,largest_rotation])
report={'passed':not failures,'failures':failures,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'preserved_meshes':29,'preserved_actions':58,'rest_bones':107,'samples':len(rows),'maximum_grip_error_m':max(x['grip_error_m'] for x in rows),'non_arm_world_matrix_error':nonarm_max,'loop_matrix_error':loop_error,'maximum_half_sample_elbow_step_m':largest_step,'rows':rows,'scope':'Run-only stored bone interpolation and anatomy checks. Hinge normal, wrist deflection and elbow step are diagnostic proxies; visual approval is separate.'}
report['maximum_half_sample_arm_rotation_degrees']=largest_rotation
(OUT/'independent_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert not failures,failures[:3]
contact.append_transformed(ROOT,r);contacts=[]
for i in range(25):
    f=1+4*i;pose=sample('combat_run_rh_v21',f)
    c=pose['DEF-hand.R']@off;axis=(pose['DEF-hand.R'].to_3x3()@axis_local).normalized()
    probe=contact.probe(c,axis,-.26,-.26,contact.trees(contact.CORE+contact.CIVILIAN+contact.TRANSFORMED),step=.005)
    contacts.append({'frame':f,**probe})
cross=[x['frame'] for x in contacts if x['shaft_crossings']]
minimum=min(x['minimum_probe_clearance_m'] for x in contacts)
result={'passed':not cross and minimum>=.003,'samples':25,'crossing_frames':cross,'minimum_clearance_m':minimum,'rows':contacts,'scope':'25 run samples, evaluated core/civilian/transformed surfaces; same shaft/head and intentional cuff/hand exclusions as v20. Not a general cloth-body collision test.'}
(OUT/'run_contact.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
assert result['passed'],(cross,minimum)
print('RUN_ARM_V21_VALIDATED',report['samples'],minimum,flush=True)
