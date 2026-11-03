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

SOURCE = 'C:/Users/yurib/Documents/New project/witch/assets/weapons/firearm_tree_v1'
GAME = 'C:/Users/yurib/Documents/New project/witch/game/assets/weapons/firearm_tree_v1'
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

def matchlock():
    # Long, simple stock and a visible S-shaped match arm distinguish tier I.
    side_shape('walnut_stock',[(-.06,.29),(-.045,.67),(-.025,.80),(-.03,.93),(-.23,1.05),(-.27,1.02),(-.16,.78),(-.14,.30)],.105)
    axial('long_barrel',[(0,.060),(.024,.062),(.045,.046),(.62,.045),(.62,.028),(.014,.034)],mat='steel',closed=True,segments=20,delay=.32)
    ring('muzzle_lip',(0,0,.014),.065,.016,.028,'brass',delay=.42)
    for i,z in enumerate((.19,.43,.60)):
        ring('barrel_band_'+str(i),(0,-.018,z),.068,.014,.035,'brass')
    box('breech',(0,-.015,.68),(.13,.115,.18),'brass')
    box('side_plate',(.067,-.025,.69),(.018,.091,.22),'navy')
    tube('serpentine_match_arm',[(.082,-.045,.78),(.087,.035,.77),(.086,.075,.70),(.085,.11,.65)],.014,'brass',group='match_arm')
    tube('match_cord',[(.086,.12,.66),(.10,.08,.60),(.095,.035,.59)],.008,'rope',group='match_arm',delay=.46)
    cylinder('match_tip',(.095,.032,.59),.009,.015,'ember',(0,1,0),10,'match_arm',.48)
    cylinder('pan',(.091,.006,.61),.029,.018,'brass',(0,1,0),12)
    for i,z in enumerate((.62,.76)): bolt('plate_screw_'+str(i),(.081,-.02,z),.013)
    side_shape('butt_cap',[(-.045,1.015),(-.055,1.07),(-.25,1.055),(-.275,1.015)],.113,'brass',delay=.30)
    tube('guard',[(0,-.13,.69),(0,-.22,.70),(0,-.22,.82),(0,-.15,.84)],.011,'brass')
    tube('underbarrel_rod',[(-.038,-.086,.11),(-.038,-.086,.52)],.009,'wood_light')
    box('power_seal',(-.058,-.060,.76),(.012,.058,.065),'teal',.002,delay=.46)
    socket('muzzle',(0,0,0)); socket('ignition',(.095,.03,.59)); socket('ornament',(0,-.19,.78))

def rifle():
    side_shape('navy_stock',[(-.045,.49),(-.035,.91),(-.08,1.05),(-.08,1.28),(-.27,1.28),(-.24,1.12),(-.14,.97),(-.13,.49)],.12,'navy')
    axial('precision_barrel',[(0,.047),(.035,.051),(.085,.038),(.78,.041),(.78,.026),(.014,.025)],closed=True,segments=16,delay=.29)
    ring('muzzle_crown',(0,0,.015),.055,.020,.03,'silver',segments=16,delay=.42)
    for i,z in enumerate((.34,.57)):
        ring('floating_barrel_brace_'+str(i),(0,-.006,z),.063,.013,.042,'brass',segments=16)
    box('receiver',(0,-.012,.83),(.15,.12,.30),'steel')
    box('breech_cover',(0,.042,.82),(.12,.024,.22),'brass')
    for x in (-.072,.072):
        tube('foregrip_trim_'+str(x),[(x,-.075,.49),(x,-.075,.92),(x,-.13,1.02)],.007,'brass')
    for i,z in enumerate((.68,.89)):
        box('optic_pedestal_'+str(i),(0,.094,z),(.047,.13,.050),'brass')
    axial('optic_tube',[(0,.053),(.028,.053),(.028,.034),(.29,.034),(.32,.046),(.34,.046)],(0,.169,.60),mat='navy',segments=16,delay=.38)
    cylinder('optic_front_lens',(0,.169,.596),.044,.009,'teal',(0,0,1),16,delay=.43)
    cylinder('optic_back_lens',(0,.169,.944),.037,.009,'black',(0,0,1),16,delay=.43)
    tube('bolt_handle',[(.066,0,.89),(.125,-.005,.89),(.145,-.045,.90)],.012,'silver',group='bolt')
    cylinder('bolt_knob',(.145,-.05,.90),.024,.035,'navy',(0,1,0),12,'bolt')
    side_shape('butt_plate',[(-.078,1.265),(-.080,1.302),(-.27,1.302),(-.28,1.265)],.128,'brass',delay=.30)
    tube('trigger_guard',[(0,-.135,.90),(0,-.225,.92),(0,-.225,1.02),(0,-.14,1.04)],.009,'brass')
    box('charge_inlay',(-.079,-.014,.85),(.012,.050,.12),'teal',.002,delay=.45)
    for i,z in enumerate((.74,.95)): bolt('receiver_screw_'+str(i),(.082,-.020,z),.011)
    socket('muzzle',(0,0,0)); socket('ejection',(.09,.015,.82)); socket('ornament',(0,-.20,1.11))

