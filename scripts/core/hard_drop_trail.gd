class_name HardDropTrail
extends Node2D

## 硬降拖影：方块每一列从起点到落点留下一道渐隐的光柱，0.2 秒内消散

const LIFE := 0.2

var _streaks: Array = [] # [Rect2]
var _color: Color
var _t: float = 0.0


static func spawn(board: Board, piece_type: int, rot: int, col: int, from_row: int, to_row: int) -> void:
	if board == null or to_row <= from_row:
		return
	var trail := HardDropTrail.new()
	board.add_child(trail)
	trail._setup(board, piece_type, rot, col, from_row, to_row)


func _setup(board: Board, piece_type: int, rot: int, col: int, from_row: int, to_row: int) -> void:
	z_index = 5
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_color = PieceData.COLORS[piece_type]
	var cs := board.cell_size
	# 每列取方块在该列最高的格子作为光柱底端
	var tops := {}
	for offset in PieceData.SHAPES[piece_type][rot]:
		var c := col + int(offset.x)
		var r := int(offset.y)
		tops[c] = mini(int(tops.get(c, r)), r)
	for c in tops:
		var y0 := (from_row + int(tops[c]) - board.buffer_rows) * cs
		var y1 := (to_row + int(tops[c]) - board.buffer_rows) * cs
		y0 = maxf(y0, 0.0)
		if y1 > y0:
			_streaks.append(Rect2(c * cs + cs * 0.18, y0, cs * 0.64, y1 - y0))


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / LIFE
	var clear := Color(_color, 0.0)
	var strong := Color(_color.lightened(0.3), 0.45 * k)
	for r in _streaks:
		var x0: float = r.position.x
		var x1: float = r.end.x
		var y0: float = r.position.y
		var y1: float = r.end.y
		draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
			PackedColorArray([clear, clear, strong, strong]))
