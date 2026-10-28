"""Derive a floating scatter cannon from the accepted turret's separated upper parts."""
import bpy, json, hashlib, shutil
from pathlib import Path
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/shotgun_cast_v1'
GAME=ROOT/'game/assets/actors/shotgun_cast_v1'
REPORT=ROOT/'reports/shotgun_cast_v1'
for p in [BASE/'authoring', BASE/'exports', GAME, REPORT]: p.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=ROOT/'assets/actors/turret_assembly_v1/authoring/turret_parts.blend'
source_hash=sha(source)
data=json.loads((ROOT/'assets/actors/turret_assembly_v1/parts.json').read_text(encoding='utf-8'))
chosen={p['name']:p for p in data['parts'] if p['parent']!='root' and
        (p['parent']!='carriage' or p['godot_center'][1]>.50)}
bpy.ops.wm.open_mainfile(filepath=str(source))
scene=bpy.context.scene
barrel=scene.objects['part_001']
coords=[barrel.matrix_world@v.co for v in barrel.data.vertices]
muzzle=Vector((.00064,max(v.y for v in coords),.65099))
scale=.72
parts=[]
for obj in list(scene.objects):
    if obj.name not in chosen:
        bpy.data.objects.remove(obj,do_unlink=True)
        continue
    info=chosen[obj.name]
    transform=Matrix.Scale(scale,4)@Matrix.Translation(-muzzle)@obj.matrix_world
    obj.data=obj.data.copy();obj.data.transform(transform)
    low=Vector(tuple(min(v.co[i] for v in obj.data.vertices) for i in range(3)))
    high=Vector(tuple(max(v.co[i] for v in obj.data.vertices) for i in range(3)))
    center=(low+high)/2
    obj.data.transform(Matrix.Translation(-center));obj.matrix_world=Matrix.Translation(center)
    delay={'carriage':.02,'drive_gear':.16,'key':.23,'barrel':.35}[info['parent']]+int(obj.name[-3:])%3*.025
    parts.append({'name':obj.name,'source_parent':info['parent'],'delay':delay,
                  'triangles':sum(len(p.vertices)-2 for p in obj.data.polygons)})
marker=bpy.data.objects.new('Muzzle',None);scene.collection.objects.link(marker)
marker.empty_display_type='ARROWS';marker.empty_display_size=.08
for obj in scene.objects:obj.select_set(True)
bpy.context.view_layer.objects.active=barrel
export=BASE/'exports/shotgun_parts.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,
                          export_animations=False,export_skins=False,export_extras=True)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'authoring/shotgun_parts.blend'))
shutil.copy2(export,GAME/export.name)
report={'source':source.relative_to(ROOT).as_posix(),'source_sha256':source_hash,
        'source_unchanged':source_hash==sha(source),'parts':parts,'part_count':len(parts),
        'triangles':sum(p['triangles'] for p in parts),'scale_from_turret':scale,
        'muzzle_local':[0,0,0],'forward_local':[0,0,-1],'export_sha256':sha(export),
        'placement':{'forward_m':.62,'side_m':.52,'height_m':1.12,'near_distance_m':1.8},
        'method':'Selected upper carriage/barrel/gear/key surfaces, no legs or turntable. Original UV/PBR atlas retained; uniform 0.72 scale and muzzle-origin translation only.'}
assert report['source_unchanged']
for target in [BASE/'parts.json',GAME/'parts.json',REPORT/'build.json']:
    target.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SHOTGUN_PARTS_COMPLETE',len(parts),report['triangles'])
