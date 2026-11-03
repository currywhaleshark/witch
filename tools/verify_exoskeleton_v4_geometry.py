from pathlib import Path
import json,sys,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v4_geometry import read,frames,garment,skin
R=ROOT/'reports/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4';m=json.loads((G/'parts.json').read_text())
d,_=read(G/'exoskeleton_v4.glb');fs=frames(d);rests={n['name']:fs[i] for i,n in enumerate(d['nodes']) if n['name'].startswith('EXO-')}
parts=garment(G/'exoskeleton_v4.glb');names=[n['name'].removeprefix('ExoV4_') for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']]
row=next(r for r in json.loads((R/'poses.json').read_text()) if r['form']=='civilian' and r['motion']=='attack' and abs(r['phase']-.583333)<.001)
out={}
for role,part in zip(names,parts):
 v,f=skin([part],rests);v=np.column_stack([v,np.ones(len(v))]);rest=np.array(m['mechanism_rest_godot'][role]);posed=(v@(np.array(row['mechanism'][role])@np.linalg.inv(rest)).T)[:,:3]
 actual,_=skin([part],row['exo_bones']);out[role]=float(np.max(np.linalg.norm(actual-posed,axis=1)))
(R/'geometry_comparison.json').write_text(json.dumps(out,indent=2));print('GEOMETRY_COMPARISON',max(out.values()),out,flush=True)
