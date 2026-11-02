"""Skill multi-angle review of the saved authoring source, material and wire."""
import bpy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/props/ground_loot_v2'
OUT=ROOT/'reports/ground_loot_v2/authoring'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import review_shots
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'ground_loot_v2.blend'))
records=[]
for entry in json.loads((SOURCE/'models.json').read_text(encoding='utf-8'))['assets']:
    id=entry['id']
    bpy.context.window.scene=bpy.data.scenes[id]
    scene=bpy.context.scene
    scene.view_settings.view_transform='Standard'
    objects=[o.name for o in scene.objects if o.type=='MESH']
    row={'id':id}
    for mode in ('material','wire'):
        row[mode]=review_shots.run(objects=objects,out=str(OUT/(id+'_'+mode+'.png')),views=['top','three_quarter'],mode=mode,res=300)
    records.append(row)
    print('REVIEWED',id,flush=True)
(OUT/'manifest.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
