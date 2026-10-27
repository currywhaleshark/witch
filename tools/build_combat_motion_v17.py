"""Preserve v16; add a two-hand compact run, planted attack and one-hand cast.

Background Blender only. No geometry, old action, bind or game mapping edits.
"""
from pathlib import Path
import sys, json, math, hashlib, copy
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
prefix = (ROOT/'tools/build_two_hand_v16.py').read_text(encoding='utf-8').split('if PROTOTYPE:')[0]
prefix = prefix.replace("INPUT = ROOT / 'assets/characters/player/3d/source/middle_school_v1/combat_motion_v15/combat_motion_v15.blend'", "INPUT = ROOT / 'assets/characters/player/3d/source/middle_school_v1/two_hand_v16/two_hand_v16.blend'")
prefix = prefix.replace("FOLDER = ROOT / 'assets/characters/player/3d/source/middle_school_v1/two_hand_v16'", "FOLDER = ROOT / 'assets/characters/player/3d/source/middle_school_v1/combat_motion_v17'")
prefix = prefix.replace("REPORT_DIR = ROOT / 'reports/two_hand_v16/author'", "REPORT_DIR = ROOT / 'reports/combat_motion_v17/author'")
prefix = prefix.replace("OUTPUT = FOLDER / 'two_hand_v16.blend'", "OUTPUT = FOLDER / 'combat_motion_v17.blend'")
prefix = prefix.replace('c5ff00e6d36bebcee2fa208344e4f82773b656220018e97b0ac7d11ba0f9e6f7', '667e2e3aea7aaf0eebf025eee8b457846564e7be3aff0443ef01e5ba1414c640')
prefix = prefix.replace("'combat_motion_v15/combat_motion_v15.blend')", "'two_hand_v16/two_hand_v16.blend')")
prefix = prefix.replace("\"(ROOT/'assets/characters/player/3d/source/middle_school_v1/two_hand_v16')\"", "\"(ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_motion_v17')\"")
prefix = prefix.replace("\"(ROOT/'reports/two_hand_v16/author')\"", "\"(ROOT/'reports/combat_motion_v17/author')\"")
prefix = prefix.replace("if kind in ('idle','hit'):", "if kind in ('idle','hit','run'):")
prefix = prefix.replace("center.z=min(1.14,max(1.00,center.z))", "if kind!='run':center.z=min(1.14,max(1.00,center.z))")
exec(compile(prefix, str(ROOT/'tools/build_two_hand_v16.py'), 'exec'), globals())

IDLE_TWO, IDLE_TWO_BASIS = pose_source('trial_two_hand_idle_v16', 1)
RUN_SOURCE = 'trial_quaternius_run_compact'
SPECS = [('run', RUN_SOURCE, 'trial_two_hand_run_v17',25),
         ('attack','trial_two_hand_attack_v16','trial_two_hand_attack_v17',25),
         ('cast','trial_mixamo_cast_staff_v15','trial_one_hand_cast_v17',33)]
FAMILY = [('idle','trial_two_hand_idle_v16',49),('run','trial_two_hand_run_v17',25),
          ('attack','trial_two_hand_attack_v17',25),('cast','trial_one_hand_cast_v17',33),
          ('hit','trial_two_hand_hit_v16',13)]
ARM_BONES = {p.name for p in r.pose.bones if any(p.name.startswith('DEF-'+stem+'.') for stem in ('upper_arm','forearm','hand','thumb','index','middle','ring','pinky'))}
shoe = bpy.data.objects['Outfit_Shoes_v7']
shoe_ids = {side:[v.index for v in shoe.data.vertices if (v.co.x>0)==(side=='L')] for side in ('L','R')}

def current_basis(): return {p.name:p.matrix_basis.copy() for p in r.pose.bones}
def current_pose(): return {p.name:p.matrix.copy() for p in r.pose.bones}
def matrix_error(a,b,names): return max(abs(a[n][i][j]-b[n][i][j]) for n in names for i in range(4) for j in range(4))
def shoes():
    ev=shoe.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return {side:min((ev.matrix_world@ev.data.vertices[i].co).z for i in ids) for side,ids in shoe_ids.items()}

