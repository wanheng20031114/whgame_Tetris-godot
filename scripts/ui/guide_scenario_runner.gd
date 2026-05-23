class_name GuideScenarioRunner
extends RefCounted

const EMPTY := 0
const GARBAGE := 8
const ROWS := 20
const COLS := 10

var scene_id: String = "tetris"
var phase: int = 0
var grid: Array = []
var piece_type: int = PieceData.Type.I
var rot: int = PieceData.RotationState.SPAWN
var col: int = 4
var row: int = 2
var last_was_rotation: bool = false


func setup(new_scene_id: String, new_phase: int = 0) -> void:
	scene_id = new_scene_id
	phase = new_phase
	grid = empty_grid()
	last_was_rotation = false

	match scene_id:
		"tspin":
			_fill_tspin_double_grid()
			spawn(PieceData.Type.T, 5, 4, PieceData.RotationState.SPAWN)
		"combo":
			_fill_combo_phase_grid(phase)
			# 所有 combo phase 都使用 O 方块，从右侧2列上方落下
			spawn(PieceData.Type.O, 7, 2, PieceData.RotationState.SPAWN)
		"wallkick":
			_fill_wallkick_grid()
			# L 方块紧贴右墙
			spawn(PieceData.Type.L, 8, 12, PieceData.RotationState.SPAWN)
		_:
			_fill_tetris_grid()
			spawn(PieceData.Type.I, 4, 5, PieceData.RotationState.SPAWN)


func spawn(new_type: int, new_col: int, new_row: int, new_rot: int = PieceData.RotationState.SPAWN) -> void:
	piece_type = new_type
	col = new_col
	row = new_row
	rot = new_rot
	last_was_rotation = false


func try_move(dx: int, dy: int) -> bool:
	if is_valid(piece_type, rot, col + dx, row + dy):
		col += dx
		row += dy
		if dx != 0 or dy != 0:
			last_was_rotation = false
		return true
	return false


func try_rotate(direction: int) -> bool:
	var new_rot: int
	if direction == 2:
		new_rot = (rot + 2) % 4
	elif direction > 0:
		new_rot = (rot + 1) % 4
	else:
		new_rot = (rot + 3) % 4

	var kicks: Array
	if direction == 2:
		kicks = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]
	else:
		kicks = PieceData.get_wall_kicks(piece_type, rot, new_rot)

	for kick in kicks:
		var test_col := col + int(kick.x)
		var test_row := row + int(kick.y)
		if is_valid(piece_type, new_rot, test_col, test_row):
			col = test_col
			row = test_row
			rot = new_rot
			last_was_rotation = true
			return true
	return false


func soft_drop_to(target_row: int) -> Array:
	var frames: Array = []
	while row < target_row and try_move(0, 1):
		frames.append(piece_dict())
	return frames


func move_steps(dx: int, count: int) -> Array:
	var frames: Array = []
	var direction := 1 if dx > 0 else -1
	for _i in range(count):
		if try_move(direction, 0):
			frames.append(piece_dict())
	return frames


func hard_drop() -> int:
	var cells := 0
	while try_move(0, 1):
		cells += 1
	return cells


func lock_piece() -> Dictionary:
	for pos in piece_cells(piece_type, rot, col, row):
		if pos.y >= 0 and pos.y < ROWS and pos.x >= 0 and pos.x < COLS:
			grid[pos.y][pos.x] = piece_type + 1
	var spin := last_was_rotation and _is_spin_position()
	var cleared_rows := _full_rows()
	_clear_rows(cleared_rows)
	return {
		"cleared": cleared_rows.size(),
		"rows": cleared_rows,
		"spin": spin
	}


func grid_with_active() -> Array:
	var result := copy_grid(grid)
	for pos in piece_cells(piece_type, rot, col, row):
		if pos.y >= 0 and pos.y < ROWS and pos.x >= 0 and pos.x < COLS:
			result[pos.y][pos.x] = piece_type + 1
	return result


func piece_dict() -> Dictionary:
	return {"type": piece_type, "rot": rot, "col": col, "row": row}


func target_cells() -> Array:
	match scene_id:
		"tspin":
			return piece_cells(PieceData.Type.T, PieceData.RotationState.TWO, 5, 18)
		"combo":
			# O 方块目标位置：右侧2列底部
			var target_row := 19 - phase * 2
			if target_row < 1:
				target_row = 1
			return piece_cells(PieceData.Type.O, PieceData.RotationState.SPAWN, 8, target_row)
		"wallkick":
			# Wall kick 后 L 方块的位置
			return piece_cells(PieceData.Type.L, PieceData.RotationState.R, 8, 12)
		_:
			return piece_cells(PieceData.Type.I, PieceData.RotationState.R, 8, 17)


func highlight_rows() -> Array:
	match scene_id:
		"tspin":
			return [18, 19]
		"combo":
			var base_row := 19 - phase * 2
			if base_row < 1:
				return [1, 2]
			return [base_row - 1, base_row]
		"wallkick":
			return []
		_:
			return [16, 17, 18, 19]


func focus_cells() -> Array:
	match scene_id:
		"tspin":
			return [Vector2i(4, 18), Vector2i(5, 18), Vector2i(6, 18), Vector2i(4, 19), Vector2i(5, 19), Vector2i(6, 19)]
		_:
			return []


