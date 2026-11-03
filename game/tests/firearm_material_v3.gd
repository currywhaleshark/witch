extends SceneTree
const StubWorld=preload("res://tests/helpers/firearm_review_world.gd")
var output:=""
var checks:=0
var failures:Array[String]=[]
var metrics:Dictionary={}
var shared:Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

func inspect_material(mat:StandardMaterial3D,label:String) -> void:
	check(mat.albedo_texture!=null and mat.albedo_texture.get_size()==Vector2(1024,1024),label+" 1K albedo")
	check(mat.normal_enabled and mat.normal_texture!=null and mat.normal_texture.get_size()==Vector2(1024,1024),label+" 1K normal")
	check(mat.roughness_texture!=null and mat.roughness_texture.get_size()==Vector2(512,512),label+" 512 ORM")
	check(mat.metallic_texture==mat.roughness_texture and mat.ao_texture==mat.roughness_texture,label+" one ORM resource")
	check(mat.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_GREEN,label+" roughness green")
	check(mat.metallic_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_BLUE,label+" metal blue")
	check(mat.ao_enabled and mat.ao_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED,label+" occlusion red")
	for pair in [["color",mat.albedo_texture],["normal",mat.normal_texture],["orm",mat.roughness_texture]]:
		if shared.has(pair[0]):check(shared[pair[0]]==pair[1],label+" shared texture across gun models: "+pair[0])
		else:shared[pair[0]]=pair[1]
	if mat.emission_texture!=null:
		check(mat.emission_texture.get_size()==Vector2(256,256),label+" small isolated glow")

func run() -> void:
	for asset_id in ["matchlock","rifle","shotgun"]:
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_material_v3/%s.json"%asset_id))
		var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_tree_v2/%s.json"%asset_id))
		var model:Node3D=load("res://assets/weapons/firearm_material_v3/%s.glb"%asset_id).instantiate();root.add_child(model)
		var parts:=model.find_children("*","MeshInstance3D",true,false)
		check(parts.size()==int(old.part_count),asset_id+" unchanged rigid part count")
		check(data.dimensions==old.dimensions,asset_id+" unchanged dimensions")
		check(data.sockets==old.sockets,asset_id+" unchanged muzzle and sockets")
		var tris:=0;var materials:Dictionary={};var surfaces:=0
		for part in data.parts:
			var mesh:MeshInstance3D=model.find_child(part.name,true,false)
			check(mesh!=null,asset_id+" assembly name resolves")
			if mesh==null:continue
			check(mesh.scale.is_equal_approx(Vector3.ONE),asset_id+" unit part scale")
			for surface in mesh.mesh.get_surface_count():
				surfaces+=1
				var arrays:=mesh.mesh.surface_get_arrays(surface)
				tris+=arrays[Mesh.ARRAY_INDEX].size()/3
				check(arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_TANGENT].size()==arrays[Mesh.ARRAY_VERTEX].size()*4,asset_id+" complete tangent basis")
				var mat:StandardMaterial3D=mesh.get_active_material(surface);materials[mat.get_instance_id()]=mat
		check(tris==int(old.triangles),asset_id+" unchanged triangle budget")
		check(surfaces==parts.size(),asset_id+" one surface per part")
		check(materials.size()==2,asset_id+" surface and isolated glow materials only")
		for mat in materials.values():inspect_material(mat,asset_id)
		metrics[asset_id]={"parts":parts.size(),"triangles":tris,"surfaces":surfaces,"materials":materials.size()}
		model.free()
	# Verify the actual assembly class keeps every imported PBR map during its opacity changes.
	var world:=StubWorld.new();root.add_child(world)
	var assembly=load("res://scripts/shotgun_cast.gd").new();world.add_child(assembly);assembly.initialize(world)
	assembly.set_process(false);assembly.sample_progress(.65)
	check(assembly.parts_scene.resource_path.contains("firearm_material_v3"),"runtime shotgun uses v3")
	for part in assembly.parts:
		for mat in part.materials:
			check(mat.albedo_texture==shared.color and mat.normal_texture==shared.normal and mat.roughness_texture==shared.orm,"assembly preserves shared PBR maps")
	assembly.fire(Transform3D.IDENTITY)
	assembly.advance(.10)
	check(assembly.mode=="fired","material pass retains shot/recoil phase")
	assembly.free();world.free()
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"models":metrics,"shared_runtime_textures":shared.keys()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_MATERIAL_V3_CHECKS ",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
