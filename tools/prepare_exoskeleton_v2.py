"""Live-MCP derivative: repair collapsed UV triangles without changing generated geometry."""
import bpy
import json
from mathutils import Vector

ROOT = 'C:/Users/yurib/Documents/New project/witch'
assert bpy.data.scenes.get('ExoskeletonV2_Working') is None
raw = bpy.data.objects['ExoskeletonV2_RawMesh']
scene = bpy.data.scenes.new('ExoskeletonV2_Working')
scene.world = bpy.data.scenes['ExoskeletonV2_Raw'].world
scene.unit_settings.system = 'METRIC'
bpy.context.window.scene = scene
obj = raw.copy()
obj.data = raw.data.copy()
obj.name = 'ExoskeletonV2_WorkingMesh'
scene.collection.objects.link(obj)
uv = obj.data.uv_layers.active.data
fixed = []
for poly in obj.data.polygons:
    indices = list(poly.loop_indices)
    points = [uv[i].uv.copy() for i in indices]
    a, b, c = points
    area2 = (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
    if abs(area2) >= 1e-12:
        continue
    edge = 0
    for i in range(1, 3):
        if (points[(i+1)%3]-points[i]).length_squared > (points[(edge+1)%3]-points[edge]).length_squared:
            edge = i
    direction = points[(edge+1)%3]-points[edge]
    other = (edge+2)%3
    offset = Vector((-direction.y, direction.x)).normalized()/8192 if direction.length > 1e-8 else Vector((1/8192, 1/8192))
    uv[indices[other]].uv += offset
    fixed.append({'polygon': poly.index, 'loop': indices[other], 'offset': list(offset)})
obj.data.update()
scene['cleanup_json'] = json.dumps({'uv_faces_repaired': fixed, 'geometry_changed': False, 'max_uv_offset_texels_at_2048': .25})
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v2/exoskeleton_v2_working.blend')
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v2/exports/exoskeleton_v2_working.glb', export_format='GLB', use_selection=True, use_active_scene=True, export_animations=False, export_yup=True)
print('EXO_WORKING_PREPARED', len(fixed), len(obj.data.polygons))
