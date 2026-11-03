extends "res://tests/review_drive_tree_v1.gd"
const OldDemo=preload("res://tests/helpers/drive_tree_demo.gd")
const NewDemo=preload("res://tests/helpers/drive_tree_v2_demo.gd")
const Actor=preload("res://scripts/actor_visual.gd")
func run()->void:
	root.size=Vector2i(1440,800)
	var world:=world_scene();var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	for id in ["guillotine","guillotine_saw","guillotine_lock","compound_executor"]:
		var old:=OldDemo.new();old.configure(id);world.add_child(old);old.initialize(world);old.set_process(false);old.position.x=-1.65
		var revised:=NewDemo.new();revised.configure(id);world.add_child(revised);revised.initialize(world);revised.set_process(false);revised.position.x=1.65
		var targets:Array=[]
		if id=="guillotine_lock":
			for x in [-1.65,1.65]:
				var target:=Node3D.new();world.add_child(target);target.position=Vector3(x,.13,.10);target.scale=Vector3.ONE*.60
				var visual=Actor.create(target,"rag");assert(visual!=null);visual.sample("idle",.2);targets.append(target)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.4
		camera.position=Vector3(2.2,3.2,-11);camera.look_at(Vector3(0,1.05,0))
		var seq:String="compare_"+id
		for frame in 96:
			var t:=frame/24.0;old.sample_demo(t);revised.sample_demo(t)
			# One frozen reference enemy shows the lock-first order; no gameplay AI/HP.
			for target in targets:target.visible=t<1.65
			await capture("%s/%03d.jpg"%[seq,frame])
		sequences.append({"id":seq,"asset":id,"frames":96,"fps":24})
		old.sample_demo(2.6);revised.sample_demo(2.6)
		for target in targets:target.hide()
		await capture("models/%s_impact.jpg"%id)
		old.queue_free();revised.queue_free()
		for target in targets:target.queue_free()
		await process_frame
	# The front camera looks toward +Z, so world +X is screen-left.
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"captures":captures,"sequences":sequences,"left":"v2","right":"v1","target":"One static rag at 0.60 scale for lock-order illustration; not gameplay."},"  "))
	print("DRIVE_V2_REVIEW_DONE ",captures);quit()
