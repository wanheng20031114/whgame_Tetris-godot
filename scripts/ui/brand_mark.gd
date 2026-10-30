@tool
class_name BrandMark
extends Control

## 品牌标识：四块方块依次落下拼成 T 形，之后轻微呼吸浮动

const CELLS: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(1, 1)]
const COLORS: Array[Color] = [Color("#4cc9f0"), Color("#7b61ff"), Color("#f72585"), Color("#ffb703")]

@export var cell_size: float = 18.0:
	set(v):
		cell_size = v
		update_minimum_size()
		queue_redraw()
@export var gap: float = 3.0:
	set(value):
		gap = value
		update_minimum_size()
		queue_redraw()
@export var play_on_ready: bool = true

var _drop: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _t: float = 0.0
var _drop_tweens: Array[Tween] = []


func _ready() -> void:
	visibility_changed.connect(_update_processing)
	if play_on_ready and not Engine.is_editor_hint():
		play()
	_update_processing()


func _update_processing() -> void:
	set_process(not Engine.is_editor_hint() and is_visible_in_tree())


func _get_minimum_size() -> Vector2:
	return Vector2(3.0 * cell_size + 2.0 * gap, 2.0 * cell_size + gap)


func play() -> void:
	for tween in _drop_tweens:
		if tween.is_valid():
			tween.kill()
	_drop_tweens.clear()
	for i in _drop.size():
		_drop[i] = 0.0
		var tw := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		_drop_tweens.append(tw)
		tw.tween_method(_set_drop.bind(i), 0.0, 1.0, 0.55).set_delay(0.08 + i * 0.09)


func _set_drop(v: float, i: int) -> void:
	_drop[i] = v
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var step := cell_size + gap
	var origin := (size - _get_minimum_size()) * 0.5
	for i in CELLS.size():
		var bob := sin(_t * 2.2 + i * 0.7) * cell_size * 0.06
		var fall := (1.0 - _drop[i]) * -size.y * 1.4
		var p := origin + CELLS[i] * step + Vector2(0, fall + bob)
		var r := Rect2(p, Vector2(cell_size, cell_size))
		var c := COLORS[i]
		c.a = clampf(_drop[i] * 1.5, 0.0, 1.0)
		draw_rect(r, c)
		draw_rect(Rect2(r.position, Vector2(cell_size, cell_size * 0.22)), Color(1, 1, 1, 0.22 * c.a))
