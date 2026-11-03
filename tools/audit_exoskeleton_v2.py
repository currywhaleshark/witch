"""Read-only audit of the immutable generated exoskeleton and packed Blender import."""
import bpy
import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / '.agents/skills/blender-asset-qa/scripts'))
import qa_check

REPORT = ROOT / 'reports/exoskeleton_v2'
SOURCE = ROOT / 'assets/equipment/exoskeleton_v2/source/exoskeleton_tripo_h31_raw.glb'


def main():
    scene = bpy.data.scenes['ExoskeletonV2_Raw']
    bpy.context.window.scene = scene
    objects = [o for o in scene.objects if o.type == 'MESH']
    raw = SOURCE.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    json_length, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    gltf = json.loads(raw[20:20 + json_length])
    primitives = [p for m in gltf.get('meshes', []) for p in m['primitives']]
    gltf_tris = sum(gltf['accessors'][p['indices']]['count'] // 3 for p in primitives)
    gltf_verts = sum(gltf['accessors'][p['attributes']['POSITION']]['count'] for p in primitives)
    meshes = {}
    for ob in objects:
        ob.data.calc_loop_triangles()
        meshes[ob.name] = {
            'vertices': len(ob.data.vertices),
            'triangles': len(ob.data.loop_triangles),
            'dimensions_m': list(ob.dimensions),
            'material_slots': len(ob.material_slots),
            'armature_modifiers': sum(m.type == 'ARMATURE' for m in ob.modifiers),
        }
    inventory = {
        'status': 'generated_raw_source_not_fitted_or_rigged',
        'raw_sha256': hashlib.sha256(raw).hexdigest(), 'raw_bytes': len(raw),
        'raw_meshes': len(gltf.get('meshes', [])), 'raw_primitives': len(primitives),
        'raw_triangles': gltf_tris, 'raw_vertices': gltf_verts,
        'raw_skins': len(gltf.get('skins', [])), 'raw_animations': len(gltf.get('animations', [])),
        'blender_meshes': meshes,
        'textures': [{
            'name': im.name, 'size': list(im.size),
            'color_space': im.colorspace_settings.name,
            'packed': bool(im.packed_file),
        } for im in bpy.data.images if im.name.startswith('tripo_image_d12ce0c7')],
        'scale_note': 'Tripo-normalized 1m height; not character fitting scale.',
    }
    (REPORT / 'raw_inventory.json').write_text(json.dumps(inventory, indent=2), encoding='utf-8')
    result = qa_check.run(objects=[o.name for o in objects], profile='game', eps=.0002, tol=.006)
    (REPORT / 'raw_qa.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('EXO_RAW_AUDIT', json.dumps({
        'raw_triangles': gltf_tris, 'blender_triangles': sum(m['triangles'] for m in meshes.values()),
        'passed': result['pass'], 'errors': result['errors'], 'warnings': result['warnings'],
    }), flush=True)


main()
