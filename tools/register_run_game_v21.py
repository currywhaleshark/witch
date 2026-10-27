"""Register the user-approved v21 family after actual main-game checks pass."""
from pathlib import Path
import hashlib,json,re,subprocess,sys,os
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/run_arm_v21/integration'
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/run_arm_v21'
PARTS=ROOT/'game/assets/characters/player/run_arm_v21'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
baseline=read(OUT/'promotion_baseline.json')
assert all(sha(ROOT/n)==h for n,h in baseline['protected_game_files'].items())
assert all(sha(ROOT/n)==h for n,h in baseline['approved_delivery_files'].items())
for name in ['godot_pose_parity.json','runtime_hand_validation.json','gameplay/player_visual_validation.json','variants/variant_validation.json']:
    assert read(OUT/name)['passed'],name
contract=read(PARTS/'runtime_contract.json');original=read(SOURCE/'runtime_contract.json')
mapping=contract['runtime_default_clips']
assert mapping==original['runtime_default_clips'] and contract['staff_slide_tracks']==original['staff_slide_tracks']
source_hash=sha(SOURCE/'run_arm_v21.blend')
assert source_hash==baseline['approved_source_sha256']==contract['source_blend_sha256']

registry_path=ROOT/'assets/characters/player/3d/config/modular_character.spec.json'
display_path=ROOT/'assets/characters/player/3d/config/display_review.spec.json'
for p in [registry_path,display_path]:
    backup=OUT/'before'/p.name
    if not backup.exists():backup.write_bytes(p.read_bytes())
registry=read(registry_path)
registry['status']='combat_prototype_v21_user_selected_right_hand_motion_family'
registry['rig']['asset']='exports/run_arm_v21/body_standard_v21.glb'
for group,part,stem in [('bodies','standard_v1','body_standard'),('hair','semilong_v1','hair_semilong'),('eyes','neutral_v1','eyes_neutral'),('outfits','civilian_v1','outfit_civilian')]:
    filename=stem+'_v21.glb';export=ROOT/'assets/characters/player/3d/exports/run_arm_v21'/filename
    assert sha(export)==sha(PARTS/filename)
    registry[group][part].update(asset='exports/run_arm_v21/'+filename,sha256=sha(export),runtime_asset='res://assets/characters/player/run_arm_v21/'+filename)
v=registry['validation']
v.update(scope='v21_user_selected_main_game_7_current_motions_8_exported_clips_215_GPU_poses_actual_gameplay_and_variant_equivalence',
    report='reports/run_arm_v21/integration/gameplay/player_visual_validation.json',
    pose_report='reports/run_arm_v21/integration/godot_pose_parity.json',
    glb_report='reports/run_arm_v21/glb_validation.json',
    source_blend='source/middle_school_v1/run_arm_v21/run_arm_v21.blend',source_blend_sha256=source_hash,
    next_outfit='source/middle_school_v1/run_arm_v21/GAME_INTEGRATION.md',
    combat_clips=list(mapping.values()),comparison_clips=['combat_run_rh_v20'],
    hand_report='reports/run_arm_v21/integration/runtime_hand_validation.json',
    source_hand_reports=['reports/heavy_swing_v20/independent_validation.json','reports/run_arm_v21/independent_validation.json'],
    refinement_report='reports/run_arm_v21/independent_validation.json',
    variant_equivalence_report='reports/run_arm_v21/integration/variants/variant_validation.json',
    runtime_contract='game/assets/characters/player/run_arm_v21/runtime_contract.json',
    delivery_manifest='reports/run_arm_v21/integration/delivery_manifest.json',
    visual_approval='User accepted the v21 run correction and requested this motion family as the game default; final cloth contacts and balance remain separate.')
old_mapping={'trial_two_hand_idle_v16':mapping['idle'],'trial_two_hand_run_v17':mapping['run'],'trial_one_hand_cast_v17':mapping['cast'],'trial_two_hand_hit_v16':mapping['hit_react'],'combat_collapse_v18':mapping['collapse']}
for trial in v['external_motion_trials']:
    if trial['clip'] in old_mapping:
        trial['previous_clip']=trial['clip'];trial['clip']=old_mapping[trial['clip']]
        trial['status']='adapted_right_hand_motion_selected_for_current_prototype'
if not any(t['clip']==mapping['attack'] for t in v['external_motion_trials']):
    v['external_motion_trials'].append({'clip':mapping['attack'],'provider':'Adobe Mixamo','license':'Adobe Mixamo royalty-free use; not CC0','source_clip':'Heavy Weapon Swing','source_sha256':'2c657ce760a6622975a2fec34f689467f5ed6df1360da9a306c0e123103a85f0','default_selected':True,'status':'user_supplied_adjusted_motion_with_v20_right_hand_entry_correction','raw_source_policy':'local/gitignored original preserved'})
v['run_motion_approval']={'status':'selected_for_current_prototype','date':'2026-10-27','clip':mapping['run'],'scope':'User accepted corrected elbows/wrists and requested main-game promotion; original compact gait and cycle distance retained.'}
v['motion_approval']={'status':'user_selected_and_integrated','date':'2026-10-27','clips':mapping,'scope':'v21 run with six v20 right-handed motions promoted to the actual game at the user request.'}
write(registry_path,registry)
display=read(display_path)
display['game_integration'].update(configured_on='2026-10-27',runtime_asset_family='game/assets/characters/player/run_arm_v21/',
    runtime_validation='v21_main_game_GPU_parity_hand_order_gameplay_and_equal_attack_variants',validated_on='2026-10-27',source_sha256=source_hash,
    gameplay_report=v['report'],pose_parity_report=v['pose_report'],review='reports/run_arm_v21/review.html',delivery_manifest=v['delivery_manifest'],
    selected_run=mapping['run'],selected_motions=mapping,gameplay_checks_including_capture_validation=1287,failures=0,
    run_cycle_distance_m=contract['run_cycle_distance_m'])
write(display_path,display)
test=subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_character_appearance.py','-v'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',env={**os.environ,'PYTHONIOENCODING':'utf-8'})
(OUT/'appearance_tests.log').write_text(test.stdout+test.stderr,encoding='utf-8')
assert test.returncode==0,test.stdout+test.stderr
count=re.search(r'Ran (\d+) tests?',test.stdout+test.stderr);assert count
write(OUT/'appearance_validation.json',{'passed':True,'exit_code':test.returncode,'tests':int(count.group(1))})
print('V21_MAIN_GAME_REGISTERED',count.group(1),'appearance tests')
