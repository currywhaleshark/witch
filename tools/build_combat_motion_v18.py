"""Author local step/swing/thrust and retarget the licensed CC0 Death01.

Run only in a fresh background Blender. All v17 meshes, binds and actions are
protected. The prop slide is presentation data, never character root motion.
"""
from pathlib import Path
import bpy,sys,json,math,hashlib,ast
import numpy as np
from mathutils import Matrix,Quaternion,Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
INPUT=ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_motion_v17/combat_motion_v17.blend'
FOLDER=ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_motion_v18'
REPORT_DIR=ROOT/'reports/combat_motion_v18'
FOLDER.mkdir(parents=True,exist_ok=True);REPORT_DIR.mkdir(parents=True,exist_ok=True)
assert bpy.app.background
assert hashlib.sha256(INPUT.read_bytes()).hexdigest()=='5e2cd24cf4bae2a061fcea3a1f919c2250e0003c67dd80f69e028147926a2844'
bpy.ops.wm.open_mainfile(filepath=str(INPUT))
helper=(ROOT/'tools/build_combat_animations_v12.py').read_text(encoding='utf-8').split('CLIPS=')[0]
helper=helper.replace('source_outfit_v11/source_outfit_v11.blend','combat_motion_v17/combat_motion_v17.blend')
helper=helper.replace("(ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_animation_v12')","(ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_motion_v18')")
helper=helper.replace("(ROOT/'reports/combat_animation_v12/animation_agent')","(ROOT/'reports/combat_motion_v18')")
exec(compile(helper,str(ROOT/'tools/build_combat_animations_v12.py'),'exec'),globals())
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
hands=AnatomicalHandRig(r)
BASELINE=check.snapshot(r.name,set())
(REPORT_DIR/'protected_baseline.json').write_text(json.dumps(BASELINE),encoding='utf-8')
CONTRACT=json.loads((INPUT.parent/'runtime_contract.json').read_text(encoding='utf-8'))
ATTACHMENT=CONTRACT['staff_attachment'];OFFSET=Vector(ATTACHMENT['offset_bone_local'])
STAFF_BASIS=Matrix(ATTACHMENT['basis_columns_bone_local']).transposed()
STAFF_LOCAL_AXIS=STAFF_BASIS@Vector((0,1,0))
LEFT_OFFSET=sum((hands.axes['L'][k]*OFFSET.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
borrow(ROOT/'tools/build_two_hand_v16.py',{'restore','pose_source','cage_center'})
IDLE_TWO,IDLE_TWO_BASIS=pose_source('trial_two_hand_idle_v16',1)
GUARD_CENTER=IDLE_TWO['DEF-hand.R']@OFFSET
GUARD_AXIS=(IDLE_TWO['DEF-hand.R'].to_3x3()@STAFF_LOCAL_AXIS).normalized()
GUARD_RQ=IDLE_TWO['DEF-hand.R'].to_quaternion()
HAND_FRAMES={side:check.hand_frame(r,side,Vector((-1,0,0))) for side in ('L','R')}
borrow(ROOT/'tools/build_combat_motion_v17.py',{'continuous_attack_skirt'})

def current_basis():return {pb.name:pb.matrix_basis.copy() for pb in r.pose.bones}
def current_pose():return {pb.name:pb.matrix.copy() for pb in r.pose.bones}
def scalar(t,stops):return float(blend_stops(t,[(x,[v]) for x,v in stops])[0])
def grip_amount(t):return scalar(t,[(0,0),(.25,1),(.70,1),(1,0)])

def attack_body(t,twists):
    restore(IDLE_TWO_BASIS)
    step=scalar(t,[(0,0),(.10,.012),(.32,.23),(.65,.23),(.94,0),(1,0)])
    lift=scalar(t,[(0,0),(.10,.02),(.20,.047),(.32,0),(.65,0),(.80,.045),(.94,0),(1,0)])
    lean=scalar(t,[(0,0),(.25,-2),(.5,9),(.65,11),(1,0)])
    weight=scalar(t,[(0,0),(.32,1),(.65,1),(1,0)])
    pelvis=IDLE_TWO['DEF-pelvis'].copy();pelvis.translation+=Vector((0,-.065*weight,-.03*weight))
    pelvis=Matrix.LocRotScale(pelvis.translation,qworld(x=lean*.20)@pelvis.to_quaternion(),Vector((1,1,1)))
    ankles={side:IDLE_TWO['DEF-foot.'+side].translation.copy() for side in ('L','R')}
    ankles['L']+=Vector((0,-step,lift))
    for _ in range(24):
        dp=pelvis@IDLE_TWO['DEF-pelvis'].inverted()
        excess=max((dp@IDLE_TWO['DEF-thigh.'+side].translation-ankles[side]).length-CHAIN['DEF-thigh.'+side][1]-CHAIN['DEF-shin.'+side][1]+.001 for side in ('L','R'))
        if excess<=0:break
        pelvis.translation.z-=excess+.00001
    desired={'DEF-pelvis':pelvis}
    for n,gain in [('DEF-spine',.35),('DEF-chest',.45),('DEF-neck',-.10),('DEF-head',-.10),('DEF-clavicle.L',0),('DEF-clavicle.R',0)]:
        parent=r.data.bones[n].parent.name;base=desired[parent]@IDLE_TWO[parent].inverted()@IDLE_TWO[n]
        desired[n]=Matrix.LocRotScale(base.translation,qworld(x=lean*gain)@base.to_quaternion(),Vector((1,1,1)))
    clamps=[]
    for side in ('L','R'):
        thigh,shin,foot,toe=['DEF-'+n+'.'+side for n in ('thigh','shin','foot','toe')]
        hip=pelvis@IDLE_TWO['DEF-pelvis'].inverted()@IDLE_TWO[thigh].translation
        knee,end=solve_ik(hip,ankles[side],CHAIN[thigh][1],CHAIN[shin][1],Vector((-.08 if side=='L' else .08,-1,0)))
        qa=IDLE_TWO[thigh].to_quaternion();qf=IDLE_TWO[shin].to_quaternion();qfoot=IDLE_TWO[foot].to_quaternion()
        qa=(qa@Vector((0,1,0))).rotation_difference((knee-hip).normalized())@qa
        qf=(qf@Vector((0,1,0))).rotation_difference((end-knee).normalized())@qf
        chain_desired(thigh,hip,knee,qa,qf,desired,twists);chain_desired(shin,knee,end,qf,qfoot,desired,twists)
        desired[foot]=Matrix.LocRotScale(end,qfoot,Vector((1,1,1)));desired[toe]=desired[foot]@IDLE_TWO[foot].inverted()@IDLE_TWO[toe]
        clamps.append((end-ankles[side]).length)
    apply_desired(desired)
    return max(clamps)

def solve_staff(center,axis,spacing,twists):
    axis=axis.normalized();qright=GUARD_AXIS.rotation_difference(axis)@GUARD_RQ
    qleft=hands.orientation('L',qright@hands.axes['R']['finger'],-(qright@hands.axes['R']['palm']))
    requested=center.copy();source=current_pose()
    for _ in range(24):
        for side,q,ax,off in [('R',qright,0.,OFFSET),('L',qleft,spacing,LEFT_OFFSET)]:
            anchor=source['DEF-upper_arm.'+side].translation-axis*ax+q@off
            radius=CHAIN['DEF-upper_arm.'+side][1]+CHAIN['DEF-forearm.'+side][1]-.020
            d=center-anchor
            if d.length>radius:center=anchor+d.normalized()*radius
    desired={};clamps=[]
    for side,q,grip,off in [('R',qright,center,OFFSET),('L',qleft,center+axis*spacing,LEFT_OFFSET)]:
        arm,fore,hand=['DEF-'+n+'.'+side for n in ('upper_arm','forearm','hand')]
        shoulder=source[arm].translation;target=grip-q@off
        elbow,wrist=solve_ik(shoulder,target,CHAIN[arm][1],CHAIN[fore][1],Vector((.55 if side=='L' else -.55,.1,-1)))
        qa=source[arm].to_quaternion();qf=source[fore].to_quaternion()
        qa=(qa@Vector((0,1,0))).rotation_difference((elbow-shoulder).normalized())@qa
        qf=(qf@Vector((0,1,0))).rotation_difference((wrist-elbow).normalized())@qf
        chain_desired(arm,shoulder,elbow,qa.normalized(),qf.normalized(),desired,twists)
        chain_desired(fore,elbow,wrist,qf.normalized(),q.normalized(),desired,twists)
        desired[hand]=Matrix.LocRotScale(wrist,q,Vector((1,1,1)));clamps.append((wrist-target).length)
    apply_desired(desired)
    for side in ('R','L'):
        hands.apply_wrist(side,desired['DEF-hand.'+side].to_quaternion(),twists);hands.apply_fingers(side,1.)
    bpy.context.view_layer.update()
    return max(clamps),(center-requested).length

def attack(kind,t,twists):
    legclamp=attack_body(t,twists);amount=grip_amount(t);spacing=.26-.08*amount
    if kind=='swing':
        centers=[(0,GUARD_CENTER),(.28,[-.045,-.27,1.40]),(.5,[-.025,-.42,1.08]),(.64,[.015,-.40,.96]),(1,GUARD_CENTER)]
        axes=[(0,GUARD_AXIS),(.28,[0,.10,.995]),(.5,[0,-.98,.20]),(.64,[.03,-.83,-.557]),(1,GUARD_AXIS)]
    else:
        centers=[(0,GUARD_CENTER),(.27,[-.10,-.18,1.04]),(.5,[-.025,-.47,1.09]),(.58,[-.025,-.47,1.09]),(.75,[-.10,-.25,1.05]),(1,GUARD_CENTER)]
        axes=[(0,GUARD_AXIS),(.27,[0,-.997,.075]),(.5,[0,-.997,.075]),(.68,[0,-.997,.075]),(1,GUARD_AXIS)]
    clamp,correction=solve_staff(Vector(blend_stops(t,centers)),Vector(blend_stops(t,axes)),spacing,twists)
    continuous_attack_skirt();collision_adjust(stride=3,iterations=5);fit_cardigan()
    if t in (0,1):restore(IDLE_TWO_BASIS)
    return {'leg_ik_clamp_m':legclamp,'arm_ik_clamp_m':clamp,'staff_reach_correction_m':correction,'slide_m':.28*amount,'spacing_m':spacing}

def import_death():
    path=ROOT/'assets/characters/player/3d/source/motion_library/quaternius_ual_standard/extracted/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb'
    oldobj,oldact=set(bpy.data.objects),set(bpy.data.actions);s.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path));objects=set(bpy.data.objects)-oldobj;actions=set(bpy.data.actions)-oldact
    src=next(o for o in objects if o.type=='ARMATURE')
    for tr in src.animation_data.nla_tracks:tr.mute=True
    a=next(a for a in actions if a.name=='Death01');src.animation_data.action=a;src.animation_data.action_slot=a.slots[0]
    rest={b.name:src.matrix_world@b.matrix_local for b in src.data.bones};samples=[]
    for i in range(59):
        f=a.frame_range[0]+(a.frame_range[1]-a.frame_range[0])*i/58;s.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update()
        samples.append({pb.name:src.matrix_world@pb.matrix for pb in src.pose.bones})
    meta={'path':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'action':'Death01','action_sha256':check.action_digest(a),'source_fps':30,'range':list(a.frame_range),'license':'CC0-1.0','retargeted_frames':59}
    for o in objects:bpy.data.objects.remove(o,do_unlink=True)
    for a in actions:bpy.data.actions.remove(a)
    s.render.fps=24
    return rest,samples,meta

