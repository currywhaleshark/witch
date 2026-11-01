extends SceneTree
## Hand review in the real arena (GPU window): v28 body vs the v29 rebuilt hands, both outfits,
## idle / run / attack / cast, with the staff in hand. The game loads v29; with --body=v28 the v28
## body resource takes over the v29 path in Godot's resource cache, so no game code changes.
## Args: --body=v28|v29 --output=<dir>
const V28 := "res://assets/characters/player/model_refinement_v28/body_standard_v28.glb"
const V29 := "res://assets/characters/player/hand_rebuild_v29/body_standard_v29.glb"
var body := "v28"
var output := ""
var arena: Node3D
var cam: Camera3D
var shots: Array = []
# Must outlive run(): if freed, the cache drops the takeover and v28 loads again.
var replacement: Resource

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--body="): body = arg.trim_prefix("--body=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func hand(side: String) -> Vector3:
	var sk: Skeleton3D = arena.player_visual.runtime.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-hand." + side)).origin

func shoot(name: String) -> void:
	arena.paused = true
	arena.hud.visible = false
	await frames(2)
	var left := hand("L")
	var right := hand("R")
	var forward: Vector3 = -arena.player_visual.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var side_dir := forward.cross(Vector3.UP).normalized()
	var mid := (left + right) * 0.5
	for view in [["both", mid, forward * 0.95 + side_dir * 0.35 + Vector3.UP * 0.2],
			["right", right, forward * 0.42 - side_dir * 0.18 + Vector3.UP * 0.08],
			["left", left, forward * 0.42 + side_dir * 0.18 + Vector3.UP * 0.08]]:
		cam.global_position = view[1] + view[2]
		cam.look_at(view[1], Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join("%s_%s_%s.png" % [body, name, view[0]])
		root.get_texture().get_image().save_png(path)
		shots.append(path)
	arena.paused = false
	arena.hud.visible = true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	if body == "v28":
		replacement = load(V28)
		replacement.take_over_path(V29)
	arena = load("res://main.tscn").instantiate()
	arena.field_entry_mode = 2
	if "preload_mode" in arena: arena.preload_mode = 2
	root.add_child(arena)
	arena.muted = true
	await frames(10)
	for enemy in arena.enemies.values():
		enemy.cooldown = 999
	arena.config.enemy_speed = 0
	cam = Camera3D.new()
	cam.fov = 30
	arena.add_child(cam)
	cam.current = true
	for form in ["civilian", "transformed"]:
		arena.player_visual.set_form(form)
		await frames(40)
		await shoot(form + "_idle")
		var p: Vector3 = arena.player.position
		arena.request_slot("lmb", {"ground": [p.x + 6, p.y, p.z + 2]})
		await frames(24)
		await shoot(form + "_run")
		arena.request_slot("lmb", {"ground": [arena.player.position.x, p.y, arena.player.position.z]})
		await frames(30)
		arena.action_time = 0.0
		arena.request_slot("lmb", {"ground": [arena.player.position.x + 1.5, p.y, arena.player.position.z]}, true)
		await frames(9)
		await shoot(form + "_attack")
		await frames(40)
		arena.state.mana = arena.state.max_mana
		arena.state.cooldowns.clear()
		arena.action_time = 0.0
		var q: Vector3 = arena.player.position
		arena.request_slot("w", {"ground": [q.x + 2, q.y, q.z + 1]})
		await frames(12)
		await shoot(form + "_cast")
		await frames(50)
	var hands: MeshInstance3D = arena.player_visual.runtime.body.find_child("Body_Hands_v7", true, false)
	var result := {"body": body, "shots": shots.size(), "visual_loaded": arena.player_visual.loaded_ok,
		"hand_vertices": hands.mesh.surface_get_array_len(0) if hands else -1}
	FileAccess.open(output.path_join(body + "_capture.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("HAND_REVIEW ", JSON.stringify(result))
	quit()
