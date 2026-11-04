extends "res://tests/review_drive_attack_v32.gd"
## Close views to inspect the moving grip and the left-side butt path.

func run() -> void:
	root.size=Vector2i(1280,720)
	contract=JSON.parse_string(FileAccess.get_file_as_string(DIR+"runtime_contract.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	setup_stage()
	for node in world.get_children():
		if node is Label3D:node.hide()
	for v in visuals:v.position=Vector3.ZERO;v.hide()
	for i in 8:await process_frame
	var poses=[
		["bolt_ready","drive_bolt_loop_v32",0.0,"bolt_cutter"],
		["bolt_extend","drive_bolt_loop_v32",0.48,"bolt_cutter"],
		["grinder_chamber","drive_grinder_sweep_v32",0.28,"grinder"],
		["grinder_follow","drive_grinder_sweep_v32",0.60,"grinder"],
		["saw_hold","drive_chainsaw_cut_loop_v32",0.5,"chainsaw"],
		["spin","drive_chainsaw_spin_v32",0.50,"chainsaw"]]
	for index in visuals.size():
		var v=visuals[index];v.show()
		for row in poses:
			v.set_active_tool(row[3]);v.staff_visual.finish_assembly();v.staff_visual.advance(.5,false)
			sample(v,row[1],float(row[2])*float(contract.clips[row[1]].duration))
			for view in ["front","left"]:
				camera.size=1.60
				camera.position=Vector3(0,1.65,-4) if view=="front" else Vector3(-3.5,1.65,-1.7)
				camera.look_at(Vector3(0,1.0,0))
				await process_frame;await RenderingServer.frame_post_draw
				require(root.get_texture().get_image().save_png(output.path_join("%s_%s_%s.png"%["civilian" if index==0 else "transformed",row[0],view]))==OK,"detail capture")
				shots+=1
		v.hide()
	FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"captures":shots,"checks":checks},"  "))
	print("DRIVE_ATTACK_V32_REVIEW_COMPLETE details ",shots)
	quit(0)
