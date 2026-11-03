"""Live-MCP rigid telescopic shoulder bridges; no animated scale or stretch."""
import bpy,math,json
from mathutils import Vector,Matrix
ROOT='C:/Users/yurib/Documents/New project/witch'
scene=bpy.data.scenes['ExoskeletonV3_Fit'];bpy.context.window.scene=scene
rig=bpy.data.objects['ExoskeletonRig_v3'];info=json.loads(scene['exoskeleton_v3_manifest'])
assert 'bridge' not in info

def frame(origin,direction,front):
 y=Vector(direction).normalized();z=Vector(front);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
 m=Matrix((x,y,z)).transposed().to_4x4();m.translation=Vector(origin);return m

mat=bpy.data.materials.new('M_ExoV3_BridgeBrass');mat.use_nodes=True
node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
node.inputs['Base Color'].default_value=(.30,.20,.095,1);node.inputs['Metallic'].default_value=.72;node.inputs['Roughness'].default_value=.44
steel=bpy.data.materials.new('M_ExoV3_BridgeSteel');steel.use_nodes=True
node=next(n for n in steel.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
node.inputs['Base Color'].default_value=(.055,.073,.082,1);node.inputs['Metallic'].default_value=.8;node.inputs['Roughness'].default_value=.38

def cylinder_part(role,m,radius,length,material):
 vertices=[];faces=[];N=12
 for y in [0,length]:
  for i in range(N):vertices.append(m@Vector((radius*math.cos(i*math.tau/N),y,radius*math.sin(i*math.tau/N))))
 for i in range(N):
  j=(i+1)%N;faces.extend([(i,N+j,j),(i,N+i,N+j)])
 vertices.extend([m@Vector((0,0,0)),m@Vector((0,length,0))])
 for i in range(N):
  j=(i+1)%N;faces.extend([(2*N,i,j),(2*N+1,N+j,N+i)])
 mesh=bpy.data.meshes.new('ExoV3_'+role);mesh.from_pydata(vertices,[],faces);mesh.materials.append(material);mesh.update()
 # Cylinders use their own plain metal, not the AI atlas; unique local planar UVs suffice.
 uv=mesh.uv_layers.new(name='UVMap')
 for p in mesh.polygons:
  for k,loop in enumerate(p.loop_indices):uv.data[loop].uv=[(0,0),(1,0),(0,1)][k]
 ob=bpy.data.objects.new('ExoV3_'+role,mesh);scene.collection.objects.link(ob);ob.parent=rig
 group=ob.vertex_groups.new(name='EXO-'+role);group.add(list(range(len(vertices))),1,'REPLACE')
 mod=ob.modifiers.new('Rigid equipment skin','ARMATURE');mod.object=rig;ob['part_role']=role;ob['rigid_bone']='EXO-'+role
 info['parts'].append({'name':ob.name,'role':role,'bone':'EXO-'+role,'triangles':len(faces),'source':'original telescopic mount'})
 info['rig_rest_frames'][role]=[list(row) for row in m]
 return role,m

info['bridge']={};newbones=[]
for side,sign in [('L',1),('R',-1)]:
 start=Vector((sign*.105,.248,1.24));end=Vector(info['anchors'][side]['shoulder']);axis=(end-start).normalized();length=(end-start).length
 info['bridge'][side]={'start':list(start),'segment_length':.125,'segments':4,'rest_length':length}
 for i,radius in enumerate([.014,.0115,.009,.0068]):
  m=frame(start+axis*(length-.125)*i/3,axis,(0,0,1))
  newbones.append(cylinder_part('bridge_'+side+'_'+str(i),m,radius,.125,mat if i%2==0 else steel))
 # A short mount reaches the cape/back surface behind the shoulder blades.
 m=frame((sign*.065,.145,1.235),(0,1,0),(0,0,1))
 newbones.append(cylinder_part('mount_'+side,m,.022,.08,steel))
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for role,m in newbones:
 bone=rig.data.edit_bones.new('EXO-'+role);bone.head=m.translation;bone.tail=m.translation+m.to_3x3().col[1]*.075;bone.matrix=m;bone.parent=rig.data.edit_bones['EXO-root'];bone.use_connect=False
bpy.ops.object.mode_set(mode='OBJECT')
info['triangles']=sum(p['triangles'] for p in info['parts']);info['status']='rigged fitting iteration'
scene['exoskeleton_v3_manifest']=json.dumps(info)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exoskeleton_v3.blend')
print('EXO_V3_BRIDGES',len(info['parts']),info['triangles'])
