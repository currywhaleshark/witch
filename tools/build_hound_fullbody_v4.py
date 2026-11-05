"""Bake whole-body gallop and compatible armour into new prepared derivatives."""
import bpy,json,gzip,sys,copy,math
from pathlib import Path
import numpy as np
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from automation_rigid_common import part_points,dump
from automation_motion_common import write_variant
from hound_fullbody_motion import FullBodyGallop,CONTACTS
REPORT=ROOT/'reports/hound_fullbody_v4';ACTOR=sys.argv[sys.argv.index('--')+1]
VERSION=4 if ACTOR=='hound' else 3
OLD=ROOT/('assets/actors/automation_batch2/hound_game_v3' if ACTOR=='hound' else 'assets/actors/automation_batch2/hound_armour_v2')
BASE=ROOT/f"assets/actors/automation_batch2/{ACTOR}{'_game_v' if ACTOR=='hound' else '_v'}{VERSION}"
OUT=REPORT/ACTOR;BASE.mkdir(parents=True,exist_ok=True);(OUT/'local').mkdir(parents=True,exist_ok=True)

if ACTOR=='hound_armour':
    body=ROOT/'assets/actors/automation_batch2/hound_game_v4'
    bpy.ops.wm.open_mainfile(filepath=str(body/'hound_game_v4.blend'),load_ui=False,use_scripts=False)
    sc=bpy.context.scene;base_rig=next(o for o in sc.objects if o.type=='ARMATURE')
    with bpy.data.libraries.load(str(OLD/'hound_armour_game_v2.blend'),link=False) as (src,dst):
        dst.objects=['hound_armour_Rigid_Surface']
    mesh=dst.objects[0];sc.collection.objects.link(mesh)
    rig=base_rig.copy();rig.data=base_rig.data.copy();rig.name='hound_armour_Rig';sc.collection.objects.link(rig)
    rig.animation_data_clear();mesh.parent=rig
    for mod in mesh.modifiers:
        if mod.type=='ARMATURE':mod.object=rig
    contract=json.loads((OLD/'rig.json').read_text(encoding='utf8'))
    newcontract=json.loads((body/'rig.json').read_text(encoding='utf8'))
    records=json.loads(gzip.decompress((body/'animation_samples.json.gz').read_bytes()))
    previous=json.loads(gzip.decompress((OLD/'animation_samples.json.gz').read_bytes()))
    records['death']=previous['death']
    for clip,c in newcontract['clips'].items():
        if clip!='death':contract['clips'][clip]=copy.deepcopy(c)
    for key in ('motion_source','run_contact_phases','run_dense_sample_hz','run_cycle_distance_m','run_reference_speed_mps','run_reference_playback_speed'):
        if key in newcontract:contract[key]=copy.deepcopy(newcontract[key])
    contract['base_asset']='res://assets/actors/automation_batch2/hound_v4/hound_v4.glb'
    contract['correction_version']=3
    write_variant(ACTOR,VERSION,BASE,OUT,mesh,rig,contract,records)
    dump(BASE/'preservation.json',{'previous_source':str(OLD.relative_to(ROOT)),'armour_geometry_uv_normals_weights_materials_and_rest_unchanged':True,'alive_clips_match_base':'hound_v4','independent_death_unchanged':True})
    print('FULL_BODY_ARMOUR_SAVED',flush=True);raise SystemExit(0)

