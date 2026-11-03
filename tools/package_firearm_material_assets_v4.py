"""Keep portable embedded exports, then share one texture set across runtime GLBs."""
import json,struct,hashlib,collections,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'assets/weapons/firearm_material_v4';G=ROOT/'game/assets/weapons/firearm_material_v4';R=ROOT/'reports/firearm_material_v4'

def read_glb(p):
    raw=p.read_bytes();size=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+size]),raw[28+size:]

def write_glb(p,d,b):
    j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4);b+=b'\0'*((-len(b))%4)
    p.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(b))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(b),0x004e4942)+b)

def accessor(d,b,i):
    a=d['accessors'][i];v=d['bufferViews'][a['bufferView']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    c={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
    fmt='<'+c*n;stride=v.get('byteStride',struct.calcsize(fmt));start=v.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from(fmt,b,start+k*stride) for k in range(a['count'])]

def geometry(d,b):
    result={}
    for node in d['nodes']:
        if 'mesh' not in node:continue
        role=node['name'].split('__',1)[-1];faces=[];normals=[]
        for p in d['meshes'][node['mesh']]['primitives']:
            pos=accessor(d,b,p['attributes']['POSITION']);nr=accessor(d,b,p['attributes']['NORMAL'])
            ids=[x[0] for x in accessor(d,b,p['indices'])]
            for i in range(0,len(ids),3):
                tri=[tuple(round(x,6) for x in pos[j]) for j in ids[i:i+3]]
                faces.append(min(tuple(tri[s:]+tri[:s]) for s in range(3)))
            normals.extend(tuple(round(x,4) for x in (*v,*n)) for v,n in zip(pos,nr))
        result[role]={'faces':collections.Counter(faces),'normals':set(normals),
                      'transform':{k:node[k] for k in ['translation','rotation','scale','matrix'] if k in node}}
    return result

def restore_normals(old,old_bin,new,new_bin):
    # Blender re-encodes custom split normals when making the temporary triangle
    # mesh (up to 0.35 degrees on curved rods). Restore accepted normals by vertex
    # position / closest split normal, then orthogonalize the new UV tangents.
    data=bytearray(new_bin);maximum=0.
    def store_vec(index,vertex,value):
        a=new['accessors'][index];v=new['bufferViews'][a['bufferView']]
        count={'VEC3':3,'VEC4':4}[a['type']]
        offset=v.get('byteOffset',0)+a.get('byteOffset',0)+vertex*v.get('byteStride',count*4)
        struct.pack_into('<'+'f'*count,data,offset,*value)
    for node in new['nodes']:
        if 'mesh' not in node:continue
        role=node['name'].split('__',1)[1]
        old_node=next(n for n in old['nodes'] if n['name'].endswith('__'+role))
        op=old['meshes'][old_node['mesh']]['primitives'][0]
        original=collections.defaultdict(list)
        for p,n in zip(accessor(old,old_bin,op['attributes']['POSITION']),accessor(old,old_bin,op['attributes']['NORMAL'])):
            original[tuple(round(x,6) for x in p)].append(n)
        for q in new['meshes'][node['mesh']]['primitives']:
            aa=q['attributes'];pos=accessor(new,new_bin,aa['POSITION']);norm=accessor(new,new_bin,aa['NORMAL']);tan=accessor(new,new_bin,aa['TANGENT'])
            for i,(p,n,t) in enumerate(zip(pos,norm,tan)):
                candidates=original[tuple(round(x,6) for x in p)]
                exact=min(candidates,key=lambda c:sum((a-b)**2 for a,b in zip(c,n)))
                delta=math.sqrt(sum((a-b)**2 for a,b in zip(exact,n)));maximum=max(maximum,delta)
                assert delta<.008,(role,delta)
                store_vec(aa['NORMAL'],i,exact)
                dot=sum(a*b for a,b in zip(exact,t[:3]));tv=[a-dot*b for a,b in zip(t[:3],exact)]
                length=math.sqrt(sum(x*x for x in tv));assert length>.99
                store_vec(aa['TANGENT'],i,tuple(x/length for x in tv)+(t[3],))
    return bytes(data),maximum

def main():
    (S/'exports').mkdir(exist_ok=True);(G/'textures').mkdir(exist_ok=True)
    metrics={};hashes={}
    for asset_id in ['powder_barrel', 'gatling', 'smoke_launcher', 'artillery_shell', 'naval_shell', 'smoke_canister']:
        path=G/(asset_id+'.glb');d,b=read_glb(path)
        if all('uri' in im for im in d['images']):d,b=read_glb(S/'exports'/path.name)
        before,old_bin=read_glb(ROOT/'game/assets/weapons/firearm_tree_v1'/path.name)
        b,delta=restore_normals(before,old_bin,d,b)
        write_glb(S/'exports'/path.name,d,b)
        a=geometry(before,old_bin);z=geometry(d,b)
        assert a.keys()==z.keys()
        for role in a:
            assert a[role]['faces']==z[role]['faces'],(asset_id,role,'triangle topology')
            assert a[role]['transform']==z[role]['transform'],(asset_id,role,'pivot')
            assert a[role]['normals']==z[role]['normals'],(asset_id,role,'normals')
        all_pr=[p for m in d['meshes'] for p in m['primitives']]
        assert all('TANGENT' in p['attributes'] for p in all_pr)
        drop=set()
        for im in d['images']:
            vi=im['bufferView'];v=d['bufferViews'][vi];drop.add(vi)
            data=b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
            name=im['name']+'.png';digest=hashlib.sha256(data).hexdigest()
            if name in hashes:assert hashes[name]==digest
            hashes[name]=digest;(G/'textures'/name).write_bytes(data)
            im.pop('bufferView');im.pop('mimeType',None);im['uri']='textures/'+name
        views=[];bb=bytearray();remap={}
        for vi,v in enumerate(d['bufferViews']):
            if vi in drop:continue
            while len(bb)%4:bb.append(0)
            nv=dict(v);nv['byteOffset']=len(bb)
            bb.extend(b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])
            remap[vi]=len(views);views.append(nv)
        for ac in d['accessors']:
            if 'bufferView' in ac:ac['bufferView']=remap[ac['bufferView']]
        d['bufferViews']=views;d['buffers'][0]['byteLength']=len(bb)
        write_glb(path,d,bytes(bb))
        rd,rb=read_glb(path);assert geometry(rd,rb)==z
        metrics[asset_id]={'geometry_and_pivots_match_v1':True,'normals_equal_rounded_1e4':True,'parts':len(z),
            'triangles':sum(sum(q['faces'].values()) for q in z.values()),'tangents':len(all_pr),
            'materials':len(d['materials']),'bytes':path.stat().st_size,'normal_reencode_delta_repaired':delta,
            'textures':[im['uri'] for im in d['images']]}
    (R/'export_validation.json').write_text(json.dumps({'passed':True,'models':metrics,'shared_textures':hashes},indent=2),encoding='utf-8')
    print(json.dumps(metrics,indent=2))
if __name__=='__main__':main()
