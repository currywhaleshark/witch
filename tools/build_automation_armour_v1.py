"""Supplemental heavy-node armour; base geometry/rests/actions are untouched."""
import sys,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from automation_rigid_common import *
actor=sys.argv[sys.argv.index('--')+1];assert actor in ('hound','giant')
version='v2' if actor=='hound' else 'v1';source=ROOT/f'assets/actors/automation_batch2/{actor}_game_{version}/{actor}_game_{version}.blend'
bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.context.scene
body=next(o for o in sc.objects if o.type=='MESH');rig=next(o for o in sc.objects if o.type=='ARMATURE')
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=I
bpy.context.view_layer.update()
before=hashlib.sha256(np.array([v.co[:] for v in body.data.vertices],dtype=np.float32).tobytes()).hexdigest()
basepoints=part_points(body)
g=Geometry.__new__(Geometry);g.actor=actor+'_armour';g.sc=sc;g.source=source;g.source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
g.base=ROOT/f'assets/actors/automation_batch2/{actor}_armour_v1';g.out=ROOT/f'reports/automation_batch2_complete_v1/{actor}_armour'
for pth in [g.base/'textures',g.out/'geometry',g.out/'validation',g.out/'local']:pth.mkdir(parents=True,exist_ok=True)
g.src={};g.high={};g.low={};g.provenance=[];g.repairs=[];g.offsets={}
g.dark=material('Armour_dark',(.015,.025,.027),.6,.5)
g.steel=material('Armour_cutting_steel',(.15,.19,.21),.85,.28)
g.brass=material('Armour_aged_brass',(.29,.17,.06),.8,.38)
g.teal=material('Armour_deep_teal',(.016,.07,.065),.6,.44)
for m,colors in [(g.brass,[(.13,.065,.018,1),(.38,.235,.085,1)]),(g.teal,[(.009,.035,.033,1),(.025,.095,.085,1)])]:
 ns=m.node_tree.nodes;ls=m.node_tree.links;bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED')
 noise=ns.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=72.;noise.inputs['Detail'].default_value=3
 tex=ns.new('ShaderNodeTexCoord');ls.new(tex.outputs['Generated'],noise.inputs['Vector'])
 ramp=ns.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=colors[0];ramp.color_ramp.elements[1].color=colors[1]
 ls.new(noise.outputs['Fac'],ramp.inputs[0]);ls.new(ramp.outputs['Color'],bs.inputs['Base Color'])

