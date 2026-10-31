extends Control
## Temporary loading screen shown while asset_warmup.gd runs. Opaque, so warmup renders stay hidden.
const INK = Color("0d1b24")
const PAPER = Color("e3e9df")
const MUTED = Color("9aadaf")
const GOLD = Color("d8b77b")
const TEAL = Color("8dd8c4")
var warmup: Node
var font = SystemFont.new()
var _shown := 0.0
# When booted through boot.tscn, the bar continues from the share it already filled.
var _base := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_tree().root.has_meta("loading_base") and not warmup is Control:
		_base = float(get_tree().root.get_meta("loading_base"))
		_shown = _base

func _process(dt: float) -> void:
	if warmup != null:
		# Ease the bar so short steps don't jump.
		_shown = move_toward(_shown, _base + (1.0 - _base) * float(warmup.progress), dt * 1.5)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	_centered(Vector2(w / 2, h / 2 - 70), "MACHINERY WITCH  /  COMBAT STUDY", 13, GOLD)
	_centered(Vector2(w / 2, h / 2 - 28), "기계장치의 마녀", 34, PAPER)
	var bar := Rect2(w / 2 - 220, h / 2 + 20, 440, 6)
	draw_rect(bar, Color("1d3039"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_shown, 0.0, 1.0), bar.size.y)), TEAL)
	var step: String = warmup.step if warmup != null else "불러오는 중"
	_centered(Vector2(w / 2, h / 2 + 56), step + "  ·  %d%%" % roundi(_shown * 100), 14, MUTED)
	_centered(Vector2(w / 2, h - 40), "임시 로딩 화면", 11, Color("526166"))

func _centered(pos: Vector2, text: String, size_px: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, pos - Vector2(width / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
