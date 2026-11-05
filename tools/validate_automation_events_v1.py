import bpy,json,sys,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'reports/automation_batch2_complete_v1/event_validation.json';result={}
for actor in ('beacon','giant'):
    base=ROOT/f'assets/actors/automation_batch2/{actor}_game_v1';bpy.ops.wm.open_mainfile(filepath=str(base/f'{actor}_game_v1.blend'))
    mesh=bpy.data.objects[actor+'_Rigid_Surface'];rig=mesh.find_armature();sc=bpy.context.scene
    def sample(clip,t):
        a=bpy.data.actions[clip];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0]
        f=1+t*24;sc.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
    def group(n):
        gi=mesh.vertex_groups[n].index;ids=[v.index for v in mesh.data.vertices if v.groups[0].group==gi];ids_set=set(ids)
        d=rig.pose.bones[n].matrix@rig.data.bones[n].matrix_local.inverted()
        vertices={i:d@mesh.data.vertices[i].co for i in ids};faces=[p.vertices[:] for p in mesh.data.polygons if p.vertices[0] in ids_set]
        return vertices,faces
    if actor=='giant':
        sample('slam',.55);fists={}
        for side in ('L','R'):
            ps,_=group('fist.'+side);fists[side]={'lowest_z':min(v.z for v in ps.values()),'center':[float(v) for v in np.mean([p[:] for p in ps.values()],axis=0)]}
            assert abs(fists[side]['lowest_z']-.012)<.00003
        socket=rig.pose.bones['Socket_attack'].matrix.translation
        assert abs(socket.x)<1e-6 and abs(socket.y-1.1)<1e-6 and abs(socket.z-.012)<1e-6
        result[actor]={'hit_seconds':.55,'fists':fists,'attack_socket_blender':list(socket),'passed':True}
    else:
        rows=[]
        for t in (0.,.25,.5,.75,1.):
            sample('pulse',t);bell,faces=group('bell');hammer,_=group('hammer');ids={n:i for i,n in enumerate(bell)}
            tree=BVHTree.FromPolygons(list(bell.values()),[[ids[n] for n in f] for f in faces],all_triangles=True)
            pivot=rig.data.bones['hammer'].head_local
            rest_dist={i:(mesh.data.vertices[i].co-pivot).length for i in hammer}
            threshold=np.quantile(list(rest_dist.values()),.65)
            distances=[tree.find_nearest(v)[3] for i,v in hammer.items() if rest_dist[i]>=threshold]
            rows.append({'seconds':t,'distal_hammer_to_bell_m':min(distances)})
        assert rows[0]['distal_hammer_to_bell_m']<.002
        assert rows[2]['distal_hammer_to_bell_m']>.04
        assert abs(rows[0]['distal_hammer_to_bell_m']-rows[-1]['distal_hammer_to_bell_m'])<1e-6
        result[actor]={'signal_seconds':0.,'distal_hammer_clearance_samples':rows,'passed':True}
out.write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(result),flush=True)
