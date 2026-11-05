"""Shared authoring utilities for the two remaining Tripo batch2 actors.

Only runs in the caller's isolated Blender process. Original downloads and packed
sources are inputs; semantic reduction, closed joints and atlases are derivatives.
"""
import bpy, bmesh, json, math, sys, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
I=Matrix.Identity(4)

def dump(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,ensure_ascii=False),encoding='utf8')

def smooth(a,b,x):
    x=max(0.,min(1.,(x-a)/(b-a)));return x*x*(3-2*x)

def about(p,axis,angle):
    return Matrix.Translation(p)@Matrix.Rotation(angle,4,axis)@Matrix.Translation(-Vector(p))

def join(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1:bpy.ops.object.join()
    o=bpy.context.object;o.name=name;return o

def material(name,color,metal=.7,rough=.4):
    m=bpy.data.materials.new(name);m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    return m

def mesh_object(name,verts,faces,mat):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(mat)
    o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o)
    for p in me.polygons:p.use_smooth=True
    return o

def cylinder(name,a,b,r,mat,n=12,r2=None):
    a,b=Vector(a),Vector(b);d=(b-a).normalized();u=d.cross(Vector((0,0,1)))
    if u.length<.01:u=d.cross(Vector((1,0,0)))
    u.normalize();v=d.cross(u);r2=r if r2 is None else r2
    vs=[p+rr*(u*math.cos(i*math.tau/n)+v*math.sin(i*math.tau/n)) for p,rr in [(a,r),(b,r2)] for i in range(n)]
    fs=[]
    for i in range(n):
        j=(i+1)%n;fs.extend([(i,j,j+n),(i,j+n,i+n)])
    fs.extend([tuple(reversed(range(n))),tuple(range(n,n*2))])
    return mesh_object(name,vs,fs,mat)

