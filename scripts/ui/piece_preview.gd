class_name PiecePreview
extends Control

## 预览槽按出生形状的可见边界居中。棋盘上的活动块由网格锚点定位。
@export_range(1.0, 64.0, 0.5, "or_greater") var max_cell_size := 21.0:
	set(value):
		max_cell_size = value
		queue_redraw()

var piece_type := -1
var _flat_color := Color.TRANSPARENT


func _ready() -> void:
	BlockStyleManager.style_changed.connect(queue_redraw.unbind(1))


## 默认沿用玩家选择的方块样式，复盘传入自己的纯色调色板。
func set_piece(type: int, flat_color: Color = Color.TRANSPARENT) -> void:
	piece_type = type
	_flat_color = flat_color
	queue_redraw()


func get_cell_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if piece_type < 0 or size.x <= 0.0 or size.y <= 0.0:
		return rects
	# 所有出生形状都在 4 × 2 格内，同一槽位切换形状时保持格子等大。
	var cell := minf(max_cell_size, minf(size.x / 4.0, size.y / 2.0))
	var shape: Array = PieceData.SHAPES[piece_type][PieceData.RotationState.SPAWN]
	var bounds := Rect2(shape[0], Vector2.ONE)
	for coord: Vector2 in shape:
		bounds = bounds.merge(Rect2(coord, Vector2.ONE))
	var origin := size * 0.5 - bounds.get_center() * cell
	for coord: Vector2 in shape:
		rects.append(Rect2(origin + coord * cell, Vector2.ONE * cell))
	return rects


func _draw() -> void:
	for rect in get_cell_rects():
		if _flat_color.a > 0.0:
			draw_rect(rect.grow(-minf(0.5, rect.size.x * 0.1)), _flat_color)
		else:
			BlockStyleManager.draw_cell(self, rect, PieceData.COLORS[piece_type])
