extends SceneTree
## Integration checks and actual 1280x800 Compatibility-renderer captures.
var arena: Node3D
var output := ""
var checks: Array = []
var failures: Array = []
var captures: Array = []
const SHOTS = [
	{"id":"a_laundry","at":Vector3(7.6,0,-0.3),"label":"A · 세탁소 앞"},
	{"id":"a_stairs","at":Vector3(18.3,0,0),"label":"A · 슈퍼와 계단"},
	{"id":"b_stationery","at":Vector3(41.0,1.2,-11.5),"label":"B · 폐문방구"},
	{"id":"b_houses","at":Vector3(49.1,1.2,-7.8),"label":"B · 주택과 철물점"},
	{"id":"c_erosion","at":Vector3(68.8,1.2,-4.8),"label":"C · 침식 공터"}]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label);push_error(label)

func settle() -> void:
	for i in 8: await physics_frame

func capture(id: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var img:=root.get_texture().get_image()
	check(img.get_size()==Vector2i(1280,800),"capture size "+id)
	check(img.save_png(output.path_join(id+".png"))==OK,"capture saved "+id)
	captures.append(id+".png")

func geometry_signature() -> Array:
	var result: Array = []
	for shape in arena.map.find_children("*","CollisionShape3D",true,false):
		var size: Vector3 = shape.shape.size if shape.shape is BoxShape3D else Vector3.ZERO
		result.append([shape.get_parent().collision_layer,str(shape.global_transform),str(size)])
	return result

func lot_signature() -> Array:
	var result: Array = []
	for lot in arena.map.lots:
		result.append([lot.kind,lot.cut,lot.gate,lot.piers,lot.building,lot.sign,lot.ground,lot.out])
	return result

func decoration_signature() -> Array:
	var result: Array = []
	for node in arena.map.decorations.nodes:
		result.append([node.get_meta("decoration_id"),str(node.global_transform),str(node.mesh.get_aabb())])
	return result

func photos(prefix: String) -> void:
	for shot in SHOTS:
		arena.player.position=shot.at
		arena.player_model.rotation.y=PI
		arena.player_visual.sync_state(0.0,false,0.0,false,false,false,0.0)
		arena.camera.size=20.0/1.75
		arena.camera.rotation_degrees=Vector3(-30,45,0)
		arena.place_camera(shot.at)
		arena.map.fade_between(arena.camera.global_position,shot.at+Vector3.UP)
		await capture(prefix+"_"+shot.id)
		if prefix == "after":
			arena.camera.size=6.0
			await capture("close_"+shot.id)

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate();root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false);arena.muted=true
	await process_frame
	for enemy in arena.enemies.values(): enemy.body.free()
	arena.enemies.clear()
	arena.hud.visible=false;arena.hover_ring.visible=false;arena.shield_ring.visible=false;arena.move_marker.visible=false
	for ring in arena.tool_rings.values(): ring.visible=false
	var rng_state: int = arena.rng.state
	arena.map.decorations.enabled=false
	arena.map.build("alley_v2");arena.map.apply_lighting(arena.env,arena.sun);await settle()
	var colliders:=geometry_signature()
	var lots:=lot_signature()
	var nav: PackedVector3Array = arena.map.region.navigation_mesh.get_vertices()
	await photos("before")
	arena.map.decorations.enabled=true
	arena.map.build("alley_v2");await settle()
	check(geometry_signature()==colliders,"decoration preserves all collision shapes and world transforms")
	check(lot_signature()==lots,"decoration preserves seeded lot layout and original shop identity")
	check(arena.map.region.navigation_mesh.get_vertices()==nav,"decoration preserves baked navigation vertices")
	check(arena.rng.state==rng_state,"decoration does not consume arena combat RNG")
	check(arena.map.decorations.assets.size()==69,"all 69 specified textures are registered")
	var decoded_bytes:=0
	for id in arena.map.decorations.assets:
		var texture: Texture2D=arena.map.decorations._texture(id)
		check(texture!=null,"resource loaded "+id)
		if texture!=null:
			var img:=texture.get_image()
			decoded_bytes+=img.get_data_size()
			check(img.has_mipmaps(),"mipmaps "+id)
	var draw_ids: Dictionary = {}
	var fade_count:=0
	for entry in arena.map.fadeable:
		arena.map._set_alpha(entry,0.2)
		for node in entry.meshes:
			if node.has_meta("decal_base_alpha"):
				fade_count+=1
				check(is_equal_approx(node.material_override.albedo_color.a,0.2*float(node.get_meta("decal_base_alpha"))),"parent fade multiplies "+str(fade_count))
		arena.map._set_alpha(entry,entry.rest)
		for node in entry.meshes:
			if node.has_meta("decal_base_alpha"):
				check(node.material_override.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"texture alpha retained after restoring "+str(node.get_instance_id()))
	check(fade_count>0,"decorations participate in parent transparency")
	for node in arena.map.decorations.nodes:
		draw_ids[node.get_meta("decoration_id")]=true
		check(node.find_children("*","CollisionObject3D",true,false).is_empty(),"no decoration collision "+str(node.get_instance_id()))
	var layout:=decoration_signature()
	await photos("after")
	var lot_rows: Array=[]
	var occupancy: Dictionary={"open":0,"closed":0,"vacant":0}
	for lot in arena.map.lots:
		var status: String=lot.body.get_meta("alley_state")
		occupancy[status]+=1
		lot_rows.append({"key":lot.body.get_meta("lot_key"),"kind":lot.kind,"sign":lot.sign,"building":lot.building,"out":lot.out,"state":status})
	arena.map.build("flat");await settle()
	check(arena.map.decorations.nodes.is_empty() and arena.map.decorations.layout.is_empty(),"flat map has no decoration instances or layout")
	arena.map.build("alley_v2");await settle()
	check(decoration_signature()==layout,"reloading alley gives identical texture placements")
	var report={"passed":failures.is_empty(),"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"capture_count":captures.size(),"captures":captures,"texture_count":69,"instances":layout.size(),"used_assets":draw_ids.keys(),"unused_assets":arena.map.decorations.assets.keys().filter(func(id):return not draw_ids.has(id)),"decoded_texture_bytes_with_mips":decoded_bytes,"occupancy":occupancy,"lots":lot_rows,"scope":"Actual GPU captures, resource import, navigation/collision/RNG parity, parent fade, deterministic reload. Art and play-feel approval remain with the user."}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("ALLEY_DECALS_REVIEW_COMPLETE "+JSON.stringify({"passed":report.passed,"checks":checks.size(),"failures":failures.size(),"captures":captures.size(),"instances":layout.size()}))
	arena.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
