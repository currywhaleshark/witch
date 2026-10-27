extends SceneTree
## Run once after initial import, then rerun Godot --editor --import --quit.
## The saved .glb.import files carry these settings into a clean checkout.
var parts := "res://assets/characters/player/combat_v12/"
var version := "v12"
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--parts="): parts = argument.trim_prefix("--parts=").trim_suffix("/") + "/"
		elif argument.begins_with("--version="): version = argument.trim_prefix("--version=")
	call_deferred("run")

func run() -> void:
	for stem in ["body_standard", "hair_semilong", "eyes_neutral", "outfit_civilian"]:
		var filename: String = stem + "_" + version + ".glb"
		var path: String = parts + filename
		var config := ConfigFile.new()
		if config.load(path + ".import") != OK:
			push_error("Missing first import for " + path); quit(1); return
		config.set_value("params", "animation/fps", 24)
		config.set_value("params", "animation/remove_immutable_tracks", false)
		config.set_value("params", "meshes/generate_lods", false)
		if stem == "body_standard":
			var packed := load(path) as PackedScene
			if packed == null:
				push_error("Missing imported scene"); quit(1); return
			var instance := packed.instantiate()
			var players := instance.find_children("*", "AnimationPlayer", true, false)
			if players.size() != 1:
				push_error("Expected one AnimationPlayer"); instance.free(); quit(1); return
			var player: AnimationPlayer = players[0]
			var import_id: String = player.get_meta("import_id", "PATH:" + str(instance.get_path_to(player)))
			var subresources: Dictionary = config.get_value("params", "_subresources", {})
			var nodes: Dictionary = subresources.get("nodes", {})
			var settings: Dictionary = nodes.get(import_id, {})
			# Preserve the frame-sampled twist/cloth bake during the parity review.
			# Source: Godot 4.6 ResourceImporterScene::_pre_process_animations.
			settings["optimizer/enabled"] = false
			settings["compression/enabled"] = false
			nodes[import_id] = settings
			subresources["nodes"] = nodes
			config.set_value("params", "_subresources", subresources)
			instance.free()
		if config.save(path + ".import") != OK:
			push_error("Could not save import settings"); quit(1); return
	print("COMBAT_IMPORT_V12_CONFIGURED")
	quit(0)
