extends "res://tests/staff_visual.gd"
func run() -> void:
	var scene:Node3D=load("res://assets/weapons/staff_material_v3/staff_parts.glb").instantiate()
	root.add_child(scene)
	var meshes:Array=scene.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==52,"all 52 independently moving rigid meshes import")
	var surfaces:=0
	var vertices:=0
	var bad_tangents:=0
	var materials:Dictionary={}
	for mesh:MeshInstance3D in meshes:
		surfaces+=mesh.mesh.get_surface_count()
		for surface in mesh.mesh.get_surface_count():
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			var count:int=arrays[Mesh.ARRAY_VERTEX].size()
			vertices+=count
			if arrays[Mesh.ARRAY_TANGENT]==null or arrays[Mesh.ARRAY_TANGENT].size()!=count*4:bad_tangents+=1
			var material:Material=mesh.mesh.surface_get_material(surface)
			materials[material.get_instance_id()]=material
	check(surfaces==55,"55 surfaces preserve a separate emission boundary on three mixed parts")
	check(bad_tangents==0,"engine generates complete tangent data for the baked normals")
	check(materials.size()==2,"all parts reuse one body material and one core material")
	var mat:StandardMaterial3D
	var core:StandardMaterial3D
	for candidate:StandardMaterial3D in materials.values():
		if candidate.emission_enabled:core=candidate
		else:mat=candidate
	check(mat!=null and core!=null,"ordinary surfaces have no emission; original cores retain it")
	check(mat.albedo_texture!=null and mat.albedo_texture.get_size()==Vector2(1024,1024),"1K albedo imported")
	check(mat.normal_enabled and mat.normal_texture!=null and mat.normal_texture.get_size()==Vector2(1024,1024),"1K normal map enabled")
	check(mat.roughness_texture!=null and mat.roughness_texture.get_size()==Vector2(512,512),"512 roughness map imported")
	check(mat.metallic_texture!=null and mat.metallic_texture.get_size()==Vector2(512,512),"512 metallic map imported")
	check(mat.ao_enabled and mat.ao_texture!=null,"local cavity map enabled")
	check(core.emission_enabled and core.emission_texture!=null and core.emission_texture.get_size()==Vector2(256,256),"256 core emission map enabled")
	check(mat.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_GREEN,"roughness uses ORM green")
	check(mat.metallic_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_BLUE,"metalness uses ORM blue")
	check(mat.ao_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED,"occlusion uses ORM red")
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"surfaces":surfaces,
		"vertices":vertices,"bad_tangent_surfaces":bad_tangents,"materials":materials.size()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STAFF_MATERIAL_VALIDATION_COMPLETE checks=",checks.size()," failures=",failures.size())
	scene.free();quit(0 if failures.is_empty() else 1)
