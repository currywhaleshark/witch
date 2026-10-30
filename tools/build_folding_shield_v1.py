"""Build the tri-fold riot-style shield (original rigid prop) in background Blender; export a GLB.

After the folding police shield the user supplied: a centre panel with two hinged side flaps
that fold behind it. Dressed for the witch: dark gunmetal plates, brass trim grooves, a geared
emblem with a teal core and a small teal sight port. Front faces -Y here, which Godot turns
into -Z. Each flap's origin sits on its hinge line, so the game folds it by turning it about
its own local vertical axis; the stored pose is fully open (flat).
"""
import bpy, bmesh, math, json, hashlib
from pathlib import Path
from mathutils import Matrix
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'assets/props/folding_shield_v1'
GAME = ROOT/'game/assets/props/folding_shield_v1'
HALF = .17          # centre panel half width; the flap hinges sit here
FLAP = .16          # flap width
TOP, BOTTOM = .32, -.32
THICK = .016
assert bpy.app.background
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def material(name, color, metallic, roughness, emission=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1)
        bsdf.inputs['Emission Strength'].default_value = strength
    return m


# Metallic stays moderate: the game renderer has no reflection environment, so full metal goes black.
PLATE = material('ShieldGunmetal', (.16, .18, .22), .45, .42)
BRASS = material('ShieldBrass', (.80, .58, .30), .45, .40)
STEEL = material('ShieldSteel', (.55, .60, .66), .5, .35)
TEAL = material('ShieldCore', (.25, .85, .75), 0., .2, (.35, .95, .85), 3.)


def obj(name, build, materials, origin=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new(); build(bm); bm.to_mesh(mesh); bm.free()
    o = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(o)
    o.location = origin
    for m in materials:
        o.data.materials.append(m)
    return o


def slab(bm, outline, y0, y1, material_index=0):
    # Extrude an XZ outline between y0 (front) and y1 (back); faces get the given material.
    front = [bm.verts.new((x, y0, z)) for x, z in outline]
    back = [bm.verts.new((x, y1, z)) for x, z in outline]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    n = len(outline)
    for i in range(n):
        faces.append(bm.faces.new((front[i], back[i], back[(i+1) % n], front[(i+1) % n])))
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    for f in faces:
        f.material_index = material_index
    return faces


def box(bm, center, size, material_index):
    geom = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*size, 1)))
    for f in {f for v in geom['verts'] for f in v.link_faces}:
        f.material_index = material_index


def cylinder(bm, center, radius, depth, segments, material_index, axis='Y'):
    rotation = {'Y': Matrix.Rotation(math.radians(90), 4, 'X'), 'Z': Matrix.Identity(4)}[axis]
    geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=depth,
        matrix=Matrix.Translation(center) @ rotation)
    for f in {f for v in geom['verts'] for f in v.link_faces}:
        f.material_index = material_index


def centre(bm):
    c = .035  # chamfered corners like the reference
    slab(bm, [(-HALF, BOTTOM+c), (-HALF+c, BOTTOM), (HALF-c, BOTTOM), (HALF, BOTTOM+c), (HALF, TOP-c), (HALF-c, TOP), (-HALF+c, TOP), (-HALF, TOP-c)], -THICK/2, THICK/2)
    # Brass trim bands near the top and bottom edges.
    for z in (TOP-.03, BOTTOM+.03):
        box(bm, (0, -THICK/2-.002, z), (2*HALF-.07, .004, .008), 1)
    # Geared emblem: a brass gear ring with a teal core.
    teeth = 14
    for i in range(teeth):
        a = math.tau*i/teeth
        box(bm, (math.cos(a)*.072, -THICK/2-.004, .03+math.sin(a)*.072), (.018, .008, .018), 1)
    cylinder(bm, (0, -THICK/2-.004, .03), .066, .008, 28, 1)
    cylinder(bm, (0, -THICK/2-.009, .03), .034, .010, 20, 3)
    # Sight port (teal glass) top-right, as on the reference.
    cylinder(bm, (.10, -THICK/2-.003, .22), .022, .006, 16, 3)
    # Hinge knuckles down both edges.
    for side in (-1, 1):
        for z in (-.24, -.08, .08, .24):
            cylinder(bm, (side*HALF, 0, z), .010, .07, 10, 2, axis='Z')
    # Rear grip bracket.
    box(bm, (0, THICK/2+.02, 0), (.05, .03, .26), 2)


def flap(side):
    def build(bm):
        # Local to its hinge: the flap extends outward (sign = side) from x = 0.
        x0, x1 = 0, side*FLAP
        outline = [(x0, BOTTOM+.01), (x1-side*.02, BOTTOM+.01), (x1, BOTTOM+.03), (x1, TOP-.03), (x1-side*.02, TOP-.01), (x0, TOP-.01)]
        slab(bm, outline if side > 0 else list(reversed(outline)), -THICK/2+.001, THICK/2-.001)
        # Three vertical brass grooves and a long edge trim, like the reference.
        for i in range(3):
            box(bm, (side*(.045+.022*i), -THICK/2-.002, 0), (.006, .004, .30), 1)
        box(bm, (side*(FLAP-.022), -THICK/2-.002, 0), (.006, .004, .48), 1)
    return obj('flap_'+('R' if side > 0 else 'L'), build, [PLATE, BRASS], origin=(side*HALF, 0, 0))


parts = {'centre': obj('centre', centre, [PLATE, BRASS, STEEL, TEAL]), 'flap_L': flap(-1), 'flap_R': flap(1)}
SOURCE.mkdir(parents=True, exist_ok=True); GAME.mkdir(parents=True, exist_ok=True)
blend = SOURCE/'folding_shield_v1.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
for stale in list(SOURCE.glob('*.blend1')):
    stale.unlink()
glb = GAME/'folding_shield.glb'
bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', export_yup=True, export_apply=True, export_animations=False)
triangles = 0
for o in parts.values():
    o.data.calc_loop_triangles(); triangles += len(o.data.loop_triangles)
report = {'parts': sorted(parts), 'triangles': triangles, 'centre_half_width_m': HALF, 'flap_width_m': FLAP,
    'height_m': TOP-BOTTOM, 'blend': blend.relative_to(ROOT).as_posix(), 'blend_sha256': hashlib.sha256(blend.read_bytes()).hexdigest(),
    'glb': glb.relative_to(ROOT).as_posix(), 'glb_sha256': hashlib.sha256(glb.read_bytes()).hexdigest()}
(SOURCE/'build.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('FOLDING_SHIELD_V1_COMPLETE', triangles, flush=True)
