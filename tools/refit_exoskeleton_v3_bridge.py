"""Seven nested rigid sections cover the measured 78–437mm shoulder travel."""
import bpy,math,json
from mathutils import Vector,Matrix
ROOT='C:/Users/yurib/Documents/New project/witch'
scene=bpy.data.scenes['ExoskeletonV3_Fit'];bpy.context.window.scene=scene
rig=bpy.data.objects['ExoskeletonRig_v3'];info=json.loads(scene['exoskeleton_v3_manifest']);updates={}
def frame(origin,direction):
 y=direction.normalized();z=Vector((0,0,1));z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
 m=Matrix((x,y,z)).transposed().to_4x4();m.translation=origin;return m
for side in ['L','R']:
 spec=info['bridge'][side];spec['segment_length']=.07;spec['segments']=7
 start=Vector(spec['start']);end=Vector(info['anchors'][side]['shoulder']);axis=(end-start).normalized();length=(end-start).length
 for i in range(7):
  role='bridge_'+side+'_'+str(i);name='ExoV3_'+role;m=frame(start+axis*(length-.07)*i/6,axis);radius=.015-i*.0018;N=12
  vv=[];ff=[]
  for y in [0,.07]:
   for j in range(N):vv.append(m@Vector((radius*math.cos(j*math.tau/N),y,radius*math.sin(j*math.tau/N))))
  vv.extend([m@Vector((0,0,0)),m@Vector((0,.07,0))])
  for j in range(N):
   k=(j+1)%N;ff.extend([(j,N+k,k),(j,N+j,N+k),(2*N,j,k),(2*N+1,N+k,N+j)])
  mesh=bpy.data.meshes.new(name+'_nested');mesh.from_pydata(vv,[],ff);mesh.materials.append(bpy.data.materials['M_ExoV3_BridgeBrass' if i%2==0 else 'M_ExoV3_BridgeSteel'])
  uv=mesh.uv_layers.new(name='UVMap')
  for p in mesh.polygons:
   for k,loop in enumerate(p.loop_indices):uv.data[loop].uv=[(0,0),(1,0),(0,1)][k]
  mesh.update();ob=bpy.data.objects.get(name)
  if ob is None:
   ob=bpy.data.objects.new(name,mesh);scene.collection.objects.link(ob);ob.parent=rig
   mod=ob.modifiers.new('Rigid equipment skin','ARMATURE');mod.object=rig
   ob['part_role']=role;ob['rigid_bone']='EXO-'+role
   info['parts'].append({'name':name,'role':role,'bone':'EXO-'+role,'triangles':48,'source':'original telescopic mount'})
  else:ob.data=mesh
  ob.vertex_groups.clear();vg=ob.vertex_groups.new(name='EXO-'+role);vg.add(list(range(len(vv))),1,'REPLACE')
  info['rig_rest_frames'][role]=[list(row) for row in m];updates['EXO-'+role]=m
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name,m in updates.items():
 b=rig.data.edit_bones.get(name)
 if b is None:b=rig.data.edit_bones.new(name)
 b.head=m.translation;b.tail=m.translation+m.to_3x3().col[1]*.075;b.matrix=m;b.parent=rig.data.edit_bones['EXO-root'];b.use_connect=False
bpy.ops.object.mode_set(mode='OBJECT')
info['triangles']=sum(p['triangles'] for p in info['parts']);scene['exoskeleton_v3_manifest']=json.dumps(info)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exoskeleton_v3.blend')
for ob in scene.objects:ob.select_set(ob==rig or ob.name.startswith('ExoV3_'))
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exports/exoskeleton_v3.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_yup=True,export_extras=True)
print('BRIDGE_REFIT_DONE',len(info['parts']),info['triangles'])
