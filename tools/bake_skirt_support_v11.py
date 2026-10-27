"""Build and bake the selected v11 skirt from the unchanged v10 source.
Independent 99-bone report candidate; 83 existing rest matrices are preserved.
No original skirt coordinates, UVs or body/upper weights are edited. Clearance
translations are sampled at 3-frame intervals plus explicit review poses and
linearly interpolated; orientations are evaluated and baked every frame.
This is artist-guided support baking, not live cloth or arbitrary-pose clearance.
"""
import bpy,numpy as np,math,json,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'reports/source_outfit_v11/skirt_agent';OUT.mkdir(parents=True,exist_ok=True)
s=bpy.context.scene;r=bpy.data.objects['PlayerRig_v7'];old=bpy.data.objects['SourceOutfit_Skirt_v10'];upper_names=[f'DEF-skirt.{i+1:02}' for i in range(16)];lower_names=[f'DEF-skirt_lower.{i+1:02}' for i in range(16)]
preserved={b.name:np.array(b.matrix_local) for b in r.data.bones};r.data.pose_position='REST';r.animation_data.action=None
for tr in r.animation_data.nla_tracks:tr.mute=True
for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.ops.object.select_all(action='DESELECT');r.hide_set(False);r.select_set(True);bpy.context.view_layer.objects.active=r;bpy.ops.object.mode_set(mode='EDIT')
for name,parent_name in zip(lower_names,upper_names):
    parent=r.data.edit_bones[parent_name];b=r.data.edit_bones.new(name);b.head=parent.head.lerp(parent.tail,.5);b.tail=parent.tail;b.roll=parent.roll;b.parent=parent;b.use_deform=True
bpy.ops.object.mode_set(mode='OBJECT')
for name in lower_names:r.pose.bones[name].rotation_mode='QUATERNION'
new=old.copy();new.data=old.data.copy();new.name='SourceOutfit_Skirt_v11';s.collection.objects.link(new);new.hide_render=False;new.hide_viewport=False;new.hide_set(False);old.hide_render=True;old.hide_set(True)
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def bind(obj):
    for b in r.data.bones:
        if b.name not in obj.vertex_groups:obj.vertex_groups.new(name=b.name)
    ids=list(range(len(obj.data.vertices)))
    for g in obj.vertex_groups:g.remove(ids)
    for vert in obj.data.vertices:
        x,y,z=vert.co;angle=math.atan2((y+.004)/.146,x/.209)%(2*math.pi);v=angle*16/(2*math.pi);i=int(v);t=v-i;bs=[(1-t)**3/6,(3*t**3-6*t*t+4)/6,(-3*t**3+3*t*t+3*t+1)/6,t**3/6]
        depth=(1.047-z)/.346;active=smooth(0,.25,depth);lower=smooth(.35,.65,depth)
        pairs={'DEF-pelvis':1-active}
        for j,value in enumerate(bs):
            k=(i+j-1)%16;pairs[upper_names[k]]=value*active*(1-lower);pairs[lower_names[k]]=value*active*lower
        for name,value in pairs.items():
            if value>1e-8:obj.vertex_groups[name].add([vert.index],value,'REPLACE')
bind(new)
# Continuous inner lining: an added surface, not replacement of exterior pleats.
N=64;zs=np.linspace(1.052,.678,17);vertices=[];faces=[]
for z in zs:
    t=max(0,min(1,(1.047-z)/.365));rx=.129+.079*t**.72-.004;ry=.100+.046*t**.72-.004
    for i in range(N):a=2*math.pi*i/N;vertices.append((rx*math.cos(a),ry*math.sin(a)-.004,z))
for row in range(len(zs)-1):
    for i in range(N):j=(i+1)%N;faces.append((row*N+i,(row+1)*N+i,(row+1)*N+j,row*N+j))
mesh=bpy.data.meshes.new('Skirt_Lining_v11');mesh.from_pydata(vertices,[],faces);mesh.update();lining=bpy.data.objects.new('SourceOutfit_SkirtLining_v11',mesh);s.collection.objects.link(lining)
for face in mesh.polygons:face.use_smooth=True
mat=bpy.data.materials.new('Skirt_NavyLining_v11');mat.use_nodes=True;bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
if bsdf is None:
    bsdf=mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled');output=mat.node_tree.nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(bsdf.outputs['BSDF'],output.inputs['Surface'])
