"""Verify the final saved source after the last material adjustment and review-scene setup."""
import bpy
import json
import hashlib
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'assets/weapons/drive_material_v3'
R = ROOT / 'reports/drive_material_v3'


def digest(values): return hashlib.sha256(np.asarray(values).tobytes()).hexdigest()


def main():
    expected = json.loads((R / 'source_preservation.json').read_text(encoding='utf-8'))['fingerprints']
    verified = 0
    matrices = 0
    for scene in bpy.data.scenes:
        if 'manifest_json' not in scene: continue
        bpy.context.window.scene = scene
        bpy.context.view_layer.update()
        for ob in scene.objects:
            if ob.type != 'MESH': continue
            original = expected[ob['source_name']]
            me = ob.data
            co = np.empty(len(me.vertices) * 3, dtype=np.float32)
            me.vertices.foreach_get('co', co)
            loops = np.empty(len(me.loops), dtype=np.int32)
            me.loops.foreach_get('vertex_index', loops)
            uv = np.empty(len(me.loops) * 2, dtype=np.float32)
            me.uv_layers.active.data.foreach_get('uv', uv)
            normals = np.empty(len(me.corner_normals) * 3, dtype=np.float32)
            me.corner_normals.foreach_get('vector', normals)
            for key, data in [('vertices', co), ('loops', loops), ('uv', uv), ('normals', normals)]:
                assert digest(data) == original[key], (ob.name, key)
            assert [len(f.vertices) for f in me.polygons] == original['polygons']
            assert [list(row) for row in ob.matrix_basis] == original['matrix_basis']
            assert [list(row) for row in ob.matrix_parent_inverse] == original['matrix_parent_inverse']
            assert len(me.materials) == 1
            expected_mat = 'M_DriveV3_Glow' if ob.get('surface_key') == 'core' else 'M_DriveV3_Surface'
            assert me.materials[0].name == expected_mat
            verified += 1
            matrices += 2
    assert verified == 224
    material_checks = {}
    for name in ['M_DriveV3_Surface', 'M_DriveV3_Glow']:
        mat = bpy.data.materials[name]
        p = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        assert all(p.inputs[s].is_linked for s in ['Base Color', 'Metallic', 'Roughness', 'Normal'])
        images = {}
        for n in mat.node_tree.nodes:
            if n.type != 'TEX_IMAGE': continue
            image = n.image
            key = image.name.split('drive_v3_', 1)[1].split('.')[0]
            expected_space = 'sRGB' if key in ['color', 'emission'] else 'Non-Color'
            assert image.colorspace_settings.name == expected_space
            assert image.packed_file
            pixels = np.empty(len(image.pixels), dtype=np.float32)
            image.pixels.foreach_get(pixels)
            assert np.isfinite(pixels).all()
            assert np.max(pixels) > .1
            images[key] = {'size': list(image.size), 'space': expected_space, 'packed': True}
        assert set(images) == ({'color', 'normal', 'orm', 'emission'} if name.endswith('Glow') else {'color', 'normal', 'orm'})
        material_checks[name] = images
    result = {'passed': True, 'preserved_meshes': verified, 'preserved_object_matrices': matrices,
        'source_triangles': 45516, 'runtime_materials': material_checks,
        'editable_source_materials': sum(m.name.startswith('M_DriveV3_Source_') for m in bpy.data.materials),
        'note': 'Final reopened geometry/UV/normals/transforms match the complete source/reimport QA inputs. Only wear width and roughness changed after the full QA started; final map wiring, color spaces and packed data are rechecked here.',
        'blend_sha256': hashlib.sha256((S / 'drive_material_v3.blend').read_bytes()).hexdigest()}
    (R / 'saved_source_validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('SAVED_DRIVE_MATERIAL_VALIDATED', verified, flush=True)


main()
