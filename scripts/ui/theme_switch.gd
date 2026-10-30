class_name ThemeSwitch
extends Control

## 深浅主题开关：滑块在太阳 / 月亮之间滑动并形变，点击后以开关位置为圆心切换主题

var _k: float = 0.0 # 0 = 浅色(太阳)  1 = 深色(月亮)
var _tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(76, 38)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_k = 1.0 if UITheme.is_dark() else 0.0
	UITheme.theme_changed.connect(_on_theme_changed)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if click or event.is_action_pressed("ui_accept"):
		accept_event()
		if ButtonSfx:
			ButtonSfx.play_click()
		UITheme.toggle_mode(_knob_center() + get_global_rect().position)


func _on_theme_changed(mode: String) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_k, _k, 1.0 if mode == "dark" else 0.0, 0.45)


func _set_k(v: float) -> void:
	_k = v
	queue_redraw()


func _knob_center() -> Vector2:
	var r := size.y * 0.5
	return Vector2(lerpf(r, size.x - r, _k), r)


func _draw() -> void:
	var r := size.y * 0.5
	var track := Color("#ffd166").lerp(Color("#2b3a67"), clampf(_k, 0.0, 1.0))
	draw_rect(Rect2(Vector2(r, 0), Vector2(size.x - 2.0 * r, size.y)), track)
	draw_circle(Vector2(r, r), r, track)
	draw_circle(Vector2(size.x - r, r), r, track)
	if has_focus():
		var ring := UITheme.color("accent")
		draw_arc(Vector2(r, r), r + 3.0, PI * 0.5, PI * 1.5, 20, ring, 2.0, true)
		draw_arc(Vector2(size.x - r, r), r + 3.0, -PI * 0.5, PI * 0.5, 20, ring, 2.0, true)
		draw_line(Vector2(r, -3.0), Vector2(size.x - r, -3.0), ring, 2.0)
		draw_line(Vector2(r, size.y + 3.0), Vector2(size.x - r, size.y + 3.0), ring, 2.0)

	# 背景小星星（深色时出现）
	var star := Color(1, 1, 1, clampf(_k, 0.0, 1.0) * 0.8)
	draw_circle(Vector2(size.x * 0.24, size.y * 0.32), 1.5, star)
	draw_circle(Vector2(size.x * 0.36, size.y * 0.66), 1.0, star)
	draw_circle(Vector2(size.x * 0.18, size.y * 0.7), 1.2, star)

	# 滑块：太阳（带光芒）→ 月亮（被遮挡的圆）
	var c := _knob_center()
	var kr := r - 5.0
	var sun_rays := 1.0 - clampf(_k, 0.0, 1.0)
	for i in 8:
		var a := i * TAU / 8.0 + _k * PI
		var ray_col := Color(1, 1, 1, sun_rays * 0.9)
		draw_line(c + Vector2.from_angle(a) * (kr * 0.78), c + Vector2.from_angle(a) * (kr * 1.0), ray_col, 2.0, true)
	var body_r := lerpf(kr * 0.55, kr, clampf(_k, 0.0, 1.0))
	draw_circle(c, body_r, Color("#fff4d6").lerp(Color("#e8ecff"), clampf(_k, 0.0, 1.0)))
	# 月牙遮罩：用轨道色的圆从右上方压上去
	if _k > 0.02:
		var bite := c + Vector2(body_r * 0.55, -body_r * 0.35) * clampf(_k, 0.0, 1.0) + Vector2(body_r * 0.6, -body_r * 0.4) * (1.0 - clampf(_k, 0.0, 1.0))
		draw_circle(bite, body_r * 0.78 * clampf(_k, 0.0, 1.0), track)
