import bpy, json, hashlib, math
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'assets/characters/player/3d/source/motion_library/mixamo_local/Unarmed_Jump_user_2026-10-30.fbx'
OUT=ROOT/'reports/spring_jump_v24'
assert bpy.app.background
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps=30
bpy.ops.import_scene.fbx(filepath=str(PATH),use_anim=True)
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
action=rig.animation_data.action
prefix=next(b.name[:-4] for b in rig.data.bones if b.name.endswith('Hips'))
rest={b.name.removeprefix(prefix):rig.matrix_world@b.matrix_local for b in rig.data.bones}
forward=sum((rest[s+'ToeBase'].translation-rest[s+'Foot'].translation for s in ('Left','Right')),Vector());forward.z=0;forward.normalize()
align=Matrix.Rotation(-math.pi/2-math.atan2(forward.y,forward.x),4,'Z')
rows=[]
for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
    bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
    points={n:list((align@rig.matrix_world@rig.pose.bones[prefix+n].matrix).translation) for n in ['Hips','Spine2','Head','LeftUpLeg','LeftLeg','LeftFoot','LeftToeBase','RightUpLeg','RightLeg','RightFoot','RightToeBase','LeftHand','RightHand']}
    rows.append({'frame':frame,'points':points})
report={'source':str(PATH.relative_to(ROOT)),'sha256':hashlib.sha256(PATH.read_bytes()).hexdigest(),'action':action.name,'fps':bpy.context.scene.render.fps,'frames':list(action.frame_range),'objects':[(o.name,o.type) for o in bpy.data.objects],'bones':list(rest),'rest':{n:[list(row) for row in align@m] for n,m in rest.items()},'samples':rows}
(OUT/'source_inspection.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('JUMP_SOURCE',report['action'],report['frames'],report['fps'],report['objects'],flush=True)
for row in rows[::max(1,len(rows)//20)]:print('POSE',row['frame'],{n:[round(v,3) for v in row['points'][n]] for n in ['Hips','LeftFoot','RightFoot','LeftLeg','RightLeg']},flush=True)
