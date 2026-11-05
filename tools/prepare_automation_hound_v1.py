"""Minimal non-destructive cleanup of the first segmented Tripo hound source.

Eight sub-mm2 overlap slivers are removed in a derivative. All retained positions,
UVs, part transforms, material slots and imported textures are preserved. This is
still a high-density source, not a rigged/optimized runtime character.
"""
import hashlib
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'assets/actors/automation_batch2/hound_tripo_v1'
OUT = ROOT / 'reports/automation_batch2_v1/working'
OUT.mkdir(parents=True, exist_ok=True)
(BASE/'exports').mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
import qa_check

assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(BASE/'hound_segmented.blend'))
sc = bpy.context.scene
sc.name = 'Hound_Working_60_Parts'
meshes = sorted((o for o in sc.objects if o.type=='MESH'), key=lambda o:o.name)
assert len(meshes)==60 and sum(len(o.data.polygons) for o in meshes)==76870
raw_hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (BASE/'source').glob('*.glb')}
remove = {'tripo_part_0':{2552}, 'tripo_part_16':{1158}, 'tripo_part_3':{1246},
          'tripo_part_34':{290}, 'tripo_part_42':{420}, 'tripo_part_6':{2141,2554},
          'tripo_part_9':{1693}}
records=[]
max_normal_error=0.
for name, ids in remove.items():
    obj=bpy.data.objects[name]
    old=obj.data
    assert all(old.polygons[i].area < 5e-7 for i in ids)
    keep=[p for p in old.polygons if p.index not in ids]
    used=sorted({i for p in keep for i in p.vertices})
    remap={v:i for i,v in enumerate(used)}
    new=bpy.data.meshes.new(name+'_Cleanup')
    new.from_pydata([tuple(old.vertices[i].co) for i in used],[],
                    [tuple(remap[i] for i in p.vertices) for p in keep])
    for mat in old.materials:new.materials.append(mat)
    uv_layers=[new.uv_layers.new(name=u.name) for u in old.uv_layers]
    normals=[]
    for src,dst in zip(keep,new.polygons):
        dst.material_index=src.material_index
        dst.use_smooth=src.use_smooth
        for a,b in zip(src.loop_indices,dst.loop_indices):
            for au,bu in zip(old.uv_layers,uv_layers):bu.data[b].uv=au.data[a].uv
            normals.append(tuple(old.corner_normals[a].vector))
    new.normals_split_custom_set(normals)
    new.update()
    obj.data=new
    assert all(old.vertices[a].co==b.co for a,b in zip(used,new.vertices))
    for src,dst in zip(keep,new.polygons):
        assert tuple(used[i] for i in dst.vertices)==tuple(src.vertices)
        for a,b in zip(src.loop_indices,dst.loop_indices):
            for au,bu in zip(old.uv_layers,uv_layers):assert au.data[a].uv==bu.data[b].uv
            max_normal_error=max(max_normal_error,(old.corner_normals[a].vector-new.corner_normals[b].vector).length)
    records.append({'part':name,'removed_faces':[{'index':i,'area_source_units2':old.polygons[i].area} for i in sorted(ids)],
                    'retained_vertex_indices':used,'retained_polygon_indices':[p.index for p in keep]})
assert max_normal_error<.000873
sc['source_status']='60 exported source parts; eight tiny overlap slivers removed; not rigged or optimized'
sc['cleanup_faces']=8
sc['no_joint_or_scale_fit']=True
sc['preserved_uv_materials_textures']=True
for light in (o for o in sc.objects if o.type=='LIGHT'):
    light.data.energy*=.35
sc.camera.data.ortho_scale=1.45
qa=qa_check.run(objects=[o.name for o in meshes],profile='game',eps=.0002,tol=.003)
(OUT/'source_qa.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
print('WORKING_QA',len(qa['errors']),len(qa['warnings']),flush=True)
assert qa['pass'],qa['errors']
for o in sc.objects:o.select_set(o in meshes)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.file.pack_all()
blend=BASE/'hound_working.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
dest=BASE/'exports/hound_working.glb'
bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,use_active_scene=True,
                          export_animations=False,export_yup=True)
