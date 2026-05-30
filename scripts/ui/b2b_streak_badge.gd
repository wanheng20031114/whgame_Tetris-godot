class_name B2BStreakBadge
extends Label

const NODE_NAME := "B2BStreakBadgeAuto"
const BADGE_SIZE := Vector2(164.0, 78.0)
const EDGE_PADDING := 8.0

var _tween: Tween
var _last_chain_count: int = 0

static func show_badge(parent: Node, board: Board, chain_count: int) -> void:
	if parent == null or board == null or chain_count < 2:
		return

	var badge := parent.get_node_or_null(NODE_NAME) as B2BStreakBadge
	if badge == null:
		badge = B2BStreakBadge.new()
		badge.name = NODE_NAME
		parent.add_child(badge)

	badge._show_persistent(board, chain_count)

static func hide_existing(parent: Node) -> void:
	if parent == null:
		return
	var badge := parent.get_node_or_null(NODE_NAME) as B2BStreakBadge
	if badge:
		badge._hide_now()

func _show_persistent(board: Board, chain_count: int) -> void:
	text = "B2B x%d" % chain_count
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 790
	set_as_top_level(true)

	size = BADGE_SIZE
	pivot_offset = BADGE_SIZE * 0.5
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 31)
	add_theme_color_override("font_color", Color(1.0, 0.94, 0.40, 1.0))
	add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.12, 1.0))
	add_theme_constant_override("outline_size", 7)
	global_position = _position_for_board(board)
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	if _tween and _tween.is_running():
		_tween.kill()

	if _last_chain_count == chain_count:
		scale = Vector2.ONE
		return

	_last_chain_count = chain_count
	scale = Vector2(0.92, 0.92)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _hide_now() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	scale = Vector2.ONE
	_last_chain_count = 0

func _position_for_board(board: Board) -> Vector2:
	var board_origin := board.get_global_transform_with_canvas().origin
	var board_size := Vector2(board.columns * board.cell_size, board.visible_rows * board.cell_size)
	var viewport_size := get_viewport_rect().size
	var gap := maxf(24.0, board.cell_size * 1.65)
	var x := board_origin.x - BADGE_SIZE.x - gap
	var y := board_origin.y + board_size.y * 0.54
	return Vector2(
		clampf(x, EDGE_PADDING, viewport_size.x - BADGE_SIZE.x - EDGE_PADDING),
		clampf(y, EDGE_PADDING, viewport_size.y - BADGE_SIZE.y - EDGE_PADDING)
	)
