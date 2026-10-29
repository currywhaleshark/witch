"""Author a modular staff in an isolated Blender process. No existing asset is edited."""
import bpy
import bmesh
import json
import math
import hashlib
import shutil
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / 'assets/weapons/staff_transform_v1'
GAME = ROOT / 'game/assets/weapons/staff_transform_v1'
REPORT = ROOT / 'reports/staff_transform_v1'
for folder in (ASSET / 'authoring', ASSET / 'exports', GAME, REPORT):
    folder.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.render.fps = 24

def material(name, color, metal=.0, rough=.5, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

M = {
    'navy': material('Enamel_Navy', (.034, .065, .110), .28, .40),
    'brass': material('Aged_Brass', (.48, .31, .135), .42, .49),
    'edge': material('Brass_Edge', (.70, .49, .22), .48, .38),
    'steel': material('Cutting_Steel', (.45, .55, .61), .48, .32),
    'dark': material('Oiled_Steel', (.06, .08, .095), .36, .50),
    'grip': material('Navy_Grip', (.015, .025, .041), .04, .78),
    'core': material('Teal_Core', (.10, .64, .51), .26, .25, .8),
}
groups = {}
records = []

def xyz(v):
    # Author in the runtime's +Y-up staff coordinates, then map to Blender Z-up.
    return (v[0], -v[2], v[1])

def root(name):
    obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    groups[name] = obj
    return obj

for group in ('common', 'bolt_cutter', 'grinder', 'chainsaw', 'ornament_seal'):
    root(group)

def finish(obj, mat, bevel=0):
    obj.data.materials.append(M[mat])
    if bevel:
        mod = obj.modifiers.new('Machined_edge', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def box(pos, size, mat, bevel=.002):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(pos))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, bevel)

def cylinder(pos, radius, length, mat, axis='y', vertices=16, top=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if top is None else top, depth=length, location=xyz(pos))
    obj = bpy.context.object
    direction = Vector(xyz({'x':(1,0,0), 'y':(0,1,0), 'z':(0,0,1)}[axis]))
    obj.rotation_mode='QUATERNION'
    obj.rotation_quaternion = Vector((0,0,1)).rotation_difference(direction)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, mat, 0)

def polygon(points, depth, mat):
    # Extruded polygon in runtime X/Y, thickness along Z.
    verts = [xyz((x,y,z)) for z in (-depth/2,depth/2) for x,y in points]
    n=len(points)
    faces=[tuple(range(n-1,-1,-1)), tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new('Profile');mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('Profile',mesh);scene.collection.objects.link(obj)
    return finish(obj,mat,.001)

def ring(pos, outer, inner, depth, mat, start=0, end=math.tau, steps=32):
    verts=[]
    for i in range(steps+1):
        a=start+(end-start)*i/steps
        for r,z in ((outer,-depth/2),(inner,-depth/2),(outer,depth/2),(inner,depth/2)):
            verts.append(xyz((pos[0]+r*math.cos(a),pos[1]+r*math.sin(a),pos[2]+z)))
    faces=[]
    for i in range(steps):
        a=i*4;b=a+4
        faces.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
    faces.extend([(0,1,3,2),(steps*4,steps*4+2,steps*4+3,steps*4+1)])
    mesh=bpy.data.meshes.new('Ring');mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('Ring',mesh);scene.collection.objects.link(obj)
    return finish(obj,mat)

def gear(pos, radius, mat, teeth=12, depth=.018):
    shapes=[cylinder(pos,radius*.84,depth,mat,'z',24)]
    for i in range(teeth):
        a=math.tau*i/teeth
        o=box((pos[0]+radius*.91*math.cos(a),pos[1]+radius*.91*math.sin(a),pos[2]),
              (radius*.22,radius*.28,depth),mat,.0008)
        o.rotation_euler.y=-a
        shapes.append(o)
    shapes.append(cylinder((pos[0],pos[1],pos[2]-.012),radius*.20,.022,'edge','z',12))
    return shapes

def part(name, group, objects, pivot, delay=0, driver='', **extra):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1:bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name;obj.data.name=name+'_mesh'
    scene.cursor.location=xyz(pivot)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    obj.parent=groups[group]
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data);bm.free()
    # Vertex normals are explicitly flat on broad machined faces; bevels catch light.
    for f in obj.data.polygons:f.use_smooth=False
    obj['assembly_group']=group;obj['assembly_delay']=delay
    rec={'name':name,'group':group,'delay':delay,'driver':driver,'pivot':list(pivot)}
    rec.update(extra);records.append(rec)
    return obj

# The complete sliding grip remains a 10 mm radius shaft. No large ornament enters it.
part('shaft','common',[cylinder((0,.055,0),.010,1.03,'navy',vertices=20)],(0,.055,0))
part('grip_sleeve','common',[cylinder((0,-.035,0),.0108,.77,'grip',vertices=20)],(0,-.035,0))
part('pommel','common',[cylinder((0,-.455,0),.013,.022,'brass',top=.010),
    cylinder((0,-.47,0),.009,.01,'edge')],(0,-.455,0))
