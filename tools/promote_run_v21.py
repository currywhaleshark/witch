"""Promote the user-selected v21 family without replacing concurrent game work.

The reviewed files are copied only when their current inputs still match the
recorded comparison baseline. Combat rules, scene, HUD and appearance values
are recorded for preservation and are never overwritten by this migration.
"""
from pathlib import Path
import json,hashlib,shutil

ROOT=Path(__file__).resolve().parents[1]
REVIEW=ROOT/'reports/run_arm_v21'
OUT=REVIEW/'integration';OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/run_arm_v21'
GAME=ROOT/'game'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))

delivery=read(REVIEW/'delivery_manifest.json')
assert delivery['passed'] and all(sha(ROOT/n)==h for n,h in delivery['files'].items())
approved=read(REVIEW/'review_project_sources.json')['game_files']
changed=['scripts/player_visual.gd','tests/player_visual.gd','tests/player_motion_v18.gd']
assert all(sha(GAME/n)==approved[n] for n in changed), 'Review concurrent edits before applying this migration'
protected={p.relative_to(ROOT).as_posix():sha(p) for p in GAME.rglob('*') if p.is_file() and '.godot' not in p.parts and p.relative_to(GAME).as_posix() not in changed}
appearance=ROOT/'assets/characters/player/scg/config/appearance.default.json'
protected[appearance.relative_to(ROOT).as_posix()]=sha(appearance)
before={n:sha(GAME/n) for n in changed}
for n in changed:
    backup=OUT/'before'/n;backup.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(GAME/n,backup)
    shutil.copy2(REVIEW/'project_snapshot'/n,GAME/n)

controller=GAME/'scripts/player_visual.gd';text=controller.read_text(encoding='utf-8')
text=text.replace('# Authored impact/release: attack frame13/25, cast frame17/33 at 24fps.','# Authored release: swing 25/49, thrust 13/25, cast 17/33; normalized 0.5.')
text=text.replace("# v17 two-hand adaptation retains the selected compact run's measured stride.","# v21 arm correction retains the selected compact run's measured stride.")
start=text.index('static func attack_grip_slide(');end=text.index('func _sample_staff_slide(',start)
text=text[:start]+text[end:]
text=text.replace('\t_staff_slide_tracks = motion_contract["staff_slide_tracks"]','''\tif not motion_contract is Dictionary or not motion_contract.get("staff_slide_tracks") is Dictionary:
\t\treturn _fail("missing_staff_slide_contract")
\t_staff_slide_tracks = motion_contract["staff_slide_tracks"]
\tfor clip in CLIPS.values():
\t\tvar slide_track = _staff_slide_tracks.get(clip)
\t\tif not slide_track is Array or slide_track.size() < 2:
\t\t\treturn _fail("missing_staff_slide_track: " + clip)''')
controller.write_text(text,encoding='utf-8')
test=GAME/'tests/player_visual.gd';text=test.read_text(encoding='utf-8').replace('after the v18 assets are imported','after the selected character assets are imported').replace('../reports/combat_motion_v18/gameplay','../reports/run_arm_v21/integration/gameplay').replace('v18 character assets load successfully','selected v21 character assets load successfully')
test.write_text(text,encoding='utf-8')
test=GAME/'tests/player_motion_v18.gd';text=test.read_text(encoding='utf-8').replace('v18 assets load','selected character assets load')
test.write_text(text,encoding='utf-8')

parts=GAME/'assets/characters/player/run_arm_v21';parts.mkdir(parents=True,exist_ok=True)
exports=ROOT/'assets/characters/player/3d/exports/run_arm_v21'
for stem in ['body_standard','hair_semilong','eyes_neutral','outfit_civilian']:
    shutil.copy2(exports/(stem+'_v21.glb'),parts/(stem+'_v21.glb'))
contract=read(SOURCE/'runtime_contract.json')
contract.update(candidate_status='User selected and promoted to the main combat game on 2026-10-27',
    source_contract_sha256=sha(SOURCE/'runtime_contract.json'),
    game_integration_report='reports/run_arm_v21/integration/delivery_manifest.json')
(parts/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')

(OUT/'promotion_baseline.json').write_text(json.dumps({'approved_source_sha256':delivery['source_sha256'],'approved_delivery_files':delivery['files'],'protected_game_files':protected,'changed_game_files_before':before,'runtime_parts':{p.relative_to(ROOT).as_posix():sha(p) for p in parts.iterdir() if p.is_file() and p.suffix in ('.glb','.json')},'scope':'User-approved motion family promotion only. Arena, rules, HUD, audio, scene and saved appearance retained.'},indent=2),encoding='utf-8')
assert all(sha(ROOT/n)==h for n,h in protected.items())
print('RUN_V21_PROMOTED',len(protected),'protected files',contract['runtime_default_clips'])
