"""Close only v11 RunCycle skirt support end keys in the current v11 candidate.

Run in background Blender with the final source already loaded. This does not
rerun fitting or touch v10. A detailed before/after preservation report connects
the previous whole-clip validation to a new 25-frame RunCycle validation.
"""
from pathlib import Path
import hashlib,json
import bpy,numpy as np
from mathutils import Matrix

ROOT=Path(__file__).resolve().parent.parent
SOURCE=(ROOT/'assets/characters/player/3d/source/middle_school_v1/source_outfit_v11/source_outfit_v11.blend').resolve()
REPORT=(ROOT/'reports/source_outfit_v11/run_loop_fix.json').resolve()
assert Path(bpy.data.filepath).resolve()==SOURCE
r=bpy.data.objects['PlayerRig_v7'];s=bpy.context.scene
assert len(r.data.bones)==107 and r.get('rig_id')=='player_humanoid_v11'
support=[f'DEF-skirt.{i+1:02}' for i in range(16)]+[f'DEF-skirt_lower.{i+1:02}' for i in range(16)]
prefixes={f'pose.bones["{name}"]' for name in support}
def is_support(path):return any(path.startswith(prefix+'.') for prefix in prefixes)
def file_sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def array_bytes(collection,field,width,dtype):
    x=np.empty(len(collection)*width,dtype=dtype);collection.foreach_get(field,x);return x.tobytes()
def mesh_signature(obj):
    mesh=obj.data;geo=hashlib.sha256();uv=hashlib.sha256();weight=hashlib.sha256()
    for collection,field,width,dtype in [(mesh.vertices,'co',3,np.float32),(mesh.edges,'vertices',2,np.int32),(mesh.loops,'vertex_index',1,np.int32),(mesh.polygons,'loop_start',1,np.int32),(mesh.polygons,'loop_total',1,np.int32),(mesh.polygons,'material_index',1,np.int32)]:
        geo.update(field.encode());geo.update(array_bytes(collection,field,width,dtype))
    if mesh.shape_keys:
        for block in mesh.shape_keys.key_blocks:
            geo.update(block.name.encode());geo.update(array_bytes(block.data,'co',3,np.float32))
    for layer in mesh.uv_layers:uv.update(layer.name.encode());uv.update(array_bytes(layer.data,'uv',2,np.float32))
    weight.update(json.dumps([g.name for g in obj.vertex_groups],ensure_ascii=False).encode())
    for vertex in mesh.vertices:
        values=sorted((g.group,float(g.weight)) for g in vertex.groups)
        weight.update(np.array([(vertex.index,group) for group,value in values],dtype=np.int32).tobytes());weight.update(np.array([value for group,value in values],dtype=np.float32).tobytes())
    return {'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),'geometry_sha256':geo.hexdigest(),'uv_sha256':uv.hexdigest(),'weights_sha256':weight.hexdigest()}
def rig_signature():
    record={b.name:{'parent':b.parent.name if b.parent else None,'rest_matrix':np.array(b.matrix_local).tolist(),'head':list(b.head_local),'tail':list(b.tail_local),'deform':b.use_deform} for b in r.data.bones}
    return {'bone_count':len(record),'bones':record,'sha256':hashlib.sha256(json.dumps(record,sort_keys=True).encode()).hexdigest()}
def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:
                    for curve in bag.fcurves:yield curve
def action_digest(action,exclude_support=False):
    records=[]
    for curve in curves(action):
        if exclude_support and is_support(curve.data_path):continue
        records.append((curve.data_path,curve.array_index,curve.extrapolation,[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right),k.interpolation,k.handle_left_type,k.handle_right_type) for k in curve.keyframe_points]))
    return hashlib.sha256(repr(sorted(records,key=lambda x:(x[0],x[1]))).encode()).hexdigest()
