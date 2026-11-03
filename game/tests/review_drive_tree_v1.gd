extends "res://tests/review_firearm_tree_v1.gd"
const DriveDemo=preload("res://tests/helpers/drive_tree_demo.gd")
const Player=preload("res://scripts/player_visual.gd")
const DRIVE_IDS=["guillotine","guillotine_saw","guillotine_lock","restraint_winch","hydraulic_press","compound_executor","broad_cutter"]
var pose_records: Array = []

func world_scene() -> Node3D:
	var world:=ReviewWorld.new();root.add_child(world)
	var env_node:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("15222c")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("b9d0d3");env.ambient_light_energy=.45
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env_node.environment=env;world.add_child(env_node)
	for data in [[Vector3(-40,-30,0),.85,Color("ffe3bb")],[Vector3(-25,145,0),.2,Color("b6d9ef")]]:
		var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=data[0];light.light_energy=data[1];light.light_color=data[2];light.shadow_enabled=true
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30);floor.mesh=plane
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("233743");mat.roughness=.86;floor.material_override=mat;world.add_child(floor)
	return world

func mechanisms() -> void:
	root.size=Vector2i(960,680)
	var world:=world_scene();var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	var reference:=Player.new();world.add_child(reference);assert(reference.initialize());reference.set_process(false);reference._sample("idle",.5);reference.hide()
	for id in DRIVE_IDS:
		var demo:=DriveDemo.new();demo.configure(id);world.add_child(demo);demo.initialize(world);demo.set_process(false)
		var low:=demo.point(demo.manifest.aabb_godot.min);var high:=demo.point(demo.manifest.aabb_godot.max)
		var center:Vector3=(low+high)*.5;var span:float=maxf(maxf((high-low).x,(high-low).y),(high-low).z)
		if id=="restraint_winch":center.z-=.5;span=2.1
		demo.sample_demo(.67)
		place_camera(camera,center,span*1.16);await capture("models/%s.jpg"%id)
		camera.position=center+Vector3(-3,1.7,3)*4;camera.look_at(center);await capture("models/%s_rear.jpg"%id)
		if id!="broad_cutter":
			root.size=Vector2i(1280,800);reference.show();reference.position=Vector3((high-low).x*.5+.65,0,0)
			camera.rotation_degrees=Vector3(-30,45,0);camera.size=20.0/1.75*reference.MODEL_SCALE
			camera.position=Vector3(.5,.55,0)+camera.basis.z*30
			await capture("models/%s_native.jpg"%id)
			reference.hide();root.size=Vector2i(960,680)
		place_camera(camera,center,span*1.27)
		var modes:Array=["single","pull","bind"] if id=="restraint_winch" else ["base"]
		for variant in modes:
			demo.winch_mode=variant
			var seq:String="demo_%s_%s"%[id,variant]
			for frame in 82:
				demo.sample_demo(frame/24.0);await capture("%s/%03d.jpg"%[seq,frame])
			sequences.append({"id":seq,"asset":id,"variant":variant,"frames":82,"fps":24})
		demo.queue_free();await process_frame
	world.queue_free();await process_frame

func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]

func equipment() -> void:
	root.size=Vector2i(960,760)
	var world:=world_scene();var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	var player:=Player.new();world.add_child(player);assert(player.initialize());player.set_process(false);player.motion_duration=1
	var sk:Skeleton3D=player.runtime.skeleton
	for asset in ["shock_frame","exoskeleton"]:
		var demo:=DriveDemo.new();demo.configure(asset);world.add_child(demo);demo.initialize(world);demo.set_process(false)
		demo.reparent(sk,false);demo.skeleton=sk
		for form in ["civilian","transformed"]:
			assert(player.set_form(form))
			player._sample("idle",.5);place_camera(camera,Vector3(0,.76,0),1.9)
			var assembly_seq:String="%s_%s_assembly"%[asset,form]
			for frame in 82:
				demo.sample_demo(frame/24.0);await capture("%s/%03d.jpg"%[assembly_seq,frame])
			sequences.append({"id":assembly_seq,"asset":asset,"form":form,"motion":"assembly","frames":82,"fps":24})
			for motion in ["idle","run","attack","attack_thrust","cast","hit_react","spring_jump","collapse"]:
				player._attack_clip_kind="attack_thrust" if motion=="attack_thrust" else "attack"
				var kind:String="attack" if motion=="attack_thrust" else motion
				var seq:String="%s_%s_%s"%[asset,form,motion]
				for frame in 13:
					var phase:=float(frame)/12.0
					player._sample(kind,player._length(kind)*phase);demo.sample_demo(1.0)
					place_camera(camera,Vector3(0,.76,0),1.9)
					await capture("%s/%03d.jpg"%[seq,frame])
					if asset=="exoskeleton":
						var record:Dictionary={"form":form,"motion":motion,"phase":phase,"bones":{}}
						for i in sk.get_bone_count():record.bones[sk.get_bone_name(i)]=matrix(sk.get_bone_global_pose(i))
						pose_records.append(record)
				sequences.append({"id":seq,"asset":asset,"form":form,"motion":motion,"frames":13,"fps":12})
			player._sample("idle",.5);demo.sample_demo(1)
			for rear in [false,true]:
				camera.size=1.9;camera.position=Vector3(-2.2,1.4,3 if rear else -3)*3;camera.look_at(Vector3(0,.76,0))
				await capture("models/%s_%s%s.jpg"%[asset,form,"_rear" if rear else ""])
			root.size=Vector2i(1280,800)
			camera.rotation_degrees=Vector3(-30,45,0);camera.size=20.0/1.75*player.MODEL_SCALE;camera.position=Vector3(0,.4,0)+camera.basis.z*30
			await capture("models/%s_%s_native.jpg"%[asset,form])
			root.size=Vector2i(960,760)
		demo.queue_free();await process_frame
	# A single common shaft shows the large replacement head at the retained mount.
	assert(player.set_form("transformed"));player._sample("idle",.5)
	var cutter:=DriveDemo.new();cutter.configure("broad_cutter");world.add_child(cutter);cutter.initialize(world);cutter.set_process(false);cutter.reparent(player.staff_root,false);cutter.sample_demo(.8)
	place_camera(camera,Vector3(0,.8,0),2.4);await capture("models/broad_cutter_equipped.jpg")
	place_camera(camera,Vector3(0,.8,0),2.4,true);await capture("models/broad_cutter_equipped_side.jpg")
	world.queue_free();await process_frame

func run() -> void:
	if not "--equipment-only" in OS.get_cmdline_user_args():await mechanisms()
	await equipment()
	FileAccess.open(output.path_join("poses.json"),FileAccess.WRITE).store_string(JSON.stringify(pose_records))
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"captures":captures,"sequences":sequences,"equipment_pose_samples":pose_records.size(),"scope":"Prepared-asset motions and actual character clips; no new active skills."},"  "))
	print("DRIVE_REVIEW_COMPLETE ",captures," captures ",pose_records.size()," poses")
	quit()
