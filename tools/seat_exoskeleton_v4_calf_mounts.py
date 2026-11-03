import bpy,json,math
s=bpy.data.scenes['ExoskeletonV4_Fit'];m=json.loads(s['exoskeleton_v4_manifest'])
assert not m.get('calf_mount_extension')
for p in m['parts']:
 if not p['role'].startswith('calf_cuff_'):continue
 ob=bpy.data.objects[p['name']]
 for v in ob.data.vertices:
  i=v.index//8;j=v.index%8;theta=math.tau*i/48;radial=[0,.001,.005,.006,.006,.005,.001,0][j]
  bulge=max(0,-math.sin(theta))**24*.026*radial/.006
  v.co.x+=math.cos(theta)*bulge;v.co.y+=math.sin(theta)*bulge
 ob.data.update()
m['calf_mount_extension']=.026;s['exoskeleton_v4_manifest']=json.dumps(m)
bpy.ops.wm.save_as_mainfile(filepath='C:/Users/yurib/Documents/New project/witch/assets/equipment/exoskeleton_v4/exoskeleton_v4.blend')
rig=bpy.data.objects['ExoskeletonRig_v4']
for ob in s.objects:ob.select_set(ob==rig or ob.name.startswith('ExoV4_'))
bpy.ops.export_scene.gltf(filepath='C:/Users/yurib/Documents/New project/witch/assets/equipment/exoskeleton_v4/exports/exoskeleton_v4.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_yup=True,export_extras=True)
print('V4_CALF_MOUNTS_CONNECTED')

