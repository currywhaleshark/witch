"""Verify the saved overlap repair and a fresh GLB import without modifying sources."""
import bpy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / '.agents/skills/blender-asset-qa/scripts'))
import qa_check

R = ROOT / 'reports/exoskeleton_v2'
scene = bpy.data.scenes['ExoskeletonV2_Working']
bpy.context.window.scene = scene
obj = bpy.data.objects['ExoskeletonV2_WorkingMesh']
raw = bpy.data.objects['ExoskeletonV2_RawMesh']
info = json.loads(scene['cleanup_json'])
vertex_ids = info.pop('original_vertex_indices')
polygon_ids = info.pop('retained_original_polygon_indices')
assert len(obj.data.vertices) == len(vertex_ids) == 46139
assert len(obj.data.polygons) == len(polygon_ids) == 78474
assert all(raw.data.vertices[a].co == b.co for a,b in zip(vertex_ids,obj.data.vertices))
max_normal_difference = 0.0
changed_uv_faces = 0
max_uv_difference = 0.0
for original_id, polygon in zip(polygon_ids,obj.data.polygons):
    original = raw.data.polygons[original_id]
    assert tuple(vertex_ids[i] for i in polygon.vertices) == tuple(original.vertices)
    uv_changed = False
    for a,b in zip(original.loop_indices,polygon.loop_indices):
        max_normal_difference = max(max_normal_difference,(raw.data.corner_normals[a].vector-obj.data.corner_normals[b].vector).length)
        distance = (raw.data.uv_layers.active.data[a].uv-obj.data.uv_layers.active.data[b].uv).length
        max_uv_difference = max(max_uv_difference,distance)
        uv_changed |= distance > 1e-8
    changed_uv_faces += uv_changed
# Blender re-encodes split normals into its compact corner representation.
# Require less than 0.05 degrees of vector-direction error after that encoding.
assert max_normal_difference < .00087266, max_normal_difference
assert changed_uv_faces == 12 and max_uv_difference*2048 < .251
source = qa_check.run(objects=[obj.name],profile='game',eps=.0002,tol=.006)
fresh = bpy.data.scenes.new('QA_ExoskeletonV2_Reimport')
bpy.context.window.scene = fresh
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/equipment/exoskeleton_v2/exports/exoskeleton_v2_working.glb'))
imports = [o for o in fresh.objects if o.type=='MESH']
assert len(imports)==1
imports[0].data.calc_loop_triangles()
assert len(imports[0].data.loop_triangles)==78474
reimport = qa_check.run(objects=[imports[0].name],profile='game',eps=.0002,tol=.006)
report = {'passed':source['pass'] and reimport['pass'], 'cleanup':info,
    'preservation':{'all_retained_vertex_positions_exact':True,'all_retained_face_connectivity_exact':True,
        'max_retained_corner_normal_vector_difference':max_normal_difference,
        'uv_faces_changed':changed_uv_faces,'max_uv_difference_texels_at_2048':max_uv_difference*2048},
    'source':source,'reimport':reimport,
    'pre_cleanup_evidence':'pre_cleanup_qa.json',
    'limits':['12 UV faces repaired and four overlap slivers removed; source GLB unchanged.',
        'UV seams and tiny open repair boundaries retained in this source-stage candidate; not watertight retopology.',
        'No fitting, joint segmentation, rig or runtime integration.']}
(R/'working_qa.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('EXO_FINAL_QA',json.dumps({'passed':report['passed'],'preservation':report['preservation'],
    'source_errors':source['errors'],'reimport_errors':reimport['errors'],'source_warnings':source['warnings'],
    'reimport_warnings':reimport['warnings']}),flush=True)
assert report['passed']
