"""Mechanism axes, fast-gait contacts, pistons, loops and preservation."""
import bpy,json,gzip,math,sys,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/automation_motion_v2'
checks=0
def check(condition,detail):
 global checks
 checks+=1
 assert condition,detail
def read(p):return json.loads(p.read_text(encoding='utf8'))
def snap():
 sc=bpy.context.scene;mesh=next(o for o in sc.objects if o.type=='MESH' and o.find_armature());rig=mesh.find_armature()
 return {'vertices':np.array([v.co[:] for v in mesh.data.vertices]),'normals':np.array([n.vector[:] for n in mesh.data.corner_normals]),'faces':[tuple(p.vertices) for p in mesh.data.polygons],'uv':np.array([l.uv[:] for l in mesh.data.uv_layers.active.data]),'groups':[mesh.vertex_groups[v.groups[0].group].name for v in mesh.data.vertices],'weights':[(v.groups[0].weight,len(v.groups)) for v in mesh.data.vertices],'rests':{b.name:np.array(b.matrix_local) for b in rig.data.bones}},mesh,rig
def sample(rig,clip,t):
 a=bpy.data.actions[clip];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0];f=1+t*24;bpy.context.scene.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
def deformation(rig,n):return rig.pose.bones[n].matrix@rig.data.bones[n].matrix_local.inverted()
results={}
for actor,oldver,newver in [('giant',1,2),('hound',2,3)]:
 old=ROOT/f'assets/actors/automation_batch2/{actor}_game_v{oldver}';base=ROOT/f'assets/actors/automation_batch2/{actor}_game_v{newver}'
 bpy.ops.wm.open_mainfile(filepath=str(old/f'{actor}_game_v{oldver}.blend'),load_ui=False,use_scripts=False);before,mesh,rig=snap()
 oldrows={};contract_old=read(old/'rig.json')
 for clip,c in contract_old['clips'].items():
  if actor=='hound' and clip=='run':continue
  oldrows[clip]=[]
  for t in c['times']:
   sample(rig,clip,t);oldrows[clip].append({'time':t,'d':{n:np.array(deformation(rig,n)) for n in rig.pose.bones.keys()}})
 bpy.ops.wm.open_mainfile(filepath=str(base/f'{actor}_game_v{newver}.blend'),load_ui=False,use_scripts=False);after,mesh,rig=snap();contract=read(base/'rig.json')
 check(before['faces']==after['faces'],'face connectivity');check(np.array_equal(before['uv'],after['uv']),'UV exact');check(before['groups']==after['groups'] and before['weights']==after['weights'],'weights exact')
 allowed={'gear','core'} if actor=='giant' else {n for n in before['groups'] if 'piston' in n}
 indices=[i for i,n in enumerate(before['groups']) if n not in allowed]
 check(np.array_equal(before['vertices'][indices],after['vertices'][indices]),actor+' unchanged other geometry')
 corner_indices=[l.index for l in mesh.data.loops if before['groups'][l.vertex_index] not in allowed]
 invalid=[i for i in corner_indices if np.linalg.norm(before['normals'][i])<.5]
 valid=[i for i in corner_indices if i not in invalid]
 normal_error=float(np.max(np.abs(before['normals'][valid]-after['normals'][valid])));print('NORMAL_PRESERVATION',actor,normal_error,flush=True);check(normal_error<1e-6,'unchanged valid normal directions')
 check(all(abs(np.linalg.norm(after['normals'][i])-1)<1e-5 for i in invalid),'previous zero auto normals now unit normals')
 changed_rests=[n for n in before['rests'] if np.max(abs(before['rests'][n]-after['rests'][n]))>1e-7]
 check(set(changed_rests)==({'gear','key','core','Socket_core'} if actor=='giant' else set()),'only allowed rests change')
 max_unchanged=0.
 for clip,rows in oldrows.items():
  excluded={'gear','key','core','Socket_core'} if actor=='giant' else ({n for n in before['groups'] if 'piston' in n} if clip=='death' else set())
  for row in rows:
   sample(rig,clip,row['time'])
   for n,expected in row['d'].items():
    if n in excluded:continue
    e=float(np.max(abs(np.array(deformation(rig,n))-expected)));max_unchanged=max(max_unchanged,e);check(e<3e-5,(actor,clip,n,e))
 result={'topology_uv_weights_exact':True,'other_vertices_exact':True,'other_valid_normals_max_error':normal_error,'previous_zero_auto_normals_repaired':len(invalid),'changed_rest_bones':changed_rests,'unchanged_deformation_max_matrix_error':max_unchanged}
 if actor=='giant':
  mech=contract['mechanisms'];metrics={}
  for n,m in mech.items():
   p=Vector(m['pivot']);axis=Vector(m['axis']);maxpos=0.;maxaxis=0.;oldaxis=0.
   for clip in ['idle','walk']:
    for t in np.linspace(0,contract['clips'][clip]['seconds'],241):
     sample(rig,clip,float(t));d=deformation(rig,'torso').inverted()@deformation(rig,n)
     pe=(d@p-p).length;ae=(d.to_3x3()@axis-axis).length;maxpos=max(maxpos,pe);maxaxis=max(maxaxis,ae)
     check(pe<.00002 and ae<.00002,(n,clip,t,pe,ae))
     u=t/contract['clips'][clip]['seconds'];theta=math.tau*u if n=='gear' or clip=='idle' else .3*math.sin(math.tau*u)
     oldrot=Matrix.Rotation(theta,3,Vector(m['old_axis']));oldaxis=max(oldaxis,(oldrot@axis).angle(axis))
   metrics[n]={'axis_degrees_corrected':m['axis_correction_degrees'],'max_shaft_center_error_m':maxpos,'max_axis_vector_error':maxaxis,'previous_full_turn_axis_wobble_degrees':math.degrees(oldaxis)}
  result['mechanisms']=metrics
 else:
  geo=read(base/'geometry.json');contacts=contract['run_contact_phases'];plants={};piston={k:{'min_overlap_m':1e9,'min_rear_clearance_m':1e9,'max_anchor_error_m':0.} for k in geo['pistons']}
  joint_error=0.
  for t in np.linspace(0,.5,961):
   sample(rig,'run',float(t));phase=(t*4)%1;cycle=int(t*4+1e-9)
   for stem,(start,end) in contacts.items():
    f=(phase-start)%1
    if .008<f<end-start-.008:
     n=stem.split('.')[0]+'_paw.'+stem.split('.')[1];v=rig.pose.bones[n].matrix.translation.copy();v.y+=6.5*t
     key=(stem,cycle);plants.setdefault(key,[]).append(list(v))
   for stem,p in geo['pistons'].items():
    a0,b0=Vector(p['a']),Vector(p['b']);a=deformation(rig,p['a_bone'])@a0;b=deformation(rig,p['b_bone'])@b0
    ae=(deformation(rig,p['case'])@a0-a).length;be=(deformation(rig,p['rod'])@b0-b).length
    f=next(x for x in contract['piston_fits'] if x['name']==stem);met=piston[stem]
    met['min_overlap_m']=min(met['min_overlap_m'],f['case_length']+f['rod_length']-(b-a).length)
    met['min_rear_clearance_m']=min(met['min_rear_clearance_m'],(b-a).length-f['rod_length'])
    met['max_anchor_error_m']=max(met['max_anchor_error_m'],ae,be)
    check(ae<.0015 and be<.0015,('piston anchor',stem,t,ae,be))
   for stem,js in geo['joints'].items():
    limb,side=stem.split('.');labels=['upper','lower','paw'] if limb=='fore' else ['upper','lower','hock','paw']
    for i in range(len(labels)-1):
     n=limb+'_'+labels[i]+'.'+side;nn=limb+'_'+labels[i+1]+'.'+side
     a=deformation(rig,n)@Vector(js[i+1]);b=deformation(rig,nn)@Vector(js[i+1]);e=(a-b).length;joint_error=max(joint_error,e);check(e<.0001,('fixed limb joint',stem,t,e))
  plant_metrics={str(k):np.ptp(np.array(v),axis=0).tolist() for k,v in plants.items() if len(v)>3}
  # 4mm is under 0.32px at the native 1.75x camera. Keep the measured drift,
  # including sub-key hierarchical interpolation, rather than claiming zero.
  check(max(max(v) for v in plant_metrics.values())<.004,('stance world drift',plant_metrics))
  for k,v in piston.items():check(v['min_overlap_m']>.0001 and v['min_rear_clearance_m']>.0001,('piston remains engaged',k,v))
  result.update({'stance_world_drift_xyz_m':plant_metrics,'maximum_joint_endpoint_error_m':joint_error,'pistons':piston,'samples_hz':1920,'cycles_per_half_second':2,'reference_speed_mps':6.5})
 results[actor]=result
(OUT/'motion_validation.json').write_text(json.dumps({'passed':True,'checks':checks,'results':results},indent=2),encoding='utf8')
print('MOTION_CORRECTIONS_PASS',checks,json.dumps(results),flush=True)
