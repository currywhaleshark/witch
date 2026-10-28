"""Independent binary/skin/texture validation for the promoted actor GLBs."""
import struct,json,hashlib,io
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/boss_trial_v1'
REPORT=ROOT/'reports/boss_trial_v1'
DT={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
files=[];errors=[]
def check(condition,message):
    if not condition:errors.append(message)
for spec in json.loads((BASE/'production.json').read_text(encoding='utf-8-sig'))['assets']:
    actor=spec['id'];path=BASE/'exports'/f'{actor}_v1.glb';raw=path.read_bytes()
    magic,version,total=struct.unpack_from('<III',raw)
    check(magic==0x46546c67 and version==2 and total==len(raw),actor+' GLB header')
    n,tag=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);start=20+n
    bsize,btag=struct.unpack_from('<II',raw,start);binary=raw[start+8:start+8+bsize]
    def arr(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        dtype=np.dtype(DT[a['componentType']]);count=NC[a['type']]
        result=np.ndarray((a['count'],count),dtype=dtype,buffer=binary,
            offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dtype.itemsize*count),dtype.itemsize)).copy()
        if a.get('normalized',False) and a['componentType']!=5126:result=result.astype(float)/np.iinfo(dtype).max
        return result
    tris=0;max_error=0.;max_joints=0
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            at=p['attributes'];pos=arr(at['POSITION']);indices=arr(p['indices']).ravel();weights=arr(at['WEIGHTS_0']);joints=arr(at['JOINTS_0'])
            check(np.isfinite(pos).all(),actor+' finite vertices');check(int(indices.max())<len(pos),actor+' indices')
            check(np.isfinite(weights).all() and np.all(weights>=0),actor+' finite nonnegative weights')
            max_error=max(max_error,float(np.max(np.abs(weights.sum(1)-1))))
            max_joints=max(max_joints,int((weights>1e-6).sum(1).max()))
            check(np.all(joints<len(doc['skins'][0]['joints'])),actor+' joint bounds')
            check(np.isfinite(arr(at['TEXCOORD_0'])).all(),actor+' UVs')
            tris+=len(indices)//3
    check(max_error<.0001 and max_joints==1,actor+' normalized single-influence rigid skin')
    for skin in doc['skins']:
        binds=arr(skin['inverseBindMatrices']).reshape((-1,4,4));check(np.isfinite(binds).all(),actor+' finite binds')
        check(np.all(np.abs(np.linalg.det(binds))>1e-8),actor+' invertible binds')
    images=[]
    for im in doc['images']:
        v=doc['bufferViews'][im['bufferView']];image=Image.open(io.BytesIO(binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]))
        size=2048 if actor=='latch' else 1024
        check(image.size==(size,size),actor+' expected runtime map size')
        images.append({'name':im.get('name',''),'size':image.size})
    animations={}
    for anim in doc.get('animations',[]):
        end=0.
        for sampler in anim['samplers']:
            time=arr(sampler['input']).ravel();values=arr(sampler['output'])
            check(np.isfinite(values).all() and np.all(np.diff(time)>=0),actor+' animation data')
            end=max(end,float(time[-1]))
        animations[anim['name']]={'seconds':end,'channels':len(anim['channels'])}
    expected={'idle','move','sweep','slam','frames','shockwave','hit','death'} if actor=='latch' else {'idle','open','close'} if actor=='door' else {'idle'}
    check(set(animations)==expected,actor+' complete clip family')
    for anim in doc['animations']:
        check(len(anim['channels'])==len(doc['skins'][0]['joints'])*3,actor+' constant TRS tracks retained')
        for sampler in anim['samplers']:
            check(abs(float(arr(sampler['input'])[0,0]))<1e-8,actor+' animation begins at zero')
    check(tris<=spec['target_triangles'],actor+' triangle budget')
    runtime=ROOT/'game/assets/actors/boss_trial_v1'/path.name
    check(runtime.read_bytes()==raw,actor+' promoted bytes equal export')
    files.append({'id':actor,'file':path.name,'triangles':tris,'bones':len(doc['skins'][0]['joints']),
        'max_weight_sum_error':max_error,'max_influences':max_joints,'images':images,'animations':animations,
        'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
for name,expected_hash in json.loads((BASE/'production.json').read_text(encoding='utf-8'))['protected_files'].items():
    check(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected_hash,'protected file unchanged: '+name)
result={'passed':not errors,'errors':errors,'files':files,'total_triangles':sum(f['triangles'] for f in files)}
(REPORT/'glb_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
raise SystemExit(bool(errors))
