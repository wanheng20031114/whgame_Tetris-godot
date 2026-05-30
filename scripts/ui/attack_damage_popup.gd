class_name AttackDamagePopup
extends Label

const POPUP_SIZE := Vector2(112.0, 54.0)
const FLOAT_DISTANCE := 46.0
const EDGE_PADDING := 8.0
const STYLE_NORMAL := "normal"
const STYLE_TETRIS := "tetris"
const STYLE_TSPIN := "tspin"

var _target_global_position := Vector2.ZERO

static func spawn(parent: Node, board: Board, amount: int, rows_data: Array = [], style: String = STYLE_NORMAL) -> void:
	if parent == null or board == null or amount < 0:
		return

	var popup := AttackDamagePopup.new()
	parent.add_child(popup)
	popup._setup(board, amount, rows_data, style)
	popup._play()

func _setup(board: Board, amount: int, rows_data: Array, style: String) -> void:
	text = "%d" % amount
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 800
	set_as_top_level(true)

	size = POPUP_SIZE
	pivot_offset = POPUP_SIZE * 0.5
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 34)
	add_theme_color_override("font_color", _font_color_for_style(style))
	add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10, 1.0))
	add_theme_constant_override("outline_size", 6)

	var board_origin := board.get_global_transform_with_canvas().origin
	var board_size := Vector2(board.columns * board.cell_size, board.visible_rows * board.cell_size)
	var center := _popup_center_in_board(board, board_size, rows_data)
	var half_size := POPUP_SIZE * 0.5
	global_position = board_origin + center - half_size
	var target_center_y := maxf(EDGE_PADDING + half_size.y, center.y - FLOAT_DISTANCE)
	_target_global_position = board_origin + Vector2(center.x, target_center_y) - half_size
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	scale = Vector2(0.76, 0.76)

func _play() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", _target_global_position, 0.68).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.08)
	tween.chain()
	tween.tween_property(self, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)

func _popup_center_in_board(board: Board, board_size: Vector2, rows_data: Array) -> Vector2:
	var y := board_size.y * 0.42
	if not rows_data.is_empty():
		var total_y := 0.0
		for row_data in rows_data:
			if not (row_data is Dictionary):
				continue
			var row_index := int(row_data.get("row_index", board.buffer_rows))
			var visible_row := clampi(row_index - board.buffer_rows, 0, board.visible_rows - 1)
			total_y += (float(visible_row) + 0.5) * board.cell_size
		if total_y > 0.0:
			y = total_y / float(rows_data.size())

	var half_size := POPUP_SIZE * 0.5
	return Vector2(
		clampf(board_size.x * 0.70, EDGE_PADDING + half_size.x, board_size.x - EDGE_PADDING - half_size.x),
		clampf(y, EDGE_PADDING + half_size.y, board_size.y - EDGE_PADDING - half_size.y)
	)

func _font_color_for_style(style: String) -> Color:
	match style:
		STYLE_TETRIS:
			return PieceData.COLORS[PieceData.Type.I]
		STYLE_TSPIN:
			return PieceData.COLORS[PieceData.Type.T]
		_:
			return Color(1.0, 1.0, 1.0, 1.0)