def collapse(pose,first,src_rest,t,twists):
    restore(IDLE_TWO_BASIS)
    scale=(CHAIN['DEF-thigh.L'][1]+CHAIN['DEF-shin.L'][1])/sum((src_rest[b].translation-src_rest[a].translation).length for a,b in [('thigh_l','calf_l'),('calf_l','foot_l')])
    def rot(source,target):return (pose[source].to_quaternion()@src_rest[source].to_quaternion().inverted()@REST[target].to_quaternion()).normalized()
    position=IDLE_TWO['DEF-pelvis'].translation+(pose['pelvis'].translation-first['pelvis'].translation)*scale
    desired={'DEF-pelvis':Matrix.LocRotScale(position,rot('pelvis','DEF-pelvis'),Vector((1,1,1)))}
    for target,source in [('DEF-spine','spine_01'),('DEF-chest','spine_03'),('DEF-neck','neck_01'),('DEF-head','Head'),('DEF-clavicle.L','clavicle_l'),('DEF-clavicle.R','clavicle_r')]:
        parent=r.data.bones[target].parent.name;base=desired[parent]@INV[parent]@REST[target]
        desired[target]=Matrix.LocRotScale(base.translation,rot(source,target),Vector((1,1,1)))
    for side,lower in [('L','l'),('R','r')]:
        for a,b,c,sa,sb,sc,parent in [('thigh','shin','foot','thigh','calf','foot','DEF-pelvis'),('upper_arm','forearm','hand','upperarm','lowerarm','hand','DEF-clavicle.'+side)]:
            an,bn,cn=['DEF-'+n+'.'+side for n in (a,b,c)]
            head=desired[parent]@INV[parent]@REST[an].translation
            qa,qb,qc=rot(sa+'_'+lower,an),rot(sb+'_'+lower,bn),rot(sc+'_'+lower,cn)
            # The source is a T-pose, while this body has lowered A-pose arms.
            # Transfer the observed segment directions, not that rest-pose gap.
            da=(pose[sb+'_'+lower].translation-pose[sa+'_'+lower].translation).normalized()
            db=(pose[sc+'_'+lower].translation-pose[sb+'_'+lower].translation).normalized()
            if c=='foot':
                # The source's deep seated tuck is unsuitable for the short
                # layered skirts. Retain the fall, with a smaller leg fold.
                down=(desired['DEF-pelvis']@INV['DEF-pelvis']).to_3x3()@Vector((0,0,-1))
                angle=down.angle(da)
                if angle>math.radians(55):da=Quaternion().slerp(down.rotation_difference(da),math.radians(55)/angle)@down
                bend=da.angle(db)
                if bend>math.radians(95):db=Quaternion().slerp(da.rotation_difference(db),math.radians(95)/bend)@da
            qa=(qa@Vector((0,1,0))).rotation_difference(da)@qa
            qb=(qb@Vector((0,1,0))).rotation_difference(db)@qb
            if c=='foot':
                dc=(pose['ball_'+lower].translation-pose[sc+'_'+lower].translation).normalized()
                qc=(qc@Vector((0,1,0))).rotation_difference(dc)@qc
            mid=head+(qa@Vector((0,1,0))).normalized()*CHAIN[an][1]
            end=mid+(qb@Vector((0,1,0))).normalized()*CHAIN[bn][1]
            if c=='hand' and side=='R':
                axis=Vector((0,1,.015));target=GUARD_AXIS.rotation_difference(axis)@GUARD_RQ
                qc=GUARD_RQ.slerp(target,sm(t/.50))
            chain_desired(an,head,mid,qa,qb,desired,twists);chain_desired(bn,mid,end,qb,qc,desired,twists)
            desired[cn]=Matrix.LocRotScale(end,qc,Vector((1,1,1)))
            if c=='foot':desired['DEF-toe.'+side]=desired[cn]@INV[cn]@REST['DEF-toe.'+side]
    apply_desired(desired)
    for side in ('R','L'):
        hands.apply_wrist(side,desired['DEF-hand.'+side].to_quaternion(),twists);hands.apply_fingers(side,1 if side=='R' else .15)
    # A short authored lead blends the armed guard into the source fall.
    amount=sm(t/.17)
    if amount<1:
        for pb in r.pose.bones:
            a,qa,sa=IDLE_TWO_BASIS[pb.name].decompose();b,qb,sb=pb.matrix_basis.decompose()
            pb.matrix_basis=Matrix.LocRotScale(a.lerp(b,amount),qa.slerp(qb,amount),sa.lerp(sb,amount))
        bpy.context.view_layer.update()
    continuous_attack_skirt()
    # The fitted cardigan local supports follow the body; upright radial
    # clearance assumptions are not applied to a supine torso.
    for n in HELPERS:r.pose.bones[n].matrix_basis=IDLE_TWO_BASIS[n]
    bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get();low=1.
    for n in ['Face_Core_v8','Hair_Semilong_v7','Body_Hands_v7','Body_UpperLegs_v7','Outfit_Shoes_v7','SourceOutfit_Cardigan_v11']:
        ob=bpy.data.objects[n];ev=ob.evaluated_get(dg)
        low=min(low,min((ev.matrix_world@v.co).z for v in ev.data.vertices))
    lift=max(0,.004-low)*sm(t/.12)
    if lift:
        m=r.pose.bones['DEF-pelvis'].matrix.copy();m.translation.z+=lift;apply_desired({'DEF-pelvis':m})
    # Lift only the skirt supports where the evaluated cloth enters the floor.
    # These are stored support poses; no mesh, weights or runtime cloth changes.
    cloth_names=['SourceOutfit_Skirt_v11','SourceOutfit_SkirtLining_v11']
    for _ in range(4):
        aa=[];bb=[];dg=bpy.context.evaluated_depsgraph_get()
        for n in cloth_names:
            ob=bpy.data.objects[n];ev=ob.evaluated_get(dg)
            for v in ev.data.vertices:
                deficit=.004-v.co.z
                if deficit<=0:continue
                weights=np.zeros(32)
                for g in ob.data.vertices[v.index].groups:
                    gn=ob.vertex_groups[g.group].name
                    if gn in support_names:weights[support_names.index(gn)]=g.weight
                if weights.sum()>.12:aa.append(weights);bb.append(deficit)
        if not aa:break
        aa=np.array(aa);bb=np.array(bb);dz=np.clip(np.linalg.solve(aa.T@aa+np.eye(32)*.12,aa.T@bb),0,.080)
        desired={}
        for n,z in zip(support_names,dz):
            mat=r.pose.bones[n].matrix.copy();mat.translation.z+=float(z);desired[n]=mat
        apply_desired(desired)
    if t==0:restore(IDLE_TWO_BASIS)
    return {'slide_m':0.,'spacing_m':None,'floor_lift_m':lift,'unadjusted_low_m':low}

