"""Six original loot props for the November item additions (background Blender).

Editable scenes retain individual parts; runtime copies use one vertex-colored
mesh and at most three PBR surfaces. Existing v1/v2 exports are only referenced.
Run: blender -b --factory-startup --python-exit-code 1 -P tools/build_ground_loot_v3.py
"""
import bpy
import bmesh
import math
import json
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/props/ground_loot_v3'
GAME = ROOT / 'game/assets/props/ground_loot_v3'
REPORT = ROOT / 'reports/item_art_v2'
for folder in (SOURCE, GAME, REPORT):
    folder.mkdir(parents=True, exist_ok=True)
assert bpy.app.background, 'Do not replace a live authoring scene.'
bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, finish='matte'):
    m = bpy.data.materials.new(name)
    rgb = [int(color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    rgb = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Metallic'].default_value = .45 if finish == 'metal' else 0
    p.inputs['Roughness'].default_value = .38 if finish == 'metal' else .72
    m['finish'] = finish
    return m


BRASS = material('Aged_brass', 'bd914e', 'metal')
EDGE = material('Brass_edges', 'e1ba76', 'metal')
IRON = material('Blue_black_iron', '52636e', 'metal')
DARK = material('Bore_recess', '111b22')
RUST = material('Broad_rust_patches', '935038')
RED = material('Oxide_red_enamel', 'a1352e')
TEAL = material('Teal_enamel', '316269')
CORE = material('Turquoise_inset', '67c6be')
CORD = material('Tan_braided_cord', '9a744b')
CORD_DARK = material('Cord_grooves', '63503b')
EMBER = material('Orange_ember', 'ff9e39', 'ember')
COTTON = material('Ivory_cotton', 'd6cbb6')
FOLD = material('Cotton_fold', 'a99d88')
SLATE = material('Slate_collar', '586e80')
NAVY = material('Navy_teal_cape', '284a56')


def active(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def finish(o, name, mat, bevel=0):
    o.name = name
    o.data.materials.append(mat)
    active(o)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel:
        mod = o.modifiers.new('Rounded_edges', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(o.data)
    bm.free()
    for p in o.data.polygons:
        p.use_smooth = True
    mod = o.modifiers.new('Weighted_normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    o.select_set(False)
    return o


def box(name, pos, size, mat, bevel=.005, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.object
    o.scale = size
    o.rotation_euler.z = angle
    return finish(o, name, mat, bevel)


def cyl(name, pos, radius, depth, mat, rotation=(0, 0, 0), segments=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=depth, location=pos, rotation=rotation)
    return finish(bpy.context.object, name, mat, .0015)


def torus(name, pos, major, minor, mat, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=6, major_radius=major,
                                   minor_radius=minor, location=pos, rotation=rotation)
    return finish(bpy.context.object, name, mat)


def tube(name, points, radius, mat, sides=8):
    points = [Vector(p) for p in points]
    verts, faces = [], []
    for j, p in enumerate(points):
        direction = (points[min(j+1, len(points)-1)] - points[max(j-1, 0)]).normalized()
        axis = Vector((0, 0, 1)) if abs(direction.z) < .95 else Vector((0, 1, 0))
        u = direction.cross(axis).normalized()
        v = direction.cross(u).normalized()
        verts.extend(tuple(p + radius * (u*math.cos(i*math.tau/sides) + v*math.sin(i*math.tau/sides))) for i in range(sides))
    for j in range(len(points)-1):
        for i in range(sides):
            a, b = j*sides+i, j*sides+(i+1)%sides
            faces.append((a, b, b+sides, a+sides))
    faces.extend([tuple(reversed(range(sides))), tuple(range((len(points)-1)*sides, len(points)*sides))])
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return finish(o, name, mat)


def slab(name, outline, z, depth, mat, bevel=.004):
    count = len(outline)
    verts = [(x, y, z+d) for d in (-depth/2, depth/2) for x, y in outline]
    faces = [tuple(reversed(range(count))), tuple(range(count, 2*count))]
    faces.extend((i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return finish(o, name, mat, bevel)


def explosive():
    cyl('Red_sealed_cartridge', (0, 0, 0), .105, .235, RED, segments=24)
    for z in (-.115, .115):
        cyl('Heavy_brass_collar', (0, 0, z), .116, .033, BRASS, segments=24)
        torus('Collar_lip', (0, 0, z), .111, .006, EDGE)
    for x in (-.070, .070):
        box('Side_rib', (x, -.071, 0), (.020, .025, .205), BRASS)
    inset = box('Teal_diamond', (0, -.107, .005), (.065, .017, .065), TEAL, .003)
    inset.rotation_euler.y = math.pi/4
    cyl('Capped_stud', (0, 0, .147), .026, .038, IRON)


def twin_core():
    box('Teal_rear_housing', (0, .065, .015), (.245, .13, .145), TEAL, .013)
    box('Rear_brass_plate', (0, .131, .015), (.251, .016, .143), BRASS)
    for x in (-.069, .069):
        cyl('Short_iron_barrel', (x, -.045, .015), .057, .235, IRON, (math.pi/2, 0, 0), 24)
        torus('Open_brass_muzzle', (x, -.168, .015), .050, .009, BRASS, (math.pi/2, 0, 0))
        # Dark recessed disk behind the rim gives an actual visibly open mouth.
        cyl('Dark_bore', (x, -.166, .015), .040, .003, DARK, (math.pi/2, 0, 0), 24)
        torus('Rear_barrel_band', (x, .002, .015), .058, .006, EDGE, (math.pi/2, 0, 0))
    box('Brass_bridge', (0, -.002, .077), (.245, .034, .018), BRASS)
    cyl('Top_core_mount', (0, .060, .094), .037, .018, BRASS)
    cyl('Turquoise_top_inset', (0, .060, .106), .026, .009, CORE)


def fuse_bundle():
    for layer in range(3):
        for strand in range(2):
            pts = []
            for i in range(81):
                a = i*math.tau/80
                twist = a*10 + strand*math.pi
                pts.append(((.155+.006*math.cos(twist))*math.cos(a),
                            (.066+.006*math.cos(twist))*math.sin(a),
                            -.024 + layer*.027 + .006*math.sin(twist)))
            tube('Braided_cord_strand', pts, .0105, CORD if strand==0 else CORD_DARK, 6)
    for x in (-.065, .065):
        tube('Brass_binding', [(x,-.075,-.025),(x,-.086,.034),(x,-.060,.066),
                              (x,.060,.066),(x,.086,.034),(x,.075,-.025)], .010, BRASS)
        box('Brass_binding_plate',(x,0,.066),(.035,.100,.013),BRASS,.004)
        box('Teal_binding_inset',(x,0,.074),(.020,.075,.005),TEAL,.002)
    box('Red_cloth_tie', (0, -.071, .045), (.055, .032, .026), RED, .006)
    slab('Red_ribbon_tail',[(-.020,-.073),(.003,-.071),(.025,-.133),(-.007,-.125)],.022,.012,RED)
    for i in range(3):
        x = -.055 + i*.050
        end = (x-.020, .073+i*.003, .114 + (i%2)*.025)
        tube('Loose_ember_cord', [(x,.032,.024),(x,.052,.044),(x-.006,.068,.08),end], .014, CORD)
        cyl('Charred_tip', end, .015, .018, CORD_DARK)
        cyl('Warm_ember', (end[0],end[1],end[2]+.011), .012, .009, EMBER)
        if i==1:
            bpy.ops.mesh.primitive_cone_add(vertices=8,radius1=.014,radius2=.002,depth=.043,
                location=(end[0]+.004,end[1],end[2]+.035))
            finish(bpy.context.object,'Small_static_flame',EMBER)


def rusty_hinge():
    for side in (-1, 1):
        leaf = box('Broad_iron_leaf', (side*.088, 0, -.009), (.160,.240,.025), IRON, .008)
        leaf.rotation_euler.y = side*-.13
        box('Rust_edge', (side*.149,0,.016), (.020,.213,.008), RUST, .003)
        slab('Teal_leaf_inset',[(side*.049,-.064),(side*.126,-.043),(side*.115,.048),(side*.050,.064)],.019,.009,TEAL,.003)
        for y in (-.083, .083):
            cyl('Corner_bolt', (side*.114,y,.025), .021, .014, BRASS, segments=6)
            box('Bolt_slot', (side*.114,y,.033), (.023,.004,.003), DARK, .001)
    for i in range(3):
        cyl('Hinge_knuckle', (0,(i-1)*.075,.021), .037, .067, RUST if i==1 else IRON, (math.pi/2,0,0))
    for y in (-.126, .126):
        cyl('Pin_cap', (0,y,.021), .042,.020,BRASS,(math.pi/2,0,0))
    cyl('Teal_pivot_inset', (0,-.139,.021), .023,.008,CORE,(math.pi/2,0,0))


def counter_coat():
    box('Folded_ivory_coat', (0,0,0), (.320,.400,.064), FOLD, .025)
    for side in (-1,1):
        box('Ivory_front_panel',(side*.077,0,.030),(.151,.387,.045),COTTON,.018)
        box('Folded_sleeve',(side*.135,-.002,.060),(.083,.245,.045),COTTON,.014,side*.18)
        box('Slate_cuff',(side*.117,.102,.083),(.086,.060,.023),SLATE,.007,side*.18)
        slab('Slate_collar',[(side*.008,-.192),(side*.092,-.180),(side*.108,-.100),(side*.035,-.073)],.066,.018,SLATE)
        for y in (-.095,.056):
            for x in (side*.107,side*.162):
                box('Armor_hinge_leaf',(x,y,.093),(.045,.065,.016),BRASS,.004)
            cyl('Dark_armor_pivot',(side*.135,y,.106),.012,.077,IRON,(math.pi/2,0,0),12)
            for x in (side*.106,side*.163):
                cyl('Hinge_rivet',(x,y,.105),.008,.008,EDGE,segments=8)
    for y in (-.045,.030,.108):
        cyl('Brass_coat_button',(0,y,.062),.011,.009,BRASS,segments=12)
    cyl('Teal_chest_clasp',(0,-.117,.077),.021,.014,CORE)


def iron_cape():
    outline=[(-.105,-.190),(.105,-.190),(.205,.150),(.170,.200),(-.170,.200),(-.205,.150)]
    slab('Folded_navy_cape',outline,0,.074,NAVY,.018)
    for side in (-1,1):
        slab('Ivory_collar',[(side*.008,-.190),(side*.092,-.182),(side*.105,-.100),(side*.035,-.077)],.050,.016,COTTON)
        tube('Brass_hem',[(side*.195,.145,.030),(side*.164,.186,.036),(0,.186,.036)],.005,BRASS)
    for i in range(5):
        y = -.105 + i*.057
        width = .076 + .008*math.sin(i*.8)
        slab('Overlapping_iron_vertebra',[(-width/2,y-.029),(width/2,y-.029),(width*.64,y+.012),
            (width*.38,y+.034),(-width*.38,y+.034),(-width*.64,y+.012)],.064+i*.001,.027,IRON,.004)
        cyl('Brass_spine_pivot',(0,y-.008,.083+i*.001),.011,.009,BRASS,segments=12)
    for y in (-.070,.020,.110):
        for side in (-1,1):
            tube('Curved_rib_strap',[(side*.032,y,.065),(side*.081,y+.008,.066),
                 (side*.137,y+.034,.052),(side*.160,y+.053,.036)],.013,IRON)
            cyl('Rib_cap',(side*.142,y+.037,.061),.012,.009,BRASS,segments=12)


BUILDERS={'part_explosive':explosive,'twin_barrel_core':twin_core,'bundled_fuse':fuse_bundle,
          'rusted_guillotine_hinge':rusty_hinge,'counter_hinge':counter_coat,'iron_cartilage':iron_cape}
runtime_materials={}
for kind in ('matte','metal','ember'):
    m=material('Runtime_'+kind,'ffffff',kind)
    p=m.node_tree.nodes.get('Principled BSDF')
    attr=m.node_tree.nodes.new('ShaderNodeVertexColor')
    attr.layer_name='Color'
    m.node_tree.links.new(attr.outputs['Color'],p.inputs['Base Color'])
    if kind=='ember':
        m.node_tree.links.new(attr.outputs['Color'],p.inputs['Emission Color'])
        p.inputs['Emission Strength'].default_value=.25
    runtime_materials[kind]=m


def bounds(objects):
    bpy.context.view_layer.update()
    points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    return Vector(tuple(min(p[i] for p in points) for i in range(3))), Vector(tuple(max(p[i] for p in points) for i in range(3)))


records=[]
qa={}
for id,build in BUILDERS.items():
    scene=bpy.data.scenes.new(id)
    bpy.context.window.scene=scene
    build()
    objects=[o for o in scene.objects if o.type=='MESH']
    lo,hi=bounds(objects)
    center=(lo+hi)/2
    radius=max(Vector(((o.matrix_world@v.co-center).x,(o.matrix_world@v.co-center).y)).length for o in objects for v in o.data.vertices)
    scale=min(1,.315/radius)
    errors=[]
    for o in objects:
        o.location=(o.location-center)*scale
        o.scale*=scale
        active(o)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.02)
        bpy.ops.object.mode_set(mode='OBJECT')
        bm=bmesh.new(); bm.from_mesh(o.data)
        if any(f.calc_area()<1e-10 for f in bm.faces): errors.append(o.name+': degenerate face')
        if any(not e.is_manifold for e in bm.edges): errors.append(o.name+': open edge')
        bm.free()
    qa[id]={'errors':errors,'parts':len(objects),'scope':'Closed individual parts and face area; intentional joining interfaces are not inter-part collision tested.'}
    if errors: raise RuntimeError(str(qa[id]))
    lo,hi=bounds(objects)
    export_scene=bpy.data.scenes.new('Export_'+id)
    bpy.context.window.scene=export_scene
    copies=[]
    for o in objects:
        clone=o.copy(); clone.data=o.data.copy()
        export_scene.collection.objects.link(clone)
        m=o.data.materials[0]
        colors=clone.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='POINT')
        for entry in colors.data: entry.color=m.diffuse_color
        clone.data.materials.clear(); clone.data.materials.append(runtime_materials[m['finish']])
        copies.append(clone)
    bpy.ops.object.select_all(action='DESELECT')
    for o in copies: o.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    runtime=bpy.context.object
    runtime.name='SM_'+id
    path=GAME/(id+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
        export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
    record={'id':id,'source_parts':len(objects),'triangles':sum(len(p.vertices)-2 for p in runtime.data.polygons),
        'dimensions_godot':[hi.x-lo.x,hi.z-lo.z,hi.y-lo.y],'rest_height':-lo.z+.012,'radius':radius*scale,
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    records.append(record)
    bpy.context.window.scene=scene
    bpy.data.objects.remove(runtime,do_unlink=True)
    bpy.data.scenes.remove(export_scene)
    print('BUILT',id,record['triangles'],flush=True)

bpy.context.window.scene=bpy.data.scenes['part_explosive']
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'ground_loot_v3.blend'))
profiles=json.loads((ROOT/'game/assets/props/ground_loot_v2/models.json').read_text(encoding='utf-8'))
profiles.update({r['id']:{'path':'res://assets/props/ground_loot_v3/'+r['id']+'.glb',
    'rest_height':r['rest_height'],'dimensions':r['dimensions_godot']} for r in records})
(GAME/'models.json').write_text(json.dumps(profiles,indent=2)+'\n',encoding='utf-8')
(SOURCE/'models.json').write_text(json.dumps({'blender':bpy.app.version_string,'assets':records,
    'total_triangles':sum(r['triangles'] for r in records)},indent=2)+'\n',encoding='utf-8')
(REPORT/'source_qa.json').write_text(json.dumps(qa,indent=2)+'\n',encoding='utf-8')
print('GROUND_LOOT_V3_BUILT',len(records),len(profiles),flush=True)