bsdf.inputs['Base Color'].default_value=(.035,.042,.065,1);bsdf.inputs['Roughness'].default_value=.9;mesh.materials.append(mat);bind(lining);arm=lining.modifiers.new('SharedPlayerRig','ARMATURE');arm.object=r
def pose(clip,frame):
    for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    r.data.pose_position='POSE';a=bpy.data.actions[clip];r.animation_data.action=a;r.animation_data.action_slot=a.slots[0];s.frame_set(frame);bpy.context.view_layer.update()
    basis={pb.name:pb.matrix_basis.copy() for pb in r.pose.bones};r.animation_data.action=None
    for name,matrix in basis.items():r.pose.bones[name].matrix_basis=matrix
    bpy.context.view_layer.update()
def support_pose(cap=108,lower_fraction=.35,neighbor=16):
    pelvis=r.pose.bones['DEF-pelvis'];delta=pelvis.matrix@pelvis.bone.matrix_local.inverted();inv=delta.to_3x3().inverted();original=[];rest_angles=[]
    for name in upper_names:
        pb=r.pose.bones[name];d=inv@(pb.tail-pb.head).normalized();original.append(math.atan2(math.hypot(d.x,d.y),-d.z));dr=(pb.bone.tail_local-pb.bone.head_local).normalized();rest_angles.append(math.atan2(math.hypot(dr.x,dr.y),-dr.z))
    angles=np.minimum(original,math.radians(cap));base=angles.copy()
    for i in range(16):
        for j in range(16):angles[i]=max(angles[i],base[j]-math.radians(neighbor)*min((i-j)%16,(j-i)%16))
    def desired(rest,head,angle,radial):
        base=delta@rest;direction=delta.to_3x3()@(radial*math.sin(angle)+Vector((0,0,-math.cos(angle))));rest_dir=(base.to_3x3()@Vector((0,1,0))).normalized();rotation=rest_dir.rotation_difference(direction)@base.to_quaternion();return Matrix.LocRotScale(head,rotation,Vector((1,1,1)))
    for name,angle in zip(upper_names,angles):
        pb=r.pose.bones[name];rest=pb.bone.matrix_local;radial=Vector((pb.bone.head_local.x,pb.bone.head_local.y+.004,0)).normalized();head=delta@pb.bone.head_local;target=desired(rest,head,angle,radial);pb.matrix_basis=rest.inverted()@pelvis.bone.matrix_local@pelvis.matrix.inverted()@target
    bpy.context.view_layer.update()
    for i,(name,parent_name) in enumerate(zip(lower_names,upper_names)):
        pb=r.pose.bones[name];parent=r.pose.bones[parent_name];rest=pb.bone.matrix_local;head=parent.matrix@parent.bone.matrix_local.inverted()@pb.bone.head_local;radial=Vector((parent.bone.head_local.x,parent.bone.head_local.y+.004,0)).normalized();angle=rest_angles[i]+lower_fraction*max(0,angles[i]-rest_angles[i]);target=desired(rest,head,angle,radial);pb.matrix_basis=rest.inverted()@parent.bone.matrix_local@parent.matrix.inverted()@target
    bpy.context.view_layer.update();return [math.degrees(x) for x in angles]
p=np.array([v.co[:] for v in new.data.vertices]);edges=np.array([e.vertices[:] for e in new.data.edges]);length=np.linalg.norm(p[edges[:,0]]-p[edges[:,1]],axis=1)
new.data.calc_loop_triangles();triangles=np.array([t.vertices[:] for t in new.data.loop_triangles]);support_names=upper_names+lower_names;skin=np.zeros((len(p),32))
for v in new.data.vertices:
    for g in v.groups:
        name=new.vertex_groups[g.group].name
        if name in support_names:skin[v.index,support_names.index(name)]=g.weight
