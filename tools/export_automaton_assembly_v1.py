"""Extract the accepted v2 idle pose as 13 independent, unskinned assembly pieces."""
import bpy,bmesh,json,hashlib,shutil
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/actors/automaton_assembly_v1'
REPORT=ROOT/'reports/automaton_assembly_v1'
GAME=ROOT/'game/assets/actors/automaton_assembly_v1'
for path in [BASE/'authoring',BASE/'exports',REPORT,GAME]:path.mkdir(parents=True,exist_ok=True)
source=ROOT/'assets/actors/summons_v2/authoring/automaton_v2.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source_hash=sha(source)
bpy.ops.wm.open_mainfile(filepath=str(source))
scene=bpy.context.scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
obj=next(o for o in scene.objects if o.type=='MESH')
rig.animation_data.action=bpy.data.actions['idle'];scene.frame_set(1);bpy.context.view_layer.update()
evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
posed=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=bpy.context.evaluated_depsgraph_get())
groups={g.index:g.name for g in obj.vertex_groups}
membership={v.index:groups[max(v.groups,key=lambda g:g.weight).group] for v in obj.data.vertices}
parts=[];created=[]
for name in sorted(set(membership.values())):
    assert name.startswith('part_'),name
    mesh=posed.copy();bm=bmesh.new();bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if membership[v.index]!=name],context='VERTS')
    bm.to_mesh(mesh);bm.free()
    coords=[obj.matrix_world@v.co for v in mesh.vertices]
    low=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    high=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    center=(low+high)/2
    mesh.transform(Matrix.Translation(-center)@obj.matrix_world)
    part=bpy.data.objects.new(name,mesh);scene.collection.objects.link(part);part.location=center
    part['source_bone']=name;created.append(part)
    parts.append({'name':name,'triangles':sum(len(p.vertices)-2 for p in mesh.polygons),
        'godot_center':[center.x,center.z,-center.y],
        'vertices':len(mesh.vertices)})
for old in list(scene.objects):
    if old not in created:bpy.data.objects.remove(old,do_unlink=True)
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
bpy.ops.object.select_all(action='DESELECT')
for part in created:part.select_set(True)
bpy.context.view_layer.objects.active=created[0]
export=BASE/'exports/automaton_parts.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'authoring/automaton_parts.blend'))
shutil.copy2(export,GAME/export.name)
report={'source':str(source.relative_to(ROOT)),'source_sha256':source_hash,'source_unchanged':sha(source)==source_hash,
    'parts':parts,'triangles':sum(p['triangles'] for p in parts),'part_count':len(parts),
    'export_sha256':sha(export),'method':'Evaluated accepted idle frame 1, split by rigid part membership; same surface, UV and PBR atlas. No new design or decimation.'}
assert report['source_unchanged'] and report['triangles']==9791 and len(parts)==13,report
(BASE/'parts.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
(REPORT/'parts_export.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('AUTOMATON_PARTS_EXPORTED',report['part_count'],report['triangles'],report['export_sha256'])
