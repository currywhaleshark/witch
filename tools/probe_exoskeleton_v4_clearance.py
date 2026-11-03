"""Compare rigid forearm swivel policies against both skinned outfits."""
from pathlib import Path
import json,sys,numpy as np
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v3_geometry import read,frames,garment,skin,crosses
from exoskeleton_v4_pose import frame
R=ROOT/'reports/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4'
m=json.loads((G/'parts.json').read_text());rows=json.loads((R/'poses.json').read_text());br={n:Matrix(v) for n,v in json.loads((R/'body_rest.json').read_text()).items()}
d,b=read(G/'exoskeleton_v4.glb');fs=frames(d);rests={n['name']:fs[i] for i,n in enumerate(d['nodes']) if n['name'].startswith('EXO-')}
equipment=garment(G/'exoskeleton_v4.glb');names=[n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']]
ev,ef=skin(equipment,rests);owners=np.concatenate([np.full(len(p[-1]),i) for i,p in enumerate(equipment)])
local=[]
for name,part in zip(names,equipment):
 v,f=skin([part],rests);mat=np.array(m['mechanism_rest_godot'][name.removeprefix('ExoV4_')]);local.append(((np.column_stack([v,np.ones(len(v))])@np.linalg.inv(mat).T)[:,:3],f))
cloth={form:garment(G/('outfit_'+form+'_fit_v4.glb')) for form in ['civilian','transformed']}
def proposed(row,variant):
 out={n:Matrix(v) for n,v in row['mechanism'].items()};p={n:Matrix(v) for n,v in row['bones'].items()};chest=p['DEF-chest']@br['DEF-chest'].inverted()
 for side,sg in [('L',1),('R',-1)]:
  s=p['DEF-upper_arm.'+side].translation;e=p['DEF-forearm.'+side].translation;w=p['DEF-hand.'+side].translation
  n=(s-e).normalized().cross((w-e).normalized())*sg;n.normalize();axis=(w-e).normalized()
  if variant!='base':
   middle=(e+w)*.5;lc=chest.inverted()@middle
   safe=chest.to_3x3()@Vector((lc.x,0,lc.z+.02));safe-=axis*safe.dot(axis)
   if safe.length>.001:
    safe.normalize();amount=float(variant.split('_')[1]);dot=n.dot(safe)
    # Smoothly swivel only when the current hinge side aims toward the body.
    weight=max(0,min(1,(.7-dot)/1.4))*amount
    if n.dot(safe)<-.98:safe=(safe+chest.to_3x3()@Vector((sg*.15,0,-.2))).normalized();safe=(safe-axis*safe.dot(axis)).normalized()
    n=n.lerp(safe,weight).normalized()
  ee=e+n*.145;ww=w+n*.10;ss=out['shoulder_'+side].translation
  u=frame(ss,ee-ss,n);a=u.to_3x3().col[1];length=(ee-ss).length
  out['upper_'+side]=u;out['upper_prox_'+side]=u;dist=u.copy();dist.translation+=a*(length-m['anchors'][side]['upper_length']);out['upper_dist_'+side]=dist
  spec=m['upper_slide'][side];start=ss+a*spec['start_offset'];travel=length-spec['start_offset']-spec['end_offset']
  for i in range(spec['segments']):out['upper_slide_'+side+'_'+str(i)]=frame(start+a*(travel-spec['segment_length'])*i/(spec['segments']-1),a,n)
  for role in ['elbow_','forearm_','wrist_']:out[role+side]=frame(ee,ww-ee,n)
 return out
results=[]
selected=[r for i,r in enumerate(rows) if i%25 in [0,6,10,12,14,16,18,24]]
for idx,row in enumerate(selected):
 cv,cf=skin(cloth[row['form']],row['bones']);ct=BVHTree.FromPolygons(cv.tolist(),cf.tolist(),all_triangles=True)
 for variant in ['base','safe_0.7','safe_1.0','safe_1.3','safe_1.6']:
  poses=proposed(row,variant);vv=[];ff=[];offset=0
  for name,(v,f) in zip(names,local):
   mat=np.array(poses[name.removeprefix('ExoV4_')]);vv.append((np.column_stack([v,np.ones(len(v))])@mat.T)[:,:3]);ff.append(f+offset);offset+=len(v)
  v=np.concatenate(vv);f=np.concatenate(ff);t=BVHTree.FromPolygons(v.tolist(),f.tolist(),all_triangles=True);pairs=np.array(t.overlap(ct),dtype=int);counts={}
  if len(pairs):
   a=v[f[pairs[:,0]]];b=cv[cf[pairs[:,1]]];hit=np.zeros(len(pairs),bool)
   for j in range(3):hit|=crosses(a[:,j],a[:,(j+1)%3],b)|crosses(b[:,j],b[:,(j+1)%3],a)
   for i in np.unique(owners[pairs[hit,0]]):counts[names[i]]=len(np.unique(pairs[hit&(owners[pairs[:,0]]==i),0]))
  results.append({'variant':variant,'form':row['form'],'motion':row['motion'],'phase':row['phase'],'crossings':counts})
 if idx%16==15:print('CLEARANCE_PROBE',idx+1,flush=True)
summary={}
for variant in ['base','safe_0.7','safe_1.0','safe_1.3','safe_1.6']:
 rr=[r for r in results if r['variant']==variant];summary[variant]={'poses':sum(bool(r['crossings']) for r in rr),'faces':sum(sum(r['crossings'].values()) for r in rr)}
(R/'clearance_probe.json').write_text(json.dumps({'summary':summary,'poses':results},indent=2));print('CLEARANCE_DONE',summary,flush=True)
