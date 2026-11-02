extends SceneTree
## Import generated PNGs as small lossless UI textures. Source PNG pixels stay untouched.
func _initialize() -> void:
	var folder := "res://assets/ui/inventory_v1/"
	var entries: Array = []
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".png"):
			continue
		var path := folder + file
		var source := Image.new()
		source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		var imported := "res://.godot/imported/%s-%s.ctex" % [file, path.md5_text()]
		var config := ConfigFile.new()
		if FileAccess.file_exists(path + ".import"):
			config.load(path + ".import")
		config.set_value("remap", "importer", "texture")
		config.set_value("remap", "type", "CompressedTexture2D")
		config.set_value("remap", "path", imported)
		config.set_value("remap", "metadata", {"vram_texture": false})
		config.set_value("deps", "source_file", path)
		config.set_value("deps", "dest_files", PackedStringArray([imported]))
		config.set_value("params", "compress/mode", 0)
		config.set_value("params", "mipmaps/generate", true)
		config.set_value("params", "process/fix_alpha_border", true)
		config.set_value("params", "process/size_limit", 256)
		config.set_value("params", "detect_3d/compress_to", 0)
		config.save(path + ".import")
		entries.append({"id": file.get_basename(), "size": [source.get_width(), source.get_height()],
			"alpha": source.detect_alpha(), "used_rect": str(source.get_used_rect()),
			"corner_alpha": [source.get_pixel(0, 0).a, source.get_pixel(source.get_width() - 1, 0).a,
				source.get_pixel(0, source.get_height() - 1).a, source.get_pixel(source.get_width() - 1, source.get_height() - 1).a],
			"sha256": FileAccess.get_sha256(path)})
	var output := ProjectSettings.globalize_path("res://../reports/inventory_art_v1")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("source_assets.json"), FileAccess.WRITE).store_string(JSON.stringify(entries, "  ") + "\n")
	print("Prepared %d icon imports" % entries.size())
	quit()
