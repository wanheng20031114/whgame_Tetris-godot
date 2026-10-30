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
const DANGER_COLOR := Color(1.0, 0.16, 0.24)
const GARBAGE_COLOR := Color(0.45, 0.45, 0.45)

var grid: Array = []
const EMPTY_CELL_TYPE: int = 0
const GARBAGE_CELL_TYPE: int = 8
var last_hole_col: int = -1

## 兼容旧接口：danger_level > 0 即视为处于危险
var danger_warning_active: bool:
	get: return danger_level > 0.0

var danger_level: float = 0.0
var _danger_vis: float = 0.0 ## 平滑后的显示强度
var _beat_time: float = 0.0
var _spawn_warn_type: int = -1
var _spawn_warn_col: int = 0
var _spawn_warn_row: int = 0

# 垃圾行上升动画：已入场的格子从低处滑到正确位置
var _rise_offset: float = 0.0
var _rise_rows: int = 0
var _rise_flash: float = 0.0

# 落地震动（只位移本节点，子节点方块随之移动）
var _rest_position: Vector2
var _has_rest: bool = false
var _bump_offset: Vector2 = Vector2.ZERO
var _bump_velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	_init_grid()
	set_process(false)
	var manager := _get_block_style_manager()
	if manager != null and manager.has_signal("style_changed"):
		var callback := Callable(self, "_on_block_style_changed")
		if not manager.is_connected("style_changed", callback):
			manager.connect("style_changed", callback)

func _process(delta: float) -> void:
	var busy := false

	_danger_vis = move_toward(_danger_vis, danger_level, delta * 1.6)
	if _danger_vis > 0.001 or danger_level > 0.0:
		# 越危险心跳越快：72 → 120 BPM
		_beat_time += delta * lerpf(1.2, 2.0, _danger_vis)
		busy = true

	if _rise_offset > 0.0 or _rise_flash > 0.0:
		_rise_offset = move_toward(_rise_offset, 0.0, delta * cell_size * 26.0)
		_rise_flash = maxf(_rise_flash - delta * 3.2, 0.0)
		busy = true

	if _has_rest and (_bump_offset.length_squared() > 0.01 or _bump_velocity.length_squared() > 0.01):
		# 欠阻尼弹簧的解析解；低帧率或窗口卡顿时也不会因积分步长而发散。
		var stiffness := 900.0
		var damping := sqrt(stiffness) * 0.75
		var frequency := sqrt(stiffness - damping * damping)
		var decay := exp(-damping * delta)
		var wave_cos := cos(frequency * delta)
		var wave_sin := sin(frequency * delta)
		var offset := _bump_offset
		var velocity := _bump_velocity
		_bump_offset = decay * (offset * wave_cos + (velocity + damping * offset) * wave_sin / frequency)
		_bump_velocity = decay * (velocity * wave_cos - (damping * velocity + stiffness * offset) * wave_sin / frequency)
		position = _rest_position + _bump_offset
		busy = true
	elif _has_rest and position != _rest_position:
		_bump_offset = Vector2.ZERO
		_bump_velocity = Vector2.ZERO
		position = _rest_position

	queue_redraw()
	if not busy:
		set_process(false)

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

# ==============================================================================
# 绘制
# ==============================================================================