def shotgun():
    # Short paired barrels, heavy squared receiver and a saddle-shaped stock.
    for i,x in enumerate((-.086,.086)):
        axial('scatter_barrel_'+str(i),[(0,.074),(.038,.079),(.15,.064),(.39,.059),(.39,.039),(.018,.050)],(x,0,0),closed=True,segments=20,delay=.30+i*.025)
        ring('scatter_lip_'+str(i),(x,0,.019),.082,.025,.032,'brass',delay=.42)
    box('barrel_bridge',(0,.025,.22),(.060,.076,.27),'brass',delay=.26)
    box('receiver',(0,-.015,.45),(.28,.18,.20),'navy',.014)
    box('receiver_top',(0,.080,.45),(.235,.025,.17),'brass',.006)
    side_shape('short_stock',[(-.05,.49),(-.04,.61),(-.06,.76),(-.24,.79),(-.27,.74),(-.15,.55)],.17,'navy')
    side_shape('stock_plate',[(-.064,.748),(-.064,.785),(-.24,.813),(-.27,.77)],.18,'brass',delay=.31)
    box('lower_handguard',(0,-.10,.24),(.20,.07,.27),'wood',.012)
    for i,z in enumerate((.15,.22,.29,.36)):
        box('grip_rib_'+str(i),(0,-.14,z),(.17,.012,.019),'brass',.003)
    for side in (-1,1):
        cylinder('hinge_'+str(side),(side*.149,-.02,.46),.048,.018,'brass',(1,0,0),16)
        bolt('hinge_bolt_'+str(side),(side*.162,-.02,.46),.020)
    tube('trigger_guard',[(0,-.12,.49),(0,-.22,.52),(0,-.22,.63),(0,-.16,.65)],.012,'brass')
    box('core_inlay',(0,.098,.45),(.08,.012,.08),'teal',.003,delay=.47)
    socket('muzzle',(0,0,0)); socket('barrel_left',(-.086,0,0)); socket('barrel_right',(.086,0,0)); socket('ornament',(0,-.23,.58))

def powder_barrel():
    # Horizontal drum: axle X, bottom Y=0. Staves are individual burst pieces.
    center=Vector((0,.245,0)); length=.45; n=12
    for i in range(n):
        a0=math.tau*i/n+.007; a1=math.tau*(i+1)/n-.007
        verts=[]
        for x,r in ((-length/2,.207),(-.14,.229),(.14,.229),(length/2,.207)):
            for a in (a0,a1): verts.append(tuple(center+Vector((x,r*math.cos(a),r*math.sin(a)))))
        for x,r in ((-length/2,.185),(-.14,.198),(.14,.198),(length/2,.185)):
            for a in (a0,a1): verts.append(tuple(center+Vector((x,r*math.cos(a),r*math.sin(a)))))
        faces=[]
        for j in range(3):
            k=j*2; faces += [(k,k+1,k+3,k+2),(k+8,k+10,k+11,k+9),(k,k+2,k+10,k+8),(k+1,k+9,k+11,k+3)]
        faces += [(0,8,9,1),(6,7,15,14)]
        make('stave_%02d'%i,verts,faces,'wood' if i%2 else 'wood_light',.0015,'drum',.04+.015*(i%4))
    for i,x in enumerate((-.145,.145)):
        ring('rolling_hoop_'+str(i),(x,.245,0),.245,.025,.046,'steel',(1,0,0),32,'drum',.27)
        ring('brass_hoop_trim_'+str(i),(x,.245,0),.248,.009,.015,'brass',(1,0,0),32,'drum',.31)
    for i,x in enumerate((-.219,.219)):
        cylinder('end_cap_'+str(i),(x,.245,0),.201,.022,'navy',(1,0,0),24,'drum',.21)
        cylinder('end_emblem_'+str(i),(x*1.07,.245,0),.075,.012,'brass',(1,0,0),12,'drum',.34)
    cylinder('fuse_socket',(.235,.34,0),.036,.033,'brass',(1,0,0),12,'drum',.36)
    points=[(.25,.34,0),(.29,.36,0),(.32,.40,0),(.35,.44,.018),(.39,.46,.025),(.43,.455,.030),(.47,.44,.026),(.50,.415,.020),(.52,.39,.01)]
    for i in range(8): tube('fuse_%02d'%i,points[i:i+2],.012,'rope',8,'fuse',.38+.01*i)
    cylinder('fuse_ember',points[-1],.014,.018,'ember',(1,0,0),10,'fuse',.49)
    socket('roll_axis',(0,.245,0),(1,0,0)); socket('fuse_tip',points[-1]); socket('burst',(0,.245,0))
    for ob in bpy.context.scene.objects: ob.location.z+=.003

