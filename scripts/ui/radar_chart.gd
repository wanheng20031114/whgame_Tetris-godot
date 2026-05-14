class_name RadarChart
extends Control

const DIMENSION_COUNT: int = 6
const DIMENSION_KEYS: Array = ["speed", "attack", "efficiency", "structure", "stability", "vision"]
const DIMENSION_LABEL_KEYS: Array = [
	"TXT_RADAR_SPEED",
	"TXT_RADAR_ATTACK",
	"TXT_RADAR_EFFICIENCY",
	"TXT_RADAR_STRUCTURE",
	"TXT_RADAR_STABILITY",
	"TXT_RADAR_VISION"
]
const DIMENSION_TOOLTIP_KEYS: Array = [
	"TXT_REPLAY_RADAR_SPEED_TOOLTIP",
	"TXT_REPLAY_RADAR_ATTACK_TOOLTIP",
	"TXT_REPLAY_RADAR_EFFICIENCY_TOOLTIP",
	"TXT_REPLAY_RADAR_STRUCTURE_TOOLTIP",
	"TXT_REPLAY_RADAR_STABILITY_TOOLTIP",
	"TXT_REPLAY_RADAR_VISION_TOOLTIP"
]

@export_group("雷达图外观")
@export var chart_radius: float = 140.0
@export var grid_color: Color = Color(0.3, 0.35, 0.5, 0.4)
@export var axis_color: Color = Color(0.35, 0.4, 0.55, 0.6)
@export var fill_color: Color = Color(0.2, 0.75, 1.0, 0.25)
@export var outline_color: Color = Color(0.3, 0.85, 1.0, 0.9)
@export var outline_width: float = 2.5
@export var vertex_dot_radius: float = 5.0
@export var vertex_dot_color: Color = Color(0.4, 0.9, 1.0, 1.0)
@export var use_value_vertex_colors: bool = true
@export var low_score_dot_color: Color = Color(0.50, 0.02, 0.03, 1.0)
@export var mid_low_score_dot_color: Color = Color(1.0, 0.35, 0.02, 1.0)
@export var mid_high_score_dot_color: Color = Color(1.0, 0.86, 0.10, 1.0)
@export var high_score_dot_color: Color = Color(0.05, 1.0, 0.28, 1.0)

# 六个方向的文字：默认从 16 放大到 32（2 倍）
@export var label_font_size: int = 32
@export var label_color: Color = Color(0.8, 0.85, 0.95, 1.0)

# 同步外扩，避免文字放大后压在图边缘
@export var label_offset: float = 40.0

@export var show_value_labels: bool = true
@export var value_label_color: Color = Color(0.6, 0.9, 1.0, 0.8)
@export var grid_levels: int = 3
@export var animation_duration: float = 0.6
@export var auto_minimum_size: bool = true

var _current_values: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _target_values: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _animating: bool = false
var _tween: Tween = null
var _label_tooltip_rects: Array[Rect2] = []


func set_data(values: Dictionary, animate: bool = true) -> void:
	for i in range(DIMENSION_COUNT):
		var key: String = DIMENSION_KEYS[i]
		_target_values[i] = clampf(float(values.get(key, 0.0)), 0.0, 100.0)

	if animate and is_inside_tree():
		_start_animation()
	else:
		for i2 in range(DIMENSION_COUNT):
			_current_values[i2] = _target_values[i2]
		queue_redraw()


func set_data_immediate(values: Dictionary) -> void:
	set_data(values, false)


func get_data() -> Dictionary:
	var result: Dictionary = {}
	for i in range(DIMENSION_COUNT):
		result[DIMENSION_KEYS[i]] = _current_values[i]
	return result


func _start_animation() -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	_animating = true
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)

	var start_values: Array = _current_values.duplicate()
	_tween.tween_method(
		func(progress: float) -> void:
			for i in range(DIMENSION_COUNT):
				_current_values[i] = lerpf(start_values[i], _target_values[i], progress)
			queue_redraw(),
		0.0, 1.0, animation_duration
	)
	_tween.finished.connect(func() -> void:
		_animating = false
	)


