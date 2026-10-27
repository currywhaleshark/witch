extends SceneTree
## Isolated v21 run comparison using the current presentation controller in a copied current game project.
var output_dir := ""
var arena: Node3D
var visual: Node3D
var hidden: Dictionary = {}
var floor_node: MeshInstance3D
var records: Array = []
var lights: Dictionary = {}
var environment: Environment
var environment_before: Array = []
var review_kind := "swing"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_dir = arg.trim_prefix("--output=")
	call_deferred("run")

func capture(path: String, region: Rect2i) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.get_size() == Vector2i(1280, 800))
	assert(picture.get_region(region).save_png(output_dir.path_join(path)) == OK)

func camera(view: String) -> void:
	var studio := view != "native"
	for node in hidden: node.visible = false if studio else hidden[node]
	for light in lights:
		light.light_energy = 0.55 if studio else lights[light][0]
		light.light_color = Color.WHITE if studio else lights[light][1]
		light.shadow_enabled = false if studio else lights[light][2]
	if environment != null:
		environment.ambient_light_color = Color.WHITE if studio else environment_before[0]
		environment.ambient_light_energy = 0.35 if studio else environment_before[1]
		environment.background_color = Color("1c2430") if studio else environment_before[2]
	floor_node.visible = studio
	if not studio:
		arena.camera.rotation_degrees = Vector3(-30, 45, 0)
		arena.camera.size = 20.0 / 1.75
		arena.place_camera(arena.player.position)
	else:
		arena.camera.size = 3.4
		var target: Vector3 = arena.player.global_position + Vector3(0, 1.0, -0.60 if review_kind == "collapse" else 0.10)
		arena.camera.global_position = target + (Vector3(2.1, 0.8, 5) if view == "front" else Vector3(5, 0.25, 0))
		arena.camera.look_at(target)
		if view == "arms":
			var skeleton: Skeleton3D = visual.runtime.skeleton
			var hand_target: Vector3 = Vector3.ZERO
			for side in ["R", "L"]:
				hand_target += skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("DEF-hand." + side)).origin * 0.5
			hand_target += Vector3(0,0.12,0)
			arena.camera.size = 1.05
			arena.camera.global_position = hand_target + Vector3(0.55,0.12,2.2)
			arena.camera.look_at(hand_target)


func run() -> void:
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false);arena.set_process_input(false);arena.set_process_unhandled_input(false)
	await process_frame
	visual = arena.player_visual
	assert(visual.loaded_ok, visual.last_error)
	arena.player.position = Vector3.ZERO;visual.rotation.y = PI
	arena.hud.visible = false
	visual.set_active_tool(null)
	arena.shield_ring.visible = false;arena.hover_ring.visible = false;arena.move_marker.visible = false
	for ring in arena.tool_rings.values():ring.visible = false
	for enemy in arena.enemies.values():enemy.body.visible = false
	for mesh in arena.find_children("*", "MeshInstance3D", true, false):
		if not visual.is_ancestor_of(mesh):hidden[mesh] = mesh.visible
	for light in arena.find_children("*", "Light3D", true, false):
		lights[light] = [light.light_energy, light.light_color, light.shadow_enabled]
	for node in arena.find_children("*", "WorldEnvironment", true, false):
		environment = node.environment
		environment_before = [environment.ambient_light_color, environment.ambient_light_energy, environment.background_color]
	floor_node = MeshInstance3D.new();floor_node.mesh = PlaneMesh.new();floor_node.mesh.size = Vector2(7,7)
	var material := StandardMaterial3D.new();material.albedo_color = Color("384455");material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_node.material_override = material;root.add_child(floor_node);floor_node.position.y = -0.006
	for outfit in ["civilian", "transformed"]:
		if outfit == "transformed":
			assert(visual.replace_parts({"outfit":{"asset":"res://assets/outfit_transformed_v4.glb","hide_body_regions":["torso","arms","lowerlegs","feet"]}}),visual.last_error)
		for kind in ["previous", "run"]:
			review_kind = kind
			var clip_kind: String = {"previous":"run","attack":"attack","idle":"idle","run":"run","thrust":"attack","cast":"cast","hit":"hit_react","collapse":"collapse"}[kind]
			var desired_name: String = {"previous":"combat_run_rh_v20","attack":"combat_heavy_swing_rh_v20","idle":"combat_idle_rh_v20","run":"combat_run_rh_v21","thrust":"combat_thrust_rh_v20","cast":"combat_cast_rh_v20","hit":"combat_hit_rh_v20","collapse":"combat_collapse_rh_v20"}[kind]
			for animation_name in visual.runtime.animation_player.get_animation_list():
				if String(animation_name).get_file() == desired_name: visual._clips[clip_kind] = String(animation_name)
			visual._attack_clip_kind = "attack"
			visual.motion_duration = 1.0
			visual._collapse_from.clear();visual._collapse_grip_from = 0.0
			var length: float = visual._length(clip_kind)
			var count := 49
			var folder: String = outfit + "_" + kind
			DirAccess.make_dir_recursive_absolute(output_dir.path_join(folder))
			var rows: Array = []
			for i in count:
				var time := length * i / float(count - 1)
				visual._collapse_elapsed = time
				visual._sample(clip_kind, time)
				rows.append(visual.debug_snapshot())
				if kind in ["idle","attack"] and i in [0, int(count / 2)]:
					camera("grip")
					await capture("%s/%03d_grip.png" % [folder,i],Rect2i(240,0,800,800))
				for view in ["native", "front", "side", "arms"]:
					camera(view)
					var rect := Rect2i(460,240,360,320) if view == "native" else Rect2i(240,0,800,800)
					await capture("%s/%03d_%s.png" % [folder,i,view],rect)
			records.append({"folder":folder,"kind":kind,"outfit":outfit,"frames":count,"phase_samples":count,"length":length,"gameplay_duration_seconds":1.0,"controller_samples":rows})
			print("REVIEW_V21_SEQUENCE ",folder," ",count)
	FileAccess.open(output_dir.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"sequences":records,"native_camera_size":20.0/1.75,"viewport":[1280,800],"scope":"Run arms before v20 / after v21; two costumes, selected native framing and three studio views. Identical normalized body/leg phases. Authoring clip4s; review loop1s. Actual playback validated separately."},"  "))
	print("RUN_ARM_V21_REVIEW_COMPLETE")
	quit(0)
