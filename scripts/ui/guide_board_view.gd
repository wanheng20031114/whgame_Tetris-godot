class_name GuideBoardView
extends Control

const EMPTY := 0
const GARBAGE := 8

var columns: int = 10
var rows: int = 20
var grid: Array = []
var active_piece: Dictionary = {}
var target_cells: Array = []
var highlight_cells: Array = []
var highlight_rows: Array = []
var show_ghost: bool = true
var ghost_row: int = -1
var pulse: float = 0.0
var effect_text: String = ""
var effect_color: Color = Color(1.0, 0.92, 0.18, 1.0)

## 聚焦状态：玩家点击棋盘后聚焦，聚焦时可用键盘操作
var focused: bool = false

## 是否显示旋转中心点（红色圆圈）
var show_center_point: bool = false

## 消行特效
var _clear_particles: Array = []
var _clear_flash_timer: float = 0.0
var _clear_flash_rows: Array = []

const PARTICLE_COUNT_PER_CELL: int = 4
const PARTICLE_LIFETIME: float = 0.65
const PARTICLE_SIZE: float = 4.0
const EXPLOSION_SPEED: float = 200.0
const PARTICLE_GRAVITY: float = 400.0
const FLASH_DURATION: float = 0.08

const CELL_COLORS: Array[Color] = [
	Color(0.08, 0.08, 0.12, 1.0),
	Color(0.0, 0.85, 0.85, 1.0),
	Color(1.0, 0.85, 0.0, 1.0),
	Color(0.6, 0.0, 0.8, 1.0),
	Color(0.0, 0.8, 0.0, 1.0),
	Color(0.9, 0.1, 0.1, 1.0),
	Color(0.1, 0.3, 0.9, 1.0),
	Color(1.0, 0.55, 0.0, 1.0),
	Color(0.45, 0.45, 0.45, 1.0),
]


func _ready() -> void:
	set_process(true)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	pulse += delta

	# 更新消行特效
	if _clear_flash_timer > 0.0:
		_clear_flash_timer -= delta

	var alive := 0
	for p in _clear_particles:
		if p["life"] <= 0.0:
			continue
		alive += 1
		p["life"] -= delta
		p["vel"].y += PARTICLE_GRAVITY * delta
		p["pos"] += p["vel"] * delta
		p["rot"] += p["rot_speed"] * delta

	if alive == 0 and _clear_flash_timer <= 0.0:
		_clear_particles.clear()
		_clear_flash_rows.clear()

	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		focused = true
		grab_focus()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_EXIT:
		focused = false


func set_state(
	new_grid: Array,
	new_active_piece: Dictionary = {},
	new_target_cells: Array = [],
	new_highlight_rows: Array = [],
	new_highlight_cells: Array = []
) -> void:
	grid = new_grid
	active_piece = new_active_piece
	target_cells = new_target_cells
	highlight_rows = new_highlight_rows
	highlight_cells = new_highlight_cells
	ghost_row = _find_ghost_row()
	queue_redraw()


func clear_state() -> void:
	grid = []
	active_piece = {}
	target_cells = []
	highlight_rows = []
	highlight_cells = []
	ghost_row = -1
	queue_redraw()


func set_effect_text(text: String, color: Color = Color(1.0, 0.92, 0.18, 1.0)) -> void:
	effect_text = text
	effect_color = color
	queue_redraw()


