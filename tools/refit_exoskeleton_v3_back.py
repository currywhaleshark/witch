"""Seat the back module closer to the garment; retain the supported bridge sockets."""
import bpy,json
from mathutils import Matrix,Vector
ROOT='C:/Users/yurib/Documents/New project/witch'
s=bpy.data.scenes['ExoskeletonV3_Fit'];bpy.context.window.scene=s
m=json.loads(s['exoskeleton_v3_manifest']);assert abs(m['config']['back_offset'][1]-.265)<1e-6
rig=bpy.data.objects['ExoskeletonRig_v3'];shift=Matrix.Translation((0,-.055,0));updates={}
for o in s.objects:
 if o.type=='ARMATURE':o.data.pose_position='REST'
for role in ['back_power','back_link_L','back_link_R']:
 ob=bpy.data.objects['ExoV3_'+role]
 for v in ob.data.vertices:v.co=shift@v.co
 ob.data.update();new=shift@Matrix(m['rig_rest_frames'][role]);m['rig_rest_frames'][role]=[list(r) for r in new];updates['EXO-'+role]=new
 part=next(p for p in m['parts'] if p['role']==role);part['fit_matrix']=[list(r) for r in shift@Matrix(part['fit_matrix'])]
m['config']['back_offset'][1]-=.055
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name,mat in updates.items():rig.data.edit_bones[name].matrix=mat
bpy.ops.object.mode_set(mode='OBJECT')
m['status']='separated and rigged fitting candidate; remaining garment contact documented'
s['exoskeleton_v3_manifest']=json.dumps(m)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exoskeleton_v3.blend')
for ob in s.objects:ob.select_set(ob==rig or ob.name.startswith('ExoV3_'))
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exports/exoskeleton_v3.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_yup=True,export_extras=True)
print('EXO_V3_BACK_REFIT_DONE',m['config']['back_offset'])
