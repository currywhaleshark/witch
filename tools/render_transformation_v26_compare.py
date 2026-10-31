"""Render v25 and v26 entry clips from the same cameras for a before/after review.

Run: blender -b transformation_v26.blend -P tools/render_transformation_v26_compare.py -- <out_dir>
The staff is shown at its floating frame from the assembly start until the
1.40s grasp, then follows the right hand (the runtime's two phases). The civilian
outfit stays on; the 2.40s swap is labelled in the composite, not rendered.
"""
import bpy, math, sys, json
from pathlib import Path
from mathutils import Vector, Matrix

OUT = Path(sys.argv[sys.argv.index('--') + 1]); OUT.mkdir(parents=True, exist_ok=True)
CLIPS = ['combat_transform_entry_v25', 'combat_transform_entry_v26']
FRAMES = list(range(1, 74, 2))
VIEWS = {'game': (25, 28, 1.95), 'side': (90, 6, 1.95)}
sc = bpy.context.scene
rig = bpy.data.objects['PlayerRig_v7']; rig.data.pose_position = 'POSE'
prop = bpy.data.objects['PROP_StaffPreview_v18']
floating = prop.copy(); floating.data = prop.data; floating.name = 'StaffFloating'; floating.parent = None
floating.constraints.clear(); floating.animation_data_clear(); sc.collection.objects.link(floating)
sc.render.engine = 'BLENDER_EEVEE'; sc.view_settings.view_transform = 'Standard'; sc.view_settings.exposure = -.8
sc.render.resolution_x = 560; sc.render.resolution_y = 720
world = sc.world
next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND').inputs[0].default_value = (.20, .27, .27, 1)
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
floor = bpy.context.active_object; fm = bpy.data.materials.new('floor'); fm.use_nodes = True
next(n for n in fm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color'].default_value = (.33, .45, .43, 1)
floor.data.materials.append(fm)
cd = bpy.data.cameras.new('cmp'); cd.type = 'ORTHO'
cam = bpy.data.objects.new('cmp', cd); sc.collection.objects.link(cam); sc.camera = cam
for clip in CLIPS:
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    if act.slots:
        rig.animation_data.action_slot = act.slots[0]
    sc.frame_set(35)                       # hand at the floating frame (1.4167s)
    bpy.context.view_layer.update()
    floating.matrix_world = prop.matrix_world.copy()
    for view, (yaw, elev, scale) in VIEWS.items():
        cd.ortho_scale = scale
        a, e = math.radians(yaw), math.radians(elev); t = Vector((0, 0, .92))
        cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * 5
        cam.rotation_euler = (t - cam.location).to_track_quat('-Z', 'Y').to_euler()
        for f in FRAMES:
            sec = (f - 1) / 24
            sc.frame_set(f)
            floating.hide_render = not (.30 <= sec < 1.40)
            prop.hide_render = sec < 1.40
            sc.render.filepath = str(OUT / f'{clip}_{view}_{f:03}.png')
            bpy.ops.render.render(write_still=True)
(OUT / 'frames.json').write_text(json.dumps({'clips': CLIPS, 'frames': FRAMES, 'views': list(VIEWS)}), encoding='utf-8')
print('COMPARE_RENDER_DONE', flush=True)
