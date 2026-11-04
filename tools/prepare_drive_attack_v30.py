"""Minimal immutable review project from current character presentation inputs."""
from pathlib import Path
import re,shutil,json,hashlib
ROOT=Path(__file__).resolve().parents[1];GAME=ROOT/'game';OUT=ROOT/'reports/drive_attack_v30'
SNAP=OUT/'project_snapshot';SNAP.mkdir(parents=True,exist_ok=True)
(SNAP/'.gitignore').write_text('*\n!.gitignore\n',encoding='utf-8')
files={};seen=set()
def copy(path):
 rel=path.relative_to(GAME).as_posix();dest=SNAP/rel;dest.parent.mkdir(parents=True,exist_ok=True)
 if path.suffix=='.import' and dest.exists() and '\npath=' not in path.read_text(encoding='utf-8-sig'):
  files[rel]=hashlib.sha256(path.read_bytes()).hexdigest();return
 shutil.copy2(path,dest);files[rel]=hashlib.sha256(path.read_bytes()).hexdigest()
def script(path):
 if path in seen:return
 seen.add(path);copy(path)
 for rel in re.findall(r'"res://([^"\n]+)"',path.read_text(encoding='utf-8')):
  p=GAME/rel
  if p.is_file() and p.resolve().is_relative_to(GAME.resolve()):
   if p.suffix=='.gd':script(p)
   else:copy(p)
script(GAME/'scripts/player_visual.gd');script(GAME/'tests/review_drive_attack_v30.gd')
for name in ('run_arm_v21','model_refinement_v28','hand_rebuild_v29','transformation_v25','transformation_v26','transformation_v27','spring_jump_v24','drive_attack_v30'):
 for p in (GAME/'assets/characters/player'/name).rglob('*'):
  if p.is_file() and p.suffix not in ('.uid',):copy(p)
for p in (GAME/'assets/weapons/staff_material_v3').rglob('*'):
 if p.is_file():copy(p)
# The reference is not a distributable source animation: it is the adapted rig's poses.
shutil.copy2(OUT/'pose_reference.json',SNAP/'pose_reference.json')
review=SNAP/'tests/review_drive_attack_v30.gd'
review.write_text(review.read_text(encoding='utf-8').replace('res://../reports/drive_attack_v30/pose_reference.json','res://pose_reference.json'),encoding='utf-8')
(SNAP/'project.godot').write_text('''config_version=5
[application]
config/name="Witch · Drive Motion Review v30"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''',encoding='utf-8')
(OUT/'review_project_inputs.json').write_text(json.dumps(files,indent=2),encoding='utf-8')
print('DRIVE_REVIEW_PROJECT',len(files))
