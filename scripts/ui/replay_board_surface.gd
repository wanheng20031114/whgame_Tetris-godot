class_name ReplayBoardSurface
extends Node2D

## 棋盘格复用单一绘制节点，步进时只更新数据。
const CELL := 30.0
var _cells: Array = []
var _colors: Array[Color] = []
var _plan := false

func set_board(cells: Array, colors: Array[Color], plan: bool = false) -> void:
	_cells = cells
	_colors = colors
	_plan = plan
	queue_redraw()

func _draw() -> void:
	if _colors.is_empty():
		return
	# Fill the gaps between cells as well; otherwise the light panel shows
	# through as bright white lines around every square.
	draw_rect(Rect2(0, 0, 300, 600), _colors[0])
	for r in mini(_cells.size(), 20):
		var row: Array = _cells[r]
		for c in mini(row.size(), 10):
			var value := int(row[c])
			var color: Color = _colors[clampi(value, 0, _colors.size() - 1)]
			if _plan and value > 0:
				color = color.darkened(0.35)
			draw_rect(Rect2(Vector2(c, r) * CELL, Vector2.ONE * (CELL - 1.0)), color)
	var grid_color := Color(0.15, 0.15, 0.22, 0.5)
	for r in 21:
		draw_rect(Rect2(0, r * CELL, 300, 1), grid_color)
	for c in 11:
		draw_rect(Rect2(c * CELL, 0, 1, 600), grid_color)
	var border := Color(0.8, 0.5, 0, 0.5) if _plan else Color(0, 0.83, 1, 0.4)
	draw_rect(Rect2(-1, -1, 302, 602), border, false, 2.0 if _plan else 1.0)
