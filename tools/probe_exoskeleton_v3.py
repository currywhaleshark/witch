"""Record task baseline and inspect existing limb twist compatibility."""
from pathlib import Path
import json,hashlib,numpy as np
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v3'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=list((ROOT/'game/scripts').glob('*.gd'))+[ROOT/'docs/03_skills.md']
paths+=[p for directory in ['assets/equipment/exoskeleton_v2','game/assets/characters/player'] for p in (ROOT/directory).rglob('*') if p.is_file() and p.suffix in ['.glb','.blend','.json']]
baseline={p.relative_to(ROOT).as_posix():sha(p) for p in paths}
if not (R/'baseline.json').exists():(R/'baseline.json').write_text(json.dumps(baseline,indent=2),encoding='utf-8')
rest={n:np.array(m) for n,m in json.loads((ROOT/'reports/drive_tree_v1/rest_frames.json').read_text()).items()}
records=json.loads((ROOT/'reports/drive_tree_v1/review/poses.json').read_text())
out={}
for side in ['L','R']:
 rows=[]
 for up in ['', '.001','.002']:
  for fo in ['', '.001','.002']:
   a='DEF-upper_arm.'+side+up;b='DEF-forearm.'+side+fo
   diff=[]
   for p in records[:104]:
    A=np.array(p['bones'][a])@np.linalg.inv(rest[a]);B=np.array(p['bones'][b])@np.linalg.inv(rest[b])
    diff.append(A[:3,:3]-B[:3,:3])
   D=np.concatenate(diff);_,s,v=np.linalg.svd(D);axis=v[-1]
   if axis[0]*(1 if side=='L' else -1)<0:axis=-axis
   rows.append({'upper':a,'forearm':b,'rms_for_12cm_offset':float(s[-1]/np.sqrt(len(diff))*.12),'axis':axis.tolist()})
 out[side]=sorted(rows,key=lambda x:x['rms_for_12cm_offset'])
(R/'hinge_probe.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps({k:v[:3] for k,v in out.items()},indent=2))
