extends SceneTree
## New assets only. Preserve generated PNG pixels and existing imports.
const ItemIcon = preload("res://scripts/item_icon.gd")
func _initialize() -> void:
	for id in ItemIcon.NEW_ART_IDS:
		var path := ItemIcon.art_path(id)
		var imported := "res://.godot/imported/%s-%s.ctex" % [path.get_file(),path.md5_text()]
		var config := ConfigFile.new()
		if FileAccess.file_exists(path+".import"): config.load(path+".import")
		config.set_value("remap","importer","texture")
		config.set_value("remap","type","CompressedTexture2D")
		config.set_value("remap","path",imported)
		config.set_value("remap","metadata",{"vram_texture":false})
		config.set_value("deps","source_file",path)
		config.set_value("deps","dest_files",PackedStringArray([imported]))
		config.set_value("params","compress/mode",0)
		config.set_value("params","mipmaps/generate",true)
		config.set_value("params","process/fix_alpha_border",true)
		config.set_value("params","process/size_limit",256)
		config.set_value("params","detect_3d/compress_to",0)
		config.save(path+".import")
	print("Prepared six new icon imports")
	quit()
