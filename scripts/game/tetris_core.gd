class_name TetrisCore
extends Node2D

## 俄罗斯方块核心逻辑
## 包含 SRS 旋转、DAS/ARR、锁定延迟、得分与 Combo 等通用规则。
# ==============================================================================
# 信号（用于通知 UI 或网络同步）
# ==============================================================================

signal score_changed(score: int, level: int, lines: int)
signal piece_locked(type: int, grid_state: Array)
signal lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, damage: int)
signal game_over_triggered()
signal board_updated()

# ==============================================================================
# @export 配置
# ==============================================================================

@export_group("核心参数")
@export var spawn_col: int = 4
@export var starting_level: int = 1
@export var das_delay: float = 0.180
@export var arr_interval: float = 0.020
@export var soft_drop_multiplier: float = 20.0
@export var max_lock_resets: int = 15

# ==============================================================================
# 节点引用（派生场景需要包含这些节点）
# ==============================================================================

@onready var board = get_node_or_null("%Board")
@onready var current_piece = get_node_or_null("%CurrentPiece")
@onready var ghost_piece = get_node_or_null("%GhostPiece")
@onready var hold_piece = get_node_or_null("%HoldPiece")
@onready var next_container = get_node_or_null("%NextPieces")
@onready var lock_timer = get_node_or_null("%LockDelayTimer")

# ==============================================================================
# 逻辑组件
# ==============================================================================

var bag: BagRandomizer
var das: DASHandler
var scoring: Scoring

# ==============================================================================
# 运行状态
# ==============================================================================
var cur_type: PieceData.Type
var cur_rot: PieceData.RotationState
var cur_col: int = 0
var cur_row: int = 0

var game_over: bool = false
var paused: bool = false
var held_type: int = -1
var hold_used: bool = false
var lock_resets: int = 0
var lowest_row: int = 0
var gravity_timer: float = 0.0
var last_was_rotation: bool = false
var last_kick_index: int = 0
var next_displays: Array = []

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	_ensure_default_input_actions()

	if board == null or current_piece == null or ghost_piece == null or hold_piece == null or next_container == null or lock_timer == null:
		push_error("[TetrisCore] Required scene nodes are missing. Please verify unique_name_in_owner flags in scene.")
		set_process(false)
		return

	# 初始化逻辑组件
	bag = BagRandomizer.new()
	das = DASHandler.new()
	das.das_delay = das_delay
	das.arr_interval = arr_interval
	scoring = Scoring.new()
	scoring.level = starting_level

	# 收集预览节点
	for child in next_container.get_children():
		if child is Piece:
			next_displays.append(child)

	lock_timer.timeout.connect(_on_lock_timer_timeout)
	
	_update_hold_display()
	_update_next_display()

func _ensure_default_input_actions() -> void:
	pass