def collision_adjust(stride=1, iterations=7):
    """Regularized support translations from nearest-body clearance constraints.
    This is a local fitting heuristic, not continuous collision detection.
    """
    body=bpy.data.objects['TEMPLATE_CompleteCoveredBody_v8'];body.hide_viewport=False;body.hide_set(False);dg=bpy.context.evaluated_depsgraph_get();tree=BVHTree.FromObject(body,dg);q0=np.array([v.co[:] for v in new.evaluated_get(dg).data.vertices]);T=np.zeros((32,3));base={n:r.pose.bones[n].matrix.copy() for n in support_names}
    regular=np.diag(np.repeat([25.]*16+[2.]*16,3));links=[]
    for layer in (0,16):
        for i in range(16):
            for axis in range(3):
                row=np.zeros(96);row[(layer+i)*3+axis]=2;row[(layer+(i+1)%16)*3+axis]=-2;links.append(row)
    regular+=np.array(links).T@np.array(links)
    for iteration in range(iterations):
        q=q0+skin@T;ids=[];normals=[];offset=[]
        for i in range(0,len(q),stride):
            point=q[i]
            if skin[i].sum()<.2:continue
            hit,n,_,_=tree.find_nearest(Vector(point));signed=(Vector(point)-hit).dot(n)
            if signed<.003:ids.append(i);normals.append(tuple(n));offset.append(.005-signed)
        if not ids:break
        A=(skin[ids,:,None]*np.array(normals)[:,None,:]).reshape(-1,96);rhs=np.array(offset)+A@T.ravel();candidate=np.linalg.solve(A.T@A+regular,A.T@rhs).reshape(32,3)
        maximum=np.r_[np.full(16,.035),np.full(16,.055)];norm=np.linalg.norm(candidate,axis=1);candidate*=np.minimum(1,maximum/np.maximum(norm,1e-12))[:,None];T=.3*T+.7*candidate
    for layer in (upper_names,lower_names):
        for name in layer:
            pb=r.pose.bones[name];desired=base[name].copy();desired.translation+=Vector(T[support_names.index(name)]);parent=pb.parent;pb.matrix_basis=pb.bone.matrix_local.inverted()@parent.bone.matrix_local@parent.matrix.inverted()@desired
        bpy.context.view_layer.update()
    return {'maximum_support_translation':float(np.linalg.norm(T,axis=1).max()),'translation_vectors':T.tolist()}
def triangle_crossings(q,body):
    dg=bpy.context.evaluated_depsgraph_get();bm=body.evaluated_get(dg).data;bm.calc_loop_triangles();bp=np.array([v.co[:] for v in bm.vertices]);bf=np.array([t.vertices[:] for t in bm.loop_triangles]);st=BVHTree.FromPolygons([Vector(v) for v in q],triangles.tolist(),all_triangles=True);bt=BVHTree.FromPolygons([Vector(v) for v in bp],bf.tolist(),all_triangles=True);pairs=np.array(st.overlap(bt),dtype=int)
    if len(pairs)==0:return {'crossing_pairs':0,'crossing_skirt_faces':0}
    A=q[triangles[pairs[:,0]]];B=bp[bf[pairs[:,1]]]
    def crosses(p0,p1,tri):
        direction=p1-p0;e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h);good=abs(det)>1e-12;inv=np.zeros_like(det);inv[good]=1/det[good];delta=p0-tri[:,0];u=inv*np.einsum('ij,ij->i',delta,h);qq=np.cross(delta,e1);v=inv*np.einsum('ij,ij->i',direction,qq);t=inv*np.einsum('ij,ij->i',e2,qq);return good&(u>=1e-7)&(v>=1e-7)&(u+v<=1-1e-7)&(t>=1e-7)&(t<=1-1e-7)
    hit=np.zeros(len(pairs),bool)
    for j in range(3):hit|=crosses(A[:,j],A[:,(j+1)%3],B)|crosses(B[:,j],B[:,(j+1)%3],A)
    return {'crossing_pairs':int(hit.sum()),'crossing_skirt_faces':int(len(np.unique(pairs[hit,0])))}
