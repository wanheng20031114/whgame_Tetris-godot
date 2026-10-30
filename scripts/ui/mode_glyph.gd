@tool
class_name ModeGlyph
extends Control

## 模式卡片的动态图示：用图形代替说明文字
## MARATHON 方块持续下落堆叠 / GUIDE T 旋入槽位 / MULTIPLAYER 双盘对攻 / REPLAY 时间轴回放

enum Kind { MARATHON, GUIDE, MULTIPLAYER, REPLAY }

@export var kind: Kind = Kind.MARATHON:
	set(v):
		kind = v
		queue_redraw()
## 选中时动画加速、颜色提亮
@export var active: bool = false:
	set(value):
		active = value
		queue_redraw()
## 主色（调色板键）
@export_enum("accent", "cyan", "amber", "pink", "violet") var hue: String = "accent":
	set(value):
		hue = value
		queue_redraw()

var _t: float = 0.0
var _energy: float = 0.0


func _ready() -> void:
	visibility_changed.connect(_update_processing)
	if not Engine.is_editor_hint():
		UITheme.theme_changed.connect(func(_mode): queue_redraw())
	_update_processing()


func _update_processing() -> void:
	set_process(not Engine.is_editor_hint() and is_visible_in_tree())


func _process(delta: float) -> void:
	_energy = move_toward(_energy, 1.0 if active else 0.0, delta * 4.0)
	_t += delta * (1.0 + _energy * 1.2)
	queue_redraw()


func _pal(key: String) -> Color:
	if Engine.is_editor_hint():
		return {"accent": Color("#c6ff4d"), "faint": Color("#5e5681"), "surface3": Color("#2a2342"),
			"text": Color("#f6f3ff"), "danger": Color("#ff4d79"), "warning": Color("#ffb547"),
			"cyan": Color("#3ddcff"), "amber": Color("#ffb547"), "pink": Color("#ff5c9a"), "violet": Color("#8c6bff")}[key]
	return UITheme.color(key)


func _cell(origin: Vector2, c: Vector2, s: float, col: Color) -> void:
	var r := Rect2(origin + c * s, Vector2(s, s)).grow(-s * 0.08)
	draw_rect(r, col)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match kind:
		Kind.MARATHON: _draw_marathon()
		Kind.GUIDE: _draw_guide()
		Kind.MULTIPLAYER: _draw_multiplayer()
		Kind.REPLAY: _draw_replay()


func _accent() -> Color:
	return _pal(hue).lightened(_energy * 0.12)


func _well(origin: Vector2, cols: int, rows: int, s: float) -> void:
	var line := _pal("faint")
	line.a = 0.5
	draw_rect(Rect2(origin, Vector2(cols, rows) * s), _pal("surface3"))
	draw_rect(Rect2(origin, Vector2(cols, rows) * s), line, false, 1.0)


func _draw_marathon() -> void:
	var s := minf(size.x / 8.0, size.y / 9.0)
	var cols := 6
	var rows := 8
	var o := (size - Vector2(cols, rows) * s) * 0.5
	_well(o, cols, rows, s)
	var stack: Array = [Vector2(0, 7), Vector2(1, 7), Vector2(2, 7), Vector2(4, 7), Vector2(5, 7),
			Vector2(0, 6), Vector2(1, 6), Vector2(5, 6), Vector2(0, 5)]
	var stack_col := _pal("faint")
	for c in stack:
		_cell(o, c, s, stack_col)
	# 下落的 L 块：先算出真正落点（撞到堆叠就停），避免穿模
	var piece: Array = [Vector2(3, 0), Vector2(3, 1), Vector2(3, 2), Vector2(2, 2)]
	var land := _landing(piece, stack, rows)
	var cycle := fmod(_t * 0.7, 1.0)
	var fall := clampf(cycle / 0.6, 0.0, 1.0)
	var y := int(floorf(lerpf(-3.0, float(land), fall * fall)))
	var piece_col := _accent()
	if cycle >= 0.6:
		# 锁定瞬间提亮，随后淡出，循环重来
		piece_col = piece_col.lerp(Color.WHITE, clampf(1.0 - (cycle - 0.6) * 8.0, 0.0, 1.0) * 0.6)
		piece_col.a = clampf((1.0 - cycle) / 0.15, 0.0, 1.0)
		y = land
	for c in piece:
		var r: int = int(c.y) + y
		if r >= 0:
			_cell(o, Vector2(c.x, r), s, piece_col)


## 从上往下找第一个会碰撞的位置，返回最低的可放置行
func _landing(piece: Array, stack: Array, rows: int) -> int:
	var y := -4
	while _fits(piece, stack, y + 1, rows):
		y += 1
	return y


func _fits(piece: Array, stack: Array, y: int, rows: int) -> bool:
	for c in piece:
		var r: int = int(c.y) + y
		if r < 0:
			continue
		if r >= rows or stack.has(Vector2(c.x, r)):
			return false
	return true


