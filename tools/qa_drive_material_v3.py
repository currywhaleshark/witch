"""Saved source and new portable-GLB roundtrip QA for the eight material derivatives."""
import bpy
import sys
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / '.agents/skills/blender-asset-qa/scripts'))
import qa_check
R = ROOT / 'reports/drive_material_v3'
S = ROOT / 'assets/weapons/drive_material_v3'


def main():
    result = {}
    scenes = [s for s in bpy.data.scenes if s.name.startswith('DriveMaterialV3_') and 'manifest_json' in s]
    for scene in scenes:
        bpy.context.window.scene = scene
        asset = json.loads(scene['manifest_json'])['id']
        groups = {}
        for ob in scene.objects:
            if ob.type == 'MESH': groups.setdefault(ob.get('attach_bone') or 'asset', []).append(ob)
        stages = {'source': {}, 'reimport': {}}
        for group, objects in groups.items():
            q = qa_check.run(objects=[o.name for o in objects], profile='game', eps=.0002, tol=.006)
            stages['source'][group] = q
            print('SOURCE_QA', asset, group, q['pass'], q['errors'], flush=True)
        new = bpy.data.scenes.new('QA_DM3_' + asset)
        bpy.context.window.scene = new
        bpy.ops.import_scene.gltf(filepath=str(S / 'exports' / (asset + '.glb')))
        metadata = json.loads(scene['manifest_json'])
        exported = {o.name: o for o in new.objects if o.type == 'MESH'}
        for group, objects in groups.items():
            names = [o['source_name'] for o in objects]
            targets = [o.name for n, o in exported.items() if n in names]
            assert len(targets) == len(names), (asset, group, targets, names)
            q = qa_check.run(objects=targets, profile='game', eps=.0002, tol=.006)
            stages['reimport'][group] = q
            print('REIMPORT_QA', asset, group, q['pass'], q['errors'], flush=True)
        result[asset] = stages
        (R / (asset + '_qa.json')).write_text(json.dumps(stages, indent=2), encoding='utf-8')
    summary = {a: {stage: {group: {'passed': q['pass'], 'errors': q['errors'], 'warnings': q['warnings']}
        for group, q in groups.items()} for stage, groups in stages.items()} for a, stages in result.items()}
    passed = all(q['pass'] for stages in result.values() for groups in stages.values() for q in groups.values())
    (R / 'asset_qa.json').write_text(json.dumps({'passed': passed, 'models': summary}, indent=2), encoding='utf-8')
    assert passed, summary
    print('DRIVE_MATERIAL_QA_COMPLETE', len(result), flush=True)


main()
