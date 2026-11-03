"""Record current inputs, preservation, final checks and review artifacts."""
from pathlib import Path
import json,hashlib,datetime,re
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v3';S=ROOT/'assets/equipment/exoskeleton_v3'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
reports=['asset_qa','art_test','bake_test','continuity','bake_preview','saved_preview','preservation','texture_preservation','equipment_fit']
results={name:read(R/(name+'.json')) for name in reports}
for name in ['asset_qa','art_test','bake_test','continuity','bake_preview','saved_preview','preservation']:assert results[name]['passed'],name
assert results['texture_preservation']['original_images_byte_identical']
baseline=read(R/'baseline.json');assert all((ROOT/p).is_file() and sha(ROOT/p)==h for p,h in baseline.items())
capture=read(R/'review/capture.json');assert capture['passed'] and capture['captures']==1572 and not capture['probe']
ledger={}
for p in sorted((R/'review').rglob('*.jpg')):ledger[str(p.relative_to(ROOT)).replace('\\','/')]=sha(p)
assert len(ledger)==1572
for p in sorted((R/'inspection').glob('*.png')):ledger[str(p.relative_to(ROOT)).replace('\\','/')]=sha(p)
(R/'capture_hashes.json').write_text(json.dumps(ledger,indent=2),encoding='utf-8')
paths=set(ROOT/p for p in baseline)
paths.update(p for p in S.rglob('*') if p.is_file() and not p.name.endswith('.blend1'))
paths.update(p for p in (ROOT/'game/assets/equipment/exoskeleton_v3').rglob('*') if p.is_file())
paths.update(p for p in (ROOT/'tools').glob('*exoskeleton_v3*') if p.is_file())
paths.update([ROOT/'game/tests/exoskeleton_v3_art.gd',ROOT/'game/tests/exoskeleton_v3_continuity.gd',ROOT/'game/tests/helpers/exoskeleton_v3.gd',ROOT/'game/tests/review_exoskeleton_v3.gd'])
paths.update([R/(name+'.json') for name in reports]);paths.update([R/'poses.json',R/'bake_poses.json',R/'body_rest.json',R/'hair_rest.json',R/'review.html',R/'review/capture.json',R/'capture_hashes.json'])
hashes={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in sorted(paths)}
status={'date':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),'status':'separated, fitted and rigged review candidate; garment clearance pending; prepared asset only',
 'source':'assets/equipment/exoskeleton_v3/exoskeleton_v3_animated.blend','runtime':'game/assets/equipment/exoskeleton_v3/exoskeleton_v3.glb',
 'geometry':{'rigid_meshes':33,'auxiliary_bones':34,'triangles':79242,'source_faces_preserved':78474,'new_connector_triangles':768,'max_influences':1,'materials':3,'original_2k_images_byte_identical':3},
 'validation':{'rig_checks':results['art_test']['checks'],'rig_poses':results['art_test']['poses'],'bake_checks':results['bake_test']['checks'],'bake_poses':results['bake_test']['poses'],'continuity_checks':results['continuity']['checks'],'continuity_poses':1928,'saved_preview_poses':results['saved_preview']['poses'],'gpu_captures':capture['captures'],'protected_files_unchanged':len(baseline)},
 'contact_audit':{'passed':False,'poses_with_garment_crossings':results['equipment_fit']['poses_with_crossings'],'sampled_poses':results['equipment_fit']['pose_count'],'scope':results['equipment_fit']['scope']},
 'qa_adjudications':['Original UV/normal seam duplicates and narrow cut/open boundaries retained with source texture lineage.','Original hidden back-to-back shoulder face pair retained.','Plain-metal connector UV stacking is deliberate and not suitable for unique texture baking.','Separate shin groups and equipment ground offsets are intentional for a wearable rig.'],
 'limits':['Cuff/sleeve crossings remain at idle/run; large cross-body attack/cast poses retain shoulder/cape intersections.','No new active skill, assembly effect, customization UI, or edits to existing game scripts.','No hair/bare-body/swept/inter-part/ground collision or arbitrary-pose clearance guarantee.','No final retopology, LOD, performance budget or user art approval.','GPU review uses authored clip time, jump pose only, anchored hair and studio inspection cameras.','Blender thumbnail, Godot shader-cache/editor-settings and Tripo shutdown warnings are environment diagnostics; outputs were separately verified.'],
 'files_sha256':hashes}
(R/'delivery_manifest.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf-8')
html=(R/'review.html').read_text(encoding='utf-8');missing=[]
for target in re.findall(r'(?:src|href)="([^"#]+)"',html):
 if '://' in target:continue
 if not (R/target).exists():missing.append(target)
assert not missing,missing
print('EXO_V3_DELIVERY',len(hashes),'hashed files',len(ledger),'review images','preserved',len(baseline),'contact-pending',status['contact_audit']['poses_with_garment_crossings'])
