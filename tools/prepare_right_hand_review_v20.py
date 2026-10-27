"""Disposable game copy with right-dominant actions and per-clip staff curves."""
from pathlib import Path
import shutil,json,hashlib
ROOT=Path(__file__).resolve().parents[1];REPORT=ROOT/'reports/heavy_swing_v20';OUT=REPORT/'project_snapshot';SOURCE=ROOT/'game'
OUT.mkdir(parents=True,exist_ok=True);files={}
for path in SOURCE.rglob('*'):
    if not path.is_file():continue
    rel=path.relative_to(SOURCE)
    if any(p in ('.godot','.git') for p in rel.parts) or rel.parts[:3]==('assets','characters','player'):continue
    target=OUT/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target);files[rel.as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
exports=ROOT/'assets/characters/player/3d/exports/heavy_swing_v20';parts=OUT/'assets/characters/player/heavy_swing_v20';parts.mkdir(parents=True,exist_ok=True)
for stem in ['body_standard','hair_semilong','eyes_neutral','outfit_civilian']:shutil.copy2(exports/(stem+'_v20.glb'),parts/(stem+'_v20.glb'))
shutil.copy2(ROOT/'assets/characters/player/3d/exports/transformed_fit_v4/outfit_transformed_v4.glb',OUT/'assets/outfit_transformed_v4.glb')
contract_path=ROOT/'assets/characters/player/3d/source/middle_school_v1/heavy_swing_v20/runtime_contract.json';contract=json.loads(contract_path.read_text());shutil.copy2(contract_path,parts/'runtime_contract.json')
controller=OUT/'scripts/player_visual.gd';text=controller.read_text(encoding='utf-8').replace('combat_motion_v18/','heavy_swing_v20/').replace('_v18.glb','_v20.glb')
old={'idle':'trial_two_hand_idle_v16','run':'trial_two_hand_run_v17','attack':'combat_swing_v18','attack_thrust':'combat_thrust_v18','cast':'trial_one_hand_cast_v17','hit_react':'trial_two_hand_hit_v16','collapse':'combat_collapse_v18'}
for kind,name in old.items():text=text.replace('"'+name+'"','"'+contract['runtime_default_clips'][kind]+'"')
text=text.replace('var staff_slide := 0.0','var staff_slide := 0.0\nvar _staff_slide_tracks: Dictionary = {}')
text=text.replace('\t_build_staff()','\tvar motion_contract = JSON.parse_string(FileAccess.get_file_as_string(ASSET_DIR + "runtime_contract.json"))\n\t_staff_slide_tracks = motion_contract["staff_slide_tracks"]\n\t_build_staff()')
text=text.replace('staff_slide = attack_grip_slide(clip_time / maxf(clip_length, 0.000001)) if kind == "attack" else 0.0','staff_slide = _sample_staff_slide(_clip.get_file(), clip_time / maxf(clip_length, 0.000001))')
text=text.replace('lerpf(_collapse_grip_from, 0.0, clampf','lerpf(_collapse_grip_from, staff_slide, clampf')
function='''func _sample_staff_slide(clip: String, phase: float) -> float:
    var values: Array = _staff_slide_tracks.get(clip, [0.0])
    var x := clampf(phase, 0.0, 1.0) * (values.size() - 1)
    var lo := int(floorf(x))
    return lerpf(float(values[lo]), float(values[mini(lo + 1, values.size() - 1)]), x - lo)

'''.replace('    ','\t')
text=text.replace('func _sample(kind: String, time: float) -> void:',function+'func _sample(kind: String, time: float) -> void:');controller.write_text(text,encoding='utf-8')
test=OUT/'tests/player_motion_v18.gd';text=test.read_text(encoding='utf-8').replace('for time in [0.0, 1.0]:','for time in [0.0, visual()._length("attack")]:').replace('float(state().staff_slide_m) - 0.28','float(state().staff_slide_m) - 0.16').replace('is_zero_approx(float(state().staff_slide_m))','absf(float(state().staff_slide_m) + 0.26) < 0.00001')
test.write_text(text,encoding='utf-8')
# Current full presentation regression with renamed clips and 2s authored run.
test=OUT/'tests/player_visual.gd';text=test.read_text(encoding='utf-8')
for kind,name in old.items():text=text.replace(name,contract['runtime_default_clips'][kind])
text=text.replace('const EXPECTED_RUN_LENGTH := 1.0','const EXPECTED_RUN_LENGTH := 4.0').replace('retains its authored one-second cycle','retains its denser authoring and measured cycle distance')
test.write_text(text,encoding='utf-8')
(REPORT/'review_project_sources.json').write_text(json.dumps({'game_files':files,'scope':'Read-only main game copy; all modifications are candidate asset mappings, staff presentation curves, and matching test expectations in this snapshot.'},indent=2),encoding='utf-8')
print('RIGHT_HAND_V20_PROJECT_READY')
