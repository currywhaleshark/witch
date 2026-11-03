"""Check saved source, unchanged v2 geometry, and (when present) reimported GLBs."""
import bpy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/firearm_material_v3'
SOURCE=ROOT/'assets/weapons/firearm_material_v3'
GAME=ROOT/'game/assets/weapons/firearm_material_v3'
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check

def geometry(o):
    me=o.data
    return {'vertices':[tuple(v.co) for v in me.vertices],
            'polygons':[tuple(p.vertices) for p in me.polygons],
            'smooth':[p.use_smooth for p in me.polygons],
            'normals':[tuple(n.vector) for n in me.corner_normals],
            'matrix':[tuple(row) for row in o.matrix_world]}

def main():
    assert bpy.app.background
    results={};preserved={};inventory={}
    for asset_id in ['matchlock','rifle','shotgun']:
        old=bpy.data.scenes['FirearmV2_'+asset_id]
        bpy.context.window.scene=old;bpy.context.view_layer.update()
        originals={o.name:geometry(o) if o.type=='MESH' else {'matrix':[tuple(row) for row in o.matrix_world]} for o in old.objects}
        scene=bpy.data.scenes['FirearmMaterialV3_'+asset_id];bpy.context.window.scene=scene
        bpy.context.view_layer.update()
        obs=[o for o in scene.objects if o.type=='MESH']
        for ob in scene.objects:
            original=old.objects[ob.name.replace('v3_','v2_',1)]
            assert [tuple(row) for row in ob.matrix_world]==originals[original.name]['matrix'],ob.name
            if ob.type=='MESH':
                assert geometry(ob)==originals[original.name],ob.name
                for key in ['part_role','motion_group','assembly_delay']:assert ob[key]==original[key]
            preserved[ob.name]=True
        qa=qa_check.run(objects=[o.name for o in obs],profile='game',eps=.0002,tol=.006)
        results[asset_id]={'source':qa}
        print('SOURCE_QA',asset_id,qa['pass'],'errors',len(qa['errors']),'warnings',len(qa['warnings']),flush=True)
        (REPORT/(asset_id+'_source_qa.json')).write_text(json.dumps(qa,indent=2),encoding='utf-8')
        info=json.loads(scene['manifest_json']);inventory[asset_id]=info
        (GAME/(asset_id+'.json')).write_text(json.dumps(info,indent=2),encoding='utf-8')
    (SOURCE/'models.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    (REPORT/'geometry_preservation.json').write_text(json.dumps({'passed':True,'objects':preserved,
        'scope':'Exact mesh positions, polygon winding/order, smooth flags, corner normals, object frames, part roles/groups/delays; sockets retain object frames.'},indent=2),encoding='utf-8')
    for asset_id in inventory:
        path=GAME/(asset_id+'.glb')
        if not path.exists():continue
        scene=bpy.data.scenes.new('QA_Reimport_'+asset_id);bpy.context.window.scene=scene
        bpy.ops.import_scene.gltf(filepath=str(path))
        qa=qa_check.run(objects=[o.name for o in scene.objects if o.type=='MESH'],profile='game',eps=.0002,tol=.006)
        results[asset_id]['reimport']=qa
        print('REIMPORT_QA',asset_id,qa['pass'],'errors',len(qa['errors']),'warnings',len(qa['warnings']),flush=True)
        (REPORT/(asset_id+'_reimport_qa.json')).write_text(json.dumps(qa,indent=2),encoding='utf-8')
    summary={asset_id:{stage:{'passed':q['pass'],'errors':q['errors'],'warnings':q['warnings']} for stage,q in stages.items()} for asset_id,stages in results.items()}
    (REPORT/'asset_qa.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    assert all(q['pass'] for stages in results.values() for q in stages.values())
    print('FIREARM_MATERIAL_QA_DONE',len(preserved),'geometry/socket objects preserved',flush=True)
main()
