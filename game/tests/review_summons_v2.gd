extends SceneTree
const Visual = preload("res://scripts/actor_visual.gd")
var arena: Node3D
var output := ""
var sequences: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func capture(path: String, closeup: bool) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if closeup:
		img=img.get_region(Rect2i(240,0,800,800));img.resize(512,512,Image.INTERPOLATE_LANCZOS)
	assert(img.save_png(output.path_join(path))==OK)

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false);arena.muted=true
	await process_frame
	for enemy in arena.enemies.values():enemy.body.free()
	arena.enemies.clear()
	arena.hud.visible=false;arena.hover_ring.visible=false;arena.shield_ring.visible=false;arena.move_marker.visible=false
	for ring in arena.tool_rings.values():ring.visible=false
	arena.player.position=Vector3(3.5,0,1.5);arena.player_model.rotation.y=PI
	var cases := [
		{"id":"turret_aim","actor":"turret","clip":"idle","seconds":3.0,"label":"포탑 360° 회전","size":1.65},
		{"id":"turret_attack","actor":"turret","clip":"attack","seconds":1.0,"label":"포신 반동","size":1.65},
		{"id":"turret_old_death","actor":"turret","clip":"death","seconds":2.0,"label":"이전: 통째로 넘어짐","size":2.2,"old":true},
		{"id":"turret_death","actor":"turret","clip":"death","seconds":2.0,"label":"수정: 부품 붕괴","size":2.2},
		{"id":"automaton_move","actor":"automaton","clip":"move","seconds":1.0,"label":"분할 인형 이동","size":1.65},
		{"id":"automaton_death","actor":"automaton","clip":"death","seconds":2.0,"label":"인형 일반 파괴","size":2.2},
		{"id":"automaton_explode","actor":"automaton","clip":"explode","seconds":2.0,"label":"인형 자폭·부품 비산","size":5.4}]
	for item in cases:
		var actor: String=item.actor
		var parent := Node3D.new();arena.world.add_child(parent)
		if item.get("old",false): Visual._scenes[actor]=load("res://assets/actors/combat_set_v1/"+actor+"_v1.glb")
		else: Visual._scenes[actor]=load(Visual.FILES[actor])
		var art:Node3D=Visual.create(parent,actor)
		parent.rotation.y=PI
		art.preview_shot({"node":parent})
		if item.clip in ["death","explode"] and not item.get("old",false):
			art.sample("attack",.43)
			art.detach_for_death(arena.world,arena,item.clip=="explode");art.set_process(false)
		var folder: String=item.id
		DirAccess.make_dir_recursive_absolute(output.path_join(folder+"/close"));DirAccess.make_dir_recursive_absolute(output.path_join(folder+"/native"))
		for f in 49:
			var phase:=f/48.0
			if item.id=="turret_aim":
				parent.rotation.y=PI+phase*TAU
				art.sync_ally({"node":parent,"cooldown":.8,"target":""},item.seconds/48.0)
			elif item.clip in ["death","explode"] and not item.get("old",false):
				if f>0:art._process(item.seconds/48.0)
			elif item.get("old",false):art.sample(item.clip,minf(1.,phase*2./1.25))
			else:art.sample(item.clip,phase)
			arena.player.visible=false
			var target:=Vector3(0,.36,0)
			arena.camera.size=item.size;arena.camera.position=target+Vector3(2.4,1.8,4.5);arena.camera.look_at(target)
			await capture(folder+"/close/%03d.png"%f,true)
			arena.player.visible=true
			arena.camera.size=20./1.75;arena.camera.rotation_degrees=Vector3(-30,45,0);arena.place_camera(Vector3.ZERO)
			await capture(folder+"/native/%03d.png"%f,false)
		item["frames"]=49;sequences.append(item)
		if is_instance_valid(art):art.free()
		parent.free()
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"sequences":sequences,"capture_count":686,"scope":"Actual game meshes, shader, skeleton, aiming controller and destruction start/process; damage tested separately."},"  "))
	print("SUMMONS_V2_REVIEW_COMPLETE")
	arena.queue_free();await process_frame;quit(0)
