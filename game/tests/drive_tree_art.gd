extends SceneTree
const Demo=preload("res://tests/helpers/drive_tree_demo.gd")
const World=preload("res://tests/helpers/firearm_review_world.gd")
var checks:=0
var output:=""
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
	call_deferred("run")
func check(value:bool,message:String) -> void:
	assert(value,message);checks+=1
func run() -> void:
	var world:=World.new();root.add_child(world)
	for id in ["guillotine","guillotine_saw","guillotine_lock","restraint_winch","hydraulic_press","compound_executor","shock_frame","exoskeleton","broad_cutter"]:
		var demo:=Demo.new();demo.configure(id);world.add_child(demo);demo.initialize(world);demo.set_process(false)
		check(demo.parts.size()==int(demo.manifest.part_count),id+" part count")
		var triangles:=0
		for part in demo.parts:
			for surface in part.mesh.mesh.get_surface_count():triangles+=part.mesh.mesh.surface_get_array_index_len(surface)/3
		check(triangles==int(demo.manifest.triangles),id+" triangles")
		for frame in 81:
			demo.sample_demo(frame/24.0)
			for part in demo.parts:
				var tr:Transform3D=part.mesh.transform
				check(tr.origin.is_finite() and tr.basis.is_finite(),id+" finite")
				check(tr.basis.get_scale().is_equal_approx(Vector3.ONE),id+" rigid scale")
		demo.sample_demo(1.75);var poses:Array=[]
		for part in demo.parts:poses.append(part.mesh.transform)
		demo.sample_demo(.1);demo.sample_demo(3.2);demo.sample_demo(1.75)
		for i in poses.size():check(demo.parts[i].mesh.transform.is_equal_approx(poses[i]),id+" deterministic scrub")
		if id=="restraint_winch":
			for mode in ["single","pull","bind"]:
				demo.winch_mode=mode;demo.sample_demo(1.8)
				check(demo.cables[0].visible,"primary cable")
				check(demo.cables[1].visible==(mode!="single"),"node cable variants")
		demo.queue_free();await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks},"  "))
	print("DRIVE_ART_DONE ",checks);quit()
