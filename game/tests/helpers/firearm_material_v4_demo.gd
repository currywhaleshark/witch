extends "res://tests/helpers/firearm_tree_demo.gd"
## Prepared assets only: keeps the original demo clocks and rigid motion.
func configure(id:String) -> void:
	asset_id=id
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_material_v4/%s.json"%id))
	parts_scene=load("res://assets/weapons/firearm_material_v4/%s.glb"%id)
	assembly_name="FirearmMaterialReview_"+id
	effect_radius=.32;effect_height=.35
	part_delays.clear();part_info.clear()
	for item in manifest.parts:
		part_delays[item.name]=float(item.delay)
		part_info[item.name]=item
		# The original burning-fuse demo resolves its segment by the old role name.
		part_info[str(item.name).trim_prefix("v4_")]=item
