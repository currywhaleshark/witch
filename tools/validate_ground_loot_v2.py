"""Independently reopen source and round-trip every new static GLB."""
import bpy, bmesh, json, hashlib, struct, sys
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/props/ground_loot_v2'
REPORT=ROOT/'reports/ground_loot_v2'
DATA=json.loads((SOURCE/'models.json').read_text(encoding='utf-8'))
PROFILES=json.loads((ROOT/'game/assets/props/ground_loot_v2/models.json').read_text(encoding='utf-8'))
checks=[]
failures=[]
def check(ok,label):
    checks.append(label)
    if not ok: failures.append(label)

items=json.loads((ROOT/'game/data/items.json').read_text(encoding='utf-8'))
trial=json.loads((ROOT/'game/data/trial.json').read_text(encoding='utf-8'))
expected={x['id'] for x in items['bases']}|{x['id'] for x in items['uniques']}|set(trial['potions'])|set(items['pieces'])|{'currency'}
check(set(PROFILES)==expected,'Profiles exactly cover existing 39 definitions, including unique overrides and resources')
for row in DATA['preserved_v1']:
    path=ROOT/'game/assets/props/ground_loot_v1'/(row['id']+'.glb')
    check(hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],row['id']+' accepted v1 bytes preserved')

assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'ground_loot_v2.blend'))
source_metrics={}
for row in DATA['assets']:
    scene=bpy.data.scenes.get(row['id'])
    check(scene is not None,row['id']+' saved editable scene')
    objs=[o for o in scene.objects if o.type=='MESH']
    source_metrics[row['id']]={'parts':len(objs),'triangles':sum(len(p.vertices)-2 for o in objs for p in o.data.polygons)}
    check(source_metrics[row['id']]['parts']==row['source_parts'],row['id']+' source parts retained')
    check(source_metrics[row['id']]['triangles']==row['triangles'],row['id']+' saved topology count')

for row in DATA['assets']:
    id=row['id']
    path=ROOT/'game/assets/props/ground_loot_v2'/(id+'.glb')
    raw=path.read_bytes()
    check(hashlib.sha256(raw).hexdigest()==row['sha256'],id+' exported file hash')
    length=struct.unpack_from('<I',raw,12)[0]
    gltf=json.loads(raw[20:20+length])
    check(len(gltf['meshes'])==1 and len(gltf.get('scenes',[]))==1,id+' only its own runtime mesh exported')
    check(1<=len(gltf['materials'])<=3,id+' at most three PBR materials')
    check(not gltf.get('skins') and not gltf.get('animations'),id+' static no rig or animation')
    check(all('COLOR_0' in p['attributes'] and 'TEXCOORD_0' in p['attributes'] for p in gltf['meshes'][0]['primitives']),id+' vertex colors and UVs survive export')
    check(sum(gltf['accessors'][p['indices']]['count']//3 for p in gltf['meshes'][0]['primitives'])==row['triangles'],id+' GLB triangle count matches source')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    pts=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
    lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    dims=[hi.x-lo.x,hi.z-lo.z,hi.y-lo.y]
    check(max(abs(a-b) for a,b in zip(dims,row['dimensions_godot']))<1e-5,id+' reimport dimensions match')
    check(abs(lo.z+row['rest_height']-.012)<1e-5,id+' actual vertices support 12mm clearance')
    check(max(Vector((p.x,p.y)).length for p in pts)<.35,id+' fits shared 0.7m spacing')
    check((lo+hi).length<1e-5,id+' centered tumble pivot')
    bad=0
    for o in objs:
        bm=bmesh.new();bm.from_mesh(o.data)
        bad+=sum(f.calc_area()<1e-10 for f in bm.faces)
        bm.free()
    check(bad==0,id+' no zero-area exported faces')

qa=json.loads((REPORT/'source_qa.json').read_text(encoding='utf-8'))
check(all(v['pass'] for groups in qa.values() for v in groups.values()),'All source subassemblies pass unmodified skill game profile')
report={'blender':bpy.app.version_string,'checks':checks,'failures':failures,'saved_source_metrics':source_metrics,
    'source_sha256':hashlib.sha256((SOURCE/'ground_loot_v2.blend').read_bytes()).hexdigest()}
(REPORT/'asset_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('GROUND_LOOT_V2_VALIDATION',len(checks),'checks;',len(failures),'failures',failures)
if failures: raise RuntimeError('Round-trip validation failed')
