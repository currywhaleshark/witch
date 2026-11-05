"""Evaluate official CC0 Wolf Gallop including the author's IK constraints."""
import bpy, json, sys, math, gzip, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/automation_batch2/motion_sources/quaternius'
OUT=ROOT/'reports/automation_motion_v2/local/wolf';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'Wolf.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene;rig=bpy.data.objects['AnimalArmature'];mesh=bpy.data.objects['Wolf']
for tr in rig.animation_data.nla_tracks:tr.mute=True
act=bpy.data.actions['Gallop'];rig.animation_data.action=act;rig.animation_data.action_slot=act.slots[0]
result={'source':'Wolf.blend','sha256':hashlib.sha256((BASE/'Wolf.blend').read_bytes()).hexdigest(),'action':'Gallop','source_frames':[0,17],'source_fps':30,'target_duration':.5,'conversion':'sample evaluated positions; reflect source Y to target +Y; preserve labelled L/R','rest':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'matrix':[list(r) for r in b.matrix_local]} for b in rig.data.bones},'samples':[]}
for i in range(241):
    phase=i/240;f=17*phase;sc.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
    result['samples'].append({'phase':phase,'bones':{b.name:{'head':list(b.head),'tail':list(b.tail),'matrix':[list(r) for r in b.matrix]} for b in rig.pose.bones}})
(BASE/'wolf_gallop_samples.json.gz').write_bytes(gzip.compress(json.dumps(result,separators=(',',':')).encode(),mtime=0))
# Side reference contact sheet: real source motion, unchanged mesh and curves.
sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='MATERIAL';sc.display.shading.show_shadows=True
sc.display.shading.show_cavity=True;sc.display.shading.background_type='WORLD';sc.world.color=(.16,.19,.23)
sc.render.resolution_x=640;sc.render.resolution_y=400;sc.render.resolution_percentage=100
if bpy.context.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.camera_add(location=(8,-.3,2.0));cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=6.5
cam.rotation_euler=(Vector((0,-.3,1.3))-cam.location).to_track_quat('-Z','Y').to_euler();sc.camera=cam
for i in range(9):
 f=17*i/8;sc.frame_set(int(f),subframe=f%1);sc.render.filepath=str(OUT/f'{i:02}.png');bpy.ops.render.render(write_still=True)
print('WOLF_SAMPLED',len(result['samples']),flush=True)
