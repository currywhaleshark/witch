extends Control
## Game entry: shows the loading screen at once while the field scene and the character load on
## threads, then hands over to the arena, whose own warmup continues the same loading screen.
## Tests and reviews load main.tscn directly and never pass through here.
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const AssetWarmup = preload("res://scripts/asset_warmup.gd")
const PlayerVisual = preload("res://scripts/player_visual.gd")
const MAIN := "res://main.tscn"
# Share of the loading bar used here; the arena's warmup fills the rest.
const SHARE := 0.35
var progress := 0.0
var step := "필드 불러오는 중"
var _paths: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var screen := LoadingScreen.new()
	screen.warmup = self
	add_child(screen)
	_paths = [MAIN, PlayerVisual.BODY_PATH, PlayerVisual.HAIR_V27.asset]
	for part in PlayerVisual.PARTS.values():
		_paths.append(part.asset)
	for path in _paths:
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)

func _process(_dt: float) -> void:
	var total := 0.0
	var loaded := true
	for path in _paths:
		var amount := []
		var status := ResourceLoader.load_threaded_get_status(path, amount)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			loaded = false
			total += float(amount[0]) if not amount.is_empty() else 0.0
		else:
			total += 1.0
	progress = SHARE * total / _paths.size()
	if not loaded:
		return
	set_process(false)
	for path in _paths:
		if path != MAIN and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			AssetWarmup.held[path] = ResourceLoader.load_threaded_get(path)
	if ResourceLoader.load_threaded_get_status(MAIN) != ResourceLoader.THREAD_LOAD_LOADED:
		step = "필드를 불러오지 못했습니다"
		return
	step = "필드 준비 중"
	progress = SHARE
	# Let this frame draw before the arena's synchronous setup blocks the main thread.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().root.set_meta("loading_base", SHARE)
	var arena: Node = ResourceLoader.load_threaded_get(MAIN).instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	queue_free()
