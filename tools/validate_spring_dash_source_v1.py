"""Reopen the saved authoring file and independently inspect its exported GLB."""
import bpy,json,struct,hashlib,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
A=ROOT/'assets/props/spring_dash_v1';R=ROOT/'reports/spring_dash_v1'
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(A/'authoring/spring_plate.blend'))
data=json.loads((A/'parts.json').read_text())
meshes={o.name:o for o in bpy.data.objects if o.type=='MESH'}
assert set(meshes)=={p['name'] for p in data['parts']} and len(meshes)==29
triangles=0
for p in data['parts']:
    o=meshes[p['name']];o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
    assert o['spring_role']==p['role']
    assert all(math.isfinite(float(x)) for v in o.data.vertices for x in v.co)
    actual=(o.location.x,o.location.z,-o.location.y)
    assert max(abs(a-b) for a,b in zip(actual,p['pivot']))<1e-6
assert triangles==data['triangles']==5964
binary=(A/'exports/spring_plate.glb').read_bytes()
magic,version,total=struct.unpack_from('<4sII',binary,0)
assert magic==b'glTF' and version==2 and total==len(binary)
n,kind=struct.unpack_from('<I4s',binary,12);assert kind==b'JSON'
gltf=json.loads(binary[20:20+n])
assert len(gltf['meshes'])==29 and len(gltf['materials'])==6
assert not gltf.get('skins') and not gltf.get('animations')
assert not gltf.get('images')
export_triangles=sum(gltf['accessors'][p['indices']]['count']//3 for m in gltf['meshes'] for p in m['primitives'])
assert export_triangles==triangles
assert binary==(ROOT/'game/assets/props/spring_dash_v1/spring_plate.glb').read_bytes()
report={'passed':True,'saved_meshes':len(meshes),'materials':6,'source_and_glb_triangles':triangles,'no_rig_or_animation':True,'runtime_copy_identical':True,'blend_sha256':hashlib.sha256((A/'authoring/spring_plate.blend').read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(binary).hexdigest(),'runtime_coils':'Runtime uses a new helix pitch with circular wire section; end caps add 8 triangles across the two coils.'}
(R/'source_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('SPRING_SOURCE_VALIDATION_COMPLETE',triangles)
