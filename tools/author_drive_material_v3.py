"""Run through live Blender MCP; copy the eight accepted drive scenes and author PBR trim shaders."""
import bpy
import json
import math

ROOT = 'C:/Users/yurib/Documents/New project/witch'
OUT = ROOT + '/assets/weapons/drive_material_v3'
IDS = ['guillotine', 'guillotine_saw', 'guillotine_lock', 'restraint_winch',
       'hydraulic_press', 'compound_executor', 'shock_frame', 'broad_cutter']
KEYS = ['navy', 'brass', 'steel', 'silver', 'black', 'teal', 'core', 'rope']
PALETTE = {'navy': (43, 59, 82), 'brass': (206, 168, 109), 'steel': (67, 79, 94),
           'silver': (195, 204, 212), 'black': (32, 38, 43), 'teal': (35, 94, 102),
           'core': (43, 153, 158), 'rope': (133, 114, 84)}
ROUGH = dict(zip(KEYS, [.57, .52, .56, .47, .83, .52, .30, .88]))


def linear(rgb):
    return tuple(c / 255 / 12.92 if c / 255 <= .04045 else ((c / 255 + .055) / 1.055) ** 2.4 for c in rgb) + (1,)


def make_material(key):
    mat = bpy.data.materials.new('M_DriveV3_Source_' + key)
    mat.diffuse_color = linear(PALETTE[key])
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    p = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
    p.location = (1100, 0)
    output.location = (1380, 0)

    def node(kind, name):
        n = nodes.new(kind)
        n.label = name
        n.name = name
        return n

    def set_socket(socket, value):
        if isinstance(value, (int, float, tuple)):
            socket.default_value = value
        else:
            links.new(value, socket)

    def op(kind, a, b=0., name=''):
        n = node('ShaderNodeMath', name or kind)
        n.operation = kind
        set_socket(n.inputs[0], a)
        set_socket(n.inputs[1], b)
        return n.outputs[0]

    def clip(value):
        return op('MINIMUM', op('MAXIMUM', value, 0.), 1.)

    def mix(a, b, amount, name):
        n = node('ShaderNodeMixRGB', name)
        n.blend_type = 'MIX'
        set_socket(n.inputs[0], amount)
        set_socket(n.inputs[1], a)
        set_socket(n.inputs[2], b)
        return n.outputs['Color']

    uv = node('ShaderNodeTexCoord', 'Atlas UV')
    scaled = node('ShaderNodeVectorMath', 'Tile coordinates')
    scaled.operation = 'MULTIPLY'
    links.new(uv.outputs['UV'], scaled.inputs[0])
    scaled.inputs[1].default_value = (4, 2, 1)
    offset = node('ShaderNodeVectorMath', 'Tile local coordinates')
    offset.operation = 'ADD'
    links.new(scaled.outputs[0], offset.inputs[0])
    index = KEYS.index(key)
    offset.inputs[1].default_value = (-(index % 4), -(1 - index // 4), .13 * index)
    separate = node('ShaderNodeSeparateXYZ', 'Tile axes')
    links.new(offset.outputs[0], separate.inputs[0])
    x, y = separate.outputs['X'], separate.outputs['Y']
    edge = op('MINIMUM', op('MINIMUM', x, op('SUBTRACT', 1., x)), op('MINIMUM', y, op('SUBTRACT', 1., y)), 'Distance to panel edge')

    def noise(scale, detail, name):
        n = node('ShaderNodeTexNoise', name)
        links.new(offset.outputs[0], n.inputs['Vector'])
        n.inputs['Scale'].default_value = scale
        n.inputs['Detail'].default_value = detail
        n.inputs['Roughness'].default_value = .68
        return n.outputs['Fac']

    cloud = noise(6.5, 3., 'Broad surface variation')
    chips = noise(57., 2., 'Broken edge wear')
    grain = noise(210., 1., 'Fine surface grain')
    threshold = op('ADD', .060, op('MULTIPLY', op('SUBTRACT', chips, .5), .034))
    wear = clip(op('DIVIDE', op('SUBTRACT', threshold, edge), .010, 'Edge wear mask'))
    brush = op('SINE', op('ADD', op('MULTIPLY', x, 680.), op('MULTIPLY', y, 9.)), name='Machining grain')
    variation = op('ADD', .93, op('MULTIPLY', cloud, .14))
    base = node('ShaderNodeMixRGB', 'Base albedo variation')
    base.blend_type = 'MULTIPLY'
    base.inputs[0].default_value = 1.
    base.inputs[1].default_value = linear(PALETTE[key])
    links.new(variation, base.inputs[2])
    color = base.outputs[0]
    metallic = 1. if key in ['brass', 'silver'] else 0.
    roughness = op('ADD', ROUGH[key], op('MULTIPLY', op('SUBTRACT', cloud, .5), .22))
    roughness = op('ADD', roughness, op('MULTIPLY', brush, .025 if key in ['brass', 'silver'] else .008))
    if key in ['navy', 'steel', 'teal']:
        color = mix(color, linear((188, 197, 204)), wear, 'Exposed metal at worn edges')
        metallic = wear
        roughness = op('SUBTRACT', roughness, op('MULTIPLY', wear, .17))
    if key == 'brass':
        patina = clip(op('MULTIPLY', op('SUBTRACT', cloud, .64), 7.5, 'Sparse tarnish'))
        patina = op('MULTIPLY', patina, op('SUBTRACT', 1., wear))
        color = mix(color, linear((61, 85, 73)), patina, 'Oxidized brass islands')
        metallic = op('SUBTRACT', 1., patina)
        roughness = op('ADD', roughness, op('MULTIPLY', patina, .28))
        color = mix(color, linear((224, 190, 132)), op('MULTIPLY', wear, .65), 'Polished brass corners')
    set_socket(p.inputs['Base Color'], color)
    set_socket(p.inputs['Metallic'], metallic)
    set_socket(p.inputs['Roughness'], clip(roughness))
    p.inputs['IOR'].default_value = 1.5
    p.inputs['Specular IOR Level'].default_value = .5
    bump = node('ShaderNodeBump', 'Subtle tool and casting marks')
    bump.inputs['Strength'].default_value = .22
    bump.inputs['Distance'].default_value = .00022 if key in ['brass', 'silver'] else .00035
    height = op('ADD', grain, op('MULTIPLY', brush, .15 if key in ['brass', 'silver'] else .025))
    set_socket(bump.inputs['Height'], height)
    links.new(bump.outputs['Normal'], p.inputs['Normal'])
    if key == 'core':
        p.inputs['Emission Color'].default_value = linear((45, 161, 169))
        p.inputs['Emission Strength'].default_value = .8
    mat['surface_key'] = key
    mat['description'] = 'Editable albedo/roughness/metal/normal source; no baked lighting. Edge wear follows the existing planar trim charts.'
    # A compact left-to-right node layout remains inspectable in the authoring file.
    for i, n in enumerate(n for n in nodes if n not in [p, output]):
        n.location = (-1800 + (i // 9) * 280, 900 - (i % 9) * 230)
    return mat


def main():
    assert not bpy.data.scenes.get('DriveMaterialV3_Bake'), 'v3 already exists; inspect before rebuilding'
    mats = {k: make_material(k) for k in KEYS}
    scenes = []
    for asset in IDS:
        old = bpy.data.scenes[('DriveV2_' if asset.startswith('guillotine') else 'DriveV1_') + asset]
        scene = bpy.data.scenes.new('DriveMaterialV3_' + asset)
        scene.unit_settings.system = 'METRIC'
        scene.unit_settings.scale_length = 1.
        scene['manifest_json'] = old['manifest_json']
        scene['source_scene'] = old.name
        scene['material_version'] = 3
        copies = {}
        for original in old.objects:
            ob = original.copy()
            if original.type == 'MESH':
                ob.data = original.data.copy()
                key = original.get('surface_key', 'navy')
                if key == 'edge': key = 'brass'
                ob.data.materials.clear()
                ob.data.materials.append(mats[key])
                for face in ob.data.polygons: face.material_index = 0
            ob.name = 'DM3_' + original.name
            ob['source_name'] = original.name
            scene.collection.objects.link(ob)
            copies[original] = ob
        for original, ob in copies.items():
            if original.parent in copies: ob.parent = copies[original.parent]
            ob.matrix_parent_inverse = original.matrix_parent_inverse.copy()
            ob.matrix_basis = original.matrix_basis.copy()
        scenes.append(scene)
    bake = bpy.data.scenes.new('DriveMaterialV3_Bake')
    bake.unit_settings.system = 'METRIC'
    vertices, faces = [], []
    for index, key in enumerate(KEYS):
        col, row = index % 4, 1 - index // 4
        start = len(vertices)
        vertices.extend([(col, row, 0), (col + 1, row, 0), (col + 1, row + 1, 0), (col, row + 1, 0)])
        faces.append(tuple(range(start, start + 4)))
    mesh = bpy.data.meshes.new('DriveMaterialV3_AtlasTiles')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    plane = bpy.data.objects.new('DriveMaterialV3_AtlasTiles', mesh)
    bake.collection.objects.link(plane)
    uv = mesh.uv_layers.new(name='DriveTrim')
    for mat in mats.values(): mesh.materials.append(mat)
    for face in mesh.polygons:
        face.material_index = face.index
        for li in face.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (v.x / 4, v.y / 2)
    bpy.context.window.scene = scenes[0]
    bpy.ops.wm.save_as_mainfile(filepath=OUT + '/drive_material_v3_live_authoring.blend', copy=True)
    print(json.dumps({'created_scenes': [s.name for s in scenes], 'materials': list(mats),
                      'parts': sum(sum(o.type == 'MESH' for o in s.objects) for s in scenes),
                      'output': OUT + '/drive_material_v3_live_authoring.blend'}))


main()
