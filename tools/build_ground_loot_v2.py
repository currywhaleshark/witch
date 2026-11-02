"""Complete the prototype's ground loot set; preserve the four accepted v1 GLBs.

Background only: blender -b --factory-startup --python-exit-code 1 -P this_file.
Editable part scenes retain descriptive materials; export copies use vertex colors
and at most three PBR surfaces. No generated imagery or external model dependency.
"""
import bpy
import bmesh
import math
import json
import hashlib
import sys
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/props/ground_loot_v2'
GAME = ROOT / 'game/assets/props/ground_loot_v2'
REPORT = ROOT / 'reports/ground_loot_v2'
SKILLS = Path.home() / '.agents/skills'
for folder in (SOURCE, GAME, REPORT):
    folder.mkdir(parents=True, exist_ok=True)
assert bpy.app.background, 'Never clear the user live scene.'
bpy.ops.wm.read_factory_settings(use_empty=True)
sys.path.insert(0, str(SKILLS / 'blender-asset-qa/scripts'))
import qa_check

PALETTE = {}
def mat(key, rgb, finish='matte'):
    m = bpy.data.materials.new('M_' + key)
    m.use_nodes = True
    values = [int(rgb[i:i+2], 16) / 255 for i in (0, 2, 4)]
    rgb = tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values)
    m.diffuse_color = (*rgb, 1)
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Metallic'].default_value = {'metal': .7, 'gem': .08, 'matte': 0}[finish]
    p.inputs['Roughness'].default_value = {'metal': .36, 'gem': .23, 'matte': .76}[finish]
    m['finish'] = finish
    PALETTE[key] = m
    return m

BRASS = mat('aged_brass', 'ba8c49', 'metal')
EDGE = mat('brass_edge', 'e0ba73', 'metal')
SILVER = mat('silver', 'c1cbd3', 'metal')
STEEL = mat('dark_steel', '37454e', 'metal')
COPPER = mat('copper_coil', 'ad683a', 'metal')
TEAL = mat('teal_enamel', '325b61')
NAVY = mat('navy_cloth', '29384c')
FOLD = mat('navy_fold', '1b2532')
PAPER = mat('blueprint', '324d67')
INK = mat('ivory_ink', 'c9d8d5')
RED = mat('red_liquid', 'bd2034', 'gem')
BLUE = mat('blue_liquid', '127ac4', 'gem')
VIOLET = mat('violet_liquid', '9250b9', 'gem')
GREEN = mat('green_liquid', '54a735', 'gem')
CORE = mat('teal_crystal', '2fb3ab', 'gem')
PALE = mat('pale_crystal', 'a1d9e4', 'gem')
GLASS = mat('smoky_neck', 'a6c5c5', 'gem')
CORK = mat('cork', 'ac7845')
COTTON = mat('cotton', 'c9bfaa')
COTTON_FOLD = mat('cotton_fold', '928772')
LEATHER = mat('chestnut_leather', '815237')
LEATHER_EDGE = mat('leather_edges', 'a4714e')
SOLE = mat('rubber_sole', '413b36')
RIBBON = mat('wine_ribbon', '8b2736')
RIBBON_EDGE = mat('ribbon_highlight', 'b7505a')
STONE = mat('name_fragment', '3f344f')

