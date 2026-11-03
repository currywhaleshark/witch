"""Live MCP: new fitted derivative, rigid upper slides, calf cuffs and tucked sleeve copies."""
import bpy,bmesh,json,math
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
ROOT='C:/Users/yurib/Documents/New project/witch'
s=bpy.data.scenes['ExoskeletonV3_Fit'];bpy.context.window.scene=s
assert bpy.data.scenes.get('ExoskeletonV4_Fit') is None
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v4/exoskeleton_v4.blend')
s.name='ExoskeletonV4_Fit';m=json.loads(s['exoskeleton_v3_manifest']);m['version']='exoskeleton_v4'
rig=bpy.data.objects['ExoskeletonRig_v3'];rig.name='ExoskeletonRig_v4'
for o in s.objects:
 if o.type=='ARMATURE':o.data.pose_position='REST'
for p in m['parts']:
 ob=bpy.data.objects[p['name']];ob.name=p['name'].replace('ExoV3_','ExoV4_');p['name']=ob.name
rest={n:Matrix(v) for n,v in m['body_rest_frames'].items()};old={n:Matrix(v) for n,v in m['rig_rest_frames'].items()}
frames={n:v.copy() for n,v in old.items()};m['config'].update({'arm_offset_wrist':.10,'shoulder_offset':[.16,.04,.035],'shoulder_swing_weight':.75,'shin_inset':.015,'shin_length_scale':.78})
archive=bpy.data.collections.new('V4_ORIGINALS_ARCHIVE');s.collection.children.link(archive);archive.hide_viewport=True;archive.hide_render=True
def frame(origin,direction,front):
 y=Vector(direction).normalized();z=Vector(front);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized();a=Matrix((x,y,z)).transposed().to_4x4();a.translation=origin;return a
def transform(ob,a):
 normal=a.to_3x3().inverted().transposed();nn=[(normal@n.vector).normalized() for n in ob.data.corner_normals]
 for v in ob.data.vertices:v.co=a@v.co
 ob.data.normals_split_custom_set(nn);ob.data.update()
 p=next(x for x in m['parts'] if x['name']==ob.name)
 if 'fit_matrix' in p:p['fit_matrix']=[list(r) for r in a@Matrix(p['fit_matrix'])]
def bind(ob,role,mat):
 ob.parent=rig;vg=ob.vertex_groups.new(name='EXO-'+role);vg.add(list(range(len(ob.data.vertices))),1,'REPLACE');mod=ob.modifiers.new('Rigid equipment skin','ARMATURE');mod.object=rig
 ob['part_role']=role;ob['rigid_bone']='EXO-'+role;frames[role]=mat
 m['parts'].append({'name':ob.name,'role':role,'bone':'EXO-'+role,'triangles':len(ob.data.polygons),'source':'v4 mechanical fitting connector'})
def newmesh(role,vertices,faces,materials):
 me=bpy.data.meshes.new('ExoV4_'+role);me.from_pydata(vertices,[],faces)
 for mat in materials:me.materials.append(mat)
 me.update();uv=me.uv_layers.new(name='UVMap')
 for poly in me.polygons:
  for k,li in enumerate(poly.loop_indices):uv.data[li].uv=[(0,0),(1,0),(0,1)][k]
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 ob=bpy.data.objects.new('ExoV4_'+role,me);s.collection.objects.link(ob);return ob
brass=bpy.data.materials['M_ExoV3_BridgeBrass'];steel=bpy.data.materials['M_ExoV3_BridgeSteel']
def rods(role,mat,radius,length):
 v=[];f=[];N=12
 for x0 in [-.020,.020]:
  k=len(v)
  for y in [0,length]:
   for i in range(N):v.append(mat@Vector((x0+radius*math.cos(i*math.tau/N),y,radius*math.sin(i*math.tau/N))))
  v.extend([mat@Vector((x0,0,0)),mat@Vector((x0,length,0))])
  for i in range(N):
   j=(i+1)%N;f.extend([(k+i,k+N+j,k+j),(k+i,k+N+i,k+N+j),(k+2*N,k+j,k+i),(k+2*N+1,k+N+i,k+N+j)])
 ob=newmesh(role,v,f,[brass if int(role.split('_')[-1])%2==0 else steel]);bind(ob,role,mat)