part('upper_ferrule','common',[cylinder((0,.405,0),.017,.028,'brass'),
    cylinder((0,.423,0),.019,.010,'edge')],(0,.41,0))
part('ornament_mount','common',[cylinder((0,.465,0),.024,.065,'navy',vertices=12),
    cylinder((0,.443,0),.026,.009,'brass'),cylinder((0,.49,0),.027,.012,'edge')],(0,.465,0))
part('core_receiver','common',[cylinder((0,.565,0),.035,.14,'brass',vertices=12,top=.047),
    cylinder((0,.61,0),.052,.025,'navy',vertices=12),cylinder((0,.63,0),.053,.014,'edge')],(0,.565,0))
part('teal_core','common',[cylinder((0,.713,0),.034,.145,'core',vertices=8,top=.027)],(0,.713,0))
cage=[]
for x in (-1,1):
    cage.append(polygon([(x*.049,.64),(x*.061,.70),(x*.043,.79),(x*.026,.807),
                         (x*.022,.789),(x*.043,.70),(x*.033,.65)],.025,'brass'))
cage.extend([cylinder((0,.80,0),.027,.014,'edge',vertices=12),
             cylinder((0,.817,0),.017,.023,'navy',vertices=8,top=.003)])
part('core_cage','common',cage,(0,.72,0))
part('receiver_ports','common',[cylinder((x,.605,0),.014,.020,'dark','x',12) for x in (-.05,.05)],(0,.605,0))

# Bolt cutter: split compound-leverage arms, pivots and forged jaws.
part('cutter_saddle','bolt_cutter',[box((0,.65,.034),(.16,.10,.060),'navy',.008),
    box((0,.613,.036),(.13,.018,.069),'edge')],(0,.65,.034),0)
for side in (-1,1):
    tag='l' if side<0 else 'r'
    part('cutter_link_'+tag,'bolt_cutter',[polygon([(side*.022,.64),(side*.085,.71),
        (side*.077,.79),(side*.049,.80),(side*.045,.72),(side*.01,.67)],.035,'brass')],
        (side*.046,.70,0),.10)
    shapes=[polygon([(side*.055,.74),(side*.095,.79),(side*.105,.94),(side*.071,1.005),
        (side*.012,1.028),(side*.008,.990),(side*.053,.958),(side*.062,.86),(side*.025,.80)],.055,'dark'),
        polygon([(side*.071,1.005),(side*.012,1.028),(side*.008,.990),(side*.053,.958)],.058,'steel'),
        cylinder((side*.053,.787,-.035),.025,.017,'edge','z',12)]
    part('cutter_jaw_'+tag,'bolt_cutter',shapes,(side*.053,.787,0),.22,'jaw',side=side)
part('cutter_drive','bolt_cutter',gear((0,.70,-.049),.035,'steel',10,.018),(0,.70,-.049),.15,'drive')
part('cutter_lock','bolt_cutter',[box((0,.667,-.05),(.06,.021,.016),'edge'),
    cylinder((0,.667,-.064),.009,.01,'core','z',8)],(0,.667,-.05),.32)

# Grinder: motor, gearbox, independent disc and protective half shroud.
part('grinder_mount','grinder',[box((0,.64,.02),(.12,.09,.095),'navy',.007),
    cylinder((0,.62,-.04),.044,.028,'brass','z',12)],(0,.64,.02),0)
part('grinder_motor','grinder',[cylinder((0,.72,.055),.062,.12,'navy','y',12),
    cylinder((0,.78,.055),.067,.018,'brass','y',12),
    *[box((x,.71,.112),(.008,.07,.008),'brass',.0008) for x in (-.03,0,.03)]],(0,.72,.055),.10)
part('grinder_axle','grinder',[cylinder((0,.80,0),.037,.15,'brass','z',12),
    cylinder((0,.80,-.047),.05,.025,'dark','z',16)],(0,.80,0),.17)
disc=[ring((0,.80,-.07),.158,.115,.018,'steel',steps=40),
      cylinder((0,.80,-.07),.116,.014,'dark','z',40)]
for i in range(8):
    a=i*math.tau/8
    o=box((.085*math.cos(a),.80+.085*math.sin(a),-.081),(.061,.009,.005),'steel',.001)
    o.rotation_euler.y=-a;disc.append(o)
disc.append(cylinder((0,.80,-.088),.025,.021,'edge','z',8))
part('grinder_disc','grinder',disc,(0,.80,-.07),.23,'disc')
part('grinder_guard','grinder',[ring((0,.80,-.04),.175,.155,.073,'navy',0,math.pi*1.1,24),
    ring((0,.80,-.080),.178,.170,.008,'brass',0,math.pi*1.1,24)],(0,.80,-.04),.30)
part('grinder_status','grinder',[box((.049,.67,-.04),(.012,.036,.009),'core')],(.049,.67,-.04),.36)