def record(info):
    center=r.pose.bones['DEF-hand.R'].matrix@OFFSET;axis=(r.pose.bones['DEF-hand.R'].matrix.to_3x3()@STAFF_LOCAL_AXIS).normalized()
    info.update(staff_hand=list(center),staff_origin=list(center+axis*info['slide_m']),staff_axis=list(axis),staff_tip=list(center+axis*(.78+info['slide_m'])),
        feet={side:list(r.pose.bones['DEF-foot.'+side].head) for side in ('L','R')},pelvis=list(r.pose.bones['DEF-pelvis'].head),
        cage_axis_m={side:check.line_distance(cage_center(side),center,axis) for side in ('L','R')},
        wrong_finger_curls=sum(len(check.anatomy_sample(r,side,HAND_FRAMES[side],3,0)['wrong_direction_joints']) for side in ('L','R')))
    if info['spacing_m'] is not None:info['secondary_error_m']=(r.pose.bones['DEF-hand.L'].matrix@LEFT_OFFSET-center-axis*info['spacing_m']).length
    return info

def write_action(name,values,slides):
    a=bpy.data.actions.new(name);a.use_fake_user=True;r.animation_data.action=a;previous={}
    for frame,bases in enumerate(values,1):
        for name,m in bases.items():
            pb=r.pose.bones[name];loc,q,scale=m.decompose()
            if name in previous and q.dot(previous[name])<0:q.negate()
            previous[name]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=scale
            for channel in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=channel,frame=frame,group=name)
        r['staff_slide_v18']=slides[frame-1];r.keyframe_insert(data_path='["staff_slide_v18"]',frame=frame)
    for fc in check.curves(a):
        for k in fc.keyframe_points:k.interpolation='LINEAR'
    a['combat_loop']=False
    tr=r.animation_data.nla_tracks.new();tr.name=a.name;tr.mute=True;st=tr.strips.new(a.name,1,a);st.action_slot=a.slots[0]
    return a

