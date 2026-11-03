from pathlib import Path
import json,sys,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from exoskeleton_v3_geometry import read,garment,skin
R=ROOT/'reports/exoskeleton_v4';B=json.loads((ROOT/'reports/exoskeleton_v3/body_rest.json').read_text());out={}
for form,rel in [('civilian','model_refinement_v28/outfit_civilian_v28.glb'),('transformed','transformation_v25/outfit_transformed_v4.glb')]:
 path=ROOT/'game/assets/characters/player'/rel;parts=garment(path);d,_=read(path);names=[n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n for _ in d['meshes'][n['mesh']]['primitives']];report={}
 for n,p in zip(names,parts):
  v,f=skin([p],B);sections={}
  if any(x in n.lower() for x in ['socks','stockings','boots','cape','sleeve','cardigan']):
   for h in [.18,.22,.26,.4,.43,1.2,1.28,1.32]:
    sub=v[(abs(v[:,1]-h)<.012)&(v[:,0]>.03)]
    if len(sub):sections[str(h)]={'min':sub.min(axis=0).tolist(),'max':sub.max(axis=0).tolist(),'samples':len(sub)}
   report[n]=sections
 out[form]=report
(R/'garment_surfaces.json').write_text(json.dumps(out,indent=2));print('V4_SURFACES',out,flush=True)
