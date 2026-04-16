class_name Board
extends Node2D

@export_group("Board")
@export var columns: int = 10
@export var visible_rows: int = 20
var buffer_rows: int = 20
var total_rows: int:
	get: return visible_rows + buffer_rows
@export var cell_size: float = 30.0

const BG_COLOR := Color("0d0d14")
const GRID_LINE_COLOR := Color("1a1a2e")
const BORDER_COLOR := Color("3a3a5c")

var grid: Array = []
const EMPTY_CELL_TYPE: int = 0
const GARBAGE_CELL_TYPE: int = 8
var last_hole_col: int = -1

var danger_warning_active: bool = false
var _danger_pulse_time: float = 0.0

func _ready() -> void:
	_init_grid()
	set_process(false)

func _process(delta: float) -> void:
	if not danger_warning_active:
		return
	_danger_pulse_time += delta
	queue_redraw()

func _init_grid() -> void:
	grid.clear()
	for _r in range(total_rows):
		grid.append(_create_empty_row())

func _create_empty_row() -> Array:
	var row: Array = []
	row.resize(columns)
	row.fill(null)
	return row

func is_valid_position(type: PieceData.Type, rot_state: PieceData.RotationState, center_col: int, center_row: int) -> bool:
	var shape = PieceData.SHAPES[type][rot_state]
	for offset in shape:
		var col: int = center_col + int(offset.x)
		var row: int = center_row + int(offset.y)
		if col < 0 or col >= columns:
			return false
		if row >= total_rows:
			return false
		if row < 0:
			continue
		if grid[row][col] != null:
			return false
	return true

func lock_piece(type: PieceData.Type, rot_state: PieceData.RotationState, center_col: int, center_row: int, color: Color) -> void:
	var shape = PieceData.SHAPES[type][rot_state]
	for offset in shape:
		var col: int = center_col + int(offset.x)
		var row: int = center_row + int(offset.y)
		if row >= 0 and row < total_rows and col >= 0 and col < columns:
			grid[row][col] = color
	queue_redraw()

func clear_lines() -> int:
	var result: Dictionary = clear_lines_with_data()
	return result["cleared"]

## 执行消行并返回详细数据，用于粒子特效等视觉反馈。
## 返回: { "cleared": int, "rows_data": Array[{ "row_index": int, "colors": Array }] }
func clear_lines_with_data() -> Dictionary:
	var new_grid: Array = []
	var cleared: int = 0
	var rows_data: Array = []

	for row in range(total_rows):
		if _is_row_full(row):
			cleared += 1
			# 记录被消除行的颜色信息（在移除前）
			var colors: Array = []
			for col in range(columns):
				colors.append(grid[row][col])
			rows_data.append({"row_index": row, "colors": colors})
		else:
			new_grid.append(grid[row])

	for _i in range(cleared):
		new_grid.insert(0, _create_empty_row())

	grid = new_grid
	queue_redraw()
	return {"cleared": cleared, "rows_data": rows_data}

func _is_row_full(row: int) -> bool:
	for col in range(columns):
		if grid[row][col] == null:
			return false
	return true

