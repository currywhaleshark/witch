from pathlib import Path
from zipfile import ZipFile
import io,cv2,runpy,numpy as np
from PIL import Image,ImageDraw,ImageFont
P=Path(__file__).parent
# Reuse same original SCG color masks rather than regenerate the art.
with ZipFile('/mnt/data/witch_scg_layers_source.zip') as zipfile:
 for name in ['hair_chestnut','hair_navy','hair_ash','hair_rose', 'iris_blue','iris_amber','iris_green','iris_violet','cardigan_slate','cardigan_sage','cardigan_pink']:
  (P/f'semilong_{name}.png').write_bytes(zipfile.read('witch_scg_prototype/assets/'+name+'.png'))
a=np.array(Image.open(P/'base_semilong.png').convert('RGB'))
b=np.array(Image.open(P/'twin_hair_on_original.png').convert('RGB'))
h,w=b.shape[:2]
# Mask of dark strands from actual twin-tail illustration, excluding face & bow.
Y,X=np.indices((h,w))
roi=np.zeros((h,w),np.uint8)
def poly(points): cv2.fillPoly(roi,[np.array(points,np.int32)],255)
poly([(244,446),(250,200),(309,73),(416,2),(662,0),(778,80),(837,223),(833,440),(774,536),(651,587),(605,472),(474,495),(314,609),(261,570)])
poly([(325,300),(390,387),(447,465),(457,633),(464,821),(416,849),(328,797),(268,760),(234,826),(142,870),(96,842),(134,732),(198,559),(219,424)])
poly([(606,327),(765,248),(833,359),(883,457),(951,630),(1031,799),(983,870),(892,853),(816,819),(727,846),(642,839),(601,778),(647,598)])
# Exclude dark bow, skirt and eyes.
exclude=np.zeros((h,w),np.uint8)
cv2.fillPoly(exclude,[np.array([(438,602),(665,594),(660,834),(437,843)],np.int32)],255)
cv2.ellipse(exclude,(433,334),(45,38),-7,0,360,255,-1)
cv2.ellipse(exclude,(585,289),(44,36),-5,0,360,255,-1)
cv2.ellipse(exclude,(506,416),(50,36),0,0,360,255,-1)
fl=b.astype(np.float32)
r,g,bl=fl[:,:,0],fl[:,:,1],fl[:,:,2]
mean=fl.mean(2);maxc=fl.max(2);minc=fl.min(2)
condition=(mean<178)&((maxc-minc)<55)
mask=((roi>0)&(exclude==0)&condition).astype(np.float32)
mask=cv2.GaussianBlur(mask,(3,3),.55)
atten=np.clip((195-maxc)/45,0,1)
mask=mask*atten
Image.fromarray(np.uint8(mask*255),'L').save(P/'twin_hair_color_mask.png')
lum=.2126*r+.7152*g+.0722*bl
palette={'chestnut':(137,93,74),'navy':(81,103,150),'ash':(181,156,139),'rose':(142,93,112)}
for name,col in palette.items():
 factor=np.clip((lum/82)**.88,.26,1.85)
 rgb=np.uint8(np.clip(np.array(col,dtype=np.float32)[None,None,:]*factor[:,:,None],0,255))
 alpha=np.uint8(np.clip(mask*255,0,255));rgb[alpha==0]=0
 layer=np.dstack((rgb,alpha))
 Image.fromarray(layer,'RGBA').save(P/f'twin_hair_{name}.png',compress_level=3)
# Compare selectable hair colors on both styles for review.
items=[]
for style in ['semilong','twin']:
 for color in [None,'chestnut','navy','ash']:
  x=Image.open(P/'base_semilong.png').convert('RGBA')
  if style=='twin':x=Image.alpha_composite(x,Image.open(P/'twin_hair_delta_experimental.png').convert('RGBA'))
  if color is not None:
   x=Image.alpha_composite(x,Image.open(P/f'{style}_hair_{color}.png').convert('RGBA'))
  x=x.crop((0,0,1086,1000)).resize((310,286),Image.Resampling.LANCZOS).convert('RGB')
  items.append(x)
p=Image.new('RGB',(310*4,286*2),'#efeeeb')
for i,x in enumerate(items):p.paste(x,((i%4)*310,(i//4)*286))
p.save(P/'color_style_grid.png')
print('masked pixel count >127',(mask>.5).sum(),'new palette files ready')
