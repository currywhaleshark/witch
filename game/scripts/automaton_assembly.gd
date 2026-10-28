extends "res://scripts/summon_assembly.gd"
## Accepted automaton profile; shared lifecycle also drives turret assembly.
const PARTS = preload("res://assets/actors/automaton_assembly_v1/automaton_parts.glb")
const VARIANT_PARTS := {"A":preload("res://assets/actors/automaton_nodes_v1/automaton_a_parts.glb"),"B":preload("res://assets/actors/automaton_nodes_v1/automaton_b_parts.glb")}
var appearance_node := "base"
const DELAY := {"part_003":0.0,"part_005":0.0,"part_008_L":0.06,"part_008_R":0.06,
	"part_000":0.13,"part_009":0.22,"part_010":0.22,"part_001":0.31,"part_004":0.31,
	"part_013":0.37,"part_011":0.42,"part_002":0.46,"part_006":0.52}

func _init() -> void:
	parts_scene = PARTS
	part_delays = DELAY
	assembly_name = "AutomatonAssembly"

func configure(node_kind: String) -> void:
	appearance_node=node_kind if VARIANT_PARTS.has(node_kind) else "base"
	parts_scene=VARIANT_PARTS.get(appearance_node,PARTS)
	part_delays=DELAY.duplicate()
	if appearance_node!="base":
		var path: String="res://assets/actors/automaton_nodes_v1/automaton_%s.json"%appearance_node.to_lower()
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		for part in data.parts:
			if part.delay!=null: part_delays[part.name]=float(part.delay)
