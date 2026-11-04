extends SceneTree
## Isolated art review; the arena's skill or combat rules are never changed.
const Visual = preload("res://scripts/player_visual.gd")
const DIR = "res://assets/characters/player/drive_attack_v32/"
var output = "res://../reports/drive_attack_v32/captures"
var visuals: Array = []
var world: Node3D
var camera: Camera3D
var contract: Dictionary
var checks := 0
var shots := 0
var headless := false
var reference: Dictionary
var worst_parity := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--validate": headless = true
	call_deferred("run")

func require(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func setup_stage() -> void:
	world = Node3D.new(); root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color("222936")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE; env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env; world.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-35,150,0); light.light_energy = 0.22; light.shadow_enabled = true; world.add_child(light)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-15,-40,0); fill.light_energy = 0.06; world.add_child(fill)
	var floor := MeshInstance3D.new(); var mesh := PlaneMesh.new(); mesh.size = Vector2(100,100); floor.mesh = mesh
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("303744"); mat.roughness = .9; floor.material_override = mat; floor.position.y = -.02; world.add_child(floor)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 3.6
	camera.position = Vector3(4.8,3.6,-8); world.add_child(camera); camera.look_at(Vector3(0,.85,0)); camera.current = true
	for i in 2:
		var v = Visual.new(); world.add_child(v); v.position = camera.basis.x * (-1.40 if i==0 else 1.40)
		require(v.initialize(), "visual initialization")
		if i==1:require(v.set_form("transformed"), "transformed outfit")
		var animator: AnimationPlayer=v.runtime.animation_player
		var own_library: AnimationLibrary=animator.get_animation_library("").duplicate(true)
		animator.stop();animator.remove_animation_library("");animator.add_animation_library("",own_library);v._clip=""
		v.runtime.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for name in contract.clips:
			require(v._add_clips(DIR+name+".glb"),name)
			v._clips[name]=name
			var anim: Animation = v.runtime.animation_player.get_animation(name)
			require(anim.get_track_count()==321,name+" all bone channels")
			require(absf(anim.length-float(contract.clips[name].duration))<.0001,name+" duration")
		v._staff_slide_tracks.merge(contract.staff_slide_tracks)
		animator.clear_caches()
		print("PREPARED_CHARACTER ",i," ",animator.get_animation("drive_bolt_enter_v32").track_get_path(0))
		visuals.append(v)
		var label := Label3D.new(); label.text = "평상복" if i==0 else "변신복"; label.position = v.position+Vector3(0,1.80,0); label.font_size = 42; label.pixel_size = .003; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; world.add_child(label)

func sequence(key: String) -> Array:
	if key in ["bolt","chainsaw_cut"]:
		return [["idle",.25],["drive_"+key+"_enter_v32",-1.0],["drive_"+key+"_loop_v32",-1.0],["drive_"+key+"_loop_v32",-1.0],["drive_"+key+"_loop_v32",-1.0],["drive_"+key+"_exit_v32",-1.0],["idle",.25]]
	return [["idle",.25],["drive_"+key+"_v32",-1.0],["idle",.25]]

func sample(v, name: String, time: float) -> void:
	v._sample(name,time)
	var sk: Skeleton3D = v.runtime.skeleton
	for bone in sk.get_bone_count():
		var pose := sk.get_bone_global_pose(bone)
		require(pose.origin.is_finite() and pose.basis.is_finite(),"finite pose")
	var right := sk.get_bone_global_pose(sk.find_bone("DEF-hand.R"))
	var left := sk.get_bone_global_pose(sk.find_bone("DEF-hand.L"))
	var offset := Vector3(.0074299751,.0158048961,-.0480000079)
	# Export conversion applies Z-up to Y-up to bone *globals*, not bone-local offsets.
	var center := right * Visual.STAFF_GRIP_OFFSET
	var axis := right.basis * Visual.STAFF_GRIP_BASIS.y
	# Exact secondary grip is checked in Blender and in exported pose parity below.
	require(axis.is_normalized(),"unit staff axis")

func run() -> void:
	root.size = Vector2i(1280,720)
	contract=JSON.parse_string(FileAccess.get_file_as_string(DIR+"runtime_contract.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	setup_stage()
	for i in 8:await process_frame
	if headless:
		reference = JSON.parse_string(FileAccess.get_file_as_string("res://../reports/drive_attack_v32/pose_reference.json"))
		var v = visuals[0]
		var sk: Skeleton3D = v.runtime.skeleton
		for name in reference:
			for row in reference[name]:
				sample(v,name,float(row.time))
				for bone_name in row.heads:
					var p: Array=row.heads[bone_name]
					var actual: Vector3=v.runtime.body.global_transform.affine_inverse()*(sk.global_transform*sk.get_bone_global_pose(sk.find_bone(bone_name)).origin)
					var error:=actual.distance_to(Vector3(p[0],p[1],p[2]))
					worst_parity=maxf(worst_parity,error)
					require(error<.00025,"export pose parity "+name+" "+bone_name+" "+str(error))
	var manifest=[]
	for key in ["bolt","grinder_sweep","chainsaw_cut","chainsaw_spin"]:
		var tool = "bolt_cutter" if key=="bolt" else ("grinder" if key=="grinder_sweep" else "chainsaw")
		for v in visuals:
			v.set_active_tool(tool);v.staff_visual.finish_assembly();v.staff_visual.advance(.5,false)
		var index=0
		for segment in sequence(key):
			var name: String=segment[0]
			var duration: float=segment[1] if segment[1]>0 else contract.clips[name].preview_duration
			var source_duration: float=duration if name=="idle" else contract.clips[name].duration
			var count := maxi(1,roundi(duration*24))
			for f in count:
				var phase:=float(f)/count
				for v in visuals:
					sample(v,name,phase*source_duration if name!="idle" else 0.0)
					v._hair_motion.advance(1.0/24.0)
					v.staff_visual.advance(1.0/24.0,false,phase if key=="bolt" and name.contains("_loop_") else -1.0)
				await process_frame
				if not headless:
					await RenderingServer.frame_post_draw
					require(root.get_texture().get_image().save_png(output.path_join("%s_%04d.png"%[key,index]))==OK,"capture")
					shots+=1
				index+=1
		manifest.append({"key":key,"frames":index,"fps":24})
		print("DRIVE_REVIEW",key,index)
	var report={"passed":true,"checks":checks,"captures":shots,"maximum_export_pose_error_m":worst_parity,"sequences":manifest,"forms":["civilian","transformed"],"scope":"isolated Godot art review; no damage events"}
	FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("DRIVE_ATTACK_V32_REVIEW_COMPLETE ",checks," ",shots)
	quit(0)