func _draw() -> void:
	var board_w: float = columns * cell_size
	var board_h: float = visible_rows * cell_size
	var d := _danger_vis
	var beat := _heartbeat() * d

	if d > 0.001:
		_draw_danger_halo(board_w, board_h, d, beat)

	draw_rect(Rect2(Vector2.ZERO, Vector2(board_w, board_h)), BG_COLOR)

	if d > 0.001:
		_draw_danger_well(board_w, d, beat)

	var grid_color := GRID_LINE_COLOR.lerp(DANGER_COLOR.darkened(0.55), d * 0.6)
	for col in range(columns + 1):
		var x: float = col * cell_size
		draw_line(Vector2(x, 0), Vector2(x, board_h), grid_color, 1.0)
	for row in range(visible_rows + 1):
		var y: float = row * cell_size
		draw_line(Vector2(0, y), Vector2(board_w, y), grid_color, 1.0)

	var rise := _rise_offset
	for row in range(buffer_rows, total_rows):
		for col in range(columns):
			var color = grid[row][col]
			if color != null:
				var vis_row: int = row - buffer_rows
				var y := vis_row * cell_size + rise
				if y >= board_h:
					continue
				var rect := Rect2(Vector2(col * cell_size, y), Vector2(cell_size, cell_size))
				_draw_block_cell(rect, color)

	if _rise_flash > 0.0 and _rise_rows > 0:
		var top := (visible_rows - _rise_rows) * cell_size + rise
		draw_rect(Rect2(0, top, board_w, board_h - top), Color(1, 1, 1, _rise_flash * 0.35))

	if d > 0.001 and _spawn_warn_type >= 0:
		_draw_spawn_warning(d, beat)

	var border := BORDER_COLOR.lerp(DANGER_COLOR, clampf(d * (0.55 + 0.45 * beat), 0.0, 1.0))
	draw_rect(Rect2(Vector2(-1, -1), Vector2(board_w + 2, board_h + 2)), border, false, 2.0)

## 双拍心跳曲线（lub-dub），返回 0~1
func _heartbeat() -> float:
	var t := fmod(_beat_time, 1.0)
	var lub := exp(-pow((t - 0.06) / 0.05, 2.0))
	var dub := exp(-pow((t - 0.28) / 0.06, 2.0)) * 0.6
	return clampf(lub + dub, 0.0, 1.0)

## 棋盘外的柔和红色光晕，随心跳扩张；不进入棋盘内部，不遮挡视线
func _draw_danger_halo(w: float, h: float, d: float, beat: float) -> void:
	var layers := 7
	var spread := lerpf(10.0, 22.0, beat)
	for i in range(layers):
		var t := float(i + 1) / float(layers)
		var g := 2.0 + spread * t
		var a := (1.0 - t) * (1.0 - t) * lerpf(0.18, 0.5, beat) * d
		draw_rect(Rect2(-g, -g, w + g * 2.0, h + g * 2.0), Color(DANGER_COLOR, a), false, spread / float(layers) + 1.0)

## 井口红色渐变 + 缓慢滚动的警示斜纹，只覆盖堆叠上方的空区域，透明度很低
func _draw_danger_well(w: float, d: float, beat: float) -> void:
	var stack_top := (visible_rows - get_stack_height()) * cell_size
	var depth := minf(stack_top, cell_size * 6.0)
	if depth <= 1.0:
		return
	var top_a := lerpf(0.10, 0.22, beat) * d
	var cols := PackedColorArray([Color(DANGER_COLOR, top_a), Color(DANGER_COLOR, top_a), Color(DANGER_COLOR, 0.0), Color(DANGER_COLOR, 0.0)])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, depth), Vector2(0, depth)]), cols)

	# 警示斜纹：只画在最上方两行
	var band := minf(cell_size * 2.0, depth)
	var stripe := cell_size * 0.5
	var shift := fmod(_beat_time * stripe * 0.8, stripe * 2.0)
	var x := -band - stripe * 2.0 + shift
	var sa := 0.07 * d
	while x < w:
		var poly := PackedVector2Array([
			Vector2(x, band), Vector2(x + stripe, band),
			Vector2(x + stripe + band, 0), Vector2(x + band, 0)])
		var clipped := Geometry2D.intersect_polygons(poly, PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, band), Vector2(0, band)]))
		for c in clipped:
			if poly_area(c) > 0.5:
				draw_colored_polygon(c, Color(DANGER_COLOR, sa))
		x += stripe * 2.0

## 多边形面积（裁剪后会产生极细的碎片，绘制前过滤，避免三角化失败）
static func poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(p.size()):
		a += p[i].cross(p[(i + 1) % p.size()])
	return absf(a) * 0.5

