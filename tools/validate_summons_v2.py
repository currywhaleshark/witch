"""Independent GLB checks: a triangle can never stretch across separate parts."""
import json,struct,hashlib,io
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/summons_v2';OUT=ROOT/'reports/summons_v2'
DT={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
errors=[];assets=[]
def check(ok,label):
    if not ok:errors.append(label)
for actor in ['automaton','turret']:
    path=BASE/'exports'/f'{actor}_v2.glb';raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);binary=raw[28+n:]
    check(struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw)),actor+' header')
    def arr(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];dt=np.dtype(DT[a['componentType']]);count=NC[a['type']]
        result=np.ndarray((a['count'],count),dtype=dt,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*count),dt.itemsize)).copy()
        if a.get('normalized') and a['componentType']!=5126:result=result.astype(float)/np.iinfo(dt).max
        return result
    triangles=0;weighted_joints=set()
    for mesh in doc['meshes']:
        check(len(mesh['primitives'])==1,actor+' one runtime material surface')
        for p in mesh['primitives']:
            at=p['attributes'];pos=arr(at['POSITION']);idx=arr(p['indices']).ravel();w=arr(at['WEIGHTS_0']);j=arr(at['JOINTS_0'])
            check(np.isfinite(pos).all() and idx.max()<len(pos),actor+' positions and indices')
            check(np.all((w>1e-6).sum(1)==1) and np.max(abs(w.sum(1)-1))<1e-6,actor+' exactly one full rigid influence')
            joint=j[np.arange(len(j)),w.argmax(1)];faces=joint[idx].reshape(-1,3)
            check(np.all(faces[:,0]==faces[:,1]) and np.all(faces[:,0]==faces[:,2]),actor+' no triangle spans independently moving parts')
            weighted_joints.update(int(i) for i in joint);triangles+=len(idx)//3
            check(np.isfinite(arr(at['TEXCOORD_0'])).all(),actor+' finite atlas UV')
    names=[doc['nodes'][i]['name'] for i in doc['skins'][0]['joints']]
    expected=13 if actor=='automaton' else 86
    check(len(weighted_joints)==expected and all(names[i].startswith('part_') for i in weighted_joints),actor+' all segmented rigid parts weighted')
    check(len(doc['materials'])==1 and len(doc['images'])==3,actor+' one PBR material / three atlas maps')
    for image in doc['images']:
        v=doc['bufferViews'][image['bufferView']];start=v.get('byteOffset',0);im=Image.open(io.BytesIO(binary[start:start+v['byteLength']]))
        check(im.size==(1024,1024),actor+' 1K atlas')
    animations={}
    for animation in doc['animations']:
        end=0
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']];values=arr(sampler['output']);times=arr(sampler['input']).ravel()
            check(np.isfinite(values).all() and np.all(np.diff(times)>=0),actor+' finite animation')
            if channel['target']['path']=='scale':check(np.max(abs(values-1))<1e-5,actor+' unit scale at every key')
            if channel['target']['path']=='rotation':check(np.max(abs(np.linalg.norm(values,axis=1)-1))<1e-5,actor+' normalized rotations')
            end=max(end,float(times[-1]))
        animations[animation['name']]={'seconds':end,'tracks':len(animation['channels'])}
        check(abs(end-({'attack':1.,'hit':.5,'move':1.}.get(animation['name'],2.)))<1e-5,actor+' clip starts at zero and retains authored duration')
    check(set(['idle','attack','hit','death']+(['move','explode'] if actor=='automaton' else [])).issubset(animations),actor+' required clips')
    check(triangles<=(10000 if actor=='automaton' else 18000),actor+' working triangle budget')
    check((ROOT/'game/assets/actors/summons_v2'/path.name).read_bytes()==raw,actor+' promoted bytes equal export')
    build=json.loads((OUT/'build'/actor/'build.json').read_text())
    check(hashlib.sha256((BASE/'source'/f'{actor}_segmented_v2.glb').read_bytes()).hexdigest()==build['source_sha256'],actor+' user segmented source unchanged')
    assets.append({'id':actor,'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'triangles':triangles,'parts':expected,'bones':len(names),'materials':1,'atlas_size':1024,'max_influences':1,'animations':animations})
result={'passed':not errors,'errors':errors,'assets':assets,'scope':'All exported triangles have one shared rigid joint; every scale key is one. No inter-part or arbitrary environment collision claim.'}
(OUT/'glb_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2));raise SystemExit(bool(errors))
