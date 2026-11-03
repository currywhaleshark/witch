"""Actual skinned equipment/garment triangle crossings and calf support clearance."""
from pathlib import Path
import json,sys,numpy as np
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v4_geometry import read,garment,skin,crosses
R=ROOT/'reports/exoskeleton_v4';baseline='--baseline' in sys.argv;version='v3' if baseline else 'v4';G=ROOT/('game/assets/equipment/exoskeleton_'+version);m=json.loads((G/'parts.json').read_text());equipment=garment(G/('exoskeleton_'+version+'.glb'));d,_=read(G/('exoskeleton_'+version+'.glb'))
names=[n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']];assert len(names)==len(equipment)
owners=np.concatenate([np.full(len(part[-1]),i,dtype=int) for i,part in enumerate(equipment)])
paths={form:G/('outfit_'+form+'_fit_v4.glb') for form in ['civilian','transformed']}
if baseline:paths={'civilian':ROOT/'game/assets/characters/player/model_refinement_v28/outfit_civilian_v28.glb','transformed':ROOT/'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb'}
garments={form:garment(path) for form,path in paths.items()}
clothing_names={};cloth_owners={}
for form in garments:
 d,_=read(paths[form]);clothing_names[form]=[n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']];cloth_owners[form]=np.concatenate([np.full(len(part[-1]),i,dtype=int) for i,part in enumerate(garments[form])])
record_dir=ROOT/('reports/exoskeleton_'+version);records=json.loads((record_dir/('bake_poses.json' if '--bake' in sys.argv else 'poses.json')).read_text());rows=[];maximum={};band_rows=[];C=np.array([[1,0,0],[0,0,1],[0,-1,0]])
for index,record in enumerate(records):
 if '--quick' in sys.argv and index%2:continue
 xyz,faces=skin(garments[record['form']],record['bones']);cloth=BVHTree.FromPolygons(xyz.tolist(),faces.tolist(),all_triangles=True)
 ev,ef=skin(equipment,record['exo_bones']);tree=BVHTree.FromPolygons(ev.tolist(),ef.tolist(),all_triangles=True);pairs=np.array(tree.overlap(cloth),dtype=int);by_part={};by_cloth={}
 if len(pairs):
  a=ev[ef[pairs[:,0]]];b=xyz[faces[pairs[:,1]]];hit=np.zeros(len(pairs),bool)
  for j in range(3):hit|=crosses(a[:,j],a[:,(j+1)%3],b)|crosses(b[:,j],b[:,(j+1)%3],a)
  for i in np.unique(owners[pairs[hit,0]]):
   match=hit&(owners[pairs[:,0]]==i);name=names[i];by_part[name]=by_part.get(name,0)+len(np.unique(pairs[match,0]))
   ids,counts=np.unique(cloth_owners[record['form']][pairs[match,1]],return_counts=True);by_cloth[name]={clothing_names[record['form']][j]:int(c) for j,c in zip(ids,counts)}
  for name,c in by_part.items():maximum[name]=max(maximum.get(name,0),c)
 for part in m['parts']:
  if 'contact_samples_blender' not in part:continue
  role=part['role'];movement=np.array(record['mechanism'][role])@np.linalg.inv(np.array(m['mechanism_rest_godot'][role]));points=np.array(part['contact_samples_blender'])@C.T;points=(np.column_stack([points,np.ones(len(points))])@movement.T)[:,:3]
  dd=[cloth.find_nearest(p)[3] for p in points];band_rows.append({'form':record['form'],'motion':record['motion'],'phase':record['phase'],'part':role,'minimum_m':min(dd),'maximum_m':max(dd),'mean_m':float(np.mean(dd))})
 rows.append({'form':record['form'],'motion':record['motion'],'phase':record['phase'],'crossing_faces':by_part,'garments':by_cloth})
 if index%50==49:print('V4_FIT',index+1,flush=True)
out={'pose_count':len(rows),'poses_with_crossings':sum(bool(x['crossing_faces']) for x in rows),'maximum_by_part':maximum,'poses':rows,'calf_supports':band_rows,'scope':'Actual engine poses and rigid/skinned GLBs; strict garment triangle crossings. Calf inner-surface samples use nearest garment distance. Excludes hair/bare body/swept collision.'}
name='baseline_fit.json' if baseline else 'equipment_fit_800.json' if '--bake' in sys.argv else 'fit_quick.json' if '--quick' in sys.argv else 'equipment_fit.json'
out['scope']+=' Uses signed 64-bit indices across all 68,287 transformed-outfit vertices.'
(R/name).write_text(json.dumps(out,indent=2),encoding='utf-8');print('V4_FIT_DONE',out['pose_count'],out['poses_with_crossings'],maximum,flush=True)