def cap(source,ids,role,correction,mat,source_part):
 me=source.data;polys=[me.polygons[i] for i in ids];used=sorted({i for p in polys for i in p.vertices});idx={v:i for i,v in enumerate(used)}
 new=bpy.data.meshes.new('ExoV4_'+role);new.from_pydata([correction@me.vertices[i].co for i in used],[],[tuple(idx[i] for i in p.vertices) for p in polys])
 for mm in me.materials:new.materials.append(mm)
 uv=new.uv_layers.new(name='UVMap');normal=correction.to_3x3().inverted().transposed();nn=[]
 for a,b in zip(polys,new.polygons):
  b.use_smooth=a.use_smooth;b.material_index=a.material_index
  for i,j in zip(a.loop_indices,b.loop_indices):uv.data[j].uv=me.uv_layers.active.data[i].uv;nn.append((normal@me.corner_normals[i].vector).normalized())
 new.normals_split_custom_set(nn);new.update();ob=bpy.data.objects.new('ExoV4_'+role,new);s.collection.objects.link(ob);bind(ob,role,mat)
 ob['source_polygon_ids']=[source['source_polygon_ids'][i] for i in ids]
 m['parts'][-1]['fit_matrix']=[list(r) for r in correction@Matrix(source_part['fit_matrix'])];m['parts'][-1]['source']='v3 textured upper attachment cap'
m['upper_slide']={}
for side,sign in [('L',1),('R',-1)]:
 S=rest['DEF-upper_arm.'+side].translation;E=rest['DEF-forearm.'+side].translation;W=rest['DEF-hand.'+side].translation;n=Vector(m['anchors'][side]['hinge_rest'])
 ss=S+Vector((sign*.16,.04,.035));ee=E+n*.145;ww=W+n*.10
 hood=frame(ss,E-S,(sign,0,0));upper=frame(ss,ee-ss,n);fore=frame(ee,ww-ee,n);upper_length=(ee-ss).length
 transform(bpy.data.objects['ExoV4_shoulder_'+side],hood@old['shoulder_'+side].inverted());frames['shoulder_'+side]=hood
 a=fore@Matrix.Diagonal((1,(ww-ee).length/m['anchors'][side]['forearm_length'],1,1))@old['forearm_'+side].inverted()
 for role in ['elbow_','forearm_','wrist_']:transform(bpy.data.objects['ExoV4_'+role+side],a);frames[role+side]=fore
 source=bpy.data.objects['ExoV4_upper_'+side];p=next(x for x in m['parts'] if x['role']=='upper_'+side)
 local=[old['upper_'+side].inverted()@v.co for v in source.data.vertices];lo=min(v.y for v in local);hi=max(v.y for v in local)
 a=upper@Matrix.Diagonal((1,upper_length/m['anchors'][side]['upper_length'],1,1))@old['upper_'+side].inverted()
 for suffix in ['prox','dist']:
  ids=[]
  for poly in source.data.polygons:
   y=sum(local[i].y for i in poly.vertices)/len(poly.vertices)
   if (suffix=='prox' and y<lo+(hi-lo)*.18) or (suffix=='dist' and y>hi-(hi-lo)*.18):ids.append(poly.index)
  cap(source,ids,'upper_'+suffix+'_'+side,a,upper,p)
 for coll in list(source.users_collection):coll.objects.unlink(source)
 archive.objects.link(source);source.name='V3_ArchivedUpper_'+side;source.hide_render=True
 m['parts'].remove(p);frames['upper_'+side]=upper
 spec={'segments':8,'segment_length':.05,'start_offset':.045,'end_offset':.020};m['upper_slide'][side]=spec;axis=upper.to_3x3().col[1];gap=upper_length-.065
 for i in range(8):
  mat=frame(ss+axis*(.045+(gap-.05)*i/7),axis,n);rods('upper_slide_'+side+'_'+str(i),mat,.010-i*.001,.05)
 for role in ['knee_','shin_']:
  a=Matrix.Translation((0,.015,0))
  if role=='shin_':a=Matrix.Translation((0,0,.43))@Matrix.Diagonal((1,1,.78,1))@Matrix.Translation((0,0,-.43))@a
  transform(bpy.data.objects['ExoV4_'+role+side],a)
  # Only rigid translation/rotation goes into bones; authored length correction stays in vertices.
  rr=old[role+side].copy();rr.translation+=Vector((0,.015,0));frames[role+side]=rr
 m['anchors'][side].update({'shoulder':list(ss),'elbow':list(ee),'wrist':list(ww),'upper_length':upper_length,'forearm_length':(ww-ee).length})
 # Re-seat existing back bridge on the corrected shoulder pivot.
 spec=m['bridge'][side];start=Vector(spec['start']);axis=(ss-start).normalized();length=(ss-start).length
 for i in range(spec['segments']):
  role='bridge_'+side+'_'+str(i);mat=frame(start+axis*(length-spec['segment_length'])*i/(spec['segments']-1),axis,(0,0,1))
  transform(bpy.data.objects['ExoV4_'+role],mat@old[role].inverted());frames[role]=mat

