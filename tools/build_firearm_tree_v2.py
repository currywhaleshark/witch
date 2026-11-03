"""Live Blender MCP-safe firearm prop authoring. No scene reset or filesystem imports.

Send this file's code plus build_asset('id') through execute_blender_code. Each call
creates one NEW scene, keeping the user's scene and all earlier sources intact.
Coordinates in the recipe are Godot coordinates (Y up, -Z forward), metres.
These are fictional game props, with no working internal firearm mechanism.
"""
import bpy
import bmesh
import math
import json
from mathutils import Vector, Matrix

SOURCE = 'C:/Users/yurib/Documents/New project/witch/assets/weapons/firearm_tree_v2'
GAME = 'C:/Users/yurib/Documents/New project/witch/game/assets/weapons/firearm_tree_v2'
PALETTE = {
    'navy': ('293d50', .25, .49), 'brass': ('ae8250', .73, .39),
    'edge': ('d8b478', .72, .30), 'steel': ('424f58', .77, .37),
    'silver': ('9ba8aa', .82, .28), 'teal': ('2a8581', .35, .37),
    'core': ('79d8c4', .20, .25), 'wood': ('604237', .0, .69),
    'wood_light': ('7e5740', .0, .66), 'black': ('111c22', .25, .73),
    'rope': ('c2ab80', .0, .87), 'ember': ('f3a24b', .05, .55),
}

def V(p):
    return Vector((p[0], -p[2], p[1]))

def G(p):
    return [round(p.x, 6), round(p.z, 6), round(-p.y, 6)]

def material(key):
    name='M_FirearmV1_'+key
    m=bpy.data.materials.get(name)
    if m: return m
    hexcolor,metal,rough=PALETTE[key]
    c=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in c]
    m=bpy.data.materials.new(name); m.use_nodes=True
    m.diffuse_color=(*c,1)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal
    p.inputs['Roughness'].default_value=rough
    # Flat PBR values export identically; no procedural shader lost at export.
    return m

def active(o):
    for s in bpy.context.selected_objects: s.select_set(False)
    o.select_set(True); bpy.context.view_layer.objects.active=o

def make(name,vertices,faces,mat='brass',bevel=.002,group='body',delay=.12):
    me=bpy.data.meshes.new(name); me.from_pydata([V(v) for v in vertices],[],faces); me.update()
    clean=name.replace('-','neg').replace('.','p')
    ob=bpy.data.objects.new(bpy.context.scene['asset_id']+'__'+clean,me)
    bpy.context.scene.collection.objects.link(ob)
    ob['motion_group']=group; ob['assembly_delay']=delay; ob['part_role']=name
    me.materials.append(material(mat)); active(ob)
    bm=bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(me); bm.free()
    # UV before bevel; surfaces remain editable and the applied bevel has stable UVs.
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.1,island_margin=.02)
    bpy.ops.object.mode_set(mode='OBJECT')
    if bevel:
        mod=ob.modifiers.new('Machined_edge','BEVEL'); mod.width=bevel; mod.segments=2
        mod.use_clamp_overlap=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for face in me.polygons: face.use_smooth=True
    mod=ob.modifiers.new('Weighted_normals','WEIGHTED_NORMAL'); mod.keep_sharp=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Centre each rigid part. Pivots for coupled groups are recorded explicitly below.
    lo=Vector(tuple(min(v.co[i] for v in me.vertices) for i in range(3)))
    hi=Vector(tuple(max(v.co[i] for v in me.vertices) for i in range(3)))
    center=(lo+hi)/2; me.transform(Matrix.Translation(-center)); ob.location=center
    ob.select_set(False)
    return ob

