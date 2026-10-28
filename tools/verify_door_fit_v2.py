"""Independent saved-file comparison of the door fit correction."""
import bpy, json, hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/door_fit_v2'
def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True).encode()).hexdigest()
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    obj=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    leaf={b.name for b in rig.data.bones if b.parent and b.parent.name=='hinge'}
    names={g.index:g.name for g in obj.vertex_groups}
    curves={}
    for action in bpy.data.actions:
        data=[]
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag=strip.channelbag(slot)
                    if not bag:continue
                    for curve in bag.fcurves:
                        data.append([curve.data_path,curve.array_index,
                            [[list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation] for k in curve.keyframe_points]])
        curves[action.name]=digest(data)
    return {
        'frame_vertices':digest([[v.index,list(v.co)] for v in obj.data.vertices if names[v.groups[0].group] not in leaf]),
        'topology':digest([list(p.vertices) for p in obj.data.polygons]),
        'uv':digest([[list(v.uv) for v in uv.data] for uv in obj.data.uv_layers]),
        'weights':digest([[[names[g.group],g.weight] for g in v.groups] for v in obj.data.vertices]),
        'fixed_bones':digest({b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones if b.name not in leaf}),
        'actions':curves,
        'packed_images':{im.name:hashlib.sha256(bytes(im.packed_file.data)).hexdigest() for im in bpy.data.images if im.packed_file},
        'triangles':sum(len(p.vertices)-2 for p in obj.data.polygons),
        'bones':len(rig.data.bones),
    }
before=snapshot(REPORT/'before/door_v1.blend')
after=snapshot(ROOT/'assets/actors/boss_trial_v1/authoring/door_v1.blend')
preserved={key:before[key]==after[key] for key in before}
measurements={key:json.loads((REPORT/folder/'fit_measurement.json').read_text()) for key,folder in [('before','before'),('after','after_all_parts')]}
gaps={key:max(r['right_gap_m'] for r in val['rows'] if .4<r['z']<1.7) for key,val in measurements.items()}
old_manifest=json.loads((REPORT/'before/delivery_manifest.json').read_text(encoding='utf-8-sig'))
unchanged={f['path']:sha(ROOT/f['path'])==f['sha256'] for f in old_manifest['files'] if '/door_v1.' not in f['path']}
result={
    'passed':all(preserved.values()) and all(unchanged.values()) and gaps['after']<=.006 and gaps['after']<gaps['before']/10,
    'preserved':preserved,'non_door_and_raw_asset_hashes_unchanged':unchanged,
    'latch_side_maximum_gap_m_at_z_0_4_to_1_7':gaps,
    'front_uncovered_aperture_fraction':{k:v['uncovered_aperture_fraction'] for k,v in measurements.items()},
    'measurement_resolution_m':[.002,.01],
    'scope':'Saved mesh/frame/UV/topology/weights/images, fixed rest bones and all three action curves. Front-ray aperture sampling, not full inter-part collision clearance.',
    'door_blend_sha256':sha(ROOT/'assets/actors/boss_trial_v1/authoring/door_v1.blend'),
    'door_glb_sha256':sha(ROOT/'assets/actors/boss_trial_v1/exports/door_v1.glb'),
}
(REPORT/'fit_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('DOOR_FIT_VERIFIED',json.dumps(result))
assert result['passed'],result
