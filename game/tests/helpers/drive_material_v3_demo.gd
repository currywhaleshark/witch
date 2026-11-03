extends "res://tests/helpers/drive_tree_v2_demo.gd"
## Material derivative only. Inherits the selected v2/v1 assembly and mechanism clocks.

func configure(id: String) -> void:
	asset_id = id
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/drive_material_v3/%s.json" % id))
	parts_scene = load("res://assets/weapons/drive_material_v3/%s.glb" % id)
	assembly_name = "DriveMaterialV3Review_" + id
	effect_radius = .65
	effect_height = 1.1
	for part in manifest.parts:
		part_delays[part.name] = float(part.delay)
		info[part.name] = part