func _draw() -> void:
	var board_w: float = columns * cell_size
	var board_h: float = visible_rows * cell_size

	draw_rect(Rect2(Vector2.ZERO, Vector2(board_w, board_h)), BG_COLOR)

	for col in range(columns + 1):
		var x: float = col * cell_size
		draw_line(Vector2(x, 0), Vector2(x, board_h), GRID_LINE_COLOR, 1.0)
	for row in range(visible_rows + 1):
		var y: float = row * cell_size
		draw_line(Vector2(0, y), Vector2(board_w, y), GRID_LINE_COLOR, 1.0)

	for row in range(buffer_rows, total_rows):
		for col in range(columns):
			var color = grid[row][col]
			if color != null:
				var vis_row: int = row - buffer_rows
				var rect := Rect2(Vector2(col * cell_size, vis_row * cell_size), Vector2(cell_size, cell_size))
				draw_rect(rect, color)
				draw_rect(rect, color.darkened(0.3), false, 2.0)
				var inner := rect.grow(-4.0)
				draw_rect(inner, color.lightened(0.4), false, 1.0)

	draw_rect(Rect2(Vector2(-1, -1), Vector2(board_w + 2, board_h + 2)), BORDER_COLOR, false, 2.0)
	if danger_warning_active:
		var pulse := 0.5 + 0.5 * sin(_danger_pulse_time * 4.0)
		var outer_color := Color(1.0, 0.10, 0.10, lerpf(0.30, 0.85, pulse))
		draw_rect(Rect2(Vector2(-3, -3), Vector2(board_w + 6, board_h + 6)), outer_color, false, 8.0)
		var inner_color := Color(1.0, 0.22, 0.22, lerpf(0.18, 0.50, pulse))
		draw_rect(Rect2(Vector2(1, 1), Vector2(board_w - 2, board_h - 2)), inner_color, false, 4.0)

func get_grid_state() -> Array:
	var state := []
	for r in range(total_rows):
		var row_data := []
		for c in range(columns):
			var cell_color = grid[r][c]
			if cell_color == null:
				row_data.append(EMPTY_CELL_TYPE)
			else:
				var type_idx := -1
				for t in PieceData.COLORS:
					if PieceData.COLORS[t].is_equal_approx(cell_color):
						type_idx = t
						break
				if type_idx == -1:
					row_data.append(GARBAGE_CELL_TYPE)
				else:
					row_data.append(int(type_idx) + 1)
		state.append(row_data)
	return state

func set_grid_state(data: Array) -> void:
	if data.size() != total_rows:
		return

	for r in range(total_rows):
		var row_data: Array = data[r]
		for c in range(columns):
			var type_idx: int = row_data[c]
			if type_idx == EMPTY_CELL_TYPE:
				grid[r][c] = null
			elif type_idx == GARBAGE_CELL_TYPE:
				grid[r][c] = Color(0.45, 0.45, 0.45)
			else:
				var piece_type: int = type_idx - 1
				if PieceData.COLORS.has(piece_type):
					grid[r][c] = PieceData.COLORS[piece_type]
				else:
					grid[r][c] = Color(0.45, 0.45, 0.45)

	queue_redraw()

func add_garbage_lines(amount: int) -> void:
	if amount <= 0:
		return

	for _i in range(amount):
		grid.pop_front()

	# 50% keep previous hole, 50% reroll (10 columns => +5% same column from reroll)
	var hole_col: int = last_hole_col
	if hole_col < 0 or randf() < 0.5:
		hole_col = randi() % columns
	last_hole_col = hole_col

	var garbage_color: Color = Color(0.45, 0.45, 0.45)
	for _j in range(amount):
		var new_row: Array = _create_empty_row()
		for c in range(columns):
			if c != hole_col:
				new_row[c] = garbage_color
		grid.append(new_row)

	queue_redraw()

func has_blocks_in_top_rows(row_count: int) -> bool:
	if row_count <= 0:
		return false
	var check_rows: int = mini(row_count, total_rows)
	for r in range(check_rows):
		for c in range(columns):
			if grid[r][c] != null:
				return true
	return false

func has_blocks_near_visible_top(row_count: int) -> bool:
	if row_count <= 0:
		return false
	var check_rows: int = mini(row_count, visible_rows)
	var start_row: int = buffer_rows
	var end_row: int = mini(buffer_rows + check_rows, total_rows)
	for r in range(start_row, end_row):
		for c in range(columns):
			if grid[r][c] != null:
				return true
	return false

func set_danger_warning(active: bool) -> void:
	if danger_warning_active == active:
		return
	danger_warning_active = active
	if danger_warning_active:
		_danger_pulse_time = 0.0
	set_process(danger_warning_active)
	queue_redraw()
