import bpy,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def signature(mesh):
    data={'vertices':[v.co[:] for v in mesh.data.vertices], 'faces':[p.vertices[:] for p in mesh.data.polygons],
      'materials':[p.material_index for p in mesh.data.polygons], 'uv':[[u.uv[:] for u in layer.data] for layer in mesh.data.uv_layers],
      'normals':[n.vector[:] for n in mesh.data.corner_normals],
      'weights':[[[mesh.vertex_groups[g.group].name,g.weight] for g in v.groups] for v in mesh.data.vertices]}
    return {k:hashlib.sha256(json.dumps(v).encode()).hexdigest() for k,v in data.items()}
def actions(prefix=''):
    result={}
    for a in bpy.data.actions:
        if prefix and not a.name.startswith(prefix):continue
        if not prefix and a.name.startswith('BasePreview_'):continue
        raw=[]
        for layer in a.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:raw.append([fc.data_path,fc.array_index,[[*k.co,k.interpolation] for k in fc.keyframe_points]])
        result[a.name.removeprefix(prefix)]=hashlib.sha256(json.dumps(raw).encode()).hexdigest()
    return result
for actor in ('hound','giant'):
    version='v2' if actor=='hound' else 'v1';folder=ROOT/f'assets/actors/automation_batch2/{actor}_game_{version}'
    source=folder/f'{actor}_game_{version}.blend';bpy.ops.wm.open_mainfile(filepath=str(source))
    body=next(o for o in bpy.context.scene.objects if o.type=='MESH');body_name=body.name;rig=body.find_armature()
    before=signature(body);rest={b.name:[list(r) for r in b.matrix_local] for b in rig.data.bones};a=actions()
    armour_folder=ROOT/f'assets/actors/automation_batch2/{actor}_armour_v1'
    bpy.ops.wm.open_mainfile(filepath=str(armour_folder/f'{actor}_armour_game_v1.blend'))
    body=bpy.data.objects[body_name];assert signature(body)==before
    assert {b.name:[list(r) for r in b.matrix_local] for b in body.find_armature().data.bones}==rest
    assert actions('BasePreview_')==a
    extra=bpy.data.objects[actor+'_armour_Rigid_Surface'];extra_rig=extra.find_armature()
    assert {b.name:[list(r) for r in b.matrix_local] for b in extra_rig.data.bones}==rest
    output={'passed':True,'base_mesh_geometry_normals_uv_weights_exact':True,'base_rests_and_actions_exact':True,'extra_rests_exact':True,
      'base_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'base_glb_sha256':hashlib.sha256((folder/f'{actor}_{version}.glb').read_bytes()).hexdigest(),
      'base_mesh_signatures':before,'base_action_signatures':a}
    path=ROOT/f'reports/automation_batch2_complete_v1/{actor}_armour/validation/base_preservation.json';path.write_text(json.dumps(output,indent=2),encoding='utf8')
    print('BASE_PRESERVED',actor,flush=True)
