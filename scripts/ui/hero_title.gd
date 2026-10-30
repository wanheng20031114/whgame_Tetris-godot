@tool
class_name HeroTitle
extends Control

## 单行 TETRIS 字标：按容器自适应字号，逐字方块配色、弹跳落入与轻微浮动。

const LETTER_HUES: Array[String] = ["cyan", "amber", "violet", "accent", "pink", "accent2"]

@export var title_text: String = "TETRIS":
	set(value):
		title_text = value
		if is_node_ready():
			_rebuild_letters()
@export_enum("Left", "Center", "Right") var horizontal_alignment: int = HORIZONTAL_ALIGNMENT_LEFT:
	set(value):
		horizontal_alignment = value
		queue_redraw()

var _drop: Array[float] = []
var _t: float = 0.0
var _letter_tweens: Array[Tween] = []


func _ready() -> void:
	_rebuild_letters()
	visibility_changed.connect(_update_processing)
	if not Engine.is_editor_hint():
		UITheme.theme_changed.connect(func(_m): queue_redraw())
		play()
	_update_processing()


func _update_processing() -> void:
	set_process(not Engine.is_editor_hint() and is_visible_in_tree())


func _stop_letter_tweens() -> void:
	for tween in _letter_tweens:
		if tween.is_valid():
			tween.kill()
	_letter_tweens.clear()


func _rebuild_letters() -> void:
	# Kill callbacks holding old indices before resizing, including when shortening.
	_stop_letter_tweens()
	_drop.resize(title_text.length())
	_drop.fill(1.0)
	queue_redraw()


func play() -> void:
	_stop_letter_tweens()
	for i in _drop.size():
		_drop[i] = 0.0
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_letter_tweens.append(tw)
		tw.tween_method(func(v: float): _drop[i] = v, 0.0, 1.0, 0.6).set_delay(0.15 + i * 0.055)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _c(key: String) -> Color:
	if Engine.is_editor_hint():
		return {"cyan": Color("#3ddcff"), "amber": Color("#ffb547"), "pink": Color("#ff5c9a"),
			"violet": Color("#8c6bff"), "accent": Color("#c6ff4d"), "text": Color("#f6f3ff"), "accent2": Color("#ff8f6b"),
			"ink": Color("#06040b")}[key]
	return UITheme.color(key)


func _dark() -> bool:
	return Engine.is_editor_hint() or UITheme.is_dark()


func _word_width(font: Font, font_size: int) -> float:
	# 与逐字绘制使用相同的 advance，避免整词测宽与逐字绘制产生溢出。
	var width := 0.0
	for ch in title_text:
		width += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return width


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var font := get_theme_font("font", "TitleLabel")
	if font == null:
		return
	var dark := _dark()

	# 单行居中基线；预留浮动、回弹和阴影空间。
	var probe := 100
	var available_width := maxf(size.x - 8.0, 1.0)
	var available_height := maxf(size.y - 32.0, 1.0)
	var font_size := maxi(1, int(probe * minf(
		available_width / maxf(_word_width(font, probe), 1.0),
		available_height / font.get_height(probe))))
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var total := _word_width(font, font_size)
	var x := 4.0
	if horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (size.x - total) * 0.5
	elif horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = size.x - total - 4.0
	for i in title_text.length():
		var ch := title_text[i]
		var k := _drop[i]
		var bob := sin(_t * 1.8 + i * 0.6) * 2.0
		var dy := (1.0 - k) * -90.0 + bob
		var hue := _c(LETTER_HUES[i % LETTER_HUES.size()])
		var a := clampf(k * 1.4, 0.0, 1.0)
		var pos := Vector2(x, baseline + dy)
		# 柔和落影 + 实色字
		draw_string(font, pos + Vector2(0, 6), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, a * (0.28 if dark else 0.08)))
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(hue, a))
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
