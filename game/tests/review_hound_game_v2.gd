extends SceneTree
## Isolated prepared-asset viewer / checks. No arena skill integration.
const HOUND := "res://assets/actors/automation_batch2/hound_v2/hound_v2.glb"
const PlayerVisual = preload("res://scripts/player_visual.gd")
const Actors = preload("res://scripts/actor_visual.gd")
var output := ""
var checks := 0
var failures: Array[String] = []
var captures := 0
var model: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var geometry: Array = []
var metrics: Dictionary = {}
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="): output = a.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok and not failures.has(what): failures.append(what); push_error(what)

func sample(clip: String, seconds: float) -> void:
	animator.play(clip); animator.seek(seconds, true); animator.advance(0)
	skeleton.force_update_all_bone_transforms()

func bone_world(i: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(i)

func make_world() -> void:
	world = Node3D.new(); root.add_child(world)
	var we := WorldEnvironment.new(); var env := Environment.new(); we.environment = env; world.add_child(we)
	env.background_mode = Environment.BG_COLOR; env.background_color = Color("18252e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("cad8dc"); env.ambient_light_energy = .4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color=Color("506171");sm.sky_horizon_color=Color("b4bec5");sm.ground_horizon_color=Color("969d9c");sm.ground_bottom_color=Color("34414a")
	sm.sky_energy_multiplier=.6;sm.ground_energy_multiplier=.45;sky.sky_material=sm;env.sky=sky;env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	for entry in [[Vector3(-40,-30,0),.8,Color("ffe5bf")],[Vector3(-28,145,0),.25,Color("c2e2f4")]]:
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees=entry[0]; light.light_energy=entry[1];light.light_color=entry[2];light.shadow_enabled=true
	var floor_node := MeshInstance3D.new(); var plane := PlaneMesh.new();plane.size=Vector2(40,40);floor_node.mesh=plane
	var mat := StandardMaterial3D.new();mat.albedo_color=Color("2b3a43");mat.roughness=.9;floor_node.material_override=mat;world.add_child(floor_node)
	camera=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.make_current()

func place(view: String="front") -> void:
	var center := Vector3(0,.34,0)
	camera.size=1.55
	var offsets := {"front":Vector3(-2.2,1.2,-3),"rear":Vector3(2.2,1.2,3),"side":Vector3(-3,.20,0),"top":Vector3(.01,4,.01)}
	camera.position=center+offsets[view];camera.look_at(center)

func capture(file: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var path := output.path_join(file);DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(root.get_texture().get_image().save_jpg(path,.92)==OK,"capture writes "+file);captures+=1

func inspect_geometry() -> void:
	var triangle_count := 0;var surfaces := 0;var wrong_weights := 0;var wrong_faces := 0
	for mi in model.find_children("*","MeshInstance3D",true,false):
		check(mi.skin!=null,"skin exists")
		for si in mi.mesh.get_surface_count():
			surfaces+=1
			var a: Array=mi.mesh.surface_get_arrays(si);var vertices: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=a[Mesh.ARRAY_INDEX];var bones: PackedInt32Array=a[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=a[Mesh.ARRAY_WEIGHTS]
			triangle_count+=indices.size()/3;var influences:int=bones.size()/vertices.size();var owners: Array[int]=[]
			for vi in vertices.size():
				var owner:=-1;var count:=0;var total:=0.0
				for j in influences:
					var w:float=weights[vi*influences+j]
					if w>.000001:owner=bones[vi*influences+j];count+=1;total+=w
				if count!=1 or absf(total-1.)>.000001:wrong_weights+=1
				owners.append(owner)
				var name:String=mi.skin.get_bind_name(owner);var bone:=skeleton.find_bone(name)
				if bone<0:bone=mi.skin.get_bind_bone(owner)
				geometry.append({"bone":bone,"local":mi.skin.get_bind_pose(owner)*vertices[vi],"name":skeleton.get_bone_name(bone)})
			for i in range(0,indices.size(),3):
				if owners[indices[i]]!=owners[indices[i+1]] or owners[indices[i]]!=owners[indices[i+2]]:wrong_faces+=1
	check(wrong_weights==0,"100 percent single-bone vertices");check(wrong_faces==0,"triangles never span rigid parts")
	check(triangle_count>=5000 and triangle_count<=7000,"triangle budget 5-7k");check(surfaces==2,"separate surface and glow materials")
	metrics.merge({"triangles":triangle_count,"surfaces":surfaces,"exported_vertices":geometry.size(),"bones":skeleton.get_bone_count()})

func validate() -> void:
	inspect_geometry()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/automation_batch2/hound_v2/parts.json"))
	for socket in ["Socket_attack","Socket_core","Socket_bar"]:check(skeleton.find_bone(socket)>=0,"socket "+socket)
	var loops := {};var floors := {};var poses: Array=[]
	for clip in manifest.clips:
		check(animator.has_animation(clip),"clip exists "+clip)
		var animation:=animator.get_animation(clip)
		check(absf(animation.length-float(manifest.clips[clip].seconds))<.00001,"exact duration "+clip)
		animation.loop_mode=Animation.LOOP_NONE
		check(animation.has_meta("exact_source_sample_times"),"exact event/contact import "+clip)
		for track in animation.get_track_count():
			check(animation.track_get_key_count(track)==manifest.clips[clip].times.size(),"all authored keys preserved "+clip)
		check(animation.get_track_count()==skeleton.get_bone_count()*3,"constant TRS tracks preserved "+clip)
		var first:Array[Transform3D]=[];var min_floor:=INF;var foot_floor:=INF;var worst:={}
		var sample_steps:int=ceili(animation.length*240.0)
		for frame in sample_steps+1:
			var t:=animation.length*frame/sample_steps;sample(clip,t)
			for i in skeleton.get_bone_count():
				var p:=bone_world(i);var gram:=p.basis.transposed()*p.basis
				check(p.origin.is_finite() and absf(p.basis.determinant()-1)<.0001 and gram.is_equal_approx(Basis.IDENTITY),"rigid transforms "+clip)
				if frame==0:first.append(p)
				if frame==sample_steps and bool(manifest.clips[clip].loop):check(first[i].is_equal_approx(p),"matching loop endpoints "+clip)
			for v in geometry:
				var p:Vector3=bone_world(v.bone)*v.local
				if p.y<min_floor:worst={"time":t,"bone":v.name,"point":str(p),"bone_origin":str(bone_world(v.bone).origin)}
				min_floor=minf(min_floor,p.y)
				if "_paw." in v.name:foot_floor=minf(foot_floor,p.y)
		floors[clip]={"minimum_y":min_floor,"paw_minimum_y":foot_floor,"worst":worst}
		check(min_floor>-.001,"sampled floor clearance "+clip)
		for t in manifest.clips[clip].times:
			sample(clip,float(t));var bones:={}
			for i in skeleton.get_bone_count():
				var tr:=bone_world(i);bones[skeleton.get_bone_name(i)]=[tr.origin.x,tr.origin.y,tr.origin.z]
			poses.append({"clip":clip,"time":t,"bones":bones})
	metrics["floors"]=floors
	sample("idle",0)
	check(bone_world(skeleton.find_bone("Socket_attack")).origin.z<bone_world(skeleton.find_bone("chest")).origin.z,"attack socket points toward -Z")
	FileAccess.open(output.path_join("runtime_poses.json"),FileAccess.WRITE).store_string(JSON.stringify(poses))

func native_lineup() -> void:
	root.size=Vector2i(1280,800)
	var player:=PlayerVisual.new();world.add_child(player);check(player.initialize(),"current player loads");player.set_process(false);player._sample("idle",.5);player.position=Vector3(-3.6,0,0)
	model.position=Vector3(-2.1,0,0);sample("idle",.3)
	var holders:Array[Node3D]=[]
	for data in [["automaton",-.6],["turret",.85],["rag",2.3],["crow",3.7],["brute",5.0]]:
		var holder:=Node3D.new();world.add_child(holder);holder.position=Vector3(data[1],0,0)
		var visual:Node3D=Actors.create(holder,data[0]);check(visual!=null and visual.loaded_ok,"native comparison "+data[0]);visual.sample("idle",.2);holders.append(holder)
	camera.rotation_degrees=Vector3(-30,45,0);camera.size=20.0/1.75*player.MODEL_SCALE;camera.position=Vector3(.2,.4,0)+camera.basis.z*30
	await capture("native_lineup.jpg")
	metrics["native_camera"]={"size":camera.size,"pitch":-30,"yaw":45,"resolution":[1280,800],"shared_studio_lighting":true}
	for holder in holders:holder.free()
	model.position=Vector3(.65,0,0);player.position=Vector3(-.75,0,0)
	camera.position=Vector3(0,.4,0)+camera.basis.z*30
	for frame in 48:
		sample("run",fmod(frame/24.0,.5));await capture("native_run/%03d.jpg"%frame)
	player.free();model.position=Vector3.ZERO

func pack_preview() -> void:
	root.size=Vector2i(1000,760);model.hide();var copies:Array[Node3D]=[]
	var shared:Mesh=model.find_children("*","MeshInstance3D",true,false)[0].mesh
	for i in 3:
		var copy:Node3D=load(HOUND).instantiate();world.add_child(copy);copies.append(copy)
		copy.scale=Vector3.ONE*.8;copy.position=Vector3((i-1)*.7,0,-.25 if i==1 else .25)
		var ap:AnimationPlayer=copy.find_children("*","AnimationPlayer",true,false)[0]
		ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;ap.play("idle");ap.seek(i*.2,true);ap.advance(0)
		check(copy.find_children("*","MeshInstance3D",true,false)[0].mesh==shared,"pack reuses unchanged base mesh")
	place("front");camera.size=2.7;await capture("pack.jpg")
	for copy in copies:copy.free()
	model.show()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	make_world();model=load(HOUND).instantiate();world.add_child(model)
	skeleton=model.find_children("*","Skeleton3D",true,false)[0];animator=model.find_children("*","AnimationPlayer",true,false)[0]
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	validate()
	if not "--checks-only" in OS.get_cmdline_user_args():
		root.size=Vector2i(1000,760)
		for view in ["front","rear","side","top"]:
			place(view);sample("idle",0);await capture(view+".jpg")
		for clip in ["spawn","idle","run","bite","hit","death"]:
			place("front")
			if clip=="death":camera.size=1.8
			var duration:=animator.get_animation(clip).length
			var count:=maxi(25,int(ceil(duration*24))+13)
			if clip in ["idle","run"]:count=48
			for frame in count:
				var t:=fmod(frame/24.0,duration) if clip in ["idle","run"] else clampf((frame-5)/24.0,0,duration)
				sample(clip,t);await capture("motion_%s/%03d.jpg"%[clip,frame])
			place("side")
			for frame in 7:
				sample(clip,duration*frame/6.0);await capture("poses_%s/%02d.jpg"%[clip,frame])
		await native_lineup()
		await pack_preview()
	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"metrics":metrics,"scope":"prepared art and playback; no gameplay integration"}
	FileAccess.open(output.path_join("runtime_validation.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("HOUND_V2_REVIEW ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
