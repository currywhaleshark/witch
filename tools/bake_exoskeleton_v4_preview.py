"""Bake actual engine-sampled body/equipment poses into editable preview actions.

Only isolated GLB reference copies and the new auxiliary rig are changed.
The shipping GLB stays animation-free and uses the pose follower.
"""
import bpy,json,sys,math
from pathlib import Path
from mathutils import Matrix
from bpy_extras import anim_utils
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4';S=ROOT/'assets/equipment/exoskeleton_v4'
scene=bpy.data.scenes['ExoskeletonV4_Fit'];bpy.context.window.scene=scene;scene.render.fps=24
body=bpy.data.objects['ReferenceBodyRig_v29'];exo=bpy.data.objects['ExoskeletonRig_v4']
hair=next(o for o in scene.objects if o.type=='ARMATURE' and o.name.startswith('REF_Hair_'))
manifest=json.loads((S/'parts.json').read_text(encoding='utf-8'))
records=[r for r in json.loads((R/'bake_poses.json').read_text()) if r['form']=='civilian']
body_rest={n:Matrix(m) for n,m in json.loads((R/'body_rest.json').read_text()).items()}
hair_rest={n:Matrix(m) for n,m in json.loads((R/'hair_rest.json').read_text()).items()}
mechanism_rest={n:Matrix(m) for n,m in manifest['mechanism_rest_godot'].items()}
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)));CI=C.inverted()
def error(a,b):return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))
rebind=[]
for ob in list(scene.objects):
 if ob.type!='MESH' or not ob.name.startswith(('REF_Civilian_','REF_Transformed_','REF_Eyes_')):continue
 for mod in ob.modifiers:
  if mod.type!='ARMATURE':continue
  other=mod.object
  assert len(other.data.bones)==len(body.data.bones)
  assert all(b.name in body.data.bones and error(b.matrix_local,body.data.bones[b.name].matrix_local)<2e-5 for b in other.data.bones)
  mod.object=body;ob.parent=body;rebind.append(ob.name)
for rig in [body,exo,hair]:
 rig.animation_data_clear();rig.data.pose_position='POSE';rig.animation_data_create()
 for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
motion_order=list(dict.fromkeys(r['motion'] for r in records));summaries=[];first_actions={}
for motion in motion_order:
 samples=[r for r in records if r['motion']==motion];actions={};previous_q={}
 for rig in [body,exo,hair]:
  prefix='EXO' if rig==exo else 'BODY' if rig==body else 'HAIR'
  act=bpy.data.actions.new(prefix+'_v4_'+motion);act.use_fake_user=True
  rig.animation_data.action=act;slot=act.slots.new(id_type='OBJECT',name=rig.name);rig.animation_data.action_slot=slot
  actions[rig.name]=(act,slot)
  if motion=='idle':first_actions[rig.name]=(act,slot)
 for row in samples:
  f=1+row['phase']*row['clip_length']*24;scene.frame_set(int(f),subframe=f-int(f))
  for rig in [body,exo,hair]:
   desired={}
   for b in rig.data.bones:
    if rig==exo:
     role=b.name.removeprefix('EXO-')
     delta=Matrix.Identity(4) if role=='root' else CI@Matrix(row['mechanism'][role])@mechanism_rest[role].inverted()@C
    else:
     source=row['bones'] if rig==body else row['hair_bones'];rest=body_rest if rig==body else hair_rest
     delta=CI@Matrix(source[b.name])@rest[b.name].inverted()@C
    desired[b.name]=delta@b.matrix_local
   for b in rig.data.bones:
    pb=rig.pose.bones[b.name]
    kw={'parent_matrix':desired[b.parent.name],'parent_matrix_local':b.parent.matrix_local} if b.parent else {}
    basis=b.convert_local_to_pose(desired[b.name],b.matrix_local,invert=True,**kw)
    loc,quat,scale=basis.decompose();key=(rig.name,b.name)
    if key in previous_q and quat.dot(previous_q[key])<0:quat.negate()
    previous_q[key]=quat.copy();pb.location=loc;pb.rotation_quaternion=quat;pb.scale=scale
    for channel in ['location','rotation_quaternion','scale']:pb.keyframe_insert(channel,frame=f,group=b.name)
 for rig in [body,exo,hair]:
  act,slot=actions[rig.name];cb=anim_utils.action_ensure_channelbag_for_slot(act,slot)
  for fc in cb.fcurves:
   for k in fc.keyframe_points:k.interpolation='LINEAR'
  track=rig.animation_data.nla_tracks.new();track.name='PREVIEW_'+motion
  strip=track.strips.new(motion,1,act);strip.action_slot=slot;track.mute=True
 summaries.append({'motion':motion,'samples':len(samples),'duration':samples[0]['clip_length'],'frame_end':1+samples[0]['clip_length']*24})
 print('BAKE_V4',motion,len(samples),flush=True)
