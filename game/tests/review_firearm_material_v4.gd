extends "res://tests/review_firearm_tree_v1.gd"
const MaterialDemo=preload("res://tests/helpers/firearm_material_v4_demo.gd")
const REST_IDS=["powder_barrel","gatling","smoke_launcher","artillery_shell","naval_shell","smoke_canister"]

func studio() -> void:
	root.size=Vector2i(1000,680)
	var world:=ReviewWorld.new();root.add_child(world)
	var env_node:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2831")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("c3d7dc");env.ambient_light_energy=.42
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env_node.environment=env;world.add_child(env_node)
	for data in [[Vector3(-40,-30,0),1.0,Color("ffe3bb")],[Vector3(-25,145,0),.45,Color("b6d9ef")]]:
		var light:=DirectionalLight3D.new();world.add_child(light)
		light.rotation_degrees=data[0];light.light_energy=data[1];light.light_color=data[2];light.shadow_enabled=true
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);floor.mesh=plane
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("26343f");mat.roughness=.85;floor.material_override=mat;world.add_child(floor)
	var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	for asset_id in REST_IDS:
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_material_v4/%s.json"%asset_id))
		var low:=Vector3(data.aabb_godot.min[0],data.aabb_godot.min[1],data.aabb_godot.min[2])
		var high:=Vector3(data.aabb_godot.max[0],data.aabb_godot.max[1],data.aabb_godot.max[2])
		var center:Vector3=(low+high)*.5;var span:float=maxf(maxf((high-low).x,(high-low).y),(high-low).z)
		floor.position.y=low.y-.025;place_camera(camera,center,span*1.15)
		var previous:Node3D=load("res://assets/weapons/firearm_tree_v1/%s.glb"%asset_id).instantiate()
		var current:Node3D=load("res://assets/weapons/firearm_material_v4/%s.glb"%asset_id).instantiate()
		world.add_child(previous);world.add_child(current);current.visible=false
		await capture("models/%s_before.jpg"%asset_id)
		previous.visible=false;current.visible=true
		await capture("models/%s.jpg"%asset_id)
		camera.position=center+Vector3(-2.5,1.9,3.2)*4;camera.look_at(center)
		await capture("models/%s_rear.jpg"%asset_id)
		previous.free();current.free()
		if asset_id in ["powder_barrel","gatling","smoke_launcher"]:
			var demo:=MaterialDemo.new();demo.configure(asset_id);world.add_child(demo);demo.initialize(world);demo.set_process(false)
			var count:=85 if asset_id=="powder_barrel" else 67
			var size:=span*1.45
			if asset_id=="powder_barrel":center=Vector3(.1,.26,-.45);size=1.7;floor.position.y=0
			if asset_id=="smoke_launcher":center+=Vector3(0,.12,-.13);size=1.3
			place_camera(camera,center,size)
			for frame in count:
				demo.sample_demo(frame/24.0);await capture("demo_%s/%03d.jpg"%[asset_id,frame])
			sequences.append({"id":"demo_"+asset_id,"asset":asset_id,"frames":count,"fps":24,"kind":"prepared_asset_demo"})
			demo.queue_free();await process_frame
	world.queue_free();await process_frame

func scale_reference() -> void:
	root.size=Vector2i(1280,800)
	var arena:Node3D=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	for enemy in arena.enemies.values():enemy.body.free()
	var screen_right:=Vector3(1,0,-1).normalized()
	var screen_near:=Vector3(1,0,1).normalized()
	arena.enemies.clear();arena.player.position=screen_right*-3.25;arena.muted=true;arena.help_visible=false
	arena._physics_process(0.0);arena.hud.visible=false;arena.hover_ring.visible=false;arena.move_marker.visible=false
	var positions:Array[Vector3]=[Vector3(-1.65,0,-1.4),Vector3(0,.8,-1.4),Vector3(1.65,0,-1.4),Vector3(-1.1,0,1.25),Vector3(0,0,1.25),Vector3(1.1,0,1.25)]
	for i in REST_IDS.size():
		var asset_id:String=REST_IDS[i]
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_material_v4/%s.json"%asset_id))
		var model:Node3D=load("res://assets/weapons/firearm_material_v4/%s.glb"%asset_id).instantiate();arena.add_child(model)
		var bounds_center:=Vector3((float(data.aabb_godot.min[0])+float(data.aabb_godot.max[0]))*.5,0,(float(data.aabb_godot.min[2])+float(data.aabb_godot.max[2]))*.5)
		model.position=screen_right*positions[i].x+screen_near*positions[i].z-bounds_center
		model.position.y=positions[i].y-float(data.aabb_godot.min[1])+.008
	arena.camera.rotation_degrees=Vector3(-30,45,0)
	arena.camera.size=20.0/1.75*arena.player_visual.MODEL_SCALE;arena.place_camera(Vector3.ZERO)
	await capture("scale_native.jpg")
	arena.camera.size=5.5;arena.place_camera(Vector3.ZERO)
	await capture("scale_close.jpg")
	arena.queue_free();await process_frame

func run() -> void:
	await studio();await scale_reference()
	var result:Dictionary={"passed":true,"captures":captures,"sequences":sequences,
		"scope":"Six prepared assets: same-camera material comparisons, rear views, original rigid demos and static game-camera size reference. No new active skills."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_MATERIAL_V4_REVIEW_COMPLETE captures=",captures)
	await process_frame;await process_frame;quit()
