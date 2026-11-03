"""Author rigid arm-carriage pose correctives from the existing attack clips.

Outfit surfaces are only an offline fitting reference. No runtime cloth collision,
body-motion edits, mesh stretch or hidden equipment is used.
"""
from pathlib import Path
import json,sys,itertools,math,numpy as np
from mathutils import Matrix,Vector,Quaternion
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v4_geometry import read,frames,garment,skin,crosses
from exoskeleton_v4_pose import frame
R=ROOT/'reports/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4'
m=json.loads((G/'parts.json').read_text());rows=json.loads((R/'poses.json').read_text());br={n:Matrix(v) for n,v in json.loads((R/'body_rest.json').read_text()).items()}
d,b=read(G/'exoskeleton_v4.glb');fs=frames(d);rests={n['name']:fs[i] for i,n in enumerate(d['nodes']) if n['name'].startswith('EXO-')}
equipment=garment(G/'exoskeleton_v4.glb');names=[n['name'].removeprefix('ExoV4_') for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']]
local={}
for name,part in zip(names,equipment):
 if not name.startswith(('upper_','forearm_','elbow_','wrist_')):continue
 v,f=skin([part],rests);mat=np.array(m['mechanism_rest_godot'][name]);local[name]=((np.column_stack([v,np.ones(len(v))])@np.linalg.inv(mat).T)[:,:3],f)
cloth={form:garment(G/('outfit_'+form+'_fit_v4.glb')) for form in ['civilian','transformed']}
def proposed(row,side,shift,angle=0):
 out={n:Matrix(v) for n,v in row['mechanism'].items()};chest=Matrix(row['bones']['DEF-chest'])@br['DEF-chest'].inverted();delta=chest.to_3x3()@Vector(shift)
 s=Matrix(row['bones']['DEF-upper_arm.'+side]).translation;e=Matrix(row['bones']['DEF-forearm.'+side]).translation;w=Matrix(row['bones']['DEF-hand.'+side]).translation
 n=(s-e).normalized().cross((w-e).normalized())*(1 if side=='L' else -1);n.normalize();n=Quaternion((w-e).normalized(),math.radians(angle))@n
 ee=e+n*.145+delta;ww=w+n*.10+delta;ss=out['shoulder_'+side].translation
 u=frame(ss,ee-ss,n);a=u.to_3x3().col[1];length=(ee-ss).length
 out['upper_prox_'+side]=u;dist=u.copy();dist.translation+=a*(length-m['anchors'][side]['upper_length']);out['upper_dist_'+side]=dist
 spec=m['upper_slide'][side];start=ss+a*spec['start_offset'];travel=length-spec['start_offset']-spec['end_offset']
 for i in range(spec['segments']):out['upper_slide_'+side+'_'+str(i)]=frame(start+a*(travel-spec['segment_length'])*i/(spec['segments']-1),a,n)
 for role in ['elbow_','forearm_','wrist_']:out[role+side]=frame(ee,ww-ee,n)
 return out
def vertices(row,side,shift,angle):
 out=proposed(row,side,shift,angle);vv=[];ff=[];offset=0
 for role,(v,f) in local.items():
  if not (role.endswith('_'+side) or '_'+side+'_' in role):continue
  mat=np.array(out[role]);vv.append((np.column_stack([v,np.ones(len(v))])@mat.T)[:,:3]);ff.append(f.astype(np.int64)+offset);offset+=len(v)
 return np.concatenate(vv),np.concatenate(ff)
def crossings(row,side,shift,cv,cf,ct,angle=0):
 v,f=vertices(row,side,shift,angle);t=BVHTree.FromPolygons(v.tolist(),f.tolist(),all_triangles=True);pairs=np.array(t.overlap(ct),dtype=int)
 if not len(pairs):return 0
 a=v[f[pairs[:,0]]];b=cv[cf[pairs[:,1]]];hit=np.zeros(len(pairs),bool)
 for j in range(3):hit|=crosses(a[:,j],a[:,(j+1)%3],b)|crosses(b[:,j],b[:,(j+1)%3],a)
 return len(np.unique(pairs[hit,0]))
result=[];previous={};seeds=json.loads((R/'clearance_curve_seeds.json').read_text()) if (R/'clearance_curve_seeds.json').exists() else []
if '--fresh' in sys.argv:seeds=[]
if '--check' in sys.argv:
 curves=json.loads((G/'clearance_curves.json').read_text());row=next(r for r in rows if r['form']=='transformed' and r['motion']=='attack' and abs(r['phase']-.625)<.001)
 side='L';key=next(k for k in curves['attack']['L'] if abs(k['phase']-.625)<.001);out=proposed(row,side,key['shift'],key['angle'])
 print('MATRIX_PARITY',{n:float(np.max(np.abs(np.array(v)-np.array(row['mechanism'][n])))) for n,v in out.items() if n.endswith('_L') or '_L_' in n},flush=True)
 for form in cloth:
  cv,cf=skin(cloth[form],row['bones']);ct=BVHTree.FromPolygons(cv.tolist(),cf.tolist(),all_triangles=True);print('FIT_COUNT',form,crossings(row,side,key['shift'],cv,cf,ct,key['angle']),flush=True)
 print('INDICES_DTYPES',[(form,skin(cloth[form],row['bones'])[1].dtype.str) for form in cloth],flush=True)
 sys.exit(0)
if '--augment' in sys.argv:
 curves=json.loads((G/'clearance_curves.json').read_text());before=json.loads(json.dumps(curves));audit=json.loads((R/'equipment_fit_800.json').read_text());bake_rows=json.loads((R/'bake_poses.json').read_text());report=[]
 requests=[]
 for item in audit['poses']:
  for part in item['crossing_faces']:
   side='L' if '_L' in part else 'R';key=(item['motion'],item['phase'],side)
   if key not in requests:requests.append(key)
 for motion,phase,side in requests:
  row=next(r for r in bake_rows if r['form']=='civilian' and r['motion']==motion and r['phase']==phase);keys=curves[motion][side]
  i=next(i for i in range(1,len(keys)) if keys[i]['phase']>=phase);a=keys[i-1];b=keys[i];t=(phase-a['phase'])/(b['phase']-a['phase']);angle=a['angle']*(1-t)+b['angle']*t;shift=np.array(a['shift'])*(1-t)+np.array(b['shift'])*t
  cv=[];cf=[];offset=0
  for form in cloth:
   v,f=skin(cloth[form],row['bones']);cv.append(v);cf.append(f.astype(np.int64)+offset);offset+=len(v)
  cv=np.concatenate(cv);cf=np.concatenate(cf);ct=BVHTree.FromPolygons(cv.tolist(),cf.tolist(),all_triangles=True)
  candidates=[(0,0,0,0)]
  for d in [.005,.01,.015,.025]:
   for axis in range(3):
    for sign in [-1,1]:
     value=[0,0,0,0];value[axis]=d*sign;candidates.append(tuple(value))
  candidates.extend((0,0,0,a) for a in [-5,5,-10,10,-15,15])
  candidates.extend((x,y,z,a) for x in [0,.01] for y in [0,.01,.025] for z in [0,.01,.025] for a in [0,-5,5])
  candidates.sort(key=lambda v:np.linalg.norm(v[:3])+abs(v[3])*.001)
  best=None
  for x,y,z,turn in candidates:
   candidate=shift+np.array([x,y,z]);count=crossings(row,side,candidate,cv,cf,ct,angle+turn)
   if best is None or count<best['crossings']:best={'phase':phase,'angle':angle+turn,'shift':candidate.tolist(),'crossings':count}
   if count==0:break
  assert best['crossings']==0,(motion,phase,side,best)
  inserted={k:best[k] for k in ['phase','angle','shift']};keys.insert(i,inserted);report.append({'motion':motion,'side':side,**best});print('V4_INSERT_KEY',report[-1],flush=True)
 for motion,sides in before.items():
  for side,keys in sides.items():
   assert all(k in curves[motion][side] for k in keys),'Existing validated keys changed'
 for path in [ROOT/'assets/equipment/exoskeleton_v4/clearance_curves.json',G/'clearance_curves.json']:path.write_text(json.dumps(curves,indent=2))
 (R/'clearance_augmentation.json').write_text(json.dumps({'inserted':report,'old_keys_preserved':True},indent=2));sys.exit(0)
repair='--repair' in sys.argv
if repair:result=json.loads((R/'clearance_curve_fit.json').read_text())['rows']
for idx,row in enumerate(rows):
 if row['form']!='civilian':continue
 if repair and not any(r['motion']==row['motion'] and r['phase']==row['phase'] and r['crossings'] for r in result):continue
 cv=[];cf=[];offset=0
 for form in cloth:
  v,f=skin(cloth[form],row['bones']);cv.append(v);cf.append(f.astype(np.int64)+offset);offset+=len(v)
 cv=np.concatenate(cv);cf=np.concatenate(cf);ct=BVHTree.FromPolygons(cv.tolist(),cf.tolist(),all_triangles=True)
 for side,sg in [('L',1),('R',-1)]:
  if repair and not any(r['motion']==row['motion'] and r['phase']==row['phase'] and r['side']==side and r['crossings'] for r in result):continue
  base=crossings(row,side,[0,0,0],cv,cf,ct);best={'shift':[0,0,0],'angle':0,'crossings':base}
  if base:
   candidates=[]
   if repair:candidates.extend([(.025,.025,.1,0),(.025,.05,.1,0),(.025,0,.125,0)])
   for seed in seeds:
    if seed['motion']==row['motion'] and seed['side']==side and abs(seed['phase']-row['phase'])<.001:
     candidates.append((abs(seed['shift'][0]),seed['shift'][1],seed['shift'][2],seed['angle']))
   prev=previous.get((row['motion'],side))
   if prev:
    x,y,z=prev['shift'];angle=prev['angle']
    candidates.extend([(abs(x),y,z,angle),(abs(x),y+.025,z,angle),(abs(x),y,z+.025,angle)])
   candidates.extend((0,0,0,a) for a in sorted(range(-180,181,15),key=abs))
   shifts=[(0,.025,0),(0,.05,0),(.025,.05,0),(0,.075,0),(.025,.075,0),(0,.1,0),(0,0,.05),(.025,0,.05),(.05,0,0)]
   candidates.extend((*shift,a) for shift in shifts for a in [0,-15,15,-30,30,-60,60,-90,90])
   for x,y,z,angle in candidates:
    shift=[sg*x,y,z];count=crossings(row,side,shift,cv,cf,ct,angle)
    if count<best['crossings']:best={'shift':shift,'angle':angle,'crossings':count}
    if count==0:break
  previous[(row['motion'],side)]=best
  item={'motion':row['motion'],'phase':row['phase'],'side':side,'before':base,**best}
  if repair:
   ri=next(i for i,r in enumerate(result) if r['motion']==row['motion'] and r['phase']==row['phase'] and r['side']==side);result[ri]=item
  else:result.append(item)
  (R/'clearance_curve_fit.json').write_text(json.dumps({'rows':result},indent=2))
  if base:print('FIT_CURVE',row['motion'],round(row['phase'],3),side,base,best,flush=True)
(R/'clearance_curve_fit.json').write_text(json.dumps({'rows':result},indent=2));print('CLEARANCE_CURVE_FIT_DONE',flush=True)
