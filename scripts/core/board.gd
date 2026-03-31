class_name Board
extends Node2D

## 棋盘网格系统
##
## 俄罗斯方块的"竞技场"。管理 10×40 的二维网格数据（上方 20 行隐藏缓冲区 + 下方 20 行可见区域）。
## 负责碰撞检测、方块锁定写入、满行消除、以及整个棋盘的程序化绘制。
## 列数参数化设计，为将来 WIDE 模式动态修改列宽留出接口。

# ==============================================================================
# 棋盘尺寸配置（参数化，支持未来 WIDE 模式扩展）
# ==============================================================================

@export_group("棋盘尺寸")
## 列数（标准 10，将来可在检查器里改为更宽试试 WIDE 模式）
@export var columns: int = 10
## 可见行数
@export var visible_rows: int = 20
## 隐藏缓冲行数（方块在此生成，玩家看不到）
var buffer_rows: int = 20
## 总行数 = 可见 + 缓冲
var total_rows: int:
	get: return visible_rows + buffer_rows
## 单个格子像素尺寸
@export var cell_size: float = 30.0

# ==============================================================================
# 视觉配色
# ==============================================================================

const BG_COLOR := Color("0d0d14")         ## 棋盘背景：极深炭黑
const GRID_LINE_COLOR := Color("1a1a2e")  ## 网格线：若隐若现的暗线
const BORDER_COLOR := Color("3a3a5c")     ## 棋盘边框：科技蓝灰

# ==============================================================================
# 网格数据：grid[row][col]，值为 null（空）或 Color（已占据）
# ==============================================================================

var grid: Array = []
var last_hole_col: int = -1 ## 用于记忆上一次受击缺口的列，以确保高概率对齐

# ==============================================================================
# 初始化
# ==============================================================================

func _ready() -> void:
	_init_grid()

## 清空整个棋盘网格
func _init_grid() -> void:
	grid.clear()
	for row in range(total_rows):
		grid.append(_create_empty_row())

## 创建一个全空的行
func _create_empty_row() -> Array:
	var row: Array = []
	row.resize(columns)
	row.fill(null)
	return row

# ==============================================================================
# 碰撞检测（核心中的核心）
# ==============================================================================

## 判断指定方块在指定位置是否合法（不越界、不与已锁定格子重叠）
## type: 方块类型枚举
## rotation: 旋转状态
## center_col: 方块中心所在列
## center_row: 方块中心所在行
## 返回 true = 位置合法，可以放置
func is_valid_position(type: PieceData.Type, rot_state: PieceData.RotationState,
		center_col: int, center_row: int) -> bool:
	var shape = PieceData.SHAPES[type][rot_state]
	for offset in shape:
		var col: int = center_col + int(offset.x)
		var row: int = center_row + int(offset.y)
		# 检查左右边界
		if col < 0 or col >= columns:
			return false
		# 检查底部边界（允许方块在顶部缓冲区之上）
		if row >= total_rows:
			return false
		# 跳过在棋盘上方的格子（允许方块部分超出顶部）
		if row < 0:
			continue
		# 检查是否与已锁定方块重叠
		if grid[row][col] != null:
			return false
	return true

# ==============================================================================
# 方块锁定（将活动方块永久写入网格）
# ==============================================================================

## 将方块的 4 个格子写入网格数组
func lock_piece(type: PieceData.Type, rot_state: PieceData.RotationState,
		center_col: int, center_row: int, color: Color) -> void:
	var shape = PieceData.SHAPES[type][rot_state]
	for offset in shape:
		var col: int = center_col + int(offset.x)
		var row: int = center_row + int(offset.y)
		if row >= 0 and row < total_rows and col >= 0 and col < columns:
			grid[row][col] = color

# ==============================================================================
# 消行逻辑
# ==============================================================================

## 检查并清除所有满行，返回清除的行数
func clear_lines() -> int:
	var new_grid: Array = []
	var cleared: int = 0

	# 从上到下遍历，保留未满的行
	for row in range(total_rows):
		if _is_row_full(row):
			cleared += 1
		else:
			new_grid.append(grid[row])

	# 在顶部补充空行（补回被消除的行数）
	for i in range(cleared):
		new_grid.insert(0, _create_empty_row())

	grid = new_grid
	return cleared

## 判断某一行是否满（所有列都被占据）
func _is_row_full(row: int) -> bool:
	for col in range(columns):
		if grid[row][col] == null:
			return false
	return true

# ==============================================================================
# 棋盘程序化绘制
# ==============================================================================

func _draw() -> void:
	var board_w: float = columns * cell_size
	var board_h: float = visible_rows * cell_size

	# 1. 背景填充
	draw_rect(Rect2(Vector2.ZERO, Vector2(board_w, board_h)), BG_COLOR)

	# 2. 网格线（极淡的参考线）
	for col in range(columns + 1):
		var x: float = col * cell_size
		draw_line(Vector2(x, 0), Vector2(x, board_h), GRID_LINE_COLOR, 1.0)
	for row in range(visible_rows + 1):
		var y: float = row * cell_size
		draw_line(Vector2(0, y), Vector2(board_w, y), GRID_LINE_COLOR, 1.0)

	# 3. 已锁定的格子（仅绘制可见区域）
	for row in range(buffer_rows, total_rows):
		for col in range(columns):
			var color = grid[row][col]
			if color != null:
				var vis_row: int = row - buffer_rows
				var rect := Rect2(
					Vector2(col * cell_size, vis_row * cell_size),
					Vector2(cell_size, cell_size)
				)
				# 主体填色
				draw_rect(rect, color)
				# 深色外框（立体阴影感）
				draw_rect(rect, color.darkened(0.3), false, 2.0)
				# 亮色内框（发光晶体质感）
				var inner := rect.grow(-4.0)
				draw_rect(inner, color.lightened(0.4), false, 1.0)

	# 4. 棋盘外边框
	draw_rect(Rect2(Vector2(-1, -1), Vector2(board_w + 2, board_h + 2)), BORDER_COLOR, false, 2.0)

# ==============================================================================
# 受击垃圾行分配 (Tetris 99 Style)
# ==============================================================================

## 增加指定数量的垃圾行（从底部上推）
func add_garbage_lines(amount: int) -> void:
	if amount <= 0:
		return
		
	# 向上推移现有的方块网格（扔掉顶部挤爆的行，底部腾出空位）
	for i in range(amount):
		grid.pop_front()
		
	# 70% 的极高概率孔洞开在上一批或者上一行的位置
	var hole_col: int = last_hole_col
	if hole_col < 0 or randf() < 0.3:
		hole_col = randi() % columns
	last_hole_col = hole_col
	
	var garbage_color: Color = Color(0.45, 0.45, 0.45) # 灰色无属性废墟砖块
	
	for i in range(amount):
		var new_row: Array = _create_empty_row()
		for c in range(columns):
			if c != hole_col:
				new_row[c] = garbage_color
		# 在队列最末尾（亦即物理图形的最底下）推送新受击行
		grid.append(new_row)
		
	queue_redraw()
