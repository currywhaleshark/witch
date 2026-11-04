"""A tiny closed, UV-mapped export-only carrier; never shown by player_visual."""
import bpy
def create(rig):
 bpy.ops.mesh.primitive_cube_add(size=.002,location=(0,0,.001))
 carrier=bpy.context.object;carrier.name='AnimationSkinCarrier_v30'
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 group=carrier.vertex_groups.new(name='DEF-pelvis');group.add(list(range(len(carrier.data.vertices))),1.,'REPLACE')
 modifier=carrier.modifiers.new('SkinCarrier','ARMATURE');modifier.object=rig
 carrier.parent=rig
 material=bpy.data.materials.new('AnimationCarrierDiagnostic');material.diffuse_color=(.5,.5,.5,1.)
 carrier.data.materials.append(material)
 return carrier