## 播放消行特效（白色闪光 + 粒子爆炸），不播放音效
func play_clear_effect(cleared_rows: Array) -> void:
	_clear_particles.clear()
	_clear_flash_rows = cleared_rows.duplicate()
	_clear_flash_timer = FLASH_DURATION

	var board_rect := _board_rect()
	var cell := board_rect.size.x / float(columns)

	for row_idx in cleared_rows:
		if row_idx < 0 or row_idx >= rows:
			continue
		for col in range(columns):
			var center_x: float = board_rect.position.x + col * cell + cell * 0.5
			var center_y: float = board_rect.position.y + row_idx * cell + cell * 0.5

			# 获取该格子的颜色
			var cell_value := EMPTY
			if row_idx < grid.size() and col < (grid[row_idx] as Array).size():
				cell_value = int(grid[row_idx][col])
			var base_color := _piece_color(cell_value) if cell_value != EMPTY else Color(0.7, 0.7, 0.8, 1.0)

			for _i in range(PARTICLE_COUNT_PER_CELL):
				var angle: float = randf() * TAU
				var speed: float = randf_range(EXPLOSION_SPEED * 0.3, EXPLOSION_SPEED)
				var vel := Vector2(cos(angle) * speed, sin(angle) * speed - 80.0)

				var c: Color = base_color
				var brightness_shift: float = randf_range(-0.15, 0.25)
				if brightness_shift > 0:
					c = c.lightened(brightness_shift)
				else:
					c = c.darkened(-brightness_shift)

				var p_size: float = randf_range(PARTICLE_SIZE * 0.5, PARTICLE_SIZE * 1.5)

				_clear_particles.append({
					"pos": Vector2(center_x + randf_range(-3, 3), center_y + randf_range(-3, 3)),
					"vel": vel,
					"color": c,
					"life": PARTICLE_LIFETIME * randf_range(0.7, 1.0),
					"max_life": PARTICLE_LIFETIME,
					"size": p_size,
					"rot": randf() * TAU,
					"rot_speed": randf_range(-10.0, 10.0)
				})


func _draw() -> void:
	var board_rect := _board_rect()

	# 聚焦状态边框颜色
	var border_glow_color := Color(0.0, 0.85, 1.0, 0.65) if focused else Color(0.0, 0.83, 1.0, 0.38)
	var border_width := 2.5 if focused else 1.0

	draw_rect(board_rect.grow(10.0), Color(0.025, 0.03, 0.055, 1.0), true)
	draw_rect(board_rect.grow(10.0), border_glow_color, false, border_width)
	draw_rect(board_rect, CELL_COLORS[0], true)

	var cell := board_rect.size.x / float(columns)

	for row in highlight_rows:
		if row >= 0 and row < rows:
			var y := board_rect.position.y + float(row) * cell
			draw_rect(Rect2(board_rect.position.x, y, board_rect.size.x, cell), Color(1.0, 0.84, 0.28, 0.22), true)

	for c in range(columns + 1):
		var x := board_rect.position.x + float(c) * cell
		draw_line(Vector2(x, board_rect.position.y), Vector2(x, board_rect.position.y + board_rect.size.y), Color(0.15, 0.15, 0.22, 0.5), 1.0)
	for r in range(rows + 1):
		var y := board_rect.position.y + float(r) * cell
		draw_line(Vector2(board_rect.position.x, y), Vector2(board_rect.position.x + board_rect.size.x, y), Color(0.15, 0.15, 0.22, 0.5), 1.0)

	for row in range(mini(rows, grid.size())):
		var row_data: Array = grid[row]
		for col in range(mini(columns, row_data.size())):
			var value := int(row_data[col])
			if value != EMPTY:
				_draw_cell(board_rect, col, row, value, 1.0)

	for cell_pos in target_cells:
		var pos := cell_pos as Vector2i
		_draw_target_cell(board_rect, pos.x, pos.y)

	for cell_pos in highlight_cells:
		var pos := cell_pos as Vector2i
		_draw_highlight_cell(board_rect, pos.x, pos.y)

	if show_ghost and ghost_row >= 0 and not active_piece.is_empty():
		var ghost_piece := active_piece.duplicate()
		ghost_piece["row"] = ghost_row
		_draw_piece(board_rect, ghost_piece, 0.20)

	if not active_piece.is_empty():
		_draw_piece(board_rect, active_piece, 1.0)

		# 显示旋转中心点（红色圆圈）
		if show_center_point:
			_draw_center_point(board_rect, active_piece)

	# 聚焦状态边框
	var main_border_color := Color(0.0, 0.92, 1.0, 0.8) if focused else Color(0.0, 0.83, 1.0, 0.45)
	var main_border_w := 3.0 if focused else 2.0
	draw_rect(board_rect, main_border_color, false, main_border_w)

	# 消行闪光
	if _clear_flash_timer > 0.0:
		var flash_alpha: float = clampf(_clear_flash_timer / FLASH_DURATION, 0.0, 1.0)
		var flash_color := Color(1.0, 1.0, 1.0, flash_alpha * 0.85)
		for row_idx in _clear_flash_rows:
			if row_idx >= 0 and row_idx < rows:
				var fy := board_rect.position.y + float(row_idx) * cell
				draw_rect(Rect2(board_rect.position.x, fy, board_rect.size.x, cell), flash_color)

	# 消行粒子
	for p in _clear_particles:
		if p["life"] <= 0.0:
			continue
		var life_ratio: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var alpha: float = life_ratio
		var current_size: float = p["size"] * (0.3 + 0.7 * life_ratio)
		var pc: Color = p["color"]
		pc.a = alpha
		var ppos: Vector2 = p["pos"]
		var half: float = current_size * 0.5
		var prot: float = p["rot"]
		var corners: Array = [
			Vector2(-half, -half),
			Vector2(half, -half),
			Vector2(half, half),
			Vector2(-half, half)
		]
		var rotated_corners: PackedVector2Array = PackedVector2Array()
		var cos_r: float = cos(prot)
		var sin_r: float = sin(prot)
		for corner in corners:
			rotated_corners.append(ppos + Vector2(
				corner.x * cos_r - corner.y * sin_r,
				corner.x * sin_r + corner.y * cos_r
			))
		var colors_arr := PackedColorArray()
		colors_arr.resize(4)
		colors_arr.fill(pc)
		draw_polygon(rotated_corners, colors_arr)
		if current_size > PARTICLE_SIZE * 0.8:
			var glow_c := Color(pc.r, pc.g, pc.b, alpha * 0.3)
			for i in range(4):
				draw_line(
					rotated_corners[i],
					rotated_corners[(i + 1) % 4],
					glow_c,
					1.5
				)

	if not effect_text.is_empty():
		_draw_effect_text(board_rect)


