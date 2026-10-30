@tool
class_name KeyHints
extends Control

## 键帽式操作提示：用图形代替"使用方向键选择、回车确认"之类的文字
## keys 中每项为一个键帽标签，"|" 表示分组间隔

@export var keys: PackedStringArray = PackedStringArray(["left", "up", "down", "right", "|", "enter"]):
	set(v):
		keys = v
		update_minimum_size()
		queue_redraw()
@export var cap_size: float = 30.0:
	set(value):
		cap_size = value
		update_minimum_size()
		queue_redraw()

var _t: float = 0.0


func _ready() -> void:
	visibility_changed.connect(_update_processing)
	if not Engine.is_editor_hint():
		UITheme.theme_changed.connect(func(_m): queue_redraw())
	_update_processing()


func _update_processing() -> void:
	# Inspector changes redraw via setters; editor previews remain static.
	set_process(not Engine.is_editor_hint() and is_visible_in_tree())


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var w := 0.0
	for k in keys:
		w += 16.0 if k == "|" else _cap_w(k) + 6.0
	return Vector2(w, cap_size + 4.0)


const GLYPHS := ["left", "up", "down", "right", "enter"]


func _cap_w(k: String) -> float:
	if k == "enter":
		return cap_size * 1.5
	if k in GLYPHS:
		return cap_size
	return maxf(cap_size, 14.0 + k.length() * 9.0)


func _glyph(k: String, c: Vector2, col: Color) -> void:
	var r := cap_size * 0.2
	var dir := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}
	if dir.has(k):
		var d: Vector2 = dir[k]
		var n := Vector2(-d.y, d.x)
		draw_line(c - d * r, c + d * r, col, 2.0, true)
		draw_polyline(PackedVector2Array([c + d * r - d * r * 0.7 + n * r * 0.7, c + d * r, c + d * r - d * r * 0.7 - n * r * 0.7]), col, 2.0, true)
	elif k == "enter":
		var a := c + Vector2(r * 1.3, -r)
		var b := c + Vector2(r * 1.3, r * 0.5)
		var e := c + Vector2(-r * 1.3, r * 0.5)
		draw_polyline(PackedVector2Array([a, b, e]), col, 2.0, true)
		draw_polyline(PackedVector2Array([e + Vector2(r * 0.6, -r * 0.6), e, e + Vector2(r * 0.6, r * 0.6)]), col, 2.0, true)


func _c(key: String) -> Color:
	if Engine.is_editor_hint():
		return {"surface2": Color("#1f1930"), "border": Color("#352c52"), "muted": Color("#a39cc0"),
			"lip": Color("#06040b"), "ink": Color("#06040b"), "surface": Color("#16121f"), "surface3": Color("#3a3541")}[key]
	return UITheme.color(key)


func _draw() -> void:
	var font := get_theme_font("font", "EyebrowLabel")
	var x := 0.0
	var dark := Engine.is_editor_hint() or UITheme.is_dark()
	var i := 0
	for k in keys:
		if k == "|":
			x += 16.0
			continue
		var w := _cap_w(k)
		# 依次"按下"的节奏动画
		var phase := fmod(_t * 0.8 - i * 0.22, 2.4)
		var press := clampf(1.0 - absf(phase - 0.15) * 8.0, 0.0, 1.0)
		var lip := 4.0 - 3.0 * press
		var top := Rect2(x, (4.0 - lip), w, cap_size - 4.0)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.anti_aliasing_size = 0.75
		sb.bg_color = _c("surface")
		sb.border_color = _c("surface3")
		sb.border_width_bottom = int(lip)
		draw_style_box(sb, Rect2(top.position, top.size + Vector2(0, lip)))
		if k in GLYPHS:
			_glyph(k, top.position + top.size * 0.5, _c("muted"))
			x += w + 6.0
			i += 1
			continue
		var fs := 15
		var ts := font.get_string_size(k, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var tp := top.position + Vector2((w - ts.x) * 0.5, (top.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
		draw_string(font, tp, k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _c("muted"))
		x += w + 6.0
		i += 1
