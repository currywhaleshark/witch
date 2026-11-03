"""Fresh source and GLB review of the three slotted guillotine derivatives."""
import bpy,sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
R=ROOT/'reports/drive_tree_v2';G=ROOT/'game/assets/weapons/drive_tree_v2';S=ROOT/'assets/weapons/drive_tree_v2'
def main():
    models={};result={}
    scenes=[s for s in bpy.data.scenes if s.name.startswith('DriveV2_')]
    for scene in scenes:
        info=json.loads(scene['manifest_json']);models[info['id']]=info
        (G/(info['id']+'.json')).write_text(json.dumps(info,indent=2),encoding='utf-8')
    (S/'models.json').write_text(json.dumps(models,indent=2),encoding='utf-8')
    for scene in scenes:
        bpy.context.window.scene=scene;asset=json.loads(scene['manifest_json'])['id']
        names=[o.name for o in scene.objects if o.type=='MESH']
        source=qa_check.run(objects=names,profile='game',eps=.0002,tol=.006)
        print('V2_QA',asset,'source',source['pass'],source['errors'],flush=True)
        new=bpy.data.scenes.new('QA_V2_'+asset);bpy.context.window.scene=new
        bpy.ops.import_scene.gltf(filepath=str(G/(asset+'.glb')))
        exported=qa_check.run(objects=[o.name for o in new.objects if o.type=='MESH'],profile='game',eps=.0002,tol=.006)
        print('V2_QA',asset,'reimport',exported['pass'],exported['errors'],flush=True)
        result[asset]={'source':source,'reimport':exported}
        (R/(asset+'_qa.json')).write_text(json.dumps(result[asset],indent=2),encoding='utf-8')
    summary={a:{k:{'passed':q['pass'],'errors':q['errors'],'warnings':q['warnings']} for k,q in stages.items()} for a,stages in result.items()}
    (R/'asset_qa.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('V2_QA_DONE',all(q['pass'] for a in result.values() for q in a.values()),flush=True)
main()
