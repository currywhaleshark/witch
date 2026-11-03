extends SceneTree
const Demo = preload("res://tests/helpers/firearm_tree_demo.gd")
const ReviewWorld = preload("res://tests/helpers/firearm_review_world.gd")
const IDS = ["matchlock", "rifle", "shotgun", "powder_barrel", "gatling", "smoke_launcher", "artillery_shell", "naval_shell", "smoke_canister"]
var checks := 0
var failures: Array[String] = []
var output := ""
var metrics: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world := ReviewWorld.new()
	root.add_child(world)
	for id in IDS:
		var demo := Demo.new()
		demo.configure(id)
		var probe: Node3D = demo.parts_scene.instantiate()
		world.add_child(probe)
		for socket_name in demo.manifest.sockets:
			var socket: Node3D = probe.find_child(id+"__"+socket_name,true,false)
			check(socket!=null, id+" named socket: "+socket_name)
			if socket!=null:
				var info: Dictionary=demo.manifest.sockets[socket_name]
				check(socket.global_position.distance_to(demo.point(info.position))<.00001,id+" socket origin survives export")
				check((-socket.global_basis.z).distance_to(demo.point(info.direction))<.00001,id+" socket forward direction survives export")
		probe.free()
		world.add_child(demo)
		demo.initialize(world)
		demo.set_process(false)
		check(demo.parts.size() == int(demo.manifest.part_count), id+" all named assembly parts import")
		var triangles := 0
		var bounds := AABB()
		var first := true
		for part in demo.parts:
			check(demo.part_info.has(part.name), id+" stable part name: "+part.name)
			check(is_equal_approx(part.mesh.transform.basis.determinant(),1.0), id+" rigid part has unit scale")
			for corner in part.corners:
				var p: Vector3 = part.target * corner
				bounds = AABB(p,Vector3.ZERO) if first else bounds.expand(p)
				first = false
			for surface in part.mesh.mesh.get_surface_count():
				triangles += part.mesh.mesh.surface_get_array_index_len(surface) / 3
				var material: StandardMaterial3D = part.mesh.get_active_material(surface)
				check(material != null and material.roughness >= .2, id+" valid PBR surface")
		check(triangles == int(demo.manifest.triangles), id+" exported topology count matches saved source")
		check(bounds.size.distance_to(demo.point(demo.manifest.dimensions)) < .00005, id+" metre dimensions survive import")
		if id in ["matchlock","rifle","shotgun","gatling","artillery_shell","naval_shell"]:
			check(bounds.position.z >= -.001, id+" geometry trails the local forward tip")
		if id in ["powder_barrel","smoke_launcher"]:
			check(absf(bounds.position.y) < .0002, id+" ground origin rests on floor")
		var max_frame_error := 0.0
		var moving := 0
		var all_finite := true
		for frame in 73:
			demo.sample_demo(frame / 24.0)
			for part in demo.parts:
				all_finite = all_finite and part.mesh.transform.is_finite()
				max_frame_error = maxf(max_frame_error, absf(part.mesh.basis.determinant() - 1.0))
				if id=="gatling" and frame==30:
					if demo.part_info[part.name].group=="rotor":
						if not part.mesh.transform.is_equal_approx(part.target): moving += 1
					else: check(part.mesh.transform.is_equal_approx(part.target),"gatling fixed housing does not turn")
		check(max_frame_error < .00001, id+" rigid mechanisms never stretch")
		check(all_finite, id+" all 73 sampled poses remain finite")
		if id=="gatling": check(moving==16,"six barrels, six muzzle collars, two braces, hub and spindle turn together")
		demo.sample_demo(1.30)
		var sampled: Array = []
		for part in demo.parts: sampled.append(part.mesh.transform)
		demo.sample_demo(.10)
		demo.sample_demo(1.30)
		for i in demo.parts.size(): check(demo.parts[i].mesh.transform.is_equal_approx(sampled[i]),id+" review can scrub without cumulative drift")
		metrics[id]={"parts":demo.parts.size(),"triangles":triangles,"dimensions":bounds.size,"max_rigid_error":max_frame_error}
		demo.queue_free()
		await process_frame
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"assets":metrics,
		"scope":"Imported art/part contracts and deterministic review mechanisms. Future skills are not implemented."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_ART_CHECKS ",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