# Actual sock/stocking surfaces determine close-fitting supports above the ankle cuff.
leg_objects=[o for o in s.objects if o.type=='MESH' and o.name.startswith(('REF_Civilian_','REF_Transformed_')) and any(x in o.name.lower() for x in ['socks','stockings','boots'])]
trees=[]
for ob in leg_objects:
 ob.data.calc_loop_triangles();trees.append(BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True))
for side,sign in [('L',1),('R',-1)]:
 for tier,z in [('upper',.41),('lower',.285)]:
  center=Vector((sign*.10,0,z));N=48;v=[];f=[];radii=[];h=.009
  for i in range(N):
   theta=math.tau*i/N;direction=Vector((math.cos(theta),math.sin(theta),0));distance=.025
   for dz in [-h,0,h]:
    for tree in trees:
     hit=tree.ray_cast(center+Vector((0,0,dz)),direction,.14)
     if hit[0] is not None:distance=max(distance,hit[3])
   radii.append(distance+.0025)
  radii=[max(radii[(i-1)%N],radii[i],radii[(i+1)%N]) for i in range(N)]
  cross=[(0,-h+.001),(.001,-h),(.005,-h),(.006,-h+.001),(.006,h-.001),(.005,h),(.001,h),(0,h-.001)]
  for i in range(N):
   theta=math.tau*i/N;direction=Vector((math.cos(theta),math.sin(theta),0));bulge=max(0,-math.sin(theta))**24*.014
   for radial,dz in cross:v.append(center+direction*(radii[i]+radial+bulge*radial/.006)+Vector((0,0,dz)))
  for i in range(N):
   for j in range(8):
    a=i*8+j;b=((i+1)%N)*8+j;c=((i+1)%N)*8+(j+1)%8;d=i*8+(j+1)%8;f.extend([(a,b,c),(a,c,d)])
  role='calf_cuff_'+tier+'_'+side;ob=newmesh(role,v,f,[brass,steel]);mat=frame(center,(0,0,-1),(0,-1,0));bind(ob,role,mat)
  for p in ob.data.polygons:p.material_index=1 if p.index//2%8 in [0,6,7] else 0;p.use_smooth=True
  m['parts'][-1]['fitting']={'height_m':z,'inner_radius_min_m':min(radii),'inner_radius_max_m':max(radii),'garment_clearance_m':.0025}

