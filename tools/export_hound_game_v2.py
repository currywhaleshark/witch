"""Append exact 24 Hz + event/end samples to the verified static skin GLB.

Blender's integer-frame export range cannot express 0.4/0.6/1.2 s exactly at
24 fps. This writes the same saved action samples without rounding deadlines.
"""
import json, struct, math, hashlib, shutil
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/actors/automation_batch2/hound_game_v2';OUT=ROOT/'reports/hound_game_v2'
GAME=ROOT/'game/assets/actors/automation_batch2/hound_v2';GAME.mkdir(parents=True,exist_ok=True)
b=(BASE/'hound_static.glb').read_bytes();n=struct.unpack_from('<I',b,12)[0];doc=json.loads(b[20:20+n]);binary=bytearray(b[28+n:])
rig=json.loads((BASE/'rig.json').read_text(encoding='utf8'));poses=json.loads((OUT/'local/animation_samples.json').read_text(encoding='utf8'))
def matrix(node):
    if 'matrix' in node:return np.array(node['matrix']).reshape(4,4).T
    x,y,z,w=node.get('rotation',[0,0,0,1]);m=np.eye(4)
    m[:3,:3]=np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])@np.diag(node.get('scale',[1,1,1]))
    m[:3,3]=node.get('translation',[0,0,0]);return m
def quaternion(m):
    # Stable symmetric eigensolve, xyzw order; caller preserves winding signs.
    r=m[:3,:3];xx,xy,xz=r[0];yx,yy,yz=r[1];zx,zy,zz=r[2]
    k=np.array([[xx-yy-zz,xy+yx,xz+zx,zy-yz],[xy+yx,yy-xx-zz,yz+zy,xz-zx],[xz+zx,yz+zy,zz-xx-yy,yx-xy],[zy-yz,xz-zx,yx-xy,xx+yy+zz]])/3
    values,vectors=np.linalg.eigh(k);q=vectors[:,np.argmax(values)]
    return q if q[3]>=0 else -q
parents={c:i for i,no in enumerate(doc['nodes']) for c in no.get('children',[])}
def world(i):return (world(parents[i]) if i in parents else np.eye(4))@matrix(doc['nodes'][i])
nodes={no['name']:i for i,no in enumerate(doc['nodes']) if no.get('name') in rig['rest_world']}
assert len(nodes)==rig['bones']
conversion=world(nodes['root'])@np.linalg.inv(np.array(rig['rest_world']['root']))
assert max(np.max(abs(world(i)-conversion@np.array(rig['rest_world'][name]))) for name,i in nodes.items())<1e-6
doc['animations']=[]
def accessor(arr,kind,bounds=False):
    arr=np.asarray(arr,dtype='<f4');binary.extend(bytes((-len(binary))%4));off=len(binary);raw=arr.tobytes();binary.extend(raw)
    vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':off,'byteLength':len(raw)})
    a={'bufferView':vi,'componentType':5126,'count':len(arr),'type':kind}
    if bounds:a['min']=[float(arr.min())];a['max']=[float(arr.max())]
    ix=len(doc['accessors']);doc['accessors'].append(a);return ix
for clip,rows in poses.items():
    ti=accessor([r['time'] for r in rows],'SCALAR',True);anim={'name':clip,'samplers':[],'channels':[],
      'extras':{'fps':24,'duration_seconds':rig['clips'][clip]['seconds'],'loop':rig['clips'][clip]['loop'],'constant_tracks_preserved':True}}
    for name,idx in nodes.items():
        positions=[];rotations=[];last=None
        for row in rows:
            target=conversion@np.array(row['world'][name]);parent=parents.get(idx)
            if parent is not None:
                parent_name=doc['nodes'][parent].get('name')
                pw=conversion@np.array(row['world'][parent_name]) if parent_name in nodes else world(parent)
                target=np.linalg.inv(pw)@target
            q=quaternion(target)
            if last is not None and q@last<0:q=-q
            last=q;positions.append(target[:3,3]);rotations.append(q)
        for channel,values,kind in [('translation',positions,'VEC3'),('rotation',rotations,'VEC4'),('scale',np.ones((len(rows),3)),'VEC3')]:
            oi=accessor(values,kind);s=len(anim['samplers']);anim['samplers'].append({'input':ti,'output':oi,'interpolation':'LINEAR'})
            anim['channels'].append({'sampler':s,'target':{'node':idx,'path':channel}})
    doc['animations'].append(anim)