def plate(group,label,outline,delta,mat,bevel=.003):
    outline=[Vector(v) for v in outline];delta=Vector(delta);n=len(outline)
    verts=outline+[v+delta for v in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    o=mesh_object(label,verts,faces,mat);bpy.context.view_layer.objects.active=o
    if bevel:
        m=o.modifiers.new('Machined edge','BEVEL');m.width=bevel;m.segments=1
        bpy.ops.object.modifier_apply(modifier=m.name)
    # Machined planes and bevel faces must not inherit smooth box-corner normals.
    for face in o.data.polygons:face.use_smooth=False
    g.add(group,o)

def hood(group,c,side,radius_y,radius_z,width):
    c=Vector(c);steps=10;vs=[]
    # Closed curved top shell with a brass edge and an inset teal upper plate.
    for dx in (0,width*side):
        for rr in (1.,.88):
            for i in range(steps+1):
                a=math.radians(8+164*i/steps);vs.append(c+Vector((dx,radius_y*rr*math.cos(a),radius_z*rr*math.sin(a))))
    n=steps+1;fs=[]
    for i in range(steps):
        for a,b in ((0,1),(2,3),(0,2),(1,3)):fs.append((a*n+i,a*n+i+1,b*n+i+1,b*n+i))
    fs.extend([(0,n,3*n,2*n),(n-1,2*n-1,4*n-1,3*n-1)])
    g.add(group,mesh_object('Brass_shell',vs,fs,g.brass))
    # Slightly raised curved paint panels, attached along the shell face.
    for i in range(1,steps-1):
        a=math.radians(8+164*i/steps);b=math.radians(8+164*(i+1)/steps)
        q=[c+Vector((dx,radius_y*1.014*math.cos(theta),radius_z*1.014*math.sin(theta))) for dx,theta in [(width*.12*side,a),(width*.88*side,a),(width*.88*side,b),(width*.12*side,b)]]
        plate(group,'Teal_panel',q,(0,0,.001),g.teal,0)

def mount_to_base(group,target,radius):
    target=Vector(target);near=min(basepoints[group],key=lambda p:(p-target).length_squared)
    axis=(near-target).normalized()
    g.add(group,cylinder('Attached_mount_pin',target-axis*.002,near+axis*.002,radius,g.brass,10))

if actor=='hound':
    for side,s in [('L',1),('R',-1)]:
        j=rig.data.bones['fore_upper.'+side].head_local
        hood('fore_upper.'+side,j+Vector((s*.028,0,.015)),s,.090,.086,.065)
        g.add('fore_upper.'+side,cylinder('Armour_mount',j,j+Vector((s*.07,0,0)),.025,g.brass,10))
        g.add('fore_upper.'+side,cylinder('Shoulder_shell_bracket',j+Vector((s*.05,0,0)),j+Vector((s*.05,0,.102)),.014,g.brass,10))
    for s in (-1,1):
        x=.00795+s*.055
        profile=[(x,.346,.603),(x,.354,.641),(x,.426,.632),(x,.551,.552),(x,.551,.530),(x,.410,.583)]
        plate('head','Head_cheek_guard',profile,(s*.014,0,0),g.brass,.002)
        plate('head','Head_paint',[(x+s*.014,.362,.622),(x+s*.014,.419,.616),(x+s*.014,.519,.550),(x+s*.014,.410,.597)],(s*.002,0,0),g.teal,.001)
        x=.00795+s*.059;poly=[]
        for i in range(7):
            y=.395+i*.025;z=.545-(y-.395)*.36
            poly.extend([(x,y,z),(x,y+.011,z+.017),(x,y+.023,z-.008)])
        poly.extend([(x,.568,.462),(x,.391,.525)])
        plate('jaw','Saw_tooth_rail',poly,(s*.010,0,0),g.steel,.0006)
        for y in (.425,.50):mount_to_base('jaw',(x+s*.005,y,.535-(y-.395)*.36),.007)
    plate('head','Rear_brow_bridge',[(-.059,.351,.623),(.074,.351,.623),(.067,.385,.643),(-.052,.385,.643)],(0,0,.008),g.brass,.002)
else:
    for side,s in [('L',1),('R',-1)]:
        j=rig.data.bones['shoulder.'+side].head_local
        hood('shoulder.'+side,j+Vector((s*.11,.01,.015)),s,.37,.40,.32)
        g.add('shoulder.'+side,cylinder('Shoulder_stand_off',j,j+Vector((s*.20,0,0)),.09,g.brass,12))
        ps=basepoints['forearm.'+side]
        a=rig.data.bones['forearm.'+side].head_local;b=rig.data.bones['fist.'+side].head_local
        up=(a-b).normalized();outward=Vector((s,0,0));outward=(outward-up*outward.dot(up)).normalized();tangent=up.cross(outward).normalized()
        middle=(a+b)/2
        radius=float(np.quantile([(v-middle).dot(outward) for v in ps if abs((v-middle).dot(up))<.25],.93))
        c=middle+outward*(radius+.007)
        def panel(poly,offset=0):return [c+tangent*y+up*z+outward*offset for y,z in poly]
        plate('forearm.'+side,'Forearm_guard',panel([(-.16,-.27),(.15,-.27),(.19,.21),(.12,.29),(-.17,.24)]),outward*.055,g.brass,.012)
        plate('forearm.'+side,'Forearm_paint',panel([(-.115,-.21),(.11,-.21),(.13,.20),(-.12,.21)],.057),outward*.007,g.teal,.008)
        for dz in (-.16,.16):mount_to_base('forearm.'+side,c+up*dz+outward*.02,.027)
        ps=basepoints['fist.'+side];lo=Vector([min(v[i] for v in ps) for i in range(3)]);hi=Vector([max(v[i] for v in ps) for i in range(3)])
        x=(lo.x+hi.x)/2;y=hi.y-.03;z0=lo.z+.04;z1=hi.z-.10;w=(hi.x-lo.x)*.50
        plate('fist.'+side,'Fist_knuckle_cover',[(x-w*.85,y,z0),(x+w*.85,y,z0),(x+w,y,z0+.05),(x+w,y,z1-.06),(x+w*.70,y,z1),(x-w*.70,y,z1),(x-w,y,z1-.06),(x-w,y,z0+.05)],(0,.095,0),g.brass,.025)
        for dx in (-w*.5,w*.5):mount_to_base('fist.'+side,(x+dx,y+.015,(z0+z1)/2),.035)
        for k in (-1,0,1):
            plate('fist.'+side,'Knuckle_inlay',[(x+k*w*.55-w*.16,y+.096,z0+.05),(x+k*w*.55+w*.16,y+.096,z0+.05),(x+k*w*.55+w*.16,y+.096,z1-.06),(x+k*w*.55-w*.16,y+.096,z1-.06)],(0,.008,0),g.steel,.004)
g.cleanup();armour=g.bake()
armour.parent=rig;m=armour.modifiers.new('Base rigid bone binding','ARMATURE');m.object=rig
assert hashlib.sha256(np.array([v.co[:] for v in body.data.vertices],dtype=np.float32).tobytes()).hexdigest()==before
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);armour.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(g.base/f'{g.actor}_static.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_yup=True,export_tangents=True)
contract=json.loads((source.parent/'rig.json').read_text(encoding='utf8'));contract['parts_metadata']={n:v for n,v in contract['parts_metadata'].items() if n in armour.vertex_groups};contract['parts']=len(armour.vertex_groups);contract['triangles']=len(armour.data.polygons)
contract['base_asset']=f'../{actor}_{version}/{actor}_{version}.glb';contract['node_scale']=1.2 if actor=='hound' else 1.1;contract['id']=g.actor;contract['additive_only']=True
dump(g.base/'rig.json',contract)
srcpose=ROOT/('reports/hound_game_v2/local/animation_samples.json' if actor=='hound' else 'reports/automation_batch2_complete_v1/giant/local/animation_samples.json')
if srcpose.exists():
    shutil.copy2(srcpose,g.out/'local/animation_samples.json')
else:
    # Reconstruct the handoff samples from the packed base on another PC.
    rows={}
    for clip,c in contract['clips'].items():
        action=bpy.data.actions[clip];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
        rows[clip]=[]
        for t in c['times']:
            f=1+t*24;sc.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
            rows[clip].append({'time':t,'world':{p.name:[list(r) for r in p.matrix] for p in rig.pose.bones}})
    dump(g.out/'local/animation_samples.json',rows)
dump(g.base/'preservation.json',{'base_source_sha256':g.source_hash,'base_mesh_positions_sha256':before,'base_mesh_unchanged':True,'bones_rests_actions_reused':True,'extra_triangles':len(armour.data.polygons),'rigid_groups':len(armour.vertex_groups),'texture_set':'1K color/normal/ORM + unused 128 emission retained only in source'})
action=bpy.data.actions['idle'];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0];sc.frame_set(1)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(g.base/f'{g.actor}_game_v1.blend'),compress=True)
print('ARMOUR_READY',actor,len(armour.data.polygons),flush=True)