def metric():
    dg=bpy.context.evaluated_depsgraph_get();q=np.array([v.co[:] for v in new.evaluated_get(dg).data.vertices]);ratio=np.linalg.norm(q[edges[:,0]]-q[edges[:,1]],axis=1)/np.maximum(length,1e-9);body=bpy.data.objects['TEMPLATE_CompleteCoveredBody_v8'];body.hide_viewport=False;body.hide_set(False);tree=BVHTree.FromObject(body,bpy.context.evaluated_depsgraph_get());inside=[]
    for point in q:
        hit,n,_,_=tree.find_nearest(Vector(point));signed=(Vector(point)-hit).dot(n)
        if signed<-.002:inside.append(-signed)
    return {'edge_max':float(ratio.max()),'edge_p99':float(np.percentile(ratio,99)),'edges_gt2':int(np.sum(ratio>2)),'edges_gt4':int(np.sum(ratio>4)),'nearest_surface_negative_2mm_hint':len(inside),'max_negative_normal_offset_hint':max(inside,default=0),**triangle_crossings(q,body)}

# The independent lining follows a simplified copy of the actual source shell.
bpy.data.objects.remove(lining,do_unlink=True)
lining=old.copy();lining.data=old.data.copy();lining.name='SourceOutfit_SkirtLining_v11';s.collection.objects.link(lining);lining.hide_viewport=False;lining.hide_render=False;lining.hide_set(False)
for modifier in list(lining.modifiers):lining.modifiers.remove(modifier)
for vertex in lining.data.vertices:
    n=Vector((vertex.co.x,vertex.co.y+.004,0)).normalized();vertex.co-=n*.0015
bpy.ops.object.select_all(action='DESELECT');lining.select_set(True);bpy.context.view_layer.objects.active=lining
dec=lining.modifiers.new('LiningOnlySimplification','DECIMATE');dec.ratio=.2;bpy.ops.object.modifier_apply(modifier=dec.name)
# Reverse shell faces for the inward surface.
import bmesh
bm=bmesh.new();bm.from_mesh(lining.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(lining.data);bm.free();lining.data.update()
lining.data.materials.clear();lining.data.materials.append(mat);mat.use_backface_culling=True
for polygon in lining.data.polygons:polygon.material_index=0;polygon.use_smooth=True
bind(lining);arm=lining.modifiers.new('SharedPlayerRig','ARMATURE');arm.object=r
for slot in new.material_slots:
    slot.material=slot.material.copy();slot.material.name='Skirt_OriginalOutside_v11';slot.material.use_backface_culling=True

import sys,time
sys.path.insert(0,str(ROOT/'tools'))
from inspect_cloth_v11 import create_waist_twist_action
waist=create_waist_twist_action(r);waist.use_fake_user=True
actions=sorted([a for a in bpy.data.actions if a.name.startswith('v7_') or a.name=='v11_Trial_WaistTwist'],key=lambda a:a.name)
assert len(actions)==12,[a.name for a in actions]
report={'method':'32 skirt supports; 4 angular by 2 vertical influences; 3-frame sampled regularized clearance, exact diagnostic samples','source':'source_outfit_v10.blend','bones':len(r.data.bones),'old_83_rest_equal':all(np.array_equal(np.array(r.data.bones[n].matrix_local),m) for n,m in preserved.items()),'rest_geometry_equal':np.array_equal(np.array([v.co[:] for v in old.data.vertices]),p),'uv_equal':all(tuple(a.uv)==tuple(b.uv) for a,b in zip(old.data.uv_layers.active.data,new.data.uv_layers.active.data)),'lining_vertices':len(lining.data.vertices),'lining_triangles':sum(len(f.vertices)-2 for f in lining.data.polygons),'max_influences':{o.name:max(sum(g.weight>1e-8 for g in v.groups) for v in o.data.vertices) for o in [new,lining]},'actions':{}}
assert report['old_83_rest_equal'] and report['rest_geometry_equal'] and report['uv_equal']
assert max(report['max_influences'].values())<=8
def bags(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:yield bag
def protected_curves(action):
    values=[]
    for bag in bags(action):
        for f in bag.fcurves:
            if 'pose.bones["DEF-skirt' in f.data_path:continue
            values.append((f.data_path,f.array_index,[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right),k.interpolation) for k in f.keyframe_points]))
    return hashlib.sha256(repr(sorted(values,key=lambda x:(x[0],x[1]))).encode()).hexdigest()
def apply_translation(T):
    base={name:r.pose.bones[name].matrix.copy() for name in support_names}
    for layer in (upper_names,lower_names):
        for name in layer:
            pb=r.pose.bones[name];desired=base[name].copy();desired.translation+=Vector(T[support_names.index(name)]);parent=pb.parent;pb.matrix_basis=pb.bone.matrix_local.inverted()@parent.bone.matrix_local@parent.matrix.inverted()@desired
        bpy.context.view_layer.update()