def box(name,p,size,mat='navy',bevel=.004,group='body',delay=.12):
    x,y,z=p; a,b,c=[s/2 for s in size]
    verts=[(x+u*a,y+v*b,z+w*c) for u,v,w in
           [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
    return make(name,verts,[(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3),(0,1,3,2),(4,6,7,5)],mat,bevel,group,delay)

def axial(name,profile,p=(0,0,0),axis=(0,0,1),mat='steel',segments=20,closed=False,bevel=.001,group='body',delay=.22):
    # Solid of revolution; closed profile makes a proper annular hollow tube.
    n=Vector(axis).normalized(); u=n.cross(Vector((0,1,0)) if abs(n.y)<.9 else Vector((0,0,1))).normalized(); v=n.cross(u)
    center=Vector(p)
    verts=[tuple(center+n*d+r*(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments)))
           for d,r in profile for i in range(segments)]
    faces=[]
    for j in range(len(profile) if closed else len(profile)-1):
        k=(j+1)%len(profile)
        for i in range(segments):
            ni=(i+1)%segments; faces.append((j*segments+i,j*segments+ni,k*segments+ni,k*segments+i))
    if not closed:
        faces += [tuple(reversed(range(segments))),tuple(range((len(profile)-1)*segments,len(profile)*segments))]
    return make(name,verts,faces,mat,bevel,group,delay)

def cylinder(name,p,radius,length,mat='brass',axis=(0,1,0),segments=16,group='body',delay=.2):
    return axial(name,[(-length/2,radius),(length/2,radius)],p,axis,mat,segments,False,.0015,group,delay)

def ring(name,p,radius,thickness,length=.025,mat='brass',axis=(0,0,1),segments=24,group='body',delay=.25):
    return axial(name,[(-length/2,radius),(length/2,radius),(length/2,radius-thickness),(-length/2,radius-thickness)],p,axis,mat,segments,True,.001,group,delay)

def tube(name,points,radius,mat='brass',sides=8,group='body',delay=.25):
    pts=[Vector(p) for p in points]; verts=[]; faces=[]
    for j,p in enumerate(pts):
        n=(pts[min(j+1,len(pts)-1)]-pts[max(0,j-1)]).normalized()
        u=n.cross(Vector((0,1,0)) if abs(n.y)<.9 else Vector((0,0,1))).normalized(); v=n.cross(u)
        verts += [tuple(p+radius*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides))) for i in range(sides)]
    for j in range(len(pts)-1):
        for i in range(sides):
            a=j*sides+i; b=j*sides+(i+1)%sides; faces.append((a,b,b+sides,a+sides))
    faces += [tuple(reversed(range(sides))),tuple(range((len(pts)-1)*sides,len(pts)*sides))]
    return make(name,verts,faces,mat,0,group,delay)

