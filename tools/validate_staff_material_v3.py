"""Validate baked glTF maps and preserved rigid geometry, independently of Blender."""
import hashlib, json, struct
from collections import Counter
from pathlib import Path
from io import BytesIO
from PIL import Image, ImageStat

ROOT=Path(__file__).resolve().parents[1];REPORT=ROOT/'reports/staff_material_v3'
class GLB:
    def __init__(self,path):
        self.bytes=path.read_bytes();n=struct.unpack_from('<I',self.bytes,12)[0]
        self.doc=json.loads(self.bytes[20:20+n]);self.bin=self.bytes[28+n:]
    def values(self,index):
        a=self.doc['accessors'][index];v=self.doc['bufferViews'][a['bufferView']]
        fmt='<'+{5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]*{'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        width=struct.calcsize(fmt);stride=v.get('byteStride',width);start=v.get('byteOffset',0)+a.get('byteOffset',0)
        return [struct.unpack_from(fmt,self.bin,start+i*stride) for i in range(a['count'])]
    def shapes(self):
        results={};surfaces=0
        for node in self.doc['nodes']:
            if 'mesh' not in node:continue
            mesh=self.doc['meshes'][node['mesh']];triangles=[]
            for p in mesh['primitives']:
                indices=[v[0] for v in self.values(p['indices'])]
                positions=self.values(p['attributes']['POSITION']);normals=self.values(p['attributes']['NORMAL'])
                vertices=[tuple(round(f,7) for f in (*position,*normal)) for position,normal in zip(positions,normals)]
                triangles.extend(tuple(sorted(vertices[i] for i in indices[k:k+3])) for k in range(0,len(indices),3))
                surfaces+=1
            results[node['name']]={'triangles':Counter(triangles),
                'translation':node.get('translation',[0,0,0]),'rotation':node.get('rotation',[0,0,0,1]),'scale':node.get('scale',[1,1,1])}
        return results,surfaces

old=GLB(ROOT/'assets/weapons/staff_transform_v2/exports/staff_parts.glb')
new=GLB(ROOT/'assets/weapons/staff_material_v3/exports/staff_parts.glb')
a,old_surfaces=old.shapes();b,new_surfaces=new.shapes()
assert len(a)==len(b)==52 and a==b,'geometry, normals or transforms changed'
assert not new.doc.get('animations') and not new.doc.get('skins')
assert len(new.doc['materials'])==2
material=next(m for m in new.doc['materials'] if m['name']=='Staff_PBR_v3');pbr=material['pbrMetallicRoughness']
core=next(m for m in new.doc['materials'] if m['name']=='Staff_Core_v3')
for texture in ('baseColorTexture','metallicRoughnessTexture'):assert texture in pbr
for texture in ('normalTexture','occlusionTexture'):assert texture in material
assert 'emissiveTexture' not in material and 'emissiveTexture' in core
assert material['occlusionTexture']['index']==pbr['metallicRoughnessTexture']['index'],'ORM not shared'
assert len(new.doc['images'])==4
images={}
for im in new.doc['images']:
    view=new.doc['bufferViews'][im['bufferView']];start=view.get('byteOffset',0)
    raw=new.bin[start:start+view['byteLength']]
    image=Image.open(BytesIO(raw)).convert('RGB');stat=ImageStat.Stat(image)
    assert max(stat.stddev)>.5,'blank map '+str(im)
    images[im.get('name',str(im['bufferView']))]={'size':list(image.size),'mean':stat.mean,'stddev':stat.stddev,'bytes':len(raw)}
uv_count=0
for mesh in new.doc['meshes']:
    assert 1<=len(mesh['primitives'])<=2
    for primitive in mesh['primitives']:
        # Godot generates MikkTSpace tangents from these normals/UVs on import;
        # Blender's source n-gons are kept intact instead of changing topology.
        for uv in new.values(primitive['attributes']['TEXCOORD_0']):
            assert all(-.000001<=v<=1.000001 for v in uv),uv
            uv_count+=1
runtime=ROOT/'game/assets/weapons/staff_material_v3/staff_parts.glb'
assert runtime.read_bytes()==new.bytes
old_config=json.loads((ROOT/'assets/weapons/staff_transform_v2/parts.json').read_text(encoding='utf-8'))
config=json.loads((ROOT/'assets/weapons/staff_material_v3/parts.json').read_text(encoding='utf-8'))
for key in ('parts','metrics','cutter','sockets','appearance_profiles','reserved_grip_y','assembly_seconds','dissolve_seconds'):
    assert old_config[key]==config[key],key
report={'passed':True,'meshes':len(b),'triangles':sum(sum(x['triangles'].values()) for x in b.values()),
        'geometry_normals_transforms_preserved':True,'mechanism_metadata_preserved':True,
        'surface_count_before':old_surfaces,'surface_count_after':new_surfaces,
        'uv_vertex_count':uv_count,'images':images,'materials':len(new.doc['materials']),
        'runtime_identical':True,'asset_sha256':hashlib.sha256(new.bytes).hexdigest()}
(REPORT/'glb_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
