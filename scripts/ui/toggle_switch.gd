class_name ToggleSwitch
extends Button

## 胶囊开关：滑块弹性滑动，开启时轨道填充强调色；浅色主题带墨色描边

var _k: float = 0.0
var _hover: float = 0.0
var _toggle_tween: Tween


func _ready() -> void:
	toggle_mode = true
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(64, 34)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	set_meta(UITheme.META_NO_MOTION, true)
	_k = 1.0 if button_pressed else 0.0
	toggled.connect(_on_toggled)
	UITheme.theme_changed.connect(func(_m): queue_redraw())


func _on_toggled(on: bool) -> void:
	if _toggle_tween:
		_toggle_tween.kill()
	_toggle_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toggle_tween.tween_method(func(v: float):
		_k = v
		queue_redraw(), _k, 1.0 if on else 0.0, 0.35)


func _process(delta: float) -> void:
	var target := 1.0 if is_hovered() else 0.0
	if not is_equal_approx(_hover, target):
		_hover = move_toward(_hover, target, delta * 6.0)
		queue_redraw()
	# 外部直接改 button_pressed（不发信号）时同步
	if not is_equal_approx(_k, 1.0 if button_pressed else 0.0) and (_toggle_tween == null or not _toggle_tween.is_running()):
		_k = 1.0 if button_pressed else 0.0
		queue_redraw()


func _draw() -> void:
	var dark := UITheme.is_dark()
	var h := size.y
	var w := minf(size.x, h * 1.9)
	var o := Vector2(size.x - w, 0)
	var r := Rect2(o, Vector2(w, h))
	var k := clampf(_k, 0.0, 1.0)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(h * 0.5))
	sb.anti_aliasing_size = 0.75
	sb.bg_color = UITheme.color("surface3").lerp(UITheme.color("accent"), k)
	draw_style_box(sb, r)
	if has_focus():
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_corner_radius_all(int(h * 0.5) + 3)
		ring.border_color = UITheme.color("accent")
		ring.set_border_width_all(3)
		draw_style_box(ring, r.grow(3.0))
	var pad := 4.0
	var kr := h * 0.5 - pad
	var cx := lerpf(o.x + pad + kr, o.x + w - pad - kr, _k)
	var stretch := 1.0 + 0.18 * _hover
	var knob := Rect2(Vector2(cx - kr * stretch, pad), Vector2(kr * 2.0 * stretch, kr * 2.0))
	var kb := StyleBoxFlat.new()
	kb.set_corner_radius_all(int(kr))
	kb.anti_aliasing_size = 0.75
	kb.bg_color = Color.WHITE
	kb.shadow_color = Color(0, 0, 0, 0.35 if dark else 0.18)
	kb.shadow_size = 4
	kb.shadow_offset = Vector2(0, 1)
	draw_style_box(kb, knob)
	# 开启时滑块里的小对勾
	if k > 0.05:
		var c := knob.get_center()
		var col := Color(UITheme.color("accent") if dark else UITheme.color("accent"), k)
		draw_polyline(PackedVector2Array([c + Vector2(-kr * 0.4, 0), c + Vector2(-kr * 0.1, kr * 0.32), c + Vector2(kr * 0.42, -kr * 0.32)]), col, 2.0, true)
