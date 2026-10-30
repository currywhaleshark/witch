"""Original low-profile spring launch plate, built in isolated background Blender."""
import bpy, bmesh, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
ASSET=ROOT/'assets/props/spring_dash_v1'
GAME=ROOT/'game/assets/props/spring_dash_v1'
REPORT=ROOT/'reports/spring_dash_v1'
for p in [ASSET/'authoring',ASSET/'exports',GAME,REPORT]:p.mkdir(parents=True,exist_ok=True)
assert bpy.app.background
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
M={}
for name,color,metal,rough in [
    ('Navy_enamel',(.035,.070,.105),.24,.40),('Aged_brass',(.50,.32,.135),.42,.45),
    ('Polished_edge',(.72,.52,.27),.48,.32),('Spring_steel',(.29,.38,.43),.50,.30),
    ('Rubber_grip',(.018,.026,.035),.02,.78),('Teal_inlay',(.10,.58,.46),.12,.28)]:
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if name=='Teal_inlay':p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=.65
    M[name]=m
records=[]
def xyz(p):return (p[0],-p[2],p[1])
def finish(o,material,bevel=0):
    o.data.materials.append(M[material])
    if bevel:
        m=o.modifiers.new('Machined_bevel','BEVEL');m.width=bevel;m.segments=1
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=m.name)
    return o
def box(p,size,mat='Navy_enamel',bevel=.003):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p));o=bpy.context.object
    o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,mat,bevel)
