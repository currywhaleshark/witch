"""Bring the open wrist saddles closer to the cuffs without changing the elbow pivot."""
import bpy,json
from mathutils import Vector,Matrix
ROOT='C:/Users/yurib/Documents/New project/witch'
scene=bpy.data.scenes['ExoskeletonV3_Fit'];bpy.context.window.scene=scene
info=json.loads(scene['exoskeleton_v3_manifest']);rig=bpy.data.objects['ExoskeletonRig_v3']
assert abs(info['config']['arm_offset_wrist']-.10)<1e-6
def frame(origin,direction,front):
 y=direction.normalized();z=(front-y*front.dot(y)).normalized();x=y.cross(z).normalized()
 m=Matrix((x,y,z)).transposed().to_4x4();m.translation=origin;return m
updates={}
for side in ['L','R']:
 n=Vector(info['anchors'][side]['hinge_rest']);elbow=Vector(info['anchors'][side]['elbow'])
 wrist=Vector(info['anchors'][side]['wrist'])-n*.035
 old=Matrix(info['rig_rest_frames']['forearm_'+side]);new=frame(elbow,wrist-elbow,n)
 correction=new@Matrix.Diagonal((1,(wrist-elbow).length/info['anchors'][side]['forearm_length'],1,1))@old.inverted()
 normal=correction.to_3x3().inverted().transposed()
 for role in ['elbow_'+side,'forearm_'+side,'wrist_'+side]:
  obj=bpy.data.objects['ExoV3_'+role];normals=[(normal@n.vector).normalized() for n in obj.data.corner_normals]
  for v in obj.data.vertices:v.co=correction@v.co
  obj.data.normals_split_custom_set(normals);obj.data.update()
  info['rig_rest_frames'][role]=[list(r) for r in new];updates['EXO-'+role]=new
  part=next(p for p in info['parts'] if p['role']==role);part['fit_matrix']=[list(r) for r in correction@Matrix(part['fit_matrix'])]
 info['anchors'][side]['wrist']=list(wrist);info['anchors'][side]['forearm_length']=(wrist-elbow).length
info['config']['arm_offset_wrist']=.065
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name,m in updates.items():rig.data.edit_bones[name].matrix=m
bpy.ops.object.mode_set(mode='OBJECT')
scene['exoskeleton_v3_manifest']=json.dumps(info)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exoskeleton_v3.blend')
for ob in scene.objects:ob.select_set(ob==rig or ob.name.startswith('ExoV3_'))
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exports/exoskeleton_v3.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_yup=True,export_extras=True)
print('WRIST_REFIT_DONE')
