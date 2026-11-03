"""Share authored trim PNGs in runtime, keep portable embedded GLBs."""
from pathlib import Path
import json,struct,hashlib
from package_firearm_material_assets_v4 import read_glb,write_glb,geometry
ROOT=Path(__file__).resolve().parents[1];S=ROOT/'assets/weapons/drive_tree_v1';G=ROOT/'game/assets/weapons/drive_tree_v1';R=ROOT/'reports/drive_tree_v1'

def main():
    results={};textures={}
    for path in G.glob('*.glb'):
        d,b=read_glb(path)
        if all('uri' in im for im in d['images']):d,b=read_glb(S/'exports'/path.name)
        original=geometry(d,b);write_glb(S/'exports'/path.name,d,b);drop=set()
        for im in d['images']:
            vi=im['bufferView'];v=d['bufferViews'][vi];drop.add(vi)
            pixels=b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
            name=im['name'];name=name if name.endswith('.png') else name+'.png'
            h=hashlib.sha256(pixels).hexdigest()
            if name in textures:assert textures[name]==h
            textures[name]=h;(G/'textures'/name).write_bytes(pixels)
            im.pop('bufferView');im.pop('mimeType',None);im['uri']='textures/'+name
        views=[];bb=bytearray();mapping={}
        for vi,v in enumerate(d['bufferViews']):
            if vi in drop:continue
            while len(bb)%4:bb.append(0)
            new=dict(v);new['byteOffset']=len(bb);bb.extend(b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]);mapping[vi]=len(views);views.append(new)
        for ac in d['accessors']:
            if 'bufferView' in ac:ac['bufferView']=mapping[ac['bufferView']]
        d['bufferViews']=views;d['buffers'][0]['byteLength']=len(bb);write_glb(path,d,bytes(bb))
        rd,rb=read_glb(path);assert geometry(rd,rb)==original
        assert all('TANGENT' in p['attributes'] for m in d['meshes'] for p in m['primitives'])
        results[path.stem]={'parts':len(original),'triangles':sum(sum(p['faces'].values()) for p in original.values()),'materials':len(d['materials']),'bytes':path.stat().st_size,'images':[im['uri'] for im in d['images']]}
    (R/'export_validation.json').write_text(json.dumps({'passed':True,'models':results,'textures':textures},indent=2),encoding='utf-8')
    print('DRIVE_PACKAGED',len(results),'models',sum(x['triangles'] for x in results.values()),'triangles')
if __name__=='__main__':main()
