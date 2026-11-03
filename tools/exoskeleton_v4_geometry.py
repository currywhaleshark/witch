"""64-bit topology indices for multi-mesh and multi-outfit collision audits."""
from pathlib import Path
import json,struct,sys,numpy as np
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/drive_tree_v1'

def read(path):
    b=path.read_bytes();n=struct.unpack_from('<I',b,12)[0];return json.loads(b[20:20+n]),b[28+n:]
def access(d,b,i):
    a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    dt={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];item=np.dtype(dt).itemsize;start=v.get('byteOffset',0)+a.get('byteOffset',0)
    out=np.ndarray((a['count'],count),dtype=dt,buffer=b,offset=start,strides=(v.get('byteStride',item*count),item)).copy()
    if a.get('normalized'):out=out.astype(float)/np.iinfo(dt).max
    return out
def local(n):
    if 'matrix' in n:return np.array(n['matrix']).reshape(4,4).T
    a,b,c,d=n.get('rotation',[0,0,0,1]);m=np.eye(4)
    m[:3,:3]=np.array([[1-2*b*b-2*c*c,2*a*b-2*c*d,2*a*c+2*b*d],[2*a*b+2*c*d,1-2*a*a-2*c*c,2*b*c-2*a*d],[2*a*c-2*b*d,2*b*c+2*a*d,1-2*a*a-2*b*b]])@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0]);return m
def frames(d):
    parent={c:i for i,n in enumerate(d['nodes']) for c in n.get('children',[])};cache={}
    def frame(i):
        if i not in cache:cache[i]=(frame(parent[i]) if i in parent else np.eye(4))@local(d['nodes'][i])
        return cache[i]
    return [frame(i) for i in range(len(d['nodes']))]
def garment(path):
    d,b=read(path);result=[]
    for n in d['nodes']:
        if 'mesh' not in n or 'skin' not in n:continue
        skin=d['skins'][n['skin']];names=[d['nodes'][i]['name'] for i in skin['joints']]
        binds=access(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        for p in d['meshes'][n['mesh']]['primitives']:
            a=p['attributes'];v=access(d,b,a['POSITION']);v=np.column_stack([v,np.ones(len(v))])
            j=access(d,b,a['JOINTS_0']);w=access(d,b,a['WEIGHTS_0'])
            if 'JOINTS_1' in a:j=np.column_stack([j,access(d,b,a['JOINTS_1'])]);w=np.column_stack([w,access(d,b,a['WEIGHTS_1'])])
            f=access(d,b,p['indices']).astype(np.int64).reshape(-1,3)
            result.append((names,binds,v,j,w,f))
    return result
def skin(parts,poses):
    vv=[];ff=[];offset=0
    for names,bind,v,j,w,f in parts:
        mats=np.array([poses[name] for name in names])@bind
        xyz=np.zeros((len(v),3))
        for i in range(j.shape[1]):xyz+=np.einsum('nij,nj->ni',mats[j[:,i]],v)[:,:3]*w[:,i,None]
        vv.append(xyz);ff.append(f+offset);offset+=len(v)
    return np.concatenate(vv),np.concatenate(ff)
def crosses(a,b,t):
    d=b-a;e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];h=np.cross(d,e2);det=np.einsum('ij,ij->i',e1,h);good=abs(det)>1e-12;inv=np.zeros_like(det);inv[good]=1/det[good];s=a-t[:,0];u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=inv*np.einsum('ij,ij->i',d,q);tt=inv*np.einsum('ij,ij->i',e2,q)
    return good&(u>1e-7)&(v>1e-7)&(u+v<1-1e-7)&(tt>1e-7)&(tt<1-1e-7)

