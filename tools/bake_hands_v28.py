"""Bake the original hand color to a compact, non-overlapping 512px atlas."""
from pathlib import Path
import bpy,sys,json
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/model_refinement_v28/model_refinement_v28.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False,use_scripts=False)
ob=bpy.data.objects['Body_Hands_v7'];bpy.data.objects['PlayerRig_v7'].data.pose_position='REST'
assert not ob.get('v28_hand_atlas_baked',False)
ob.data.uv_layers.active.name='SourceTripoUV_v28'
atlas=ob.data.uv_layers.new(name='HandAtlas_v28');ob.data.uv_layers.active=atlas;atlas.active_render=True
for o in bpy.context.selected_objects:o.select_set(False)
ob.hide_set(False);ob.select_set(True);bpy.context.view_layer.objects.active=ob
with bpy.context.temp_override(object=ob,active_object=ob,selected_objects=[ob],selected_editable_objects=[ob]):
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
 bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.02,area_weight=.5,correct_aspect=True,scale_to_bounds=True)
 bpy.ops.object.mode_set(mode='OBJECT')
target=bpy.data.images.new('Hands_BaseColor_v28',width=512,height=512,alpha=False)
target.colorspace_settings.name='sRGB'
for slot in ob.material_slots:
 original=slot.material;mat=original.copy();slot.material=mat;nt=mat.node_tree
 bsdf=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
 output=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
 source=bsdf.inputs['Base Color'];em=nt.nodes.new('ShaderNodeEmission')
 if source.is_linked:nt.links.new(source.links[0].from_socket,em.inputs['Color'])
 else:em.inputs['Color'].default_value=source.default_value
 nt.links.new(em.outputs[0],output.inputs['Surface'])
 uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='SourceTripoUV_v28'
 for n in list(nt.nodes):
  if n.type=='TEX_IMAGE':nt.links.new(uv.outputs['UV'],n.inputs['Vector'])
 node=nt.nodes.new('ShaderNodeTexImage');node.image=target;nt.nodes.active=node
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.bake.use_selected_to_active=False;scene.render.bake.margin=8;scene.render.bake.use_clear=True
with bpy.context.temp_override(object=ob,active_object=ob,selected_objects=[ob],selected_editable_objects=[ob]):bpy.ops.object.bake(type='EMIT',uv_layer='HandAtlas_v28')
folder=SOURCE.parent/'textures';folder.mkdir(exist_ok=True)
target.filepath_raw=str(folder/'hands_basecolor_v28.png');target.file_format='PNG';target.save();target.pack()
mat=bpy.data.materials.new('HandsSkin_v28');mat.use_nodes=True
bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=target
mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color']);bsdf.inputs['Roughness'].default_value=.8;bsdf.inputs['Specular IOR Level'].default_value=.23
ob.data.materials.clear();ob.data.materials.append(mat)
for p in ob.data.polygons:p.material_index=0
ob.data.uv_layers.remove(ob.data.uv_layers['SourceTripoUV_v28']);ob.data.uv_layers.active=ob.data.uv_layers['HandAtlas_v28'];ob.data.uv_layers.active.active_render=True
ob['v28_hand_atlas_baked']=True
bpy.data.objects['PlayerRig_v7'].data.pose_position='POSE';scene.frame_set(71)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
print('V28_HAND_ATLAS_BAKED_512',flush=True)
