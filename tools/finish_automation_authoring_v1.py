"""Prepare a usable opening view; prove geometry and actions stay identical."""
import bpy,json,hashlib,sys,numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
def signature():
    meshes={};actions={};rests={}
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH':
            arrays=[np.array([v.co[:] for v in ob.data.vertices],dtype='<f4').tobytes(),np.array([p.vertices[:] for p in ob.data.polygons],dtype='<i4').tobytes()]
            arrays.extend(np.array([u.uv[:] for u in layer.data],dtype='<f4').tobytes() for layer in ob.data.uv_layers)
            meshes[ob.name]=hashlib.sha256(b''.join(arrays)).hexdigest()
        if ob.type=='ARMATURE':rests[ob.name]={b.name:[list(r) for r in b.matrix_local] for b in ob.data.bones}
    for a in bpy.data.actions:
        raw=[]
        for layer in a.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:raw.append([fc.data_path,fc.array_index,[[*k.co,k.interpolation] for k in fc.keyframe_points]])
        actions[a.name]=hashlib.sha256(json.dumps(raw).encode()).hexdigest()
    return {'meshes':meshes,'actions':actions,'rests':rests}
for actor in ['beacon','giant','hound_armour','giant_armour']:
    folder=ROOT/f"assets/actors/automation_batch2/{actor}{'_v1' if actor.endswith('_armour') else '_game_v1'}"
    path=folder/f'{actor}_game_v1.blend';bpy.ops.wm.open_mainfile(filepath=str(path));sc=bpy.context.scene;before=signature()
    for ob in [o for o in sc.objects if o.type in ('LIGHT','CAMERA')]:bpy.data.objects.remove(ob,do_unlink=True)
    for arm in [o for o in sc.objects if o.type=='ARMATURE']:
        clip='pulse' if actor=='beacon' else 'idle'
        if actor.endswith('_armour') and arm!=bpy.data.objects[actor+'_Rigid_Surface'].find_armature():clip='BasePreview_idle'
        a=bpy.data.actions[clip];arm.animation_data.action=a;arm.animation_data.action_slot=a.slots[0]
        for track in arm.animation_data.nla_tracks:track.mute=True
    scale=.9 if actor.startswith('hound') else 1.5 if actor=='beacon' else 2.8
    target=Vector((0,0,scale*.46));sc.frame_start=1;sc.frame_end=25 if actor in ('beacon','hound_armour') else 49;sc.frame_set(1)
    sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1000;sc.render.resolution_y=760;sc.render.resolution_percentage=100
    sc.view_settings.view_transform='Khronos PBR Neutral'
    world=bpy.data.worlds.new('Authoring_Studio');world.use_nodes=True;sc.world=world
    bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.14,.17,.21,1);bg.inputs['Strength'].default_value=.4
    for n,pos,e,size in [('Key',(-1,2,3),280,3),('Fill',(2,1,1.7),140,2.5),('Rim',(1,-2,2.5),240,2)]:
        ld=bpy.data.lights.new(n,'AREA');ld.energy=e*scale*scale;ld.shape='DISK';ld.size=size*scale
        ob=bpy.data.objects.new('Studio_'+n,ld);sc.collection.objects.link(ob);ob.location=Vector(pos)*scale;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
    cam=bpy.data.objects.new('Studio_Camera',bpy.data.cameras.new('Studio_Camera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=scale*1.65
    cam.location=target+Vector((-1.8,2.8,1.3))*scale;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active;space.region_3d.view_location=target;space.region_3d.view_distance=scale*2.1;space.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
                space.shading.type='MATERIAL';space.overlay.show_overlays=False
    for ob in sc.objects:ob.select_set(ob.name==actor+'_Rigid_Surface')
    bpy.context.view_layer.objects.active=bpy.data.objects[actor+'_Rigid_Surface']
    sc['prepared_only']=True;sc['preview']='idle/pulse; auxiliary armour source includes unchanged base reference on separate rig'
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(path));assert signature()==before
    out=ROOT/f'reports/automation_batch2_complete_v1/{actor}/validation/authoring_preservation.json'
    out.write_text(json.dumps({'passed':True,'meshes_rests_actions_exact':True,'signature':before,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest()},indent=2),encoding='utf8')
    print('AUTHORING_FINISHED',actor,flush=True)
