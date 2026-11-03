extends SceneTree
const Demo=preload("res://tests/helpers/firearm_tree_demo.gd")
const ReviewWorld=preload("res://tests/helpers/firearm_review_world.gd")
const IDS=["matchlock","rifle","shotgun","powder_barrel","gatling","smoke_launcher","artillery_shell","naval_shell","smoke_canister"]
var output := ""
var captures := 0
var sequences: Array = []
var checks: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func capture(relative: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(root.get_texture().get_image().save_jpg(path,.92)==OK)
	captures+=1

func place_camera(camera: Camera3D, center: Vector3, distance: float, side: bool=false) -> void:
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=distance
	camera.position=center+Vector3(3.0,1.0,.5) * 4.0 if side else center+Vector3(2.5,1.9,-3.2)*4.0
	camera.look_at(center)

func studio() -> void:
	root.size=Vector2i(960,600)
	var world:=ReviewWorld.new(); root.add_child(world)
	var env_node:=WorldEnvironment.new(); var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR; env.background_color=Color("19232d")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c3d7dc"); env.ambient_light_energy=.42
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env_node.environment=env; world.add_child(env_node)
	for data in [[Vector3(-40,-30,0),1.0,Color("ffe3bb")],[Vector3(-25,145,0),.45,Color("b6d9ef")]]:
		var light:=DirectionalLight3D.new(); world.add_child(light)
		light.rotation_degrees=data[0]; light.light_energy=data[1]; light.light_color=data[2]
		light.shadow_enabled=true
	var floor:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(20,20)
	floor.mesh=plane; var mat:=StandardMaterial3D.new();mat.albedo_color=Color("26343f");mat.roughness=.85
	floor.material_override=mat;world.add_child(floor)
	var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	for id in IDS:
		var demo:=Demo.new();demo.configure(id);world.add_child(demo);demo.initialize(world);demo.set_process(false)
		var low:=demo.point(demo.manifest.aabb_godot.min)
		var high:=demo.point(demo.manifest.aabb_godot.max)
		var center:Vector3=(low+high)*.5
		var span:float=maxf(maxf((high-low).x,(high-low).y),(high-low).z)
		floor.position.y=low.y-.025
		demo.sample_demo(.80)
		place_camera(camera,center,span*1.10)
		await capture("models/%s.jpg"%id)
		place_camera(camera,center,span*1.02,true)
		await capture("models/%s_side.jpg"%id)
		if id in ["matchlock","rifle","shotgun","powder_barrel","gatling","smoke_launcher"]:
			var count:=85 if id=="powder_barrel" else 67
			var size:float=span*1.45
			if id=="powder_barrel": center=Vector3(.10,.26,-.45);size=1.7;floor.position.y=0
			if id=="smoke_launcher": center+=Vector3(0,.12,-.13);size=1.3
			place_camera(camera,center,size)
			for frame in count:
				demo.sample_demo(frame/24.0)
				await capture("demo_%s/%03d.jpg"%[id,frame])
			sequences.append({"id":"demo_"+id,"kind":"asset_demo","frames":count,"fps":24,"asset":id})
		demo.queue_free();await process_frame
	world.queue_free();await process_frame

func game() -> void:
	root.size=Vector2i(1280,800)
	var arena:Node3D=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	var warmup=load("res://scripts/asset_warmup.gd").new()
	arena.add_child(warmup)
	await warmup.run(arena.camera)
	assert(warmup.done)
	checks.append("GPU startup warmup includes dedicated matchlock and rifle")
	warmup.queue_free()
	arena.build.set_level(5)
	for id in ["matchlock","rifle","shotgun"]:
		for close in [false,true]:
			arena.reset_arena()
			for enemy in arena.enemies.values(): enemy.body.free()
			arena.enemies.clear()
			arena.player.position=Vector3.ZERO;arena.config.enemy_speed=0.0;arena.config.mana_regen=0.0
			arena.muted=true;arena.help_visible=false;arena.force_rolls={"hit":true,"crit":false}
			arena.spawn_enemy("target",Vector3(4,0,0),false,"normal","rag")
			arena.enemies.target.hp=9999.0;arena.enemies.target.max_hp=9999.0;arena.enemies.target.cooldown=999.0
			arena._physics_process(0.0)
			arena.hover_ring.visible=false;arena.move_marker.visible=false
			if id!="shotgun": arena.bind_slot("q",id)
			arena.request_slot("rmb" if id=="shotgun" else "q",{"enemy_id":"target"})
			var assembly:Node3D=arena.shotgun_assembly if id=="shotgun" else arena.gun_assembly
			assert(is_instance_valid(assembly));assembly.set_process(false)
			var sequence_id: String="game_%s_%s"%[id,"close" if close else "native"]
			var release:float=arena.windup.release
			for frame in 49:
				if frame>0:
					await physics_frame
					arena._physics_process(1.0/30.0)
					if is_instance_valid(assembly):assembly.advance(1.0/30.0)
				if frame==28 and id!="shotgun": arena.request_slot("lmb",{"enemy_id":"target"})
				arena.hud.visible=not close
				arena.hover_ring.visible=false;arena.move_marker.visible=false
				if close:
					arena.camera.rotation_degrees=Vector3(-20,130,0);arena.camera.size=3.4
					arena.camera.position=Vector3(.5,.85,.15)+arena.camera.basis.z*30
				else:
					arena.camera.rotation_degrees=Vector3(-30,45,0)
					arena.camera.size=20.0/1.75*arena.player_visual.MODEL_SCALE
					arena.place_camera(arena.player.position)
				await capture("%s/%03d.jpg"%[sequence_id,frame])
			if id!="shotgun":
				assert(arena.gun.id==id and arena.gun.visual.parts_scene.resource_path.ends_with("/%s.glb"%id))
				checks.append(id+" actual arena selected model")
			else:
				assert(not arena.last_shotgun.is_empty())
				checks.append("actual shotgun release retained")
			sequences.append({"id":sequence_id,"kind":"actual_game","asset":id,"frames":49,"fps":30,"release_seconds":release,"native":not close})
	arena.build.set_level(1);arena.queue_free();await process_frame

func run() -> void:
	await studio()
	await game()
	var result:Dictionary={"passed":true,"captures":captures,"checks":checks,"sequences":sequences,
		"note":"Future skill animations are isolated art previews, not gameplay implementations. Game sequences use actual current release clocks."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIREARM_REVIEW_COMPLETE captures=",captures)
	await process_frame
	await process_frame
	quit()
