"""Review the live-authored saved source and freshly reimported runtime GLBs.

Run in a separate background Blender; never mutate the live user's scene.
"""
import bpy
import sys
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/firearm_tree_v2'
GAME=ROOT/'game/assets/weapons/firearm_tree_v2'
SOURCE=ROOT/'assets/weapons/firearm_tree_v2'
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check

def run():
    assert bpy.app.background
    REPORT.mkdir(parents=True,exist_ok=True)
    results={}; inventory={}
    scenes=[s for s in bpy.data.scenes if s.name.startswith('FirearmV2_') and 'asset_id' in s]
    for scene in scenes:
        bpy.context.window.scene=scene
        id=scene['runtime_id']; info=json.loads(scene['manifest_json']); inventory[id]=info
        objects=[o.name for o in scene.objects if o.type=='MESH']
        qa=qa_check.run(objects=objects,profile='game',eps=.0002,tol=.006)
        results[id]={'source':qa}
        (REPORT/(id+'_source_qa.json')).write_text(json.dumps(qa,indent=2),encoding='utf-8')
        (GAME/(id+'.json')).write_text(json.dumps(info,indent=2),encoding='utf-8')
        print('SOURCE_QA',id,qa['pass'],'errors',len(qa['errors']),'warnings',len(qa['warnings']),flush=True)
    (SOURCE/'models.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    for id in inventory:
        scene=bpy.data.scenes.new('Reimport_'+id); bpy.context.window.scene=scene
        bpy.ops.import_scene.gltf(filepath=str(GAME/(id+'.glb')))
        objects=[o.name for o in scene.objects if o.type=='MESH']
        qa=qa_check.run(objects=objects,profile='game',eps=.0002,tol=.006)
        results[id]['reimport']=qa
        (REPORT/(id+'_reimport_qa.json')).write_text(json.dumps(qa,indent=2),encoding='utf-8')
        print('REIMPORT_QA',id,qa['pass'],'errors',len(qa['errors']),'warnings',len(qa['warnings']),flush=True)
    summary={id:{stage:{'passed':qa['pass'],'errors':qa['errors'],'warnings':qa['warnings']} for stage,qa in stages.items()} for id,stages in results.items()}
    (REPORT/'asset_qa.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('FIREARM_QA_DONE',all(q['pass'] for stages in results.values() for q in stages.values()),flush=True)

run()
