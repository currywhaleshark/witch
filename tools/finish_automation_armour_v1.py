"""Keep live clips exact; bake a separate rigid collapse for detachable armour.

The original actor and its actions stay in the source as a preview reference.
Only the additive armour gets its own skeleton/action copy at destruction.
"""
import sys,copy
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from automation_rigid_common import *
actor=sys.argv[sys.argv.index('--')+1];assert actor in ('hound','giant')
name=actor+'_armour';base=ROOT/f'assets/actors/automation_batch2/{name}_v1';out=ROOT/f'reports/automation_batch2_complete_v1/{name}'
bpy.ops.wm.open_mainfile(filepath=str(base/f'{name}_game_v1.blend'))
sc=bpy.context.scene;mesh=bpy.data.objects[name+'_Rigid_Surface'];original=mesh.find_armature()
contract=json.loads((base/'rig.json').read_text(encoding='utf8'))
records=json.loads((out/'local/animation_samples.json').read_text(encoding='utf8'))
rests={n:Matrix(m) for n,m in contract['rest_world'].items()}
base_actions={n:bpy.data.actions[n] for n in contract['clips']}
detach=.18 if actor=='hound' else .22
original.animation_data.action=base_actions['death'];original.animation_data.action_slot=base_actions['death'].slots[0]
frame=1+detach*24;sc.frame_set(int(frame),subframe=frame%1);bpy.context.view_layer.update()
points=part_points(mesh)
initial={n:original.pose.bones[n].matrix@rests[n].inverted() for n in points}
duration=contract['clips']['death']['seconds']
falls=collapse(points,initial,duration-detach,delay=0)
for row in records['death']:
    if row['time']<=detach:continue
    f=(row['time']-detach)/(duration-detach)*(len(falls)-1);i=min(int(f),len(falls)-2);u=f-i
    for n in points:
        a,b=falls[i][n],falls[i+1][n]
        d=Matrix.Translation(a.translation.lerp(b.translation,u))@a.to_quaternion().slerp(b.to_quaternion(),u).to_matrix().to_4x4()
        row['world'][n]=[list(r) for r in d@rests[n]]
for clip,a in base_actions.items():a.name='BasePreview_'+clip
original.animation_data.action=base_actions['idle'];original.animation_data.action_slot=base_actions['idle'].slots[0]
rig=original.copy();rig.data=original.data.copy();rig.name=name+'_Rig';sc.collection.objects.link(rig)
rig.animation_data_clear();rig.animation_data_create()
for pb in rig.pose.bones:pb.matrix_basis=I
mesh.parent=rig
for modifier in mesh.modifiers:
    if modifier.type=='ARMATURE':modifier.object=rig
spec={b.name:(b.head_local.copy(),b.parent.name if b.parent else None) for b in rig.data.bones}
def pose(clip,t):
    row=min(records[clip],key=lambda r:abs(r['time']-t))
    if abs(row['time']-t)<1e-6:
        result={n:Matrix(row['world'][n])@rests[n].inverted() for n in spec}
    else:
        original.animation_data.action=base_actions[clip];original.animation_data.action_slot=base_actions[clip].slots[0]
        frame=1+t*24;sc.frame_set(int(frame),subframe=frame%1);bpy.context.view_layer.update()
        result={n:original.pose.bones[n].matrix.copy()@rests[n].inverted() for n in spec}
    if clip=='death' and t>detach:
        f=(t-detach)/(duration-detach)*(len(falls)-1);i=min(int(f),len(falls)-2);u=f-i
        for n in points:
            a,b=falls[i][n],falls[i+1][n]
            result[n]=Matrix.Translation(a.translation.lerp(b.translation,u))@a.to_quaternion().slerp(b.to_quaternion(),u).to_matrix().to_4x4()
        # Unused descendant bones follow their detached parent. Keeping their
        # unrelated base-world trajectory would create large cancelling local
        # translations and unnecessary float error; no armour vertex uses them.
        changed=set(points)
        for n,(_,parent) in spec.items():
            if n not in points and parent in changed:result[n]=result[parent];changed.add(n)
    return result
clips={n:(c['seconds'],c['loop']) for n,c in contract['clips'].items()}
metadata={k:v for k,v in contract.items() if k not in ('clips','parts','bones','triangles','parts_metadata','sockets','rest_world')}
metadata['death_armour_detach_seconds']=detach
metadata['playback']='Sample the base and this additive armour with the same clip/time. Living bone poses match exactly; death detaches armour into its own baked floor-supported fall.'
write_actions(name,base,out,mesh,rig,spec,clips,pose,events={n:[r['time'] for r in rows] for n,rows in records.items()},metadata=metadata)
p=json.loads((base/'preservation.json').read_text(encoding='utf8'));p['death_armour_only']=True;p['living_actions_exact']=True;p['death_detach_seconds']=detach;dump(base/'preservation.json',p)
print('ARMOUR_COLLAPSE_FINISHED',name,detach,flush=True)
