"""Join the sustained-cut loop to its entry's continuous forearm twist branch.

All joint and hand positions are preserved. Return uses the reversed entry, so
the actual continuous pose path closes instead of choosing a new 2*pi branch.
"""
import bpy,sys,json,ast,math
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v31'
REPORT=ROOT/'reports/drive_attack_v31'
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'drive_attack_v31.blend'),load_ui=False,use_scripts=False)
r=bpy.data.objects['PlayerRig_v7'];r.data.pose_position='POSE';s=bpy.context.scene
for tr in r.animation_data.nla_tracks:tr.mute=True
REST={b.name:b.matrix_local.copy() for b in r.data.bones};INV={n:m.inverted() for n,m in REST.items()}
def borrow(file,names):
    nodes=[n for n in ast.parse((ROOT/'tools'/file).read_text(encoding='utf-8')).body if isinstance(n,ast.FunctionDef) and n.name in names]
    exec(compile(ast.Module(body=nodes,type_ignores=[]),file,'exec'),globals())
borrow('build_combat_animations_v12.py',{'apply_desired'})
borrow('build_combat_motion_v18.py',{'write_action'})
contract=json.loads((SOURCE/'runtime_contract.json').read_text(encoding='utf-8'))
def sample(name):
    action=bpy.data.actions[name];r.animation_data.action=action;r.animation_data.action_slot=action.slots[0]
    bases=[];poses=[]
    for frame in range(1,contract['clips'][name]['frames']+1):
        s.frame_set(frame);bpy.context.view_layer.update()
        bases.append({p.name:p.matrix_basis.copy() for p in r.pose.bones})
        poses.append({p.name:p.matrix.copy() for p in r.pose.bones})
    return bases,poses
enter='drive_chainsaw_cut_enter_v31';loop='drive_chainsaw_cut_loop_v31';exit='drive_chainsaw_cut_exit_v31'
entry_basis,entry_pose=sample(enter);loop_basis,loop_pose=sample(loop)
correction={}
for n in loop_pose[0]:
    if n.startswith('DEF-forearm.') and n.endswith(('.001','.002')):
        delta=loop_pose[0][n].to_quaternion().inverted()@entry_pose[-1][n].to_quaternion()
        if delta.angle>.01:correction[n]=delta
if correction:
    values=[];max_head_error=0.
    for basis,pose in zip(loop_basis,loop_pose):
        r.animation_data.action=None
        for n,m in basis.items():r.pose.bones[n].matrix_basis=m
        bpy.context.view_layer.update()
        desired={n:m.copy() for n,m in pose.items()}
        for n,q in correction.items():
            m=desired[n];desired[n]=Matrix.LocRotScale(m.translation,m.to_quaternion()@q,Vector((1,1,1)))
        apply_desired(desired)
        max_head_error=max(max_head_error,max((p.matrix.translation-pose[p.name].translation).length for p in r.pose.bones))
        values.append({p.name:p.matrix_basis.copy() for p in r.pose.bones})
    values[0]={n:m.copy() for n,m in entry_basis[-1].items()};values[-1]={n:m.copy() for n,m in entry_basis[-1].items()}
    for name,new_values in [(loop,values),(exit,list(reversed(entry_basis)))]:
        old=bpy.data.actions[name];r.animation_data.action=None
        for tr in list(r.animation_data.nla_tracks):
            if any(st.action==old for st in tr.strips):r.animation_data.nla_tracks.remove(tr)
        bpy.data.actions.remove(old)
        if name==exit:
            for field in ('staff_slide_tracks','grip_spacing_tracks'):contract[field][name]=list(reversed(contract[field][enter]))
        action=write_action(name,new_values,contract['staff_slide_tracks'][name]);action['combat_loop']=contract['clips'][name]['loop']
        contract['clips'][name]['action_sha256']=check.action_digest(action)
    check.sample_action(r,bpy.data.actions['combat_idle_rh_v20'],1)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'drive_attack_v31.blend'))
    (SOURCE/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
    report={'corrected_bones':{n:math.degrees(q.angle) for n,q in correction.items()},'maximum_head_change_m':max_head_error,
            'loop_endpoints':'exact entry end, including skirt supports','exit':'reversed entry; unchanged duration and grip slide endpoints'}
    (REPORT/'join_polish.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('V31_JOIN_POLISHED',report,flush=True)
else:print('V31_JOIN_ALREADY_MATCHES',flush=True)