assert ACTOR=='hound'
bpy.ops.wm.open_mainfile(filepath=str(OLD/'hound_game_v3.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene;mesh=next(o for o in sc.objects if o.type=='MESH' and o.find_armature());rig=mesh.find_armature()
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
for tr in rig.animation_data.nla_tracks:tr.mute=True
bpy.context.view_layer.update()
rests={b.name:b.matrix_local.copy() for b in rig.data.bones}
contract=json.loads((OLD/'rig.json').read_text(encoding='utf8'));geo=json.loads((OLD/'geometry.json').read_text(encoding='utf8'))
records=json.loads(gzip.decompress((OLD/'animation_samples.json.gz').read_bytes()))
oldverts=np.array([tuple(v.co) for v in mesh.data.vertices]);groups={v.index:mesh.vertex_groups[v.groups[0].group].name for v in mesh.data.vertices}
points=part_points(mesh);motion=FullBodyGallop(ROOT,rests,geo,points)
times=sorted(set([round(i/480,9) for i in range(241)]+[round((c+ph)/4,9) for c in (0,1) for interval in CONTACTS.values() for ph in interval]))
records['run']=[];ranges={n:[1e9,0.] for n in geo['pistons']}
for t in times:
    d=motion.pose(t*4)
    records['run'].append({'time':t,'world':{n:[list(r) for r in d[n]@rests[n]] for n in rests}})
    for n,p in geo['pistons'].items():
        distance=((d[p['b_bone']]@Vector(p['b']))-(d[p['a_bone']]@Vector(p['a']))).length
        ranges[n]=[min(ranges[n][0],distance),max(ranges[n][1],distance)]
# The slightly greater extension needs longer front cylinders only.
# All pieces stay rigid; no per-frame scaling or added render materials.
fits=[]
for oldfit in contract['piston_fits']:
    name=oldfit['name'];p=geo['pistons'][name]
    lo=min(oldfit['minimum_distance'],ranges[name][0]);hi=max(oldfit['maximum_distance'],ranges[name][1])
    case=oldfit['case_length']+max(0.,hi-oldfit['maximum_distance'])
    rod=oldfit['rod_length'];assert case<lo-.0003,(name,lo,case)
    f=dict(oldfit,minimum_distance=lo,maximum_distance=hi,case_length=case,rod_length=rod,minimum_overlap=case+rod-hi,minimum_rod_rear_clearance=lo-rod)
    fits.append(f)
    a0,b0=Vector(p['a']),Vector(p['b']);axis=(b0-a0).normalized()
    for v in mesh.data.vertices:
        if groups[v.index]==p['case']:v.co+=axis*(v.co-a0).dot(axis)*(case/oldfit['case_length']-1)
mesh.data.update();points=part_points(mesh)
for row in records['death']:
    for n,ps in points.items():
        if 'piston_case' not in n:continue
        d=Matrix(row['world'][n])@rests[n].inverted();low=min((d@p).z for p in ps)
        if low<.005:row['world'][n]=[list(r) for r in Matrix.Translation((0,0,.005-low))@Matrix(row['world'][n])]
delta=np.linalg.norm(np.array([tuple(v.co) for v in mesh.data.vertices])-oldverts,axis=1)
preservation={'previous_source':str(OLD.relative_to(ROOT)),'changed_vertex_groups':sorted({groups[i] for i in np.where(delta>1e-7)[0]}),'changed_vertices':int((delta>1e-7).sum()),'maximum_rest_vertex_delta_m':float(delta.max()),'triangles':len(mesh.data.polygons),'bones':len(rests),'all_rest_matrices_topology_uv_weights_materials_preserved':True,'changed_clips':'run; changed cylinder death floor support only'}
contract['piston_fits']=fits;contract['correction_version']=4;contract['prepared_only']=True
contract['run_cycle_distance_m']=2*motion.distance
contract['run_reference_speed_mps']=6.5
contract['run_reference_playback_speed']=6.5/(2*motion.distance/.5)
contract['run_contact_phases']=CONTACTS;contract['run_dense_sample_hz']=480
contract['motion_source']=dict(contract['motion_source'],cycles_per_clip=2,anatomical_cycle_seconds=.25,distance_per_anatomical_cycle_m=motion.distance,
    retarget='Full source world rotation deltas on chest/pelvis/neck/head/tail; evaluated whole limb directions, proportion-calibrated forelimb recovery, source-pole contact cleanup. Source trunk XYZ translation at 0.25 scale plus measured smooth contact height correction. No former constant -108mm body lowering.',
    fullbody_bones={'chest':'Torso2','pelvis':'Back','neck':'Neck1','head':'Head','tail_01':'Tail1','tail_02':'Tail4'},
    forelimb_adaptation='Mechanical upper/lower ratio near 1:1 versus wolf 1:2.6. Soft humerus recovery limit keeps elbow below shoulder; no reversed knee pole.',
    calibrated_contact_height_offset_m=motion.height_offset,source_body_translation_scale=.25)
# Remove the obsolete top-level distance alias if present; every remaining
# machine-readable field must agree on the newly measured stride.
for k in list(contract):
    if 'distance' in k and 'run' in k:contract[k]=2*motion.distance
dump(BASE/'geometry.json',geo);dump(BASE/'preservation.json',preservation)
dump(OUT/'retarget_analysis.json',{'motion_stats':motion.stats,'distance_per_anatomical_cycle_m':motion.distance,'distance_per_clip_m':2*motion.distance,'reference_speed_mps':6.5,'reference_playback_speed':contract['run_reference_playback_speed'],'body_height_offset_m':motion.height_offset,'pistons':fits,'preservation':preservation})
write_variant(ACTOR,VERSION,BASE,OUT,mesh,rig,contract,records)
print('FULL_BODY_HOUND_SAVED',json.dumps(preservation),flush=True)
