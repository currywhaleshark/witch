"""Live MCP authoring of independent drive-tree props; metres, Godot coordinates."""
import bpy
import bmesh
import math
import json
from mathutils import Vector, Matrix

SOURCE = 'C:/Users/yurib/Documents/New project/witch/assets/weapons/drive_tree_v1'
GAME = 'C:/Users/yurib/Documents/New project/witch/game/assets/weapons/drive_tree_v1'
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
    name='M_DriveV1_'+key
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
    ob['surface_key']=mat
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


def plate(name,outline,depth=.07,z=0,mat='steel',group='body',delay=.2):
    n=len(outline)
    verts=[(x,y,z+s*depth/2) for s in (-1,1) for x,y in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return make(name,verts,faces,mat,.003,group,delay)

def bar(name,a,b,r=.035,mat='brass',group='body',delay=.2):
    d=Vector(b)-Vector(a)
    return cylinder(name,(Vector(a)+Vector(b))*.5,r,d.length,mat,d.normalized(),12,group,delay)

def toothed_disc(name,p,r=.49,group='saw',teeth=28):
    # Closed, thick toothed wheel: no stacked coplanar discs or deforming teeth.
    outline=[]
    for i in range(teeth):
        for fraction,rr in [(0,.91),(.24,1),(.50,.97),(.74,.90)]:
            a=math.tau*(i+fraction)/teeth
            outline.append((p[0]+r*rr*math.cos(a),p[1]+r*rr*math.sin(a)))
    o=plate(name,outline,.045,p[2],'silver',group,.42)
    cylinder(name+'_hub',p,r*.20,.13,'brass',(0,0,1),16,group,.48)
    return o

def machine_base(width,depth):
    box('ground_foundation',(0,.065,0),(width,.13,depth),'steel',.025,delay=.01)
    for s in (-1,1):
        box('foot_'+str(s),(s*(width/2-.14),.115,0),(.27,.12,depth+.20),'navy',.025,delay=.05)
        box('foot_trim_'+str(s),(s*(width/2-.14),.18,-depth*.28),(.21,.025,.16),'brass',.008,delay=.18)

def guillotine(kind='blade'):
    machine_base(1.52,.66)
    for s in (-1,1):
        x=s*.61
        box('column_'+str(s),(x,1.22,.015),(.15,2.12,.20),'navy',.018,delay=.07)
        bar('guide_'+str(s),(x, .23,-.115),(x,2.21,-.115),.027,'silver',delay=.23)
        box('runner_'+str(s),(x,1.88,-.12),(.12,.21,.16),'brass',.009,'drop',.35)
        for y in (.34,2.13):bolt('rail_cap_%s_%s'%(s,y),(x,y,-.132),.031,(0,0,1))
    box('crown',(0,2.25,.015),(1.48,.23,.30),'navy',.025,delay=.14)
    box('crown_trim',(0,2.31,-.152),(1.33,.035,.018),'brass',.004,delay=.26)
    cylinder('clock_seal',(0,2.23,-.165),.115,.04,'brass',(0,0,1),12,delay=.42)
    cylinder('core',(0,2.23,-.189),.063,.015,'core',(0,0,1),12,delay=.49)
    box('anvil',(0,.22,-.025),(1.17,.13,.22),'silver',.014,delay=.12)
    box('carriage',(0,1.9,-.095),(1.31,.13,.17),'brass',.014,'drop',.33)
    if kind=='saw':
        toothed_disc('descending_saw',(0,1.52,-.11),.50)
        bar('saw_fork_L',(-.22,1.88,-.10),(-.10,1.52,-.10),.045,'navy','drop')
        bar('saw_fork_R',(.22,1.88,-.10),(.10,1.52,-.10),.045,'navy','drop')
        socket('saw_axis',(0,1.52,-.11),(0,0,1))
    else:
        plate('falling_blade',[(-.55,1.84),(.55,1.84),(.55,1.30),(-.55,1.56)],.065,-.10,'steel','drop',.40)
        plate('honed_edge',[(-.53,1.57),(.53,1.32),(.53,1.35),(-.53,1.60)],.012,-.134,'silver','drop',.43)
        for x in (-.43,.43):bolt('blade_fastener_'+str(x),(x,1.79,-.143),.027,(0,0,1),'drop')
    if kind=='lock':
        for s in (-1,1):
            x=s*.49
            box('clamp_slide_'+str(s),(x,.47,0),(.23,.13,.22),'brass',.014,'clamp_'+str(s),.34)
            plate('clamp_jaw_'+str(s),[(x-s*.03,.40),(x-s*.22,.44),(x-s*.22,.65),(x-s*.10,.70),(x+s*.07,.61)],.10,-.03,'navy','clamp_'+str(s),.40)
    socket('impact',(0,.28,-.10));socket('drop_axis',(0,1.9,-.095),(0,-1,0))

def winch():
    machine_base(.78,.62)
    for s in (-1,1):
        box('cheek_'+str(s),(s*.285,.39,.04),(.075,.42,.43),'navy',.023,delay=.13)
        cylinder('axle_'+str(s),(s*.34,.41,.025),.09,.07,'brass',(1,0,0),16,delay=.25)
    cylinder('spool',(0,.41,.025),.17,.50,'steel',(1,0,0),24,'drum',.22)
    for i,x in enumerate((-.22,-.11,0,.11,.22)):
        ring('reel_groove_'+str(i),(x,.41,.025),.185,.025,.022,'brass',(1,0,0),24,'drum',.30)
    box('gearbox',(.32,.40,.19),(.16,.29,.22),'brass',.018,delay=.24)
    cylinder('core',(.41,.42,.19),.062,.026,'core',(1,0,0),12,delay=.46)
    for i,x in enumerate((0,-.20,.20)):
        box('fairlead_'+str(i),(x,.40,-.24),(.13,.11,.12),'brass',.012,delay=.32)
        tube('cable_'+str(i),[(x,.40,-.28),(x,.40,-.75)],.009,'black',8,'cable_'+str(i),.38)
        tube('hook_'+str(i),[(x,.40,-.72),(x,.40,-.85),(x+.08,.40,-.96),(x+.145,.40,-.94),(x+.15,.40,-.86)],.023,'silver',8,'hook_'+str(i),.43)
        cylinder('hook_ferrule_'+str(i),(x,.40,-.75),.035,.07,'brass',(0,0,1),12,'hook_'+str(i),.44)
        socket('cable_'+str(i),(x,.40,-.28));socket('hook_'+str(i),(x,.40,-.75))
    socket('drum_axis',(0,.41,.025),(1,0,0));socket('target',(0,.40,-2.0))

def press(compound=False):
    w=1.72 if compound else 1.92;d=1.44 if compound else 1.25;h=2.12
    machine_base(w,d)
    for i,(x,z) in enumerate([(-w*.40,-d*.34),(w*.40,-d*.34),(-w*.40,d*.34),(w*.40,d*.34)]):
        cylinder('column_'+str(i),(x,1.13,z),.065,1.94,'steel',(0,1,0),12,delay=.09)
        ring('column_collar_'+str(i),(x,.26,z),.10,.026,.14,'brass',(0,1,0),12,delay=.20)
    box('crown',(0,h,0),(w,.20,d),'navy',.028,delay=.16)
    for i,x in enumerate((-.42,.42)):
        cylinder('hydraulic_barrel_'+str(i),(x,1.91,0),.105,.43,'navy',(0,1,0),16,delay=.23)
        ring('gland_'+str(i),(x,1.70,0),.12,.045,.075,'brass',(0,1,0),16,delay=.32)
        cylinder('piston_rod_'+str(i),(x,1.57,0),.057,.65,'silver',(0,1,0),12,'platen',.34)
        axial('telescopic_stage_'+str(i),[(-.48,.078),(.48,.078),(.48,.061),(-.48,.061)],(x,1.73,0),(0,1,0),'silver',16,True,.001,'platen_stage',.31)
        tube('hydraulic_line_'+str(i),[(x,2.09,.12),(x,2.02,.30),(x,1.82,.31),(x,1.82,.11)],.019,'black',8,delay=.34)
    box('platen',(0,1.28,0),(w*.80,.18,d*.78),'steel',.022,'platen',.35)
    box('platen_band',(0,1.37,-d*.39),(w*.76,.032,.024),'brass',.004,'platen',.42)
    for i in range(5):
        box('press_rib_'+str(i),((i-2)*w*.13,1.17,0),(.08,.06,d*.66),'silver',.008,'platen',.42)
    cylinder('pressure_gauge',(w*.39,2.13,-d/2-.025),.085,.04,'brass',(0,0,1),16,delay=.45)
    cylinder('core',(0,2.12,-d/2-.008),.06,.025,'core',(0,0,1),12,delay=.48)
    socket('impact',(0,.22,0));socket('press_axis',(0,1.28,0),(0,-1,0))
    if compound:
        # Separate open-front cage leaves readability for the trapped target.
        for i,a in enumerate((0,math.pi/4,math.pi/2,3*math.pi/4,math.pi)):
            x=.69*math.cos(a);z=.53*math.sin(a)
            box('cage_bar_'+str(i),(x,.64,z),(.055,1.04,.055),'brass',.006,delay=.22)
        for side in (-1,1):
            group='gate_'+str(side);pivot=(side*.69,.70,-.49)
            box('gate_rail_'+str(side),(side*.35,.71,-.49),(.71,.065,.065),'brass',.005,group,.28)
            for k in range(2):box('gate_bar_%s_%s'%(side,k),(side*(.14+k*.23),.70,-.49),(.05,.94,.05),'navy',.005,group,.31)
            cylinder('gate_hinge_'+str(side),pivot,.083,.94,'brass',(0,1,0),12,group,.32)
            socket('gate_'+str(side),pivot,(0,1,0))
            # Twin saw arms park outboard and swing into the chamber.
            p=(side*.94,.76,.10);end=(side*.95,.76,-.40)
            cylinder('arm_motor_'+str(side),p,.13,.18,'navy',(0,1,0),16,delay=.32)
            bar('saw_arm_'+str(side),p,end,.055,'brass','arm_'+str(side),.38)
            toothed_disc('execution_saw_'+str(side),(side*.95,.76,-.40),.27,'saw_'+str(side),20)
            socket('arm_'+str(side),p,(0,1,0));socket('saw_'+str(side),end,(0,0,1))

def broad_cutter():
    # Independently authored larger blades: rigid jaw geometry, never runtime scale.
    box('saddle',(0,.76,.03),(.25,.24,.15),'navy',.013,delay=.08)
    cylinder('power_collar',(0,.68,0),.083,.13,'brass',(0,1,0),16,delay=.15)
    cylinder('core',(0,.78,-.055),.042,.025,'core',(0,0,1),12,delay=.42)
    for side in (-1,1):
        x=side*.105;p=(x,.94,0);group='jaw_'+str(side)
        pts=[(side*.025,.91),(side*.15,.88),(side*.31,1.10),(side*.30,1.40),(side*.12,1.86),(side*.006,1.72),(side*.006,1.10)]
        plate('forged_jaw_'+str(side),pts,.085,0,'steel',group,.30)
        plate('honed_edge_'+str(side),[(side*.018,1.13),(side*.018,1.70),(side*.108,1.81),(side*.052,1.63),(side*.055,1.15)],.012,-.044,'silver',group,.37)
        cylinder('jaw_axle_'+str(side),p,.064,.14,'brass',(0,0,1),16,delay=.25)
        bar('drive_link_'+str(side),(side*.04,.77,-.09),(side*.18,.99,-.09),.025,'brass','link_'+str(side),.24)
        socket('jaw_'+str(side),p,(0,0,1))
        socket('jaw_pin_'+str(side),(side*.18,.99,-.09))
    socket('mount',(0,.65,0),(0,1,0));socket('cut',(0,1.50,0),(0,1,0));socket('slider',(0,.77,-.09))

def bind_new(start_names,bone):
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH' and ob.name not in start_names:ob['attach_bone']=bone

def exoskeleton(rest,light=False):
    def at(b):return Vector((rest[b][0][3],rest[b][1][3],rest[b][2][3]))
    old=set(o.name for o in bpy.context.scene.objects)
    # Back plate behind the clothing, centre spine exposed rather than enclosing torso.
    box('backplate',(0,1.14,-.24),(.17,.25,.055),'navy',.017,delay=.08)
    for s in (-1,1):
        cylinder('back_damper_'+str(s),(s*.067,1.14,-.28),.028,.20,'brass',(0,1,0),12,delay=.19)
    cylinder('back_core',(0,1.16,-.285),.047,.026,'core',(0,0,1),12,delay=.45)
    bind_new(old,'DEF-chest')
    for side,tag in [(1,'L'),(-1,'R')]:
        upper=at('DEF-upper_arm.'+tag);elbow=at('DEF-forearm.'+tag);wrist=at('DEF-hand.'+tag)
        knee=at('DEF-shin.'+tag);ankle=at('DEF-foot.'+tag)
        old=set(o.name for o in bpy.context.scene.objects)
        # Compact shoulder boss follows the upper arm, not the cape/cloth skeleton.
        offset=Vector((side*.145,0,-.035));a=upper+offset;b=elbow+offset
        cylinder('shoulder_'+tag,a,.045,.060,'navy',(1,0,0),16,delay=.20)
        cylinder('shoulder_pin_'+tag,a+Vector((side*.042,0,0)),.032,.018,'brass',(1,0,0),12,delay=.31)
        if not light:
            bar('upper_rail_'+tag,a,b,.018,'brass',delay=.27)
            bar('upper_damper_'+tag,a.lerp(b,.22)+Vector((0,0,.02)),a.lerp(b,.71)+Vector((0,0,.02)),.027,'navy',delay=.34)
        bind_new(old,'DEF-upper_arm.'+tag+('.002' if tag=='L' else '.001'))
        old=set(o.name for o in bpy.context.scene.objects)
        if not light:
            a=elbow+Vector((side*.16,0,-.035));b=wrist+Vector((side*.105,0,-.025))
            cylinder('elbow_'+tag,a,.038,.050,'navy',(1,0,0),16,delay=.32)
            bar('forearm_rail_'+tag,a,b,.017,'brass',delay=.34)
            bar('forearm_plate_'+tag,a.lerp(b,.22),a.lerp(b,.78),.028,'navy',delay=.39)
            # C-shaped wrist saddle stays outside the hand and never covers the grip.
            axis=(wrist-elbow).normalized();u=Vector((side,0,0));u=(u-axis*u.dot(axis)).normalized();v=axis.cross(u)
            center=wrist-axis*.025
            arc=[tuple(center+.115*(u*math.cos(-1.1+i*2.2/12)+v*math.sin(-1.1+i*2.2/12))) for i in range(13)]
            tube('wrist_cuff_'+tag,arc,.009,'brass',8,delay=.43)
            # Proximal forearm follows the rigid elbow frame; sleeve-twist middle
            # bones can roll the mechanism through the cloth during running.
            bind_new(old,'DEF-forearm.'+tag)
            if tag=='L':
                for ob in bpy.context.scene.objects:
                    if ob.get('part_role')=='wrist_cuff_L':ob['attach_bone']='DEF-forearm.L.001'
        old=set(o.name for o in bpy.context.scene.objects)
        a=knee+Vector((side*.055,-.025,.105));b=ankle+Vector((side*.042,.055,.09))
        cylinder('knee_'+tag,a,.045,.035,'brass',(0,0,1),12,delay=.34)
        bar('shin_rail_'+tag,a,b,.025,'brass',delay=.35)
        if not light:
            bar('shin_guard_'+tag,a.lerp(b,.25),a.lerp(b,.85),.041,'navy',delay=.40)
        bind_new(old,'DEF-shin.'+tag+'.001')
    socket('body_origin',(0,0,0));socket('back_anchor',(0,1.14,-.24))

IDS=['guillotine','guillotine_saw','guillotine_lock','restraint_winch','hydraulic_press','compound_executor','shock_frame','exoskeleton','broad_cutter']

def build_asset(asset_id,rest=None):
    assert asset_id in IDS
    name='DriveV1_'+asset_id
    assert bpy.data.scenes.get(name) is None,'Existing revision is preserved'
    scene=bpy.data.scenes.new(name);bpy.context.window.scene=scene
    scene['asset_id']=asset_id;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    scene.render.engine='BLENDER_EEVEE';scene.view_settings.view_transform='AgX'
    scene.world=bpy.data.worlds.new('World_'+name);scene.world.color=(.12,.12,.12)
    if asset_id.startswith('guillotine'):guillotine({'guillotine':'blade','guillotine_saw':'saw','guillotine_lock':'lock'}[asset_id])
    elif asset_id=='restraint_winch':winch()
    elif asset_id=='hydraulic_press':press()
    elif asset_id=='compound_executor':press(True)
    elif asset_id=='broad_cutter':broad_cutter()
    else:exoskeleton(rest,asset_id=='shock_frame')
    summarize(asset_id)

def object_name(o):
    return o.name

def summarize(asset_id):
    scene=bpy.data.scenes['DriveV1_'+asset_id];bpy.context.window.scene=scene;bpy.context.view_layer.update()
    obs=sorted([o for o in scene.objects if o.type=='MESH'],key=object_name)
    info={'id':asset_id,'parts':[],'sockets':{},'units':'metres','runtime_status':'prepared_asset','triangles':0,'part_count':len(obs),'forward':[0,0,-1],'up':[0,1,0]};points=[]
    for o in obs:
        o.data.calc_loop_triangles();n=len(o.data.loop_triangles);info['triangles']+=n
        points += [G(o.matrix_world@v.co) for v in o.data.vertices]
        info['parts'].append({'name':o.name,'role':o['part_role'],'group':o['motion_group'],'delay':o['assembly_delay'],'surface':o['surface_key'],'origin':G(o.location),'triangles':n,'attach_bone':o.get('attach_bone','')})
    for o in scene.objects:
        if o.type=='EMPTY':info['sockets'][o.name.split('__')[-1]]={'position':G(o.location),'direction':list(o['godot_axis'])}
    lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
    info['aabb_godot']={'min':lo,'max':hi};info['dimensions']=[round(b-a,5) for a,b in zip(lo,hi)]
    info['materials']=sorted({m.name for o in obs for m in o.data.materials});scene['manifest_json']=json.dumps(info)
    print(json.dumps({'asset':asset_id,'parts':len(obs),'triangles':info['triangles'],'dimensions':info['dimensions']}))

def save_source():
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/drive_tree_v1.blend')

