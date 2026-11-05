extends "res://tests/review_automation_batch2_complete_v1.gd"
## Same-camera before/after and current armour, isolated from gameplay.

func add_version(kind: String, version: int, at: Vector3, extra: bool=false) -> Dictionary:
	var holder:=Node3D.new();world.add_child(holder);holders.append(holder);holder.position=at
	var base:Node3D=load("res://assets/actors/automation_batch2/%s_v%d/%s_v%d.glb"%[kind,version,kind,version]).instantiate();holder.add_child(base)
	var ap:AnimationPlayer=base.find_children("*","AnimationPlayer",true,false)[0]
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var entry:={"holder":holder,"base":base,"ap":ap,"kind":kind,"armour":null,"armour_ap":null}
	if extra:
		var armour:Node3D=load("res://assets/actors/automation_batch2/%s_armour_v2/%s_armour_v2.glb"%[kind,kind]).instantiate();holder.add_child(armour)
		var aa:AnimationPlayer=armour.find_children("*","AnimationPlayer",true,false)[0]
		aa.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;entry.armour=armour;entry.armour_ap=aa
	entries.append(entry);return entry

func fixed_labels(left_text:String,right_text:String) -> void:
	for pair in [[left_text,32],[right_text,670]]:
		var item:=Label.new();hud.add_child(item);item.text=pair[0];item.position=Vector2(pair[1],28);item.add_theme_font_size_override("font_size",23)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output);make_world();root.size=Vector2i(1280,800)
	hud=CanvasLayer.new();root.add_child(hud)
	for view in ["side","front"]:
		var left:=add_version("hound",3,Vector3(0,0,-.85) if view=="side" else Vector3(.85,0,0))
		var right:=add_version("hound",2,Vector3(0,0,.85) if view=="side" else Vector3(-.85,0,0))
		camera.size=2.40;var center:=Vector3(0,.28,0)
		camera.position=center+(Vector3(-5,.9,0) if view=="side" else Vector3(0,1.5,-5));camera.look_at(center)
		fixed_labels("NEW / Wolf gallop","PREVIOUS / procedural")
		for frame in 120:
			var t:=fmod(frame/60.0,.5);pose_entry(left,"run",t);pose_entry(right,"run",t)
			await capture("hound_%s/%03d.jpg"%[view,frame])
		clear_actors()
	for detail in ["gear","key","full"]:
		var spacing:=.65 if detail=="gear" else .52 if detail=="key" else 1.75
		var left:=add_version("giant",2,Vector3(spacing,0,0));var right:=add_version("giant",1,Vector3(-spacing,0,0))
		var center:=Vector3(0,1.52,-.65) if detail=="gear" else Vector3(0,2.58,-.43) if detail=="key" else Vector3(0,1.38,0)
		camera.size=1.18 if detail=="gear" else .96 if detail=="key" else 3.55
		camera.position=center+(Vector3(0,.25,-5) if detail!="full" else Vector3(0,1.9,-6));camera.look_at(center)
		fixed_labels("NEW / fitted shaft axis","PREVIOUS / world axis")
		for frame in 120:
			var t:=frame/60.0;pose_entry(left,"idle",t);pose_entry(right,"idle",t)
			await capture("giant_%s/%03d.jpg"%[detail,frame])
		clear_actors()
	var hound:=add_version("hound",3,Vector3.ZERO,true)
	camera.size=1.50;camera.position=Vector3(-3,.9,-3);camera.look_at(Vector3(0,.32,0))
	fixed_labels("HEAVY TRACKER / updated gallop","")
	for frame in 120:
		pose_entry(hound,"run",fmod(frame/60.0,.5));await capture("hound_armour/%03d.jpg"%frame)
	clear_actors()
	var giant:=add_version("giant",2,Vector3.ZERO,true)
	camera.size=3.65;camera.position=Vector3(-4,3,-6);camera.look_at(Vector3(0,1.35,0))
	fixed_labels("ENHANCED GIANT / fitted mechanism","")
	for frame in 120:
		pose_entry(giant,"idle",frame/60.0);await capture("giant_armour/%03d.jpg"%frame)
	clear_actors()
	player=PlayerVisual.new();world.add_child(player);check(player.initialize(),"current player loads");player.set_process(false);player._sample("idle",.5)
	camera.rotation_degrees=Vector3(-30,45,0);camera.size=20./1.75*player.MODEL_SCALE;camera.position=Vector3(0,.7,0)+camera.basis.z*30
	player.position=floor_at(-5);player.rotation.y=PI;label("Witch",player.position)
	for row in [["hound",3,-3.5,false],["hound",3,-1.8,true],["giant",2,.7,false],["giant",2,4.6,true]]:
		var entry:=add_version(row[0],row[1],floor_at(row[2]),row[3]);entry.holder.rotation.y=PI
		if row[3]:entry.holder.scale=Vector3.ONE*(1.2 if row[0]=="hound" else 1.1)
		pose_entry(entry,"run" if row[0]=="hound" else "idle",.15);label(row[0]+(" + armour" if row[3] else ""),entry.holder.position)
	await capture("native_camera.jpg")
	metrics["native_camera"]={"size":camera.size,"pitch":-30,"yaw":45,"resolution":[1280,800]}
	for frame in 120:
		for entry in entries:pose_entry(entry,"run" if entry.kind=="hound" else "idle",fmod(frame/60.0,.5 if entry.kind=="hound" else 2.))
		await capture("native/%03d.jpg"%frame)
	var result:={"passed":failures.is_empty(),"checks":checks,"captures":captures,"failures":failures,"metrics":metrics,"capture_fps":60,"scope":"same lighting before/after, latest armour, native camera; prepared assets only"}
	FileAccess.open(output.path_join("runtime_validation.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("MOTION_CORRECTION_REVIEW ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
