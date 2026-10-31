extends "res://tests/review_staff_visual.gd"

func pixels(path: String) -> Image:
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	picture.save_png(output.path_join(path))
	return picture

func run() -> void:
	ProjectSettings.set_setting("debug/entry_polish_v27",true)
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();arena.field_entry_mode=1;root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat");prepare()
	for i in 180:arena._physics_process(1.0/60.0)
	arena.player_model.look_at(arena.player.position+Vector3.RIGHT)
	arena.hud.visible=false
	var focus:Vector3=arena.player.position+Vector3(0,.85,0)
	arena.camera.size=2.65;arena.camera.position=focus+Vector3(8,2,-4);arena.camera.look_at(focus)
	var reveal=load("res://scripts/outfit_reveal.gd").new();reveal.initialize(arena.player_visual)
	var rows:Array=[]
	var passed:=true
	for form in ["civilian","transformed"]:
		arena.player_visual.set_form(form)
		var before:Image=await pixels(form+"_original.png")
		assert(reveal.begin());reveal.sample(0.0 if form=="civilian" else 1.0)
		var after:Image=await pixels(form+"_preview.png")
		# Restrict the comparison to the character, excluding the arena background.
		var total:=0.0;var large:=0;var count:=0;var maximum:=0.0
		for y in range(200,680):
			for x in range(500,780):
				var a:=before.get_pixel(x,y);var b:=after.get_pixel(x,y)
				var difference:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
				total+=difference;maximum=maxf(maximum,difference);count+=1
				if difference>.1:large+=1
		var ok:=total/count<.01 and float(large)/count<.02
		passed=passed and ok
		rows.append({"form":form,"passed":ok,"mean_max_rgb_error":total/count,"large_error_fraction":float(large)/count,"max_rgb_error":maximum,"pixels":count})
		reveal.clear()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"rows":rows,"scope":"Actual game PBR outfit versus reveal preview at fully outgoing/incoming endpoints; identical fixed pose and camera. Includes imported metallic/roughness channel maps."},"  "))
	print("OUTFIT_MATERIAL_PARITY ",passed," ",rows)
	arena.free();quit(0 if passed else 1)