class Geometry:
    def __init__(self,actor,version='v1'):
        assert bpy.app.background
        self.actor=actor;self.base=ROOT/f'assets/actors/automation_batch2/{actor}_game_{version}'
        self.out=ROOT/f'reports/automation_batch2_complete_v1/{actor}'
        for p in (self.base/'textures',self.out/'geometry',self.out/'validation',self.out/'local'):p.mkdir(parents=True,exist_ok=True)
        self.source=ROOT/f'assets/actors/automation_batch2/{actor}_tripo_v1/{actor}_segmented.blend'
        self.source_hash=hashlib.sha256(self.source.read_bytes()).hexdigest()
        bpy.ops.wm.open_mainfile(filepath=str(self.source));self.sc=bpy.context.scene
        self.sc.render.fps=24
        self.src={int(o.name.rsplit('_',1)[1]):o for o in self.sc.objects if o.type=='MESH'}
        for o in list(self.sc.objects):
            if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)
        self.high={};self.low={};self.provenance=[];self.repairs=[];self.offsets={}
        self.dark=material('Author_Recess',(.012,.027,.028),.65,.48)
        self.brass=material('Author_Brass',(.28,.165,.055),.8,.39)
        self.steel=material('Author_Steel',(.16,.20,.21),.86,.31)
        self.teal=material('Author_Teal',(.018,.085,.078),.55,.46)
        self.cyan=material('Author_Cyan',(.02,.64,.56),.05,.24)

    def extract(self,label,ids,transform,predicate=None):
        obs=[]
        for n in ids:
            o=self.src[n];old=o.data;mw=o.matrix_world
            chosen=[p for p in old.polygons if predicate is None or predicate(mw@p.center)]
            if not chosen:continue
            used=sorted({v for p in chosen for v in p.vertices});remap={v:i for i,v in enumerate(used)}
            me=bpy.data.meshes.new(label+'_source')
            me.from_pydata([transform(mw@old.vertices[v].co) for v in used],[],[[remap[v] for v in p.vertices] for p in chosen])
            for m in old.materials:me.materials.append(m)
            uv=me.uv_layers.new(name='UVMap')
            origin=transform(Vector());jacobian=Matrix(tuple(transform(Vector(v))-origin for v in [(1,0,0),(0,1,0),(0,0,1)])).transposed()
            nm=(jacobian@mw.to_3x3()).inverted().transposed();normals=[]
            for a,b in zip(chosen,me.polygons):
                b.use_smooth=True;b.material_index=a.material_index
                for ai,bi in zip(a.loop_indices,b.loop_indices):
                    uv.data[bi].uv=old.uv_layers.active.data[ai].uv
                    normals.append(tuple((nm@old.corner_normals[ai].vector).normalized()))
            me.normals_split_custom_set(normals)
            ob=bpy.data.objects.new(label+'_source',me);self.sc.collection.objects.link(ob);obs.append(ob)
            self.provenance.append({'source_part':n,'group':label,'triangles':len(chosen)})
        if label in self.high:obs.insert(0,self.high[label])
        self.high[label]=join(obs,'HIGH_'+label)

    def reduce(self,budgets):
        for o in self.src.values():bpy.data.objects.remove(o,do_unlink=True)
        for name,h in self.high.items():
            o=h.copy();o.data=h.data.copy();self.sc.collection.objects.link(o);o.name='LOW_'+name
            bm=bmesh.new();bm.from_mesh(o.data)
            bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000008)
            bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000002)
            bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
            bpy.context.view_layer.objects.active=o
            d=o.modifiers.new('Silhouette reduction','DECIMATE');d.ratio=min(1,budgets[name]/sum(len(p.vertices)-2 for p in o.data.polygons));d.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=d.name)
            if o.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
            for p in o.data.polygons:p.use_smooth=True
            self.low[name]=o

    def add(self,label,ob):
        hi=ob.copy();hi.data=ob.data.copy();self.sc.collection.objects.link(hi)
        if label in self.low:
            self.low[label]=join([self.low[label],ob],'LOW_'+label);self.high[label]=join([self.high[label],hi],'HIGH_'+label)
        else:self.low[label]=ob;self.high[label]=hi

    def cleanup(self,cap_groups=()):
        for name,o in self.low.items():
            bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
            bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001)
            removed=[]
            while True:
                bad=next((e for e in bm.edges if len(e.link_faces)>2),None)
                if bad is None:break
                f=min(bad.link_faces,key=lambda f:f.calc_area());removed.append({'area':f.calc_area(),'center':list(f.calc_center_median())})
                bmesh.ops.delete(bm,geom=[f],context='FACES_ONLY')
            wire=[e for e in bm.edges if not e.link_faces]
            if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
            loose=[v for v in bm.verts if not v.link_faces]
            if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
            caps=0;cap_faces=set();removed_caps=[]
            if name in cap_groups:
                new=bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0).get('faces',[])
                cv=[];cf=[]
                for f in list(new):
                    vs=list(f.verts);f.normal_update();center=f.calc_center_median()-f.normal*.002
                    bmesh.ops.delete(bm,geom=[f],context='FACES_ONLY');vcenter=bm.verts.new(center)
                    for i in range(len(vs)):
                        vv=(vs[i],vs[(i+1)%len(vs)],vcenter);cap_faces.add(bm.faces.new(vv))
                        cf.append(tuple(range(len(cv),len(cv)+3)));cv.extend(tuple(v.co) for v in vv);caps+=1
                if cf:self.high[name]=join([self.high[name],mesh_object('Recessed_caps',cv,cf,self.dark)],'HIGH_'+name)
            bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
            todo=set(bm.faces)
            while todo:
                seed=todo.pop();component={seed};stack=[seed]
                while stack:
                    f=stack.pop()
                    for e in f.edges:
                        for other in e.link_faces:
                            if other in todo:todo.remove(other);component.add(other);stack.append(other)
                closed=all(len(e.link_faces)==2 for f in component for e in f.edges)
                volume=sum(f.verts[0].co.dot(f.verts[1].co.cross(f.verts[2].co))/6 for f in component)
                if closed and volume<0:bmesh.ops.reverse_faces(bm,faces=list(component))
            # A new recessed cap can touch an existing internal source shelf.
            # Remove only the redundant cap triangle, never a visible source face.
            if cap_faces:
                bm.faces.ensure_lookup_table();bm.faces.index_update();bm.normal_update();tree=BVHTree.FromBMesh(bm)
                def inside(q,a,b,c,n):
                    return min((b-a).cross(q-a).dot(n),(c-b).cross(q-b).dot(n),(a-c).cross(q-c).dot(n))>=-1e-9
                redundant=set()
                for f in cap_faces:
                    if not f.is_valid:continue
                    for q in [f.calc_center_median()]+[f.calc_center_median().lerp(v.co,.6) for v in f.verts]:
                        for _,_,idx,_ in tree.find_nearest_range(q,.00015):
                            other=bm.faces[idx]
                            if other==f or set(f.verts)&set(other.verts) or f.normal.dot(other.normal)<.999:continue
                            a,b,c=[v.co for v in other.verts];projected=q-other.normal*other.normal.dot(q-a)
                            if inside(projected,a,b,c,other.normal):redundant.add(f)
                for f in redundant:removed_caps.append({'center':list(f.calc_center_median()),'area':f.calc_area()})
                if redundant:bmesh.ops.delete(bm,geom=list(redundant),context='FACES_ONLY')
            bm.to_mesh(o.data);bm.free()
            self.repairs.append({'group':name,'removed_nonmanifold_flaps':removed,'new_cap_triangles':caps,'redundant_internal_caps_removed':removed_caps})

    def bake(self,glow_groups=(),cage=.018):
        part_sizes={}
        for i,(name,o) in enumerate(self.low.items()):
            offset=Vector(((i%6)*4,(i//6)*4,0));self.offsets[name]=offset
            for ob in (o,self.high[name]):
                for v in ob.data.vertices:v.co+=offset
            for uv in list(o.data.uv_layers):o.data.uv_layers.remove(uv)
            o.data.uv_layers.new(name='UVMap');g=o.vertex_groups.new(name=name);g.add(list(range(len(o.data.vertices))),1.,'REPLACE')
            part_sizes[name]=sum(len(p.vertices)-2 for p in o.data.polygons)
        lo=join(list(self.low.values()),self.actor+'_Rigid_Surface')
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.002,area_weight=0.,correct_aspect=True,scale_to_bounds=True)
        bpy.ops.uv.pack_islands(rotate=True,margin=.006,shape_method='AABB');bpy.ops.object.mode_set(mode='OBJECT')
        hi=join(list(self.high.values()),'Atlas_Projection_Source')
        sc=self.sc;sc.render.engine='CYCLES';sc.cycles.samples=16
        try:
            prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='CUDA';prefs.get_devices()
            for d in prefs.devices:d.use=d.type!='CPU'
            sc.cycles.device='GPU'
        except Exception:sc.cycles.device='CPU'
        sc.render.bake.use_selected_to_active=True;sc.render.bake.cage_extrusion=cage;sc.render.bake.max_ray_distance=cage*2.5;sc.render.bake.margin=5;sc.render.bake.use_clear=True
        m=material('BakeTarget',(.5,.5,.5));lo.data.materials.clear();lo.data.materials.append(m)
        for p in lo.data.polygons:p.material_index=0
        target=m.node_tree.nodes.new('ShaderNodeTexImage');m.node_tree.nodes.active=target
        mats=list({m for m in hi.data.materials if m});original={}
        for m in mats:
            out=next(n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL');original[m]=out.inputs['Surface'].links[0].from_socket
        images={}
        for label,kind in [('color','EMIT'),('orm','EMIT'),('normal','NORMAL')]:
            im=bpy.data.images.new(self.actor+'_'+label,width=1024,height=1024,alpha=False);im.colorspace_settings.name='sRGB' if label=='color' else 'Non-Color';target.image=im
            if label=='normal':im.generated_color=(.5,.5,1,1)
            for m in mats:
                ns=m.node_tree.nodes;ls=m.node_tree.links;out=next(n for n in ns if n.type=='OUTPUT_MATERIAL')
                if kind=='NORMAL':ls.new(original[m],out.inputs['Surface']);continue
                bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED');em=ns.new('ShaderNodeEmission')
                if label=='color':
                    s=bs.inputs['Base Color']
                    if s.is_linked:ls.new(s.links[0].from_socket,em.inputs['Color'])
                    else:em.inputs['Color'].default_value=s.default_value
                else:
                    comb=ns.new('ShaderNodeCombineColor');comb.inputs['Red'].default_value=1
                    for c,sock in [('Green','Roughness'),('Blue','Metallic')]:
                        s=bs.inputs[sock]
                        if s.is_linked:ls.new(s.links[0].from_socket,comb.inputs[c])
                        else:comb.inputs[c].default_value=s.default_value
                    ls.new(comb.outputs['Color'],em.inputs['Color'])
                ls.new(em.outputs[0],out.inputs['Surface'])
            bpy.ops.object.select_all(action='DESELECT');hi.select_set(True);lo.select_set(True);bpy.context.view_layer.objects.active=lo
            bpy.ops.object.bake(type=kind)
            im.filepath_raw=str(self.base/'textures'/f'{self.actor}_{label}.png');im.file_format='PNG';im.save();im.pack();images[label]=im
            print('BAKED',self.actor,label,flush=True)
        for m in mats:m.node_tree.links.new(original[m],next(n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
        bpy.data.objects.remove(hi,do_unlink=True)
        emission=images['color'].copy();emission.name=self.actor+'_emission';emission.scale(128,128)
        emission.filepath_raw=str(self.base/'textures'/f'{self.actor}_emission.png');emission.file_format='PNG';emission.save();emission.pack()
        def runtime_mat(glow):
            m=material('M_'+self.actor+('_Glow' if glow else '_Surface'),(.5,.5,.5));ns=m.node_tree.nodes;ls=m.node_tree.links;bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED');tex={}
            for label,im in images.items():n=ns.new('ShaderNodeTexImage');n.image=im;tex[label]=n
            ls.new(tex['color'].outputs['Color'],bs.inputs['Base Color'])
            s=ns.new('ShaderNodeSeparateColor');ls.new(tex['orm'].outputs['Color'],s.inputs['Color']);ls.new(s.outputs['Green'],bs.inputs['Roughness']);ls.new(s.outputs['Blue'],bs.inputs['Metallic'])
            n=ns.new('ShaderNodeNormalMap');ls.new(tex['normal'].outputs['Color'],n.inputs['Color']);ls.new(n.outputs['Normal'],bs.inputs['Normal'])
            if glow:
                e=ns.new('ShaderNodeTexImage');e.image=emission;ls.new(e.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=1.3
            return m
        lo.data.materials.clear();lo.data.materials.append(runtime_mat(False))
        if glow_groups:lo.data.materials.append(runtime_mat(True))
        for p in lo.data.polygons:p.material_index=int(lo.vertex_groups[lo.data.vertices[p.vertices[0]].groups[0].group].name in glow_groups)
        for v in lo.data.vertices:v.co-=self.offsets[lo.vertex_groups[v.groups[0].group].name]
        lo.data.update();self.mesh=lo
        sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1
        for key in list(sc.keys()):del sc[key]
        sc['stage']='Prepared Tripo derivative; no gameplay integration';sc['forward']='Blender +Y / Godot -Z'
        bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(self.base/f'{self.actor}_geometry.blend'),compress=True)
        self.report={'actor':self.actor,'triangles':sum(part_sizes.values()),'parts':len(part_sizes),'part_triangles':part_sizes,'provenance':self.provenance,'repairs':self.repairs,'source_sha256':self.source_hash,'source_unchanged':hashlib.sha256(self.source.read_bytes()).hexdigest()==self.source_hash,'bake':'exploded semantic pairs, color/normal/ORM 1024, emission 128; ORM R=1 (no AO bake)','glow_groups':list(glow_groups)}
        dump(self.base/'geometry.json',self.report)
        return lo

def make_rig(mesh,spec,name):
    sc=bpy.context.scene;data=bpy.data.armatures.new(name);rig=bpy.data.objects.new(name,data);sc.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
    for n,(p,parent) in spec.items():
        b=data.edit_bones.new(n);b.head=Vector(p);b.tail=Vector(p)+Vector((0,.05,0))
        if parent:b.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT');mesh.parent=rig
    m=mesh.modifiers.new('Rigid single-bone skin','ARMATURE');m.object=rig
    for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
    rig.animation_data_create();return rig

def part_points(mesh):
    points={g.name:[] for g in mesh.vertex_groups}
    for v in mesh.data.vertices:
        assert len(v.groups)==1 and abs(v.groups[0].weight-1)<1e-6
        points[mesh.vertex_groups[v.groups[0].group].name].append(v.co.copy())
    return points

def collapse(points,initial,duration,delay=.08):
    """Baked gravity, floor support from rotated vertices, no explosion/scale."""
    centers={n:sum(ps,Vector())/len(ps) for n,ps in points.items()};states={}
    for i,n in enumerate(points):
        c=centers[n];d=initial[n];angle=i*2.399963
        states[n]={'p':d@c,'q':d.to_quaternion(),'v':Vector((math.cos(angle)*.16,math.sin(angle)*.16,.0)),
          'axis':Vector((math.sin(i*1.37+.3),math.cos(i*2.14),.23)).normalized(),'spin':1.2+.4*(i%5),'delay':delay+.015*(i%5)}
    rows=[];steps=math.ceil(duration*120)
    for j in range(steps+1):
        row={n:Matrix.Translation(s['p'])@s['q'].to_matrix().to_4x4()@Matrix.Translation(-centers[n]) for n,s in states.items()};rows.append(row)
        dt=duration/steps;t=j*dt
        for n,s in states.items():
            if t<s['delay']:continue
            s['v'].z-=8.5*dt;s['p']+=s['v']*dt;s['q']=(Quaternion(s['axis'],s['spin']*dt)@s['q']).normalized()
            support=-min((s['q']@(p-centers[n])).z for p in points[n])+.012
            if s['p'].z<support:
                s['p'].z=support;s['v'].z=max(0,-s['v'].z*.10) if s['v'].z<-.4 else 0
                s['v'].x*=math.exp(-16*dt);s['v'].y*=math.exp(-16*dt);s['spin']*=math.exp(-17*dt)
            if t>duration*.78:s['spin']*=math.exp(-12*dt)
    return rows

def write_actions(actor,base,out,mesh,rig,spec,clips,pose,events=None,metadata=None):
    sc=bpy.context.scene;sc.render.fps=24;rests={b.name:b.matrix_local.copy() for b in rig.data.bones}
    rest_local={n:(rests[spec[n][1]].inverted()@m if spec[n][1] else m) for n,m in rests.items()}
    samples={};actions={};export={}
    for clip,(duration,loop) in clips.items():
        times=sorted(set([round(i/24,8) for i in range(int(duration*24)+1)]+[duration]+(events or {}).get(clip,[])))
        if clip=='death':times=sorted(set(times+[round(i/120,8) for i in range(int(duration*120)+1)]))
        # Blender merges keys closer than about .01 frame. Prefer the explicit
        # contact/event key instead of silently replacing a nearby 24 Hz key.
        for event in (events or {}).get(clip,[]):times=[t for t in times if t==event or abs(t-event)>=.0005]
        a=bpy.data.actions.new(clip);a.use_fake_user=True;rig.animation_data.action=a;previous={};records=[]
        for t in times:
            frame=1+t*24;sc.frame_set(int(frame),subframe=frame%1);d=pose(clip,t)
            world={n:d[n]@rests[n] for n in spec}
            for n,pb in rig.pose.bones.items():
                parent=spec[n][1];local=world[parent].inverted()@world[n] if parent else world[n]
                loc,q,scale=(rest_local[n].inverted()@local).decompose()
                assert max(abs(v-1) for v in scale)<2e-5,(clip,t,n,scale)
                if n in previous and q.dot(previous[n])<0:q.negate()
                previous[n]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=(1,1,1)
                for prop in ('location','rotation_quaternion','scale'):pb.keyframe_insert(prop,frame=frame,group=n)
            bpy.context.view_layer.update()
            bone_error=max(((rig.pose.bones[n].matrix.translation-world[n].translation).length,n) for n in spec)
            # Deep inherited armour chains need <30 micrometres of float32
            # decomposition tolerance when independently detached at death.
            assert bone_error[0]<(3e-5 if actor.endswith('_armour') else 1e-5),(clip,t,bone_error,rig.pose.bones[bone_error[1]].matrix.translation[:],world[bone_error[1]].translation[:])
            records.append({'time':t,'world':{n:[list(r) for r in m] for n,m in world.items()}})
        for layer in a.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        assert len(fc.keyframe_points)==len(times),(clip,len(fc.keyframe_points),len(times))
                        for k in fc.keyframe_points:k.interpolation='LINEAR'
        a['duration_seconds']=duration;a['loop']=loop;actions[clip]=a;samples[clip]=times;export[clip]=records
        tr=rig.animation_data.nla_tracks.new();tr.name='CLIP_'+clip;tr.mute=True;st=tr.strips.new(clip,1,a);st.action_slot=a.slots[0]
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=I
    sc.frame_set(1);bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(base/f'{actor}_static.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_yup=True,export_tangents=True)
    points=part_points(mesh)
    report={'clips':{n:{'seconds':d,'loop':loop,'times':samples[n]} for n,(d,loop) in clips.items()},'bones':len(spec),'parts':len(points),'triangles':sum(len(p.vertices)-2 for p in mesh.data.polygons),
      'parts_metadata':{n:{'bone':n,'parent':spec[n][1],'pivot_blender':list(spec[n][0]),'vertices':len(ps)} for n,ps in points.items()},
      'sockets':{n:{'parent':spec[n][1],'rest_blender':list(p)} for n,(p,parent) in spec.items() if n.startswith('Socket_')},'rest_world':{n:[list(r) for r in m] for n,m in rests.items()}}
    report.update(metadata or {});dump(base/'rig.json',report);dump(out/'local/animation_samples.json',export)
    rig.animation_data.action=actions.get('idle',actions.get('pulse'));rig.animation_data.action_slot=rig.animation_data.action.slots[0]
    sc.frame_end=1+round(rig.animation_data.action['duration_seconds']*24);sc.frame_start=1;sc.frame_set(1)
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(base/f'{actor}_game_v1.blend'),compress=True)
    return report
