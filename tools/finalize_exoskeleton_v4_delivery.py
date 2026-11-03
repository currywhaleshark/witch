"""Final current-input manifest for the isolated fitted equipment derivative."""
from pathlib import Path
import json,hashlib,datetime,re
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4';S=ROOT/'assets/equipment/exoskeleton_v4';G=ROOT/'game/assets/equipment/exoskeleton_v4'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
names=['asset_qa','outfit_qa','art_test','bake_test','continuity','bake_preview','saved_preview','preservation','texture_preservation','package_validation','equipment_fit','equipment_fit_800','baseline_fit','outfit_preservation','clearance_augmentation']
results={name:read(R/(name+'.json')) for name in names}
for name in ['asset_qa','outfit_qa','art_test','bake_test','continuity','bake_preview','saved_preview','preservation','package_validation']:assert results[name]['passed'],name
assert results['texture_preservation']['original_images_byte_identical']
assert results['equipment_fit']['pose_count']==400 and results['equipment_fit']['poses_with_crossings']==0
assert results['equipment_fit_800']['pose_count']==800 and results['equipment_fit_800']['poses_with_crossings']==0
assert results['baseline_fit']['poses_with_crossings']==297
assert results['outfit_preservation']['transformed']['file_byte_identical']
baseline=read(R/'baseline.json');assert all((ROOT/p).is_file() and sha(ROOT/p)==h for p,h in baseline.items())
capture=read(R/'review/capture.json');assert capture['passed'] and capture['captures']==1572 and not capture['probe']
ledger={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in sorted((R/'review').rglob('*.jpg'))};assert len(ledger)==1572
ledger.update({str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in sorted((R/'inspection').glob('*.png'))});assert len(ledger)==1577
(R/'capture_hashes.json').write_text(json.dumps(ledger,indent=2),encoding='utf-8')
curves=read(S/'clearance_curves.json');original=read(R/'clearance_curve_fit.json')['rows']
assert all({'phase':r['phase'],'angle':r['angle'],'shift':r['shift']} in curves[r['motion']][r['side']] for r in original)
counts={'parts':55,'bones':56,'triangles':79049,'retained_source_faces':73673,'archived_replaced_faces':4801,'new_connector_faces':5376,'max_equipment_influences':1,'materials':3,'original_images':3,'corrective_keys':sum(len(keys) for sides in curves.values() for keys in sides.values())}
production={'version':'exoskeleton_v4','status':'fitted review candidate','requested':'손목 소매랑 케이프 뚫리는 부분부터 더 손봐보자 그리고 다리쪽은 떠있으니 잘 붙여놓고','source':'assets/equipment/exoskeleton_v3/exoskeleton_v3.blend','source_lineage':'Tripo v2 derivative; live Blender MCP fittings and authored rigid mechanisms; no new Tripo generation','tooling':{'blender':'5.1.1','mcp_addon':'1.8 protocol 15','engine':'Godot 4.6.2'},'geometry':counts,'current_review':'reports/exoskeleton_v4/review.html','user_art_approval':False,'active_game_skill_integrated':False}
(S/'production.json').write_text(json.dumps(production,ensure_ascii=False,indent=2),encoding='utf-8')
paths={ROOT/p for p in baseline}
paths.update(p for p in S.rglob('*') if p.is_file() and not p.name.endswith('.blend1'))
paths.update(p for p in G.rglob('*') if p.is_file())
paths.update(p for p in (ROOT/'tools').glob('*exoskeleton_v4*') if p.is_file())
paths.update([ROOT/'game/tests/exoskeleton_v4_art.gd',ROOT/'game/tests/exoskeleton_v4_continuity.gd',ROOT/'game/tests/review_exoskeleton_v4.gd',ROOT/'game/tests/helpers/exoskeleton_v4.gd',ROOT/'game/tests/helpers/exoskeleton_v3.gd',ROOT/'game/tests/review_drive_tree_v1.gd'])
paths.update([R/(n+'.json') for n in names]);paths.update([R/'poses.json',R/'bake_poses.json',R/'body_rest.json',R/'hair_rest.json',R/'review.html',R/'review_script.js',R/'review/capture.json',R/'capture_hashes.json'])
hashes={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in sorted(paths)}
supports=results['equipment_fit_800']['calf_supports']
manifest={'date':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),'status':'fitted equipment review candidate; requested sampled garment clearance and calf mounting addressed','source':'assets/equipment/exoskeleton_v4/exoskeleton_v4_animated.blend','runtime_example':'game/tests/helpers/exoskeleton_v4.gd','geometry':counts,
 'validation':{'comparison_poses':400,'comparison_rig_checks':results['art_test']['checks'],'bake_poses':800,'bake_rig_checks':results['bake_test']['checks'],'continuity_poses':1928,'continuity_checks':results['continuity']['checks'],'saved_preview_poses':results['saved_preview']['poses'],'saved_preview_maximum_matrix_error':results['saved_preview']['maximum_matrix_error'],'gpu_captures':1572,'protected_files_unchanged':len(baseline),'equipment_source_reimport_qa_passed':True,'civilian_qa_no_added_errors':True},
 'contact_audit':{'comparison_crossing_poses':0,'comparison_pose_count':400,'dense_crossing_poses':0,'dense_pose_count':800,'remeasured_v3_crossing_poses':297,'remeasured_v3_pose_count':400,'calf_inner_surface_distance_range_m':[min(x['minimum_m'] for x in supports),max(x['maximum_m'] for x in supports)],'scope':results['equipment_fit_800']['scope'],'original_400_corrective_keys_preserved_after_augmentation':True},
 'qa_adjudications':['Equipment: original UV/normal seam duplicates, narrow cut boundaries and an original hidden shoulder mating face pair remain.','New plain-metal upper slides and cuffs have deliberate repeating triangle UVs; source-textured UVs match exactly.','Equipment groups are independently body-mounted; fitted calf mounts now contact their guards.','Civilian source and fitted copy report exactly the same inherited >4-influence, 11 coplanar-pair and small-island items; source weights and topology remain unchanged.','Transformed garment is byte-identical. Reference fitting spheres stay hidden in the saved Blender preview.','64-bit indices are used for garment and multi-form topology; the historical fitting-probe attempts are not validation evidence.'],
 'limits':['Prepared equipment/helper only; no active skill, assembly effect, loadout UI or game-rule change.','No arbitrary/new pose, blend, interruption, swept/inter-part/body/hair/ground collision or exact wrist-contact guarantee.','Current pose-specific correction keys must accompany the GLB and be sampled with the current motion name/phase.','No final retopology, LOD, performance budget or new user art approval.','GPU captures use existing clip times and studio inspection cameras; the jump is pose-only and hair uses its anchor preview.','Blender thumbnail, Godot shader-cache/editor-settings and Tripo shutdown diagnostics do not affect the independently verified saved outputs.'],
 'files_sha256':hashes}
(R/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
html=(R/'review.html').read_text(encoding='utf-8');missing=[]
for target in re.findall(r'(?:src|href)="([^"#]+)"',html):
 if '://' not in target and not (R/target).exists():missing.append(target)
assert not missing,missing
print('V4_DELIVERY',len(hashes),'files',len(ledger),'images','garment crossings 0/400 and 0/800','protected',len(baseline))
