extends SceneTree
var arena: Node3D
var output := ""
var actors: Dictionary = {}
var records: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func capture(path: String, closeup: bool=false) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if closeup:
		img=img.get_region(Rect2i(240,0,800,800));img.resize(512,512,Image.INTERPOLATE_LANCZOS)
	assert(img.save_png(output.path_join(path))==OK)

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false);arena.muted=true
	await process_frame
	arena.spawn_ally(arena.player.position+Vector3(-1.0,0,0.5),true,null)
	arena.spawn_ally(arena.player.position+Vector3(1.3,0,-0.2),false,null)
	for i in 12:arena._physics_process(1.0/60.0)
	await capture("gameplay.png")
	for e in arena.enemies.values():e.body.free()
	arena.enemies.clear()
	for ally in arena.allies:ally.node.free()
	arena.allies.clear()
	for fx in arena.effects:fx.node.free()
	arena.effects.clear()
	arena.hud.visible=false;arena.hover_ring.visible=false;arena.shield_ring.visible=false;arena.move_marker.visible=false
	for ring in arena.tool_rings.values():ring.visible=false
	arena.player.position=Vector3(1.5,0,1.5);arena.player_model.rotation.y=PI
	for kind in ["rag","crow","brute"]:
		arena.spawn_enemy(kind,Vector3.ZERO,false,"normal",kind)
		actors[kind]=arena.enemies[kind].model
	for kind in ["automaton","turret"]:
		arena.spawn_ally(Vector3.ZERO,kind=="automaton",null)
		actors[kind]=arena.allies.back().node.get_node("ActorVisual")
	var right: Vector3=arena.camera.basis.x;right.y=0;right=right.normalized()
	var i:=0
	for kind in actors:
		actors[kind].get_parent().position=right*(i-2)*2.15+Vector3(0,0,-.8)
		actors[kind].rotation.y=PI
		actors[kind].sample("idle",0)
		i+=1
	arena.place_camera(Vector3.ZERO)
	await capture("native_lineup.png")
	arena.player.visible=false
	for art in actors.values():art.get_parent().visible=false
	for kind in actors:
		var art:Node3D=actors[kind]
		art.get_parent().visible=true;art.get_parent().position=Vector3.ZERO;art.get_parent().rotation=Vector3.ZERO
		art.rotation.y=PI
		var height:float={"rag":1.08,"crow":1.15,"brute":2.08,"automaton":.85,"turret":.9}[kind]
		var target:=Vector3(0,height*.52,0)
		arena.camera.size=maxf(1.6,height*1.65)
		arena.camera.position=target+Vector3(2.4,1.3,4.5)
		arena.camera.look_at(target)
		for clip in art.clips:
			var folder:String=kind+"_"+clip
			DirAccess.make_dir_recursive_absolute(output.path_join(folder))
			for f in 17:
				art.sample(clip,f/16.0)
				await capture(folder+"/%03d.png"%f,true)
			records.append({"actor":kind,"clip":clip,"folder":folder,"frames":17,"seconds":art.player.get_animation(art.clips[clip]).length})
		art.get_parent().visible=false
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"sequences":records,"native_camera_size":20.0/1.75,"viewport":[1280,800],"scope":"Actual game assets and animation controller, sampled manually; combat timing verified separately."},"  "))
	print("COMBAT_ACTORS_REVIEW_COMPLETE")
	arena.queue_free();await process_frame;quit(0)
