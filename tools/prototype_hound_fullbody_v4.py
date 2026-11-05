"""Fast numerical and Workbench review before the expensive final bake."""
import bpy,sys,json,math
from pathlib import Path
import numpy as np
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from automation_rigid_common import part_points,dump
from hound_fullbody_motion import FullBodyGallop
BASE=ROOT/'assets/actors/automation_batch2/hound_game_v3';OUT=ROOT/'reports/hound_fullbody_v4/local/prototype';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'hound_game_v3.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene;mesh=next(o for o in sc.objects if o.type=='MESH' and o.find_armature());rig=mesh.find_armature()
rig.animation_data_clear();rests={b.name:b.matrix_local.copy() for b in rig.data.bones}
points=part_points(mesh);geo=json.loads((BASE/'geometry.json').read_text(encoding='utf8'))
motion=FullBodyGallop(ROOT,rests,geo,points)
metric={'distance_per_cycle_m':motion.distance,'root_height_offset_m':motion.height_offset,'pistons':{n:[] for n in geo['pistons']},'elbow_to_back':[],'floor':[],'chest_height':[]}
def pose(ph):
    d=motion.pose(ph)
    for n,pb in rig.pose.bones.items():pb.matrix=d[n]@rests[n];bpy.context.view_layer.update()
    return d
for ph in np.linspace(0,1,241):
    d=motion.pose(float(ph))
    for n,p in geo['pistons'].items():metric['pistons'][n].append(((d[p['b_bone']]@Vector(p['b']))-(d[p['a_bone']]@Vector(p['a']))).length)
    roof=max((d['chest']@p).z for p in points['chest'])
    metric['elbow_to_back'].append(max((d['fore_lower.'+side]@motion.joints['fore.'+side][1]).z-roof for side in ('L','R')))
    metric['floor'].append(min((d[n]@p).z for n,ps in points.items() for p in ps))
    metric['chest_height'].append(roof)
metric['stats']=motion.stats
dump(OUT/'metrics.json',metric)
print('PROTOTYPE',json.dumps({k:({n:[min(v),max(v)] for n,v in x.items()} if k=='pistons' else [min(x),max(x)] if isinstance(x,list) else x) for k,x in metric.items()}),flush=True)
if '--no-render' not in sys.argv:
    for ob in list(sc.objects):
        if ob.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(ob,do_unlink=True)
    sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='MATERIAL';sc.display.shading.show_cavity=True;sc.display.shading.show_shadows=True;sc.display.shading.background_type='WORLD';sc.world.color=(.1,.14,.18)
    sc.render.resolution_x=640;sc.render.resolution_y=400;sc.render.resolution_percentage=100
    cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=1.5
    center=Vector((0,0,.34))
    for label,offset in [('side',(-5,0,.1)),('front',(-3,4,1.8))]:
        cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
        for i in range(8):
            pose(i/8);sc.render.filepath=str(OUT/f'{label}_{i:02}.png');bpy.ops.render.render(write_still=True)
print('PROTOTYPE_DONE',flush=True)
