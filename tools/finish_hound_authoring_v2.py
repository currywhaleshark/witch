"""Set a usable packed-source opening view without changing delivery geometry."""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2'
def signature():
    import numpy as np
    result={}
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        a=np.empty(len(o.data.vertices)*3,dtype=np.float32);o.data.vertices.foreach_get('co',a)
        result[o.name]=hashlib.sha256(a.tobytes()).hexdigest()
    return result
for name in ['hound_geometry','hound_game_v2']:
    path=BASE/(name+'.blend');bpy.ops.wm.open_mainfile(filepath=str(path));before=signature();sc=bpy.context.scene
    for key in list(sc.keys()):del sc[key]
    sc.name='Hound_Game_v2' if name=='hound_game_v2' else 'Hound_Geometry_v2'
    sc['stage']='prepared rigid hound art; not gameplay integration'
    sc['source']='../hound_tripo_v1/hound_working.blend (preserved)'
    if name=='hound_game_v2':
        rig=bpy.data.objects['Hound_Rigid_Rig'];action=bpy.data.actions['idle']
        rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
        sc.frame_start=1;sc.frame_end=25;sc.frame_set(1)
        target=Vector((0,-.02,.34))
        sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1000;sc.render.resolution_y=760;sc.render.resolution_percentage=100
        sc.view_settings.view_transform='Khronos PBR Neutral'
        world=bpy.data.worlds.new('Hound_Authoring_World');world.use_nodes=True;sc.world=world
        bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.14,.17,.21,1);bg.inputs['Strength'].default_value=.4
        for n,pos,power,size in [('Key',(-1,2,3),280,3),('Fill',(2,1,1.7),140,2.5),('Rim',(1,-2,2.5),240,2)]:
            ld=bpy.data.lights.new(n,'AREA');ld.energy=power;ld.shape='DISK';ld.size=size
            ob=bpy.data.objects.new('Review_'+n,ld);sc.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
        cam=bpy.data.objects.new('Review_Camera',bpy.data.cameras.new('Review_Camera'));sc.collection.objects.link(cam);sc.camera=cam
        cam.location=target+Vector((-1.8,2.8,1.3));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=1.6
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type=='VIEW_3D':
                    space=area.spaces.active;space.region_3d.view_location=target;space.region_3d.view_distance=1.8;space.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
                    space.shading.type='MATERIAL';space.overlay.show_overlays=False
        for o in sc.objects:o.select_set(o.name=='Hound_Rigid_Surface')
        bpy.context.view_layer.objects.active=bpy.data.objects['Hound_Rigid_Surface']
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(path));assert signature()==before
print('HOUND_AUTHORING_VIEW_SAVED_GEOMETRY_EXACT',flush=True)
