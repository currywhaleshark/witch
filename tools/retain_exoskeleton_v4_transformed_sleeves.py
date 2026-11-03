import bpy,json
s=bpy.data.scenes['ExoskeletonV4_Fit'];m=json.loads(s['exoskeleton_v4_manifest'])
for name in list(m['sleeve_tuck']):
 if not name.startswith('REF_Transformed_'):continue
 ob=bpy.data.objects[name];old=bpy.data.objects['V3_Original_'+name]
 ob.data=old.data.copy();del m['sleeve_tuck'][name]
m['transformed_sleeves_preserved']=True
s['exoskeleton_v4_manifest']=json.dumps(m)
bpy.ops.wm.save_as_mainfile(filepath='C:/Users/yurib/Documents/New project/witch/assets/equipment/exoskeleton_v4/exoskeleton_v4.blend')
print('V4_TF_ORIGINAL_SLEEVES_RETAINED')

