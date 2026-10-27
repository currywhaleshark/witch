"""Pack existing Tripo part maps without repainting them; one material per summon."""
import json,struct,io,math,hashlib
from pathlib import Path
from PIL import Image,ImageOps
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/summons_v2'
SIZE=1024;PAD=3
for actor in ['automaton','turret']:
    src=BASE/'source'/f'{actor}_segmented_v2.glb';raw=src.read_bytes();n=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+n]);binary=raw[28+n:]
    def tex(index):
        image=doc['images'][doc['textures'][index]['source']];v=doc['bufferViews'][image['bufferView']];start=v.get('byteOffset',0)
        return Image.open(io.BytesIO(binary[start:start+v['byteLength']])).convert('RGB')
    mats=[]
    for m in doc['materials']:
        pbr=m['pbrMetallicRoughness'];images=[tex(pbr['baseColorTexture']['index']),tex(pbr['metallicRoughnessTexture']['index']),tex(m['normalTexture']['index'])]
        mats.append({'name':m['name'],'images':images,'size':images[0].width})
    # Binary guillotine packing, padded boundaries; proportional downsampling.
    scale=.46
    while True:
        free=[(0,0,SIZE,SIZE)];placements={};ok=True
        for m in sorted(mats,key=lambda m:(-m['size'],m['name'])):
            side=max(12,round(m['size']*scale));need=side+PAD*2
            candidates=[(w*h,i) for i,(x,y,w,h) in enumerate(free) if w>=need and h>=need]
            if not candidates:ok=False;break
            _,idx=min(candidates);x,y,w,h=free.pop(idx)
            placements[m['name']]={'x':x+PAD,'y':y+PAD,'size':side,'original_size':m['size']}
            if w>need:free.append((x+need,y,w-need,need))
            if h>need:free.append((x,y+need,w,h-need))
        if ok:break
        scale*=.94
        assert scale>.1
    atlases=[Image.new('RGB',(SIZE,SIZE),c) for c in [(60,48,28),(0,180,160),(128,128,255)]]
    for m in mats:
        p=placements[m['name']];s=p['size']
        for srcim,dest in zip(m['images'],atlases):
            im=srcim.resize((s,s),Image.Resampling.LANCZOS)
            tile=Image.new('RGB',(s+PAD*2,s+PAD*2));tile.paste(im,(PAD,PAD))
            tile.paste(im.crop((0,0,1,s)).resize((PAD,s)),(0,PAD));tile.paste(im.crop((s-1,0,s,s)).resize((PAD,s)),(s+PAD,PAD))
            tile.paste(tile.crop((0,PAD,s+PAD*2,PAD+1)).resize((s+PAD*2,PAD)),(0,0))
            tile.paste(tile.crop((0,s+PAD-1,s+PAD*2,s+PAD)).resize((s+PAD*2,PAD)),(0,s+PAD))
            dest.paste(tile,(p['x']-PAD,p['y']-PAD))
    folder=BASE/'textures'/actor;folder.mkdir(parents=True,exist_ok=True)
    for label,im in zip(['color','metal_rough','normal'],atlases):im.save(folder/f'{label}.png')
    (folder/'atlas.json').write_text(json.dumps({'size':SIZE,'padding':PAD,'scale':scale,'materials':placements,'source_sha256':hashlib.sha256(raw).hexdigest()},indent=2),encoding='utf-8',newline='\n')
    print(actor,'materials',len(mats),'atlas',SIZE,'scale',round(scale,3))
