from pathlib import Path
import cv2, numpy as np
from PIL import Image, ImageDraw
P=Path(__file__).parent
BASE=Path('/mnt/data/차분한_교복_소녀_초상화.png')
TWIN=Path('/mnt/data/차분한_트윈테일_교복_소녀.png')
a=np.array(Image.open(BASE).convert('RGB')).astype(np.uint8)
b=np.array(Image.open(TWIN).convert('RGB')).astype(np.uint8)
h,w=a.shape[:2]

def polys(coords):
 m=np.zeros((h,w),np.uint8)
 for p in coords: cv2.fillPoly(m,[np.array(p,np.int32)],255)
 return m
# Generous hair scene region: excludes center blouse, skirt, and most face.
roi=polys([
 [(255,430),(255,242),(286,157),(320,85),(401,13),(475,0),(693,0),(766,47),(820,129),(850,223),(832,420),(766,505),(685,550),(638,535),(613,440),(529,453),(449,494),(350,559),(265,592)],
 [(220,240),(330,230),(407,382),(464,480),(453,603),(451,742),(488,803),(432,855),(355,837),(305,791),(254,711),(223,632),(172,807),(132,854),(77,840),(121,701),(148,578),(192,487)],
 [(597,205),(753,150),(853,252),(850,377),(888,459),(946,560),(1000,709),(1047,773),(1019,837),(962,867),(901,859),(820,825),(793,768),(732,824),(699,848),(633,822),(621,765),(630,658),(652,579),(625,507)],
 [(637,487),(716,452),(831,522),(874,657),(894,787),(861,851),(790,846),(702,825),(649,756)]
 ])
# Hair color in generated anime originals is slightly cool neutral charcoal.
A=a.astype(np.float32); B=b.astype(np.float32)
brightnessA=np.mean(A,2);brightnessB=np.mean(B,2)
neutralA=(np.max(A,2)-np.min(A,2)<50)
neutralB=(np.max(B,2)-np.min(B,2)<50)
darkA=(brightnessA<172)&neutralA
darkB=(brightnessB<172)&neutralB
base=(roi>0)&(darkA|darkB)
# Exclude all front bow parts; only admit outer side strands below upper chest.
exclude=polys([
 [(452,616),(637,605),(654,810),(455,834)],
 [(418,831),(685,825),(720,1000),(384,1000)]
 ])
base[exclude>0]=0
# Protect eye/iris & lips. Hair fringe top remains selectable.
cv2.ellipse(exclude,(435,331),(46,33),-7,0,360,255,-1)
cv2.ellipse(exclude,(582,290),(48,35),-6,0,360,255,-1)
cv2.ellipse(exclude,(502,412),(52,34),-12,0,360,255,-1)
base[exclude>0]=0
# Fill isolated dark hair strands, continuous shadow sections.
mask=np.uint8(base)*255
mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9)))
mask=cv2.dilate(mask,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(13,13)),iterations=1)
# Apply region and exclusions after smoothing morphology
mask[exclude>0]=0
mask=np.uint8(mask*(roi>0))
# Differences on edge of hair are blended, but keep solid interior.
mask=cv2.GaussianBlur(mask,(0,0),1.8)
# Surgical correction: the original loose hairstyle places a dark section
# behind the neck where the twin-tail source has clean light background.
# Replace that small area with the existing twin source instead of inventing pixels.
neck=np.zeros((h,w),np.uint8)
cv2.fillPoly(neck,[np.array([(445,459),(514,446),(531,490),(515,518),(461,539),(432,526),(440,484)],np.int32)],255)
neck=cv2.GaussianBlur(neck,(0,0),2.3)
mask=np.maximum(mask,neck)
# Don't disturb the center of the face or eyes.
mask[exclude>0]=0
# keep very white backdrop pixels outside hair unmodified; mask excludes those except halo.
alpha=mask.astype(np.float32)/255
comp=np.uint8(np.clip(A*(1-alpha[:,:,None])+B*alpha[:,:,None],0,255))
# Mask overlay: pixel data is exact replacement from twin for masked regions.
layer=np.concatenate([b,mask[:,:,None]],axis=2)
Image.fromarray(a).save(P/'base_semilong.png',optimize=True)
Image.fromarray(b).save(P/'full_twin_reference.png',optimize=True)
Image.fromarray(layer,'RGBA').save(P/'twin_hair_delta_experimental.png',optimize=True)
Image.fromarray(mask).save(P/'swap_mask.png')
Image.fromarray(comp).save(P/'twin_hair_on_original.png',optimize=True)
# diagnostics: overlay magenta on changed regions
mix=np.uint8(np.clip(0.75*A+0.25*np.array([247,49,143]),0,255))
quality=np.uint8(A*(1-.65*alpha[:,:,None])+mix*(.65*alpha[:,:,None]))
Image.fromarray(quality).save(P/'patch_inspection.png')
montage=Image.new('RGB',(3*460,700),'#f2f0ed')
labels=['① 공통 기준 세미롱','② 트윈테일 부분합성','③ 트윈테일 별도 원화']
for i,img in enumerate([a,comp,b]):
 tile=Image.fromarray(img).resize((460,613),Image.Resampling.LANCZOS)
 montage.paste(tile,(i*460,0))
 ImageDraw.Draw(montage).text((i*460+24,630),labels[i],fill='#222222')
montage.save(P/'comparison.png')
print('size',w,h,'fraction patched',np.mean(mask>100),'output',P)
# Validate face and dress that should be unchanged compared with base
for nm,(x0,y0,x1,y1) in {'eyes':(390,270,630,350),'face':(430,350,620,455),'torso':(310,860,785,1330)}.items():
 print(nm,'mean_abs_delta',np.abs(comp[y0:y1,x0:x1].astype(int)-a[y0:y1,x0:x1].astype(int)).mean())
