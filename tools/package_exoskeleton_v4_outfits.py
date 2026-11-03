"""Patch sleeve POSITION/NORMAL into original GLB containers, preserving all 107 binds/rests.

Reexporting an imported Blender skeleton changes bone roll; the strict outfit contract
requires the original skeleton and all weights byte-for-byte instead.
"""
from pathlib import Path
import json,struct,hashlib,numpy as np
ROOT=Path(__file__).resolve().parents[1];S=ROOT/'assets/equipment/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4';R=ROOT/'reports/exoskeleton_v4'
m=json.loads((S/'parts.json').read_text());rests={n:np.array(v) for n,v in m['body_rest_frames'].items()};C=np.array([[1,0,0],[0,0,1],[0,-1,0]],dtype=float)
def decode(path):
 b=path.read_bytes();n=struct.unpack_from('<I',b,12)[0];return json.loads(b[20:20+n]),bytearray(b[28+n:])
def accessor(d,b,i):
 a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];count={'VEC3':3}[a['type']];assert a['componentType']==5126
 return np.ndarray((a['count'],count),dtype='<f4',buffer=b,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',count*4),4))
def deform(points,normals):
 p=points.astype(float)@C;n=normals.astype(float)@C;out=p.copy();nn=n.copy();amount=np.zeros(len(p))
 for side,sign in [('L',1),('R',-1)]:
  E=rests['DEF-forearm.'+side][:3,3];W=rests['DEF-hand.'+side][:3,3];axis=W-E;length=np.linalg.norm(axis);axis/=length;u=(p-E)@axis/length
  radial=p-E-np.outer((p-E)@axis,axis);radius=np.linalg.norm(radial,axis=1);t=np.clip((u+.18)/.48,0,1);t=t*t*(3-2*t)
  t[(sign*p[:,0]<.18)|(u<-.18)|(u>1.35)|(radius>.16)]=0
  shrink=np.minimum(.22*t,.022/np.maximum(radius,1e-8));mask=shrink>0;out[mask]=p[mask]-radial[mask]*shrink[mask,None];amount[mask]=radius[mask]*shrink[mask]
  parallel=np.outer(n@axis,axis);normal=parallel+(n-parallel)/(1-shrink[:,None]);normal/=np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-8);nn[mask]=normal[mask]
 return out@C.T,nn@C.T,amount
report={}
for form,rel in [('civilian','model_refinement_v28/outfit_civilian_v28.glb'),('transformed','transformation_v25/outfit_transformed_v4.glb')]:
 src=ROOT/'game/assets/characters/player'/rel;d,b=decode(src);old_d=json.loads(json.dumps(d));before=bytes(b);changed={};ranges=[]
 for node in d['nodes']:
  if 'mesh' not in node:continue
  name=node['name']
  if form!='civilian' or 'Cardigan' not in name:continue
  maximum=0.;count=0
  for prim in d['meshes'][node['mesh']]['primitives']:
   pa=prim['attributes']['POSITION'];na=prim['attributes']['NORMAL'];p=accessor(d,b,pa);n=accessor(d,b,na);new,normal,amount=deform(p.copy(),n.copy());p[:]=new;n[:]=normal
   d['accessors'][pa]['min']=p.min(axis=0).tolist();d['accessors'][pa]['max']=p.max(axis=0).tolist();count+=int(np.count_nonzero(amount));maximum=max(maximum,float(amount.max()))
   for a in [pa,na]:
    ac=d['accessors'][a];view=d['bufferViews'][ac['bufferView']];start=view.get('byteOffset',0)+ac.get('byteOffset',0);stride=view.get('byteStride',12)
    ranges.extend((start+i*stride,start+i*stride+12) for i in range(ac['count']))
  changed[name]={'changed_vertices':count,'max_displacement_m':maximum}
 assert d['nodes']==old_d['nodes'] and d['skins']==old_d['skins']
 mask=np.zeros(len(b),bool)
 for start,end in ranges:mask[start:end]=True
 assert np.array_equal(np.frombuffer(before,dtype='u1')[~mask],np.frombuffer(b,dtype='u1')[~mask])
 j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4);binary=bytes(b)+b'\0'*((-len(b))%4)
 blob=struct.pack('<III',0x46546c67,2,28+len(j)+len(binary))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(binary),0x004e4942)+binary
 if not changed:blob=src.read_bytes()
 name='outfit_'+form+'_fit_v4.glb'
 for path in [S/'exports'/name,G/name]:path.write_bytes(blob)
 report[form]={'source':str(src.relative_to(ROOT)),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'only_position_normal_bytes_changed':True,'nodes_skins_identical':True,'file_byte_identical':blob==src.read_bytes(),'meshes':changed}
(R/'outfit_preservation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('V4_OUTFIT_PACKAGE',report)