func _ensure_action_with_default_keys(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	var events: Array = InputMap.action_get_events(action_name)
	if not events.is_empty():
		return

	for keycode in keycodes:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		InputMap.action_add_event(action_name, ev)

# ==============================================================================
# 核心循环
# ==============================================================================

func process_logic(delta: float) -> void:
	if game_over or paused:
		return
		
	_handle_core_input(delta)
	_update_gravity(delta)
	_update_lock_delay()
	_update_ghost()

# ==============================================================================
# 输入与移动
# ==============================================================================
func _handle_core_input(delta: float) -> void:
	if Input.is_action_just_pressed("rotate_cw"):
		_try_rotate(1)
	if Input.is_action_just_pressed("rotate_ccw"):
		_try_rotate(-1)
	if Input.is_action_just_pressed("rotate_180"):
		_try_rotate(2)

	if Input.is_action_just_pressed("hard_drop"):
		_hard_drop()
		return

	if Input.is_action_just_pressed("hold"):
		_try_hold()

	if Input.is_action_just_pressed("move_left"):
		_try_move(-1, 0)
		das.start(-1)
	if Input.is_action_just_pressed("move_right"):
		_try_move(1, 0)
		das.start(1)

	if Input.is_action_just_released("move_left") and das.direction == -1:
		das.stop()
		if Input.is_action_pressed("move_right"):
			_try_move(1, 0)
			das.start(1)
	if Input.is_action_just_released("move_right") and das.direction == 1:
		das.stop()
		if Input.is_action_pressed("move_left"):
			_try_move(-1, 0)
			das.start(-1)

	var repeat_count: int = das.update(delta)
	for i in range(mini(repeat_count, 20)):
		if not _try_move(das.direction, 0):
			break

func _update_gravity(delta: float) -> void:
	var speed: float = scoring.get_gravity_speed()
	if Input.is_action_pressed("soft_drop"):
		speed = maxf(speed, soft_drop_multiplier)

	gravity_timer += delta * speed
	while gravity_timer >= 1.0:
		gravity_timer -= 1.0
		if _try_move(0, 1):
			last_was_rotation = false
			if Input.is_action_pressed("soft_drop"):
				scoring.add_soft_drop_score(1)
				score_changed.emit(scoring.score, scoring.level, scoring.lines)
		else:
			gravity_timer = 0.0
			break

# ==============================================================================
# 移动/锁定逻辑
# ==============================================================================

func _try_move(dx: int, dy: int) -> bool:
	var new_col: int = cur_col + dx
	var new_row: int = cur_row + dy
	if board.is_valid_position(cur_type, cur_rot, new_col, new_row):
		cur_col = new_col
		cur_row = new_row
		_sync_piece_position()
		# 只要方块位置发生有效位移（左右或上下），都不再把“上一手动作”视为旋转。
		# 这样可以避免“先旋转一次，再硬降到底”被误判为 Spin。
		if dx != 0 or dy != 0:
			last_was_rotation = false
			last_kick_index = 0
		if dx != 0:
			_on_piece_manipulated()
		return true
	return false

func _try_rotate(direction: int) -> bool:
	var new_rot: int
	if direction == 2:
		new_rot = (cur_rot + 2) % 4
	elif direction == 1:
		new_rot = (cur_rot + 1) % 4
	else:
		new_rot = (cur_rot + 3) % 4

	var new_rot_state := new_rot as PieceData.RotationState
	var kicks: Array
	if direction == 2:
		kicks = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]
	else:
		kicks = PieceData.get_wall_kicks(cur_type, cur_rot as PieceData.RotationState, new_rot_state)

	for i in range(kicks.size()):
		var kick: Vector2 = kicks[i]
		var test_col: int = cur_col + int(kick.x)
		var test_row: int = cur_row + int(kick.y)
		if board.is_valid_position(cur_type, new_rot_state, test_col, test_row):
			cur_col = test_col
			cur_row = test_row
			cur_rot = new_rot_state
			current_piece.apply_rotation(cur_rot)
			_sync_piece_position()
			last_was_rotation = true
			last_kick_index = i
			_on_piece_manipulated()
			return true
	return false

func _hard_drop() -> void:
	var cells: int = 0
	while board.is_valid_position(cur_type, cur_rot, cur_col, cur_row + 1):
		cur_row += 1
		cells += 1
	# 硬降属于明显位移动作，落锁前必须清除“上一手是旋转”的状态。
	if cells > 0:
		last_was_rotation = false
		last_kick_index = 0
	scoring.add_hard_drop_score(cells)
	score_changed.emit(scoring.score, scoring.level, scoring.lines)
	_sync_piece_position()
	_lock_piece()

func _update_lock_delay() -> void:
	var grounded: bool = not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row + 1)
	if grounded:
		if lock_timer.is_stopped():
			lock_timer.start()
	else:
		if not lock_timer.is_stopped():
			lock_timer.stop()

func _on_lock_timer_timeout() -> void:
	_lock_piece()

func _on_piece_manipulated() -> void:
	if not lock_timer.is_stopped() and lock_resets < max_lock_resets:
		lock_timer.start()
		lock_resets += 1
	if cur_row > lowest_row:
		lowest_row = cur_row
		lock_resets = 0

# ==============================================================================
# 锁定与消行核心
# ==============================================================================
func _lock_piece() -> void:
	lock_timer.stop()
	board.lock_piece(cur_type, cur_rot, cur_col, cur_row, PieceData.COLORS[cur_type])
	
	# 检查特殊旋转
	var is_spin: bool = false
	if last_was_rotation and _is_spin_piece_type(cur_type):
		is_spin = _check_immobile()

	# 执行消行逻辑
	var cleared: int = board.clear_lines()
	var dmg: int = 0
	if cleared > 0:
		var is_t_spin = (cur_type == PieceData.Type.T and is_spin)
		scoring.process_line_clear(cleared, is_spin, is_t_spin)
		dmg = _calculate_damage(cleared, is_spin)
		lines_cleared.emit(cleared, is_spin, is_t_spin, dmg)
	else:
		scoring.reset_combo()
	
	score_changed.emit(scoring.score, scoring.level, scoring.lines)
	piece_locked.emit(cur_type, board.get_grid_state())
	
	hold_used = false
	_spawn_next_piece()

