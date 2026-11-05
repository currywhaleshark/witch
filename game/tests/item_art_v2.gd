extends "res://tests/ground_loot_art_v2.gd"
## Exact new icon/model coverage, real loot interactions and actual GPU review.
const ItemIcon = preload("res://scripts/item_icon.gd")
var new_ids: Array = ItemIcon.NEW_ART_IDS.duplicate()
var names: Dictionary = {}
var icon_metrics: Array = []

func make_sheet() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)
	canvas.draw.connect(func():
		canvas.draw_rect(Rect2(Vector2.ZERO, root.size), Color("101c23"))
		canvas.draw_string(ThemeDB.fallback_font, Vector2(24, 34), "새 아이템 6종 · 아이템창 그림 / 바닥 모델", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("e3e9df"))
		for i in new_ids.size():
			var origin := Vector2(22 + (i % 3) * 419, 60 + (i / 3) * 348)
			canvas.draw_rect(Rect2(origin, Vector2(402, 332)), Color("1b2e37"))
			ItemIcon.draw_art(canvas, Rect2(origin + Vector2(12, 48), Vector2(175, 224)), new_ids[i])
			canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(10, 30), names[new_ids[i]], HORIZONTAL_ALIGNMENT_CENTER, 382, 19, Color("e3e9df"))
			canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(12, 311), "인벤토리", HORIZONTAL_ALIGNMENT_CENTER, 175, 14, Color("acbfc5"))
			canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(210, 311), "바닥 모델", HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color("acbfc5"))
	)
	for i in new_ids.size():
		var origin := Vector2(22 + (i % 3) * 419, 60 + (i / 3) * 348)
		var container := SubViewportContainer.new()
		container.position = origin + Vector2(207, 49)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(186, 224)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		container.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		arena.GroundLootVisual.create(world, {"kind":"equipment", "item":equipment(new_ids[i])})
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 0.63
		camera.position = Vector3(0.60, 0.90, 1.0)
		world.add_child(camera)
		camera.look_at(Vector3.ZERO)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("d4e2eb")
		environment.environment.ambient_light_energy = 0.65
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("718eaa")
		sky_material.sky_horizon_color = Color("cbd5dc")
		sky_material.ground_bottom_color = Color("4b4843")
		sky_material.ground_horizon_color = Color("cbd5dc")
		sky.sky_material = sky_material
		environment.environment.sky = sky
		environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -35, 0)
		light.light_energy = 1.6
		world.add_child(light)
	return layer

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/item_art_v2")
	DirAccess.make_dir_recursive_absolute(output)
	arena = load("res://main.tscn").instantiate()
	arena.field_entry_mode = 2
	arena.preload_mode = 2
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await physics_frame
	await physics_frame
	var definitions: Array = arena.items.bases.keys() + arena.items.uniques.keys() + arena.config.potions.keys()
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arena.GroundLootVisual.PROFILE_PATH))
	for id in definitions:
		check(not ItemIcon.art(id).is_empty() and FileAccess.file_exists(ItemIcon.art_path(id)), id + " has an explicit inventory icon")
		check(profiles.has(id), id + " has an explicit ground model")
	for id in new_ids:
		names[id] = arena.items.uniques[id].name if arena.items.uniques.has(id) else arena.items.bases[id].name
		var art := ItemIcon.art(id)
		check(not art.is_empty(), id + " loads its new texture")
		if art.is_empty(): continue
		var image: Image = art.texture.get_image()
		var alpha := image.detect_alpha() != Image.ALPHA_NONE
		for p in [Vector2i.ZERO, Vector2i(image.get_width()-1,0), Vector2i(0,image.get_height()-1), image.get_size()-Vector2i.ONE]:
			alpha = alpha and image.get_pixelv(p).a < .01
		check(alpha and image.has_mipmaps() and maxi(image.get_width(),image.get_height()) <= 256, id + " transparent corners and bounded mipmapped import")
		check(art.region.has_area() and art.region.size.x > 64 and art.region.size.y > 64, id + " readable visible icon bounds")
		icon_metrics.append({"id":id,"size":[image.get_width(),image.get_height()],"mip_bytes":image.get_data_size(),"region":str(art.region)})
		await inspect(id, arena.player.position + Vector3(0,0,-1))
	clear_drops()
	arena.bag.clear()
	for id in new_ids:
		check(arena.stow(equipment(id)), id + " fits inventory review")
	arena.inventory_window.visible = true
	arena.inventory_window.refresh()
	await process_frame
	await process_frame
	var bag_canvas: Control = arena.inventory_window.find_child("Bag", true, false)
	if OS.get_cmdline_user_args().has("--capture"):
		check(bag_canvas != null and bag_canvas.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "inventory uses smooth mipmapped icons")
	arena.inventory_window.visible = false
	var layer := make_sheet()
	await capture("catalogue")
	layer.queue_free()
	await process_frame
	# Real alley/camera with the same lighting as ordinary play.
	arena.map.build(arena.config.map)
	arena.map.apply_lighting(arena.env, arena.sun)
	arena.reset_arena()
	arena.set_physics_process(false)
	await physics_frame
	await physics_frame
	for frame in 180:
		if arena.map.nav_ready(): break
		await physics_frame
	check(arena.map.nav_ready(), "raised alley ready before capture")
	arena.player.position = arena.map.grounded(arena.map.snap(Vector3(46,1.2,-4)))
	arena.place_camera(arena.player.position)
	for enemy in arena.enemies.values():
		enemy.body.hide()
		enemy.body.position = Vector3(500,0,500)
	arena.bag.clear()
	for id in new_ids:
		arena.stow(equipment(id))
	arena.inventory_window.visible = true
	arena.inventory_window.refresh()
	arena.update_loot_hover(Vector2(-1000,-1000))
	await capture("inventory")
	arena.inventory_window.visible = false
	var native_size: float = arena.camera.size
	var front := Vector3(arena.camera.basis.z.x,0,arena.camera.basis.z.z).normalized()
	var center: Vector3 = arena.player.position + front*1.2
	group_lineup(new_ids, center)
	await capture("drop_launch")
	arena.tick_ground_loot(.14)
	await capture("drop_turn")
	arena.tick_ground_loot(.26)
	await capture("native_ground")
	arena.camera.size = native_size / 2.7
	arena.camera.position += center-arena.player.position
	await capture("detail_ground")
	arena.tick_ground_loot(5.1)
	check(arena.loot_labels().is_empty(), "new labels expire after five seconds")
	await capture("hidden_labels")
	for id in new_ids:
		var loot: Dictionary = arena.ground_items[new_ids.find(id)]
		arena.update_loot_hover(arena.camera.unproject_position(loot.visual.global_position))
		check(is_same(arena.hovered_loot,loot), id + " hover at actual alley position")
		await capture("hover_"+id)
	arena.update_loot_hover(Vector2(-1000,-1000))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ALT
	event.pressed = true
	arena._input(event)
	check(arena.loot_labels().size() == new_ids.size(), "Alt reveals all six expired labels")
	event.pressed = false
	arena._input(event)
	check(arena.loot_labels().is_empty(), "Alt release restores expired state")
	clear_drops()
	var report := {"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,
		"models":catalogue,"icons":icon_metrics,"captures":shots}
	FileAccess.open(output.path_join("runtime_validation.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("ITEM_ART_V2_RESULT checks=%d failures=%s" % [checks.size(),str(failures)])
	quit(0 if failures.is_empty() else 1)
