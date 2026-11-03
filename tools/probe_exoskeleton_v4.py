"""Numerical fitting alternatives only; temporary longitudinal stretch is diagnostic.
Final authored parts must use rigid telescoping segments instead.
"""
from pathlib import Path
import json,sys,numpy as np
from mathutils import Matrix,Vector,Quaternion
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4';R.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v3_geometry import read,frames,garment,skin,crosses
M=json.loads((ROOT/'assets/equipment/exoskeleton_v3/parts.json').read_text());BR=json.loads((ROOT/'reports/exoskeleton_v3/body_rest.json').read_text());ROWS=json.loads((ROOT/'reports/exoskeleton_v3/poses.json').read_text())
P=ROOT/'game/assets/equipment/exoskeleton_v3/exoskeleton_v3.glb';D,B=read(P);F=frames(D);rests={n['name']:F[i] for i,n in enumerate(D['nodes']) if n['name'].startswith('EXO-')};raw=garment(P)
NAMES=[n['name'].removeprefix('ExoV3_') for n in D['nodes'] if 'mesh' in n and 'skin' in n]
equipment={}
for name,part in zip(NAMES,raw):
 v,f=skin([part],rests);mat=np.array(M['mechanism_rest_godot'][name]);lv=(np.column_stack([v,np.ones(len(v))])@np.linalg.inv(mat).T)[:,:3]
 equipment[name]=(lv,f)
def frame(p,y,z):
 y=Vector(y).normalized();z=Vector(z);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized();m=Matrix((x,y,z)).transposed().to_4x4();m.translation=p;return m
def vec(v):return Vector((v[0],v[2],-v[1]))
def proposed(row,offset=.10,leg_shift=.015,hood_offset=.16,swing_weight=.0):
 bones={n:Matrix(v) for n,v in row['bones'].items()};chest=bones['DEF-chest']@Matrix(BR['DEF-chest']).inverted();out={n:Matrix(v) for n,v in row['mechanism'].items()}
 for side,sign in [('L',1),('R',-1)]:
  s=bones['DEF-upper_arm.'+side].translation;e=bones['DEF-forearm.'+side].translation;w=bones['DEF-hand.'+side].translation
  n=out['upper_'+side].to_3x3().col[2].normalized();ee=e+n*.145;ww=w+n*offset
  hood_y=chest.to_3x3()@Vector((sign*.063,-.240,-.01))
  swing=Quaternion().slerp(hood_y.normalized().rotation_difference((e-s).normalized()),swing_weight)
  ss=s+swing@(chest.to_3x3()@Vector((sign*hood_offset,.035,-.04)))
  out['shoulder_'+side]=frame(ss,swing@hood_y,swing@(chest.to_3x3()@Vector((sign,0,0))))
  for role in ['forearm_','wrist_','elbow_']:out[role+side]=frame(ee,ww-ee,n)
  out['upper_'+side]=frame(ss,ee-ss,n)
  # Constant authored rest length changes for the forearm; variable upper length only for this diagnostic.
  for role in ['forearm_','wrist_','elbow_']:out[role+side]@=Matrix.Diagonal((1,(ww-ee).length/M['anchors'][side]['forearm_length'],1,1))
  out['upper_'+side]@=Matrix.Diagonal((1,(ee-ss).length/M['anchors'][side]['upper_length'],1,1))
  delta=bones['DEF-shin.'+side]@Matrix(BR['DEF-shin.'+side]).inverted()
  for role in ['shin_','knee_']:
   # Top seats closer, shin lower endpoint rises for ankle/boot flexion clearance.
   T=Matrix.Translation((0,0,-leg_shift))
   if role=='shin_':T=Matrix.Translation((0,.43,0))@Matrix.Diagonal((1,.78,1,1))@Matrix.Translation((0,-.43,0))@T
   out[role+side]=delta@T@Matrix(M['mechanism_rest_godot'][role+side])
 return out
def count(v,f,cv,cf,ct):
 t=BVHTree.FromPolygons(v.tolist(),f.tolist(),all_triangles=True);pairs=np.array(t.overlap(ct),dtype=int)
 if not len(pairs):return 0,{}
 a=v[f[pairs[:,0]]];b=cv[cf[pairs[:,1]]];hit=np.zeros(len(pairs),bool)
 for j in range(3):hit|=crosses(a[:,j],a[:,(j+1)%3],b)|crosses(b[:,j],b[:,(j+1)%3],a)
 return len(np.unique(pairs[hit,0])),pairs[hit,1].tolist()
paths={'civilian':ROOT/'game/assets/characters/player/model_refinement_v28/outfit_civilian_v28.glb','transformed':ROOT/'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb'}
garments={k:garment(p) for k,p in paths.items()};owners={};cloth_names={}
for k,p in paths.items():
 d,b=read(p);cloth_names[k]=[n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']];owners[k]=np.concatenate([np.full(len(part[-1]),i) for i,part in enumerate(garments[k])])
selected=[r for i,r in enumerate(ROWS) if i%25 in [0,6,12,18,24]]
results=[]
for idx,row in enumerate(selected):
 cv,cf=skin(garments[row['form']],row['bones']);ct=BVHTree.FromPolygons(cv.tolist(),cf.tolist(),all_triangles=True)
 for variant in ['v3','swing_050','swing_075','swing_100']:
  poses={n:Matrix(v) for n,v in row['mechanism'].items()} if variant=='v3' else proposed(row,swing_weight=int(variant[-3:])/100)
  counts={};by_cloth={}
  for role in equipment:
   if not role.startswith(('shoulder','upper','elbow','forearm','wrist','knee','shin')):continue
   v,f=equipment[role];p=(np.column_stack([v,np.ones(len(v))])@np.array(poses[role]).T)[:,:3];c,hits=count(p,f,cv,cf,ct)
   if c:
    counts[role]=c;ids,nn=np.unique(owners[row['form']][hits],return_counts=True);by_cloth[role]={cloth_names[row['form']][i]:int(n) for i,n in zip(ids,nn)}
  results.append({'variant':variant,'form':row['form'],'motion':row['motion'],'phase':row['phase'],'crossings':counts,'cloth':by_cloth})
 if idx%10==9:print('V4_PROBE',idx+1,flush=True)
out={'poses':results,'summary':{}}
for v in ['v3','swing_050','swing_075','swing_100']:
 rr=[r for r in results if r['variant']==v];out['summary'][v]={'poses_with_crossings':sum(bool(r['crossings']) for r in rr),'sum_crossed_faces':sum(sum(r['crossings'].values()) for r in rr),'by_part':{part:sum(r['crossings'].get(part,0) for r in rr) for part in equipment if part.startswith(('shoulder','upper','elbow','forearm','wrist','knee','shin'))}}
(R/'fitting_probe.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print('V4_PROBE_DONE',out['summary'],flush=True)
