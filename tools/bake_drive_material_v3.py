"""Bake the live-authored trim shaders, verify source parity, and save a compact editable derivative."""
import bpy
import json
import hashlib
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'assets/weapons/drive_material_v3'
R = ROOT / 'reports/drive_material_v3'
KEYS = ['navy', 'brass', 'steel', 'silver', 'black', 'teal', 'core', 'rope']


def sha_array(data):
    return hashlib.sha256(np.asarray(data).tobytes()).hexdigest()


def fingerprint(ob):
    me = ob.data
    coords = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get('co', coords)
    loops = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get('vertex_index', loops)
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get('uv', uv)
    normals = np.empty(len(me.corner_normals) * 3, dtype=np.float32)
    me.corner_normals.foreach_get('vector', normals)
    return {'vertices': sha_array(coords), 'loops': sha_array(loops), 'uv': sha_array(uv),
            'normals': sha_array(normals), 'polygons': [len(f.vertices) for f in me.polygons],
            'matrix_basis': [list(v) for v in ob.matrix_basis],
            'matrix_parent_inverse': [list(v) for v in ob.matrix_parent_inverse]}


def make_image(name, resolution, data=False):
    image = bpy.data.images.new(name, resolution, resolution, alpha=True)
    image.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
    image.filepath_raw = str(S / 'textures' / (name + '.png'))
    image.file_format = 'PNG'
    return image