def support_record():
    center=r.pose.bones['DEF-hand.R'].matrix@OFFSET
    axis=(r.pose.bones['DEF-hand.R'].matrix.to_3x3()@STAFF_LOCAL_AXIS).normalized()
    return {'staff_center':list(center),'staff_axis':list(axis),
            'left_grip_target_error_m':(r.pose.bones['DEF-hand.L'].matrix@LEFT_OFFSET-center-axis*LEFT_SPACING).length,
            'finger_cage_axis_distance_m':{side:check.line_distance(cage_center(side),center,axis) for side in ('L','R')},
            'finger_cage_axial_error_m':{side:abs((cage_center(side)-center).dot(axis)-(LEFT_SPACING if side=='L' else 0)) for side in ('L','R')}}

def continuous_attack_skirt():
    pelvis=r.pose.bones['DEF-pelvis'];delta=pelvis.matrix@INV['DEF-pelvis'];directions=[]
    for side in ('L','R'):
        d=delta.to_3x3().inverted()@(r.pose.bones['DEF-shin.'+side].head-r.pose.bones['DEF-thigh.'+side].head).normalized()
        horizontal=Vector((d.x,d.y,0))
        if horizontal.length>.001:directions.append((horizontal.normalized(),math.atan2(horizontal.length,-d.z)))
    for name in upper_names:
        pb=r.pose.bones[name];base=delta@REST[name]
        radial=Vector((pb.bone.head_local.x,pb.bone.head_local.y+.004,0)).normalized()
        dr=(pb.bone.tail_local-pb.bone.head_local).normalized();angle=math.atan2(math.hypot(dr.x,dr.y),-dr.z)
        for horizontal,tilt in directions:
            influence=math.exp(-(math.acos(max(-1,min(1,radial.dot(horizontal))))/math.radians(62))**2)
            angle=max(angle,min(math.radians(50),tilt+math.radians(8))*influence)
        direction=delta.to_3x3()@(radial*math.sin(angle)+Vector((0,0,-math.cos(angle))))
        q=(base.to_quaternion()@Vector((0,1,0))).rotation_difference(direction)@base.to_quaternion()
        target=Matrix.LocRotScale(base.translation,q,Vector((1,1,1)))
        pb.matrix_basis=INV[name]@REST['DEF-pelvis']@pelvis.matrix.inverted()@target
    bpy.context.view_layer.update();support_pose(lower_fraction=.8,neighbor=16)

def planted_attack(source,twists):
    pelvis=source['DEF-pelvis'].copy()
    idle_z=IDLE_TWO['DEF-pelvis'].translation.z
    pelvis.translation.z=idle_z+min(.002,(pelvis.translation.z-idle_z)*.30)
    # Keep enough knee flexion for both planted ankles; move the pelvis rather
    # than accepting an IK reach clamp that would slide either planted foot.
    for _ in range(32):
        change=pelvis@INV['DEF-pelvis']
        excess=max((change@REST['DEF-thigh.'+side].translation-IDLE_TWO['DEF-foot.'+side].translation).length-CHAIN['DEF-thigh.'+side][1]-CHAIN['DEF-shin.'+side][1]+.001 for side in ('L','R'))
        if excess<0: break
        pelvis.translation.z-=excess+.00001
    apply_desired({'DEF-pelvis':pelvis})
    desired={};clamps=[]
    for side in ('L','R'):
        thigh='DEF-thigh.'+side;shin='DEF-shin.'+side;foot='DEF-foot.'+side
        hip=r.pose.bones[thigh].head.copy();ankle=IDLE_TWO[foot].translation
        # Character forward is -Y. Slight inward bias matches the idle stance.
        knee,end=solve_ik(hip,ankle,CHAIN[thigh][1],CHAIN[shin][1],Vector((-.10 if side=='L' else .10,-1.,0.)))
        qa=IDLE_TWO[thigh].to_quaternion();qf=IDLE_TWO[shin].to_quaternion()
        qa=(qa@Vector((0,1,0))).rotation_difference((knee-hip).normalized())@qa
        qf=(qf@Vector((0,1,0))).rotation_difference((end-knee).normalized())@qf
        qfoot=IDLE_TWO[foot].to_quaternion()
        chain_desired(thigh,hip,knee,qa,qf,desired,twists)
        chain_desired(shin,knee,end,qf,qfoot,desired,twists)
        desired[foot]=IDLE_TWO[foot].copy();desired['DEF-toe.'+side]=IDLE_TWO['DEF-toe.'+side].copy()
        clamps.append((end-ankle).length)
    apply_desired(desired)
    # Continuous thigh-following replaces the historical 12-degree jump.
    # This local attack correction does not change the selected running cloth.
    for name in support_names+HELPERS:r.pose.bones[name].matrix_basis=IDLE_TWO_BASIS[name]
    bpy.context.view_layer.update()
    continuous_attack_skirt()
    collision_adjust(stride=2,iterations=6)
    return max(clamps)

