"""Two-hand staff adaptation of the preserved v15 external-motion candidates.

Separate background Blender process; only the v16 candidate/report files are written.
"""
from pathlib import Path
import sys, json, math, hashlib, ast, time
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / 'assets/characters/player/3d/source/middle_school_v1/combat_motion_v15/combat_motion_v15.blend'
FOLDER = ROOT / 'assets/characters/player/3d/source/middle_school_v1/two_hand_v16'
REPORT_DIR = ROOT / 'reports/two_hand_v16/author'
OUTPUT = FOLDER / 'two_hand_v16.blend'
PROTOTYPE = '--prototype' in sys.argv
FOLDER.mkdir(parents=True, exist_ok=True); REPORT_DIR.mkdir(parents=True, exist_ok=True)
assert bpy.app.background
assert hashlib.sha256(INPUT.read_bytes()).hexdigest() == 'c5ff00e6d36bebcee2fa208344e4f82773b656220018e97b0ac7d11ba0f9e6f7'
if Path(bpy.data.filepath).resolve() != INPUT.resolve(): bpy.ops.wm.open_mainfile(filepath=str(INPUT))

helper = (ROOT / 'tools/build_combat_animations_v12.py').read_text(encoding='utf-8').split('CLIPS=')[0]
helper = helper.replace('source_outfit_v11/source_outfit_v11.blend','combat_motion_v15/combat_motion_v15.blend')
helper = helper.replace("(ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_animation_v12')", "(ROOT/'assets/characters/player/3d/source/middle_school_v1/two_hand_v16')")
helper = helper.replace("(ROOT/'reports/combat_animation_v12/animation_agent')", "(ROOT/'reports/two_hand_v16/author')")
helper = helper.replace("baseline_meshes={o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'};baseline_rig=rig_signature();baseline_actions={a.name:action_digest(a) for a in bpy.data.actions}", '')
exec(compile(helper, str(ROOT / 'tools/build_combat_animations_v12.py'), 'exec'), globals())
sys.path.insert(0, str(ROOT / 'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
hands=AnatomicalHandRig(r)
BASELINE=check.snapshot(r.name,set()) if not PROTOTYPE else None
CONTRACT=json.loads((INPUT.parent/'motion_contract.json').read_text(encoding='utf-8'))
ATTACHMENT=CONTRACT['staff_attachment']
OFFSET=Vector(ATTACHMENT['offset_bone_local'])
STAFF_BASIS=Matrix(ATTACHMENT['basis_columns_bone_local']).transposed()
STAFF_LOCAL_AXIS=STAFF_BASIS@Vector((0,1,0))
SPECS=[('idle','trial_quaternius_idle_staff_v15',49),('attack','trial_quaternius_attack_staff_v15',25),
       ('cast','trial_mixamo_cast_staff_v15',33),('hit','trial_quaternius_hit_staff_v15',13)]
check.sample_action(r,bpy.data.actions[SPECS[0][1]],1)
IDLE={p.name:p.matrix.copy() for p in r.pose.bones}
IDLE_BASIS={p.name:p.matrix_basis.copy() for p in r.pose.bones}
OLD_CENTER=IDLE['DEF-hand.R']@OFFSET
OLD_AXIS=(IDLE['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
OLD_CHEST=IDLE['DEF-chest'].to_quaternion()
GUARD_CENTER=Vector((-.115,-.285,1.075))
GUARD_AXIS=Vector((.72,-.12,.68)).normalized()
GUARD_RQ=OLD_AXIS.rotation_difference(GUARD_AXIS)@IDLE['DEF-hand.R'].to_quaternion()
LEFT_SPACING=.26
LEFT_OFFSET=sum((hands.axes['L'][key]*OFFSET.dot(hands.axes['R'][key]) for key in ('thumb','finger','palm')),Vector())
HAND_FRAMES={side:check.hand_frame(r,side,Vector((-1,0,0))) for side in ('L','R')}

def restore(data):
    r.animation_data.action=None
    for name,matrix in data.items():r.pose.bones[name].matrix_basis=matrix
    bpy.context.view_layer.update()

def pose_source(name,frame):
    check.sample_action(r,bpy.data.actions[name],frame)
    return {p.name:p.matrix.copy() for p in r.pose.bones},{p.name:p.matrix_basis.copy() for p in r.pose.bones}

def cage_center(side):
    points=[]
    for finger in check.FINGERS:
        bones=[r.pose.bones[f'DEF-{finger}.{i:02}.{side}'] for i in range(1,4)]
        points += [bones[0].head.copy()]+[b.tail.copy() for b in bones]
    return sum(points,Vector())/len(points)

def two_hand_pose(kind,phase,source,twists):
    # Staff placement is shared; both arms solve to the same rigid prop.
    chest_delta=source['DEF-chest'].to_quaternion()@OLD_CHEST.inverted()
    source_center=source['DEF-hand.R']@OFFSET
    source_axis=(source['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
    if kind in ('idle','hit'):
        center=source['DEF-chest'].translation+chest_delta@(GUARD_CENTER-IDLE['DEF-chest'].translation)
        axis=chest_delta@GUARD_AXIS
        qright=chest_delta@GUARD_RQ
    else:
        # Keep the source preparation/release timing and restrained local travel.
        center=GUARD_CENTER+(source_center-OLD_CENTER)*.32
        source_delta=OLD_AXIS.rotation_difference(source_axis)
        if source_delta.w<0:source_delta.negate()
        rotation=Quaternion().slerp(source_delta,.43)
        axis=(rotation@GUARD_AXIS).normalized()
        qright=rotation@GUARD_RQ
    # Avoid a high face-level grip and keep both wrists within useful reach.
    center.y=min(center.y,-.24)
    center.z=min(1.14,max(1.00,center.z))
    # The mirrored left hand closes around the shaft with opposing palm normals.
    right_finger=qright@hands.axes['R']['finger']
    right_palm=qright@hands.axes['R']['palm']
    qleft=hands.orientation('L',right_finger,-right_palm)
    # Move the common prop, rather than allowing either hand to detach at an
    # IK reach clamp. Alternating sphere projections keep a useful elbow bend.
    requested_center=center.copy()
    for _ in range(16):
        for side,qhand,axial,offset in [('R',qright,0.,OFFSET),('L',qleft,LEFT_SPACING,LEFT_OFFSET)]:
            shoulder=source['DEF-upper_arm.'+side].translation
            allowed_center=shoulder-axis*axial+qhand@offset
            reach=CHAIN['DEF-upper_arm.'+side][1]+CHAIN['DEF-forearm.'+side][1]-.025
            delta=center-allowed_center
            if delta.length>reach:center=allowed_center+delta.normalized()*reach
    desired={};targets={};clamps=[]
    for side,qhand,grip,offset in [('R',qright,center,OFFSET),('L',qleft,center+axis*LEFT_SPACING,LEFT_OFFSET)]:
        name='DEF-upper_arm.'+side;fore='DEF-forearm.'+side;hand='DEF-hand.'+side
        shoulder=source[name].translation
        target=grip-qhand@offset
        pole=Vector((.45 if side=='L' else -.45,.12,-1.))
        elbow,wrist=solve_ik(shoulder,target,CHAIN[name][1],CHAIN[fore][1],pole)
        qa=source[name].to_quaternion();qf=source[fore].to_quaternion()
        qa=(qa@Vector((0,1,0))).rotation_difference((elbow-shoulder).normalized())@qa
        qf=(qf@Vector((0,1,0))).rotation_difference((wrist-elbow).normalized())@qf
        qa.normalize();qf.normalize();qhand.normalize()
        chain_desired(name,shoulder,elbow,qa,qf,desired,twists)
        chain_desired(fore,elbow,wrist,qf,qhand,desired,twists)
        desired[hand]=Matrix.LocRotScale(wrist,qhand,Vector((1,1,1)))
        clamps.append((wrist-target).length);targets[side]=grip
    apply_desired(desired)
    for side in ('R','L'):
        hands.apply_wrist(side,desired['DEF-hand.'+side].to_quaternion(),twists)
        hands.apply_fingers(side,1.)
    actual_center=r.pose.bones['DEF-hand.R'].matrix@OFFSET
    actual_axis=(r.pose.bones['DEF-hand.R'].matrix.to_3x3()@STAFF_LOCAL_AXIS).normalized()
    left_actual=r.pose.bones['DEF-hand.L'].matrix@LEFT_OFFSET
    return {'staff_center':list(actual_center),'staff_axis':list(actual_axis),
        'left_grip_target':list(actual_center+actual_axis*LEFT_SPACING),'left_grip_actual':list(left_actual),
        'left_grip_target_error_m':(left_actual-actual_center-actual_axis*LEFT_SPACING).length,
        'maximum_ik_clamp_m':max(clamps),
        'shared_staff_reach_correction_m':(center-requested_center).length,
        'finger_cage_axial_error_m':{side:abs((cage_center(side)-actual_center).dot(actual_axis)-(LEFT_SPACING if side=='L' else 0.)) for side in ('L','R')},
        'finger_cage_axis_distance_m':{side:check.line_distance(cage_center(side),actual_center,actual_axis) for side in ('L','R')}}

def staff_clearance(record):
    center=Vector(record['staff_center']);axis=Vector(record['staff_axis']);hits=[]
    # Remove both intentional grip intervals from shaft/body centerline tests.
    intervals=[(-.42,-.08),(.08,LEFT_SPACING-.08),(LEFT_SPACING+.08,.78)]
    for name in ['Body_Torso_v7','Body_Pelvis_v7','Face_Core_v8','Body_Arms_v7']:
        obj=bpy.data.objects[name];ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        tree=BVHTree.FromPolygons([ev.matrix_world@v.co for v in ev.data.vertices],[list(p.vertices) for p in ev.data.polygons])
        for a,b in intervals:
            result=tree.ray_cast(center+axis*a,axis,b-a)
            if result[0] is not None:hits.append({'mesh':name,'axial_m':a+result[3]})
    return hits

def render(name,frame):
    s.camera.animation_data_clear();s.camera.constraints.clear();s.camera.data.ortho_scale=2.25
    s.camera.location=(2.5,-5,1.7);s.camera.rotation_euler=(Vector((0,-.12,.98))-s.camera.location).to_track_quat('-Z','Y').to_euler()
    s.render.engine='BLENDER_EEVEE';s.render.resolution_x=560;s.render.resolution_y=700;s.render.resolution_percentage=100
    s.render.filepath=str(REPORT_DIR/f'{name}_{frame:03}.png');bpy.ops.render.render(write_still=True)

if PROTOTYPE:
    observations=[]
    for kind,clip,frame in [('idle',SPECS[0][1],1),('attack',SPECS[1][1],13),('cast',SPECS[2][1],17)]:
        source,basis=pose_source(clip,frame);restore(basis)
        rec=two_hand_pose(kind,0 if kind=='idle' else .5,source,{})
        rec['shaft_body_crossings']=staff_clearance(rec)
        rec['kind']=kind;rec['frame']=frame;observations.append(rec)
        render('prototype_'+kind,frame)
    (REPORT_DIR/'prototype.json').write_text(json.dumps({'left_offset':list(LEFT_OFFSET),'grip_spacing':LEFT_SPACING,'observations':observations},indent=2),encoding='utf-8')
    print('TWO_HAND_V16_PROTOTYPE_COMPLETE',flush=True)
    raise SystemExit(0)

from idle_skirt_fix_v16 import IdleSkirtFix
skirt_fix=IdleSkirtFix(r,IDLE_BASIS)
def idle_cloth():
    skirt_fix.apply()
    # The former inflated skirt also pushed cardigan hem helper keys outward.
    # Calm idle retains the accepted local hem offset and follows its parents.
    for name in HELPERS:r.pose.bones[name].matrix_basis=IDLE_BASIS[name]
    bpy.context.view_layer.update()
source,idle_basis=pose_source(SPECS[0][1],1);restore(idle_basis)
two_hand_pose('idle',0,source,{})
idle_cloth()
NEW_IDLE_BASIS={p.name:p.matrix_basis.copy() for p in r.pose.bones}
reports={};target_hashes={}
for kind,source_name,count in SPECS:
    samples=[pose_source(source_name,frame) for frame in range(1,count+1)]
    values=[];rows=[];twists={}
    for index,(source,basis) in enumerate(samples):
        restore(basis)
        rec=two_hand_pose(kind,index/(count-1),source,twists)
        if kind=='idle':idle_cloth()
        if index in (0,count-1):restore(NEW_IDLE_BASIS)
        rec['frame']=index+1
        rec['shaft_body_crossings']=staff_clearance(rec)
        rec['hand_anatomy']={side:check.anatomy_sample(r,side,HAND_FRAMES[side],3,0) for side in ('L','R')}
        rec['finite_pose']=all(check.finite_matrix(p.matrix) and check.finite_matrix(p.matrix_basis) for p in r.pose.bones)
        rec['max_limb_length_error_m']=max(abs((r.pose.bones['DEF-'+last+'.'+side].head-r.pose.bones['DEF-'+first+'.'+side].head).length-CHAIN['DEF-'+first+'.'+side][1]) for side in ('L','R') for first,last in [('upper_arm','forearm'),('forearm','hand'),('thigh','shin'),('shin','foot')])
        values.append({p.name:p.matrix_basis.copy() for p in r.pose.bones});rows.append(rec)
    name='trial_two_hand_'+kind+'_v16';action=bpy.data.actions.new(name);action.use_fake_user=True;r.animation_data.action=action;previous={}
    for frame,bases in enumerate(values,1):
        for bone,matrix in bases.items():
            pb=r.pose.bones[bone];loc,q,scale=matrix.decompose()
            if bone in previous and q.dot(previous[bone])<0:q.negate()
            previous[bone]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=scale
            for channel in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=channel,frame=frame,group=bone)
    for curve in check.curves(action):
        for key in curve.keyframe_points:key.interpolation='LINEAR'
    action['combat_loop']=kind=='idle';action['two_hand_grip_spacing_m']=LEFT_SPACING
    action['intermediate_source_action']=source_name
    if kind in ('attack','cast'):action['event_normalized']=.5;action['event_frame']=(count+1)//2
    track=r.animation_data.nla_tracks.new();track.name=name;track.mute=True
    strip=track.strips.new(name,1,action);strip.action_slot=action.slots[0]
    target_hashes[name]=check.action_digest(action)
    report={'frames':count,'duration_seconds':(count-1)/24,'loop':kind=='idle','source_action':source_name,
        'source_action_sha256':BASELINE['actions'][source_name],'action_sha256':target_hashes[name],
        'maximum_left_grip_error_m':max(x['left_grip_target_error_m'] for x in rows),
        'maximum_ik_clamp_m':max(x['maximum_ik_clamp_m'] for x in rows),
        'maximum_limb_length_error_m':max(x['max_limb_length_error_m'] for x in rows),
        'maximum_cage_axis_distance_m':max(v for x in rows for v in x['finger_cage_axis_distance_m'].values()),
        'maximum_cage_axial_error_m':max(v for x in rows for v in x['finger_cage_axial_error_m'].values()),
        'shaft_crossing_frames':[x['frame'] for x in rows if x['shaft_body_crossings']],
        'wrong_direction_samples':sum(len(a['wrong_direction_joints']) for x in rows for a in x['hand_anatomy'].values()),
        'all_poses_finite':all(x['finite_pose'] for x in rows),'rows':rows}
    reports[name]=report
    (REPORT_DIR/'in_progress_validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    print('TWO_HAND_CLIP_BAKED',name,report['maximum_left_grip_error_m'],report['shaft_crossing_frames'],flush=True)
    assert report['maximum_left_grip_error_m']<.001 and report['maximum_ik_clamp_m']<.001, name
    assert report['wrong_direction_samples']==0 and report['all_poses_finite'],name
    assert report['maximum_limb_length_error_m']<.00005,name
    assert report['maximum_cage_axis_distance_m']<.007 and report['maximum_cage_axial_error_m']<.01,name
    assert not report['shaft_crossing_frames'],(name,report['shaft_crossing_frames'])

after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][name]==sha for name,sha in BASELINE['actions'].items())
assert len(after['actions'])==44
check.sample_action(r,bpy.data.actions['trial_two_hand_idle_v16'],1)
s.frame_start=1;s.frame_end=49;s.render.fps=24
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
output_sha=hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
report={'passed':True,'source':str(INPUT),'source_sha256':CONTRACT['expected_source_sha256'],'output':str(OUTPUT),'output_sha256':output_sha,
    'protected_meshes':29,'protected_actions':40,'rest_bones':107,'left_spacing_m':LEFT_SPACING,'left_offset_bone_local':list(LEFT_OFFSET),
    'staff_attachment':ATTACHMENT,'clips':reports,
    'scope':'Two-hand pose constraint and centerline/body proxies; not full skin/garment contact clearance or final art approval.'}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
contract={'expected_source_sha256':output_sha,'protected_baseline_sha256':CONTRACT['expected_source_sha256'],'expected_bones':107,
    'staff_attachment':ATTACHMENT,'clips':{name:{'frames':item['frames'],'loop':item['loop'],'action_sha256':item['action_sha256']} for name,item in reports.items()},
    'external_clips':list(reports),'status':'two_hand_comparison','selected_run_unchanged':'trial_quaternius_run_compact',
    'left_hand_grip':{'spacing_from_right_m':LEFT_SPACING,'offset_bone_local':list(LEFT_OFFSET)}}
contract['secondary_grip']={'bone':'DEF-hand.L','shaft_axial_m':LEFT_SPACING,'max_cage_axis_distance_m':.007,'max_axial_error_m':.01}
(FOLDER/'motion_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
provenance=json.loads((ROOT/'reports/combat_motion_v15/provenance.json').read_text(encoding='utf-8'))
mapping={source:'trial_two_hand_'+kind+'_v16' for kind,source,_ in SPECS}
for entry in provenance['sources']:
    for target in entry['target_clips']:
        old=target['name'];new=mapping[old]
        target.update({'name':new,'action_sha256':target_hashes[new],'intermediate_action_name':old,'intermediate_action_sha256':BASELINE['actions'][old]})
    entry['intermediate_source_file']=str(INPUT);entry['intermediate_source_sha256']=CONTRACT['expected_source_sha256']
(REPORT_DIR/'provenance.json').write_text(json.dumps(provenance,indent=2),encoding='utf-8')
for kind,_,count in SPECS:
    clip='trial_two_hand_'+kind+'_v16'
    for frame in [1,(count+1)//2,count]:
        check.sample_action(r,bpy.data.actions[clip],frame);render(kind,frame)
print('TWO_HAND_V16_COMPLETE',output_sha,flush=True)
