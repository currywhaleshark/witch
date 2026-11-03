"""Replace only GLB material/image declarations; keep all accepted mesh and mechanism bytes."""
from pathlib import Path
import copy
import json
import hashlib
import shutil
from package_firearm_material_assets_v4 import read_glb, write_glb

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'assets/weapons/drive_material_v3'
G = ROOT / 'game/assets/weapons/drive_material_v3'
R = ROOT / 'reports/drive_material_v3'
IDS = ['guillotine', 'guillotine_saw', 'guillotine_lock', 'restraint_winch',
       'hydraulic_press', 'compound_executor', 'shock_frame', 'broad_cutter']
LABELS = ['낙하 단두대', '단두대 · 회전 톱날', '단두대 · 고정', '구속 윈치',
          '유압 압착기', '복합 집행기', '충격 흡수 프레임', '광역 볼트커터']


def main():
    for key in ['color', 'normal', 'orm', 'emission']:
        name = 'drive_v3_' + key + '.png'
        shutil.copyfile(S / 'textures' / name, G / 'textures' / name)
    metrics, models, catalog = {}, {}, {}
    for asset, label in zip(IDS, LABELS):
        old_folder = 'drive_tree_v2' if asset.startswith('guillotine') else 'drive_tree_v1'
        old_path = ROOT / 'game/assets/weapons' / old_folder / (asset + '.glb')
        old, binary = read_glb(old_path)
        doc = copy.deepcopy(old)
        for material in doc['materials']:
            material['name'] = material['name'].replace('DriveV1', 'DriveV3')
        for image in doc['images']:
            key = image['name'].split('_')[-1]
            image['name'] = 'drive_v3_' + key
            image['uri'] = 'textures/drive_v3_' + key + '.png'
        destination = G / (asset + '.glb')
        write_glb(destination, doc, binary)
        current, current_binary = read_glb(destination)
        assert current_binary == binary
        for key in set(old) - {'materials', 'images'}: assert old[key] == current[key], (asset, key)
        metadata_path = ROOT / 'game/assets/weapons' / old_folder / (asset + '.json')
        original_metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        models[asset] = copy.deepcopy(original_metadata)
        models[asset]['materials'] = ['M_DriveV3_Surface', 'M_DriveV3_Glow']
        models[asset]['texture_set'] = 'drive_material_v3 shared trim'
        for key in set(original_metadata) - {'materials', 'texture_set'}:
            assert models[asset][key] == original_metadata[key]
        (G / metadata_path.name).write_text(json.dumps(models[asset], ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        # Portable export embeds exactly these four PNGs, leaving all original accessors intact.
        portable = copy.deepcopy(doc)
        embedded = bytearray(binary)
        for image in portable['images']:
            while len(embedded) % 4: embedded.append(0)
            pixels = (G / image.pop('uri')).read_bytes()
            image['bufferView'] = len(portable['bufferViews'])
            image['mimeType'] = 'image/png'
            portable['bufferViews'].append({'buffer': 0, 'byteOffset': len(embedded), 'byteLength': len(pixels)})
            embedded.extend(pixels)
        portable['buffers'][0]['byteLength'] = len(embedded)
        write_glb(S / 'exports' / (asset + '.glb'), portable, bytes(embedded))
        primitives = [p for m in doc['meshes'] for p in m['primitives']]
        count = sum(doc['accessors'][p['indices']]['count'] // 3 for p in primitives)
        assert count == models[asset]['triangles']
        metrics[asset] = {'source': old_path.relative_to(ROOT).as_posix(), 'parts': len(doc['meshes']),
                         'triangles': count, 'materials': len(doc['materials']), 'surfaces': len(primitives),
                         'geometry_binary_unchanged': True, 'nodes_accessors_uv_normals_tangents_unchanged': True,
                         'mechanism_metadata_unchanged': True,
                         'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}
        catalog[asset] = {'name': label, 'model': 'res://assets/weapons/drive_material_v3/' + asset + '.glb',
                          'metadata': 'res://assets/weapons/drive_material_v3/' + asset + '.json',
                          'review_helper': 'res://tests/helpers/drive_material_v3_demo.gd'}
    (S / 'models.json').write_text(json.dumps(models, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (S / 'catalog.json').write_text(json.dumps({'status': 'prepared assets / reviewed material derivative', 'assets': catalog,
        'exoskeleton': 'Unchanged selected v4 under assets/equipment/exoskeleton_v4; outside this material task.'}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (R / 'export_validation.json').write_text(json.dumps({'passed': True, 'models': metrics,
        'parts': sum(m['parts'] for m in metrics.values()), 'triangles': sum(m['triangles'] for m in metrics.values())}, indent=2) + '\n', encoding='utf-8')
    print('DRIVE_MATERIAL_PACKAGED', len(metrics), sum(m['parts'] for m in metrics.values()), sum(m['triangles'] for m in metrics.values()))


if __name__ == '__main__': main()
