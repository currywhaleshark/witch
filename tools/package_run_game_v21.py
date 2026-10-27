"""Finalize hashes and evidence for the actual game promotion, without replaying it."""
from pathlib import Path
import json,hashlib,re
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/run_arm_v21/integration'
PARTS=ROOT/'game/assets/characters/player/run_arm_v21'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
baseline=read(OUT/'promotion_baseline.json')
assert all(sha(ROOT/n)==h for n,h in baseline['protected_game_files'].items())
assert all(sha(ROOT/n)==h for n,h in baseline['approved_delivery_files'].items())
report_names=['godot_pose_parity.json','runtime_hand_validation.json','gameplay/player_visual_validation.json','variants/variant_validation.json','appearance_validation.json']
reports={n:read(OUT/n) for n in report_names};assert all(r['passed'] for r in reports.values())
execution={phase:read(OUT/phase/'execution.json') for phase in ['import_initial','import_settings','import_final','parity','hands','gameplay','variants']}
assert all(r['engine_exit_code']==0 and r['completion_marker'] for r in execution.values())
contract=read(PARTS/'runtime_contract.json');mapping=contract['runtime_default_clips']
controller=(ROOT/'game/scripts/player_visual.gd').read_text(encoding='utf-8')
block=re.search(r'const CLIPS := \{([\s\S]*?)\}',controller).group(1)
assert dict(re.findall(r'"([^\"]+)": "([^\"]+)"',block))==mapping
assert 'static func attack_grip_slide(' not in controller
registry=read(ROOT/'assets/characters/player/3d/config/modular_character.spec.json')
display=read(ROOT/'assets/characters/player/3d/config/display_review.spec.json')
assert registry['validation']['motion_approval']['clips']==display['game_integration']['selected_motions']==mapping
assert display['camera']['relative_zoom']==1.75
assert registry['outfits']['transformed_v1']['asset'] is None
gameplay=reports['gameplay/player_visual_validation.json'];poses=reports['godot_pose_parity.json']['pose_checks']
files=[ROOT/'game'/n for n in baseline['changed_game_files_before']]
files += [p for p in PARTS.iterdir() if p.is_file()]
files += [ROOT/n for n in ['assets/characters/player/3d/config/modular_character.spec.json','assets/characters/player/3d/config/display_review.spec.json','docs/godot_prototype.md','docs/09_character_art_pipeline.md','assets/characters/player/3d/source/README.md','assets/characters/player/3d/source/middle_school_v1/run_arm_v21/GAME_INTEGRATION.md','AGENTS.md']]
files += [OUT/n for n in report_names]+[OUT/'promotion_baseline.json']
files += [ROOT/'tools'/n for n in ['promote_run_v21.py','validate_run_game_v21.ps1','register_run_game_v21.py','package_run_game_v21.py']]
manifest={'passed':True,'user_selected':True,'main_game_promoted':True,'selected_on':'2026-10-27','source_sha256':baseline['approved_source_sha256'],
    'runtime_asset_family':'game/assets/characters/player/run_arm_v21/','runtime_default_clips':mapping,
    'approved_art_files_preserved':len(baseline['approved_delivery_files']),'existing_game_and_appearance_files_preserved':len(baseline['protected_game_files']),
    'gpu_clips':len(poses),'gpu_poses':sum(p['samples'] for p in poses),
    'runtime_hand_samples':reports['runtime_hand_validation.json']['samples'],'gameplay_checks':len(gameplay['checks']),'gameplay_captures':len(gameplay['captures']),
    'variant_checks':len(reports['variants/variant_validation.json']['checks']),'appearance_tests':reports['appearance_validation.json']['tests'],
    'run_playback':gameplay['observations']['run_playback_contract'],'execution':execution,
    'files':{p.relative_to(ROOT).as_posix():sha(p) for p in files},
    'scope':'Actual main-game promotion requested by user. Motion/attachment only; current combat, saved appearance, approved authoring assets and historical review preserved. No arbitrary-pose cloth clearance or final balance/budget claim.'}
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('V21_GAME_DELIVERED',manifest['gameplay_checks'],manifest['variant_checks'],manifest['appearance_tests'],len(files))
