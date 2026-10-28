extends SceneTree
## Exercise the full frame after release, including the summon AI and visual update.
var arena: Node3D
var output := ""
var failures: Array[String] = []
var checks := 0
var metrics: Array = []
var observe_only := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg=="--observe-only": observe_only=true
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func fresh() -> void:
	arena.reset_arena()
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel",Vector3(18,0,18),false,"normal","brute")
	arena.config.enemy_speed=0.0; arena.config.mana_regen=0.0
	arena.player.position=Vector3.ZERO; arena.place_camera(arena.player.position)

func run() -> void:
	root.size=Vector2i(1280,800)
	arena=load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.muted=true
	await process_frame
	for fps in [30.0,60.0]:
		for score in [0.0,40.0]:
			fresh(); arena.config.cast_speed_score=score
			arena.request_slot("w",{"ground":[4,0,0]})
			var anchor: Vector3=arena.automaton_assembly.global_position
			var maximum_drift:=0.0
			var first_drift:=-1.0
			var movement_frames:=0
			for frame in ceili((float(arena.windup.release)+0.6)*fps):
				await physics_frame
				arena._physics_process(1.0/fps)
				if arena.allies.is_empty(): continue
				var ally: Dictionary=arena.allies[0]
				var drift: float=ally.node.global_position.distance_to(anchor)
				if first_drift<0.0: first_drift=drift
				maximum_drift=maxf(maximum_drift,drift)
				if ally.node.get_node("ActorVisual").visual_state=="move": movement_frames+=1
			metrics.append({"fps":fps,"fcr":score,"first_release_frame_drift_m":first_drift,
				"maximum_idle_drift_m":maximum_drift,"unwanted_walk_frames":movement_frames})
			if not observe_only:
				check(arena.allies.size()==1,"full cast creates one ally")
				check(maximum_drift<0.00001,"idle ally stays at its assembled origin through release and following frames")
				check(movement_frames==0,"no walk pose triggered by mismatched waiting coordinates")
				arena.player.position+=Vector3(2,0,0)
				for frame in 45:
					await physics_frame
					arena._physics_process(1.0/60.0)
				check(arena.allies[0].node.position.distance_to(arena.automaton_spawn_position())<0.001,"ally still follows player movement")
				arena.spawn_enemy("near",Vector3(5,0,1),false,"normal","brute")
				var before: Vector3=arena.allies[0].node.position
				await physics_frame
				arena._physics_process(1.0/60.0)
				check(arena.allies[0].target=="near" and arena.allies[0].node.position.distance_to(before)>0.01,"nearby enemy still triggers immediate pursuit")
	var result: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"observe_only":observe_only,"metrics":metrics}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("AUTOMATON_ANCHOR_COMPLETE ",JSON.stringify(result))
	arena.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
