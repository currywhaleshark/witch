"""Reopen the saved editable scenes and independently reimport all six GLBs."""
import bpy
import bmesh
import json
import struct
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/props/ground_loot_v3'
GAME=ROOT/'game/assets/props/ground_loot_v3'
OUT=ROOT/'reports/item_art_v2'
records=json.loads((SOURCE/'models.json').read_text(encoding='utf-8'))['assets']
profiles=json.loads((GAME/'models.json').read_text(encoding='utf-8'))
old=json.loads((ROOT/'game/assets/props/ground_loot_v2/models.json').read_text(encoding='utf-8'))
checks=[]
failures=[]


def check(ok,label):
    checks.append(label)
    if not ok: failures.append(label)


items=json.loads((ROOT/'game/data/items.json').read_text(encoding='utf-8'))
trial=json.loads((ROOT/'game/data/trial.json').read_text(encoding='utf-8'))
expected={x['id'] for x in items['bases']+items['uniques']}|set(trial['potions'])|set(items['pieces'])|{'currency'}
check(set(profiles)==expected,'Every current definition has an explicit model')
check(all(profiles[k]==v for k,v in old.items()),'All 39 previous profiles preserved exactly')
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'ground_loot_v3.blend'))
for row in records:
    scene=bpy.data.scenes.get(row['id'])
    check(scene is not None,row['id']+' editable scene saved')
    objects=[o for o in scene.objects if o.type=='MESH']
    check(len(objects)==row['source_parts'],row['id']+' separate source parts retained')
    check(sum(len(p.vertices)-2 for o in objects for p in o.data.polygons)==row['triangles'],row['id']+' source triangle count retained')
    check(all(o.data.uv_layers for o in objects),row['id']+' source UVs retained')

for row in records:
    id=row['id']
    path=GAME/(id+'.glb')
    raw=path.read_bytes()
    check(hashlib.sha256(raw).hexdigest()==row['sha256'],id+' export hash matches')
    gltf=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
    check(len(gltf['meshes'])==1 and len(gltf['materials'])<=3,id+' one mesh and at most three surfaces')
    check(not gltf.get('animations') and not gltf.get('skins') and not gltf.get('images'),id+' static mesh with no texture dependency')
    check(all('COLOR_0' in p['attributes'] and 'TEXCOORD_0' in p['attributes'] for p in gltf['meshes'][0]['primitives']),id+' vertex colors and UVs exported')
    check(sum(gltf['accessors'][p['indices']]['count']//3 for p in gltf['meshes'][0]['primitives'])==row['triangles'],id+' exported triangle count')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    check((lo+hi).length<1e-5,id+' centered tumble pivot')
    check(abs(lo.z+row['rest_height']-.012)<1e-5,id+' true vertex 12mm floor clearance')
    check(max(Vector((p.x,p.y)).length for p in points)<.35,id+' fits existing 0.7m spacing')
    check(max(abs(a-b) for a,b in zip([hi.x-lo.x,hi.z-lo.z,hi.y-lo.y],row['dimensions_godot']))<1e-5,id+' reimport dimensions')
    degenerate=0
    for o in objects:
        bm=bmesh.new();bm.from_mesh(o.data)
        degenerate+=sum(f.calc_area()<1e-10 for f in bm.faces)
        bm.free()
    check(degenerate==0,id+' no degenerate exported triangles')

report={'blender':bpy.app.version_string,'checks':checks,'failures':failures,
    'source_sha256':hashlib.sha256((SOURCE/'ground_loot_v3.blend').read_bytes()).hexdigest(),
    'scope':'Saved parts, reimport topology, colors, dimensions, pivots and floor support. Joining interfaces are intentional; no full inter-part collision certificate.'}
(OUT/'asset_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('GROUND_LOOT_V3_VALIDATION',len(checks),'checks',len(failures),'failures',failures)
if failures: raise RuntimeError(str(failures))
