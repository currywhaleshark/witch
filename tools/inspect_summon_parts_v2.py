"""Inspect the user's Tripo segmentation, preserving both downloaded GLBs."""
import bpy, json, math, sys, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/summons_v2'
OUT=ROOT/'reports/summons_v2/source'
for actor in ['automaton','turret']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source=BASE/'source'/f'{actor}_segmented_v2.glb'
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(source.with_suffix('.blend')))
    coords=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    lo=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    origin=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    turn=Matrix.Rotation(-math.pi/2 if actor=='turret' else math.pi,4,'Z')
    info={'id':actor,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'parts':[]}
    for o in meshes:
        world=o.matrix_world.copy()
        for v in o.data.vertices:v.co=turn@((world@v.co-origin)/(hi.z-lo.z))
        o.parent=None;o.matrix_world=Matrix.Identity(4)
        pts=[v.co for v in o.data.vertices]
        low=Vector(tuple(min(v[i] for v in pts) for i in range(3)))
        high=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
        info['parts'].append({'id':int(o.name.rsplit('_',1)[-1]),'name':o.name,'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'bounds':[list(low),list(high)],'center':list((low+high)/2)})
    info['parts'].sort(key=lambda p:p['id'])
    dest=OUT/actor;dest.mkdir(parents=True,exist_ok=True)
    (dest/'parts.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
    scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard'
    scene.world=bpy.data.worlds.new('Review');scene.world.color=(.05,.065,.08)
    for material in list(bpy.data.materials):
        if not material.use_nodes:continue
        bs=next((n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
        if bs and bs.inputs['Base Color'].is_linked:
            color=bs.inputs['Base Color'].links[0].from_socket
            em=material.node_tree.nodes.new('ShaderNodeEmission');output=next(n for n in material.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
            material.node_tree.links.new(color,em.inputs['Color']);material.node_tree.links.new(em.outputs[0],output.inputs['Surface'])
    camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));scene.collection.objects.link(camera);scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=1.55
    target=Vector((0,0,.5))
    for label,d in [('front',(2,4,1.7)),('back',(-2,-4,1.7)),('side',(4,0,1.2))]:
        camera.location=target+Vector(d);camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(dest/(label+'.png'));bpy.ops.render.render(write_still=True)
    print('SUMMON_SEGMENTS_INSPECTED',actor,len(meshes),flush=True)
