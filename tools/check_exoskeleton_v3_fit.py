"""Current rigged GLB against both actual skinned outfits at engine-sampled poses."""
from pathlib import Path
import json,sys,numpy as np
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v3_geometry import read,garment,skin,crosses
R=ROOT/'reports/exoskeleton_v3';eqpath=ROOT/'game/assets/equipment/exoskeleton_v3/exoskeleton_v3.glb'
equipment=garment(eqpath);d,_=read(eqpath)
names=[n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n]
assert len(names)==len(equipment)
owners=np.concatenate([np.full(len(part[-1]),i,dtype=int) for i,part in enumerate(equipment)])
garments={'civilian':garment(ROOT/'game/assets/characters/player/model_refinement_v28/outfit_civilian_v28.glb'),
 'transformed':garment(ROOT/'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb')}
records=json.loads((R/'poses.json').read_text());rows=[];maximum={}
for index,record in enumerate(records):
 if '--quick' in sys.argv and index%2:continue
 xyz,faces=skin(garments[record['form']],record['bones']);cloth=BVHTree.FromPolygons(xyz.tolist(),faces.tolist(),all_triangles=True)
 ev,ef=skin(equipment,record['exo_bones']);tree=BVHTree.FromPolygons(ev.tolist(),ef.tolist(),all_triangles=True)
 pairs=np.array(tree.overlap(cloth),dtype=int);by_part={}
 if len(pairs):
  a=ev[ef[pairs[:,0]]];b=xyz[faces[pairs[:,1]]];hit=np.zeros(len(pairs),bool)
  for j in range(3):hit|=crosses(a[:,j],a[:,(j+1)%3],b)|crosses(b[:,j],b[:,(j+1)%3],a)
  unique=np.unique(pairs[hit,0]);part_ids,counts=np.unique(owners[unique],return_counts=True)
  for i,count in zip(part_ids,counts):by_part[names[i]]=int(count);maximum[names[i]]=max(maximum.get(names[i],0),int(count))
 rows.append({'form':record['form'],'motion':record['motion'],'phase':record['phase'],'crossing_faces':by_part})
 if index%25==24:print('FIT_V3',record['form'],record['motion'],sum(bool(x['crossing_faces']) for x in rows if x['form']==record['form'] and x['motion']==record['motion']),flush=True)
result={'pose_count':len(rows),'poses_with_crossings':sum(bool(x['crossing_faces']) for x in rows),'maximum_by_part':maximum,'poses':rows,
 'scope':'Strict non-coplanar garment/equipment triangle crossings. Actual engine poses and skinned GLB. Excludes hair, bare body, swept collision and arbitrary poses.'}
(R/('fit_quick.json' if '--quick' in sys.argv else 'equipment_fit.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
print('FIT_V3_DONE',result['pose_count'],result['poses_with_crossings'],maximum,flush=True)
