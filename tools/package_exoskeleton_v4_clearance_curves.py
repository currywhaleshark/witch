"""Publish authored pose-corrective keys shared by both clothing forms."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4';S=ROOT/'assets/equipment/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4'
data=json.loads((R/'clearance_curve_fit.json').read_text());curves={}
assert len(data['rows'])==400,'Fitting pass is incomplete'
assert not any(r['crossings'] for r in data['rows']),'Unresolved fitted key'
for motion in list(dict.fromkeys(r['motion'] for r in data['rows'])):
 curves[motion]={}
 for side in ['L','R']:
  keys=[{'phase':r['phase'],'angle':r['angle'],'shift':r['shift']} for r in data['rows'] if r['motion']==motion and r['side']==side]
  assert len(keys)==25 and keys[0]['angle']==keys[-1]['angle']==0
  curves[motion][side]=keys
for p in [S/'clearance_curves.json',G/'clearance_curves.json']:p.write_text(json.dumps(curves,indent=2))
print('V4_CORRECTIVE_KEYS',sum(len(k) for sides in curves.values() for k in sides.values()))
