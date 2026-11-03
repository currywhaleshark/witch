"""Preserve embedded portable exports and reuse the accepted v1 trim images."""
from pathlib import Path
import json,hashlib
from package_firearm_material_assets_v4 import read_glb,write_glb,geometry
ROOT=Path(__file__).resolve().parents[1];S=ROOT/'assets/weapons/drive_tree_v2';G=ROOT/'game/assets/weapons/drive_tree_v2';R=ROOT/'reports/drive_tree_v2'
def main():
    result={}
    for path in G.glob('*.glb'):
        d,b=read_glb(path)
        if all('uri' in im for im in d['images']):d,b=read_glb(S/'exports'/path.name)
        original=geometry(d,b);write_glb(S/'exports'/path.name,d,b);drop=set()
        for im in d['images']:
            vi=im['bufferView'];v=d['bufferViews'][vi];drop.add(vi)
            pixels=b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
            name=im['name'];name=name if name.endswith('.png') else name+'.png'
            target=G.parent/'drive_tree_v1/textures'/name
            assert pixels==target.read_bytes(),name
            im.pop('bufferView');im.pop('mimeType',None);im['uri']='../drive_tree_v1/textures/'+name
        views=[];bb=bytearray();mapping={}
        for vi,v in enumerate(d['bufferViews']):
            if vi in drop:continue
            while len(bb)%4:bb.append(0)
            new=dict(v);new['byteOffset']=len(bb);bb.extend(b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]);mapping[vi]=len(views);views.append(new)
        for ac in d['accessors']:
            if 'bufferView' in ac:ac['bufferView']=mapping[ac['bufferView']]
        d['bufferViews']=views;d['buffers'][0]['byteLength']=len(bb);write_glb(path,d,bytes(bb))
        rd,rb=read_glb(path);assert geometry(rd,rb)==original
        result[path.stem]={'triangles':sum(sum(p['faces'].values()) for p in original.values()),'parts':len(original),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (R/'export_validation.json').write_text(json.dumps({'passed':True,'models':result},indent=2),encoding='utf-8')
    print('DRIVE_V2_PACKAGED',result)
if __name__=='__main__':main()
