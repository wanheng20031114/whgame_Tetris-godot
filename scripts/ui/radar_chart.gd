class_name RadarChart
extends Control

## 六芒星雷达图控件
##
## 使用 _draw() 绘制六维雷达图。
## 功能：
## 1) 6个等距角度（60°间隔）的坐标轴
## 2) 3层背景网格线（33%/66%/100%半径）
## 3) 数据多边形填充（半透明渐变）
## 4) 顶点标签（维度名称，支持i18n）
## 5) 动画插值（数据更新时平滑过渡）
## 6) 高度可配置（颜色、大小、标签字体）

# ==============================================================================
# 常量 & 导出参数（便于调风格只改这里）
# ==============================================================================

## 维度数量
const DIMENSION_COUNT: int = 6

## 维度顺序（与数据字典 key 对应）
const DIMENSION_KEYS: Array = ["speed", "attack", "efficiency", "topology", "holes", "vision"]

## 维度标签翻译键（用于 tr() 多语言）
const DIMENSION_LABEL_KEYS: Array = [
	"TXT_RADAR_SPEED",
	"TXT_RADAR_ATTACK",
	"TXT_RADAR_EFFICIENCY",
	"TXT_RADAR_TOPOLOGY",
	"TXT_RADAR_HOLES",
	"TXT_RADAR_VISION"
]

## ── 可导出的视觉参数 ──
@export_group("雷达图外观")

## 雷达图半径（像素）
@export var chart_radius: float = 140.0

## 背景网格颜色
@export var grid_color: Color = Color(0.3, 0.35, 0.5, 0.4)

## 坐标轴颜色
@export var axis_color: Color = Color(0.35, 0.4, 0.55, 0.6)

## 数据多边形填充颜色
@export var fill_color: Color = Color(0.2, 0.75, 1.0, 0.25)

## 数据多边形边框颜色
@export var outline_color: Color = Color(0.3, 0.85, 1.0, 0.9)

## 数据多边形边框粗细
@export var outline_width: float = 2.5

## 顶点圆点半径
@export var vertex_dot_radius: float = 5.0

## 顶点圆点颜色
@export var vertex_dot_color: Color = Color(0.4, 0.9, 1.0, 1.0)

## 标签字体大小
@export var label_font_size: int = 16

## 标签颜色
@export var label_color: Color = Color(0.8, 0.85, 0.95, 1.0)

## 标签与顶点间距
@export var label_offset: float = 24.0

## 数值标签（显示具体分数数字）
@export var show_value_labels: bool = true

## 数值标签颜色
@export var value_label_color: Color = Color(0.6, 0.9, 1.0, 0.8)

## 网格层数
@export var grid_levels: int = 3

## 动画时长（秒）
@export var animation_duration: float = 0.6

# ==============================================================================
# 数据
# ==============================================================================

## 当前显示的数据（0-100分）
var _current_values: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## 动画目标数据
var _target_values: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## 动画是否正在播放
var _animating: bool = false
## 动画 Tween
var _tween: Tween = null


# ==============================================================================
# 公开接口
# ==============================================================================

## 设置雷达图数据（带动画过渡）。
## values: Dictionary，key为维度名（speed/attack/...），value为0-100分。
func set_data(values: Dictionary, animate: bool = true) -> void:
	for i in range(DIMENSION_COUNT):
		var key: String = DIMENSION_KEYS[i]
		_target_values[i] = clampf(float(values.get(key, 0.0)), 0.0, 100.0)

	if animate and is_inside_tree():
		_start_animation()
	else:
		# 无动画，直接设置
		for i2 in range(DIMENSION_COUNT):
			_current_values[i2] = _target_values[i2]
		queue_redraw()


## 立即设置数据（无动画）。
func set_data_immediate(values: Dictionary) -> void:
	set_data(values, false)


## 获取当前数据的副本。
func get_data() -> Dictionary:
	var result: Dictionary = {}
	for i in range(DIMENSION_COUNT):
		result[DIMENSION_KEYS[i]] = _current_values[i]
	return result