def adapt(kind,frame,count,source,basis,twists):
    restore(basis);extra={}
    if kind=='run':
        extra=two_hand_pose('run',(frame-1)/(count-1),source,twists)
        extra['unchanged_non_arm_basis_max_error']=matrix_error(basis,current_basis(),set(basis)-ARM_BONES)
    elif kind=='attack':extra['maximum_ik_clamp_m']=planted_attack(source,twists)
    else:
        amount=sm((frame-1)/8)*sm((count-frame)/8)
        if amount<1:
            blended={}
            for name in basis:
                a,qa,sa=IDLE_TWO_BASIS[name].decompose();b,qb,sb=basis[name].decompose()
                blended[name]=Matrix.LocRotScale(a.lerp(b,amount),qa.slerp(qb,amount),sa.lerp(sb,amount))
            restore(blended)
        extra['one_hand_source_blend']=amount
        if 9<=frame<=25:extra['source_central_pose_max_error']=matrix_error(source,current_pose(),source)
    if kind!='run' and frame in (1,count):restore(IDLE_TWO_BASIS)
    rec=support_record();rec.update(extra)
    rec['frame']=frame;rec['support_required']=kind!='cast' or frame in (1,count)
    rec['knee_width_m']=abs(r.pose.bones['DEF-shin.L'].head.x-r.pose.bones['DEF-shin.R'].head.x)
    rec['ankle_width_m']=abs(r.pose.bones['DEF-foot.L'].head.x-r.pose.bones['DEF-foot.R'].head.x)
    rec['ankle_displacement_m']={side:(r.pose.bones['DEF-foot.'+side].head-IDLE_TWO['DEF-foot.'+side].translation).length for side in ('L','R')}
    rec['shoe_minima_m']=shoes()
    rec['shaft_body_crossings']=staff_clearance(rec)
    rec['hand_anatomy']={side:check.anatomy_sample(r,side,HAND_FRAMES[side],3,0) for side in ('L','R')}
    return rec

if PROTOTYPE:
    rows=[]
    for kind,src,target,count in SPECS:
        for frame in ({'run':[1,7,13],'attack':[1,13,17],'cast':[1,5,9,17,29,33]}[kind]):
            source,basis=pose_source(src,frame);rec=adapt(kind,frame,count,source,basis,{})
            rec['kind']=kind;rows.append(rec);render('prototype_'+kind,frame)
    (REPORT_DIR/'prototype.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    print('COMBAT_MOTION_V17_PROTOTYPE_COMPLETE',flush=True)
    raise SystemExit(0)

reports={}
for kind,src,target,count in SPECS:
    samples=[pose_source(src,f) for f in range(1,count+1)];values=[];rows=[];twists={}
    for frame,(source,basis) in enumerate(samples,1):
        rows.append(adapt(kind,frame,count,source,basis,twists));values.append(current_basis())
    if kind=='run':
        assert matrix_error(values[0],values[-1],values[0])<.00001
        assert max(x['unchanged_non_arm_basis_max_error'] for x in rows)<.00001
    if kind=='attack':
        assert max(x['knee_width_m'] for x in rows)<.24
        assert max(v for x in rows for v in x['ankle_displacement_m'].values())<.00005
        assert max(x['maximum_ik_clamp_m'] for x in rows)<.00005
    if kind=='cast': assert max(x.get('source_central_pose_max_error',0) for x in rows)<.00001
    required=[x for x in rows if x['support_required']]
    assert max(x['left_grip_target_error_m'] for x in required)<.001
    assert max(v for x in required for v in x['finger_cage_axis_distance_m'].values())<.007
    assert sum(len(a['wrong_direction_joints']) for x in rows for a in x['hand_anatomy'].values())==0
    assert not any(x['shaft_body_crossings'] for x in rows),(kind,[(x['frame'],x['shaft_body_crossings']) for x in rows if x['shaft_body_crossings']])
    action=bpy.data.actions.new(target);action.use_fake_user=True;r.animation_data.action=action;previous={}
    for frame,bases in enumerate(values,1):
        for name,m in bases.items():
            pb=r.pose.bones[name];loc,q,scale=m.decompose()
            if name in previous and q.dot(previous[name])<0:q.negate()
            previous[name]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=scale
            for channel in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=channel,frame=frame,group=name)
    for curve in check.curves(action):
        for key in curve.keyframe_points:key.interpolation='LINEAR'
    action['combat_loop']=kind=='run';action['intermediate_source_action']=src
    if kind=='run':action['cycle_distance_m']=3.242813140153885
    else:action['event_normalized']=.5;action['event_frame']=(count+1)//2
    track=r.animation_data.nla_tracks.new();track.name=target;track.mute=True
    strip=track.strips.new(target,1,action);strip.action_slot=action.slots[0]
    reports[target]={'frames':count,'source_action':src,'source_action_sha256':BASELINE['actions'][src],
                     'action_sha256':check.action_digest(action),'rows':rows}
    print('V17_BAKED',target,flush=True)

