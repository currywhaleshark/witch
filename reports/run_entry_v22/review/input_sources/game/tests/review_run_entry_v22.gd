extends "res://tests/review_staff_visual.gd"

func previous_controller() -> GDScript:
	var original:=FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../reports/run_entry_v22/player_visual_before.gd"))
	var method:="func _sample_locomotion"+original.get_slice("func _sample_locomotion",1).get_slice("func _settle_turn",0)
	var source:=GDScript.new()
	source.source_code="extends \"res://scripts/player_visual.gd\"\n"+method
	assert(source.reload()==OK)
	return source

func configure_camera(view: String) -> void:
	arena.hud.visible=view=="native"
	arena.move_marker.visible=false;arena.hover_ring.visible=false
	if view=="native":
		frame_camera(true)
	else:
		var center:Vector3=arena.player.position+Vector3(0,1.12,0)
		arena.camera.size=2.95
		arena.camera.position=center+(Vector3(0,.08,-7) if view=="front" else Vector3(3,.6,-7))
		arena.camera.look_at(center)

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	var previous:=previous_controller()
	for view in ["front","quarter","native"]:
		for version in ["before","after"]:
			if view=="native" and version=="before":continue
			prepare()
			if version=="before":
				var replacement=previous.new()
				arena.player_visual.free()
				arena.player.add_child(replacement);assert(replacement.initialize())
				arena.player_visual=replacement;arena.player_model=replacement
				arena.tool_visuals=replacement.tool_visuals;arena.grinder_disk=replacement.grinder_disk
			if view!="front":
				arena.request_slot("q",{});arena.player_visual.set_active_tool(arena.state.active_tool);arena.player_visual.staff_visual.finish_assembly()
			var id:String=view+"_"+version
			DirAccess.make_dir_recursive_absolute(output.path_join(id))
			var rows:Array=[]
			for frame in 91:
				if frame in [12,44,62]:
					arena.set_destination(arena.player.position+(Vector3(2,0,-4) if view=="quarter" and frame==62 else Vector3(0,0,-4)))
				if frame in [33,47]:
					arena.moving=false;arena.destination=arena.player.position;arena.player_route={}
				arena.paused=frame>=78 and frame<84
				await physics_frame
				arena._physics_process(1./60.)
				configure_camera(view)
				await capture(id+"/%03d.jpg"%frame)
				var v=arena.player_visual
				var sk:Skeleton3D=v.runtime.skeleton
				var hand:Transform3D=sk.get_bone_global_pose(sk.find_bone("DEF-hand.R"))
				var staff:Transform3D=hand*Transform3D(v.STAFF_GRIP_BASIS,v.STAFF_GRIP_OFFSET+v.STAFF_GRIP_BASIS.y*v.staff_slide)
				rows.append({"frame":frame,"weight":v._run_weight,"phase":v._run_time,"tip":[(staff*Vector3(0,.828,0)).x,(staff*Vector3(0,.828,0)).y,(staff*Vector3(0,.828,0)).z],"player_position":[arena.player.position.x,arena.player.position.y,arena.player.position.z],"paused":arena.paused,"yaw":v.rotation.y,"turn_lag":v._turn_lag})
			sequences.append({"id":id,"view":view,"version":version,"frames":rows.size(),"fps":60,"samples":rows})
	var report:Dictionary={"passed":true,"captures":captures,"sequences":sequences,"events":{"start":12,"stop":33,"short_restart":44,"short_stop":47,"restart":62,"pause":78,"resume":84},"scope":"Actual arena physics and movement inputs. Before uses only the exact former locomotion-mix method, with the same v3 staff and current game. Ordinary game lighting, two enlarged views and current native 1.75x framing."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RUN_ENTRY_REVIEW_COMPLETE captures=",captures)
	arena.free();quit(0)
