"""Archive and inspect generated batch2 sources; never turn these into runtime assets.

Run with Blender --background --factory-startup --python this_file -- raw|segmented.
Keeps downloaded geometry/UV/materials unchanged. QA findings are source diagnostics.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ACTOR = sys.argv[sys.argv.index('--') + 1]
assert ACTOR in ('beacon','giant')
BASE = ROOT / ('assets/actors/automation_batch2/'+ACTOR+'_tripo_v1')
OUT = ROOT / ('reports/automation_batch2_complete_v1/'+ACTOR+'_source')
MODE = sys.argv[sys.argv.index('--') + 2]
assert MODE in ('raw', 'segmented') and bpy.app.background
SOURCE = BASE / 'source' / (ACTOR+'_' + MODE + '.glb')
DEST = OUT / MODE
DEST.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(Path.home() / '.agents/skills/blender-asset-qa/scripts'))
import qa_check
import review_shots


def write_json(path, obj):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding='utf-8')


def geometry_digest(obj):
    mesh = obj.data
    h = hashlib.sha256()
    for collection, prop, width, dtype in (
        (mesh.vertices, 'co', 3, np.float32),
        (mesh.loops, 'vertex_index', 1, np.int32),
        (mesh.polygons, 'loop_total', 1, np.int32),
        (mesh.polygons, 'material_index', 1, np.int32),
    ):
        data = np.empty(len(collection) * width, dtype=dtype)
        collection.foreach_get(prop, data)
        h.update(data.tobytes())
    for uv in mesh.uv_layers:
        data = np.empty(len(uv.data) * 2, dtype=np.float32)
        uv.data.foreach_get('uv', data)
        h.update(data.tobytes())
    h.update(np.asarray(obj.matrix_world, dtype=np.float64).tobytes())
    return h.hexdigest()


bpy.ops.wm.read_factory_settings(use_empty=True)
assert bpy.ops.import_scene.gltf(filepath=str(SOURCE)) == {'FINISHED'}
sc = bpy.context.scene
sc.name = 'Generated_' + MODE + '_Source_Inspection'
meshes = sorted((o for o in sc.objects if o.type == 'MESH'), key=lambda o: o.name)
before = {o.name: geometry_digest(o) for o in meshes}
points = np.asarray([list(o.matrix_world @ v.co) for o in meshes for v in o.data.vertices])
lo, hi = points.min(axis=0), points.max(axis=0)
center = Vector((lo + hi) / 2)
span = float(max(hi - lo))
parts = []
for ob in meshes:
    pp = np.asarray([list(ob.matrix_world @ v.co) for v in ob.data.vertices])
    parts.append({'name': ob.name, 'vertices': len(ob.data.vertices),
                  'triangles': sum(len(p.vertices)-2 for p in ob.data.polygons),
                  'bounds_blender': [pp.min(axis=0).tolist(), pp.max(axis=0).tolist()],
                  'center_blender': ((pp.min(axis=0)+pp.max(axis=0))/2).tolist(),
                  'material_slots': [m.name if m else None for m in ob.data.materials],
                  'geometry_uv_transform_sha256': before[ob.name]})
blob = SOURCE.read_bytes()
length, kind = struct.unpack_from('<II', blob, 12)
assert kind == 0x4e4f534a
gltf = json.loads(blob[20:20+length])
inventory = {'source': SOURCE.relative_to(ROOT).as_posix(),
    'source_sha256': hashlib.sha256(blob).hexdigest(), 'source_bytes': len(blob),
    'status': 'generated source; no game-ready rig, reduction or joint cleanup',
    'blender': bpy.app.version_string, 'mesh_count': len(meshes),
    'triangles': sum(p['triangles'] for p in parts),
    'vertices': sum(p['vertices'] for p in parts),
    'bounds_blender': [lo.tolist(), hi.tolist()], 'dimensions_source_units': (hi-lo).tolist(),
    'gltf': {'meshes':len(gltf.get('meshes',[])), 'materials':len(gltf.get('materials',[])),
             'skins':len(gltf.get('skins',[])), 'animations':len(gltf.get('animations',[]))},
    'parts':parts,
    'images':[{'name':im.name, 'size':list(im.size), 'color_space':im.colorspace_settings.name}
              for im in bpy.data.images if im.type != 'RENDER_RESULT']}
write_json(DEST/'inventory.json', inventory)
print('INVENTORY', MODE, len(meshes), inventory['triangles'], flush=True)

sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 900
sc.render.resolution_y = 900
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.film_transparent = False
try:
    sc.view_settings.view_transform = 'Khronos PBR Neutral'
except TypeError:
    sc.view_settings.view_transform = 'AgX'
world = bpy.data.worlds.new('Generated_Source_ReviewWorld')
world.use_nodes = True
sc.world = world
bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs['Color'].default_value = (.15, .17, .20, 1)
bg.inputs['Strength'].default_value = .4
for label, vec, energy, size in (
    ('Key',(1,-2,3),650,3), ('Fill',(-2,-1,1.4),350,2.5), ('Rim',(1,2,2),500,2)):
    data = bpy.data.lights.new('Review_'+label, 'AREA')
    data.energy = energy * span * span * .4
    data.shape = 'DISK'
    data.size = size * span
    ob = bpy.data.objects.new('Review_'+label, data)
    sc.collection.objects.link(ob)
    ob.location = center + Vector(vec)*span
    ob.rotation_euler = (center-ob.location).to_track_quat('-Z','Y').to_euler()
camera = bpy.data.objects.new('Review_Camera', bpy.data.cameras.new('Review_Camera'))
sc.collection.objects.link(camera)
sc.camera = camera
camera.data.type = 'ORTHO'
camera.data.ortho_scale = span*1.45
camera.data.clip_start = span*.001
camera.data.clip_end = span*100
views = [('three_quarter',(1,-1.5,.85)), ('opposite',(-1,1.5,.85)),
         ('side',(1,0,.12)), ('top',(0,-.05,1))]
for label,direction in views:
    camera.location = center + Vector(direction).normalized()*span*4
    camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath = str(DEST/(label+'.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDER', MODE, label, flush=True)

# Save an editable packed source with its imported geometry, material nodes and UV intact.
camera.location = center + Vector(views[0][1]).normalized()*span*4
camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
for ob in sc.objects:
    ob.select_set(ob in meshes)
bpy.context.view_layer.objects.active = meshes[0]
sc['source_status'] = inventory['status']
sc['source_glb_sha256'] = inventory['source_sha256']
sc['no_geometry_uv_transform_edits'] = True
bpy.ops.file.pack_all()
blend = BASE / (ACTOR+'_'+MODE+'.blend')
bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
assert {o.name:geometry_digest(o) for o in meshes} == before
qa = qa_check.run(objects=[o.name for o in meshes], profile='game', eps=.0002, tol=.003)
write_json(DEST/'source_qa.json',qa)
print('SOURCE_QA', MODE, 'errors', len(qa['errors']), 'warnings',len(qa['warnings']), flush=True)
for mode in (('random','wire') if MODE == 'segmented' else ('wire',)):
    result=review_shots.run(objects=[o.name for o in meshes], out=str(DEST/(mode+'.png')),
                            views=['front','back','right','three_quarter'], mode=mode, res=512)
    write_json(DEST/(mode+'_shots.json'),result)
# Verify the saved file, not just the in-memory session.
bpy.ops.wm.open_mainfile(filepath=str(blend))
reopened = [o for o in bpy.context.scene.objects if o.type == 'MESH']
assert {o.name:geometry_digest(o) for o in reopened} == before
assert all(im.packed_file or im.packed_files for im in bpy.data.images if im.source == 'FILE')
write_json(DEST/'preservation.json', {'saved_reopened_geometry_uv_material_indices_transforms_exact':True,
    'packed_file_images':True, 'mesh_count':len(reopened), 'geometry_digests':before,
    'raw_glb_sha256_unchanged':hashlib.sha256(SOURCE.read_bytes()).hexdigest()==inventory['source_sha256'],
    'blend_bytes':blend.stat().st_size})
print('COMPLETE', MODE, str(blend), flush=True)
