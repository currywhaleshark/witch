"""Author repeatable procedural PBR trim tiles, not lighting or geometry-baked maps."""
from pathlib import Path
import numpy as np
from PIL import Image
import shutil,json
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'assets/weapons/drive_tree_v1/textures';G=ROOT/'game/assets/weapons/drive_tree_v1/textures'
KEYS=['navy','brass','steel','silver','black','teal','core','rope']
COLORS=[[41,58,71],[188,143,81],[36,47,57],[183,192,195],[32,38,43],[39,110,107],[108,202,180],[153,139,106]]

def make():
    rng=np.random.default_rng(317)
    size=1024;tile=size//4
    color=np.zeros((size,size,4),dtype=np.uint8);orm=color.copy();normal=color.copy();emission=color.copy()
    y,x=np.mgrid[0:tile*2,0:tile].astype(float);y/=tile*2-1;x/=tile-1
    def noise(h,w):return np.asarray(Image.fromarray((rng.random((h,w))*255).astype(np.uint8)).resize((tile,tile*2),Image.Resampling.BICUBIC),dtype=float)/255
    cloud=.78*noise(7,5)+.22*noise(24,16)
    fine=rng.random(x.shape);edge=np.minimum.reduce([x,y,1-x,1-y])
    wear=np.clip((.065-edge)/.025,0,1)*np.clip((cloud-.3)*2,0,1)
    for index,(key,c) in enumerate(zip(KEYS,COLORS)):
        # Each material uses one continuous rectangular trim tile.
        rough={'navy':.58,'brass':.43,'steel':.51,'silver':.36,'black':.78,'teal':.56,'core':.35,'rope':.86}[key]
        base=np.array(c,dtype=float)[None,None,:]*(.97+.06*cloud[:,:,None])
        metal=np.ones_like(x) if key in ['brass','silver'] else np.zeros_like(x)
        if key=='brass':
            tarnish=np.clip((cloud-.48)*1.5,0,.25)*(1-wear)
            base=base*(1-tarnish[:,:,None])+np.array([69,65,43])*tarnish[:,:,None]
            metal=1-tarnish;roughness=rough+.20*tarnish
        else:roughness=np.full_like(x,rough)
        if key in ['navy','steel','teal']:
            amount=wear*.60;base=base*(1-amount[:,:,None])+np.array([170,181,184])*amount[:,:,None];metal=amount
        if key=='silver':base+=np.sin(x*650+y*2)[:,:,None]*.4
        rgba=np.zeros((tile*2,tile,4),dtype=np.uint8);rgba[:,:,:3]=np.clip(base,0,255);rgba[:,:,3]=255
        data=np.zeros_like(rgba);data[:,:,0]=255;data[:,:,1]=np.clip((roughness+(cloud-.5)*.13+(fine-.5)*.035)*255,0,255);data[:,:,2]=(metal*255).astype(np.uint8);data[:,:,3]=255
        n=np.zeros_like(rgba);n[:,:,0]=np.clip(127.5+np.cos(x*650)*.8,0,255);n[:,:,1]=np.clip(127.5+(fine-.5)*1.4,0,255);n[:,:,2:]=255
        e=np.zeros_like(rgba);e[:,:,3]=255
        if key=='core':e[:,:,:3]=rgba[:,:,:3]
        # Each key occupies one continuous 256x512 region.
        xx=(index%4)*tile;yy=(index//4)*tile*2
        color[yy:yy+tile*2,xx:xx+tile]=rgba
        orm[yy:yy+tile*2,xx:xx+tile]=data
        normal[yy:yy+tile*2,xx:xx+tile]=n
        emission[yy:yy+tile*2,xx:xx+tile]=e
    for name,array,target in [('color',color,1024),('normal',normal,1024),('orm',orm,512),('emission',emission,256)]:
        p=S/('drive_'+name+'.png');im=Image.fromarray(array)
        if target!=size:im=im.resize((target,target),Image.Resampling.LANCZOS)
        im.save(p);shutil.copyfile(p,G/p.name)
    (S.parent/'trim_layout.json').write_text(json.dumps({'keys':KEYS,'columns':4,'rows':2,'kind':'reusable planar trim charts; intentional UV reuse','maps':{'color':1024,'normal':1024,'orm':512,'emission':256}},indent=2),encoding='utf-8')
    print('DRIVE_TRIM_CREATED',len(KEYS),'material tiles')
if __name__=='__main__':make()