info={'status':'source-stage cleanup, not a runtime-ready model','parts':60,'triangles_before':76870,
      'triangles_after':sum(len(o.data.polygons) for o in meshes),'removed_triangles':8,
      'retained_positions_connectivity_uv_exact':True,'max_corner_normal_vector_difference':max_normal_error,
      'materials_textures_unchanged':True,'part_transforms_unchanged':True,'repairs':records,
      'raw_hashes':raw_hashes,'warnings_note':'Imported UV/normal seams, source separation boundaries and hidden mating faces retained; joint caps/contact and reduction are future work.'}
assert info['triangles_after']==76862
(OUT/'cleanup.json').write_text(json.dumps(info,indent=2),encoding='utf-8')

# Verify a fresh GLB import before returning to the saved source for review.
fresh=bpy.data.scenes.new('QA_Working_Reimport')
bpy.context.window.scene=fresh
bpy.ops.import_scene.gltf(filepath=str(dest))
loaded=[o for o in fresh.objects if o.type=='MESH']
assert len(loaded)==60 and sum(len(o.data.polygons) for o in loaded)==76862
reimport=qa_check.run(objects=[o.name for o in loaded],profile='game',eps=.0002,tol=.003)
(OUT/'reimport_qa.json').write_text(json.dumps(reimport,indent=2),encoding='utf-8')
print('REIMPORT_QA',len(reimport['errors']),len(reimport['warnings']),flush=True)
assert reimport['pass'],reimport['errors']
bpy.ops.wm.open_mainfile(filepath=str(blend))
sc=bpy.context.scene
meshes=[o for o in sc.objects if o.type=='MESH']
assert len(meshes)==60 and sum(len(o.data.polygons) for o in meshes)==76862
assert all(im.packed_file or im.packed_files for im in bpy.data.images if im.source=='FILE')
points=np.asarray([list(o.matrix_world@v.co) for o in meshes for v in o.data.vertices])
center=Vector((points.min(axis=0)+points.max(axis=0))/2)
views=[('three_quarter',(1,-1.5,.85)),('opposite',(-1,1.5,.85)),('profile',(0,-1,.12)),('top',(0,-.05,1))]
for label,direction in views:
    sc.camera.location=center+Vector(direction).normalized()*4
    sc.camera.rotation_euler=(center-sc.camera.location).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=str(OUT/(label+'.png'))
    bpy.ops.render.render(write_still=True)

# Thin wire lines on a full-size sheet remain readable on this 77k-triangle source.
sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'
sc.display.shading.color_type='OBJECT'
sc.display.shading.show_shadows=False
sc.display.shading.show_cavity=False
sc.display.shading.background_type='WORLD'
sc.world.color=(.11,.13,.16)
for ob in meshes:
    ob.color=(.58,.64,.69,1)
    wire=ob.copy()
    wire.data=ob.data
    wire.name='ReviewWire_'+ob.name
    wire.color=(.015,.02,.025,1)
    sc.collection.objects.link(wire)
    mod=wire.modifiers.new('ReviewWire','WIREFRAME')
    mod.thickness=.00006
    mod.use_even_offset=False
sc.camera.location=center+Vector((1,-1.5,.85)).normalized()*4
sc.camera.rotation_euler=(center-sc.camera.location).to_track_quat('-Z','Y').to_euler()
sc.render.filepath=str(OUT/'wire.png')
bpy.ops.render.render(write_still=True)
assert all(hashlib.sha256((BASE/'source'/name).read_bytes()).hexdigest()==sha for name,sha in raw_hashes.items())
(OUT/'verification.json').write_text(json.dumps({'source_qa_pass':qa['pass'],'fresh_glb_qa_pass':reimport['pass'],
    'saved_reopened_parts':60,'saved_reopened_triangles':76862,'packed_images':True,'raw_files_unchanged':True,
    'source_stage_only':True},indent=2),encoding='utf-8')
print('HOUND_WORKING_COMPLETE',flush=True)