src_rest,death_samples,provenance=import_death()
reports={}
for kind,count in [('swing',25),('thrust',25),('collapse',59)]:
    twists={};values=[];rows=[]
    for i in range(count):
        t=i/(count-1)
        info=collapse(death_samples[i],death_samples[0],src_rest,t,twists) if kind=='collapse' else attack(kind,t,twists)
        info['frame']=i+1;rows.append(record(info));values.append(current_basis())
        if i%6==0:print('V18_POSE',kind,i+1,flush=True)
    assert all(x['wrong_finger_curls']==0 for x in rows)
    if kind!='collapse':
        assert max(x['secondary_error_m'] for x in rows)<.001
        assert max(x['leg_ik_clamp_m'] for x in rows)<.0001
        assert max(abs(values[0][n][i][j]-values[-1][n][i][j]) for n in values[0] for i in range(4) for j in range(4))<1e-6
    name='combat_'+kind+'_v18';a=write_action(name,values,[x['slide_m'] for x in rows])
    if kind!='collapse':a['event_normalized']=.5;a['event_frame']=13
    reports[name]={'frames':count,'duration_seconds':(count-1)/24,'action_sha256':check.action_digest(a),'rows':rows}
    (REPORT_DIR/'build_progress.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
after=check.snapshot(r.name,set())
assert BASELINE['meshes']==after['meshes'] and BASELINE['rig']==after['rig']
assert all(after['actions'][n]==h for n,h in BASELINE['actions'].items())
# Derived preview prop follows the same animated hand/shaft slide as the engine.
original=bpy.data.objects['PROP_StaffPreview_v13'];original.hide_render=True;original.hide_set(True)
anchor=bpy.data.objects.new('StaffAnchor_v18',None);s.collection.objects.link(anchor)
c=anchor.constraints.new('COPY_TRANSFORMS');c.target=r;c.subtarget='DEF-hand.R'
mesh=original.data.copy();mesh.name='StaffPreview_v18'
for v in mesh.vertices:v.co=INV['DEF-hand.R']@(original.matrix_world@v.co)
prop=bpy.data.objects.new('PROP_StaffPreview_v18',mesh);s.collection.objects.link(prop);prop.parent=anchor
prop['preview_only']=True
for i in range(3):
    d=prop.driver_add('location',i).driver;d.type='SCRIPTED';v=d.variables.new();v.name='slide';v.type='SINGLE_PROP';v.targets[0].id=r;v.targets[0].data_path='["staff_slide_v18"]';d.expression=f'slide * {STAFF_LOCAL_AXIS[i]:.12f}'
r['staff_slide_v18']=0.;check.sample_action(r,bpy.data.actions['trial_two_hand_idle_v16'],1)
s.frame_start=1;s.frame_end=59;s.render.fps=24
output=FOLDER/'combat_motion_v18.blend';bpy.ops.wm.save_as_mainfile(filepath=str(output))
report={'passed':True,'source_sha256':hashlib.sha256(INPUT.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'protected_meshes':len(BASELINE['meshes']),'protected_actions':len(BASELINE['actions']),'rest_bones':107,'clips':reports,'collapse_provenance':provenance}
(REPORT_DIR/'build_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
contract={**CONTRACT,'source_blend':str(output.relative_to(ROOT)),'source_blend_sha256':report['output_sha256'],'exported_clips':['trial_two_hand_idle_v16','trial_two_hand_run_v17','combat_swing_v18','combat_thrust_v18','trial_one_hand_cast_v17','trial_two_hand_hit_v16','combat_collapse_v18']}
contract['runtime_default_clips'].update(attack='combat_swing_v18',attack_thrust='combat_thrust_v18',collapse='combat_collapse_v18')
contract['attack_variants']={'probability':[.5,.5],'selection':'once per basic attack, visual RNG only','same_gameplay_clock':True,'step_local_m':.23,'release_normalized':.5,'grip_slide_curve':[[i/24,rowslide] for i,rowslide in enumerate([x['slide_m'] for x in reports['combat_swing_v18']['rows']])],'secondary_spacing_m':[.26,.18],'right_grip_from_shaft_bottom_m':[.42,.14]}
contract['collapse']={'trigger':'HP <= 0','clip':'combat_collapse_v18','duration_seconds':58/24,'hold_last_pose':True,'world_root_motion':False,'source':provenance}
contract['clips'].pop('trial_two_hand_attack_v17')
for n,rep in reports.items():contract['clips'][n]={'frames':rep['frames'],'loop':False,'action_sha256':rep['action_sha256']}
(FOLDER/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
print('COMBAT_MOTION_V18_COMPLETE',report['output_sha256'],flush=True)