func _draw() -> void:
	var center: Vector2 = size / 2.0
	_label_tooltip_rects.clear()

	for level in range(1, grid_levels + 1):
		var ratio: float = float(level) / float(grid_levels)
		var r: float = chart_radius * ratio
		_draw_polygon_outline(center, r, grid_color, 1.0)

	for i in range(DIMENSION_COUNT):
		var angle: float = _get_angle(i)
		var end_point: Vector2 = center + Vector2(cos(angle), sin(angle)) * chart_radius
		draw_line(center, end_point, axis_color, 1.0)

	var data_points: PackedVector2Array = PackedVector2Array()
	for i in range(DIMENSION_COUNT):
		var angle2: float = _get_angle(i)
		var ratio2: float = _current_values[i] / 100.0
		var point: Vector2 = center + Vector2(cos(angle2), sin(angle2)) * chart_radius * ratio2
		data_points.append(point)

	if data_points.size() >= 3:
		var colors: PackedColorArray = PackedColorArray()
		for _c in range(data_points.size()):
			colors.append(fill_color)
		draw_polygon(data_points, colors)

		for i in range(data_points.size()):
			var next_i: int = (i + 1) % data_points.size()
			draw_line(data_points[i], data_points[next_i], outline_color, outline_width, true)

	for i in range(data_points.size()):
		var dot_color: Color = _get_vertex_dot_color(float(_current_values[i]))
		draw_circle(data_points[i], vertex_dot_radius, dot_color)

	var font: Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	for i in range(DIMENSION_COUNT):
		var angle3: float = _get_angle(i)
		var label_anchor: Vector2 = center + Vector2(cos(angle3), sin(angle3)) * (chart_radius + label_offset)

		var label_text: String = tr(DIMENSION_LABEL_KEYS[i])
		var text_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
		var text_offset: Vector2 = Vector2(-text_size.x / 2.0, text_size.y / 4.0)
		_label_tooltip_rects.append(_build_label_tooltip_rect(label_anchor, text_size))
		draw_string(font, label_anchor + text_offset, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, label_color)

		if show_value_labels:
			var value_font_size: int = maxi(12, int(round(float(label_font_size) * 0.5)))
			var value_text: String = "%.0f" % _current_values[i]
			var value_size: Vector2 = font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size)
			var value_offset: Vector2 = Vector2(-value_size.x / 2.0, text_size.y / 4.0 + float(value_font_size) + 2.0)
			draw_string(font, label_anchor + value_offset, value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size, value_label_color)


func _get_tooltip(at_position: Vector2) -> String:
	for i in range(_label_tooltip_rects.size()):
		if _label_tooltip_rects[i].has_point(at_position):
			return tr(DIMENSION_TOOLTIP_KEYS[i])
	return ""


func _build_label_tooltip_rect(label_anchor: Vector2, text_size: Vector2) -> Rect2:
	var padding := Vector2(8.0, 8.0)
	return Rect2(label_anchor - text_size * 0.5 - padding, text_size + padding * 2.0)


func _get_vertex_dot_color(score: float) -> Color:
	if not use_value_vertex_colors:
		return vertex_dot_color
	var ratio: float = clampf(score / 100.0, 0.0, 1.0)
	if ratio < 0.4:
		return low_score_dot_color.lerp(mid_low_score_dot_color, ratio / 0.4)
	if ratio < 0.75:
		return mid_low_score_dot_color.lerp(mid_high_score_dot_color, (ratio - 0.4) / 0.35)
	return mid_high_score_dot_color.lerp(high_score_dot_color, (ratio - 0.75) / 0.25)


func _draw_polygon_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	for i in range(DIMENSION_COUNT):
		var angle_a: float = _get_angle(i)
		var angle_b: float = _get_angle((i + 1) % DIMENSION_COUNT)
		var a: Vector2 = center + Vector2(cos(angle_a), sin(angle_a)) * radius
		var b: Vector2 = center + Vector2(cos(angle_b), sin(angle_b)) * radius
		draw_line(a, b, color, width)


func _get_angle(index: int) -> float:
	return deg_to_rad(-90.0 + float(index) * 360.0 / float(DIMENSION_COUNT))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not auto_minimum_size:
		return
	var edge_padding: float = maxf(60.0, float(label_font_size) * 1.8)
	custom_minimum_size = Vector2(
		(chart_radius + label_offset + edge_padding) * 2.0,
		(chart_radius + label_offset + edge_padding) * 2.0
	)
