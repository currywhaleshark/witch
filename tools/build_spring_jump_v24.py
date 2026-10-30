"""Adapt the user's actual Unarmed Jump to the unchanged v21/v23 character rig."""
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/characters/player/3d/source/middle_school_v1/thrust_v23/thrust_v23.blend'
setup=(ROOT/'tools/build_combat_motion_v18.py').read_text(encoding='utf-8').split('src_rest,death_samples,provenance=import_death()')[0]
setup=setup.replace('combat_motion_v17/combat_motion_v17.blend','thrust_v23/thrust_v23.blend')
setup=setup.replace('5e2cd24cf4bae2a061fcea3a1f919c2250e0003c67dd80f69e028147926a2844',hashlib.sha256(BASE.read_bytes()).hexdigest())
setup=setup.replace("/combat_motion_v18'","/spring_jump_v24'")
setup=setup.replace("exec(compile(helper,", "helper=helper.replace(\"ROOT/'reports/source_outfit_v11/cardigan_audit/build_cardigan_candidate.py'\",\"ROOT/'tools/cardigan_fit_helpers_v23.py'\")\nexec(compile(helper,",1)
exec(compile(setup,str(ROOT/'tools/build_combat_motion_v18.py'),'exec'),globals())

FBX=ROOT/'assets/characters/player/3d/source/motion_library/mixamo_local/Unarmed_Jump_user_2026-10-30.fbx'
CLIP='combat_spring_jump_v24';COUNT=49
assert hashlib.sha256(FBX.read_bytes()).hexdigest()=='c3a76978f47439d4c929ebad881f277ade45d60b3543bf4e92821a979949bc68'
assert CLIP not in bpy.data.actions
guard,guard_basis=pose_source('combat_idle_rh_v20',1)
GC=guard['DEF-hand.R']@OFFSET;GA=(guard['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
GQ={side:guard['DEF-hand.'+side].to_quaternion() for side in ('L','R')}
borrow(ROOT/'tools/build_run_arm_v21.py',{'hinge_frame','hinge_rotations'})
borrow(ROOT/'tools/build_thrust_v23.py',{'drive_staff'})
old_objects=set(bpy.data.objects);old_actions=set(bpy.data.actions);s.render.fps=30
bpy.ops.import_scene.fbx(filepath=str(FBX),use_anim=True)
imported=set(bpy.data.objects)-old_objects;imported_actions=set(bpy.data.actions)-old_actions
src=next(o for o in imported if o.type=='ARMATURE');source_action=src.animation_data.action
prefix=next(b.name[:-4] for b in src.data.bones if b.name.endswith('Hips'))
raw={b.name.removeprefix(prefix):src.matrix_world@b.matrix_local for b in src.data.bones}
forward=sum((raw[x+'ToeBase'].translation-raw[x+'Foot'].translation for x in ('Left','Right')),Vector());forward.z=0;forward.normalize()
align=Matrix.Rotation(-math.pi/2-math.atan2(forward.y,forward.x),4,'Z')
for tr in src.animation_data.nla_tracks:tr.mute=True
TIME_MAP=[(0.,1.),(.12,19.),(.25,25.),(.50,35.),(.75,45.),(.84,52.),(1.,71.)]
def source_at(t):
    for (ta,fa),(tb,fb) in zip(TIME_MAP,TIME_MAP[1:]):
        if ta<=t<=tb:return fa+(fb-fa)*(t-ta)/(tb-ta)
    return 71.
samples=[]
for i in range(COUNT):
    f=source_at(i/(COUNT-1));s.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update()
    samples.append({pb.name.removeprefix(prefix):align@src.matrix_world@pb.matrix for pb in src.pose.bones})
provenance={'source':'User-supplied Unarmed Jump.fbx','provider_metadata':source_action.name,'raw_path':FBX.relative_to(ROOT).as_posix(),'raw_sha256':hashlib.sha256(FBX.read_bytes()).hexdigest(),'source_action_sha256':check.action_digest(source_action),'source_fps':30,'source_frames':list(source_action.frame_range),'time_map':TIME_MAP,'license':'Mixamo source; not CC0; raw source remains local/gitignored'}
for ob in imported:bpy.data.objects.remove(ob,do_unlink=True)
for ac in imported_actions:bpy.data.actions.remove(ac)
s.render.fps=24
first=samples[0]
scale=(CHAIN['DEF-thigh.L'][1]+CHAIN['DEF-shin.L'][1])/sum((first[b].translation-first[a].translation).length for a,b in [('LeftUpLeg','LeftLeg'),('LeftLeg','LeftFoot')])

def retarget(pose,t,twists):
    restore(guard_basis)
    env=min(sm(t/.10),sm((1.-t)/.10))
    def rotation(src_name,target,gain=.65):
        delta=pose[src_name].to_quaternion()@first[src_name].to_quaternion().inverted()
        return Quaternion().slerp(delta,gain*env)@guard[target].to_quaternion()
    pelvis=guard['DEF-pelvis'].copy()
    pelvis.translation.z+=max(-.12,min(0.,(pose['Hips'].translation.z-first['Hips'].translation.z)*scale*.65))*env
    desired={'DEF-pelvis':Matrix.LocRotScale(pelvis.translation,rotation('Hips','DEF-pelvis',.55),Vector((1,1,1)))}
    for name,source in [('DEF-spine','Spine'),('DEF-chest','Spine2'),('DEF-neck','Neck'),('DEF-head','Head'),('DEF-clavicle.L','LeftShoulder'),('DEF-clavicle.R','RightShoulder')]:
        parent=r.data.bones[name].parent.name
        base=desired[parent]@guard[parent].inverted()@guard[name]
        desired[name]=base if name.startswith('DEF-clavicle') else Matrix.LocRotScale(base.translation,rotation(source,name,.6),Vector((1,1,1)))
    for side,long in [('L','Left'),('R','Right')]:
        a,b,c,toe=['DEF-'+name+'.'+side for name in ('thigh','shin','foot','toe')]
        hip=desired['DEF-pelvis']@guard['DEF-pelvis'].inverted()@guard[a].translation
        qa,qb,qc=rotation(long+'UpLeg',a,.67),rotation(long+'Leg',b,.67),rotation(long+'Foot',c,.6)
        # Transfer source segment directions relative to the source's initial stance.
        dirs=[]
        for sn,en,targetq,target in [(long+'UpLeg',long+'Leg',qa,a),(long+'Leg',long+'Foot',qb,b)]:
            before=(first[en].translation-first[sn].translation).normalized()
            after=(pose[en].translation-pose[sn].translation).normalized()
            initial=(guard[b if target==a else c].translation-guard[target].translation).normalized()
            direction=Quaternion().slerp(before.rotation_difference(after),.67*env)@initial
            dirs.append(direction.normalized())
        qa=(qa@Vector((0,1,0))).rotation_difference(dirs[0])@qa
        qb=(qb@Vector((0,1,0))).rotation_difference(dirs[1])@qb
        knee=hip+dirs[0]*CHAIN[a][1];ankle=knee+dirs[1]*CHAIN[b][1]
        chain_desired(a,hip,knee,qa,qb,desired,twists);chain_desired(b,knee,ankle,qb,qc,desired,twists)
        desired[c]=Matrix.LocRotScale(ankle,qc,Vector((1,1,1)))
        desired[toe]=desired[c]@guard[c].inverted()@guard[toe]
    apply_desired(desired)
    dg=bpy.context.evaluated_depsgraph_get()
    shoe=bpy.data.objects['Outfit_Shoes_v7'].evaluated_get(dg)
    low=min((shoe.matrix_world@v.co).z for v in shoe.data.vertices)
    air=max(0.,math.sin(math.pi*max(0.,min(1.,(t-.25)/.5)))) if .25<t<.75 else 0.
    # Foot planting for preparation/landing; retained knee tuck in flight. Runtime supplies
    # the horizontal path and modest world-space parabola, never the FBX's root travel.
    correction=(.009-low)*(1.-air)
    pelvis=r.pose.bones['DEF-pelvis'].matrix.copy();pelvis.translation.z+=correction
    apply_desired({'DEF-pelvis':pelvis})
    pose_now=current_pose();chest_delta=pose_now['DEF-chest']@guard['DEF-chest'].inverted()
    # Transport the accepted two-hand guard as one chest-relative pose. Solving each
    # endpoint wrist anew can choose a different twist winding at the idle boundary.
    arms={name:chest_delta@guard[name] for name in guard if any(name.startswith('DEF-'+stem+'.') for stem in ('upper_arm','forearm','hand','thumb','index','middle','ring','pinky'))}
    apply_desired(arms)
    arm_error=0.;reach=0.
    continuous_attack_skirt();collision_adjust(stride=3,iterations=5);fit_cardigan()
    if t in (0.,1.):restore(guard_basis)
    return {'source_frame':source_at(t),'slide_m':-.26,'spacing_m':-.26,'arm_ik_clamp_m':arm_error,'reach_correction_m':reach,'ground_correction_m':correction,'flight_weight':air}

values=[];rows=[];twists={}
for i,pose in enumerate(samples):
    info=retarget(pose,i/(COUNT-1),twists);info['frame']=i+1
    rows.append(record(info));values.append(current_basis())
    if i%8==0:print('SPRING_JUMP_FRAME',i+1,'grip',rows[-1]['secondary_error_m'],flush=True)
assert max(x['secondary_error_m'] for x in rows)<.001
assert all(x['wrong_finger_curls']==0 for x in rows)
action=write_action(CLIP,values,[-.26]*COUNT)
action['source_fbx_sha256']=provenance['raw_sha256'];action['takeoff_phase']=.25;action['landing_phase']=.75
after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][name]==digest for name,digest in BASELINE['actions'].items())
check.sample_action(r,action,1);r['staff_slide_v18']=-.26
s.frame_start=1;s.frame_end=COUNT;s.render.fps=24
output=FOLDER/'spring_jump_v24.blend';bpy.ops.wm.save_as_mainfile(filepath=str(output))
contract={'rig_id':'player_humanoid_v11','clip':CLIP,'fps':24,'frames':COUNT,'takeoff_phase':.25,'landing_phase':.75,'height_m':.32,'landing_seconds':.12,'staff_slide_tracks':{CLIP:[-.26]*COUNT},'source':provenance,'source_blend':output.relative_to(ROOT).as_posix(),'source_blend_sha256':hashlib.sha256(output.read_bytes()).hexdigest()}
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
report={'passed':True,'input_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),'output_sha256':contract['source_blend_sha256'],'protected_meshes':len(BASELINE['meshes']),'protected_actions':len(BASELINE['actions']),'rest_bones':len(r.data.bones),'provenance':provenance,'clip':CLIP,'rows':rows,'action_sha256':check.action_digest(action)}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SPRING_JUMP_BUILD_COMPLETE',contract['source_blend_sha256'],flush=True)
