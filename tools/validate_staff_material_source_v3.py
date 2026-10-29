"""Reopen saved source and verify geometry, atlas and editable material sources."""
import bpy,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];REPORT=ROOT/'reports/staff_material_v3'
def sig(o):
    return {'vertices':[list(v.co) for v in o.data.vertices],
        'faces':[list(p.vertices) for p in o.data.polygons],
        'smooth':[p.use_smooth for p in o.data.polygons],
        'transform':[list(r) for r in o.matrix_world],'parent':o.parent.name}
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/weapons/staff_transform_v2/authoring/staff_transform_v2.blend'))
old={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH'}
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/weapons/staff_material_v3/authoring/staff_material_v3.blend'))
new={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH'}
assert len(old)==len(new)==52 and old==new
for obj in bpy.context.scene.objects:
    if obj.type=='MESH':
        assert len(obj.data.uv_layers)==1 and obj.data.uv_layers[0].name=='StaffAtlas'
        assert 1<=len(obj.data.materials)<=2
        assert all(m.name in ('Staff_PBR_v3','Staff_Core_v3') for m in obj.data.materials)
packed=[i for i in bpy.data.images if i.name.startswith('Staff_') and i.packed_file]
assert len(packed)==4
procedural=[m for m in bpy.data.materials if m.use_fake_user and m.name!='Staff_PBR_v3']
assert len(procedural)==7
report={'passed':True,'saved_geometry_preserved':52,'packed_images':{i.name:list(i.size) for i in packed},
    'editable_procedural_materials':[m.name for m in procedural],
    'blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()}
(REPORT/'source_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('STAFF_MATERIAL_SOURCE_COMPLETE '+json.dumps(report))
