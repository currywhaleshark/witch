"""Inspect preserved Tripo actors and render cardinal views (no source edits)."""
import bpy, json, sys, math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
actor = sys.argv[sys.argv.index('--') + 1]
src = ROOT / 'assets/actors/combat_set_v1/source' / f'{actor}_tripo_h31_raw.glb'
out = ROOT / 'reports/combat_actors_v1/source' / actor
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(src))
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
coords = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
lo = Vector(tuple(min(v[i] for v in coords) for i in range(3)))
hi = Vector(tuple(max(v[i] for v in coords) for i in range(3)))
center = (lo + hi) / 2
size = hi-lo
info = {'actor':actor, 'bounds':[list(lo),list(hi)], 'meshes':[],'images':[]}
for o in meshes:
    info['meshes'].append({'name':o.name, 'vertices':len(o.data.vertices), 'triangles':sum(len(p.vertices)-2 for p in o.data.polygons), 'materials':[m.name for m in o.data.materials]})
for im in bpy.data.images:
    if im.type=='IMAGE':
        info['images'].append({'name':im.name,'size':list(im.size)})
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(src.with_suffix('.blend')))
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=640
scene.render.resolution_y=640
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='Standard'
scene.world.color=(0.25,0.25,0.25)
for o in meshes:
    for slot in o.material_slots:
        m=slot.material
        bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
        if not bs: continue
        if bs.inputs['Base Color'].is_linked:
            color=bs.inputs['Base Color'].links[0].from_socket
            output=next(n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
            em=m.node_tree.nodes.new('ShaderNodeEmission')
            m.node_tree.links.new(color,em.inputs['Color'])
            m.node_tree.links.new(em.outputs[0],output.inputs['Surface'])
camdata=bpy.data.cameras.new('InspectionCamera')
cam=bpy.data.objects.new('InspectionCamera',camdata)
scene.collection.objects.link(cam)
scene.camera=cam
camdata.type='ORTHO'
camdata.ortho_scale=max(size)*1.25
for name,direction in [('neg_y',(0,-3,.25)),('pos_y',(0,3,.25)),('neg_x',(-3,0,.25)),('pos_x',(3,0,.25))]:
    cam.location=center+Vector(direction)*max(size)
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(out/f'{name}.png')
    bpy.ops.render.render(write_still=True)
(out/'inspection.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
print('ACTOR_SOURCE_INSPECTED',actor,json.dumps(info))