func _draw_guide() -> void:
	var s := minf(size.x / 6.0, size.y / 6.0)
	var o := (size - Vector2(6, 6) * s) * 0.5
	_well(o, 6, 6, s)
	# 固定堆叠：第 2 列在第 4、5 行留出一个 T-Spin 槽
	var base: Array = [Vector2(0, 5), Vector2(1, 5), Vector2(2, 5), Vector2(4, 5), Vector2(5, 5),
			Vector2(0, 4), Vector2(1, 4), Vector2(4, 4), Vector2(5, 4)]
	var stack_col := _pal("faint")
	var acc := _accent()
	# 一个周期：T 块竖起悬停 → 逆时针转向 → 旋入槽位 → 锁定 → 双消 → 复位
	var p := fmod(_t * 0.4, 1.0)
	var clearing := p >= 0.72 and p < 0.92
	if not clearing:
		for c in base:
			_cell(o, c, s, stack_col)
	# 旋转后的 T 块（朝左的竖向形态）
	var pivot := Vector2(3, 1)
	if p >= 0.3:
		pivot.y = roundf(lerpf(1.0, 4.0, clampf((p - 0.3) / 0.3, 0.0, 1.0)))
	var rel_up: Array = [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, -1)]
	var rel_left: Array = [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(-1, 0)]
	var rel: Array = rel_left if p >= 0.2 else rel_up
	if p < 0.72:
		var piece_col := acc
		if p >= 0.6:
			piece_col = acc.lerp(Color.WHITE, clampf(1.0 - (p - 0.6) / 0.12, 0.0, 1.0) * 0.6)
		for c in rel:
			_cell(o, pivot + c, s, piece_col)
	elif clearing:
		# 双消后，上方剩下的一格落到最底行
		_cell(o, Vector2(3, 5), s, acc)
	# 旋转弧线：只在转向时出现
	var arc_a := clampf(1.0 - absf(p - 0.25) / 0.07, 0.0, 1.0)
	if arc_a > 0.0:
		var arc_col := acc
		arc_col.a = arc_a
		var center := o + (Vector2(3, 1) + Vector2(0.5, 0.5)) * s
		draw_arc(center, s * 1.2, -PI * 0.9, PI * 0.5, 20, arc_col, 2.0, true)
	# 双消闪白
	if p >= 0.72 and p < 0.8:
		var flash := Color.WHITE
		flash.a = (1.0 - (p - 0.72) / 0.08) * 0.85
		draw_rect(Rect2(o + Vector2(0, 4) * s, Vector2(6, 2) * s), flash)


func _draw_multiplayer() -> void:
	var s := minf(size.x / 12.0, size.y / 9.0)
	var w := Vector2(4, 7) * s
	var gap := size.x - w.x * 2.0 - s * 1.0
	var ol := Vector2(s * 0.5, (size.y - w.y) * 0.5)
	var orr := Vector2(ol.x + w.x + gap, ol.y)
	_well(ol, 4, 7, s)
	_well(orr, 4, 7, s)
	var stack := _pal("faint")
	var phase := fmod(_t * 0.6, 1.0)
	var rise := 1 if phase > 0.75 else 0
	for x in 4:
		for y in range(5, 7):
			if not (x == 1 and y == 6):
				_cell(ol, Vector2(x, y), s, stack)
			if x != 2:
				_cell(orr, Vector2(x, y - rise), s, stack)
	# 垃圾行升起
	if rise:
		var g := _pal("danger")
		for x in 4:
			if x != 0:
				_cell(orr, Vector2(x, 6), s, g)
	# 攻击弹道
	var acc := _accent()
	var a := ol + Vector2(w.x, w.y * 0.6)
	var b := orr + Vector2(0, w.y * 0.6)
	var k := clampf(phase / 0.7, 0.0, 1.0)
	var head := a.lerp(b, k) + Vector2(0, -sin(k * PI) * s * 1.6)
	for i in 6:
		var kk := clampf(k - i * 0.04, 0.0, 1.0)
		var p := a.lerp(b, kk) + Vector2(0, -sin(kk * PI) * s * 1.6)
		var c := acc
		c.a = (1.0 - i / 6.0) * (1.0 if phase < 0.7 else 0.0)
		draw_circle(p, s * (0.38 - i * 0.04), c)
	if phase < 0.7:
		draw_circle(head, s * 0.45, acc)


func _draw_replay() -> void:
	var pad := size.x * 0.08
	var top := size.y * 0.18
	var bottom := size.y * 0.72
	var acc := _accent()
	var faint := _pal("faint")
	# 走势折线
	var pts := PackedVector2Array()
	for i in 13:
		var x := lerpf(pad, size.x - pad, i / 12.0)
		var y := lerpf(bottom, top, 0.35 + 0.3 * sin(i * 1.3) + 0.15 * sin(i * 0.5 + 1.0))
		pts.append(Vector2(x, y))
	draw_polyline(pts, faint, 2.0, true)
	var head := fmod(_t * 0.25, 1.0)
	var hx := lerpf(pad, size.x - pad, head)
	var played := PackedVector2Array()
	for p in pts:
		if p.x <= hx:
			played.append(p)
	if played.size() >= 2:
		draw_polyline(played, acc, 3.0, true)
	# 关键点
	for i in [3, 7, 10]:
		var p: Vector2 = pts[i]
		draw_circle(p, 4.0, acc if p.x <= hx else faint)
	# 时间轴与播放头
	var ty := size.y * 0.86
	draw_line(Vector2(pad, ty), Vector2(size.x - pad, ty), faint, 4.0, true)
	draw_line(Vector2(pad, ty), Vector2(hx, ty), acc, 4.0, true)
	draw_line(Vector2(hx, top - 6.0), Vector2(hx, ty), Color(acc, 0.35), 1.0)
	draw_circle(Vector2(hx, ty), 7.0, acc)
