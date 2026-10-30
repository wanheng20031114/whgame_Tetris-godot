class_name BlockStylePreview
extends Control

@export var style_id := "inner":
	set(value):
		style_id = value
		queue_redraw()

const SAMPLE_COLORS := [
	Color("00e5ff"),
	Color("ffd21f"),
	Color("ff4d57"),
	Color("6df06b"),
]

const SAMPLE_CELLS := [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(2, 1),
]


func _ready() -> void:
	custom_minimum_size = Vector2(96, 72)


func _draw() -> void:
	var cell := minf(size.x / 4.0, size.y / 3.0)
	var origin := Vector2((size.x - cell * 3.0) * 0.5, (size.y - cell * 2.0) * 0.5)
	for i in range(SAMPLE_CELLS.size()):
		var coord: Vector2i = SAMPLE_CELLS[i]
		var rect := Rect2(origin + Vector2(coord.x * cell, coord.y * cell), Vector2(cell, cell))
		_draw_block_cell(rect, SAMPLE_COLORS[i])


func _draw_block_cell(rect: Rect2, color: Color) -> void:
	BlockStyleManager.draw_cell(self, rect, color, style_id)