func _board_rect() -> Rect2:
	var margin := 10.0
	var available := size - Vector2(margin * 2.0, margin * 2.0)
	var cell := minf(available.x / float(columns), available.y / float(rows))
	var board_size := Vector2(cell * columns, cell * rows)
	var origin := (size - board_size) * 0.5
	return Rect2(origin, board_size)


func _draw_piece(board_rect: Rect2, piece: Dictionary, alpha: float) -> void:
	var type := int(piece.get("type", PieceData.Type.T))
	var rot := int(piece.get("rot", PieceData.RotationState.SPAWN))
	var col := float(piece.get("col", 4.0))
	var row := float(piece.get("row", 0.0))
	for offset in PieceData.SHAPES[type][rot]:
		var cell_col := col + float(offset.x)
		var cell_row := row + float(offset.y)
		if cell_row > -1.0 and cell_row < float(rows) and cell_col > -1.0 and cell_col < float(columns):
			if alpha < 0.35:
				_draw_ghost_cell_at(board_rect, cell_col, cell_row, type + 1, alpha)
			else:
				_draw_cell_at(board_rect, cell_col, cell_row, type + 1, alpha)


func _draw_center_point(board_rect: Rect2, piece: Dictionary) -> void:
	var col := float(piece.get("col", 4.0))
	var row := float(piece.get("row", 0.0))
	var cell := board_rect.size.x / float(columns)

	# 旋转中心点位置 = 方块的 col, row（即旋转轴心）
	var center_x := board_rect.position.x + (col + 0.5) * cell
	var center_y := board_rect.position.y + (row + 0.5) * cell

	# 红色圆圈，大小约格子的 40%
	var radius := cell * 0.20
	# 外圈红色
	draw_arc(Vector2(center_x, center_y), radius, 0.0, TAU, 32, Color(1.0, 0.15, 0.15, 0.9), 2.5)
	# 内填充半透明红色
	draw_circle(Vector2(center_x, center_y), radius * 0.6, Color(1.0, 0.15, 0.15, 0.45))


