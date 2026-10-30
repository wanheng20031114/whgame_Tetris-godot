@tool
class_name IconButton
extends Button

## 纯图标按钮：矢量图标 + 悬停底座与微动效，不显示文字

@export var icon_name: String = "gear":
	set(v):
		icon_name = v
		queue_redraw()
@export var icon_scale: float = 0.56

var _hover: float = 0.0


func _ready() -> void:
	flat = true
	text = ""
	icon = null
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(44, 44)
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 外部代码可能给按钮写入文字（用作无障碍/提示），这里隐藏不绘制
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(st, Color(0, 0, 0, 0))


func _process(delta: float) -> void:
	var target := 1.0 if (is_hovered() or button_pressed) and not disabled else 0.0
	if not is_equal_approx(_hover, target):
		_hover = move_toward(_hover, target, delta * 6.0)
		queue_redraw()


func _draw() -> void:
	if Engine.is_editor_hint():
		UIIcon.draw(self, icon_name, size * 0.5, minf(size.x, size.y) * icon_scale, Color.WHITE)
		return
	var e := ease(_hover, -2.0)
	UIIcon.draw_chrome(self, Rect2(Vector2.ZERO, size), e, has_focus())
	var col := UIIcon.tint(e) if not disabled else UITheme.color("faint")
	UIIcon.draw(self, icon_name, size * 0.5, minf(size.x, size.y) * icon_scale, col, e)