all_matrices={};start_time=time.perf_counter()
for action in actions:
    name=action.name;first,last=map(lambda x:int(round(x)),action.frame_range);frames=list(range(first,last+1));exact={first,last,7,17,19,25,42,67,73,85,113};samples=sorted(set(range(first,last+1,3))|{f for f in exact if first<=f<=last});translations={}
    for frame in samples:
        pose(name,frame);support_pose(lower_fraction=.8,neighbor=16)
        result=collision_adjust(stride=1 if frame in exact else 3,iterations=7 if frame in exact else 5)
        translations[frame]=np.array(result['translation_vectors'])
    values=np.empty((len(frames),32,4,4),dtype=np.float64)
    for fi,frame in enumerate(frames):
        pose(name,frame);support_pose(lower_fraction=.8,neighbor=16)
        if frame in translations:T=translations[frame]
        else:
            j=int(np.searchsorted(samples,frame));lo,hi=samples[j-1],samples[j];alpha=(frame-lo)/(hi-lo);T=(1-alpha)*translations[lo]+alpha*translations[hi]
        apply_translation(T)
        for i,n in enumerate(support_names):values[fi,i]=np.array(r.pose.bones[n].matrix_basis)
    if name=='v7_Trial_RunCycle':
        # Godot recognizes the Cycle suffix as looping. Match the duplicated
        # end pose exactly, including every added skirt support transform.
        values[-1]=values[0]
    all_matrices[name]=values
    original_hash=protected_curves(action);action.name='ARCHIVE_v10_'+name;action.use_fake_user=True;candidate=action.copy();candidate.name=name;candidate.use_fake_user=True
    for bag in bags(candidate):
        for curve in list(bag.fcurves):
            if 'pose.bones["DEF-skirt' in curve.data_path:bag.fcurves.remove(curve)
    r.animation_data.action=candidate;r.animation_data.action_slot=candidate.slots[0];previous={}
    for fi,frame in enumerate(frames):
        for i,n in enumerate(support_names):
            pb=r.pose.bones[n];loc,quat,scale=Matrix(values[fi,i]).decompose()
            if n in previous and quat.dot(previous[n])<0:quat.negate()
            previous[n]=quat.copy();pb.location=loc;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=quat;pb.scale=scale
            for channel in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=channel,frame=frame,group=n)
    for bag in bags(candidate):
        for curve in bag.fcurves:
            if 'pose.bones["DEF-skirt' in curve.data_path:
                for key in curve.keyframe_points:key.interpolation='LINEAR'
    assert protected_curves(candidate)==original_hash,(name,'body channel changed')
    candidate['v11_skirt_baked']=True;candidate['skirt_clearance_sample_step']=3
    report['actions'][name]={'frames':len(frames),'range':[first,last],'clearance_samples':len(samples),'body_tracks_sha256':original_hash,'protected_body_tracks_unchanged':True}
    (OUT/'bake_progress.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('BAKED',name,len(frames),'elapsed',round(time.perf_counter()-start_time,1),flush=True)
report['total_frames']=sum(x['frames'] for x in report['actions'].values());report['elapsed_seconds']=time.perf_counter()-start_time
np.savez_compressed(OUT/'skirt_support_baked_matrices.npz',support_names=np.array(support_names),**all_matrices)
(OUT/'skirt_bake_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
for track in r.animation_data.nla_tracks:track.mute=True
r.animation_data.action=None;r.data.pose_position='REST';r['rig_id']='player_humanoid_v11';s.frame_set(1)
for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
new['candidate_status']='12 diagnostic clips baked; integration/runtime validation pending'
new['rig_id']='player_humanoid_v11';lining['rig_id']='player_humanoid_v11'
body=bpy.data.objects['TEMPLATE_CompleteCoveredBody_v8'];body.hide_render=True;body.hide_set(True)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str((OUT/'skirt_v11_baked_candidate.blend').resolve()))
print('SKIRT_V11_BAKED_CANDIDATE_SAVED',json.dumps(report),flush=True)
