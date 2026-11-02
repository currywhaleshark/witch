"""Run isolated loot-art reports without replacing the earlier regression artifacts."""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/ground_loot_v2'

def inputs():
    files=list((ROOT/'game/scripts').glob('*.gd'))+list((ROOT/'game/data').glob('*.json'))
    files += [ROOT/'game/main.tscn', ROOT/'game/project.godot', ROOT/'tools/run_ground_loot_v2.py',
              ROOT/'tools/build_ground_loot_v2.py', ROOT/'assets/props/ground_loot_v2/models.json']
    for folder in ['ground_loot_v1','ground_loot_v2']:
        files+=list((ROOT/'game/assets/props'/folder).glob('*'))
    files+=[ROOT/'game/tests'/name for name in ['ground_loot_art_v2.gd','ground_loot_art.gd','ground_loot.gd','loot_resources.gd','items.gd']]
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(files)) if p.is_file()}

def run(engine, key, args):
    folder=OUT/key
    folder.mkdir(parents=True,exist_ok=True)
    before=inputs()
    (folder/'inputs_before.json').write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    cmd=[str(engine),'--path',str(ROOT/'game'),'--audio-driver','Dummy','--log-file',str(folder/'engine.log'),*args]
    start=time.time()
    with (folder/'stdout.log').open('w',encoding='utf-8') as out,(folder/'stderr.log').open('w',encoding='utf-8') as err:
        result=subprocess.run(cmd,cwd=ROOT,stdout=out,stderr=err)
    after=inputs()
    (folder/'inputs_after.json').write_text(json.dumps(after,indent=2)+'\n',encoding='utf-8')
    record={'command':cmd,'exit_code':result.returncode,'seconds':time.time()-start,
            'changed_inputs':[k for k in before.keys()|after.keys() if before.get(k)!=after.get(k)]}
    (folder/'execution.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(key,'exit',result.returncode,'changed inputs',len(record['changed_inputs']),flush=True)
    if result.returncode:raise RuntimeError(key+' failed; inspect '+str(folder))
    return record

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--phase',choices=['import','runtime','regressions'],required=True)
    parser.add_argument('--godot',type=Path)
    args=parser.parse_args()
    engine=args.godot or next((Path.home()/'Downloads').glob('Godot_v4.6.2-stable_win64.exe/*console.exe'))
    if args.phase=='import':
        run(engine,'import',['--headless','--editor','--import','--quit'])
    elif args.phase=='runtime':
        run(engine,'runtime',['--resolution','1280x800','--script','res://tests/ground_loot_art_v2.gd','--','--capture'])
    else:
        source_dir=OUT/'regression_scripts'
        source_dir.mkdir(parents=True,exist_ok=True)
        for name in ['ground_loot','loot_resources','items']:
            original=ROOT/'game/tests'/(name+'.gd')
            text=original.read_text(encoding='utf-8-sig')
            if name=='items':
                text=text.replace('../reports/godot_items_report.json','../reports/ground_loot_v2/regressions/items/result.json')
            else:
                text=text.replace('res://../reports/loot_selection','res://../reports/ground_loot_v2/regressions/'+name)
            script=source_dir/(name+'.gd')
            script.write_text(text,encoding='utf-8')
            run(engine,'regressions/'+name,['--headless','--script',str(script)])

if __name__=='__main__':main()
