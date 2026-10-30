class_name Tetris33OpponentPanel
extends Control

@export var opponent_index: int = 0
@export var player_name: String = ""

@onready var frame: Panel = %Frame
@onready var name_back: Panel = $Frame/NameBack
@onready var name_label: Label = %NameLabel
@onready var badge_label: Label = get_node_or_null("%BadgeLabel")
@onready var metric_label: Label = get_node_or_null("%MetricLabel")
@onready var preview_board: Board = %PreviewBoard
@onready var target_marker: ColorRect = %TargetMarker
@onready var ko_label: Label = %KOLabel

var _is_eliminated: bool = false
var _content_inset: float = 4.0
var _header_height: float = 19.0
var _board_gap: float = 4.0
var _bottom_inset: float = 9.0


func _ready() -> void:
	if preview_board:
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
	resized.connect(_layout_contents)
	_layout_contents()


func configure_layout(columns: int) -> void:
	var card_sizes := [Vector2(280, 568), Vector2(168, 320), Vector2(112, 208), Vector2(84, 156)]
	var font_sizes := [20, 14, 12, 10]
	var header_heights := [32.0, 24.0, 22.0, 19.0]
	var insets := [8.0, 6.0, 4.0, 4.0]
	var profile := columns - 1
	custom_minimum_size = card_sizes[profile]
	name_label.add_theme_font_size_override("font_size", font_sizes[profile])
	ko_label.add_theme_font_size_override("font_size", [64, 48, 36, 32][profile])
	_header_height = header_heights[profile]
	_content_inset = insets[profile]
	_board_gap = 8.0 if columns == 1 else 4.0
	_bottom_inset = 9.0 if columns == 4 else _content_inset
	_layout_contents()


func _layout_contents() -> void:
	pivot_offset = size * 0.5
	name_back.offset_left = _content_inset
	name_back.offset_right = -_content_inset
	name_back.offset_top = _content_inset
	name_back.offset_bottom = _content_inset + _header_height
	var board_top := name_back.offset_bottom + _board_gap
	var available := Vector2(size.x - _content_inset * 2.0, size.y - board_top - _bottom_inset)
	preview_board.cell_size = minf(available.x / 10.0, available.y / 20.0)
	var board_size := Vector2(10, 20) * preview_board.cell_size
	preview_board.position = Vector2((size.x - board_size.x) * 0.5, board_top + (available.y - board_size.y) * 0.5)
	preview_board.queue_redraw()


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
		name_label.tooltip_text = name_label.text

	var board_data: Array = sample.get("visible_board", [])
	if preview_board and not board_data.is_empty():
		preview_board.set_grid_state(_to_full_grid(board_data))


func _refresh_static_labels() -> void:
	if name_label:
		name_label.text = player_name if not player_name.strip_edges().is_empty() else "P%02d" % (opponent_index + 2)
		name_label.tooltip_text = name_label.text
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
