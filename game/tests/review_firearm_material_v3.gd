extends "res://tests/review_firearm_tree_v1.gd"
## Same actual-arena capture path; new studio section compares v2/v3 at identical scale.
func studio() -> void:
	root.size=Vector2i(1000,640)
	var world:=Node3D.new();root.add_child(world)
	var node:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2831")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c3d7dc");env.ambient_light_energy=.42
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	node.environment=env;world.add_child(node)
	for data in [[Vector3(-40,-30,0),1.0,Color("ffe3bb")],[Vector3(-25,145,0),.45,Color("b6d9ef")]]:
		var light:=DirectionalLight3D.new();world.add_child(light)
		light.rotation_degrees=data[0];light.light_energy=data[1];light.light_color=data[2]
	# The profile camera sees the +X faces directly; give both versions the same fill.
	var profile_fill:=DirectionalLight3D.new();world.add_child(profile_fill)
	profile_fill.rotation_degrees=Vector3(0,90,0);profile_fill.light_energy=.65
	var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	for id in ["matchlock","rifle","shotgun"]:
		var old:Node3D=load("res://assets/weapons/firearm_tree_v2/%s.glb"%id).instantiate()
		var model:Node3D=load("res://assets/weapons/firearm_material_v3/%s.glb"%id).instantiate()
		world.add_child(old);world.add_child(model);old.position.y=.60
		# All comparisons use the same pixels/metre and align both muzzle tips at Z=0.
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.22
		var center:=Vector3(0,.245,.78)
		camera.position=center+Vector3.RIGHT*10.0;camera.look_at(center)
		await capture("compare_%s.jpg"%id)
		old.visible=false
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_material_v3/%s.json"%id))
		center=Vector3(0,-.025,float(data.dimensions[2])*.5)
		place_camera(camera,center,float(data.dimensions[2])*.80)
		await capture("model_%s.jpg"%id)
		old.free();model.free()
	world.queue_free();await process_frame

func run() -> void:
	await studio()
	await game()
	var result:Dictionary={"passed":true,"captures":captures,"checks":checks,"sequences":sequences,
		"note":"Three v2/v3 pairs at identical metre scale; actual arena assembly/shooting at native and enlarged camera. Same geometry and same lights; new shared baked PBR maps. Gameplay rules unchanged."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_MATERIAL_V3_REVIEW_COMPLETE captures=",captures)
	await process_frame
	await process_frame
	quit()
