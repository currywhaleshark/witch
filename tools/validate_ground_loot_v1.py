"""Reopen the editable source, then reimport each exported GLB and check actual vertices."""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/props/ground_loot_v1'
GAME = ROOT / 'game/assets/props/ground_loot_v1'
model_data = json.loads((SOURCE/'models.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'ground_loot_v1.blend'))
checks = []
def check(ok, label):
    checks.append({'label':label,'passed':bool(ok)})
    assert ok, label
for entry in model_data['assets']:
    scene = bpy.data.scenes.get(entry['id'])
    check(scene is not None, entry['id']+' saved editable scene')
    objs = [o for o in scene.objects if o.type == 'MESH']
    triangles = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objs)
    check(triangles == entry['triangles'], entry['id']+' saved source triangle count')
for entry in model_data['assets']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = GAME/(entry['id']+'.glb')
    check(hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'], entry['id']+' export hash')
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    points = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    dims = [high[0]-low[0],high[2]-low[2],high[1]-low[1]]
    check(max(abs(a-b) for a,b in zip(dims,entry['dimensions_godot'])) < 1e-5, entry['id']+' reimport dimensions')
    check(abs(low[2]+entry['rest_height']-.012) < 1e-5, entry['id']+' true floor support')
    check(all(o.type != 'ARMATURE' for o in bpy.context.scene.objects), entry['id']+' static unrigged asset')
report = {'blender':bpy.app.version_string,'checks':checks,'failures':[],'source_sha256':hashlib.sha256((SOURCE/'ground_loot_v1.blend').read_bytes()).hexdigest()}
(ROOT/'reports/ground_loot_v1/asset_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('GROUND_LOOT_ASSET_CHECKS',len(checks))
