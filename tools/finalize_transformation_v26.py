"""Reopen, validate and export the v26 field entry clip without touching existing assets.

Only the clip and its runtime contract go to the v26 game folder; the unchanged
transformed v4 outfit keeps loading from its v25 game path."""
import bpy,json,hashlib,sys,math
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/transformation_v26'
FOLDER=ROOT/'assets/characters/player/3d/source/middle_school_v1/transformation_v26'
EXPORT=ROOT/'assets/characters/player/3d/exports/transformation_v26'
GAME=ROOT/'game/assets/characters/player/transformation_v26'
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(FOLDER/'transformation_v26.blend'))
r=bpy.data.objects['PlayerRig_v7'];scene=bpy.context.scene
baseline=json.loads((OUT/'protected_baseline.json').read_text(encoding='utf-8'))
after=check.snapshot(r.name,set())
assert baseline['meshes']==after['meshes'] and baseline['rig']==after['rig']
assert all(after['actions'][n]==h for n,h in baseline['actions'].items())
contract=json.loads((FOLDER/'runtime_contract.json').read_text(encoding='utf-8'))
hands=AnatomicalHandRig(r);off=Vector(contract['staff_attachment']['offset_bone_local'])
axis_local=Matrix(contract['staff_attachment']['basis_columns_bone_local']).transposed()@Vector((0,1,0))
leftoff=sum((hands.axes['L'][k]*off.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
frames={side:check.hand_frame(r,side,Vector((-1,0,0))) for side in ('L','R')}
action=bpy.data.actions[contract['clip']];rows=[];fixtures=[];failures=[]
for i in range(145):
    frame=1+i/2;sec=(frame-1)/24
    check.sample_action(r,action,int(frame));scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
    pose={p.name:p.matrix.copy() for p in r.pose.bones}
    right=pose['DEF-hand.R']@off;left=pose['DEF-hand.L']@leftoff
    axis=(pose['DEF-hand.R'].to_3x3()@axis_local).normalized()
    error=(left-right+axis*.26).length
    wrong=sum(len(check.anatomy_sample(r,side,frames[side],3,0)['wrong_direction_joints']) for side in ('R','L'))
    if wrong or not all(check.finite_matrix(m) for m in pose.values()):failures.append([frame,'pose',wrong])
    if sec>=2.15 and error>.003:failures.append([frame,'two_hand_grip',error])
    rows.append({'frame':frame,'seconds':sec,'two_hand_error_m':error,'wrong_curls':wrong})
    if i%6==0 or abs(sec-1.40)<.021:
        fixtures.append({'seconds':sec,'bones':{n:list(Vector((p.x,p.z,-p.y))) for n,m in pose.items() for p in [r.matrix_world@m.translation]}})
    if i==144:final=pose
check.sample_action(r,bpy.data.actions['combat_idle_rh_v20'],1)
endpoint=max(abs(final[p.name][a][b]-p.matrix[a][b]) for p in r.pose.bones for a in range(4) for b in range(4))
if endpoint>1e-5:failures.append(['idle_endpoint',endpoint])
report={'passed':not failures,'failures':failures,'samples':len(rows),'preserved_meshes':len(baseline['meshes']),'preserved_actions':len(baseline['actions']),'rest_bones':107,'maximum_held_grip_error_m':max(x['two_hand_error_m'] for x in rows if x['seconds']>=2.15),'idle_endpoint_matrix_error':endpoint,'source_sha256':hashlib.sha256((FOLDER/'transformation_v26.blend').read_bytes()).hexdigest(),'rows':rows}
(OUT/'source_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert not failures,failures[:8]
(OUT/'pose_fixture.json').write_text(json.dumps({'clip':contract['clip'],'samples':fixtures,'left_offset':list(leftoff)},indent=2),encoding='utf-8')
for t in r.animation_data.nla_tracks:t.mute=True
r.animation_data.action=action;r.animation_data.action_slot=action.slots[0]
skinned=[o for o in bpy.data.objects if o.type=='MESH' and any(m.type=='ARMATURE' and m.object==r for m in o.modifiers)]
carrier=min(skinned,key=lambda o:len(o.data.vertices))
for ob in bpy.data.objects:ob.select_set(ob in (r,carrier))
bpy.context.view_layer.objects.active=r;scene.frame_start=1;scene.frame_end=73;scene.render.fps=24
EXPORT.mkdir(parents=True,exist_ok=True);GAME.mkdir(parents=True,exist_ok=True)
target=EXPORT/(contract['clip']+'.glb')
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_anim_slide_to_zero=True,export_def_bones=False,export_skins=True,export_morph=False,export_materials='NONE',export_extras=False,export_image_format='NONE')
(GAME/target.name).write_bytes(target.read_bytes());(GAME/'runtime_contract.json').write_bytes((FOLDER/'runtime_contract.json').read_bytes())
outfit=ROOT/'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb'   # unchanged v4 outfit stays at its v25 game path
report={'passed':True,'glb_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'outfit_sha256':hashlib.sha256(outfit.read_bytes()).hexdigest(),'carrier':carrier.name,'source_sha256':report['source_sha256']}
(OUT/'export.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('TRANSFORMATION_EXPORT_COMPLETE',report,flush=True)