def activate(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o

def finish(o, name, material, bevel=0, smooth=True, group='main'):
    o.name = name
    o['qa_group'] = group
    o.data.materials.append(material)
    activate(o)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel:
        mod = o.modifiers.new('Edge_highlight', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        mod.use_clamp_overlap = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()
    for poly in o.data.polygons:
        poly.use_smooth = smooth
    if smooth:
        mod = o.modifiers.new('Weighted_normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.select_set(False)
    return o

def mesh(name, verts, faces, material, bevel=0, smooth=True, group='main'):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return finish(o, name, material, bevel, smooth, group)

def box(name, pos, size, material, bevel=.005, angle=0, group='main'):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.object
    o.scale = size
    o.rotation_euler.z = angle
    return finish(o, name, material, bevel, group=group)

def sphere(name, pos, size, material, segments=16, rings=10, group='main'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=pos)
    o = bpy.context.object
    o.scale = size
    return finish(o, name, material, group=group)

def cyl(name, pos, radius, depth, material, rotation=(0, 0, 0), segments=16, group='main'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=depth, location=pos, rotation=rotation)
    return finish(bpy.context.object, name, material, .0015, group=group)

def torus(name, pos, major, minor, material, scale=(1, 1, 1), rotation=(0, 0, 0), group='main'):
    bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=6, major_radius=major, minor_radius=minor, location=pos, rotation=rotation)
    o = bpy.context.object
    o.scale = scale
    return finish(o, name, material, group=group)

def rod(name, a, b, radius, material, group='main', segments=8):
    a, b = Vector(a), Vector(b)
    o = cyl(name, (a+b)/2, radius, (b-a).length, material, segments=segments, group=group)
    o.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    activate(o)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o

def tube(name, pts, radius, material, group='main', sides=8):
    # A capped polyline tube, rather than a chain of coplanar cylinder caps.
    pts = [Vector(p) for p in pts]
    verts, faces = [], []
    for j, p in enumerate(pts):
        tangent = (pts[min(j+1,len(pts)-1)] - pts[max(j-1,0)]).normalized()
        axis = Vector((0,0,1)) if abs(tangent.z) < .95 else Vector((0,1,0))
        u = tangent.cross(axis).normalized()
        v = tangent.cross(u).normalized()
        verts += [tuple(p + radius * (u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides))) for i in range(sides)]
    for j in range(len(pts)-1):
        for i in range(sides):
            k = j*sides+i; n = j*sides+(i+1)%sides
            faces.append((k,n,n+sides,k+sides))
    faces += [tuple(reversed(range(sides))), tuple(range((len(pts)-1)*sides,len(pts)*sides))]
    return mesh(name,verts,faces,material,group=group)

def lathe(name, profile, material, segments=24, group='main', smooth=True):
    verts = [(r*math.cos(i*math.tau/segments), r*math.sin(i*math.tau/segments), z) for z,r in profile for i in range(segments)]
    faces=[]
    for j in range(len(profile)-1):
        for i in range(segments):
            a=j*segments+i; b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces += [tuple(reversed(range(segments))),tuple(range((len(profile)-1)*segments,len(profile)*segments))]
    return mesh(name,verts,faces,material,group=group,smooth=smooth)

def slab(name, outline, z, thickness, material, bevel=.002, group='main'):
    n=len(outline)
    verts=[(x,y,z+d) for d in (-thickness/2,thickness/2) for x,y in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,material,bevel,group=group)

def gear(name, pos, radius, depth, material, teeth=12, group='main'):
    x,y,z=pos
    outline=[]
    for i in range(teeth):
        for phase,r in ((0,.84),(.18,1),(.65,1),(.85,.84)):
            a=(i+phase)*math.tau/teeth
            outline.append((x+radius*r*math.cos(a),y+radius*r*math.sin(a)))
    return slab(name,outline,z,depth,material,.001,group)

def rotate_set(objs, angle, axis='X'):
    bpy.context.view_layer.update()
    rot=Matrix.Rotation(angle,4,axis)
    for o in objs:
        o.matrix_world=rot@o.matrix_world

def potion(id):
    liquid = RED if 'health' in id else BLUE if 'mana' in id else GREEN if id=='speed' else VIOLET
    full=id.startswith('full_')
    size='full' if full else id.rsplit('_',1)[-1]
    if size=='s':
        profile=[(0,.045),(.008,.074),(.035,.099),(.075,.116),(.12,.118),(.16,.104),(.193,.068),(.21,.045)]
        shoulder=.193; neck=.21; top=.26; radius=.045
    elif size=='m':
        profile=[(0,.045),(.015,.067),(.07,.091),(.16,.098),(.23,.080),(.28,.045)]
        shoulder=.265; neck=.28; top=.335; radius=.037
    elif size=='l':
        profile=[(0,.080),(.015,.13),(.05,.15),(.17,.15),(.22,.13),(.26,.054)]
        shoulder=.25; neck=.26; top=.32; radius=.046
    elif full:
        profile=[(0,.012),(.035,.048),(.18,.152),(.255,.115),(.30,.038)]
        shoulder=.29; neck=.30; top=.35; radius=.035
    else:
        profile=[(0,.025),(.02,.045),(.09,.073),(.15,.065),(.22,.04),(.30,.027)]
        shoulder=.28; neck=.30; top=.35; radius=.026
    lathe('Liquid_body',profile,liquid,segments=8 if full else 24,smooth=not full)
    lathe('Glass_neck',[(shoulder,radius*1.3),(neck,radius),(top-.015,radius),(top-.01,radius*1.22),(top,radius*1.22)],GLASS)
    torus('Neck_band',(0,0,top-.011),radius*1.16,.007,BRASS)
    if full:
        lathe('Faceted_stop',[(top-.008,radius*.8),(top+.022,radius*1.35),(top+.060,.004)],EDGE,8,smooth=False)
        # Strong cage ribs and a waist ring identify the rare complete-recovery bottle.
        for i in range(4):
            a=i*math.tau/4
            tube('Crystal_cage_rib',[(r*math.cos(a),r*math.sin(a),z) for z,r in ((.02,.035),(.18,.155),(.258,.118),(.315,.038))],.006,BRASS)
        torus('Crystal_waist',(0,0,.181),.152,.006,EDGE)
    else:
        lathe('Stopper',[(top-.014,radius*.8),(top+.035,radius*.96),(top+.04,radius*.88)],CORK,16)
        if size=='l':
            torus('Lower_gilded_band',(0,0,.045),.147,.008,BRASS)
            for a in (0,math.pi):
                tube('Bottle_side_binding',[(r*math.cos(a),r*math.sin(a),z) for z,r in ((.045,.147),(.17,.151),(.225,.128),(.26,.055))],.005,BRASS)
        elif size=='m':
            torus('Foot_rim',(0,0,.027),.076,.006,GLASS)
        elif size=='s':
            torus('Glass_foot',(0,0,.012),.062,.007,GLASS)
        else:
            tube('Speed_leaf',[(0,-.056,.07),(.025,-.064,.12),(.018,-.048,.19),(0,-.028,.25)],.004,EDGE)
    # The round small vial is already accepted. Increase the long/broad bottle
    # bodies rather than making the small model smaller than its preserved v1 peer.
    size_scale = 1.24 if size=='m' else 1.15 if size=='l' else 1.0
    for o in list(bpy.context.scene.objects):
        o.location *= size_scale
        o.scale *= size_scale
    rotate_set(list(bpy.context.scene.objects),math.radians(68 if not full else 63))

def ring():
    torus('Open_silver_band',(0,0,0),.11,.016,SILVER,scale=(1,1,.75))
    sphere('Raised_setting',(0,-.106,.023),(.045,.03,.022),SILVER)
    gem=lathe('Cut_ice_stone',[(0,.022),(.022,.045),(.041,.029),(.046,.018)],PALE,8,smooth=False)
    gem.location=(0,-.108,.032)
    for x in (-.034,.034):
        rod('Stone_claw',(x,-.108,.035),(x*.82,-.108,.072),.004,SILVER)

def brooch(silver=False):
    if silver:
        cyl('Flower_back',(0,0,0),.076,.028,SILVER)
        for i in range(6):
            a=i*math.tau/6
            o=sphere('Silver_petal',(math.cos(a)*.083,math.sin(a)*.083,.013),(.082,.038,.019),SILVER)
            o.rotation_euler.z=a
            tube('Petal_ridge',[(r*math.cos(a),r*math.sin(a),z) for r,z in ((.042,.03),(.085,.037),(.137,.025))],.003,EDGE)
        torus('Center_setting',(0,0,.028),.045,.006,SILVER)
        sphere('Teal_center',(0,0,.035),(.045,.045,.025),CORE)
    else:
        gear('Twelve_tooth_frame',(0,0,0),.16,.025,BRASS)
        torus('Raised_inner_frame',(0,0,.020),.115,.015,EDGE)
        sphere('Teal_cabochon',(0,0,.019),(.111,.111,.033),CORE)
        for i in range(4):
            a=i*math.tau/4
            cyl('Frame_stud',(.14*math.cos(a),.14*math.sin(a),.018),.009,.009,STEEL,segments=8)

def orb(crystal=False):
    lathe('Brass_pedestal',[(0,.083),(.015,.096),(.035,.063),(.055,.068)],BRASS)
    if crystal:
        o=lathe('Tall_teal_shard',[(.04,.045),(.09,.082),(.28,.063),(.38,.007)],CORE,7,smooth=False)
        for i in range(4):
            a=i*math.tau/4
            tube('Crystal_prong',[(r*math.cos(a),r*math.sin(a),z) for z,r in ((.025,.075),(.065,.080),(.13,.073))],.009,EDGE)
    else:
        sphere('Teal_glass_orb',(0,0,.173),(.124,.124,.124),CORE,24,16)
        for i in range(3):
            a=i*math.tau/3
            tube('Orb_claw',[(r*math.cos(a),r*math.sin(a),z) for z,r in ((.02,.068),(.08,.087),(.14,.127),(.195,.122))],.009,BRASS)
        torus('Equatorial_inlay',(0,0,.173),.124,.004,EDGE)
    rotate_set(list(bpy.context.scene.objects),math.radians(70))

def blueprint(id):
    # Solid bowed sheet with rolled ends, a clasp, and a raised pale schematic emblem.
    outline=[(-.14,-.19),(.12,-.19),(.15,-.15),(.14,.17),(.10,.195),(-.14,.18)]
    slab('Rolled_blue_drafting_sheet',outline,0,.014,PAPER,.004)
    for y in (-.178,.178):
        cyl('Rolled_edge',(0,y,.011),.025,.29,PAPER,(0,math.pi/2,0))
        for x in (-.143,.143):
            torus('Roll_brass_cap',(x,y,.011),.021,.004,BRASS,rotation=(0,math.pi/2,0))
    box('Clasp',(0,-.19,.028),(.068,.042,.016),BRASS)
    # Emblems are shallow embossed schematic silhouettes, not mechanical instructions.
    z=.012
    if id=='bp_shotgun':
        slab('Shotgun_emblem',[(-.10,-.02),(.10,-.02),(.10,.003),(-.025,.003),(-.067,.055),(-.09,.04),(-.052,.004),(-.10,.004)],z,.006,INK,.001)
    elif id=='bp_chainsaw':
        slab('Chainsaw_emblem',[(-.10,-.03),(-.065,-.05),(.10,-.03),(.13,-.005),(.10,.027),(-.065,.045),(-.10,.025)],z,.006,INK,.001)
        for x in (-.05,-.015,.02,.055,.09):
            box('Chain_mark',(x,.034,z+.004),(.015,.02,.006),INK,.001,angle=-.3)
        torus('Emblem_handle',(-.095,0,z),.024,.005,INK,scale=(1,.8,1))
    else:
        gear('Automaton_body_emblem',(0,0,z),.05,.006,INK,8)
        cyl('Automaton_head_emblem',(0,-.078,z),.026,.006,INK)
        for side in (-1,1):
            tube('Automaton_limb',[(side*.043,-.02,z),(side*.078,.025,z),(side*.07,.055,z)],.005,INK)
            tube('Automaton_leg',[(side*.02,.038,z),(side*.035,.085,z),(side*.058,.09,z)],.006,INK)
    # Sparse margin strokes stay readable without stippled text at gameplay scale.
    for y in (-.11,.105):
        box('Draft_rule',(0,y,.011),(.19,.003,.004),INK,.0005)

def ballistic():
    box('Receiver',(0,0,0),(.22,.14,.13),BRASS,.013)
    cyl('Front_barrel',(-.145,0,0),.059,.16,STEEL,(0,math.pi/2,0))
    torus('Muzzle_lip',(-.223,0,0),.048,.009,SILVER,rotation=(0,math.pi/2,0))
    cyl('Dark_muzzle_recess',(-.218,0,0),.040,.012,FOLD,(0,math.pi/2,0))
    box('Teal_mount',(.04,0,-.075),(.16,.14,.028),TEAL)
    cyl('Rear_coil',(.14,0,0),.052,.10,TEAL,(0,math.pi/2,0))
    for x in (-.06,.065,.15):
        cyl('Barrel_ring',(x,0,0),.073 if x<.1 else .057,.014,EDGE,(0,math.pi/2,0))
    for y in (-.076,.076):
        rod('Receiver_rail',(-.085,y,.035),(.08,y,.035),.01,STEEL)
    for x in (-.02,.025):
        cyl('Top_bolt',(x,0,.074),.014,.02,STEEL,segments=6)

def power():
    box('Engine_skid',(0,0,-.085),(.31,.18,.032),TEAL)
    cyl('Teal_power_cell',(0,0,0),.082,.29,CORE,(0,math.pi/2,0),24)
    for x in (-.155,.155):
        cyl('End_cartridge',(x,0,0),.092,.045,BRASS,(0,math.pi/2,0))
        cyl('End_cap',(x*1.14,0,0),.065,.018,STEEL,(0,math.pi/2,0))
    for a in (math.pi/4,math.pi*3/4,math.pi*5/4,math.pi*7/4):
        rod('Brass_guard_rail',(-.145,.088*math.cos(a),.088*math.sin(a)),(.145,.088*math.cos(a),.088*math.sin(a)),.009,BRASS)
    # Helical copper winding is visibly distinct from the long ballistic barrel.
    pts=[(-.075+i*.15/70,.034*math.cos(i*math.tau/14),.12+.034*math.sin(i*math.tau/14)) for i in range(71)]
    tube('Copper_induction_coil',pts,.005,COPPER,sides=6)
    for x in (-.10,.10):
        cyl('Terminal_post',(x,0,.095),.028,.065,BRASS)

def ribbon():
    for sign in (-1,1):
        # Closed creased bow lobes: broad outer edge, narrow pinched center.
        outline=[(sign*.012,0),(sign*.14,-.10),(sign*.19,-.075),(sign*.18,.08),(sign*.13,.10)]
        slab('Bow_loop',outline,.025,.045,RIBBON,.014)
        tube('Bow_crease',[(sign*.02,0,.046),(sign*.09,.012,.057),(sign*.17,.05,.046)],.004,RIBBON_EDGE)
        slab('Ribbon_tail',[(sign*.015,.015),(sign*.11,.075),(sign*.11,.20),(sign*.064,.17),(sign*.024,.20)],0,.013,RIBBON,.003)
    box('Gathered_center',(0,0,.026),(.055,.075,.065),RIBBON_EDGE,.016)

def star_pin():
    poly=[]
    for i in range(10):
        a=math.pi/2+i*math.pi/5
        r=.16 if i%2==0 else .066
        poly.append((r*math.cos(a),r*math.sin(a)))
    slab('Five_point_star',poly,.016,.028,BRASS,.005)
    for i in range(5):
        a=math.pi/2+i*math.tau/5
        rod('Star_ridge',(0,0,.035),(.135*math.cos(a),.135*math.sin(a),.031),.004,EDGE)
    sphere('Center_stone',(0,0,.038),(.036,.036,.023),CORE)
    tube('Hairpin_loop',[(-.18,.085,-.004),(-.24,.15,-.004),(-.225,.17,-.004),(-.11,.08,-.004),(0,-.02,-.004)],.005,STEEL)

def cape():
    outline=[(-.12,-.19),(.12,-.19),(.21,.15),(.17,.20),(-.17,.20),(-.21,.15)]
    slab('Folded_cape',outline,0,.065,FOLD,.018)
    slab('Top_quilted_layer',[(x*.98,y*.97) for x,y in outline],.029,.06,NAVY,.017)
    # Fold ridge panels and paired ivory collar communicate clothing at native scale.
    for x in (-.11,0,.11):
        tube('Long_fold',[(x*.65,-.13,.066),(x,.04,.066),(x*1.4,.17,.061)],.004,FOLD)
    for y in (-.045,.055,.145):
        tube('Quilting_seam',[(-.12,y,.061),(0,y+.04,.064),(.12,y,.061)],.0025,FOLD)
    for side in (-1,1):
        slab('Cotton_collar',[(side*.012,-.185),(side*.093,-.176),(side*.115,-.091),(side*.040,-.056)],.066,.014,COTTON,.004)
    tube('Gold_hem',[(-.20,.14,.047),(-.166,.186,.049),(.166,.186,.049),(.20,.14,.047)],.005,BRASS)
    cyl('Throat_clasp',(0,-.13,.075),.02,.014,BRASS)

def gloves(leather=False):
    main=LEATHER if leather else COTTON
    edge=LEATHER_EDGE if leather else COTTON_FOLD
    for hand,x0 in enumerate((-.10,.105)):
        group='left' if hand==0 else 'right'
        sign=-1 if hand==0 else 1
        y0=.018 if hand==0 else -.012
        sphere('Glove_palm',(x0,y0,.014),(.070,.105,.038),main,group=group)
        box('Wrist_cuff',(x0,y0+.095,.010),(.136,.068,.061),edge,.012,group=group)
        box('Cuff_fold',(x0,y0+.115,.027),(.139,.018,.036),main,.008,group=group)
        for i,(dx,length) in enumerate(((-.047,.071),(-.016,.093),(.016,.10),(.046,.080))):
            px=x0+dx
            sphere('Rounded_finger',(px,y0-.088-length*.36,.014),(.018,length*.63,.022),main,12,8,group)
            if leather:
                box('Finger_stitch',(px,y0-.093,.034),(.004,.038,.003),edge,.001,group=group)
        # Thumb projects outward, away from the paired glove.
        thumb=sphere('Thumb',(x0+sign*.075,y0-.028,.010),(.024,.061,.025),main,12,8,group)
        thumb.rotation_euler.z=sign*.5
        if leather:
            box('Wrist_strap',(x0,y0+.069,.045),(.137,.027,.012),TEAL,.004,group=group)
            box('Strap_buckle',(x0+sign*.035,y0+.069,.055),(.031,.029,.010),BRASS,.002,group=group)
        else:
            for dx in (-.025,0,.025):
                tube('Palm_seam',[(x0+dx,y0+.035,.050),(x0+dx,y0-.045,.047)],.002,edge,group)

def shoe_mesh(name,x0,y0,scale,z,depth,material,group):
    outline=[(-.052,-.19),(.038,-.195),(.075,-.162),(.083,-.105),(.075,-.025),(.066,.06),(.065,.16),(.039,.18),(-.038,.18),(-.068,.15),(-.067,.047),(-.073,-.05),(-.079,-.13)]
    return slab(name,[(x0+x*scale,y0+y*scale) for x,y in outline],z,depth,material,.009,group)

def shoes(boots=False):
    for idx,x0 in enumerate((-.095,.095)):
        group='left' if idx==0 else 'right'
        y0=.012 if idx==0 else -.012
        shoe_mesh('Sole',x0,y0,1,0,.038,SOLE if boots else COTTON,group)
        shoe_mesh('Upper',x0,y0,.95,.041,.068,LEATHER if boots else COTTON,group)
        sphere('Toe_cap',(x0,y0-.119,.062),(.07,.079,.040),LEATHER_EDGE if boots else COTTON,group=group)
        if boots:
            o=lathe('Hollow_boot_shaft',[(.055,.060),(.21,.056),(.22,.060),(.22,.045),(.09,.044)],LEATHER,20,group)
            o.location=(x0,y0+.092,0)
            torus('Rolled_boot_rim',(x0,y0+.092,.211),.054,.009,LEATHER_EDGE,scale=(1,1,.7),group=group)
            cyl('Boot_dark_interior',(x0,y0+.092,.12),.043,.012,FOLD,group=group)
            box('Ankle_strap',(x0,y0+.102,.114),(.13,.052,.016),TEAL,.006,group=group)
            box('Small_buckle',(x0+.052,y0+.079,.125),(.024,.022,.014),BRASS,.003,group=group)
        else:
            sphere('Heel_opening',(x0,y0+.109,.078),(.052,.052,.018),FOLD,group=group)
            torus('Padded_collar',(x0,y0+.109,.082),.052,.013,NAVY,scale=(1,1,.6),group=group)
            for side in (-1,1):
                tube('Navy_side_stripe',[(x0+side*.068,y0-.085,.067),(x0+side*.068,y0-.015,.068),(x0+side*.059,y0+.06,.076)],.005,NAVY,group)
        box('Tongue',(x0,y0+.006,.085),(.065,.116,.018),LEATHER_EDGE if boots else NAVY,.006,group=group)
        for y in (-.038,-.012,.014,.040):
            rod('Cross_lace',(x0-.028,y0+y-.008,.098),(x0+.028,y0+y+.008,.098),.0035,COTTON,group)

def pulley():
    # Twin pulley cheeks, recessed sheave and a suspended cutter jaw joined by a chain.
    for x in (-.039,.039):
        cyl('Pulley_cheek',(x,-.045,.035),.105,.023,BRASS,(0,math.pi/2,0),24)
    cyl('Recessed_sheave',(0,-.045,.035),.088,.067,STEEL,(0,math.pi/2,0),24)
    cyl('Axle',(.055,-.045,.035),.025,.026,EDGE,(0,math.pi/2,0))
    tube('Pulley_crown',[(-.048,-.035,.10),(-.038,-.03,.16),(.038,-.03,.16),(.048,-.035,.10)],.012,BRASS)
    torus('Hanging_eye',(0,-.03,.16),.026,.008,BRASS,rotation=(math.pi/2,0,0))
    # Connected chain bends along the floor toward the distinctive opposing jaws.
    for i in range(5):
        torus('Chain_link',(.055+i*.023,.045+i*.026,.025),.021,.006,BRASS,scale=(.8,1.2,1),rotation=(math.pi/2 if i%2 else 0,0,-.7))
    for sign in (-1,1):
        slab('Cutter_jaw',[(.14+sign*.012,.12),(.14+sign*.075,.17),(.14+sign*.06,.235),(.14+sign*.014,.26),(.14+sign*.029,.19)],.015,.034,STEEL,.003)
    cyl('Cutter_hinge',(.14,.15,.035),.033,.021,BRASS)

def spring():
    # Two clockwork capsules share a bridged central core; no blueprint substitution.
    box('Twin_cell_bridge',(0,0,0),(.24,.14,.05),BRASS,.013)
    for side in (-1,1):
        x=side*.089
        cyl('Clock_housing',(x,0,.015),.087,.070,TEAL,segments=24)
        gear('Clock_rim',(x,0,.05),.088,.018,BRASS,12)
        # Visible spiral mainspring, capped tube, fully supported by the face plate.
        pts=[]
        for i in range(65):
            a=i*math.tau*2.1/64
            r=.013+.052*i/64
            pts.append((x+r*math.cos(a),r*math.sin(a),.064))
        tube('Exposed_mainspring',pts,.005,EDGE,sides=6)
        cyl('Spindle',(x,0,.067),.014,.020,STEEL)
    sphere('Twin_core',(0,.075,.026),(.043,.040,.037),CORE)
    rod('Key_stem',(0,-.07,.015),(0,-.13,.015),.012,BRASS)
    for i,x in enumerate((-.028,.028)):
        torus('Winding_key_eye',(x,-.15,.015+i*.004),.028,.008,BRASS)

def currency():
    for i,(x,y,z) in enumerate(((-.055,.012,0),(.035,.025,.015),(.015,-.055,.031))):
        cyl('Engraved_coin',(x,y,z),.077,.018,BRASS,segments=24)
        torus('Raised_coin_rim',(x,y,z+.009),.066,.004,EDGE)
        # Stamped square-hole emblem: four separate bars, not a flat decal.
        for dx,dy,sx,sy in ((0,-.017,.045,.006),(0,.017,.045,.006),(-.019,0,.006,.03),(.019,0,.006,.03)):
            box('Square_stamp',(x+dx,y+dy,z+.011),(sx,sy,.005),STEEL,.001)

def piece(id):
    outline=[(-.08,-.12),(.045,-.135),(.093,-.064),(.08,.103),(.013,.138),(-.081,.095),(-.106,-.028)]
    slab('Broken_name_stone',outline,0,.044,STONE,.005)
    # Sculpted emblems mirror the established meanings without adding game rules.
    if id=='bel':
        for y in (-.03,.025):
            tube('Wave_glyph',[(-.060,y,.024),(-.025,y+.02,.027),(.016,y-.015,.027),(.06,y,.024)],.005,PALE)
    elif id=='rok':
        rod('Leaf_stem',(-.027,.073,.026),(.026,-.067,.026),.005,CORE)
        for sign in (-1,1):
            tube('Leaf_outline',[(0,-.07,.026),(sign*.05,-.025,.027),(sign*.035,.025,.027),(-.016,.055,.026)],.005,CORE)
    else:
        for i in range(3):
            y=(i-1)*.04
            tube('Mist_glyph',[(-.055,y,.025),(-.02,y+.013,.027),(.025,y+.013,.027),(.055,y,.025)],.004,VIOLET)

BUILDERS = {'glass_orb':lambda:orb(False),'crystal_core':lambda:orb(True),
    **{key:(lambda key=key:blueprint(key)) for key in ('bp_shotgun','bp_chainsaw','bp_automaton')},
    'part_ballistic':ballistic,'part_power':power,'ribbon_tie':ribbon,'star_pin':star_pin,
    'quilted_cape':cape,'cotton_gloves':lambda:gloves(False),'work_gloves':lambda:gloves(True),
    'sneakers':lambda:shoes(False),'leather_boots':lambda:shoes(True),
    'brass_brooch':lambda:brooch(False),'silver_brooch':lambda:brooch(True),'silver_ring':ring,
    'executioner_pulley':pulley,'self_replicating_spring':spring,
    **{key:(lambda key=key:potion(key)) for key in ('health_m','health_l','mana_s','mana_m','mana_l','rejuv_s','rejuv_m','rejuv_l','full_health','full_mana','full_rejuv','speed')},
    'currency':currency,**{key:(lambda key=key:piece(key)) for key in ('bel','rok','sha')}}

def bounds(obs):
    bpy.context.view_layer.update()
    points=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return lo,hi

RUNTIME_MATS={}
for kind in ('metal','matte','gem'):
    m=mat('runtime_'+kind,'ffffff',kind)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    vc=m.node_tree.nodes.new('ShaderNodeVertexColor')
    vc.layer_name='Color'
    m.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
    RUNTIME_MATS[kind]=m

records=[]
qa={}
for index,(id,builder) in enumerate(BUILDERS.items()):
    scene=bpy.context.scene if index==0 else bpy.data.scenes.new(id)
    scene.name=id
    bpy.context.window.scene=scene
    scene.unit_settings.system='METRIC'
    scene.unit_settings.scale_length=1
    builder()
    obs=[o for o in scene.objects if o.type=='MESH']
    lo,hi=bounds(obs)
    center=(lo+hi)/2
    # Keep the same 0.7m spacing contract as v1. All points fit a 0.33m disc.
    radius=max(Vector(((o.matrix_world@v.co-center).x,(o.matrix_world@v.co-center).y)).length for o in obs for v in o.data.vertices)
    scale=min(1,.325/radius)
    for o in obs:
        o.location=(o.location-center)*scale
        o.scale*=scale
        activate(o)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        # Every source part has a UV map for later texture refinement.
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.02)
        bpy.ops.object.mode_set(mode='OBJECT')
    lo,hi=bounds(obs)
    groups=sorted(set(o.get('qa_group','main') for o in obs))
    qa[id]={g:qa_check.run(objects=[o.name for o in obs if o.get('qa_group','main')==g],profile='game',eps=.0002,tol=.005) for g in groups}
    # Source parts stay separate/editable; only the transient export copy is joined.
    export_scene=bpy.data.scenes.new('Export_'+id)
    bpy.context.window.scene=export_scene
    copies=[]
    for o in obs:
        clone=o.copy(); clone.data=o.data.copy()
        export_scene.collection.objects.link(clone)
        material=o.data.materials[0]
        colors=clone.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='POINT')
        for entry in colors.data:
            entry.color=material.diffuse_color
        clone.data.materials.clear()
        clone.data.materials.append(RUNTIME_MATS[material['finish']])
        copies.append(clone)
    bpy.ops.object.select_all(action='DESELECT')
    for clone in copies: clone.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    runtime=bpy.context.object
    runtime.name='SM_'+id
    path=GAME/(id+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
        export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
    triangles=sum(len(p.vertices)-2 for p in runtime.data.polygons)
    record={'id':id,'source_parts':len(obs),'meshes':1,'materials':len(runtime.data.materials),'triangles':triangles,
        'dimensions_godot':[hi.x-lo.x,hi.z-lo.z,hi.y-lo.y],'rest_height':-lo.z+.012,
        'radius':radius*scale,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'qa_groups':groups}
    records.append(record)
    bpy.context.window.scene=scene
    bpy.data.objects.remove(runtime,do_unlink=True)
    bpy.data.scenes.remove(export_scene)
    print('BUILT',id,triangles,'errors',sum(len(v['errors']) for v in qa[id].values()),flush=True)
    (REPORT/'source_qa.json').write_text(json.dumps(qa,indent=2)+'\n',encoding='utf-8')

bpy.context.window.scene=bpy.data.scenes['glass_orb']
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'ground_loot_v2.blend'))
preserved=json.loads((ROOT/'assets/props/ground_loot_v1/models.json').read_text(encoding='utf-8'))['assets']
manifest={'blender':bpy.app.version_string,'source':'assets/props/ground_loot_v2/ground_loot_v2.blend',
    'assets':records,'preserved_v1':preserved,'total_new_triangles':sum(r['triangles'] for r in records),
    'notes':'Original authored static props from the selected inventory icons; source parts retained; vertex-color runtime meshes, <=3 opaque PBR surfaces.'}
(SOURCE/'models.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
profiles={r['id']:{'path':'res://assets/props/ground_loot_v1/'+r['id']+'.glb','rest_height':r['rest_height'],'dimensions':r['dimensions_godot']} for r in preserved}
profiles.update({r['id']:{'path':'res://assets/props/ground_loot_v2/'+r['id']+'.glb','rest_height':r['rest_height'],'dimensions':r['dimensions_godot']} for r in records})
(GAME/'models.json').write_text(json.dumps(profiles,indent=2)+'\n',encoding='utf-8')
print('GROUND_LOOT_V2_BUILT',len(records),'new,',len(profiles),'total')
