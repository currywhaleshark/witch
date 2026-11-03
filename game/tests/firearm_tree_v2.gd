extends SceneTree
var output := ""
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

func vec(data: Array) -> Vector3:
	return Vector3(data[0],data[1],data[2])

func run() -> void:
	for id in ["matchlock","rifle","shotgun"]:
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_tree_v2/%s.json"%id))
		var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_tree_v1/%s.json"%id))
		var model:Node3D=load("res://assets/weapons/firearm_tree_v2/%s.glb"%id).instantiate()
		root.add_child(model)
		var meshes:=model.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==data.part_count,id+" preserves the independent assembly part count")
		check(model.scale.is_equal_approx(Vector3.ONE),id+" no whole-model stretching")
		var bounds:=AABB();var first:=true;var triangles:=0
		for item in data.parts:
			var mesh:MeshInstance3D=model.find_child(item.name,true,false)
			check(mesh!=null,id+" resolves assembly name: "+item.name)
			if mesh==null:continue
			check(mesh.scale.is_equal_approx(Vector3.ONE),id+" unit part scale")
			for surface in mesh.mesh.get_surface_count():
				triangles+=mesh.mesh.surface_get_array_index_len(surface)/3
				check(mesh.get_active_material(surface) is StandardMaterial3D,id+" export keeps PBR materials")
			var aabb: AABB=mesh.mesh.get_aabb()
			for x in [aabb.position.x,aabb.end.x]:
				for y in [aabb.position.y,aabb.end.y]:
					for z in [aabb.position.z,aabb.end.z]:
						var p:Vector3=mesh.global_transform*Vector3(x,y,z)
						bounds=AABB(p,Vector3.ZERO) if first else bounds.expand(p)
						first=false
		check(triangles==data.triangles,id+" source and exported triangle counts agree")
		check(bounds.size.distance_to(vec(data.dimensions))<.00005,id+" source and imported dimensions agree")
		check(bounds.size.z>float(old.dimensions[2])*1.20,id+" longer silhouette")
		check(bounds.size.y<float(old.dimensions[1])*.75,id+" lower overall profile")
		check(bounds.size.x<float(old.dimensions[0])*.80,id+" slimmer width")
		check(bounds.position.z>=-.001,id+" model remains behind muzzle")
		for name in data.sockets:
			var socket:Node3D=model.find_child("v2_"+id+"__"+name,true,false)
			check(socket!=null,id+" socket exists: "+name)
			if socket!=null:
				check(socket.global_position.distance_to(vec(data.sockets[name].position))<.00001,id+" socket position")
				check((-socket.global_basis.z).distance_to(vec(data.sockets[name].direction))<.00001,id+" socket direction")
		check(vec(data.sockets.Socket_muzzle.position).is_zero_approx(),id+" existing muzzle anchor stays zero")
		metrics[id]={"old_dimensions":old.dimensions,"dimensions":data.dimensions,"parts":data.part_count,"triangles":triangles}
		model.free()
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"models":metrics}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_V2_CHECKS ",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
