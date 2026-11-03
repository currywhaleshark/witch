"""Connect the baked runtime maps and arrange an editable eight-asset review scene."""
import bpy
import json
from mathutils import Vector

ROOT = 'C:/Users/yurib/Documents/New project/witch'
S = ROOT + '/assets/weapons/drive_material_v3'
IDS = ['guillotine', 'guillotine_saw', 'guillotine_lock', 'restraint_winch',
       'hydraulic_press', 'compound_executor', 'shock_frame', 'broad_cutter']


def material(glow):
    name = 'M_DriveV3_Glow' if glow else 'M_DriveV3_Surface'
    found = bpy.data.materials.get(name)
    if found: return found
    mat = bpy.data.materials.new(name)
    p = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for key in ['color', 'normal', 'orm'] + (['emission'] if glow else []):
        im = bpy.data.images.load(S + '/textures/drive_v3_' + key + '.png', check_existing=True)
        im.colorspace_settings.name = 'sRGB' if key in ['color', 'emission'] else 'Non-Color'
        im.pack()
        t = nodes.new('ShaderNodeTexImage')
        t.image = im
        t.label = key
        if key == 'color': links.new(t.outputs['Color'], p.inputs['Base Color'])
        elif key == 'normal':
            n = nodes.new('ShaderNodeNormalMap')
            n.uv_map = 'DriveTrim'
            links.new(t.outputs['Color'], n.inputs['Color'])
            links.new(n.outputs['Normal'], p.inputs['Normal'])
        elif key == 'emission':
            links.new(t.outputs['Color'], p.inputs['Emission Color'])
            p.inputs['Emission Strength'].default_value = 1.
        else:
            n = nodes.new('ShaderNodeSeparateColor')
            n.mode = 'RGB'
            links.new(t.outputs['Color'], n.inputs['Color'])
            links.new(n.outputs['Green'], p.inputs['Roughness'])
            links.new(n.outputs['Blue'], p.inputs['Metallic'])
            group = bpy.data.node_groups.get('glTF Material Output')
            if group is None:
                group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
                group.interface.new_socket(name='Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
            n = nodes.new('ShaderNodeGroup')
            n.node_tree = group
            split = next(n for n in nodes if n.type == 'SEPARATE_COLOR')
            links.new(split.outputs['Red'], n.inputs['Occlusion'])
    return mat


def finish(save=True):
    mats = {False: material(False), True: material(True)}
    for asset in IDS:
        scene = bpy.data.scenes['DriveMaterialV3_' + asset]
        info = json.loads(scene['manifest_json'])
        info['materials'] = ['M_DriveV3_Surface', 'M_DriveV3_Glow']
        info['texture_set'] = 'drive_material_v3 shared trim'
        scene['manifest_json'] = json.dumps(info)
        scene.render.engine = 'BLENDER_EEVEE'
        scene.view_settings.view_transform = 'Khronos PBR Neutral'
        for ob in scene.objects:
            if ob.type != 'MESH': continue
            ob.data.materials.clear()
            ob.data.materials.append(mats[ob.get('surface_key') == 'core'])
    review = bpy.data.scenes.get('DriveMaterialV3_Review')
    if review is None:
        review = bpy.data.scenes.new('DriveMaterialV3_Review')
        review.unit_settings.system = 'METRIC'
        review.unit_settings.scale_length = 1.
        review.render.engine = 'BLENDER_EEVEE'
        review.view_settings.view_transform = 'Khronos PBR Neutral'
        for i, asset in enumerate(IDS):
            offset = Vector(((i % 4) * 3.6, (i // 4) * 3.8, 0))
            for original in bpy.data.scenes['DriveMaterialV3_' + asset].objects:
                if original.type != 'MESH': continue
                ob = original.copy()
                ob.name = 'DM3_Review_' + original.name
                ob.parent = None
                ob.matrix_basis = original.matrix_basis.copy()
                ob.location += offset
                review.collection.objects.link(ob)
    bpy.context.window.scene = review
    bpy.context.view_layer.update()
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.shading.type = 'MATERIAL'
            area.spaces.active.overlay.show_overlays = False
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=S + '/drive_material_v3.blend')
    print(json.dumps({'assets': len(IDS), 'parts': len(review.objects), 'runtime_materials': [m.name for m in mats.values()], 'saved': save}))


finish(save=True)
