class_name UIIcon
extends RefCounted

## 矢量线性图标集（2px 描边风格），替代位图图标，随主题着色
## 用法：UIIcon.draw(canvas_item, "gear", center, size, color, anim)
## anim 为 0..1 的悬停动画量，部分图标据此做微动效


static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color, anim: float = 0.0, w: float = 2.0) -> void:
	match kind:
		"gear": _gear(ci, c, s, col, anim, w)
		"blocks": _blocks(ci, c, s, col, anim)
		"chart": _chart(ci, c, s, col, anim, w)
		"back": _back(ci, c, s, col, anim, w)
		"close": _close(ci, c, s, col, anim, w)
		"user": _user(ci, c, s, col, w)
		"play": _play(ci, c, s, col, anim)
		"refresh": _refresh(ci, c, s, col, anim, w)
		"plus": _plus(ci, c, s, col, anim, w)
		"link": _link(ci, c, s, col, w)
		"prev": _skip(ci, c, s, col, -1, false)
		"next": _skip(ci, c, s, col, 1, false)
		"first": _skip(ci, c, s, col, -1, true)
		"last": _skip(ci, c, s, col, 1, true)
		"sun": _sun(ci, c, s, col, anim, w)
		"moon": _moon(ci, c, s, col, w)


static func _gear(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	var teeth := 8
	var r_out := s * 0.46
	var r_in := s * 0.34
	var rot := anim * PI / 4.0
	var pts := PackedVector2Array()
	for i in teeth:
		var base := TAU * i / teeth + rot
		var half := TAU / teeth
		for k in [-0.36, -0.2, 0.2, 0.36]:
			var r := r_out if absf(k) < 0.3 else r_in
			pts.append(c + Vector2.from_angle(base + half * k) * r)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, w, true)
	ci.draw_arc(c, s * 0.14, 0.0, TAU, 24, col, w, true)


static func _blocks(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float) -> void:
	var cell := s * 0.27
	var gap := s * 0.05
	var keys := ["cyan", "violet", "pink", "amber"]
	var cells := [Vector2(-1, -0.5), Vector2(0, -0.5), Vector2(1, -0.5), Vector2(0, 0.5)]
	for i in 4:
		var hop := -sin(clampf(anim * 1.6 - i * 0.18, 0.0, 1.0) * PI) * s * 0.12
		var p: Vector2 = c + cells[i] * (cell + gap) - Vector2(cell, cell) * 0.5 + Vector2(0, hop)
		var hue: Color = UITheme.color(keys[i]) if UITheme else col
		var sb := StyleBoxFlat.new()
		sb.bg_color = hue
		sb.set_corner_radius_all(int(cell * 0.28))
		sb.anti_aliasing_size = 0.75
		ci.draw_style_box(sb, Rect2(p, Vector2(cell, cell)))


static func _chart(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	var base := c.y + s * 0.36
	var hs := [0.38, 0.62, 0.48]
	for i in 3:
		var x := c.x + (i - 1) * s * 0.28
		var h: float = s * (hs[i] + 0.12 * anim * sin(i * 2.1 + 1.0))
		ci.draw_line(Vector2(x, base), Vector2(x, base - h), col, w * 1.6, true)
	ci.draw_line(Vector2(c.x - s * 0.44, base + s * 0.08), Vector2(c.x + s * 0.44, base + s * 0.08), col, w, true)


static func _back(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	var dx := -anim * s * 0.08
	var tip := c + Vector2(-s * 0.32 + dx, 0)
	ci.draw_line(tip, c + Vector2(s * 0.34, 0), col, w, true)
	ci.draw_polyline(PackedVector2Array([tip + Vector2(s * 0.26, -s * 0.26), tip, tip + Vector2(s * 0.26, s * 0.26)]), col, w, true)


static func _close(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	var r := s * 0.3
	var a := anim * PI * 0.5
	for k in [PI * 0.25, PI * 0.75]:
		var d := Vector2.from_angle(k + a) * r
		ci.draw_line(c - d, c + d, col, w, true)


static func _user(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_arc(c + Vector2(0, -s * 0.14), s * 0.18, 0.0, TAU, 24, col, w, true)
	ci.draw_arc(c + Vector2(0, s * 0.46), s * 0.36, PI * 1.15, PI * 1.85, 20, col, w, true)


static func _play(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float) -> void:
	var r := s * (0.34 + 0.04 * anim)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r), c + Vector2(r, 0), c + Vector2(-r * 0.7, r)]), col)


