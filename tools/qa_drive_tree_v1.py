"""Saved-source and fresh GLB checks; equipment components are checked per attachment."""
import bpy,sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
R=ROOT/'reports/drive_tree_v1';G=ROOT/'game/assets/weapons/drive_tree_v1';S=ROOT/'assets/weapons/drive_tree_v1'

def main():
    result={};models={}
    selection=next((a.split('=',1)[1].split(',') for a in sys.argv if a.startswith('--assets=')),None)
    for scene in list(bpy.data.scenes):
        if not scene.name.startswith('DriveV1_') or 'manifest_json' not in scene:continue
        bpy.context.window.scene=scene
        info=json.loads(scene['manifest_json']);asset=info['id'];models[asset]=info
        (G/(asset+'.json')).write_text(json.dumps(info,indent=2),encoding='utf-8')
        if selection and asset not in selection:
            result[asset]=json.loads((R/(asset+'_qa.json')).read_text(encoding='utf-8'))
            continue
        obs=[o for o in scene.objects if o.type=='MESH'];groups={}
        for o in obs:groups.setdefault(o.get('attach_bone','asset'),[]).append(o.name)
        stages={'source':{}}
        for group,names in groups.items():
            q=qa_check.run(objects=names,profile='game',eps=.0002,tol=.006)
            stages['source'][group]=q
            print(asset,group,'pass',q['pass'],'errors',q['errors'],flush=True)
        path=G/(asset+'.glb')
        if path.exists():
            new=bpy.data.scenes.new('QA_Drive_'+asset);bpy.context.window.scene=new
            bpy.ops.import_scene.gltf(filepath=str(path));stages['reimport']={}
            for group,names in groups.items():
                targets=[o.name for o in new.objects if o.type=='MESH' and any(o.name==n or o.name.startswith(n+'.') for n in names)]
                q=qa_check.run(objects=targets,profile='game',eps=.0002,tol=.006)
                stages['reimport'][group]=q
                print(asset,'reimport',group,'pass',q['pass'],'errors',q['errors'],flush=True)
        result[asset]=stages
        (R/(asset+'_qa.json')).write_text(json.dumps(stages,indent=2),encoding='utf-8')
    (S/'models.json').write_text(json.dumps(models,indent=2),encoding='utf-8')
    summary={a:{s:{k:{'passed':q['pass'],'errors':q['errors'],'warnings':q['warnings']} for k,q in groups.items()} for s,groups in stages.items()} for a,stages in result.items()}
    (R/'asset_qa.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('DRIVE_QA_DONE',all(q['pass'] for a in result.values() for s in a.values() for q in s.values()),flush=True)
main()
