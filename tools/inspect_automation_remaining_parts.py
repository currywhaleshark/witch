"""Read-only source diagnostic: isolated segmented parts and world geometry."""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
ACTOR=sys.argv[sys.argv.index('--')+1]
OUT=ROOT/('reports/automation_batch2_complete_v1/local/'+ACTOR+'_parts')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/('assets/actors/automation_batch2/'+ACTOR+'_tripo_v1/'+ACTOR+'_segmented.blend')))
sc=bpy.context.scene
meshes=sorted([o for o in sc.objects if o.type=='MESH'],key=lambda o:int(o.name.rsplit('_',1)[1]))
for o in sc.objects:
    if o.type=='LIGHT':o.hide_render=True
sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO';sc.display.shading.color_type='SINGLE';sc.display.shading.single_color=(.57,.67,.68)
sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True;sc.display.shading.cavity_type='BOTH'
sc.display.shading.background_type='WORLD';sc.world.color=(.11,.13,.16)
sc.render.resolution_x=380;sc.render.resolution_y=300;sc.render.resolution_percentage=100
sc.render.image_settings.file_format='PNG';sc.render.film_transparent=False
cam=sc.camera;cam.data.type='ORTHO'
result=[]
for o in meshes:
    pts=[o.matrix_world@v.co for v in o.data.vertices]
    lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)])
    target=(lo+hi)/2
    for p in meshes:p.hide_render=p!=o
    cam.location=target+Vector((-.45,-1,.35));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=max((hi-lo).length*1.3,.065)
    sc.render.filepath=str(OUT/(o.name+'.png'));bpy.ops.render.render(write_still=True)
    result.append({'name':o.name,'lo':list(lo),'hi':list(hi),'vertices':[list(v) for v in pts],'faces':[list(p.vertices) for p in o.data.polygons]})
(OUT/'geometry.json').write_text(json.dumps(result),encoding='utf8')
print('BATCH2_PARTS_DIAGNOSTIC_COMPLETE',len(meshes),flush=True)
