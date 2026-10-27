"""Measure actual delivered skin deformation, including long surface edges."""
import bpy,sys,json,math
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
ids=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['rag','crow','brute','automaton','turret']
for actor in ids:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/actors/combat_set_v1/authoring'/f'{actor}_v1.blend'))
    obj=bpy.data.objects[f'{actor}_surface'];rig=bpy.data.objects[f'{actor}_rig']
    scene=bpy.context.scene
    positions=np.array([v.co[:] for v in obj.data.vertices])
    edges=np.array([e.vertices[:] for e in obj.data.edges])
    rest=np.linalg.norm(positions[edges[:,0]]-positions[edges[:,1]],axis=1)
    meaningful=rest>.008
    records=[]
    for action in bpy.data.actions:
        rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
        worst=np.ones(len(edges));worstframe=np.zeros(len(edges),dtype=int)
        for f in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
            scene.frame_set(f);bpy.context.view_layer.update()
            ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            coords=np.array([v.co[:] for v in ev.data.vertices])
            ratio=np.linalg.norm(coords[edges[:,0]]-coords[edges[:,1]],axis=1)/np.maximum(rest,1e-9)
            higher=ratio>worst;worst[higher]=ratio[higher];worstframe[higher]=f
        ids_=np.where(meaningful & (worst>2.5))[0]
        ids_=ids_[np.argsort(worst[ids_])[::-1]][:12]
        records.append({'clip':action.name,'over_2_5':int(np.sum(meaningful&(worst>2.5))),
            'max_ratio':float(worst[meaningful].max()),'worst':[{'ratio':float(worst[i]),'frame':int(worstframe[i]),
            'vertices':[{'id':int(v),'co':positions[v].tolist(),'weights':{obj.vertex_groups[g.group].name:g.weight for g in obj.data.vertices[v].groups}} for v in edges[i]]} for i in ids_]})
    (ROOT/'reports/combat_actors_v1/build'/actor/'deformation.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
    print('DEFORMATION',actor,json.dumps([{k:v for k,v in r.items() if k!='worst'} for r in records]),flush=True)
