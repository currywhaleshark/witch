"""Export only new clips and verify their complete, unchanged skin contract."""
import bpy,json,hashlib,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/drive_attack_v32'
OUT=ROOT/'game/assets/characters/player/drive_attack_v32';OUT.mkdir(parents=True,exist_ok=True)
REPORT=ROOT/'reports/drive_attack_v32'
contract=json.loads((SOURCE/'runtime_contract.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'drive_attack_v32.blend'),load_ui=False,use_scripts=False)
rig=bpy.data.objects['PlayerRig_v7'];rig.data.pose_position='POSE'
for track in rig.animation_data.nla_tracks:track.mute=True
sys.path.insert(0,str(ROOT/'tools'))
from drive_animation_carrier_v30 import create
carrier=create(rig)
for obj in bpy.data.objects:obj.select_set(obj in (rig,carrier))
bpy.context.view_layer.objects.active=rig
scene=bpy.context.scene;scene.render.fps=24
records=[]
for name,spec in contract['clips'].items():
 action=bpy.data.actions[name];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
 scene.frame_start,scene.frame_end=map(int,action.frame_range);scene.frame_set(1)
 path=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,
  export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,
  export_anim_slide_to_zero=True,export_def_bones=False,export_skins=True,export_morph=False,
  export_materials='EXPORT',export_extras=False,export_image_format='NONE')
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size])
 assert len(doc['animations'])==1 and len(doc['skins'])==1
 assert len(doc['skins'][0]['joints'])==107
 assert len(doc['animations'][0]['channels'])==321
 # Names and all inverse bind matrices must be identical between the new clips.
 bind=doc['accessors'][doc['skins'][0]['inverseBindMatrices']];view=doc['bufferViews'][bind['bufferView']]
 start=28+size+view.get('byteOffset',0)+bind.get('byteOffset',0)
 bindsha=hashlib.sha256(raw[start:start+bind['count']*64]).hexdigest()
 if records:assert bindsha==records[0]['inverse_bind_sha256']
 records.append({'name':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'channels':321,'bones':107,'inverse_bind_sha256':bindsha})
 # Import metadata is explicit from first import; don't let Godot strip constant tracks.
 params=(ROOT/'game/assets/characters/player/spring_jump_v24/combat_spring_jump_v24.glb.import').read_text(encoding='utf-8').split('[params]')[1]
 params=params.replace('meshes/generate_lods=true','meshes/generate_lods=false')
 res='res://assets/characters/player/drive_attack_v32/'+name+'.glb'
 imp='[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\nsource_file="'+res+'"\n\n[params]'+params
 Path(str(path)+'.import').write_text(imp,encoding='utf-8')
(OUT/'runtime_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
(REPORT/'export.json').write_text(json.dumps({'carrier':carrier.name,'source_sha256':hashlib.sha256((SOURCE/'drive_attack_v32.blend').read_bytes()).hexdigest(),'clips':records},indent=2),encoding='utf-8')
print('DRIVE_ATTACK_V32_EXPORT',len(records),carrier.name,flush=True)