for rig in [body,exo,hair]:
 rig.animation_data.action,rig.animation_data.action_slot=first_actions[rig.name]
scene.frame_start=1;scene.frame_end=49;scene.frame_set(1);bpy.context.view_layer.update()
# Keep the reference outfit switching explicit and safe in collections.
for form,prefix in [('Civilian','REF_Civilian_'),('Transformed','REF_Transformed_')]:
 collection=bpy.data.collections.new('OUTFIT_'+form);scene.collection.children.link(collection)
 for ob in list(scene.objects):
  if ob.type=='MESH' and ob.name.startswith(prefix):
   if not any(mod.type=='ARMATURE' and mod.object==body for mod in ob.modifiers):
    ob.hide_set(True);ob.hide_render=True;continue # Original fitting sphere is not a garment.
   for old in list(ob.users_collection):old.objects.unlink(ob)
   collection.objects.link(ob)
   ob.hide_set(False);ob.hide_render=False
 collection.hide_viewport=form=='Transformed';collection.hide_render=form=='Transformed'
scene['preview_instructions']='BODY / EXO / HAIR actions share a motion suffix. Choose matching actions on all three rigs; OUTFIT collections switch forms. Runtime GLB uses the procedural follower. Reference files are unchanged.'
# Evaluate every baked clip against the authoritative matrix cache.
max_body=0.;max_exo=0.;max_hair=0.
last_motion=None
for row in records:
 if row['motion']!=last_motion:
  for rig,prefix in [(body,'BODY'),(exo,'EXO'),(hair,'HAIR')]:
   action=bpy.data.actions[prefix+'_v4_'+row['motion']];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
  last_motion=row['motion']
 f=1+row['phase']*row['clip_length']*24;scene.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update()
 for rig in [body,exo,hair]:
  for b in rig.data.bones:
   if rig==exo:
    role=b.name.removeprefix('EXO-');delta=Matrix.Identity(4) if role=='root' else CI@Matrix(row['mechanism'][role])@mechanism_rest[role].inverted()@C
   else:
    source=row['bones'] if rig==body else row['hair_bones'];rest=body_rest if rig==body else hair_rest;delta=CI@Matrix(source[b.name])@rest[b.name].inverted()@C
   e=error(rig.pose.bones[b.name].matrix,delta@b.matrix_local)
   if rig==exo:max_exo=max(max_exo,e)
   elif rig==body:max_body=max(max_body,e)
   else:max_hair=max(max_hair,e)
result={'passed':max(max_body,max_exo,max_hair)<.0001,'clips':summaries,'verified_poses':len(records),'body_matrix_error':max_body,'exo_matrix_error':max_exo,'hair_matrix_error':max_hair,'rebound_reference_meshes':rebind,'fps':24,'scope':'Editable 24fps previews of existing game motions. No source character actions or rig rests changed.'}
(R/'bake_preview.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('BAKE_V4_DONE',result['passed'],max_body,max_exo,max_hair,flush=True)
assert result['passed']
# A synchronized NLA playlist makes the saved file immediately playable.
for rig,prefix in [(body,'BODY'),(exo,'EXO'),(hair,'HAIR')]:
 rig.animation_data.action=None;track=rig.animation_data.nla_tracks.new();track.name='PLAYLIST_8_CURRENT_MOTIONS';cursor=1
 for item in summaries:
  action=bpy.data.actions[prefix+'_v4_'+item['motion']];strip=track.strips.new(item['motion'],cursor,action);strip.action_slot=action.slots[0]
  strip.extrapolation='NOTHING'
  if rig==exo:scene.timeline_markers.new(item['motion'],frame=cursor)
  # Both endpoints are included in the review. Do not share an NLA boundary:
  # Blender evaluates the previous strip at that exact shared frame.
  cursor+=round(item['duration']*24)+1
scene.frame_end=cursor-1;scene.frame_set(1);bpy.context.view_layer.update()
scene['preview_instructions']='Press Space to play the synchronized 8-motion NLA playlist. OUTFIT collections switch forms. Individual PREVIEW tracks are muted. Runtime GLB uses the procedural follower. Reference files are unchanged.'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(S/'exoskeleton_v4_animated.blend'))

