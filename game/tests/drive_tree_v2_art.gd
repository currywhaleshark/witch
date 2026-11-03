extends SceneTree
const Demo=preload("res://tests/helpers/drive_tree_v2_demo.gd")
const World=preload("res://tests/helpers/firearm_review_world.gd")
var checks:=0
var output:=""
var measurements:Dictionary={}
var frame_bounds:Dictionary={}
var vertex_cache:Dictionary={}
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
	call_deferred("run")
func check(ok:bool,message:String)->void:
	assert(ok,message);checks+=1
func bounds(part:Dictionary)->AABB:
	var object_id:int=part.mesh.get_instance_id()
	if frame_bounds.has(object_id):return frame_bounds[object_id]
	var mesh_id:int=part.mesh.mesh.get_instance_id()
	if not vertex_cache.has(mesh_id):
		var points:PackedVector3Array=[]
		for s in part.mesh.mesh.get_surface_count():points.append_array(part.mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
		vertex_cache[mesh_id]=points
	var vertices:PackedVector3Array=vertex_cache[mesh_id]
	var first:Vector3=part.mesh.transform*vertices[0]
	var box:=AABB(first,Vector3.ZERO)
	for v in vertices:box=box.expand(part.mesh.transform*v)
	frame_bounds[object_id]=box
	return box
func run()->void:
	var world:=World.new();root.add_child(world)
	for id in ["guillotine","guillotine_saw","guillotine_lock","compound_executor"]:
		var demo:=Demo.new();demo.configure(id);world.add_child(demo);demo.initialize(world);demo.set_process(false)
		var minimum:=INF;var lock_rest:Dictionary={};var last_floor:=INF;var platen_rise:=false
		for sample in 343:
			var t:=sample/120.0;demo.sample_demo(t);frame_bounds.clear()
			for part in demo.parts:
				var p:Dictionary=demo.info[part.name];var group:String=p.group
				check(part.mesh.transform.origin.is_finite(),id+" finite")
				check(part.mesh.transform.basis.get_scale().is_equal_approx(Vector3.ONE),id+" rigid")
				if id.begins_with("guillotine") and p.role in ["falling_blade","descending_saw"] and t>=1.0:
					var low:=bounds(part).position.y;minimum=minf(minimum,low)
					check(low>=-.0001,id+" cutting tip below floor")
					if t>=2.5:check(low<.015,id+" cutting tip stops above floor")
				if id=="guillotine_lock":
					if not group.begins_with("clamp_") and t<.60:check(not part.mesh.visible,"frame appeared before target lock")
					if group.begins_with("clamp_") and t>=.56:
						check(part.mesh.visible,"clamp not holding target")
						if not lock_rest.has(part.name):lock_rest[part.name]=part.mesh.transform
						else:check(part.mesh.transform.is_equal_approx(lock_rest[part.name]),"clamp moved during frame assembly")
				if id=="compound_executor" and p.role=="platen" and t>=1.55 and t<=2.10:
					var low:=bounds(part).position.y
					if last_floor<INF:check(low>=last_floor-.00001,"press failed to rise")
					last_floor=low;platen_rise=true
			if id=="compound_executor" and t>=1.05:
				for saw in demo.parts:
					if not demo.info[saw.name].group.begins_with("saw_"):continue
					for platen in demo.parts:
						if demo.info[platen.name].role in ["platen","press_rib_0","press_rib_1","press_rib_2","press_rib_3","press_rib_4"]:
							check(not bounds(saw).intersects(bounds(platen)),"saw/platen bounds overlap while operating")
		if id.begins_with("guillotine"):measurements[id]={"minimum_cutting_tip_y":minimum}
		else:check(platen_rise,"missing press rise sampling")
		# Scrubbing must restore all visual state, including the early lock-only phase.
		for t in [.18,.48,.59,.80,1.18,1.60,2.20,3.10]:
			demo.sample_demo(t);var poses:Array=[];var visible:Array=[]
			for part in demo.parts:poses.append(part.mesh.transform);visible.append(part.mesh.visible)
			demo.sample_demo(2.8);demo.sample_demo(0);demo.sample_demo(t)
			for i in demo.parts.size():
				check(demo.parts[i].mesh.transform.is_equal_approx(poses[i]),id+" non-deterministic transform")
				check(demo.parts[i].mesh.visible==visible[i],id+" non-deterministic visibility")
		demo.queue_free();await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks,"measurements":measurements},"  "))
	print("DRIVE_V2_TEST_DONE ",checks);quit()
