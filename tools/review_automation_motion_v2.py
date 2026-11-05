"""Pose, part, wire, and mechanism-axis review of the derivative sources."""
import bpy,json,sys,math,colorsys
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];actor=sys.argv[sys.argv.index('--')+1]
version=int(next((x.split('=',1)[1] for x in sys.argv if x.startswith('--version=')), '3' if actor=='hound' else '2'))
report=next((x.split('=',1)[1] for x in sys.argv if x.startswith('--report=')), 'reports/automation_motion_v2')
BASE=ROOT/f'assets/actors/automation_batch2/{actor}_game_v{version}';OUT=ROOT/report/actor/'geometry';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/f'{actor}_game_v{version}.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene;mesh=next(o for o in sc.objects if o.type=='MESH' and o.find_armature());rig=mesh.find_armature()
for ob in list(sc.objects):
 if ob.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(ob,do_unlink=True)
for tr in rig.animation_data.nla_tracks:tr.mute=True
contract=json.loads((BASE/'rig.json').read_text(encoding='utf8'))
pts={g.name:np.array([(*v.co,1.) for v in mesh.data.vertices if v.groups[0].group==g.index]) for g in mesh.vertex_groups}
inv={b.name:b.matrix_local.inverted() for b in rig.data.bones}
def sample(clip,t):
 a=bpy.data.actions[clip];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0];f=1+t*24;sc.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
floors={}
for clip,c in contract['clips'].items():
 low=1e9;worst={}
 for t in np.linspace(0,c['seconds'],math.ceil(c['seconds']*240)+1):
  sample(clip,t)
  for n,p in pts.items():
   z=float((p@np.array(rig.pose.bones[n].matrix@inv[n]).T)[:,2].min())
   if z<low:low=z;worst={'time':float(t),'part':n}
 floors[clip]={'min_z':low,**worst}
(OUT/'floor_diagnostic.json').write_text(json.dumps(floors,indent=2),encoding='utf8');print('FLOORS',json.dumps(floors),flush=True)
sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='MATERIAL';sc.display.shading.show_cavity=True;sc.display.shading.show_shadows=True;sc.display.shading.background_type='WORLD';sc.world.color=(.1,.14,.18)
sc.render.resolution_x=720;sc.render.resolution_y=480;sc.render.resolution_percentage=100
cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO'
center=Vector((0,0,.32 if actor=='hound' else 1.5));cam.data.ortho_scale=1.45 if actor=='hound' else 4.7
def view(offset):
 cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
def render(name):sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
clip='run' if actor=='hound' else 'idle';duration=.25 if actor=='hound' else 2
for label,offset in [('side',(-5,0,.25)),('front',(-3,4,1.8))]:
 view(offset)
 for i in range(9):sample(clip,duration*i/8);render(f'{label}_{i:02}')
sample('idle',0)
colors=mesh.data.color_attributes.new(name='QA_parts',type='FLOAT_COLOR',domain='CORNER')
for p in mesh.data.polygons:
 group=mesh.data.vertices[p.vertices[0]].groups[0].group;c=colorsys.hsv_to_rgb(group*.618%1,.65,.9)
 for li in p.loop_indices:colors.data[li].color=(*c,1)
sc.display.shading.color_type='VERTEX';render('parts');mesh.data.color_attributes.remove(colors)
sc.display.shading.color_type='OBJECT';mesh.color=(.5,.6,.65,1)
wire=mesh.copy();wire.data=mesh.data.copy();sc.collection.objects.link(wire);wire.color=(.01,.015,.02,1)
mod=wire.modifiers.new('QA thin wire','WIREFRAME');mod.thickness=.001 if actor=='hound' else .002;mod.offset=1;mod.use_replace=True;mod.use_even_offset=False
render('wire');bpy.data.objects.remove(wire,do_unlink=True)
print('SOURCE_MOTION_REVIEW_DONE',actor,flush=True)
