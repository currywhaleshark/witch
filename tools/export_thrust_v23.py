"""Export the v23 thrust as a one-action GLB for the unchanged v21 runtime parts.

Background Blender. Only the rig and its smallest skinned mesh are selected: the
mesh is there so the glTF carries a skin, which makes Godot build the same
``PlayerRig_v7/Skeleton3D`` bone tracks as the v21 family. The game adds this
animation to the character's existing library; no v21 part is re-exported.
"""
import bpy, hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'assets/characters/player/3d/source/middle_school_v1/thrust_v23/thrust_v23.blend'
EXPORTS = ROOT/'assets/characters/player/3d/exports/thrust_v23'
GAME = ROOT/'game/assets/characters/player/run_arm_v21'
NAME = 'combat_thrust_rh_v23'
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rig = bpy.data.objects['PlayerRig_v7']
for track in rig.animation_data.nla_tracks:
    track.mute = True
action = bpy.data.actions[NAME]
rig.animation_data.action = action
rig.animation_data.action_slot = action.slots[0]
skinned = [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers)]
carrier = min(skinned, key=lambda o: len(o.data.vertices))
for obj in bpy.data.objects:
    obj.select_set(obj in (rig, carrier))
bpy.context.view_layer.objects.active = rig
bpy.context.scene.frame_start, bpy.context.scene.frame_end = int(action.frame_range[0]), int(action.frame_range[1])
EXPORTS.mkdir(parents=True, exist_ok=True)
target = EXPORTS/(NAME+'.glb')
bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True, export_animations=True,
    export_animation_mode='ACTIVE_ACTIONS', export_force_sampling=True, export_optimize_animation_size=False,
    export_anim_slide_to_zero=True, export_def_bones=False, export_skins=True, export_morph=False,
    export_materials='NONE', export_extras=False, export_image_format='NONE')
data = target.read_bytes()
(GAME/(NAME+'.glb')).write_bytes(data)
report = {'source_blend': SOURCE.relative_to(ROOT).as_posix(), 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'action': NAME, 'frames': [int(v) for v in action.frame_range], 'carrier_mesh': carrier.name,
    'export': target.relative_to(ROOT).as_posix(), 'game_copy': (GAME/(NAME+'.glb')).relative_to(ROOT).as_posix(),
    'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
(ROOT/'reports/thrust_v23/export.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('THRUST_V23_EXPORTED', report['sha256'], carrier.name, flush=True)
