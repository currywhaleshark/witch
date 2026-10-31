extends RefCounted
## Two transient clothed previews around the unchanged logical outfit swap.
## Both use the live skeleton. Complementary clipping keeps one side of the
## sweep covered; originals are restored on finish, cancellation and reset.
const SHADER = preload("res://shaders/outfit_reveal.gdshader")
var visual: Node3D
var previews: Array[Node3D] = []
var materials: Array[ShaderMaterial] = []
var hidden_meshes: Array = []
var active := false
var progress := 0.0
var error := ""

func initialize(player_visual: Node3D) -> void:
	visual = player_visual

func begin() -> bool:
	if active: return true
	# Duplicate the live mesh instances, sharing immutable mesh/texture resources.
	# The clone has the same parent depth, so its existing skeleton paths stay valid.
	var old: Node3D = visual.runtime.slots.outfit.duplicate(0) as Node3D
	visual.runtime.body.add_child(old)
	old.visible = false
	var next: Node3D = visual.runtime._stage_part(visual.FieldEntry.OUTFIT,"outfit")
	if next == null:
		error = visual.runtime.last_error
		old.free()
		return false
	previews = [old,next]
	for i in previews.size():
		var node := previews[i]
		node.name = "OutfitReveal_" + ("incoming" if i else "outgoing")
		for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var base := mesh.get_active_material(surface) as StandardMaterial3D
				if base == null: continue
				var material := ShaderMaterial.new()
				material.shader = SHADER
				material.set_shader_parameter("color_map",base.albedo_texture)
				material.set_shader_parameter("base_color",base.albedo_color)
				material.set_shader_parameter("normal_map",base.normal_texture)
				material.set_shader_parameter("normal_strength",base.normal_scale if base.normal_enabled else 0.0)
				material.set_shader_parameter("roughness_value",base.roughness)
				material.set_shader_parameter("metallic_value",base.metallic)
				material.set_shader_parameter("metal_map",base.metallic_texture)
				material.set_shader_parameter("metal_channel",_channel(base.metallic_texture_channel))
				material.set_shader_parameter("textured_metallic",base.metallic_texture != null)
				material.set_shader_parameter("rough_map",base.roughness_texture)
				material.set_shader_parameter("rough_channel",_channel(base.roughness_texture_channel))
				material.set_shader_parameter("textured_roughness",base.roughness_texture != null)
				material.set_shader_parameter("incoming",i == 1)
				mesh.set_surface_override_material(surface,material)
				materials.append(material)
		node.visible = true
	active = true
	return true

func _channel(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED: return Vector4(1,0,0,0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0,1,0,0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0,0,1,0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0,0,0,1)
	return Vector4(1.0/3.0,1.0/3.0,1.0/3.0,0)

func sample(value: float) -> void:
	if not active: return
	progress = clampf(value,0.0,1.0)
	var slot: Node = visual.runtime.slots.outfit
	for mesh: MeshInstance3D in slot.find_children("*","MeshInstance3D",true,false):
		var seen := false
		for record in hidden_meshes:
			if is_instance_valid(record.mesh) and record.mesh == mesh: seen = true; break
		if not seen:
			hidden_meshes.append({"mesh":mesh,"visible":mesh.visible})
			mesh.visible = false
	var from_world: Transform3D = visual.runtime.skeleton.global_transform.affine_inverse()
	for material in materials:
		material.set_shader_parameter("character_from_world",from_world)
		material.set_shader_parameter("sweep_height",lerpf(-.07,1.72,smoothstep(0.0,1.0,progress)))

func clear() -> void:
	for record in hidden_meshes:
		if is_instance_valid(record.mesh): record.mesh.visible = record.visible
	hidden_meshes.clear()
	for node in previews:
		if is_instance_valid(node): node.free()
	previews.clear()
	materials.clear()
	active = false

func debug_state() -> Dictionary:
	return {"active":active,"progress":progress,"preview_count":previews.size(),"error":error}