doc['buffers'][0]['byteLength']=len(binary)
doc['asset']['generator']='Blender 5.1.1 / witch exact-time rigid animation export'
for scene in doc['scenes']:scene['extras']={'stage':'prepared hound game art candidate','fps':24,'forward':'-Z','runtime_scale':1}
raw=json.dumps(doc,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);binary.extend(bytes((-len(binary))%4))
glb=struct.pack('<III',0x46546c67,2,28+len(raw)+len(binary))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(binary),0x004e4942)+binary
dest=BASE/'hound_v2.glb';dest.write_bytes(glb);shutil.copy2(dest,GAME/dest.name)
parts={k:v for k,v in rig.items() if k!='rest_world'}
for v in parts['parts_metadata'].values():
    x,y,z=v['pivot_blender'];v['pivot_godot']=[x,z,-y]
for v in parts['sockets'].values():
    x,y,z=v['rest_blender'];v['rest_godot']=[x,z,-y]
parts.update({'id':'mechanical_hound','version':2,'asset':'hound_v2.glb','prepared_only':True,'coordinate_system':'metres, Y up, -Z forward, unit object scale',
 'variants':{'base':{'scale':1.,'instances':1},'hunting_pack':{'scale':.8,'instances':3},'heavy_tracker':{'status':'additional armour not authored in this base motion pass'}},
 'animation_import':{'fps':24,'optimizer':False,'compression':False,'remove_immutable_tracks':False},
 'destruction':'baked gravity and rotated-vertex floor support; no explosion/inter-part/live physics',
 'sha256':hashlib.sha256(glb).hexdigest()})
for folder in (BASE,GAME):(folder/'parts.json').write_text(json.dumps(parts,indent=2),encoding='utf8')
subresources={'nodes':{'PATH:AnimationPlayer':{'optimizer/enabled':False,'compression/enabled':False}},
 'animations':{clip:{'settings/loop_mode':int(rig['clips'][clip]['loop'])} for clip in rig['clips']}}
# Let Godot create its own cache IDs; retain exact prepared import preferences.
source='res://assets/actors/automation_batch2/hound_v2/hound_v2.glb'
import_path=GAME/'hound_v2.glb.import'
if True:
    text='[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\n\nsource_file="'+source+'"\n\n[params]\n\n'
    if import_path.exists():text=import_path.read_text(encoding='utf8').split('[params]')[0]+'[params]\n\n'
    settings={'nodes/root_type':'','nodes/root_name':'','nodes/apply_root_scale':True,'nodes/root_scale':1.0,'skins/use_named_skins':True,
       'meshes/ensure_tangents':True,'meshes/generate_lods':False,'meshes/create_shadow_meshes':True,'meshes/light_baking':0,
       'animation/import':True,'animation/fps':24,'animation/trimming':False,'animation/remove_immutable_tracks':False,'animation/import_rest_as_RESET':False,
       'gltf/naming_version':2,'gltf/embedded_image_handling':1,
       'import_script/path':'res://assets/actors/automation_batch2/hound_v2/import_exact_animation.gd'}
    for k,v in settings.items():text+=k+'='+json.dumps(v)+'\n'
    text+='_subresources='+json.dumps(subresources,indent=2)+'\n';import_path.write_text(text,encoding='utf8')
print('HOUND_EXPORTED',len(glb),'bytes',len(doc['animations']),'clips',len(nodes),'bones')
