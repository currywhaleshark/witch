import bpy, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2';OUT=ROOT/'reports/hound_game_v2/geometry'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'hound_geometry.blend'))
sc=bpy.context.scene;mesh=bpy.data.objects['Hound_Rigid_Surface']
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check
q=qa_check.run(objects=[mesh.name],profile='game',eps=.00015,tol=.003)
(OUT/'source_qa.json').write_text(json.dumps(q,indent=2),encoding='utf8')
print('QA',len(q['errors']),len(q['warnings']),flush=True)
if '--qa-only' in sys.argv:raise SystemExit(0 if q['pass'] else 1)
sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1000;sc.render.resolution_y=760;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
sc.view_settings.view_transform='Khronos PBR Neutral'
w=bpy.data.worlds.new('Hound_Review');w.use_nodes=True;sc.world=w
bg=next(n for n in w.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.14,.17,.21,1);bg.inputs['Strength'].default_value=.4
target=Vector((0,.02,.36))
for n,pos,e,size in [('Key',(-1,2,3),280,3),('Fill',(2,1,1.7),140,2.5),('Rim',(1,-2,2.5),240,2)]:
    data=bpy.data.lights.new(n,'AREA');data.energy=e;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(n,data);sc.collection.objects.link(o);o.location=pos;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=1.6
for name,vec in [('front',(-1.8,2.8,1.3)),('rear',(2,-2.8,1.4)),('profile',(-3,0,.4)),('top',(.01,.01,3))]:
    cam.location=target+Vector(vec);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.color_type='VERTEX';sc.display.shading.light='STUDIO';sc.display.shading.show_cavity=True
colors=mesh.data.color_attributes.new(name='Diagnostic_parts',type='FLOAT_COLOR',domain='CORNER')
import colorsys
for p in mesh.data.polygons:
    i=mesh.data.vertices[p.vertices[0]].groups[0].group;c=colorsys.hsv_to_rgb(i*.618%1,.6,.8)
    for li in p.loop_indices:colors.data[li].color=(*c,1)
cam.location=target+Vector((-1.8,2.8,1.3));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(OUT/'parts.png');bpy.ops.render.render(write_still=True)
mesh.data.color_attributes.remove(colors)
sc.display.shading.color_type='SINGLE';sc.display.shading.single_color=(.55,.61,.66)
mesh.show_wire=True;mesh.show_all_edges=True
wire=mesh.copy();wire.data=mesh.data.copy();sc.collection.objects.link(wire);wire.color=(.012,.015,.018,1)
mod=wire.modifiers.new('Thin wire diagnostic','WIREFRAME');mod.thickness=.00025;mod.use_replace=True
sc.display.shading.color_type='OBJECT';mesh.color=(.5,.6,.65,1)
sc.render.filepath=str(OUT/'wire.png');bpy.ops.render.render(write_still=True)
print('HOUND_GEOMETRY_REVIEW_DONE',flush=True)
