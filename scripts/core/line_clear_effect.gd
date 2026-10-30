class_name LineClearEffect
extends Node2D

## 消行特效
##
## 1. 消除行先闪白，再纵向收缩成一道细光线、横向冲出棋盘边缘（"切开"的感觉）
## 2. 每格迸出少量同色碎片，以水平方向为主，带轻微上抛与重力
## 3. 四消 / T-Spin 额外发出一圈冲击波
## 全程 < 0.6s，采用加色混合，消散快，不遮挡后续操作视线。

const FLASH_TIME: float = 0.05
const SLICE_TIME: float = 0.32
const SHARD_LIFE: float = 0.55
const SHARD_GRAVITY: float = 900.0

var _rows: Array = []      # [{y: float, colors: Array}]
var _shards: Array = []    # [{pos, vel, color, life, max_life, size, rot, spin}]
var _rings: Array = []     # [{center, t, max_r, color}]
var _t: float = 0.0
var _cell: float = 30.0
var _width: float = 300.0
var _tint: Color = Color.WHITE
var _power: float = 0.0


func _ready() -> void:
	z_index = 100
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


## cleared_rows_data: Array of { row_index: int, colors: Array[Color or null] }
## tint: 光带主色（普通消行为白色，四消/T-Spin 用对应方块色）
## power: 0~1，强度（行数、连击越高越强）
func setup(cleared_rows_data: Array, cell_size: float, buffer_rows: int, tint: Color = Color.WHITE, power: float = -1.0) -> void:
	_cell = cell_size
	_tint = tint
	var count := cleared_rows_data.size()
	_power = clampf(float(count - 1) / 3.0, 0.0, 1.0) if power < 0.0 else clampf(power, 0.0, 1.0)

	var sum_y := 0.0
	for row_data in cleared_rows_data:
		var vis_row: int = int(row_data["row_index"]) - buffer_rows
		var colors: Array = row_data["colors"]
		_width = colors.size() * cell_size
		var y := (vis_row + 0.5) * cell_size
		sum_y += y
		_rows.append({"y": y, "colors": colors})

		var per_cell := 1 + int(round(_power * 2.0))
		for col in range(colors.size()):
			var c = colors[col]
			if c == null:
				continue
			var cx := (col + 0.5) * cell_size
			# 越靠两侧越往外飞，中间更多向上
			var side := (cx / _width - 0.5) * 2.0
			for _i in range(per_cell):
				var speed := randf_range(160.0, 420.0) * (0.8 + _power * 0.6)
				var dir := Vector2(side + randf_range(-0.6, 0.6), randf_range(-1.1, -0.2)).normalized()
				_shards.append({
					"pos": Vector2(cx + randf_range(-6, 6), y + randf_range(-6, 6)),
					"vel": dir * speed,
					"color": (c as Color).lightened(randf_range(0.0, 0.35)),
					"life": SHARD_LIFE * randf_range(0.55, 1.0),
					"max_life": SHARD_LIFE,
					"size": cell_size * randf_range(0.14, 0.3),
					"rot": randf() * TAU,
					"spin": randf_range(-14.0, 14.0),
				})

	if count >= 4 or _power >= 0.99 or tint != Color.WHITE:
		_rings.append({"center": Vector2(_width * 0.5, sum_y / maxf(count, 1)), "t": 0.0, "max_r": _width * (0.45 + _power * 0.15), "color": tint})

	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var alive := false
	for s in _shards:
		if s["life"] <= 0.0:
			continue
		s["life"] -= delta
		s["vel"] = s["vel"] * pow(0.06, delta) + Vector2(0, SHARD_GRAVITY * delta)
		s["pos"] += s["vel"] * delta
		s["rot"] += s["spin"] * delta
		alive = true
	for r in _rings:
		r["t"] += delta / 0.42
	if not alive and _t > FLASH_TIME + SLICE_TIME and _t > 0.45:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	_draw_rows()
	_draw_rings()
	_draw_shards()


func _draw_rows() -> void:
	for row in _rows:
		var y: float = row["y"]
		if _t < FLASH_TIME:
			# 闪白：整行实心 + 上下柔光
			var a := 1.0 - _t / FLASH_TIME * 0.3
			draw_rect(Rect2(0, y - _cell * 0.5, _width, _cell), Color(1, 1, 1, a))
			_soft_band(y, _cell * 1.6, Color(_tint, 0.35 * a), _width, 0.0)
			continue
		var p := clampf((_t - FLASH_TIME) / SLICE_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - p, 3.0)
		var h := lerpf(_cell, 2.0, e)
		var over := lerpf(0.0, _cell * (1.0 + _power * 1.2), e) # 光线冲出棋盘的长度
		var a := 1.0 - p
		var core := Color(1, 1, 1, a)
		draw_rect(Rect2(-over, y - h * 0.5, _width + over * 2.0, h), Color(_tint.lerp(Color.WHITE, 0.5), a * 0.85))
		draw_rect(Rect2(-over * 0.6, y - 1.0, _width + over * 1.2, 2.0), core)
		_soft_band(y, h + _cell * 1.2 * (1.0 - e), Color(_tint, 0.3 * a), _width, over)


## 一条上下渐隐的柔光带（中心最亮）
func _soft_band(y: float, height: float, color: Color, w: float, over: float) -> void:
	var half := height * 0.5
	if half < 0.5 or w + over * 2.0 < 1.0:
		return
	var clear := Color(color, 0.0)
	var x0 := -over
	var x1 := w + over
	draw_polygon(PackedVector2Array([Vector2(x0, y - half), Vector2(x1, y - half), Vector2(x1, y), Vector2(x0, y)]),
		PackedColorArray([clear, clear, color, color]))
	draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + half), Vector2(x0, y + half)]),
		PackedColorArray([color, color, clear, clear]))


func _draw_rings() -> void:
	for r in _rings:
		var t: float = r["t"]
		if t >= 1.0:
			continue
		var e := 1.0 - pow(1.0 - t, 2.0)
		var radius: float = lerpf(_cell * 0.5, r["max_r"], e)
		var col: Color = r["color"]
		draw_arc(r["center"], radius, 0.0, TAU, 64, Color(col, (1.0 - t) * 0.8), lerpf(6.0, 1.0, t), true)
		draw_arc(r["center"], radius * 0.82, 0.0, TAU, 64, Color(1, 1, 1, (1.0 - t) * 0.3), 1.5, true)


func _draw_shards() -> void:
	for s in _shards:
		if s["life"] <= 0.0:
			continue
		var k: float = clampf(s["life"] / s["max_life"], 0.0, 1.0)
		var size: float = s["size"] * (0.4 + 0.6 * k)
		var c: Color = s["color"]
		c.a = k
		draw_set_transform(s["pos"], s["rot"], Vector2.ONE)
		draw_rect(Rect2(-size * 0.5, -size * 0.5, size, size), c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