actions={a.name:a for a in bpy.data.actions if a.name.startswith('v7_') or a.name=='v11_Trial_WaistTwist'}
assert len(actions)==12
action=actions['v7_Trial_RunCycle'];first,last=map(lambda x:int(round(x)),action.frame_range);assert (first,last)==(1,25)
report={'input_file':str(SOURCE),'output_file':str(SOURCE),'input_sha256':file_sha(SOURCE),'changed_clip':'v7_Trial_RunCycle','changed_frame':last,'support_bones':support,'mesh_signature_before':{o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'},'rig_rest_before':rig_signature(),'canonical_action_digest_before':{name:action_digest(a) for name,a in actions.items()},'run_non_skirt_digest_before':action_digest(action,True),'changes':[]}
def heads(frame):
    for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    r.data.pose_position='POSE';r.animation_data.action=action;r.animation_data.action_slot=action.slots[0];s.frame_set(frame);bpy.context.view_layer.update();return {pb.name:np.array(pb.head) for pb in r.pose.bones}
for track in r.animation_data.nla_tracks:track.mute=True
initial=heads(first);before=heads(last)
report['endpoint_head_errors_before']={name:float(np.linalg.norm(before[name]-initial[name])) for name in initial}
count=0
for curve in curves(action):
    if not is_support(curve.data_path):continue
    keys=[k for k in curve.keyframe_points if abs(k.co[0]-last)<1e-5];assert len(keys)==1,(curve.data_path,curve.array_index)
    key=keys[0];value=float(curve.evaluate(first));old=float(key.co[1]);delta=value-old
    if delta:
        report['changes'].append({'data_path':curve.data_path,'array_index':curve.array_index,'frame':last,'before':old,'after':value})
        key.co[1]=value;key.handle_left[1]+=delta;key.handle_right[1]+=delta;curve.update()
    count+=1
assert count==32*10,count
initial=heads(first);after=heads(last)
report['endpoint_head_errors_after']={name:float(np.linalg.norm(after[name]-initial[name])) for name in initial}
assert max(report['endpoint_head_errors_after'].values())<1e-7
report['mesh_signature_after']={o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'}
report['rig_rest_after']=rig_signature();report['canonical_action_digest_after']={name:action_digest(a) for name,a in actions.items()};report['run_non_skirt_digest_after']=action_digest(action,True)
report['all_mesh_geometry_uv_weights_unchanged']=report['mesh_signature_before']==report['mesh_signature_after']
report['rig_rest_unchanged']=report['rig_rest_before']==report['rig_rest_after']
report['changed_canonical_actions']=[name for name in actions if report['canonical_action_digest_before'][name]!=report['canonical_action_digest_after'][name]]
report['run_non_skirt_channels_unchanged']=report['run_non_skirt_digest_before']==report['run_non_skirt_digest_after']
assert report['all_mesh_geometry_uv_weights_unchanged'] and report['rig_rest_unchanged'] and report['run_non_skirt_channels_unchanged']
assert report['changed_canonical_actions']==['v7_Trial_RunCycle']
# This saves only the authorized final v11 source; v10 is not loaded or changed.
r.animation_data.action=None;r.data.pose_position='REST';s.frame_set(1)
for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
report['output_sha256']=file_sha(SOURCE)
cache=ROOT/'reports/source_outfit_v11/skirt_agent/skirt_support_baked_matrices.npz'
if cache.exists():
    report['cache_input_sha256']=file_sha(cache)
    with np.load(cache) as data:values={name:data[name].copy() for name in data.files}
    values['v7_Trial_RunCycle'][-1]=values['v7_Trial_RunCycle'][0];np.savez_compressed(cache,**values)
    report['cache_output_sha256']=file_sha(cache)
report['scope']='Only 32 skirt support TRS end keys in canonical RunCycle; full geometry/UV/weights/rest and all other canonical actions preserved. Revalidate RunCycle 25 frames and re-export.'
REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('RUN_LOOP_CLOSED',json.dumps({key:report[key] for key in ['input_sha256','output_sha256','all_mesh_geometry_uv_weights_unchanged','rig_rest_unchanged','changed_canonical_actions','run_non_skirt_channels_unchanged']}),'changed_channels',len(report['changes']),flush=True)