after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][n]==h for n,h in BASELINE['actions'].items())
assert len(after['actions'])==47
check.sample_action(r,bpy.data.actions['trial_two_hand_idle_v16'],1)
s.frame_start=1;s.frame_end=49;s.render.fps=24
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT));output_sha=hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
contract={'expected_source_sha256':output_sha,'protected_baseline_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),
          'expected_bones':107,'preserve_all_baseline_actions':True,'staff_attachment':ATTACHMENT,
          'secondary_grip':CONTRACT['secondary_grip'],'clips':{},'external_clips':[name for _,name,_ in FAMILY],
          'game_mapping_changed':False,'cycle_distance_m':3.242813140153885,
          'status':'User-directed two-hand locomotion and one-hand casting comparison'}
for kind,name,count in FAMILY:
    contract['clips'][name]={'frames':count,'loop':kind in ('idle','run'),'action_sha256':after['actions'][name]}
contract['clips']['trial_one_hand_cast_v17']['secondary_grip']={**CONTRACT['secondary_grip'],'required_frame_ranges':[[1,1],[33,33]]}
(FOLDER/'motion_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
provenance=json.loads((ROOT/'reports/combat_motion_v15/provenance.json').read_text(encoding='utf-8'))
mapping={'trial_quaternius_idle_staff_v15':'trial_two_hand_idle_v16','trial_quaternius_hit_staff_v15':'trial_two_hand_hit_v16',
         'trial_quaternius_attack_staff_v15':'trial_two_hand_attack_v17','trial_mixamo_cast_staff_v15':'trial_one_hand_cast_v17'}
for entry in provenance['sources']:
    for target in entry['target_clips']:
        old=target['name'];name=mapping[old]
        target.update({'name':name,'action_sha256':after['actions'][name],'intermediate_action_name':old,'intermediate_action_sha256':BASELINE['actions'][old]})
    entry['intermediate_source_file']=str(INPUT);entry['intermediate_source_sha256']=contract['protected_baseline_sha256']
run_entry=copy.deepcopy(provenance['sources'][0]);run_entry['source_action']='Jog_Fwd_Loop';run_entry.pop('source_action_sha256',None)
run_entry['target_clips']=[{'name':'trial_two_hand_run_v17','action_sha256':after['actions']['trial_two_hand_run_v17'],
                          'intermediate_action_name':RUN_SOURCE,'intermediate_action_sha256':BASELINE['actions'][RUN_SOURCE]}]
provenance['sources'].append(run_entry)
(REPORT_DIR/'provenance.json').write_text(json.dumps(provenance,indent=2),encoding='utf-8')
report={'passed':True,'source_sha256':contract['protected_baseline_sha256'],'output_sha256':output_sha,
        'protected_meshes':29,'protected_actions':44,'rest_bones':107,'clips':reports,
        'scope':'All prior assets preserved; run non-arm basis retained, attack feet planted and knees forward, cast central frames 9-25 retained. Contact proxies are not complete clearance.'}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('COMBAT_MOTION_V17_COMPLETE',output_sha,flush=True)
