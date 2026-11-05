extends SceneTree
## Isolated prepared-asset viewer / checks. No arena skill integration.
var actor := "beacon"
var asset_version := 1
var ASSET := ""
var manifest: Dictionary = {}
var rest_clip := "pulse"
var art_height := 1.5
const Presentation = preload("res://tests/helpers/automation_batch2_visual.gd")
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
var reference: Node3D
var reference_animator: AnimationPlayer
var reference_skeleton: Skeleton3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--actor="): actor = a.trim_prefix("--actor=")
		if a.begins_with("--version="): asset_version = int(a.trim_prefix("--version="))
		if a.begins_with("--output="): output = a.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok and not failures.has(what): failures.append(what); push_error(what)

func sample(clip: String, seconds: float) -> void:
	animator.play(clip); animator.seek(seconds, true); animator.advance(0)
	skeleton.force_update_all_bone_transforms()
	Presentation.sample(model, actor, clip, seconds)
	if reference != null:
		reference_animator.play(clip); reference_animator.seek(seconds, true); reference_animator.advance(0)
		reference_skeleton.force_update_all_bone_transforms()
		Presentation.sample(reference, actor.trim_suffix("_armour"), clip, seconds)

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
	var center := Vector3(0,art_height*.46,0)
	camera.size=art_height*1.55
	var offsets := {"front":Vector3(-2.2,1.2,-3),"rear":Vector3(2.2,1.2,3),"side":Vector3(-3,.20,0),"top":Vector3(.01,4,.01)}
	camera.position=center+offsets[view]*art_height;camera.look_at(center)

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
	if actor.ends_with("_armour"):
		check(triangle_count>0 and triangle_count<=2000,"supplemental armour triangle budget"); check(surfaces==1,"one armour material")
	else:
		check(triangle_count>=(5000 if actor=="hound" else 3000 if actor=="beacon" else 12000) and triangle_count<=(7000 if actor=="hound" else 4500 if actor=="beacon" else 16000),"actor triangle budget");check(surfaces==2,"separate surface and glow materials")
	metrics.merge({"triangles":triangle_count,"surfaces":surfaces,"exported_vertices":geometry.size(),"bones":skeleton.get_bone_count()})

func validate() -> void:
	inspect_geometry()
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/automation_batch2/%s_v%d/parts.json"%[actor,asset_version]))
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
		var sample_steps:int=ceili(animation.length*120.0)
		for frame in sample_steps+1:
			var t:=animation.length*frame/sample_steps;sample(clip,t)
			for i in skeleton.get_bone_count():
				var p:=bone_world(i);var gram:=p.basis.transposed()*p.basis
				check(p.origin.is_finite() and absf(p.basis.determinant()-1)<.0001 and gram.is_equal_approx(Basis.IDENTITY),"rigid transforms "+clip)
				if reference != null and clip != "death":
					var reference_bone := reference_skeleton.find_bone(skeleton.get_bone_name(i))
					check(reference_skeleton.get_bone_global_pose(reference_bone).is_equal_approx(skeleton.get_bone_global_pose(i)),"armour follows exact base pose "+clip)
				if frame==0:first.append(p)
				if frame==sample_steps and bool(manifest.clips[clip].loop):check(first[i].is_equal_approx(p),"matching loop endpoints "+clip)
			for v in geometry:
				var p:Vector3=bone_world(v.bone)*v.local
				if p.y<min_floor:worst={"time":t,"bone":v.name,"point":str(p),"bone_origin":str(bone_world(v.bone).origin)}
				min_floor=minf(min_floor,p.y)
				if v.name.begins_with("foot.") or v.name.begins_with("leg."):foot_floor=minf(foot_floor,p.y)
		floors[clip]={"minimum_y":min_floor,"paw_minimum_y":foot_floor if is_finite(foot_floor) else min_floor,"worst":worst}
		check(min_floor>-.001,"sampled floor clearance "+clip)
		for t in manifest.clips[clip].times:
			sample(clip,float(t));var bones:={}
			for i in skeleton.get_bone_count():
				var tr:=bone_world(i);bones[skeleton.get_bone_name(i)]=[tr.origin.x,tr.origin.y,tr.origin.z]
			poses.append({"clip":clip,"time":t,"bones":bones})
	metrics["floors"]=floors
	sample(rest_clip,0)
	check(bone_world(skeleton.find_bone("Socket_attack")).origin.z<bone_world(skeleton.find_bone("root")).origin.z,"attack socket points toward -Z")
	FileAccess.open(output.path_join("runtime_poses.json"),FileAccess.WRITE).store_string(JSON.stringify(poses))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	ASSET="res://assets/actors/automation_batch2/%s_v%d/%s_v%d.glb"%[actor,asset_version,actor,asset_version]
	rest_clip="pulse" if actor=="beacon" else "idle"
	art_height=.9 if actor.begins_with("hound") else 1.5 if actor=="beacon" else 2.8
	make_world();model=load(ASSET).instantiate();world.add_child(model)
	skeleton=model.find_children("*","Skeleton3D",true,false)[0];animator=model.find_children("*","AnimationPlayer",true,false)[0]
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if actor.ends_with("_armour"):
		var base_actor := actor.trim_suffix("_armour"); var version := "v2" if base_actor=="hound" else "v1"
		if asset_version == 2: version = "v3" if base_actor=="hound" else "v2"
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/automation_batch2/%s_v%d/parts.json"%[actor,asset_version]))
		var base_path: String = metadata.get("base_asset", "res://assets/actors/automation_batch2/%s_%s/%s_%s.glb"%[base_actor,version,base_actor,version])
		reference=load(base_path).instantiate();world.add_child(reference)
		reference_skeleton=reference.find_children("*","Skeleton3D",true,false)[0]
		reference_animator=reference.find_children("*","AnimationPlayer",true,false)[0]
		reference_animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	validate()
	if not "--checks-only" in OS.get_cmdline_user_args():
		root.size=Vector2i(1000,760)
		for view in ["front","rear","side","top"]:
			place(view);sample(rest_clip,0);await capture(view+".jpg")
		for clip in manifest.clips:
			place("front")
			if clip in ["death","assemble"]:camera.size=art_height*1.9
			var duration:=animator.get_animation(clip).length
			var count:=maxi(25,int(ceil(duration*24))+13)
			var is_loop: bool=manifest.clips[clip].loop
			# 30 fps review captures give exact integral frames for 0.5/1/1.2/2 s
			# loops. The delivered animation remains 24 fps + exact event keys.
			if is_loop:count=roundi(duration*30)*2
			for frame in count:
				var t:=fmod(frame/30.0,duration) if is_loop else clampf((frame-5)/24.0,0,duration)
				sample(clip,t);await capture("motion_%s/%03d.jpg"%[clip,frame])
			place("side")
			for frame in 7:
				sample(clip,duration*frame/6.0);await capture("poses_%s/%02d.jpg"%[clip,frame])

	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"metrics":metrics,"scope":"prepared art and playback; no gameplay integration"}
	FileAccess.open(output.path_join("runtime_validation.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("AUTOMATION_ACTOR_REVIEW ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
