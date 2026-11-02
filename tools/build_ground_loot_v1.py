"""Four original static drop meshes, authored in Blender from inventory icon designs.
Run: blender --background --factory-startup --python tools/build_ground_loot_v1.py
Each editable scene has centered geometry; +Z is up. GLB converts it to Godot +Y.
"""
import bpy
import math
import json
import hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/props/ground_loot_v1'
GAME = ROOT / 'game/assets/props/ground_loot_v1'
REPORT = ROOT / 'reports/ground_loot_v1'
for folder in (SOURCE, GAME, REPORT):
    folder.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, metal=0, rough=.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    color = [int(rgb[i:i+2], 16) / 255 for i in (0, 2, 4)]
    color = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in color]
    m.diffuse_color = (*color, 1)
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    return m


BRASS = material('aged_brass', 'bb8c48', .65, .38)
COPPER = material('copper', 'c98b59', .7, .35)
STEEL = material('blade_steel', 'adb8bd', .72, .38)
TEAL = material('painted_teal', '315f64', .25, .5)
DARK = material('dark_steel', '34434b', .45, .56)
RED = material('ruby_liquid', 'b91b2b', .05, .23)
GLASS = material('smoky_glass_neck', 'a6c5c5', .12, .2)
CORK = material('cork', 'ac7845', 0, .9)
CLOTH = material('warm_cotton', 'c6bea9', 0, .88)
LINING = material('slate_collar', '596978', 0, .8)
SEAM = material('cotton_fold', '918976', 0, .92)