def cylinder(p,radius,depth,mat='Aged_brass',vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=xyz(p));return finish(bpy.context.object,mat)
def slab(p,width,length,height,mat,corner=.045):
    x=width/2;z=length/2;c=corner
    outline=[(-x+c,-z),(x-c,-z),(x,-z+c),(x,z-c),(x-c,z),(-x+c,z),(-x,z-c),(-x,-z+c)]
    vs=[xyz((p[0]+a,p[1]+y,p[2]+b)) for y in [-height/2,height/2] for a,b in outline]
    fs=[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    mesh=bpy.data.meshes.new('Chamfered_plate');mesh.from_pydata(vs,[],fs);mesh.update()
    o=bpy.data.objects.new('Plate',mesh);scene.collection.objects.link(o);return finish(o,mat,.002)
def part(name,role,objects,pivot,delay):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1:bpy.ops.object.join()
    o=bpy.context.object;o.name=name;o.data.name=name+'_mesh'
    scene.cursor.location=xyz(pivot);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
    o['spring_role']=role;o['assembly_delay']=delay
    records.append({'name':name,'role':role,'delay':delay,'pivot':list(pivot)})
    return o

part('foundation','base',[slab((0,.020,0),.65,.82,.028,'Aged_brass'),slab((0,.037,0),.59,.76,.012,'Navy_enamel')],(0,.02,0),0.)
for side,x in [('L',-.28),('R',.28)]:
    part('side_rail_'+side,'base',[box((x,.049,0),(.035,.028,.64),'Polished_edge'),box((x,.063,0),(.015,.008,.40),'Navy_enamel')],(x,.05,0),.04)
    part('guide_sleeve_'+side,'base',[cylinder((x,.067,0),.027,.090),cylinder((x,.113,0),.031,.008,'Polished_edge')],(x,.025,0),.10)
    part('guide_middle_'+side,'guide_mid',[cylinder((x,.0695,0),.018,.127,'Spring_steel'),cylinder((x,.136,0),.021,.008,'Aged_brass')],(x,.07,0),.16)
    part('guide_rod_'+side,'guide_top',[cylinder((x,.095,0),.012,.12,'Spring_steel'),cylinder((x,.110,0),.022,.014,'Polished_edge')],(x,.105,0),.20)
for i,(x,z) in enumerate([(-.24,-.30),(.24,-.30),(-.24,.30),(.24,.30)]):
    part('foot_%d'%i,'base',[box((x,.010,z),(.095,.018,.12),'Rubber_grip'),cylinder((x,.043,z),.018,.012,'Spring_steel',6)],(x,.01,z),.025)

coil={'radius':.066,'wire_radius':.009,'turns':3.5,'steps':84,'sides':7,'bottom_y':.034,'closed_height':.070,'open_height':.255}
def helix(x):
    vs=[];fs=[];n=coil['steps'];k=coil['sides'];r=coil['radius'];w=coil['wire_radius'];height=coil['closed_height']
    for i in range(n+1):
        a=i/n*math.tau*coil['turns'];radial=Vector((math.cos(a),0,math.sin(a)))
        tangent=Vector((-r*math.sin(a),height/(math.tau*coil['turns']),r*math.cos(a))).normalized()
        cross=tangent.cross(radial).normalized();center=Vector((x+r*math.cos(a),coil['bottom_y']+height*i/n,r*math.sin(a)))
        for j in range(k):
            b=math.tau*j/k;v=center+w*(radial*math.cos(b)+cross*math.sin(b));vs.append(xyz(v))
    for i in range(n):
        for j in range(k):a=i*k+j;b=i*k+(j+1)%k;fs.append((a,b,b+k,a+k))
    fs.extend([tuple(range(k-1,-1,-1)),tuple(n*k+j for j in range(k))])
    mesh=bpy.data.meshes.new('Helix');mesh.from_pydata(vs,[],fs);mesh.update();o=bpy.data.objects.new('Helix',mesh);scene.collection.objects.link(o)
    for f in mesh.polygons:f.use_smooth=True
    return finish(o,'Spring_steel')
for side,x in [('L',-.16),('R',.16)]:
    part('spring_seat_'+side,'base',[cylinder((x,.037,0),.084,.012,'Aged_brass'),cylinder((x,.044,0),.073,.008,'Rubber_grip')],(x,.034,0),.08)
    part('spring_'+side,'coil',[helix(x)],(x,coil['bottom_y'],0),.13)
    part('spring_cap_'+side,'deck',[cylinder((x,.107,0),.083,.014,'Polished_edge')],(x,.107,0),.23)

part('deck_carriage','deck',[slab((0,.115,0),.58,.70,.018,'Polished_edge'),box((0,.102,0),(.52,.018,.048),'Spring_steel')],(0,.115,0),.24)
for i,x in enumerate([-.174,0,.174]):
    p=[slab((x,.131,0),.163,.64,.018,'Navy_enamel',.02)]
    for z in [-.22,-.14,-.06,.06,.14,.22]:p.append(box((x,.145,z),(.135,.006,.017),'Rubber_grip',.001))
    p.append(box((x,.145,-.285),(.11,.004,.012),'Polished_edge',.001))
    part('tread_%d'%i,'deck',p,(x,.13,0),.28+i*.025)
for side,x in [('L',-.306),('R',.306)]:
    part('latch_'+side,'latch',[box((x,.085,.16),(.025,.065,.09),'Aged_brass'),box((x*.91,.119,.16),(.067,.015,.05),'Polished_edge')],(x,.054,.16),.19)
part('power_core','base',[cylinder((0,.052,.338),.047,.022,'Polished_edge'),cylinder((0,.066,.338),.028,.012,'Teal_inlay')],(0,.05,.338),.08)
for i,x in enumerate([-.11,0,.11]):
    p=[box((x-.012,.147,-.235),(.010,.004,.05),'Teal_inlay',.0005),box((x+.012,.147,-.235),(.010,.004,.05),'Teal_inlay',.0005)]
    for o,angle in zip(p,[.5,-.5]):o.rotation_euler.z=angle
    part('launch_mark_%d'%i,'deck',p,(x,.147,-.235),.32)

scene.render.fps=24
scene['asset_notes']='Original cosmetic launch plate. Runtime helix changes pitch at fixed wire radius; other parts stay rigid. No gameplay collision.'
for o in scene.objects:
    if o.type=='MESH':o.data.calc_loop_triangles()
triangles=sum(len(o.data.loop_triangles) for o in scene.objects if o.type=='MESH')
source=ASSET/'authoring/spring_plate.blend';export=ASSET/'exports/spring_plate.glb'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',export_animations=False,export_yup=True,export_tangents=False)
shutil.copy2(export,GAME/export.name)
data={'id':'spring_dash_v1','origin':'ground below launch position','forward':'-Z','deck_pivot':[0,.115,0],'coil':coil,'parts':records,'triangles':triangles,'part_count':len(records),'materials':len(M),'launch_seconds':.085,'hold_seconds':.055,'dissolve_seconds':.24,'source':'original Blender authoring; no Tripo regeneration'}
for path in [ASSET/'parts.json',GAME/'parts.json']:path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
report={**data,'passed':True,'blend_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(export.read_bytes()).hexdigest(),'bytes':export.stat().st_size}
(REPORT/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('SPRING_PLATE_BUILD_COMPLETE',len(records),triangles)
