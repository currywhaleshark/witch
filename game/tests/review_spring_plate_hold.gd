extends "res://tests/review_spring_plate_v1.gd"

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();arena.field_entry_mode=2;root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat")
	for id in ["close","native"]:
		prepare();arena.bind_slot("q","spring_dash");arena.config.cast_speed_score=0.0
		var origin:Vector3=arena.player.position
		arena.player_model.look_at(origin+Vector3.RIGHT)
		DirAccess.make_dir_recursive_absolute(output.path_join(id))
		var rows:Array=[]
		var p:Node3D=null
		for frame in 90:
			if frame==8:
				arena.request_slot("q",{"ground":[origin.x+5,0,origin.z]});p=arena.spring_plate
				if is_instance_valid(p):p.set_process(false)
			var launched:bool=is_instance_valid(p) and p.mode!="assembling"
			await physics_frame
			arena._physics_process(1.0/60.0)
			if launched and is_instance_valid(p):p.advance(1.0/60.0)
			if id=="native":frame_camera(true)
			else:
				arena.hud.visible=false;arena.move_marker.visible=false;arena.hover_ring.visible=false
				var focus:Vector3=origin+Vector3(2,.60,0)
				arena.camera.size=4.7;arena.camera.position=focus+Vector3(0,6,-9);arena.camera.look_at(focus)
			await capture(id+"/%03d.jpg"%frame)
			var opacity:=0.0
			if is_instance_valid(p):
				for part in p.parts:
					for material in part.materials:opacity=maxf(opacity,material.albedo_color.a)
			rows.append({"seconds":frame/60.0,"dash_active":not arena.dash.is_empty(),"jump_mode":arena.player_visual._spring_jump.mode,"plate":plate_state(p),"max_opacity":opacity})
		sequences.append({"id":id,"fps":60,"frames":90,"samples":rows})
	var result:Dictionary={"passed":true,"captures":captures,"sequences":sequences,"scope":"Actual arena dash and visual landing; plate manually advanced at 60Hz to avoid render-time variation. Close and selected native camera, current game lighting."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SPRING_HOLD_REVIEW ",captures)
	arena.free();quit(0)
