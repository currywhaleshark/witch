"""Independent saved-pose checks: full body, elbow silhouette, contacts and rigid mechanisms."""
import bpy,json,gzip,math,sys,hashlib
from pathlib import Path
import numpy as np
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/hound_fullbody_v4'
checks=0
def check(ok,detail):
 global checks
 checks+=1
 assert ok,detail
def read(p):return json.loads(p.read_text(encoding='utf8'))
def snap(actor):
 mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.find_armature() and actor.lower() in o.name.lower());rig=mesh.find_armature()
 return {'vertices':np.array([v.co[:] for v in mesh.data.vertices]),'normals':np.array([n.vector[:] for n in mesh.data.corner_normals]),'faces':[tuple(p.vertices) for p in mesh.data.polygons],'uv':np.array([l.uv[:] for l in mesh.data.uv_layers.active.data]),'groups':[mesh.vertex_groups[v.groups[0].group].name for v in mesh.data.vertices],'weights':[(v.groups[0].weight,len(v.groups)) for v in mesh.data.vertices],'rests':{b.name:np.array(b.matrix_local) for b in rig.data.bones},'materials':[m.name for m in mesh.data.materials]},mesh,rig
def sample(rig,clip,t):
 a=bpy.data.actions[clip];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0];f=1+t*24;bpy.context.scene.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
