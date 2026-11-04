"""Verify the final saved derivative against the initial v29 protected data."""
from pathlib import Path
import bpy,sys,json,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/drive_attack_v30'
source=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v30/drive_attack_v30.blend'
bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
before=json.loads((OUT/'protected_baseline.json').read_text());after=check.snapshot('PlayerRig_v7',set())
assert before['meshes']==after['meshes']
assert before['rig']==after['rig']
assert all(after['actions'][n]==digest for n,digest in before['actions'].items())
result={'passed':True,'protected_meshes':len(before['meshes']),'protected_actions':len(before['actions']),'rest_bones':len(before['rig']),
 'new_actions':sorted(set(after['actions'])-set(before['actions'])),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
(OUT/'final_preservation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('DRIVE_FINAL_PRESERVATION',result,flush=True)
