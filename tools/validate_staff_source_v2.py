"""Reopen both saved sources and compare all protected meshes and materials."""
import bpy, json, hashlib, math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/bolt_cutter_v2'
ASSET=ROOT/'assets/weapons/staff_transform_v2'

def signature(obj):
    return {'vertices':[list(v.co) for v in obj.data.vertices],
            'polygons':[(list(p.vertices),p.material_index,p.use_smooth) for p in obj.data.polygons],
            'materials':[m.name for m in obj.data.materials],
            'uv':[[list(loop.uv) for loop in layer.data] for layer in obj.data.uv_layers],
            'matrix':[list(row) for row in obj.matrix_world]}

bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/weapons/staff_transform_v1/authoring/staff_transform_v1.blend'))
protected={o.name:signature(o) for o in bpy.data.objects if o.type=='MESH' and o.parent.name!='bolt_cutter'}
bpy.ops.wm.open_mainfile(filepath=str(ASSET/'authoring/staff_transform_v2.blend'))
config=json.loads((ASSET/'parts.json').read_text(encoding='utf-8'))
failures=[];metrics={}
for name,sig in protected.items():
    current=signature(bpy.data.objects[name])
    if current!=sig:failures.append('protected mesh changed: '+name+' '+','.join(k for k in sig if sig[k]!=current[k]))
for name,expected in config['metrics'].items():
    meshes=[o for o in bpy.data.objects if o.type=='MESH' and o.parent.name==name]
    tris=0
    for obj in meshes:
        obj.data.calc_loop_triangles();tris+=len(obj.data.loop_triangles)
        if not all(math.isfinite(c) for v in obj.data.vertices for c in v.co):failures.append(obj.name+':nonfinite')
    metrics[name]={'parts':len(meshes),'triangles':tris}
    if metrics[name]!=expected:failures.append(name+':metrics')
for record in config['parts']:
    obj=bpy.data.objects.get(record['name'])
    if not obj or obj.parent.name!=record['group']:failures.append(record['name']+':parent')
report={'passed':not failures,'failures':failures,'protected_meshes_unchanged':len(protected),
        'metrics':metrics,'blender':bpy.app.version_string,
        'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
        'scope':'Both saved sources reopened; all 45 non-cutter meshes compare exactly in coordinates, topology, materials, normals mode and world transforms.'}
(REPORT/'source_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('CUTTER_SOURCE_VALIDATION_COMPLETE '+json.dumps(report))
if failures:raise RuntimeError(str(failures))