def gatling():
    # Every rotating barrel and brace carries group=rotor; fixed shroud never stretches.
    cylinder('rear_motor',(0,0,.98),.23,.38,'navy',(0,0,1),24,delay=.04)
    ring('rear_rim',(0,0,1.155),.245,.045,.044,'brass',delay=.20)
    cylinder('rotor_hub',(0,0,.79),.205,.17,'steel',(0,0,1),24,'rotor',.20)
    for i in range(6):
        a=math.tau*i/6; x=.133*math.cos(a); y=.133*math.sin(a)
        axial('rotating_barrel_'+str(i),[(0,.042),(.05,.046),(.72,.042),(.72,.026),(.012,.026)],(x,y,0),mat='steel',segments=16,closed=True,group='rotor',delay=.28+i*.02)
        ring('barrel_muzzle_'+str(i),(x,y,.023),.048,.021,.036,'silver',segments=16,group='rotor',delay=.45)
    # Annular collars meet the outer sides of the barrel bundle without sealing the bores.
    for i,z in enumerate((.20,.61)):
        ring('bundle_collar_'+str(i),(0,0,z),.187,.026,.060,'brass',segments=24,group='rotor',delay=.39)
    cylinder('center_spindle',(0,0,.405),.045,.76,'brass',(0,0,1),12,'rotor',.16)
    cylinder('side_feed_drum',(.335,-.015,.94),.19,.25,'navy',(1,0,0),24,delay=.25)
    cylinder('feed_cover',(.466,-.015,.94),.174,.025,'brass',(1,0,0),24,delay=.34)
    box('feed_bridge',(.23,-.015,.94),(.14,.18,.22),'steel',.01)
    for i in range(5):
        a=-.8+i*.4
        box('feed_teeth_'+str(i),(.485,-.015+.125*math.sin(a),.94+.125*math.cos(a)),(.016,.020,.040),'silver',.002)
    box('bottom_mount',(0,-.24,.96),(.25,.12,.32),'brass',.012)
    box('mount_inlay',(0,-.307,.96),(.18,.015,.20),'navy',.004)
    for x in (-.24,.24):
        tube('motor_rail_'+str(x),[(x,-.08,.80),(x,-.08,1.15)],.017,'brass')
    ring('core_ring',(0,0,1.19),.105,.025,.025,'brass',delay=.44)
    cylinder('rear_core',(0,0,1.185),.078,.018,'teal',(0,0,1),16,delay=.46)
    socket('muzzle',(0,0,0)); socket('rotor',(0,0,.42),(0,0,1)); socket('mount',(0,-.30,.96)); socket('ornament',(-.245,0,1.0))

def smoke_launcher():
    box('base',(0,.075,.07),(.62,.15,.34),'navy',.018,delay=.02)
    box('base_trim',(0,.035,.07),(.65,.035,.36),'brass',.007,delay=.20)
    box('bank_support',(0,.19,.11),(.56,.15,.16),'steel',.012,delay=.12)
    direction=Vector((0,.55,-.835)).normalized()
    for i in range(6):
        x=(i%3-1)*.19; row=i//3
        back=Vector((x,.20+row*.16,.16+row*.10))
        d=Vector((x*.25,direction.y,direction.z)).normalized()
        muzzle=back+d*.25
        axial('launch_tube_'+str(i),[(0,.065),(.028,.071),(.29,.071),(.29,.052),(.009,.052)],back,tuple(d),'steel',16,True,.001,'bank',.20+i*.022)
        ring('tube_rim_'+str(i),tuple(muzzle+d*.035),.078,.024,.028,'brass',tuple(d),16,'bank',.38)
        cylinder('smoke_canister_'+str(i),tuple(back+d*.17),.049,.22,'teal',tuple(d),16,'canister_'+str(i),.43+i*.012)
        cylinder('canister_cap_'+str(i),tuple(back+d*.285),.047,.018,'navy',tuple(d),16,'canister_'+str(i),.47)
        socket('launch_'+str(i),tuple(back+d*.30),tuple(d))
    for x in (-.28,.28):
        box('side_bracket_'+str(x),(x,.22,.20),(.045,.25,.14),'brass',.005)
        bolt('bracket_pin_'+str(x),(x*1.1,.26,.20),.025)
    box('power_inlay',(0,.16,-.103),(.16,.06,.013),'teal',.003,delay=.46)
    socket('ground',(0,0,0),(0,1,0)); socket('bank_pivot',(0,.20,.16),(1,0,0))