def d(rig,n):return rig.pose.bones[n].matrix@rig.data.bones[n].matrix_local.inverted()
results={}
for actor,oldver,newver in [('hound',3,4),('hound_armour',2,3)]:
 suffix='_v' if actor.endswith('_armour') else '_game_v'
 old=ROOT/f'assets/actors/automation_batch2/{actor}{suffix}{oldver}';base=ROOT/f'assets/actors/automation_batch2/{actor}{suffix}{newver}'
 bpy.ops.wm.open_mainfile(filepath=str(old/f'{actor}_game_v{oldver}.blend'),load_ui=False,use_scripts=False);before,mesh,rig=snap(actor)
 oldrows=json.loads(gzip.decompress((old/'animation_samples.json.gz').read_bytes()))
 old_roof=[];old_elbows=[]
 if actor=='hound':
  chest=[v.co.copy() for v in mesh.data.vertices if mesh.vertex_groups[v.groups[0].group].name=='chest'];geo=read(old/'geometry.json')
  for ph in np.linspace(0,1,241):
   sample(rig,'run',float(ph*.25));roof=max((d(rig,'chest')@p).z for p in chest);old_roof.append(roof)
   old_elbows.append(max((d(rig,'fore_lower.'+side)@Vector(geo['joints']['fore.'+side][1])).z-roof for side in ('L','R')))
 bpy.ops.wm.open_mainfile(filepath=str(base/f'{actor}_game_v{newver}.blend'),load_ui=False,use_scripts=False);after,mesh,rig=snap(actor);contract=read(base/'rig.json')
 check(before['faces']==after['faces'],'face connectivity');check(np.array_equal(before['uv'],after['uv']),'UV exact');check(before['groups']==after['groups'] and before['weights']==after['weights'],'weights exact');check(before['materials']==after['materials'],'materials exact')
 allowed={'fore_piston_case.R','fore_piston_case.L'} if actor=='hound' else set()
 ids=[i for i,n in enumerate(before['groups']) if n not in allowed]
 check(np.array_equal(before['vertices'][ids],after['vertices'][ids]),'other geometry exact')
 ci=[l.index for l in mesh.data.loops if before['groups'][l.vertex_index] not in allowed]
 check(np.max(abs(before['normals'][ci]-after['normals'][ci]))<1e-6,'other automatic normals unchanged')
 check(all(np.array_equal(before['rests'][n],after['rests'][n]) for n in before['rests']),'all rest matrices exact')
 max_other=0.
 for clip,rows in oldrows.items():
  if clip=='run':continue
  for row in rows:
   sample(rig,clip,row['time'])
   for n,m in row['world'].items():
    if actor=='hound' and clip=='death' and n in allowed:continue
    e=float(np.max(abs(np.array(rig.pose.bones[n].matrix)-np.array(m))));max_other=max(max_other,e);check(e<2e-5,(actor,clip,n,e))
 result={'topology_uv_weights_materials_rest_exact':True,'other_geometry_normals_exact':True,'previous_nonrun_clips_max_matrix_error':max_other}
 if actor=='hound':
  geo=read(base/'geometry.json');points={g.name:np.array([(*v.co,1.) for v in mesh.data.vertices if v.groups[0].group==g.index]) for g in mesh.vertex_groups}
  plants={};pistons={n:{'min_overlap_m':1e9,'min_rear_clearance_m':1e9,'max_anchor_error_m':0.} for n in geo['pistons']};maxjoint=0.;roofheights=[];elbows=[];elbow_shell=[];floor=1e9
  velocity_samples={n:[] for n in rig.data.bones.keys()}
  for t in np.linspace(0,.5,961):
   sample(rig,'run',float(t));phase=(t*4)%1;cycle=int(t*4+1e-9);deform={n:d(rig,n) for n in points}
   roof=float((points['chest']@np.array(deform['chest']).T)[:,2].max());roofheights.append(roof)
   for n,p in points.items():floor=min(floor,float((p@np.array(deform[n]).T)[:,2].min()))
   for side in ('L','R'):
    n='fore_lower.'+side;j=Vector(geo['joints']['fore.'+side][1]);elbows.append((deform[n]@j).z-roof)
    candidates=points[n][np.linalg.norm(points[n][:,:3]-np.array(j),axis=1)<.055]
    elbow_shell.append(float((candidates@np.array(deform[n]).T)[:,2].max())-roof)
   for stem,(start,end) in contract['run_contact_phases'].items():
    f=(phase-start)%1
    if .006<f<end-start-.006:
     limb,side=stem.split('.');v=rig.pose.bones[limb+'_paw.'+side].matrix.translation.copy();v.y+=contract['run_cycle_distance_m']/.5*t
     plants.setdefault((stem,cycle),[]).append(list(v))
   for stem,p in geo['pistons'].items():
    a0,b0=Vector(p['a']),Vector(p['b']);a=deform[p['a_bone']]@a0;b=deform[p['b_bone']]@b0
    ae=(deform[p['case']]@a0-a).length;be=(deform[p['rod']]@b0-b).length;fit=next(f for f in contract['piston_fits'] if f['name']==stem);m=pistons[stem]
    m['min_overlap_m']=min(m['min_overlap_m'],fit['case_length']+fit['rod_length']-(b-a).length);m['min_rear_clearance_m']=min(m['min_rear_clearance_m'],(b-a).length-fit['rod_length']);m['max_anchor_error_m']=max(m['max_anchor_error_m'],ae,be)
    check(ae<.001 and be<.001,('piston anchors',stem,t,ae,be))
   for stem,js in geo['joints'].items():
    limb,side=stem.split('.');labels=['upper','lower','paw'] if limb=='fore' else ['upper','lower','hock','paw']
    for i in range(len(labels)-1):
     a=deform[limb+'_'+labels[i]+'.'+side]@Vector(js[i+1]);b=deform[limb+'_'+labels[i+1]+'.'+side]@Vector(js[i+1]);e=(a-b).length;maxjoint=max(maxjoint,e);check(e<.00015,('joint',stem,t,e))
   for n in velocity_samples:velocity_samples[n].append(list(rig.pose.bones[n].matrix.translation))
  drift={str(k):np.ptp(v,axis=0).tolist() for k,v in plants.items()}
  check(max(max(v) for v in drift.values())<.002,('planted foot drift',drift));check(max(elbows)<-.03,('elbow below back',max(elbows)));check(max(elbow_shell)<-.01,('outer elbow below back',max(elbow_shell)));check(floor>-.0005,('floor',floor))
  for n,m in pistons.items():check(m['min_overlap_m']>.0002 and m['min_rear_clearance_m']>.0002,('piston stroke',n,m))
  source=json.loads(gzip.decompress((ROOT/'assets/actors/automation_batch2/motion_sources/quaternius/wolf_gallop_samples.json.gz').read_bytes()));reflection=Matrix.Diagonal((1.,-1.,1.));orientation_error=0.
  for i in range(0,241,10):
   sample(rig,'run',i/240*.25)
   for n,sn in contract['motion_source']['fullbody_bones'].items():
    expected=reflection@(Matrix(source['samples'][i]['bones'][sn]['matrix'])@Matrix(source['rest'][sn]['matrix']).inverted()).to_3x3()@reflection
    e=float(np.max(abs(np.array(d(rig,n).to_3x3())-np.array(expected))));orientation_error=max(orientation_error,e);check(e<.00003,('full source rotation',n,i,e))
  seam={}
  for n,vs in velocity_samples.items():
   positions=np.array(vs);vel=np.diff(positions,axis=0)*1920;jump=float(np.linalg.norm(vel[0]-vel[-1]));speed=float(np.linalg.norm(vel,axis=1).max())
   seam[n]={'velocity_jump_mps':jump,'maximum_speed_mps':speed,'ratio':jump/max(speed,.00001)}
   check(jump/max(speed,.00001)<.10,('loop velocity discontinuity',n,seam[n]))
   if n in contract['motion_source']['fullbody_bones']:check(jump/max(speed,.00001)<.04,('body loop velocity',n,seam[n]))
  result.update({'source_fullbody_rotation_max_matrix_error':orientation_error,'old_back_height_range_m':[min(old_roof),max(old_roof)],'new_back_height_range_m':[min(roofheights),max(roofheights)],'old_elbow_above_back_max_m':max(old_elbows),'new_elbow_above_back_max_m':max(elbows),'new_outer_elbow_above_back_max_m':max(elbow_shell),'minimum_floor_m':floor,'stance_world_drift_xyz_m':drift,'max_joint_error_m':maxjoint,'pistons':pistons,'loop_velocity':seam,'dense_hz':1920,'distance_per_clip_m':contract['run_cycle_distance_m'],'reference_playback_speed':contract['run_reference_playback_speed']})
 results[actor]=result
baseline=read(OUT/'previous_asset_baseline.json');preserved=[]
for path,digest in baseline.items():
 check(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,('previous art changed',path));preserved.append(path)
result={'passed':True,'checks':checks,'results':results,'previous_asset_files_preserved':len(preserved),'preserved_inputs':baseline}
(OUT/'motion_validation.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print('FULLBODY_VALIDATION_PASS',checks,json.dumps({a:{k:v for k,v in r.items() if k!='loop_velocity'} for a,r in results.items()}),flush=True)
