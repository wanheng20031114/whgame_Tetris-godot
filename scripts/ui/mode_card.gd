@tool
class_name ModeCard
extends PanelContainer

## 模式磁贴：每个模式一种方块色
## 深色：色彩晕染 + 柔光外发光；浅色：墨色描边 + 硬投影，选中时投影变色并"抬起"

@export_enum("cyan", "amber", "pink", "violet", "accent") var hue: String = "cyan":
	set(v):
		hue = v
		queue_redraw()
@export var index: int = 1:
	set(v):
		index = v
		queue_redraw()
## 左上角大序号 / 右下角箭头圆钮 / 鼠标悬停自动高亮
@export var show_index: bool = true
@export var show_arrow: bool = true
@export var hover_activate: bool = false
@export var corner_radius: int = 28

var active: bool = false:
	set(v):
		active = v
		set_process(true)

var _act: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 24
	pad.content_margin_right = 24
	if show_arrow:
		pad.content_margin_top = 22
	elif show_index:
		pad.content_margin_top = 20
	else:
		pad.content_margin_top = 34
	pad.content_margin_bottom = 18
	add_theme_stylebox_override("panel", pad)
	# 磁贴模式：序号徽章放在标题左侧，给标题留出缩进
	var title := get_node_or_null("VBoxContainer/Title") as Label
	if title and show_index and show_arrow:
		var indent := StyleBoxEmpty.new()
		indent.content_margin_left = 46
		title.add_theme_stylebox_override("normal", indent)
	if not Engine.is_editor_hint():
		UITheme.theme_changed.connect(func(_m): queue_redraw())
		if hover_activate:
			mouse_entered.connect(func(): active = true)
			mouse_exited.connect(func(): active = get_global_rect().has_point(get_global_mouse_position()))


func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if active else 0.0
	_act = move_toward(_act, target, delta * 5.0)
	queue_redraw()
	if is_equal_approx(_act, target) and not active:
		set_process(false)


func _c(key: String) -> Color:
	if Engine.is_editor_hint():
		return {"cyan": Color("#3ddcff"), "amber": Color("#ffb547"), "pink": Color("#ff5c9a"),
			"violet": Color("#8c6bff"), "accent": Color("#c6ff4d"), "surface": Color("#16121f"),
			"surface2": Color("#1f1930"), "border": Color("#352c52"), "text": Color("#f6f3ff"),
			"muted": Color("#a39cc0"), "ink": Color("#06040b"), "accent_text": Color("#130e1f"),
			"cta": Color("#f3ede4"), "cta_text": Color("#25222a")}[key]
	return UITheme.color(key)


func _dark() -> bool:
	return Engine.is_editor_hint() or UITheme.is_dark()


func _box(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing_size = 0.75
	return sb


func _badge(font: Font, center: Vector2, h: Color, dark: bool) -> void:
	draw_circle(center, 17.0, h, true, -1.0, true)
	var num := str(index)
	var fs := 18
	var ts := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, center + Vector2(-ts.x * 0.5, font.get_ascent(fs) * 0.36), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		_c("ink") if dark else Color.WHITE)


func _draw() -> void:
	var e := ease(_act, -2.2)
	var r := Rect2(Vector2.ZERO, size)
	var radius := corner_radius
	var h := _c(hue)
	var dark := _dark()
	var lift := 4.0 * e

	# 底卡：柔和投影，选中时投影加深并上浮
	var base := _box(_c("surface"), radius)
	base.shadow_color = Color(0, 0, 0, (0.4 if dark else 0.10) + 0.08 * e)
	base.shadow_size = int(18 + 14 * e)
	base.shadow_offset = Vector2(0, 6 + 4 * e)
	r.position.y -= lift
	draw_style_box(base, r)
	if e > 0.01:
		var ring := _box(Color(0, 0, 0, 0), radius + 3)
		ring.draw_center = false
		ring.border_color = Color(h, e)
		ring.set_border_width_all(3)
		draw_style_box(ring, r.grow(3.0))

	var font := get_theme_font("font", "TitleLabel")
	if show_arrow:
		# 图示托盘：章节色淡底（像物品槽一样承载图示）
		var tray := _box(_c("surface").lerp(h, (0.14 if dark else 0.18) + 0.08 * e), radius - 8)
		draw_style_box(tray, Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, r.size.y - 82)))
		if show_index:
			_badge(font, Vector2(r.position.x + 41, r.end.y - 36), h, dark)
	elif show_index:
		# 文本卡片：整卡极淡章节色 + 标题左侧序号徽章（标题需留 46px 缩进）
		var wash := _box(Color(h, (0.06 if dark else 0.08) + 0.06 * e), radius)
		draw_style_box(wash, r)
		_badge(font, r.position + Vector2(41, 20 + 16), h, dark)
		return
	else:
		var bar := _box(h, 99)
		draw_style_box(bar, Rect2(r.position + Vector2(24, 14), Vector2(44 + 20 * e, 6)))
		return
	if not show_arrow:
		return
	# 右下角箭头圆钮：深色实心，选中时变章节色
	var cr := 19.0
	var cc := r.end - Vector2(20 + cr, 17 + cr)
	draw_circle(cc, cr, _c("cta").lerp(h, e), true, -1.0, true)
	var arrow_col := _c("cta_text").lerp(_c("ink") if dark else Color.WHITE, e)
	var ax := cc.x - 6.0 + 3.0 * e
	draw_line(Vector2(ax, cc.y), Vector2(ax + 12.0, cc.y), arrow_col, 2.5, true)
	draw_polyline(PackedVector2Array([Vector2(ax + 7.0, cc.y - 5.0), Vector2(ax + 12.0, cc.y), Vector2(ax + 7.0, cc.y + 5.0)]),
		arrow_col, 2.5, true)
