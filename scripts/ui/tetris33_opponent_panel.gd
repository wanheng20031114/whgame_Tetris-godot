class_name Tetris33OpponentPanel
extends Control

@export var opponent_index: int = 0
@export var player_name: String = ""

@onready var frame: Panel = %Frame
@onready var name_label: Label = %NameLabel
@onready var badge_label: Label = get_node_or_null("%BadgeLabel")
@onready var metric_label: Label = get_node_or_null("%MetricLabel")
@onready var preview_board: Board = %PreviewBoard
@onready var target_marker: ColorRect = %TargetMarker
@onready var ko_label: Label = %KOLabel

var _is_eliminated: bool = false


func _ready() -> void:
	if preview_board:
		preview_board.cell_size = 6.0
		preview_board.visible_rows = 20
	if target_marker:
		target_marker.visible = false
	if ko_label:
		ko_label.visible = false
	if badge_label:
		badge_label.get_parent().visible = false
	if metric_label:
		metric_label.visible = false
	_refresh_static_labels()


func set_targeted(active: bool) -> void:
	if target_marker:
		target_marker.visible = active and not _is_eliminated


func set_eliminated(active: bool) -> void:
	_is_eliminated = active
	modulate = Color(0.42, 0.42, 0.48, 0.72) if active else Color.WHITE
	if ko_label:
		ko_label.visible = active
	if target_marker and active:
		target_marker.visible = false


func update_from_sample(sample: Dictionary) -> void:
	if sample.has("name"):
		player_name = str(sample["name"])
	if sample.has("index"):
		opponent_index = int(sample["index"])
	if sample.has("eliminated"):
		set_eliminated(bool(sample["eliminated"]))

	if name_label:
		name_label.text = player_name if not player_name.strip_edges().is_empty() else "P%02d" % (opponent_index + 2)

	var board_data: Array = sample.get("visible_board", [])
	if preview_board and not board_data.is_empty():
		preview_board.set_grid_state(_to_full_grid(board_data))


func _refresh_static_labels() -> void:
	if name_label:
		name_label.text = player_name if not player_name.strip_edges().is_empty() else "P%02d" % (opponent_index + 2)
	if badge_label:
		badge_label.text = "#%02d" % (opponent_index + 2)


func _to_full_grid(visible_board: Array) -> Array:
	var full_grid: Array = []
	var cols := 10
	if not visible_board.is_empty() and visible_board[0] is Array:
		cols = int((visible_board[0] as Array).size())

	for _i in range(20):
		var row: Array = []
		row.resize(cols)
		row.fill(0)
		full_grid.append(row)

	for row_data in visible_board:
		full_grid.append((row_data as Array).duplicate())

	return full_grid
