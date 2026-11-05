"""Read-only joint/mesh inventory for the motion correction."""
import bpy, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/automation_motion_v2/local';OUT.mkdir(parents=True,exist_ok=True)
def dump(name,data): (OUT/name).write_text(json.dumps(data,indent=2),encoding='utf8')
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/actors/automation_batch2/motion_sources/quaternius/Wolf.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene
report={'fps':sc.render.fps,'range':[sc.frame_start,sc.frame_end],'objects':[],'actions':[],'rigs':{}}
for o in sc.objects:
    report['objects'].append({'name':o.name,'type':o.type,'matrix':[list(r) for r in o.matrix_world], 'modifiers':[(m.name,m.type) for m in o.modifiers]})
    if o.type=='ARMATURE':
        report['rigs'][o.name]={'bones':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None,'deform':b.use_deform,'constraints':[(c.name,c.type) for c in o.pose.bones[b.name].constraints]} for b in o.data.bones},'action':o.animation_data.action.name if o.animation_data and o.animation_data.action else None,'nla':[(t.name,[(s.name,s.action.name,s.frame_start,s.frame_end) for s in t.strips]) for t in o.animation_data.nla_tracks] if o.animation_data else []}
for a in bpy.data.actions:
    report['actions'].append({'name':a.name,'frames':list(a.frame_range),'slots':[(s.identifier,s.target_id_type) for s in a.slots], 'paths':sorted(set(fc.data_path for l in a.layers for s in l.strips for c in s.channelbags for fc in c.fcurves))})
dump('wolf_inventory.json',report)
print('WOLF',[(a['name'],a['frames']) for a in report['actions']],flush=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/actors/automation_batch2/giant_game_v1/giant_game_v1.blend'),load_ui=False,use_scripts=False)
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.find_armature())
dump('giant_mechanism_mesh.json',{n:{'vertices':[list(v.co) for v in mesh.data.vertices if any(g.group==mesh.vertex_groups[n].index for g in v.groups)],'faces':[[list(mesh.data.vertices[i].co) for i in p.vertices] for p in mesh.data.polygons if all(any(g.group==mesh.vertex_groups[n].index for g in mesh.data.vertices[i].groups) for i in p.vertices)]} for n in ('gear','key','core','torso')})
print('GIANT_MECHANISM_INVENTORY',flush=True)