# Chainsaw: detachable motor and two guide plates; teeth travel on an actual capsule path.
part('saw_motor','chainsaw',[box((0,.64,.035),(.145,.14,.12),'navy',.012),
    box((0,.594,.034),(.15,.018,.125),'edge'),
    *[box((x,.65,-.032),(.008,.07,.008),'brass',.001) for x in (-.045,-.022,0,.022,.045)]],(0,.64,.035),0)
part('saw_gear','chainsaw',gear((0,.71,-.05),.059,'brass',12,.027),(0,.71,-.05),.09,'drive')
for z in (-.023,.023):
    # Rounded guide outline is a single closed extrusion.
    pts=[]
    for i in range(13):
        a=math.pi*i/12
        pts.append((.058*math.cos(a),1.04+.058*math.sin(a)))
    for i in range(13):
        a=math.pi+math.pi*i/12
        pts.append((.058*math.cos(a),.77+.058*math.sin(a)))
    obj=polygon(pts,.009,'steel');obj.location.y=-z
    part('saw_guide_'+('front' if z<0 else 'back'),'chainsaw',[obj],(0,.90,z),.18)
part('saw_spine','chainsaw',[box((0,.905,0),(.077,.277,.035),'dark',.007),
    box((0,.91,-.03),(.018,.18,.008),'navy'),box((0,.91,-.036),(.007,.11,.005),'core')],(0,.9,0),.13)

def chain_point(t):
    r=.069;lo=.77;hi=1.04;leg=hi-lo;arc=math.pi*r;length=2*leg+2*arc
    s=(t%1)*length
    if s<leg:return (r,lo+s,0),0.0
    s-=leg
    if s<arc:
        a=s/r;return (r*math.cos(a),hi+r*math.sin(a),0),a
    s-=arc
    if s<leg:return (-r,hi-s,0),math.pi
    a=math.pi+(s-leg)/r
    return (r*math.cos(a),lo+r*math.sin(a),0),a

for i in range(22):
    p,a=chain_point(i/22)
    tooth=box(p,(.017,.024,.050),'steel',.002)
    tooth.rotation_euler.y=-a
    part('saw_tooth_%02d'%i,'chainsaw',[tooth],p,.24+i%4*.025,'chain',phase=i/22)
part('saw_nose','chainsaw',[cylinder((0,1.04,0),.030,.062,'brass','z',16)],(0,1.04,0),.31)

# One optional neutral seal proves that cosmetic equipment survives every tool switch.
part('seal_plate','ornament_seal',[polygon([(-.032,.488),(0,.515),(.032,.488),(.032,.454),(0,.433),(-.032,.454)],
    .008,'brass')],(0,.474,0),0)
groups['ornament_seal'].location=xyz((0,0,-.036))
part('seal_inlay','ornament_seal',[box((0,.475,-.007),(.024,.037,.006),'navy'),
    cylinder((0,.475,-.013),.008,.006,'core','z',6)],(0,.475,-.007),0)

scene['description']='Modular machinery staff: common body, 3 generated tool modules, optional mediator seal.'
scene['grip_contract']='player_humanoid_v11 / run_arm_v21, +Y staff, unchanged bone offset/basis/slide'
scene['art_status']='review_candidate'
scene['authoring_source']='Original parametric hard-surface asset; not Tripo generated.'

# All groups remain inspectable in the source; export selection contains the complete family.
bpy.ops.object.select_all(action='SELECT')
source=ASSET/'authoring/staff_transform_v1.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
export=ASSET/'exports/staff_parts.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,
    export_animations=False,export_extras=True,export_yup=True)
shutil.copy2(export,GAME/export.name)
metrics={}
for group,parent in groups.items():
    meshes=[o for o in parent.children if o.type=='MESH']
    tris=0
    for o in meshes:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
    metrics[group]={'parts':len(meshes),'triangles':tris}
config={'version':1,'asset':'res://assets/weapons/staff_transform_v1/staff_parts.glb',
    'axis':'+Y','grip_radius_m':.010,'reserved_grip_y':[-.43,.38],
    'assembly_seconds':.22,'dissolve_seconds':.16,'parts':records,'metrics':metrics,
    'sockets':{'mediator_seal':{'position':[0,.474,-.036],'max_half_extent':[.04,.045,.025],
        'exclusive_to_tools':False},'future_side_l':{'position':[-.04,.525,0]},
        'future_side_r':{'position':[.04,.525,0]}},
    'appearance_profiles':{'basic':[], 'seal':['ornament_seal']},
    'policy':'Common shaft/core and equipment ornaments persist; skill tool modules assemble independently. No equipment UI or stats.'}
for out in (ASSET/'parts.json',GAME/'parts.json'):out.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
build={'passed':True,'blender':bpy.app.version_string,'metrics':metrics,
    'asset_sha256':hashlib.sha256(export.read_bytes()).hexdigest(),
    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'materials':len(M),
    'scope':'Original rigid modular meshes. No new character geometry, rig, clips or gameplay changes.'}
(REPORT/'build.json').write_text(json.dumps(build,indent=2)+'\n',encoding='utf-8')
print('STAFF_BUILD_COMPLETE '+json.dumps(build))