func _draw_cell(board_rect: Rect2, col: int, row: int, value: int, alpha: float) -> void:
	_draw_cell_at(board_rect, float(col), float(row), value, alpha)


func _draw_cell_at(board_rect: Rect2, col: float, row: float, value: int, alpha: float) -> void:
	var cell := board_rect.size.x / float(columns)
	var rect := Rect2(
		board_rect.position + Vector2(col * cell, row * cell),
		Vector2(cell, cell)
	).grow(-1.0)
	var color := _piece_color(value)
	color.a *= alpha
	draw_rect(rect, color, true)
	draw_rect(rect, color.lightened(0.25), false, 1.2)


func _draw_target_cell(board_rect: Rect2, col: int, row: int) -> void:
	if col < 0 or col >= columns or row < 0 or row >= rows:
		return
	var value := int(active_piece.get("type", PieceData.Type.I)) + 1 if not active_piece.is_empty() else PieceData.Type.I + 1
	_draw_ghost_cell_at(board_rect, float(col), float(row), value, 0.26)


func _draw_ghost_cell_at(board_rect: Rect2, col: float, row: float, value: int, alpha: float) -> void:
	var cell := board_rect.size.x / float(columns)
	var rect := Rect2(
		board_rect.position + Vector2(col * cell, row * cell),
		Vector2(cell, cell)
	).grow(-2.0)
	var color := _piece_color(value)
	var fill := color
	fill.a = alpha
	var edge := color.lightened(0.28)
	edge.a = minf(alpha + 0.28, 0.62)
	draw_rect(rect, fill, true)
	draw_rect(rect, edge, false, 1.4)


func _draw_highlight_cell(board_rect: Rect2, col: int, row: int) -> void:
	if col < 0 or col >= columns or row < 0 or row >= rows:
		return
	_draw_ghost_cell_at(board_rect, float(col), float(row), PieceData.Type.T + 1, 0.18)


func _piece_color(value: int) -> Color:
	if value >= 0 and value < CELL_COLORS.size():
		return CELL_COLORS[value]
	return Color(0.45, 0.45, 0.45, 1.0)


func _draw_effect_text(board_rect: Rect2) -> void:
	var font := get_theme_default_font()
	var font_size := mini(34, maxi(22, int(board_rect.size.x / maxf(1.0, float(effect_text.length())) * 1.55)))
	var text_size := font.get_string_size(effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := board_rect.position + (board_rect.size - text_size) * 0.5
	draw_string_outline(font, pos, effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color(0.02, 0.04, 0.08, 0.92))
	draw_string(font, pos, effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, effect_color)


func _find_ghost_row() -> int:
	if active_piece.is_empty() or grid.is_empty():
		return -1
	var type := int(active_piece.get("type", PieceData.Type.T))
	var rot := int(active_piece.get("rot", PieceData.RotationState.SPAWN))
	var col := int(active_piece.get("col", 4))
	var row := int(active_piece.get("row", 0))
	while _is_valid(type, rot, col, row + 1):
		row += 1
	return row


func _is_valid(type: int, rot: int, col: int, row: int) -> bool:
	for offset in PieceData.SHAPES[type][rot]:
		var c := col + int(offset.x)
		var r := row + int(offset.y)
		if c < 0 or c >= columns:
			return false
		if r >= rows:
			return false
		if r < 0:
			continue
		if r < grid.size() and int(grid[r][c]) != EMPTY:
			return false
	return true
