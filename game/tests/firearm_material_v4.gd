extends SceneTree
const Demo=preload("res://tests/helpers/firearm_material_v4_demo.gd")
const ReviewWorld=preload("res://tests/helpers/firearm_review_world.gd")
const IDS=["powder_barrel","gatling","smoke_launcher","artillery_shell","naval_shell","smoke_canister"]
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
	check(mat.albedo_texture!=null and mat.albedo_texture.get_size()==Vector2(1024,1024),label+" 1K color")
	check(mat.normal_enabled and mat.normal_texture!=null and mat.normal_texture.get_size()==Vector2(1024,1024),label+" 1K normal")
	check(mat.roughness_texture!=null and mat.roughness_texture.get_size()==Vector2(512,512),label+" 512 ORM")
	check(mat.metallic_texture==mat.roughness_texture and mat.ao_texture==mat.roughness_texture,label+" one ORM resource")
	check(mat.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_GREEN,label+" roughness green")
	check(mat.metallic_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_BLUE,label+" metal blue")
	check(mat.ao_enabled and mat.ao_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED,label+" occlusion red")
	var maps:Array=[["color",mat.albedo_texture],["normal",mat.normal_texture],["orm",mat.roughness_texture]]
	if mat.emission_enabled:
		check(mat.emission_texture!=null and mat.emission_texture.get_size()==Vector2(256,256),label+" isolated small emission map")
		maps.append(["emission",mat.emission_texture])
	for pair in maps:
		if shared.has(pair[0]):check(shared[pair[0]]==pair[1],label+" shared atlas resource: "+pair[0])
		else:shared[pair[0]]=pair[1]

func run() -> void:
	var world:=ReviewWorld.new();root.add_child(world)
	for asset_id in IDS:
		var demo:=Demo.new();demo.configure(asset_id)
		var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_tree_v1/%s.json"%asset_id))
		check(demo.manifest.sockets==before.sockets,asset_id+" original sockets")
		check(demo.manifest.dimensions==before.dimensions,asset_id+" original dimensions")
		var probe:Node3D=demo.parts_scene.instantiate();world.add_child(probe)
		var materials:Dictionary={};var triangles:=0;var surfaces:=0
		for item in demo.manifest.parts:
			var mesh:MeshInstance3D=probe.find_child(item.name,true,false)
			check(mesh!=null,asset_id+" assembly name resolves")
			if mesh==null:continue
			check(mesh.scale.is_equal_approx(Vector3.ONE),asset_id+" unit part scale")
			for surface in mesh.mesh.get_surface_count():
				surfaces+=1;var arrays:=mesh.mesh.surface_get_arrays(surface)
				triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
				check(arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_TANGENT].size()==arrays[Mesh.ARRAY_VERTEX].size()*4,asset_id+" complete tangents")
				var mat:StandardMaterial3D=mesh.get_active_material(surface);materials[mat.get_instance_id()]=mat
		check(triangles==int(before.triangles),asset_id+" unchanged triangle count")
		check(surfaces==int(before.part_count),asset_id+" one surface per original part")
		for mat in materials.values():inspect_material(mat,asset_id)
		if asset_id in ["artillery_shell","naval_shell","smoke_canister"]:
			for mat in materials.values():check(not mat.emission_enabled,asset_id+" identification paint does not glow")
		for socket_name in demo.manifest.sockets:
			var socket:Node3D=probe.find_child("v4_"+asset_id+"__"+socket_name,true,false)
			check(socket!=null,asset_id+" named socket")
			if socket!=null:
				var spec:Dictionary=demo.manifest.sockets[socket_name]
				check(socket.global_position.distance_to(demo.point(spec.position))<.00001,asset_id+" socket location")
				check((-socket.global_basis.z).distance_to(demo.point(spec.direction))<.00001,asset_id+" socket direction")
		probe.free();world.add_child(demo);demo.initialize(world);demo.set_process(false)
		check(demo.parts.size()==int(before.part_count),asset_id+" assembly part count")
		var max_error:=0.0;var finite:=true;var moving:=0
		for frame in 85:
			demo.sample_demo(frame/24.0)
			for part in demo.parts:
				finite=finite and part.mesh.transform.is_finite()
				max_error=maxf(max_error,absf(part.mesh.basis.determinant()-1.0))
				if asset_id=="gatling" and frame==30:
					if demo.part_info[part.name].group=="rotor":
						if not part.mesh.transform.is_equal_approx(part.target):moving+=1
					else:check(part.mesh.transform.is_equal_approx(part.target),"gatling housing stays fixed")
		check(finite and max_error<.00001,asset_id+" 85 rigid samples stay finite and never stretch")
		if asset_id=="gatling":check(moving==16,"all 16 rotor pieces turn together")
		demo.sample_demo(1.30);var sampled:Array=[]
		for part in demo.parts:sampled.append(part.mesh.transform)
		demo.sample_demo(.10);demo.sample_demo(1.30)
		for i in demo.parts.size():
			var part:Dictionary=demo.parts[i]
			check(part.mesh.transform.is_equal_approx(sampled[i]),asset_id+" scrub is reversible")
			for mat in part.materials:
				check(mat.albedo_texture==shared.color and mat.normal_texture==shared.normal and mat.roughness_texture==shared.orm,asset_id+" moving parts keep PBR maps")
		metrics[asset_id]={"parts":demo.parts.size(),"triangles":triangles,"surfaces":surfaces,"materials":materials.size(),"max_rigid_error":max_error}
		demo.queue_free();await process_frame
	world.free()
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"models":metrics,"shared_maps":shared.keys(),"scope":"Prepared assets and existing review mechanisms; no new gameplay implementation."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_MATERIAL_V4_CHECKS ",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
