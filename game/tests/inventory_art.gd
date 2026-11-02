extends SceneTree
## Validate icon coverage/transparency/imports and capture native inventory plus a contact sheet.
const ItemIcon = preload("res://scripts/item_icon.gd")
var arena: Node3D
var checks: Array = []
var failures: Array = []
var assets: Array = []
var output: String
var ids: Array = []
var names: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error(label)

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " GPU capture saved")

func item(id: String, rarity: String = "rare") -> Dictionary:
	var base: Dictionary = arena.items.bases[id]
	return {"base": id, "slot": base.slot, "rarity": rarity, "level": 30, "options": {}, "affixes": [],
		"name": base.name, "sockets": int(base.socket_max), "pieces": []}

func draw_sheet(view: Control) -> void:
	view.draw_rect(Rect2(Vector2.ZERO, root.size), Color("101c23"))
	var font: Font = arena.inventory_window.get_theme_default_font()
	view.draw_string(font, Vector2(24, 30), "인벤토리 아이콘 v1 · 장비 22종 / 물약 13종", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("e3e9df"))
	for i in ids.size():
		var origin := Vector2(24 + (i % 7) * 176, 48 + (i / 7) * 146)
		view.draw_rect(Rect2(origin, Vector2(168, 138)), Color("172b34"))
		ItemIcon.draw_art(view, Rect2(origin + Vector2(30, 6), Vector2(108, 104)), ids[i])
		view.draw_string(font, origin + Vector2(4, 131), names[ids[i]], HORIZONTAL_ALIGNMENT_CENTER, 160, 11, Color("e3e9df"))

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/inventory_art_v1")
	DirAccess.make_dir_recursive_absolute(output)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await physics_frame
	await physics_frame
	for base in arena.items.data.bases:
		ids.append(base.id)
		names[base.id] = base.name
	for unique in arena.items.data.uniques:
		ids.append(unique.id)
		names[unique.id] = unique.name
	for id in arena.config.potions:
		ids.append(id)
		names[id] = arena.config.potions[id].name
	check(ids.size() == 35, "all twenty bases, two uniques and thirteen potions have explicit icon IDs")
	for id in ids:
		var asset := ItemIcon.art(id)
		check(not asset.is_empty(), id + " has a runtime texture")
		if asset.is_empty():
			continue
		var texture: Texture2D = asset.texture
		var image := texture.get_image()
		var transparent := image.detect_alpha() != Image.ALPHA_NONE
		var corners := [Vector2i.ZERO, Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1), image.get_size() - Vector2i.ONE]
		for point in corners:
			transparent = transparent and image.get_pixelv(point).a < 0.01
		check(transparent and asset.region.has_area() and maxi(image.get_width(), image.get_height()) <= 256 and image.has_mipmaps(), id + " is a transparent bounded mipmapped UI texture")
		assets.append({"id": id, "path": ItemIcon.ART_PATH + id + ".png", "sha256": FileAccess.get_sha256(ItemIcon.ART_PATH + id + ".png"),
			"imported_size": [image.get_width(), image.get_height()], "region": str(asset.region), "mip_bytes": image.get_data_size()})
	var window = arena.inventory_window
	window.visible = true
	for id in ["glass_orb", "star_pin", "cotton_coat", "work_gloves", "sneakers", "brass_brooch", "silver_ring"]:
		var worn := item(id)
		arena.equipment[worn.slot] = worn
	arena.refresh_gear()
	for id in ["glass_orb", "crystal_core", "bp_shotgun", "bp_chainsaw", "bp_automaton", "part_cutting", "part_ballistic", "part_power", "brass_brooch", "silver_brooch", "copper_ring", "silver_ring"]:
		check(arena.stow(item(id, "magic")), id + " fits equipment review page 1")
	window.refresh()
	await capture("equipment_mediums")
	arena.bag.clear()
	for id in ["ribbon_tie", "star_pin", "cotton_coat", "quilted_cape", "cotton_gloves", "work_gloves", "sneakers", "leather_boots"]:
		check(arena.stow(item(id)), id + " fits equipment review page 2")
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	for unique in arena.items.data.uniques:
		check(arena.stow(arena.items.make_unique(rng, 30, unique.id)), unique.id + " fits the unique review")
	window.refresh()
	await capture("equipment_clothing")
	for id in arena.config.potions:
		arena.store_potion(id, 7)
	window.mode = "potions"
	window.refresh()
	await capture("potions")
	window.visible = false
	var sheet_layer := CanvasLayer.new()
	sheet_layer.layer = 100
	root.add_child(sheet_layer)
	var sheet := Control.new()
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.draw.connect(func(): draw_sheet(sheet))
	sheet_layer.add_child(sheet)
	await capture("contact_sheet")
	var bytes := 0
	for asset in assets:
		bytes += asset.mip_bytes
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "assets": assets, "texture_mip_bytes": bytes}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("INVENTORY_ART_RESULT checks=%d failures=%s bytes=%d" % [checks.size(), str(failures), bytes])
	quit(0 if failures.is_empty() else 1)