def final_material(glow):
    mat = bpy.data.materials.new('M_DriveV3_Glow' if glow else 'M_DriveV3_Surface')
    p = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for key in ['color', 'normal', 'orm'] + (['emission'] if glow else []):
        image = bpy.data.images.get('drive_v3_' + key)
        if image is None: image = bpy.data.images.load(str(S / 'textures' / ('drive_v3_' + key + '.png')))
        image.colorspace_settings.name = 'sRGB' if key in ['color', 'emission'] else 'Non-Color'
        image.pack()
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.label = key
        tex.location = (-600, -220 * ['color', 'normal', 'orm', 'emission'].index(key))
        if key == 'color': links.new(tex.outputs['Color'], p.inputs['Base Color'])
        elif key == 'normal':
            node = nodes.new('ShaderNodeNormalMap')
            node.uv_map = 'DriveTrim'
            links.new(tex.outputs['Color'], node.inputs['Color'])
            links.new(node.outputs['Normal'], p.inputs['Normal'])
        elif key == 'emission':
            links.new(tex.outputs['Color'], p.inputs['Emission Color'])
            p.inputs['Emission Strength'].default_value = 1.
        else:
            node = nodes.new('ShaderNodeSeparateColor')
            node.mode = 'RGB'
            links.new(tex.outputs['Color'], node.inputs['Color'])
            links.new(node.outputs['Green'], p.inputs['Roughness'])
            links.new(node.outputs['Blue'], p.inputs['Metallic'])
            group = bpy.data.node_groups.get('glTF Material Output')
            if group is None:
                group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
                group.interface.new_socket(name='Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
            ao = nodes.new('ShaderNodeGroup')
            ao.node_tree = group
            links.new(node.outputs['Red'], ao.inputs['Occlusion'])
    return mat


def main():
    scenes = [s for s in bpy.data.scenes if s.name.startswith('DriveMaterialV3_') and not s.name.endswith('_Bake')]
    parity = {}
    for scene in scenes:
        bpy.context.window.scene = scene
        bpy.context.view_layer.update()
        for ob in scene.objects:
            if ob.type != 'MESH': continue
            old = bpy.data.objects[ob['source_name']]
            a, b = fingerprint(old), fingerprint(ob)
            assert a == b, (ob.name, [k for k in a if a[k] != b[k]])
            parity[ob['source_name']] = a
    (R / 'source_preservation.json').write_text(json.dumps({'passed': True, 'meshes': len(parity), 'fingerprints': parity}, indent=2), encoding='utf-8')
    bake = bpy.data.scenes['DriveMaterialV3_Bake']
    bpy.context.window.scene = bake
    plane = bpy.data.objects['DriveMaterialV3_AtlasTiles']
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    bake.render.engine = 'CYCLES'
    bake.cycles.samples = 16
    bake.cycles.use_denoising = False
    bake.render.bake.margin = 0
    bake.render.bake.use_clear = True
    bake.render.bake.use_selected_to_active = False
    bake.view_settings.view_transform = 'Standard'
    # This separate process does the slow baking; the user's live scene remains responsive.
    preferences = bpy.context.preferences.addons['cycles'].preferences
    try:
        preferences.compute_device_type = 'OPTIX'
        preferences.refresh_devices()
        for device in preferences.devices: device.use = device.type == 'OPTIX'
        bake.cycles.device = 'GPU'
    except Exception:
        bake.cycles.device = 'CPU'
    mats = [bpy.data.materials['M_DriveV3_Source_' + k] for k in KEYS]
    originals, emissions, targets = {}, {}, {}
    for mat in mats:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        p = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
        originals[mat.name] = (p, output)
        emissions[mat.name] = nodes.new('ShaderNodeEmission')
        targets[mat.name] = nodes.new('ShaderNodeTexImage')

    images = {}
    for key, res in [('color', 1024), ('normal', 1024), ('roughness', 512), ('metallic', 512), ('emission', 256)]:
        image = make_image('drive_v3_' + key, res, data=key not in ['color', 'emission'])
        for mat in mats:
            p, output = originals[mat.name]
            em = emissions[mat.name]
            node = targets[mat.name]
            node.image = image
            mat.node_tree.nodes.active = node
            if key == 'normal':
                mat.node_tree.links.new(p.outputs['BSDF'], output.inputs['Surface'])
                continue
            socket = p.inputs[{'color': 'Base Color', 'roughness': 'Roughness', 'metallic': 'Metallic', 'emission': 'Emission Color'}[key]]
            for link in list(em.inputs['Color'].links): mat.node_tree.links.remove(link)
            if socket.is_linked:
                mat.node_tree.links.new(socket.links[0].from_socket, em.inputs['Color'])
            else:
                value = socket.default_value
                em.inputs['Color'].default_value = (value, value, value, 1) if isinstance(value, float) else value
            em.inputs['Strength'].default_value = p.inputs['Emission Strength'].default_value if key == 'emission' else 1.
            mat.node_tree.links.new(em.outputs['Emission'], output.inputs['Surface'])
        print('BAKE_START', key, res, flush=True)
        result = bpy.ops.object.bake(type='NORMAL' if key == 'normal' else 'EMIT')
        assert result == {'FINISHED'}, (key, result)
        image.save()
        image.pack()
        images[key] = image
        print('BAKE_DONE', key, flush=True)
    orm = make_image('drive_v3_orm', 512, data=True)
    rough = np.array(images['roughness'].pixels[:], dtype=np.float32).reshape(-1, 4)
    metal = np.array(images['metallic'].pixels[:], dtype=np.float32).reshape(-1, 4)
    pixels = np.ones_like(rough)
    pixels[:, 1] = rough[:, 0]
    pixels[:, 2] = metal[:, 0]
    orm.pixels.foreach_set(pixels.ravel())
    orm.save()
    orm.pack()
    for mat in mats:
        p, output = originals[mat.name]
        mat.node_tree.links.new(p.outputs['BSDF'], output.inputs['Surface'])
        mat.node_tree.nodes.remove(emissions[mat.name])
        mat.node_tree.nodes.remove(targets[mat.name])
    runtime = {False: final_material(False), True: final_material(True)}
    for scene in scenes:
        scene.render.engine = 'BLENDER_EEVEE'
        scene.view_settings.view_transform = 'Khronos PBR Neutral'
        for ob in scene.objects:
            if ob.type != 'MESH': continue
            ob.data.materials.clear()
            ob.data.materials.append(runtime[ob.get('surface_key') == 'core'])
    # Prune only this new headless copy; all original and live data remain intact.
    bpy.context.window.scene = scenes[0]
    for scene in list(bpy.data.scenes):
        if not scene.name.startswith('DriveMaterialV3_'): bpy.data.scenes.remove(scene)
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(S / 'drive_material_v3.blend'))
    (R / 'bake.json').write_text(json.dumps({'passed': True, 'materials': 8, 'maps': {'color': 1024, 'normal': 1024, 'orm': 512, 'emission': 256},
        'source_meshes_preserved': len(parity), 'bake': 'Cycles self-bake of editable planar trim source materials; no lighting/AO multiplied into basecolor',
        'uv': 'Existing 4 x 2 trim atlas and existing mesh UVs are unchanged', 'orm': 'R=1 (no new AO bake), G=roughness, B=metallic',
        'device': bake.cycles.device}, indent=2), encoding='utf-8')
    print('DRIVE_MATERIAL_BAKE_COMPLETE', len(parity), flush=True)


main()