## 限定可参与 Spin 判定的方块类型。
## O 方块不具备有效旋转中心与踢墙特征，剔除可减少误判。
func _is_spin_piece_type(piece_type: PieceData.Type) -> bool:
	return piece_type != PieceData.Type.O

func _check_immobile() -> bool:
	# 使用四方向不可移动计数（左/右/上/下），满足 >= 3 视为“锁定在狭小空间”。
	# 配合 last_was_rotation，可以更稳地识别真正由旋转导致的卡入。
	var blocked: int = 0
	if not board.is_valid_position(cur_type, cur_rot, cur_col - 1, cur_row):
		blocked += 1
	if not board.is_valid_position(cur_type, cur_rot, cur_col + 1, cur_row):
		blocked += 1
	if not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row - 1):
		blocked += 1
	if not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row + 1):
		blocked += 1
	return blocked >= 3

func _calculate_damage(cleared_count: int, is_spin: bool) -> int:
	var dmg: int = 0
	if is_spin:
		if cleared_count == 1: dmg = 2
		elif cleared_count == 2: dmg = 4
		elif cleared_count == 3: dmg = 6
	else:
		if cleared_count == 2: dmg = 1
		elif cleared_count == 3: dmg = 2
		elif cleared_count >= 4: dmg = 4
	
	# B2B 加成
	if scoring.b2b > 0 and (is_spin or cleared_count >= 4):
		dmg += 1
		
	# Combo 加成
	var combo_table = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5]
	var c_idx = mini(scoring.combo, combo_table.size() - 1)
	if c_idx > 0:
		dmg += combo_table[c_idx]
		
	return dmg

# ==============================================================================
# Hold / Spawn
# ==============================================================================

func _try_hold() -> void:
	if hold_used:
		return
	hold_used = true
	lock_timer.stop()
	if held_type == -1:
		held_type = cur_type
		_update_hold_display()
		_spawn_next_piece()
	else:
		var temp: int = held_type
		held_type = cur_type
		_update_hold_display()
		cur_type = temp as PieceData.Type
		cur_rot = PieceData.RotationState.SPAWN
		cur_col = spawn_col
		cur_row = board.buffer_rows
		_reset_piece_state()
		current_piece.initialize(cur_type)
		_sync_piece_position()

func _spawn_next_piece() -> void:
	cur_type = bag.next()
	cur_rot = PieceData.RotationState.SPAWN
	cur_col = spawn_col
	cur_row = board.buffer_rows
	_reset_piece_state()

	if not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row):
		game_over = true
		game_over_triggered.emit()
		return

	current_piece.initialize(cur_type)
	_sync_piece_position()
	_update_next_display()

func _reset_piece_state() -> void:
	gravity_timer = 0.0
	lock_timer.stop()
	lock_resets = 0
	lowest_row = cur_row
	last_was_rotation = false
	last_kick_index = 0

# ==============================================================================
# 视觉反馈辅助同步
# ==============================================================================

func _sync_piece_position() -> void:
	current_piece.position = Vector2(
		cur_col * board.cell_size,
		(cur_row - board.buffer_rows) * board.cell_size
	)
	board_updated.emit() # 用于同步幽灵块等视觉表现

func _update_ghost() -> void:
	var ghost_row: int = cur_row
	while board.is_valid_position(cur_type, cur_rot, cur_col, ghost_row + 1):
		ghost_row += 1
	ghost_piece.initialize(cur_type)
	ghost_piece.apply_rotation(cur_rot)
	ghost_piece.set_as_ghost()
	ghost_piece.position = Vector2(
		cur_col * board.cell_size,
		(ghost_row - board.buffer_rows) * board.cell_size
	)

func _update_hold_display() -> void:
	if held_type >= 0:
		hold_piece.initialize(held_type as PieceData.Type)
		hold_piece.visible = true
	else:
		hold_piece.visible = false

func _update_next_display() -> void:
	var upcoming: Array = bag.peek(next_displays.size())
	for i in range(mini(upcoming.size(), next_displays.size())):
		next_displays[i].initialize(upcoming[i])
