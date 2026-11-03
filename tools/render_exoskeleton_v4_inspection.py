"""Technical source views. Colors identify separate rigid parts, not final materials."""
import bpy,json,colorsys
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4/inspection';R.mkdir(parents=True,exist_ok=True)
s=bpy.data.scenes['ExoskeletonV4_Fit'];bpy.context.window.scene=s
try:s.render.engine='BLENDER_WORKBENCH'
except TypeError as e:raise RuntimeError(str(e))
s.render.resolution_x=1000;s.render.resolution_y=1000;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.film_transparent=False
s.view_settings.view_transform='Standard';s.display.shading.light='STUDIO';s.display.shading.color_type='OBJECT'
s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.cavity_type='BOTH'
s.display.shading.show_specular_highlight=True;s.display.shading.background_type='WORLD'
if s.world is None:s.world=bpy.data.worlds.new('ExoV4_InspectionWorld')
s.world.color=(.045,.058,.075)
camdata=bpy.data.cameras.new('ExoV4_Inspection');cam=bpy.data.objects.new('ExoV4_Inspection',camdata);s.collection.objects.link(cam);s.camera=cam
camdata.type='ORTHO';camdata.ortho_scale=1.9
rig=bpy.data.objects['ExoskeletonRig_v4'];rig.data.pose_position='REST'
parts=[o for o in s.objects if o.type=='MESH' and o.name.startswith('ExoV4_')]
for ob in s.objects:
 if ob.type=='MESH':ob.hide_render=ob not in parts
for i,o in enumerate(parts):o.color=(*colorsys.hsv_to_rgb((i*.61803398875)%1,.46,.78),1)
center=Vector((0,0,.93))
for view,position in [('parts_front',(2.8,-4,2.3)),('parts_back',(-2.8,4,2.3)),('parts_side',(4,.2,1.5))]:
 cam.location=position;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
 s.render.filepath=str(R/(view+'.png'));bpy.ops.render.render(write_still=True)
# Spread semantic groups for a topology-and-pivot inspection.
for o in parts:
 role=o.name.removeprefix('ExoV4_');sign=1 if '_L' in role else -1
 if role.startswith('back'):o.location.y+=.18
 elif role.startswith(('shoulder','upper','elbow','forearm','wrist')):
  o.location.x+=sign*.25
  o.location.z+= {'shoulder':.13,'upper':.07,'elbow':0,'forearm':-.06,'wrist':-.13}[role.split('_')[0]]
 elif role.startswith(('knee','shin','calf')):o.location.x+=sign*.1
camdata.ortho_scale=2.15;cam.location=(2,-4,2.1);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(R/'parts_exploded.png');bpy.ops.render.render(write_still=True)
# Mesh wire overlay via evaluated renderable wire geometry, only in this unsaved QA scene.
for o in parts:
 wire=o.copy();wire.data=o.data.copy();s.collection.objects.link(wire);wire.name='QA_wire_'+o.name
 wire.color=(.015,.018,.025,1);mod=wire.modifiers.new('QA topology','WIREFRAME');mod.thickness=.00035;mod.use_replace=True;mod.offset=1
s.render.filepath=str(R/'parts_wire.png');bpy.ops.render.render(write_still=True)
print('EXO_V4_INSPECTION_DONE',len(parts),flush=True)

