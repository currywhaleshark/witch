"""Remove four sub-mm generated overlap slivers, preserving every retained corner."""
import bpy
import json

ROOT = 'C:/Users/yurib/Documents/New project/witch'
bpy.context.window.scene = bpy.data.scenes['ExoskeletonV2_Working']
scene = bpy.context.scene
obj = bpy.data.objects['ExoskeletonV2_WorkingMesh']
old = obj.data
assert len(old.polygons) == 78478
remove = {78476, 52552, 65577, 78463}
assert all(old.polygons[i].area < 2e-7 for i in remove)
keep = [p for p in old.polygons if p.index not in remove]
used = sorted({i for p in keep for i in p.vertices})
mapping = {old_index: new_index for new_index, old_index in enumerate(used)}
mesh = bpy.data.meshes.new('ExoskeletonV2_OverlapCleaned')
mesh.from_pydata([tuple(old.vertices[i].co) for i in used], [], [tuple(mapping[i] for i in p.vertices) for p in keep])
for mat in old.materials: mesh.materials.append(mat)
new_uv = mesh.uv_layers.new(name=old.uv_layers.active.name)
uv = old.uv_layers.active.data
normals = []
for src, dst in zip(keep, mesh.polygons):
    dst.material_index = src.material_index
    dst.use_smooth = src.use_smooth
    for a,b in zip(src.loop_indices,dst.loop_indices):
        new_uv.data[b].uv = uv[a].uv
        normals.append(tuple(old.corner_normals[a].vector))
mesh.normals_split_custom_set(normals)
mesh.update()
obj.data = mesh
info = json.loads(scene['cleanup_json'])
info['removed_overlap_slivers'] = [{'original_polygon': i, 'area_m2': old.polygons[i].area} for i in sorted(remove)]
info['geometry_changed'] = True
info['retained_vertex_positions_unchanged'] = True
info['original_vertex_indices'] = used
info['retained_original_polygon_indices'] = [p.index for p in keep]
info['triangles_after'] = len(mesh.polygons)
scene['cleanup_json'] = json.dumps(info)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v2/exoskeleton_v2_working.blend')
for ob in scene.objects: ob.select_set(ob == obj)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v2/exports/exoskeleton_v2_working.glb',export_format='GLB',use_active_scene=True,use_selection=True,export_animations=False,export_yup=True)
print('EXO_OVERLAP_REPAIRED',len(mesh.vertices),len(mesh.polygons))