def finish(obj, name, mat, smooth=True, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('soft edges', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    if smooth:
        mod = obj.modifiers.new('weighted normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    return obj


def box(name, loc, size, mat, bevel=.008, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = size
    obj.rotation_euler.z = angle
    return finish(obj, name, mat, bevel=bevel)


def cyl(name, loc, radius, depth, mat, rotation=(0, 0, 0), vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    return finish(bpy.context.object, name, mat, bevel=.002)


def torus(name, loc, major, minor, mat, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=32, minor_segments=8, major_radius=major, minor_radius=minor, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, mat)


def lathe(name, profile, mat, segments=32):
    verts = [(r * math.cos(i*math.tau/segments), r * math.sin(i*math.tau/segments), z) for z, r in profile for i in range(segments)]
    faces = []
    for j in range(len(profile)-1):
        for i in range(segments):
            a = j*segments+i
            b = j*segments+(i+1)%segments
            faces.append((a, b, b+segments, a+segments))
    faces += [tuple(reversed(range(segments))), tuple(range((len(profile)-1)*segments, len(profile)*segments))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat)


def polygon_slab(name, xy, height, depth, mat):
    n = len(xy)
    vertices = [(x, y, height + z) for z in (-depth/2, depth/2) for x, y in xy]
    faces = [tuple(reversed(range(n))), tuple(range(n, n*2))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, bevel=.002)


def potion():
    lathe('rounded red bottle', [(0,.045),(.008,.074),(.035,.099),(.075,.116),(.12,.118),(.16,.104),(.193,.068),(.21,.045)], RED)
    lathe('glass shoulder and neck', [(.193,.068),(.211,.045),(.241,.045),(.245,.054),(.259,.054)], GLASS)
    torus('brass neck ring', (0,0,.245), .051, .008, BRASS)
    lathe('cork stopper', [(.251,.039),(.29,.044),(.296,.041)], CORK, 20)
    torus('glass foot', (0,0,.012), .062, .007, GLASS)
    # A resting bottle tilts on its side; the whole authored silhouette tumbles as one piece.
    rotation = Matrix.Rotation(math.radians(68), 4, 'X') @ Matrix.Rotation(math.radians(-20), 4, 'Z')
    for obj in list(bpy.context.scene.objects):
        obj.matrix_world = rotation @ obj.matrix_world


def ring():
    torus('thick copper band', (0,0,0), .11, .025, COPPER, (1,1,.65))
    box('signet shoulder', (0,-.105,.025), (.118,.075,.043), COPPER, .018)
    torus('oval bezel', (0,-.108,.054), .047, .007, BRASS, (1.12,.85,.8))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=(0,-.108,.055))
    obj = bpy.context.object
    obj.scale = (.048,.036,.026)
    finish(obj, 'red cabochon', RED)


def cutting():
    box('teal mounting foot', (-.07,.015,-.06), (.28,.19,.044), TEAL)
    cyl('motor casing', (-.105,.015,.005), .077,.19, TEAL, (0,math.pi/2,0))
    for x in (-.19,-.035):
        cyl('motor brass collar', (x,.015,.005), .08,.018, BRASS, (0,math.pi/2,0))
    xy = []
    for tooth in range(20):
        for phase, radius in ((0,.142),(.28,.164),(.65,.164),(.86,.142)):
            angle = (tooth+phase)*math.tau/20
            xy.append((.095 + radius*math.cos(angle), .015 + radius*math.sin(angle)))
    polygon_slab('twenty tooth blade', xy, .056,.012, STEEL)
    cyl('central brass hub', (.095,.015,.072), .055,.027, BRASS)
    cyl('hex spindle bolt', (.095,.015,.095), .025,.018, DARK, vertices=6)
    for i in range(4):
        a = i*math.pi/2
        cyl('hub rivet', (.095+.042*math.cos(a), .015+.042*math.sin(a), .09), .006,.007, DARK, vertices=8)
    box('drive bracket', (-.025,.015,.015), (.10,.12,.09), BRASS)
    # Broad openings suggested by dark inset strips, no noisy micro-texture.
    for y in (-.023,.015,.053):
        box('motor vent', (-.11,y,.080), (.075,.012,.003), DARK, .001)


def coat():
    box('folded coat lower layer', (0,0,0), (.40,.45,.07), SEAM, .022)
    box('folded coat body', (0,-.006,.028), (.408,.438,.072), CLOTH, .024)
    box('front opening', (0,-.01,.067), (.015,.37,.007), LINING, .002)
    box('folded left sleeve', (-.13,.046,.07), (.13,.29,.045), CLOTH, .015, -.18)
    box('folded right sleeve', (.13,.046,.07), (.13,.29,.045), CLOTH, .015, .18)
    box('left cuff', (-.151,.166,.096), (.132,.055,.013), LINING, .007, -.18)
    box('right cuff', (.151,.166,.096), (.132,.055,.013), LINING, .007, .18)
    polygon_slab('left slate lapel', [(-.112,-.205),(-.018,-.215),(-.01,-.105),(-.068,-.037),(-.132,-.13)], .087,.012, LINING)
    polygon_slab('right slate lapel', [(.018,-.215),(.112,-.205),(.132,-.13),(.068,-.037),(.01,-.105)], .087,.012, LINING)
    for y in (-.064,.012,.088):
        cyl('brass button', (.022,y,.08), .010,.007, BRASS, vertices=12)
    box('folded hem piping', (0,.204,.047), (.35,.007,.008), SEAM, .002)


records = []
for index, (id, builder) in enumerate((('health_s',potion),('copper_ring',ring),('part_cutting',cutting),('cotton_coat',coat))):
    scene = bpy.context.scene if index == 0 else bpy.data.scenes.new(id)
    scene.name = id
    bpy.context.window.scene = scene
    builder()
    objects = [o for o in scene.objects if o.type == 'MESH']
    bpy.context.view_layer.update()
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (low+high)/2
    for obj in objects:
        obj.location -= center
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    path = GAME / (id+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_animations=False, export_cameras=False, export_lights=False, export_yup=True)
    triangles = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
    dims = high-low
    records.append({'id':id,'meshes':len(objects),'triangles':triangles,'dimensions_godot':[dims.x,dims.z,dims.y], 'rest_height':dims.z/2+.012, 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    bpy.ops.object.select_all(action='DESELECT')
bpy.context.window.scene = bpy.data.scenes['health_s']
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'ground_loot_v1.blend'))
manifest = {'blender':bpy.app.version_string,'source':'assets/props/ground_loot_v1/ground_loot_v1.blend','assets':records,'total_triangles':sum(r['triangles'] for r in records),'style':'Original low-detail geometry; opaque materials with broad highlights, no simulation or animation in GLBs.'}
(SOURCE/'models.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
(GAME/'models.json').write_text(json.dumps({r['id']:{'rest_height':r['rest_height'],'dimensions':r['dimensions_godot']} for r in records},indent=2)+'\n',encoding='utf-8')
print('GROUND_LOOT_BUILD '+json.dumps(manifest))
