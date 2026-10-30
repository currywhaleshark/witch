"""Reopen the saved jump, check preservation/grip, export one animation on the shared rig."""
import bpy, json, hashlib, sys, math
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/spring_jump_v24'
FOLDER=ROOT/'assets/characters/player/3d/source/middle_school_v1/spring_jump_v24'
EXPORT=ROOT/'assets/characters/player/3d/exports/spring_jump_v24'
GAME=ROOT/'game/assets/characters/player/spring_jump_v24'
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
from hand_anatomy_v13 import AnatomicalHandRig
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(FOLDER/'spring_jump_v24.blend'))
r=bpy.data.objects['PlayerRig_v7'];scene=bpy.context.scene
baseline=json.loads((OUT/'protected_baseline.json').read_text(encoding='utf-8'))
after=check.snapshot(r.name,set())
assert baseline['meshes']==after['meshes'] and baseline['rig']==after['rig']
assert all(after['actions'][name]==digest for name,digest in baseline['actions'].items())
old=json.loads((FOLDER.parent/'thrust_v23/runtime_contract.json').read_text(encoding='utf-8'))
contract=json.loads((FOLDER/'runtime_contract.json').read_text(encoding='utf-8'))
hands=AnatomicalHandRig(r);off=Vector(old['staff_attachment']['offset_bone_local'])
axis_local=Matrix(old['staff_attachment']['basis_columns_bone_local']).transposed()@Vector((0,1,0))
leftoff=sum((hands.axes['L'][k]*off.dot(hands.axes['R'][k]) for k in ('thumb','finger','palm')),Vector())
frames={side:check.hand_frame(r,side,Vector((-1,0,0))) for side in ('L','R')}
name=contract['clip'];action=bpy.data.actions[name]
rows=[];fixtures=[];failures=[]
for i in range(97):
    frame=1+i/2;phase=(frame-1)/48
    check.sample_action(r,action,int(frame));scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
    pose={pb.name:pb.matrix.copy() for pb in r.pose.bones}
    right=pose['DEF-hand.R']@off;left=pose['DEF-hand.L']@leftoff
    axis=(pose['DEF-hand.R'].to_3x3()@axis_local).normalized()
    error=(left-right+axis*.26).length
    wrong=sum(len(check.anatomy_sample(r,side,frames[side],3,0)['wrong_direction_joints']) for side in ('L','R'))
    air=max(0.,min(1.,(phase-.25)/.5));height=.32*4*air*(1-air)
    shoe=bpy.data.objects['Outfit_Shoes_v7'].evaluated_get(bpy.context.evaluated_depsgraph_get())
    floor=min((shoe.matrix_world@v.co).z for v in shoe.data.vertices)*(1.5/1.711)+height
    if wrong or error>.003 or not all(check.finite_matrix(m) for m in pose.values()):failures.append([frame,'pose',wrong,error])
    if floor<-.005:failures.append([frame,'shoe_floor',floor])
    rows.append({'frame':frame,'grip_error_m':error,'wrong_curls':wrong,'shoe_floor_with_runtime_arc_m':floor})
    if i%6==0:
        # glTF Y-up conversion, before the runtime facing wrapper and character scale.
        points={n:list(Vector((p.x,p.z,-p.y))) for n,m in pose.items() for p in [r.matrix_world@m.translation]}
        fixtures.append({'seconds':(frame-1)/24,'bones':points})
    if i==0:first=pose
    if i==96:endpoint=max(abs(pose[n][a][b]-first[n][a][b]) for n in pose for a in range(4) for b in range(4))
assert endpoint<1e-5
report={'passed':not failures,'failures':failures,'samples':len(rows),'preserved_meshes':len(baseline['meshes']),'preserved_actions':len(baseline['actions']),'rest_bones':107,'maximum_grip_error_m':max(x['grip_error_m'] for x in rows),'minimum_shoe_floor_m':min(x['shoe_floor_with_runtime_arc_m'] for x in rows),'endpoint_matrix_error':endpoint,'source_sha256':hashlib.sha256((FOLDER/'spring_jump_v24.blend').read_bytes()).hexdigest(),'rows':rows}
(OUT/'source_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert not failures,failures[:4]
(OUT/'pose_fixture.json').write_text(json.dumps({'clip':name,'samples':fixtures,'left_offset':list(leftoff)},indent=2),encoding='utf-8')
for track in r.animation_data.nla_tracks:track.mute=True
r.animation_data.action=action;r.animation_data.action_slot=action.slots[0]
skinned=[o for o in bpy.data.objects if o.type=='MESH' and any(m.type=='ARMATURE' and m.object==r for m in o.modifiers)]
carrier=min(skinned,key=lambda o:len(o.data.vertices))
for ob in bpy.data.objects:ob.select_set(ob in (r,carrier))
bpy.context.view_layer.objects.active=r;scene.frame_start=1;scene.frame_end=49;scene.render.fps=24
EXPORT.mkdir(parents=True,exist_ok=True);GAME.mkdir(parents=True,exist_ok=True)
target=EXPORT/(name+'.glb')
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_anim_slide_to_zero=True,export_def_bones=False,export_skins=True,export_morph=False,export_materials='NONE',export_extras=False,export_image_format='NONE')
(GAME/target.name).write_bytes(target.read_bytes())
(GAME/'runtime_contract.json').write_bytes((FOLDER/'runtime_contract.json').read_bytes())
report={'passed':True,'glb_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'bytes':target.stat().st_size,'carrier':carrier.name,'frames':49,'clip':name,'source_sha256':report['source_sha256']}
(OUT/'export.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SPRING_JUMP_EXPORT_COMPLETE',report,flush=True)
