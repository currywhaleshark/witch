"""Independent Blender round-trip of the exported animation carrier and bones."""
import bpy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/drive_attack_v32'
sys.path.insert(0,str(Path.home()/'.agents/skills/blender-asset-qa/scripts'))
try:
 import qa_check
except ImportError:
 qa_check=None
reports={}
for path in sorted((ROOT/'game/assets/characters/player/drive_attack_v32').glob('*.glb')):
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=24
 bpy.ops.import_scene.gltf(filepath=str(path))
 rigs=[o for o in bpy.data.objects if o.type=='ARMATURE'];meshes=[o for o in bpy.data.objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
 print('REIMPORT_SHAPE',path.name,[(o.name,len(o.data.bones)) for o in rigs],[o.name for o in meshes],flush=True)
 assert len(rigs)==1 and len(meshes)==1
 joint_names=[b.name for b in rigs[0].data.bones if b.name.startswith('DEF-')]
 assert len(joint_names)==107,(len(joint_names),[b.name for b in rigs[0].data.bones])
 assert len(bpy.data.actions)==1
 rigs[0].data.pose_position='REST';bpy.context.view_layer.update()
 if qa_check:
  result=qa_check.run(objects=[meshes[0].name],profile='game',uv=False,no_modifiers=True)
  # Animation-only carrier deliberately omits all texture/material payloads.
  assert result['pass'],result['errors']
 else:
  action=bpy.data.actions[0]
  result={'pass':None,'skipped':'blender-asset-qa skill not installed on this PC','bones':len(joint_names),
   'carrier_triangles':len(meshes[0].data.polygons),'action_frame_range':list(action.frame_range)}
 reports[path.name]=result
(OUT/'reimport_asset_qa.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
print('DRIVE_V32_REIMPORT_QA',len(reports),flush=True)
