extends SceneTree
## Actual PlayerVisual/controller, isolated from map/enemy/HUD assets to keep RAM low.
const Player = preload("res://scripts/player_visual.gd")
var output := ""
var visual: Node3D
var camera: Camera3D
var scene: Node3D
var captures := 0
var failures: Array = []
var checks := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)

func run() -> void:
	ProjectSettings.set_setting("debug/entry_polish_v27", true)
	root.size=Vector2i(1280,800)
	scene=Node3D.new();root.add_child(scene)
	var world:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("101d25")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("b9d0d3")
	env.ambient_light_energy=.45;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	world.environment=env;scene.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-30,0)
	sun.light_color=Color("ffddb0");sun.light_energy=.85;sun.shadow_enabled=true;scene.add_child(sun)
	var floor:=MeshInstance3D.new();floor.mesh=PlaneMesh.new();floor.mesh.size=Vector2(15,15)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("26343b");mat.roughness=1.0
	floor.material_override=mat;scene.add_child(floor)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.add_child(camera);camera.current=true
	visual=Player.new();scene.add_child(visual);check(visual.initialize(),"player initialization")
	if not visual.loaded_ok:finish();return
	var sequences:Array=[]
	for view in ["front","back","native","hair"]:
		visual.rotation=Vector3.ZERO
		if view=="native":visual.look_at(Vector3(7,0,7))
		visual.begin_field_entry()
		DirAccess.make_dir_recursive_absolute(output.path_join(view))
		var samples:Array=[]
		for f in 94:
			if f>0:
				for step in 2:visual.sync_state(1.0/60.0,false,0.0,false,false,false,0.0)
			var focus:=Vector3(0,.82,0)
			camera.size=2.35
			camera.position=focus+(Vector3(3,1,7) if view=="back" else Vector3(-3,1,-7))
			if view=="hair":
				focus=Vector3(0,1.25,0);camera.size=1.0;camera.position=focus+Vector3(4,1,7)
			if view=="native":
				camera.size=20.0/1.75*Player.MODEL_SCALE
				camera.rotation_degrees=Vector3(-30,45,0)
				camera.position=focus+camera.basis.z*30
			else:camera.look_at(focus)
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_jpg(output.path_join(view+"/%03d.jpg"%f),.92)==OK,"capture %s/%d"%[view,f])
			captures+=1;samples.append(visual.debug_snapshot())
		check(visual.form=="transformed" and not visual.field_entry_active(),"three second endpoint "+view)
		check(visual._entry._reveal.previews.is_empty(),"reveal cleanup "+view)
		sequences.append({"id":view,"frames":94,"fps":30,"samples":samples})
	# Exercise cancellation on both sides of the unchanged logical swap.
	for seconds in [2.20,2.50]:
		visual.begin_field_entry()
		for i in int(seconds*60):visual.sync_state(1.0/60,false,0,false,false,false,0)
		var progress:float=visual._entry._reveal.progress
		var pose:Transform3D=visual._hair_motion._rig.get_bone_global_pose(7)
		for i in 12:visual.sync_state(1.0/60,false,0,true,false,false,0)
		check(visual._entry._reveal.progress==progress,"pause reveal %.2f"%seconds)
		check(visual._hair_motion._rig.get_bone_global_pose(7).is_equal_approx(pose),"pause hair %.2f"%seconds)
		visual._entry.cancel()
		check(visual._entry._reveal.previews.is_empty(),"cancel removes previews %.2f"%seconds)
		for mesh in visual.runtime.slots.outfit.find_children("*","MeshInstance3D",true,false):check(mesh.visible,"cancel restores clothing")
	check(visual.runtime.skeleton.get_bone_count()==107,"shared body rest remains 107 bones")
	check(visual._hair_motion._rig.get_bone_count()==8,"six hair segments and two anchors")
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"sequences":sequences,"scope":"Isolated actual PlayerVisual and FieldEntry controllers, existing game base lighting, plain ground. Map/enemies/HUD are excluded due to system memory pressure."},"  "))
	finish()

func finish() -> void:
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("LIGHT_REVIEW_DONE ",JSON.stringify(result));scene.free();quit(0 if failures.is_empty() else 1)
