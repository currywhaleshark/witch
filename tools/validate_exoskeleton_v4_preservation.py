"""Current asset payload and task-baseline preservation, without importing Blender."""
from pathlib import Path
import json,struct,hashlib,numpy as np
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4';S=ROOT/'assets/equipment/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0];return json.loads(b[20:20+n]),b[28+n:]
def images(p):
 d,b=read(p);out={}
 for i in d.get('images',[]):
  v=d['bufferViews'][i['bufferView']];start=v.get('byteOffset',0);blob=b[start:start+v['byteLength']];out[i['name']]=hashlib.sha256(blob).hexdigest()
 return out
base=json.loads((R/'baseline.json').read_text());changed=[p for p,h in base.items() if not (ROOT/p).is_file() or sha(ROOT/p)!=h]
out={'checked':len(base),'changed':changed,'passed':not changed};(R/'preservation.json').write_text(json.dumps(out,indent=2));assert out['passed']
a=images(ROOT/'game/assets/equipment/exoskeleton_v3/exoskeleton_v3.glb');b=images(G/'exoskeleton_v4.glb');assert a==b
(R/'texture_preservation.json').write_text(json.dumps({'original_images_byte_identical':True,'images':b},indent=2))
copies={p.name:sha(p)==sha(G/p.name) for p in (S/'exports').glob('*.glb')};assert all(copies.values())
qa=json.loads((R/'asset_qa.json').read_text());assert qa['passed']
# UVs of new plain-metal connectors intentionally repeat a triangle.
# Retained textured faces are checked exactly against the immutable source in asset_qa.
assert qa['source_lineage']['max_uv_error']==0
new_d,new_b=read(G/'outfit_civilian_fit_v4.glb');old_d,old_b=read(ROOT/'game/assets/characters/player/model_refinement_v28/outfit_civilian_v28.glb')
assert new_d['nodes']==old_d['nodes'] and new_d['skins']==old_d['skins']
assert (G/'outfit_transformed_fit_v4.glb').read_bytes()==(ROOT/'game/assets/characters/player/transformation_v25/outfit_transformed_v4.glb').read_bytes()
result={'passed':True,'export_runtime_identical':copies,'body_outfit_nodes_and_skins_identical':True,'transformed_outfit_byte_identical':True,'retained_source_uv_exact':True,'original_images_byte_identical':True,'protected_files':len(base)}
(R/'package_validation.json').write_text(json.dumps(result,indent=2));print('V4_PRESERVATION',result)
