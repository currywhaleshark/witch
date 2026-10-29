"""Read-only reopen validation; run Blender background with the saved staff blend."""
import bpy
import json
import math
import hashlib
from pathlib import Path

root=Path(__file__).resolve().parents[1]
asset=root/'assets/weapons/staff_transform_v1'
data=json.loads((asset/'parts.json').read_text(encoding='utf-8'))
failures=[]
metrics={}
for name,expected in data['metrics'].items():
    parent=bpy.data.objects.get(name)
    meshes=[obj for obj in parent.children if obj.type=='MESH'] if parent else []
    tris=0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tris+=len(obj.data.loop_triangles)
        if not all(math.isfinite(v) for vertex in obj.data.vertices for v in vertex.co):failures.append(name+':nonfinite')
        if not obj.data.materials:failures.append(name+':material_missing')
    metrics[name]={'parts':len(meshes),'triangles':tris}
    if metrics[name]!=expected:failures.append(name+':metrics')
for rec in data['parts']:
    obj=bpy.data.objects.get(rec['name'])
    if not obj or obj.parent.name!=rec['group']:failures.append(rec['name']+':missing_or_wrong_parent')
if any(obj.type=='ARMATURE' for obj in bpy.data.objects):failures.append('unexpected_armature')
report={'passed':not failures,'failures':failures,'metrics':metrics,'blender':bpy.app.version_string,
    'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
    'scope':'Saved blend reopened, expected groups/rigid meshes/material assignments/finite vertices; no save performed.'}
(root/'reports/staff_transform_v1/source_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('STAFF_SOURCE_VALIDATION_COMPLETE '+json.dumps(report))
if failures:raise RuntimeError(str(failures))