# Preserve ordinary garments; this derivative contains an equipment-specific sleeve tuck.
m['sleeve_tuck']={}
for ob in list(s.objects):
 if ob.type!='MESH' or not ob.name.startswith(('REF_Civilian_','REF_Transformed_')):continue
 if not any(x in ob.name for x in ['Cardigan','TF_sleeve_','TF_under_sleeves']):continue
 saved=ob.copy();saved.data=ob.data;saved.name='V3_Original_'+ob.name;archive.objects.link(saved);saved.hide_render=True
 ob.data=ob.data.copy();oldnorm=[n.vector.copy() for n in ob.data.corner_normals];changed=0;maximum=0.;normal_map={}
 for vertex in ob.data.vertices:
  p=vertex.co.copy();side='L' if p.x>=0 else 'R';sign=1 if side=='L' else -1;E=rest['DEF-forearm.'+side].translation;W=rest['DEF-hand.'+side].translation;axis=(W-E).normalized();length=(W-E).length;u=(p-E).dot(axis)/length
  radial=p-(E+axis*((p-E).dot(axis)));t=max(0,min(1,(u+.18)/.48));t=t*t*(3-2*t)
  if sign*p.x<.18 or u<-.18 or u>1.35 or radial.length>.16:t=0
  scale=1-.22*t
  if t>0:
   new=p-radial*(1-scale);displacement=(new-p).length
   if displacement>.022:scale=1-.022/max(radial.length,1e-8);new=p-radial*(1-scale);displacement=.022
   vertex.co=new;changed+=1;maximum=max(maximum,displacement)
  normal_map[vertex.index]=(axis,scale)
 nn=[]
 for loop,n in zip(ob.data.loops,oldnorm):
  axis,scale=normal_map[loop.vertex_index];parallel=axis*n.dot(axis);nn.append((parallel+(n-parallel)/scale).normalized())
 ob.data.normals_split_custom_set(nn);ob.data.update();m['sleeve_tuck'][ob.name]={'changed_vertices':changed,'max_displacement_m':maximum}

# Bind all active new rigid parts with one full weight. No animated scale.
bpy.context.view_layer.objects.active=rig;rig.hide_set(False);rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for side in ['L','R']:rig.data.edit_bones.remove(rig.data.edit_bones['EXO-upper_'+side])
for p in m['parts']:
 role=p['role'];name='EXO-'+role;b=rig.data.edit_bones.get(name)
 if b is None:b=rig.data.edit_bones.new(name);b.parent=rig.data.edit_bones['EXO-root'];b.use_connect=False
 b.head=frames[role].translation;b.tail=b.head+frames[role].to_3x3().col[1]*.05;b.matrix=frames[role];b.length=.05
bpy.ops.object.mode_set(mode='OBJECT')
m['rig_rest_frames']={n:[list(r) for r in a] for n,a in frames.items()};m['triangles']=sum(p['triangles'] for p in m['parts']);m['rig_bones']=len(rig.data.bones);m['max_influences']=1;m['status']='v4 fitting candidate'
s['exoskeleton_v4_manifest']=json.dumps(m);bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v4/exoskeleton_v4.blend')
for ob in s.objects:ob.select_set(ob==rig or ob.name.startswith('ExoV4_'))
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v4/exports/exoskeleton_v4.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_yup=True,export_extras=True)
for form,prefix in [('civilian','REF_Civilian_'),('transformed','REF_Transformed_')]:
 selected=[ob for ob in s.objects if ob.name.startswith(prefix)];states=[(ob,ob.hide_get(),ob.hide_render) for ob in selected]
 for ob in s.objects:ob.select_set(False)
 for ob,_,_ in states:ob.hide_set(False);ob.hide_render=False;ob.select_set(True)
 bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v4/exports/outfit_'+form+'_fit_v4.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_yup=True,export_all_influences=True)
 for ob,hidden,render in states:ob.hide_set(hidden);ob.hide_render=render
print('EXO_V4_BUILT',len(m['parts']),m['rig_bones'],m['triangles'],m['sleeve_tuck'])
