extends Node
## Named combat sound effects from audio/sfx_v1 (ElevenLabs candidates; see tools/combat_sfx.json).
## Presentation only: its own RNG picks variants and pitch, never the combat RNG.
## Gains level each file's measured RMS toward a per-role target; all values are trial values.
const DIR = "res://audio/sfx_v1/"
const FADE = 0.08
# files, gain_db, max_seconds (0 = play out), voices (same-cue overlap before stealing), skip (start offset), fade
const CUES = {
	"staff_swing": {"files": ["staff_swing"], "gain_db": -24.0, "max_seconds": 0.45, "voices": 2},
	"staff_hit": {"files": ["staff_hit_1", "staff_hit_2", "staff_hit_3"], "gain_db": -19.0, "max_seconds": 0.55, "voices": 2},
	"bolt_cutter_cut": {"files": ["bolt_cutter_cut"], "gain_db": -12.0, "max_seconds": 0.0, "voices": 2, "skip": 0.12},
	"grinder_hit": {"files": ["grinder_hit"], "gain_db": -21.0, "max_seconds": 0.6, "voices": 2},
	"chainsaw_cut": {"files": ["chainsaw_cut"], "gain_db": -19.0, "max_seconds": 0.7, "voices": 2},
	"tool_change": {"files": ["tool_change"], "gain_db": -6.0, "max_seconds": 0.0, "voices": 1},
	"shotgun_fire": {"files": ["shotgun_fire"], "gain_db": -22.0, "max_seconds": 0.0, "voices": 2},
	"crit_hit": {"files": ["crit_hit"], "gain_db": -20.0, "max_seconds": 0.0, "voices": 2},
	"player_hurt": {"files": ["player_hurt"], "gain_db": -6.0, "max_seconds": 0.0, "voices": 2},
	"block": {"files": ["block"], "gain_db": -14.0, "max_seconds": 0.0, "voices": 2},
	"summon_assemble": {"files": ["summon_assemble"], "gain_db": -4.0, "max_seconds": 0.7, "voices": 2},
	"summon_arrive": {"files": ["summon_arrive"], "gain_db": -10.0, "max_seconds": 0.0, "voices": 2},
	"automaton_explode": {"files": ["automaton_explode"], "gain_db": -19.0, "max_seconds": 0.0, "voices": 3},
	"summon_break": {"files": ["summon_break"], "gain_db": -13.0, "max_seconds": 0.0, "voices": 2},
	"potion_drink": {"files": ["potion_drink"], "gain_db": -17.0, "max_seconds": 0.0, "voices": 1},
	"spring_dash": {"files": ["spring_dash"], "gain_db": -11.0, "max_seconds": 0.0, "voices": 1},
	"shield_raise": {"files": ["shield_raise"], "gain_db": -5.0, "max_seconds": 0.0, "voices": 1},
	"enemy_bolt": {"files": ["enemy_bolt"], "gain_db": -18.0, "max_seconds": 0.0, "voices": 3},
	"boss_sweep": {"files": ["boss_sweep"], "gain_db": -18.0, "max_seconds": 0.0, "voices": 1},
	"boss_slam": {"files": ["boss_slam"], "gain_db": -9.0, "max_seconds": 0.0, "voices": 1},
	"boss_shockwave": {"files": ["boss_shockwave"], "gain_db": -13.0, "max_seconds": 0.0, "voices": 1},
	# Field-entry transformation. The 3.4s gear sound is cut near the grasp so it never covers the outfit change.
	"staff_assemble": {"files": ["staff_assemble"], "gain_db": -16.0, "max_seconds": 1.1, "voices": 1, "fade": 0.3},
	"outfit_change": {"files": ["outfit_change"], "gain_db": -6.0, "max_seconds": 0.0, "voices": 1},
}
var streams: Dictionary = {}
var voices: Array = []
var pool: Array[AudioStreamPlayer] = []
var rng = RandomNumberGenerator.new()
var last_variant: Dictionary = {}
# Recent cue names for tests and reviews.
var history: Array = []

func _ready() -> void:
	rng.seed = 7301
	for cue in CUES:
		var loaded: Array = []
		for file in CUES[cue].files:
			var path: String = DIR + file + ".wav"
			if ResourceLoader.exists(path):
				loaded.append(load(path))
		if not loaded.is_empty():
			streams[cue] = loaded
	for i in 16:
		var player = AudioStreamPlayer.new()
		add_child(player)
		pool.append(player)

func has_cue(cue: String) -> bool:
	return streams.has(cue)

func play(cue: String, gain_db: float = 0.0) -> bool:
	if not streams.has(cue):
		return false
	var spec: Dictionary = CUES[cue]
	var same: Array = voices.filter(func(v): return v.cue == cue)
	if same.size() >= int(spec.voices):
		_release(same[0])
	var player: AudioStreamPlayer = _free_player()
	var choices: Array = streams[cue]
	# Rotate variants without repeating the previous one back to back.
	var index = rng.randi() % choices.size()
	if choices.size() > 1 and index == last_variant.get(cue, -1):
		index = (index + 1) % choices.size()
	last_variant[cue] = index
	history.append(cue)
	if history.size() > 64:
		history.pop_front()
	player.stream = choices[index]
	player.pitch_scale = rng.randf_range(0.96, 1.04)
	player.volume_db = float(spec.gain_db) + gain_db
	player.play(float(spec.get("skip", 0.0)))
	voices.append({"cue": cue, "player": player, "age": 0.0, "max": float(spec.max_seconds), "base_db": player.volume_db,
		"fade": -1.0, "fade_length": float(spec.get("fade", FADE))})
	return true

func stop_all() -> void:
	for voice in voices:
		voice.player.stop()
	voices.clear()

func _free_player() -> AudioStreamPlayer:
	for player in pool:
		if not player.playing and voices.all(func(v): return v.player != player):
			return player
	var oldest: Dictionary = voices[0]
	_release(oldest)
	return oldest.player

func _release(voice: Dictionary) -> void:
	voice.player.stop()
	voices.erase(voice)

func _process(dt: float) -> void:
	for voice in voices.duplicate():
		voice.age += dt
		if not voice.player.playing:
			voices.erase(voice)
			continue
		# Long tails are faded out so rapid attacks don't pile up.
		if voice.max > 0 and voice.age >= voice.max and voice.fade < 0:
			voice.fade = 0.0
		if voice.fade >= 0:
			voice.fade += dt
			var amount = clampf(voice.fade / voice.fade_length, 0.0, 1.0)
			voice.player.volume_db = voice.base_db + linear_to_db(maxf(0.001, 1.0 - amount))
			if amount >= 1.0:
				_release(voice)