func effect_text(cleared: int, spin: bool = false) -> String:
	if scene_id == "tspin" and spin and cleared >= 2:
		return "T-SPIN DOUBLE"
	if scene_id == "tspin" and spin and cleared == 1:
		return "T-SPIN SINGLE"
	if scene_id == "combo":
		return "COMBO %d" % (phase + 1)
	if scene_id == "wallkick":
		return "WALL KICK"
	if cleared == 4:
		return "TETRIS"
	if cleared > 0:
		return "CLEAR"
	return ""


func is_valid(type: int, test_rot: int, test_col: int, test_row: int) -> bool:
	for offset in PieceData.SHAPES[type][test_rot]:
		var c := test_col + int(offset.x)
		var r := test_row + int(offset.y)
		if c < 0 or c >= COLS:
			return false
		if r >= ROWS:
			return false
		if r < 0:
			continue
		if int(grid[r][c]) != EMPTY:
			return false
	return true


func piece_cells(type: int, test_rot: int, test_col: int, test_row: int) -> Array:
	var cells: Array = []
	for offset in PieceData.SHAPES[type][test_rot]:
		cells.append(Vector2i(test_col + int(offset.x), test_row + int(offset.y)))
	return cells


static func empty_grid() -> Array:
	var data: Array = []
	for _r in range(ROWS):
		var row_data: Array = []
		for _c in range(COLS):
			row_data.append(EMPTY)
		data.append(row_data)
	return data


static func copy_grid(source: Array) -> Array:
	var result: Array = []
	for row_data in source:
		result.append((row_data as Array).duplicate())
	return result


## Tetris：右侧留一列井（col 9），行16-19 其余列填满
func _fill_tetris_grid() -> void:
	for r in range(16, 20):
		for c in range(0, 9):
			grid[r][c] = GARBAGE


## T-Spin Double 地形：
## 底部两行几乎全满，中间留一个 T 形槽口
## row 17: col 4 空（入口顶部遮挡块）
## row 18: col 4,5,6 空（T 槽上半）
## row 19: col 5 空，其余满（T 槽下半 - 只留中间）
func _fill_tspin_double_grid() -> void:
	# row 19: 底部行，col 5 空
	for c in range(COLS):
		if c != 5:
			grid[19][c] = GARBAGE
	# row 18: col 4,5,6 空（T 旋入的三个位置）
	for c in range(COLS):
		if c < 4 or c > 6:
			grid[18][c] = GARBAGE
	# row 17: col 4 有方块作为遮挡（T 需要旋入才能进去）
	# col 5,6 空作为入口通道
	for c in range(COLS):
		if c < 4 or c > 6:
			grid[17][c] = GARBAGE
	grid[17][4] = GARBAGE


## Wall Kick 地形：右侧墙壁附近有简单堆叠
## L 方块贴右墙旋转展示踢墙位移
func _fill_wallkick_grid() -> void:
	# 在底部几行构造地形，让 L 方块必须踢墙
	for r in range(14, 20):
		for c in range(0, 7):
			grid[r][c] = GARBAGE
	# col 7,8,9 保留空间给 L 方块
	# 底部 row 19 加一些方块限制
	grid[19][7] = GARBAGE
	grid[19][8] = GARBAGE


## Combo 地形：右侧空2列（col 8,9），其余8列填满，10层高
## 每个 phase O 方块落入右侧消除2行
func _fill_combo_phase_grid(combo_phase: int) -> void:
	# 根据已消除的 phase 数量确定顶部位置
	# phase 0: 行 10-19 填满（10层），O 方块消 row 18-19
	# phase 1: 行 10-17 填满（8层），O 方块消 row 16-17
	# phase 2: 行 10-15 填满（6层），O 方块消 row 14-15
	# phase 3: 行 10-13 填满（4层），O 方块消 row 12-13
	# phase 4: 行 10-11 填满（2层），O 方块消 row 10-11

	var top_row := 10
	var bottom_row := 19 - combo_phase * 2

	if bottom_row < top_row:
		return

	for r in range(top_row, bottom_row + 1):
		for c in range(0, 8):  # col 0-7 填满，col 8-9 空
			grid[r][c] = GARBAGE


func _full_rows() -> Array:
	var found_rows: Array = []
	for r in range(ROWS):
		var full := true
		for c in range(COLS):
			if int(grid[r][c]) == EMPTY:
				full = false
				break
		if full:
			found_rows.append(r)
	return found_rows


func _clear_rows(rows_to_clear: Array) -> void:
	if rows_to_clear.is_empty():
		return
	var next_grid: Array = []
	for r in range(ROWS):
		if not rows_to_clear.has(r):
			next_grid.append(grid[r])
	for _i in range(rows_to_clear.size()):
		next_grid.insert(0, empty_grid()[0])
	grid = next_grid


func _is_spin_position() -> bool:
	var blocked := 0
	if not is_valid(piece_type, rot, col - 1, row):
		blocked += 1
	if not is_valid(piece_type, rot, col + 1, row):
		blocked += 1
	if not is_valid(piece_type, rot, col, row - 1):
		blocked += 1
	if not is_valid(piece_type, rot, col, row + 1):
		blocked += 1
	return blocked >= 3