static func _refresh(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	var r := s * 0.32
	var a0 := -PI * 0.2 + anim * PI
	ci.draw_arc(c, r, a0, a0 + PI * 1.6, 28, col, w, true)
	var tip := c + Vector2.from_angle(a0 + PI * 1.6) * r
	var tan := Vector2.from_angle(a0 + PI * 1.6 + PI * 0.5)
	var nrm := Vector2.from_angle(a0 + PI * 1.6)
	ci.draw_colored_polygon(PackedVector2Array([tip + tan * s * 0.16, tip + nrm * s * 0.12, tip - nrm * s * 0.12]), col)


static func _plus(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	var r := s * 0.3
	var a := anim * PI * 0.5
	ci.draw_line(c - Vector2.from_angle(a) * r, c + Vector2.from_angle(a) * r, col, w, true)
	ci.draw_line(c - Vector2.from_angle(a + PI * 0.5) * r, c + Vector2.from_angle(a + PI * 0.5) * r, col, w, true)


static func _link(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	for k in [-1.0, 1.0]:
		var o := c + Vector2(k * s * 0.13, -k * s * 0.13)
		ci.draw_arc(o, s * 0.16, 0.0, TAU, 20, col, w, true)


static func _skip(ci: CanvasItem, c: Vector2, s: float, col: Color, dir: int, bar: bool) -> void:
	var r := s * 0.26
	var tri := PackedVector2Array([c + Vector2(-r * dir, -r), c + Vector2(r * dir, 0), c + Vector2(-r * dir, r)])
	ci.draw_colored_polygon(tri, col)
	if bar:
		var x := c.x + r * dir + dir * s * 0.06
		ci.draw_line(Vector2(x, c.y - r), Vector2(x, c.y + r), col, s * 0.1, true)


static func _sun(ci: CanvasItem, c: Vector2, s: float, col: Color, anim: float, w: float) -> void:
	ci.draw_arc(c, s * 0.17, 0.0, TAU, 24, col, w, true)
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0 + anim * 0.6)
		ci.draw_line(c + d * s * 0.29, c + d * s * 0.42, col, w, true)


static func _moon(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_arc(c, s * 0.32, PI * 0.35, PI * 1.95, 28, col, w, true)
	ci.draw_arc(c + Vector2(s * 0.16, -s * 0.1), s * 0.24, PI * 0.55, PI * 1.62, 20, col, w, true)


## 图标按钮底座：常态为色块圆钮，悬停时变为深色（浅色主题）/奶油色（深色主题）实心圆
static func draw_chrome(ci: CanvasItem, rect: Rect2, hover: float, focused: bool) -> void:
	if not UITheme:
		return
	var d := minf(rect.size.x, rect.size.y)
	var r := Rect2(rect.get_center() - Vector2(d, d) * 0.5, Vector2(d, d))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.color("surface2").lerp(UITheme.color("cta"), clampf(hover, 0.0, 1.0))
	sb.set_corner_radius_all(int(d * 0.5))
	sb.corner_detail = 12
	sb.anti_aliasing_size = 0.75
	if hover > 0.01:
		sb.shadow_color = Color(UITheme.color("shadow"), UITheme.color("shadow").a * hover)
		sb.shadow_size = int(10 * hover)
		sb.shadow_offset = Vector2(0, 3)
	ci.draw_style_box(sb, r)
	if focused:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = UITheme.color("accent")
		ring.set_border_width_all(3)
		ring.set_corner_radius_all(int(d * 0.5) + 3)
		ring.corner_detail = 12
		ci.draw_style_box(ring, r.grow(3.0))


## 图标颜色：常态正文色，悬停过渡到主操作文字色
static func tint(hover: float) -> Color:
	if not UITheme:
		return Color.WHITE
	return UITheme.color("text").lerp(UITheme.color("cta_text"), clampf(hover, 0.0, 1.0))
