"""Re-export saved rigid summons with their first key at t=0."""
import bpy,json,hashlib,shutil
from pathlib import Path
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/summons_v2'
for actor in ['automaton','turret']:
    bpy.ops.wm.open_mainfile(filepath=str(BASE/'authoring'/f'{actor}_v2.blend'))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.context.scene.objects:
        if o.type in ['MESH','ARMATURE']:o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    out=BASE/'exports'/f'{actor}_v2.glb'
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_anim_slide_to_zero=True,export_force_sampling=True,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_optimize_animation_size=False)
    shutil.copy2(out,ROOT/'game/assets/actors/summons_v2'/out.name)
    p=ROOT/'reports/summons_v2/build'/actor/'build.json';info=json.loads(p.read_text());info['sha256']=hashlib.sha256(out.read_bytes()).hexdigest();info['bytes']=out.stat().st_size;p.write_text(json.dumps(info,indent=2))
print('SUMMONS_V2_EXPORT_COMPLETE')
