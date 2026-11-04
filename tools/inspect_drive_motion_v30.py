"""Read local licensed motion files; never edit or redistribute their sources."""
import bpy, json, hashlib, math, sys
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/drive_attack_v30/local'; OUT.mkdir(parents=True,exist_ok=True)
(OUT/'.gitignore').write_text('*\n!.gitignore\n',encoding='utf-8')
SOURCES={
 'polearm':ROOT/'reports/drive_motion_research_v1/local/Animations/Female/Combat/Polearm/HumanF@AttackPolearm01.fbx',
 'slash':ROOT/'reports/drive_motion_research_v1/local/mixamo/Great Sword Slash.fbx',
 'spin':ROOT/'reports/drive_motion_research_v1/local/mixamo/Great Sword High Spin Attack.fbx',
}
for key,path in SOURCES.items():
 if not path.exists(): continue
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.context.scene.render.fps=30
 bpy.ops.import_scene.fbx(filepath=str(path),use_anim=True)
 rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
 action=rig.animation_data.action
 for track in rig.animation_data.nla_tracks: track.mute=True
 rest={b.name:rig.matrix_world@b.matrix_local for b in rig.data.bones}
 frames=[]
 for f in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
  bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
  frames.append({p.name:[list(row) for row in rig.matrix_world@p.matrix] for p in rig.pose.bones})
 report={'source':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
  'action':action.name,'range':list(action.frame_range),'fps':30,'rest':{n:[list(row) for row in m] for n,m in rest.items()},'samples':frames}
 (OUT/(key+'_source.json')).write_text(json.dumps(report),encoding='utf-8')
 print('SOURCE',key,action.name,list(action.frame_range),'bones',list(rest),flush=True)