def shell(heavy=False):
    scale=1.0 if heavy else .66
    # Nose is at local origin, trailing base +Z; flight always follows -Z.
    profile=[(0,.003),(.025,.028),(.08,.057),(.14,.073),(.21,.077),(.48,.077),(.49,.071)]
    axial('ogive_body',[(z*scale,r*scale) for z,r in profile],mat='navy' if heavy else 'steel',segments=20,bevel=.001)
    ring('driving_band',(0,0,.412*scale),.085*scale,.017*scale,.040*scale,'brass',segments=20,delay=.30)
    cylinder('base_plate',(0,0,.488*scale),.078*scale,.023*scale,'brass',(0,0,1),20,delay=.22)
    ring('identity_band',(0,0,.25*scale),.079*scale,.007*scale,.028*scale,'teal' if heavy else 'ember',segments=20,delay=.40)
    cylinder('base_mark',(0,0,.503*scale),.025*scale,.008*scale,'navy',(0,0,1),12,delay=.44)
    socket('nose',(0,0,0)); socket('trail',(0,0,.51*scale),(0,0,1))

def smoke_canister():
    axial('canister_body',[(0,.047),(.018,.050),(.21,.050),(.23,.045)],mat='teal',segments=16)
    cylinder('cap',(0,0,-.005),.046,.016,'navy',(0,0,1),16,delay=.32)
    ring('rim',(0,0,.205),.054,.008,.025,'brass',segments=16,delay=.36)
    socket('nose',(0,0,0)); socket('smoke',(0,0,.23),(0,0,1))

ASSET_IDS=['matchlock','rifle','shotgun','powder_barrel','gatling','smoke_launcher',
           'artillery_shell','naval_shell','smoke_canister']

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

def build_asset(asset_id):
    assert asset_id in ASSET_IDS
    name='FirearmV1_'+asset_id
    assert bpy.data.scenes.get(name) is None, 'Existing authored scene must be preserved; revise explicitly.'
    scene=bpy.data.scenes.new(name); bpy.context.window.scene=scene
    scene['asset_id']=asset_id; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
    scene.render.engine='BLENDER_EEVEE'; scene.view_settings.view_transform='AgX'
    scene.world=bpy.data.worlds.new('World_'+name); scene.world.color=(.12,.12,.12)
    if asset_id=='matchlock': matchlock()
    elif asset_id=='rifle': rifle()
    elif asset_id=='shotgun': shotgun()
    elif asset_id=='powder_barrel': powder_barrel()
    elif asset_id=='gatling': gatling()
    elif asset_id=='smoke_launcher': smoke_launcher()
    elif asset_id=='artillery_shell': shell()
    elif asset_id=='naval_shell': shell(True)
    elif asset_id=='smoke_canister': smoke_canister()
    finalize_asset(asset_id)

def finalize_asset(asset_id):
    scene=bpy.data.scenes['FirearmV1_'+asset_id]; bpy.context.window.scene=scene
    bpy.context.view_layer.update()
    meshes=[o for o in scene.objects if o.type=='MESH']
    info={'id':asset_id,'blender_scene':scene.name,'forward':[0,0,-1],'up':[0,1,0],
          'parts':[],'sockets':{},'triangles':0,'materials':[], 'units':'metres'}
    points=[]
    for ob in sorted(meshes,key=object_name):
        if asset_id=='matchlock' and ob['part_role']=='match_cord': unwrap_face_tiles(ob.data)
        ob.data.calc_loop_triangles(); count=len(ob.data.loop_triangles); info['triangles']+=count
        pts=[ob.matrix_world@v.co for v in ob.data.vertices]; points+=pts
        info['parts'].append({'name':ob.name,'role':ob['part_role'],'group':ob['motion_group'],
                              'delay':ob['assembly_delay'],'triangles':count,'origin':G(ob.location)})
    for ob in scene.objects:
        if ob.type=='EMPTY': info['sockets'][ob.name.split('__')[-1]]={'position':G(ob.location),'direction':list(ob['godot_axis'])}
    info['materials']=sorted({m.name for ob in meshes for m in ob.data.materials})
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3))); hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    info['dimensions']=[round(hi.x-lo.x,5),round(hi.z-lo.z,5),round(hi.y-lo.y,5)]
    info['aabb_godot']={'min':[round(lo.x,6),round(lo.z,6),round(-hi.y,6)],'max':[round(hi.x,6),round(hi.z,6),round(-lo.y,6)]}
    info['part_count']=len(meshes)
    scene['manifest_json']=json.dumps(info,indent=2)
    for ob in scene.objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.export_scene.gltf(filepath=GAME+'/'+asset_id+'.glb',export_format='GLB',use_selection=True,
        use_active_scene=True,export_animations=False,export_skins=False,export_extras=True,
        export_yup=True,export_cameras=False,export_lights=False)
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/firearm_tree_v1.blend')
    print('FIREARM_ASSET '+json.dumps(info))
