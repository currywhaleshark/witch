extends SceneTree
## Frame-time probe on a real GPU (not headless): loading, field entry, then the first automaton /
## turret / shotgun / tool / attack. Run windowed; optional user arg: output JSON path.
var arena: Node3D
var frames: Array = []
var label := "boot"
var last := 0

func _initialize() -> void:
	call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append({"ms": (now - last) / 1000.0, "label": label})
		last = now

func ready_to_cast() -> void:
	arena.state.mana = arena.state.max_mana
	arena.state.cooldowns.clear()
	arena.action_time = 0.0

func run() -> void:
	last = Time.get_ticks_usec()
	var t0 := Time.get_ticks_usec()
	arena = load("res://main.tscn").instantiate()
	arena.field_entry_mode = 1
	if "preload_mode" in arena:
		arena.preload_mode = 1
	root.add_child(arena)
	var ready_ms := (Time.get_ticks_usec() - t0) / 1000.0
	arena.muted = true
	label = "loading"
	for i in 2000:
		await tick(1)
		if not ("loading" in arena) or not arena.loading:
			break
	label = "entry"
	for i in 600:
		await tick(1)
		if not arena.player_visual.field_entry_active():
			break
	label = "settle"
	await tick(30)
	for enemy in arena.enemies.values():
		enemy.cooldown = 999
	var p: Vector3 = arena.player.position
	for step in [["automaton", "w", {"ground": [p.x + 2.0, p.y, p.z + 1.0]}], ["turret", "e", {"ground": [p.x - 2.0, p.y, p.z + 1.5]}],
			["shotgun", "rmb", {"ground": [p.x + 3.0, p.y, p.z - 3.0]}], ["tool", "q", {}], ["attack", "lmb", {"ground": [p.x + 1.0, p.y, p.z]}]]:
		ready_to_cast()
		label = step[0]
		arena.request_slot(step[1], step[2], step[0] == "attack")
		await tick(90)
	var spikes: Array = frames.filter(func(f): return f.ms > 33.0 and f.label != "boot")
	var worst := {}
	for f in frames:
		worst[f.label] = maxf(worst.get(f.label, 0.0), f.ms)
	var result := {"ready_ms": ready_ms, "frames": frames.size(), "worst_ms_by_phase": worst, "spikes_over_33ms": spikes}
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ProjectSettings.globalize_path("res://").path_join("../reports/asset_warmup_v1/hitch_latest.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print(JSON.stringify({"ready_ms": ready_ms, "worst": worst, "spikes": spikes.size()}))
	quit()
