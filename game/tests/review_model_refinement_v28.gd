extends "res://tests/review_staff_visual.gd"

var originals: Dictionary = {}
var previous: Dictionary = {}
var current: Dictionary = {}

func replace_review_meshes(which: Dictionary) -> void:
	for name in which:
		var mesh: MeshInstance3D = current[name]
		mesh.mesh=which[name][0];mesh.skin=which[name][1]

func detail_camera(part: String, view: String) -> void:
	var focus:Vector3=arena.player.position+Vector3(0,{"face":1.32,"hands":1.02,"shoes":.16,"full":.78}.get(part,.78),0)
	if part=="hands":
		var sk:Skeleton3D=arena.player_visual.runtime.skeleton
		var r:Vector3=(sk.global_transform*sk.get_bone_global_pose(sk.find_bone("DEF-hand.R"))).origin
		var l:Vector3=(sk.global_transform*sk.get_bone_global_pose(sk.find_bone("DEF-hand.L"))).origin
		focus=(r+l)*.5
	arena.camera.size={"face":.48,"hands":.62,"shoes":.57,"full":2.1}.get(part,2.1)
	var offset:Vector3={"front":Vector3(8,.1,0),"back":Vector3(-8,1,0),"side":Vector3(0,1,-8),"three_quarter":Vector3(8,2,-4)}[view]
	arena.camera.position=focus+offset;arena.camera.look_at(focus)
	arena.hud.visible=false;arena.hover_ring.visible=false;arena.move_marker.visible=false

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();arena.field_entry_mode=2;root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat");prepare();arena.player_model.look_at(arena.player.position+Vector3.RIGHT)
	var v=arena.player_visual
	assert(v.loaded_ok,v.last_error)
	for mesh:MeshInstance3D in v.runtime.find_children("*","MeshInstance3D",true,false):
		if mesh.name in ["Body_Hands_v7","Face_Core_v8","Eyes_Iris_v8","Outfit_Shoes_v7","Outfit_Socks_v7"]:
			current[String(mesh.name)]=mesh;originals[String(mesh.name)]=[mesh.mesh,mesh.skin]
	for file in ["body_standard_v21.glb","eyes_neutral_v21.glb","outfit_civilian_v21.glb"]:
		var old:Node=load(v.ASSET_DIR+file).instantiate()
		for mesh:MeshInstance3D in old.find_children("*","MeshInstance3D",true,false):
			if current.has(String(mesh.name)):previous[String(mesh.name)]=[mesh.mesh,mesh.skin]
		old.free()
	assert(previous.size()==5 and current.size()==5)
	for part in ["face","hands","shoes","full"]:
		for view in ["front","three_quarter","side"]:
			for version in ["before","after"]:
				replace_review_meshes(previous if version=="before" else originals)
				v._sample("idle",0.0);detail_camera(part,view)
				var id:String=part+"_"+view+"_"+version
				await capture(id+".jpg")
	replace_review_meshes(originals)
	# Open hand and staff grip progression, sampled from the real entry clip.
	for pose in [0.0,.85,1.4,2.1]:
		for version in ["before","after"]:
			replace_review_meshes(previous if version=="before" else originals)
			v.staff_root.visible=pose>=1.4;v._sample("entry",pose);detail_camera("hands","three_quarter")
			await capture("grip_%s_%s.jpg"%[str(pose).replace(".","_"),version])
	replace_review_meshes(originals);v.staff_root.visible=true
	for form in ["civilian","transformed"]:
		assert(v.set_form(form))
		for kind in ["idle","run","attack","cast","hit_react","spring_jump"]:
			var id:String=form+"_"+kind;DirAccess.make_dir_recursive_absolute(output.path_join(id))
			var length:float=v._length(kind);v.motion_duration=maxf(length,.1)
			for frame in 25:
				v._sample(kind,length*frame/24.0)
				detail_camera("full","three_quarter")
				await capture(id+"/%03d.jpg"%frame)
			sequences.append({"id":id,"frames":25,"fps":25.0/length,"form":form,"action":kind})
		v._sample("idle",0);frame_camera(true);await capture(form+"_native.jpg")
	var report:Dictionary={"passed":true,"captures":captures,"sequences":sequences,"scope":"Actual imported meshes and PlayerVisual animation sampling in the arena lighting. Before/after replaces only five mesh+skin resources on the identical skeleton, pose and camera. Motion clips are sampled evenly including endpoints, not gameplay timing. Native shots use selected 1.75x camera."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MODEL_V28_REVIEW ",captures)
	arena.free();quit(0)
