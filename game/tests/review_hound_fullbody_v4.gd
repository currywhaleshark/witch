extends "res://tests/review_automation_batch2_complete_v1.gd"
## Whole-body retarget review. Prepared assets; arena rules remain untouched.

func add_hound(version: int, at: Vector3, extra: bool=false) -> Dictionary:
	var holder:=Node3D.new();world.add_child(holder);holders.append(holder);holder.position=at
	var base:Node3D=load("res://assets/actors/automation_batch2/hound_v%d/hound_v%d.glb"%[version,version]).instantiate();holder.add_child(base)
	var ap:AnimationPlayer=base.find_children("*","AnimationPlayer",true,false)[0]
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var entry:={"holder":holder,"base":base,"ap":ap,"kind":"hound","armour":null,"armour_ap":null}
	if extra:
		var armour:Node3D=load("res://assets/actors/automation_batch2/hound_armour_v3/hound_armour_v3.glb").instantiate();holder.add_child(armour)
		var aa:AnimationPlayer=armour.find_children("*","AnimationPlayer",true,false)[0]
		aa.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;entry.armour=armour;entry.armour_ap=aa
	entries.append(entry);return entry

func fixed_labels(left_text:String,right_text:String) -> void:
	for pair in [[left_text,32],[right_text,670]]:
		var item:=Label.new();hud.add_child(item);item.text=pair[0];item.position=Vector2(pair[1],28);item.add_theme_font_size_override("font_size",23)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output);make_world();root.size=Vector2i(1280,800)
	hud=CanvasLayer.new();root.add_child(hud)
	var parts:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/automation_batch2/hound_v4/parts.json"))
	var rate:float=parts.run_reference_playback_speed
	for view in ["side","front","rear"]:
		var left:=add_hound(4,Vector3(0,0,-.85) if view=="side" else Vector3(.85 if view=="front" else -.85,0,0))
		var right:=add_hound(3,Vector3(0,0,.85) if view=="side" else Vector3(-.85 if view=="front" else .85,0,0))
		camera.size=2.40;var center:=Vector3(0,.30,0)
		camera.position=center+(Vector3(-5,.45,0) if view=="side" else Vector3(0,1.2,-5 if view=="front" else 5));camera.look_at(center)
		fixed_labels("NEW / whole body","PREVIOUS / low trunk")
		for frame in 120:
			var t:=fmod(frame/60.0,.5);pose_entry(left,"run",t);pose_entry(right,"run",t)
			await capture("%s/%03d.jpg"%[view,frame])
		clear_actors()
	var hound:=add_hound(4,Vector3.ZERO,true)
	camera.size=1.50;camera.position=Vector3(-3,.9,-3);camera.look_at(Vector3(0,.32,0))
	fixed_labels("HEAVY TRACKER / whole-body follow","")
	for frame in 120:
		pose_entry(hound,"run",fmod(frame/60.0,.5));await capture("armour/%03d.jpg"%frame)
	clear_actors()
	# Native 1.75x game camera, with the actual player for scale.
	player=PlayerVisual.new();world.add_child(player);check(player.initialize(),"current player loads");player.set_process(false);player._sample("idle",.5)
	camera.rotation_degrees=Vector3(-30,45,0);camera.size=20./1.75*player.MODEL_SCALE;camera.position=Vector3(0,.7,0)+camera.basis.z*30
	player.position=floor_at(-3);player.rotation.y=PI;label("Witch",player.position)
	for row in [[4,-1.5,false],[3,0.,false],[4,1.8,true]]:
		var entry:=add_hound(row[0],floor_at(row[1]),row[2]);entry.holder.rotation.y=PI
		if row[2]:entry.holder.scale=Vector3.ONE*1.2
		pose_entry(entry,"run",.15);label("Heavy v4" if row[2] else "New v4" if row[0]==4 else "Previous v3",entry.holder.position)
	await capture("native_camera.jpg")
	metrics["native_camera"]={"size":camera.size,"pitch":-30,"yaw":45,"resolution":[1280,800]}
	for frame in 120:
		for entry in entries:pose_entry(entry,"run",fmod(frame/60.0,.5))
		await capture("native/%03d.jpg"%frame)
	clear_actors();player.free()
	# Travel proof: world moves 6.5m/s, animation uses calibrated stride.
	var marks:=Node3D.new();world.add_child(marks)
	for i in range(-4,33):
		var marker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(1.8,.001,.015);marker.mesh=box;marks.add_child(marker);marker.position=Vector3(0,.001,-i*.5)
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.34,.40,.43);mat.roughness=.9;marker.material_override=mat
	hound=add_hound(4,Vector3.ZERO);fixed_labels("6.5 m/s / calibrated playback %.3fx"%rate,"")
	for frame in 120:
		var t:=frame/60.0;hound.holder.position.z=-6.5*t;pose_entry(hound,"run",fmod(t*rate,.5))
		var center:Vector3=hound.holder.position+Vector3(0,.33,0);camera.size=1.8;camera.position=center+Vector3(-5,.7,0);camera.look_at(center)
		await capture("travel/%03d.jpg"%frame)
	metrics["travel"]={"speed_mps":6.5,"playback_speed":rate,"distance_per_clip_m":parts.run_cycle_distance_m}
	var result:={"passed":failures.is_empty(),"checks":checks,"captures":captures,"failures":failures,"metrics":metrics,"capture_fps":60,"scope":"same phase before/after; latest armour; native camera; calibrated forward travel; prepared assets only"}
	FileAccess.open(output.path_join("runtime_validation.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("HOUND_FULLBODY_REVIEW ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
