import bpy, json, sys, math
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1]
actor=sys.argv[sys.argv.index('--')+1]
src=ROOT/'assets/actors/boss_trial_v1/source'/f'{actor}_tripo_segmented.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(src))
scene=bpy.context.scene
meshes=[o for o in scene.objects if o.type=='MESH']
allv=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=Vector(tuple(min(v[i] for v in allv) for i in range(3)));hi=Vector(tuple(max(v[i] for v in allv) for i in range(3)))
height=hi.z-lo.z;origin=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
turn=Matrix.Rotation(math.pi,4,'Z')
parts=[]
for o in meshes:
    co=[turn@((o.matrix_world@v.co-origin)/height) for v in o.data.vertices]
    low=[min(v[i] for v in co) for i in range(3)];high=[max(v[i] for v in co) for i in range(3)]
    parts.append({'name':o.name,'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'lo':low,'hi':high,'center':[(a+b)/2 for a,b in zip(low,high)]})
out=ROOT/'reports/boss_trial_v1'/f'{actor}_parts.json'
out.write_text(json.dumps({'parts':parts,'materials':len(bpy.data.materials),'images':[{'name':im.name,'size':list(im.size)} for im in bpy.data.images if im.type=='IMAGE'],'height':height,'bounds':[list(lo),list(hi)]},indent=2),encoding='utf-8')
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(src.with_suffix('.blend')))
print('BOSS_PARTS_INSPECTED',actor,len(parts))
