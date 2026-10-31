extends SceneTree
## Named combat effects: every cue loads and plays, long tails fade, overlap is capped, mute and fallback.
var failures: Array = []
var checks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error(name)

func run() -> void:
	var arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	for i in 3:
		await process_frame
	var sfx = arena.sfx
	var missing: Array = sfx.CUES.keys().filter(func(cue): return not sfx.has_cue(cue))
	check(missing.is_empty(), "every named cue has its file: missing %s" % [missing])
	check(sfx.streams.staff_hit.size() == 3, "staff hit keeps three variants")
	arena.muted = false
	var played = true
	for cue in sfx.CUES:
		played = played and sfx.play(cue)
	check(played and not sfx.voices.is_empty(), "every cue starts playing")
	sfx.stop_all()
	var picks: Array = []
	for i in 6:
		sfx.play("staff_hit")
		picks.append(sfx.last_variant.staff_hit)
	var repeats = 0
	for i in range(1, picks.size()):
		repeats += int(picks[i] == picks[i - 1])
	check(repeats == 0, "hit variants never repeat back to back")
	check(sfx.voices.filter(func(v): return v.cue == "staff_hit").size() == 2, "same-cue overlap is capped")
	sfx.stop_all()
	sfx.play("staff_hit")
	for i in 50:
		await process_frame
		sfx._process(1.0 / 60.0)
	check(sfx.voices.is_empty(), "long hit tail fades out after its cap")
	sfx.play("staff_assemble")
	for i in 66:
		sfx._process(1.0 / 60.0)
	check(sfx.voices.size() == 1 and sfx.voices[0].fade > 0.0, "gear assembly starts its slow fade after 1.1s")
	for i in 30:
		sfx._process(1.0 / 60.0)
	check(sfx.voices.is_empty(), "gear assembly is gone before the outfit change")
	arena.muted = true
	var before = sfx.voices.size()
	arena.play_sfx("shotgun_fire")
	check(sfx.voices.size() == before, "mute silences named effects")
	arena.muted = false
	var cues_before = arena.sound_index
	arena.play_sfx("no_such_cue", 1.3)
	check(arena.sound_index == cues_before + 1, "missing effect falls back to the old impact cue")
	# The real field entry plays the staff-assembly and outfit-change files from its own events.
	sfx.stop_all()
	sfx.history.clear()
	var entry = load("res://main.tscn").instantiate()
	entry.field_entry_mode = 1
	root.add_child(entry)
	entry.muted = false
	for i in 400:
		await physics_frame
		if not entry.player_visual.field_entry_active():
			break
	var heard: Array = entry.sfx.history
	check(heard.has("staff_assemble") and heard.has("outfit_change") and heard.find("staff_assemble") < heard.find("outfit_change"), "field entry plays gear assembly then outfit change: %s" % [heard])
	entry.sfx.stop_all()
	for sound in entry.sounds:
		sound.stop()
	entry.queue_free()
	for i in 3:
		await process_frame
	var report = {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	var out = ProjectSettings.globalize_path("res://").path_join("../reports/combat_sfx_v1/godot_sfx_report.json").simplify_path()
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	# Live playbacks would otherwise be reported as leaked resources at exit.
	sfx.stop_all()
	for sound in arena.sounds:
		sound.stop()
	arena.queue_free()
	# Both scenes need a few frames to release streamed character resources.
	for i in 10:
		await process_frame
	quit(0 if failures.is_empty() else 1)
