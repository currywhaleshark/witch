import bpy, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];ACTOR=sys.argv[sys.argv.index('--')+1];BASE=ROOT/f"assets/actors/automation_batch2/{ACTOR}{'_v1' if ACTOR.endswith('_armour') else '_game_v1'}";OUT=ROOT/f'reports/automation_batch2_complete_v1/{ACTOR}/geometry'
bpy.ops.wm.open_mainfile(filepath=str(BASE/f'{ACTOR}_game_v1.blend'))
sc=bpy.context.scene;mesh=bpy.data.objects[ACTOR+'_Rigid_Surface']
from mathutils import Matrix
for arm in [o for o in sc.objects if o.type=='ARMATURE']:
    if arm.animation_data:
        arm.animation_data.action=None
        for track in arm.animation_data.nla_tracks:track.mute=True
    for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
for ob in [o for o in sc.objects if o.type in ('LIGHT','CAMERA')]:bpy.data.objects.remove(ob,do_unlink=True)
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
targets=[o.name for o in sc.objects if o.type=='MESH'] if ACTOR.endswith('_armour') else [mesh.name]
q=qa_check.run(objects=targets,profile='game',eps=.00015,tol=.003)
(OUT/'source_qa.json').write_text(json.dumps(q,indent=2),encoding='utf8')
print('QA',len(q['errors']),len(q['warnings']),flush=True)
if '--qa-only' in sys.argv:raise SystemExit(0 if q['pass'] else 1)
sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1000;sc.render.resolution_y=760;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
sc.view_settings.view_transform='Khronos PBR Neutral'
w=bpy.data.worlds.new('Hound_Review');w.use_nodes=True;sc.world=w
bg=next(n for n in w.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.14,.17,.21,1);bg.inputs['Strength'].default_value=.4
scale=.9 if ACTOR.startswith('hound') else 1.5 if ACTOR=='beacon' else 2.8
target=Vector((0,0,scale*.48))
for n,pos,e,size in [('Key',(-1,2,3),280,3),('Fill',(2,1,1.7),140,2.5),('Rim',(1,-2,2.5),240,2)]:
    data=bpy.data.lights.new(n,'AREA');data.energy=e*scale*scale;data.shape='DISK';data.size=size*scale
    o=bpy.data.objects.new(n,data);sc.collection.objects.link(o);o.location=Vector(pos)*scale;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=scale*1.65
for name,vec in [('front',(-1.8,2.8,1.3)),('rear',(2,-2.8,1.4)),('profile',(-3,0,.4)),('top',(.01,.01,3))]:
    if '--wire-only' in sys.argv:continue
    cam.location=target+Vector(vec)*scale;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.color_type='VERTEX';sc.display.shading.light='STUDIO';sc.display.shading.show_cavity=True
colors=mesh.data.color_attributes.new(name='Diagnostic_parts',type='FLOAT_COLOR',domain='CORNER')
import colorsys
for p in mesh.data.polygons:
    i=mesh.data.vertices[p.vertices[0]].groups[0].group;c=colorsys.hsv_to_rgb(i*.618%1,.6,.8)
    for li in p.loop_indices:colors.data[li].color=(*c,1)
cam.location=target+Vector((-1.8,2.8,1.3))*scale;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(OUT/'parts.png')
if '--wire-only' not in sys.argv:bpy.ops.render.render(write_still=True)
mesh.data.color_attributes.remove(colors)
sc.display.shading.color_type='SINGLE';sc.display.shading.single_color=(.55,.61,.66)
mesh.show_wire=True;mesh.show_all_edges=True
wire=mesh.copy();wire.data=mesh.data.copy();sc.collection.objects.link(wire);wire.color=(.012,.015,.018,1)
mod=wire.modifiers.new('Thin wire diagnostic','WIREFRAME');mod.thickness=.001*scale;mod.offset=1;mod.use_replace=True;mod.use_even_offset=False
sc.display.shading.color_type='OBJECT';mesh.color=(.5,.6,.65,1)
sc.render.filepath=str(OUT/'wire.png');bpy.ops.render.render(write_still=True)
print('HOUND_GEOMETRY_REVIEW_DONE',flush=True)
