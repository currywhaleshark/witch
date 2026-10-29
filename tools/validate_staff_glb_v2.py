"""Check exported binary accessors, preservation, blade edge and source/runtime parity."""
import hashlib, json, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/bolt_cutter_v2'

class GLB:
    def __init__(self,path):
        self.bytes=path.read_bytes();n=struct.unpack_from('<I',self.bytes,12)[0]
        self.doc=json.loads(self.bytes[20:20+n]);self.bin=self.bytes[28+n:]
    def values(self,index):
        a=self.doc['accessors'][index];v=self.doc['bufferViews'][a['bufferView']]
        sizes={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
        types={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}
        fmt='<'+types[a['componentType']]*sizes[a['type']];width=struct.calcsize(fmt)
        start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width)
        return [struct.unpack_from(fmt,self.bin,start+i*stride) for i in range(a['count'])]
    def signatures(self):
        result={}
        for m in self.doc['meshes']:
            result[m['name']]=[{'attributes':{k:self.values(v) for k,v in p['attributes'].items()},
                'indices':self.values(p['indices']), 'material':self.doc['materials'][p['material']]}
                for p in m['primitives']]
        return result

old=GLB(ROOT/'assets/weapons/staff_transform_v1/exports/staff_parts.glb')
new=GLB(ROOT/'assets/weapons/staff_transform_v2/exports/staff_parts.glb')
old_s,new_s=old.signatures(),new.signatures()
protected=[k for k in old_s if not k.startswith('cutter_')]
assert len(protected)==45
uv_rounding_max=0.0
for name in protected:
    assert len(old_s[name])==len(new_s[name])
    for old_p,new_p in zip(old_s[name],new_s[name]):
        assert old_p['indices']==new_p['indices'] and old_p['material']==new_p['material']
        assert old_p['attributes'].keys()==new_p['attributes'].keys()
        for attr in old_p['attributes']:
            a,b=old_p['attributes'][attr],new_p['attributes'][attr]
            assert len(a)==len(b)
            delta=max(abs(c-d) for v,w in zip(a,b) for c,d in zip(v,w))
            if attr.startswith('TEXCOORD'):
                uv_rounding_max=max(uv_rounding_max,delta)
                assert delta<=1e-7,(name,attr,delta)
            else:assert delta==0.0,(name,attr,delta)
assert not new.doc.get('skins') and not new.doc.get('animations')
runtime=ROOT/'game/assets/weapons/staff_transform_v2/staff_parts.glb'
assert runtime.read_bytes()==new.bytes
triangles=sum(len(p['indices'])//3 for m in new_s.values() for p in m)
config=json.loads((ROOT/'assets/weapons/staff_transform_v2/parts.json').read_text(encoding='utf-8'))
assert triangles==sum(m['triangles'] for m in config['metrics'].values())
edge_report={}
for tag,side in [('l',-1),('r',1)]:
    name='cutter_jaw_'+tag
    node=next(n for n in new.doc['nodes'] if n.get('name')==name)
    t=node['translation']
    assert node.get('rotation',[0,0,0,1])==[0,0,0,1]
    mesh_name=new.doc['meshes'][node['mesh']]['name']
    verts={tuple(round(c+t[i],7) for i,c in enumerate(v)) for p in new_s[mesh_name] for v in p['attributes']['POSITION']}
    edge=[v for v in verts if abs(v[0]-side*.001)<1e-6 and v[1]>.931 and abs(v[2])<.001]
    assert len(edge)>=8,(name,edge)
    assert max(v[1] for v in edge)-min(v[1] for v in edge)>.293
    assert min(side*v[0] for v in verts if v[1]>.931)>.00099,'closed blades cross center plane'
    edge_report[name]={'straight_edge_vertices':len(edge),'y_span':[min(v[1] for v in edge),max(v[1] for v in edge)],'x':side*.001}
report={'passed':True,'protected_meshes_geometry_indices_materials_unchanged':len(protected),
        'protected_uv_export_rounding_max':uv_rounding_max,
        'meshes':len(new_s),'triangles':triangles,'materials':len(new.doc['materials']),
        'closed_edge_gap_m':.002,'edges':edge_report,'runtime_identical':True,
        'asset_sha256':hashlib.sha256(new.bytes).hexdigest()}
(REPORT/'glb_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