def side_shape(name,outline,width,mat='wood',x=0,group='body',delay=.02):
    n=len(outline)
    verts=[(x+s*width/2,y,z) for s in (-1,1) for y,z in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return make(name,verts,faces,mat,.004,group,delay)

def bolt(name,p,radius=.015,axis=(1,0,0),group='body'):
    return cylinder(name,p,radius,.012,'silver',axis,6,group,.34)

def socket(name,p,axis=(0,0,-1)):
    ob=bpy.data.objects.new(bpy.context.scene['asset_id']+'__Socket_'+name,None); bpy.context.scene.collection.objects.link(ob)
    ob.location=V(p); ob.rotation_euler=V(axis).to_track_quat('Y','Z').to_euler()
    ob.empty_display_type='ARROWS'; ob.empty_display_size=.06
    ob['godot_axis']=list(axis); return ob

def band_bolts(prefix,x,y,z,count=4,r=.085,group='body'):
    for i in range(count):
        a=math.tau*i/count
        bolt(prefix+str(i),(x+r*math.cos(a),y+r*math.sin(a),z),.009,(0,0,1),group)

def object_name(ob):
    return ob.name

def unwrap_face_tiles(me):
    # Small bent match cord: isolated planar face charts avoid export triangulation overlap.
    bm=bmesh.new(); bm.from_mesh(me)
    bmesh.ops.triangulate(bm,faces=[face for face in bm.faces if len(face.verts)>3])
    bm.to_mesh(me); bm.free(); me.update()
    uv=me.uv_layers.active
    columns=math.ceil(math.sqrt(len(me.polygons)))
    for i,face in enumerate(me.polygons):
        loops=list(face.loop_indices)
        coords=[me.vertices[me.loops[index].vertex_index].co for index in loops]
        u=(coords[1]-coords[0]).normalized()
        v=face.normal.cross(u).normalized()
        points=[(p.dot(u),p.dot(v)) for p in coords]
        lo=(min(p[0] for p in points),min(p[1] for p in points))
        hi=(max(p[0] for p in points),max(p[1] for p in points))
        for loop_index,p in zip(loops,points):
            uv.data[loop_index].uv=((i%columns+.12+.76*(p[0]-lo[0])/max(hi[0]-lo[0],1e-8))/columns,
                                    (i//columns+.12+.76*(p[1]-lo[1])/max(hi[1]-lo[1],1e-8))/columns)


# Recipes below use the v1 primitive helpers, copied above by the packaging step.
# Whole-object nonuniform runtime scaling is deliberately not used.

def matchlock():
    side_shape('walnut_stock',[(-.045,.42),(-.035,.88),(-.022,1.02),(-.026,1.20),(-.155,1.37),(-.183,1.35),(-.12,1.0),(-.103,.43)],.078)
    axial('long_barrel',[(0,.044),(.024,.046),(.045,.033),(.86,.033),(.86,.021),(.014,.025)],mat='steel',closed=True,segments=20,delay=.32)
    ring('muzzle_lip',(0,0,.014),.049,.014,.028,'brass',delay=.42)
    for i,z in enumerate((.25,.57,.82)):
        ring('barrel_band_'+str(i),(0,-.012,z),.050,.011,.026,'brass')
    box('breech',(0,-.010,.92),(.097,.087,.19),'brass')
    box('side_plate',(.052,-.020,.93),(.012,.067,.22),'navy')
    tube('serpentine_match_arm',[(.061,-.030,1.02),(.065,.025,1.005),(.064,.055,.95),(.064,.079,.90)],.0105,'brass',group='match_arm')
    tube('match_cord',[(.064,.088,.91),(.075,.055,.86),(.071,.026,.846)],.006,'rope',group='match_arm',delay=.46)
    cylinder('match_tip',(.071,.024,.846),.007,.012,'ember',(0,1,0),10,'match_arm',.48)
    cylinder('pan',(.071,.002,.855),.023,.014,'brass',(0,1,0),12)
    for i,z in enumerate((.85,1.00)): bolt('plate_screw_'+str(i),(.063,-.020,z),.009)
    side_shape('butt_cap',[(-.030,1.350),(-.039,1.398),(-.169,1.390),(-.190,1.350)],.084,'brass',delay=.30)
    tube('guard',[(0,-.095,.95),(0,-.15,.96),(0,-.15,1.09),(0,-.10,1.105)],.008,'brass')
    tube('underbarrel_rod',[(-.028,-.063,.16),(-.028,-.063,.72)],.006,'wood_light')
    box('power_seal',(-.043,-.040,.985),(.008,.042,.065),'teal',.002,delay=.46)
    socket('muzzle',(0,0,0));socket('ignition',(.071,.024,.846));socket('ornament',(0,-.14,1.05))

def rifle():
    side_shape('navy_stock',[(-.034,.65),(-.027,1.14),(-.055,1.29),(-.065,1.59),(-.18,1.59),(-.17,1.44),(-.095,1.18),(-.096,.65)],.09,'navy')
    axial('precision_barrel',[(0,.037),(.035,.040),(.085,.030),(1.02,.032),(1.02,.020),(.014,.018)],closed=True,segments=16,delay=.29)
    ring('muzzle_crown',(0,0,.015),.043,.016,.030,'silver',segments=16,delay=.42)
    for i,z in enumerate((.43,.76)):
        ring('floating_barrel_brace_'+str(i),(0,-.008,z),.047,.013,.031,'brass',segments=16)
    box('receiver',(0,-.012,1.075),(.113,.088,.27),'steel')
    box('breech_cover',(0,.033,1.07),(.092,.020,.22),'brass')
    for x in (-.051,.051):
        tube('foregrip_trim_'+str(x),[(x,-.055,.65),(x,-.055,1.15),(x,-.095,1.26)],.005,'brass')
    for i,z in enumerate((.94,1.17)):
        box('optic_pedestal_'+str(i),(0,.052,z),(.037,.048,.042),'brass')
    axial('optic_tube',[(0,.040),(.024,.040),(.024,.025),(.33,.025),(.354,.034),(.38,.034)],(0,.097,.87),mat='navy',segments=16,delay=.38)
    cylinder('optic_front_lens',(0,.097,.866),.033,.008,'teal',(0,0,1),16,delay=.43)
    cylinder('optic_back_lens',(0,.097,1.254),.028,.008,'black',(0,0,1),16,delay=.43)
    tube('bolt_handle',[(.05,-.005,1.145),(.097,-.007,1.145),(.111,-.035,1.155)],.009,'silver',group='bolt')
    cylinder('bolt_knob',(.111,-.041,1.155),.017,.025,'navy',(0,1,0),12,'bolt')
    side_shape('butt_plate',[(-.060,1.572),(-.065,1.620),(-.185,1.620),(-.190,1.572)],.097,'brass',delay=.30)
    tube('trigger_guard',[(0,-.10,1.16),(0,-.16,1.19),(0,-.16,1.29),(0,-.10,1.31)],.007,'brass')
    box('charge_inlay',(-.061,-.010,1.10),(.010,.036,.10),'teal',.002,delay=.45)
    for i,z in enumerate((.98,1.18)):bolt('receiver_screw_'+str(i),(.063,-.012,z),.009)
    socket('muzzle',(0,0,0));socket('ejection',(.069,.010,1.075));socket('ornament',(0,-.145,1.37))

def shotgun():
    for i,x in enumerate((-.060,.060)):
        axial('scatter_barrel_'+str(i),[(0,.050),(.022,.053),(.15,.045),(.61,.043),(.61,.030),(.014,.031)],(x,0,0),closed=True,segments=20,delay=.30+i*.025)
        ring('scatter_lip_'+str(i),(x,0,.014),.057,.017,.024,'brass',delay=.42)
    box('barrel_bridge',(0,.020,.34),(.040,.050,.43),'brass',delay=.26)
    box('receiver',(0,-.015,.675),(.210,.130,.18),'navy',.010)
    box('receiver_top',(0,.056,.675),(.180,.018,.15),'brass',.005)
    side_shape('short_stock',[(-.038,.72),(-.030,.86),(-.040,1.06),(-.160,1.10),(-.182,1.04),(-.110,.78)],.123,'navy')
    side_shape('stock_plate',[(-.044,1.054),(-.045,1.100),(-.164,1.132),(-.189,1.080)],.132,'brass',delay=.31)
    box('lower_handguard',(0,-.068,.39),(.150,.048,.42),'wood',.008)
    for i,z in enumerate((.23,.33,.43,.53)):
        box('grip_rib_'+str(i),(0,-.095,z),(.13,.008,.019),'brass',.002)
    for side in (-1,1):
        cylinder('hinge_'+str(side),(side*.112,-.015,.68),.034,.014,'brass',(1,0,0),16)
        bolt('hinge_bolt_'+str(side),(side*.121,-.015,.68),.014)
    tube('trigger_guard',[(0,-.085,.735),(0,-.150,.77),(0,-.150,.89),(0,-.110,.91)],.008,'brass')
    box('core_inlay',(0,.067,.675),(.060,.008,.058),'teal',.002,delay=.47)
    socket('muzzle',(0,0,0));socket('barrel_left',(-.060,0,0));socket('barrel_right',(.060,0,0));socket('ornament',(0,-.17,.84))

def build_asset(asset_id):
    assert asset_id in ['matchlock','rifle','shotgun']
    name='FirearmV2_'+asset_id
    assert bpy.data.scenes.get(name) is None, 'Preserve existing scenes; review revisions explicitly.'
    scene=bpy.data.scenes.new(name); bpy.context.window.scene=scene
    scene['asset_id']='v2_'+asset_id;scene['runtime_id']=asset_id
    scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    scene.render.engine='BLENDER_EEVEE';scene.view_settings.view_transform='AgX'
    scene.world=bpy.data.worlds.new('World_'+name);scene.world.color=(.12,.12,.12)
    if asset_id=='matchlock':matchlock()
    elif asset_id=='rifle':rifle()
    else:shotgun()
    finalize_asset(asset_id)

def finalize_asset(asset_id):
    scene=bpy.data.scenes['FirearmV2_'+asset_id];bpy.context.window.scene=scene
    bpy.context.view_layer.update()
    meshes=[ob for ob in scene.objects if ob.type=='MESH']
    info={'id':asset_id,'version':2,'blender_scene':scene.name,'forward':[0,0,-1],'up':[0,1,0],
          'parts':[],'sockets':{},'triangles':0,'materials':[],'units':'metres'}
    points=[]
    for ob in sorted(meshes,key=object_name):
        if asset_id=='matchlock' and ob['part_role']=='match_cord':unwrap_face_tiles(ob.data)
        ob.data.calc_loop_triangles(); count=len(ob.data.loop_triangles);info['triangles']+=count
        points += [ob.matrix_world@v.co for v in ob.data.vertices]
        info['parts'].append({'name':ob.name,'role':ob['part_role'],'group':ob['motion_group'],
                              'delay':ob['assembly_delay'],'triangles':count,'origin':G(ob.location)})
    for ob in scene.objects:
        if ob.type=='EMPTY':info['sockets'][ob.name.split('__')[-1]]={'position':G(ob.location),'direction':list(ob['godot_axis'])}
    info['materials']=sorted({m.name for ob in meshes for m in ob.data.materials})
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    info['dimensions']=[round(hi.x-lo.x,5),round(hi.z-lo.z,5),round(hi.y-lo.y,5)]
    info['aabb_godot']={'min':[round(lo.x,6),round(lo.z,6),round(-hi.y,6)],'max':[round(hi.x,6),round(hi.z,6),round(-lo.y,6)]}
    info['part_count']=len(meshes)
    scene['manifest_json']=json.dumps(info,indent=2)
    for ob in scene.objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.export_scene.gltf(filepath=GAME+'/'+asset_id+'.glb',export_format='GLB',use_selection=True,
        use_active_scene=True,export_animations=False,export_skins=False,export_extras=True,
        export_yup=True,export_cameras=False,export_lights=False)
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/firearm_tree_v2.blend')
    print('FIREARM_V2 '+json.dumps(info))