## 下一块的出生位置轮廓：若会和堆叠重叠，则该格画成实心警示
func _draw_spawn_warning(d: float, beat: float) -> void:
	var shape: Array = PieceData.SHAPES[_spawn_warn_type][PieceData.RotationState.SPAWN]
	var a := lerpf(0.35, 0.9, beat) * d
	for offset in shape:
		var col: int = _spawn_warn_col + int(offset.x)
		var row: int = _spawn_warn_row + int(offset.y)
		var vis_row := row - buffer_rows
		if vis_row < 0 or col < 0 or col >= columns:
			continue
		var rect := Rect2(col * cell_size, vis_row * cell_size, cell_size, cell_size).grow(-3.0)
		var blocked: bool = row < total_rows and grid[row][col] != null
		if blocked:
			draw_rect(rect, Color(DANGER_COLOR, a * 0.55))
		draw_rect(rect, Color(DANGER_COLOR, a), false, 2.0)

# ==============================================================================
# 状态与查询
# ==============================================================================

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
	# Validate the entire packet before mutating any cell.
	for row in data:
		if not row is Array or row.size() != columns:
			return
		for value in row:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)):
				return
			if int(value) < 0 or int(value) > GARBAGE_CELL_TYPE:
				return

	for r in range(total_rows):
		var row_data: Array = data[r]
		for c in range(columns):
			var type_idx: int = row_data[c]
			if type_idx == EMPTY_CELL_TYPE:
				grid[r][c] = null
			elif type_idx == GARBAGE_CELL_TYPE:
				grid[r][c] = GARBAGE_COLOR
			else:
				var piece_type: int = type_idx - 1
				if PieceData.COLORS.has(piece_type):
					grid[r][c] = PieceData.COLORS[piece_type]
				else:
					grid[r][c] = GARBAGE_COLOR

	queue_redraw()

func add_garbage_lines(amount: int) -> bool:
	if amount <= 0:
		return false
	# Work and allocations are bounded by the board, never by a network amount.
	var topped_out := amount >= total_rows
	var applied := mini(amount, total_rows)
	for i in range(applied):
		for cell in grid[i]:
			if cell != null:
				topped_out = true
	for _i in range(applied):
		grid.pop_front()

	# 50% keep previous hole, 50% reroll (10 columns => +5% same column from reroll)
	var hole_col: int = last_hole_col
	if hole_col < 0 or randf() < 0.5:
		hole_col = randi() % columns
	last_hole_col = hole_col

	for _j in range(applied):
		var new_row: Array = _create_empty_row()
		for c in range(columns):
			if c != hole_col:
				new_row[c] = GARBAGE_COLOR
		grid.append(new_row)

	# 堆叠从下方顶上来：先整体下沉 amount 行，再快速升回
	_rise_rows = mini(applied, visible_rows)
	_rise_offset = _rise_rows * cell_size
	_rise_flash = 1.0
	bump(Vector2(0, -minf(2.0 + applied, 7.0)))
	set_process(true)
	queue_redraw()
	return topped_out

## 落地/受击震动：offset 为瞬时冲量方向（像素级，建议 2~8）
func bump(impulse: Vector2) -> void:
	if not _has_rest:
		_rest_position = position
		_has_rest = true
	_bump_velocity += impulse * 34.0
	set_process(true)

## 可见区内堆叠的最高高度（行数）
func get_stack_height() -> int:
	for r in range(buffer_rows, total_rows):
		for c in range(columns):
			if grid[r][c] != null:
				return total_rows - r
	return 0

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

func set_danger_level(level: float) -> void:
	level = clampf(level, 0.0, 1.0)
	if is_equal_approx(level, danger_level):
		return
	danger_level = level
	set_process(true)

func set_danger_warning(active: bool) -> void:
	set_danger_level(1.0 if active else 0.0)

func set_spawn_warning(piece_type: int, col: int, row: int) -> void:
	if piece_type == _spawn_warn_type and col == _spawn_warn_col and row == _spawn_warn_row:
		return
	_spawn_warn_type = piece_type
	_spawn_warn_col = col
	_spawn_warn_row = row
	queue_redraw()


func _on_block_style_changed(_style_id: String) -> void:
	queue_redraw()


func _get_block_style_manager() -> Node:
	return get_node_or_null("/root/BlockStyleManager")


func _draw_block_cell(rect: Rect2, color: Color) -> void:
	var manager := _get_block_style_manager()
	if manager != null and manager.has_method("draw_cell"):
		manager.call("draw_cell", self, rect, color)
		return

	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	draw_rect(rect.grow(-4.0), color.lightened(0.4), false, 1.0)