# ==============================================================================
# 动画
# ==============================================================================

func _start_animation() -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	_animating = true
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)

	# 使用自定义 callback 插值每个值
	var start_values: Array = _current_values.duplicate()
	_tween.tween_method(
		func(progress: float) -> void:
			for i in range(DIMENSION_COUNT):
				_current_values[i] = lerpf(start_values[i], _target_values[i], progress)
			queue_redraw(),
		0.0, 1.0, animation_duration
	)
	_tween.finished.connect(func():
		_animating = false
	)


# ==============================================================================
# 绘制
# ==============================================================================

func _draw() -> void:
	var center: Vector2 = size / 2.0

	# ── 1. 绘制背景网格层 ──
	for level in range(1, grid_levels + 1):
		var ratio: float = float(level) / float(grid_levels)
		var r: float = chart_radius * ratio
		_draw_polygon_outline(center, r, grid_color, 1.0)

	# ── 2. 绘制坐标轴 ──
	for i in range(DIMENSION_COUNT):
		var angle: float = _get_angle(i)
		var end_point: Vector2 = center + Vector2(cos(angle), sin(angle)) * chart_radius
		draw_line(center, end_point, axis_color, 1.0)

	# ── 3. 绘制数据多边形 ──
	var data_points: PackedVector2Array = PackedVector2Array()
	for i in range(DIMENSION_COUNT):
		var angle: float = _get_angle(i)
		var ratio2: float = _current_values[i] / 100.0
		var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * chart_radius * ratio2
		data_points.append(point)

	if data_points.size() >= 3:
		# 填充多边形
		var colors: PackedColorArray = PackedColorArray()
		for _c in range(data_points.size()):
			colors.append(fill_color)
		draw_polygon(data_points, colors)

		# 边框
		for i in range(data_points.size()):
			var next_i: int = (i + 1) % data_points.size()
			draw_line(data_points[i], data_points[next_i], outline_color, outline_width, true)

	# ── 4. 绘制顶点圆点 ──
	for i in range(data_points.size()):
		draw_circle(data_points[i], vertex_dot_radius, vertex_dot_color)

	# ── 5. 绘制标签 ──
	var font: Font = ThemeDB.fallback_font
	for i in range(DIMENSION_COUNT):
		var angle2: float = _get_angle(i)
		var label_pos: Vector2 = center + Vector2(cos(angle2), sin(angle2)) * (chart_radius + label_offset)

		# 维度名称标签
		var label_text: String = tr(DIMENSION_LABEL_KEYS[i])
		var text_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
		var text_offset: Vector2 = Vector2(-text_size.x / 2.0, text_size.y / 4.0)
		draw_string(font, label_pos + text_offset, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, label_color)

		# 数值标签
		if show_value_labels:
			var value_text: String = "%.0f" % _current_values[i]
			var val_size: Vector2 = font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size - 2)
			var val_offset: Vector2 = Vector2(-val_size.x / 2.0, text_size.y / 4.0 + label_font_size + 2)
			draw_string(font, label_pos + val_offset, value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size - 2, value_label_color)


## 绘制正多边形的轮廓线（用于背景网格）。
func _draw_polygon_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	for i in range(DIMENSION_COUNT):
		var angle_a: float = _get_angle(i)
		var angle_b: float = _get_angle((i + 1) % DIMENSION_COUNT)
		var a: Vector2 = center + Vector2(cos(angle_a), sin(angle_a)) * radius
		var b: Vector2 = center + Vector2(cos(angle_b), sin(angle_b)) * radius
		draw_line(a, b, color, width)


## 计算第 i 个维度的角度（从正上方开始，顺时针）。
func _get_angle(index: int) -> float:
	# 从 -90°（正上方）开始，每个维度间隔 60°
	return deg_to_rad(-90.0 + float(index) * 360.0 / float(DIMENSION_COUNT))


# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	# 确保控件最小尺寸足够
	custom_minimum_size = Vector2(
		(chart_radius + label_offset + 60) * 2,
		(chart_radius + label_offset + 60) * 2
	)
