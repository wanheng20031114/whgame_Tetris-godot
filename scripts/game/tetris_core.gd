class_name TetrisCore
extends Node2D

## 俄罗斯方块核心逻辑
## 手感对齐 TETR.IO：SRS+ 踢墙、DAS/ARR/SDF/DCD、30 帧锁定延迟 + 15 次重置、
## T 块三角判定（含 Mini）+ 其他块卡死判定（All-Mini+）。
# ==============================================================================
# 信号（用于通知 UI 或网络同步）
# ==============================================================================

signal score_changed(score: int, level: int, lines: int)
signal piece_locked(type: int, grid_state: Array)
signal lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, damage: int)
signal rows_cleared(rows_data: Array) # 传递被消行的详细数据，用于粒子效果
signal game_over_triggered()
signal board_updated()
signal piece_moved(dx: int, dy: int)
signal hard_dropped(cells: int) # 发出时 cur_* 仍是落地前的方块，供落地特效读取

# ==============================================================================
# @export 配置
# ==============================================================================

const T99_DAS_DELAY: float = 10.0 / 60.0
const T99_ARR_INTERVAL: float = 2.0 / 60.0
const T99_LOCK_DELAY: float = 0.5
const T99_SOFT_DROP_SPEED: float = 20.0
const RESULT_INPUT_LOCK_MSEC: int = 800
const PIECE_ACTIONS: Array[StringName] = [
	&"rotate_cw", &"rotate_ccw", &"rotate_180", &"hard_drop", &"hold",
	&"move_left", &"move_right", &"soft_drop",
]

@export_group("核心参数")
@export var spawn_col: int = 4
@export var starting_level: int = 1
@export var das_delay: float = T99_DAS_DELAY
@export var arr_interval: float = T99_ARR_INTERVAL
@export var soft_drop_multiplier: float = T99_SOFT_DROP_SPEED
@export var lock_delay_seconds: float = T99_LOCK_DELAY
@export var max_lock_resets: int = 15

# ==============================================================================
# 节点引用（派生场景需要包含这些节点）
# ==============================================================================

@onready var board = get_node_or_null("%Board")
@onready var current_piece = get_node_or_null("%CurrentPiece")
@onready var ghost_piece = get_node_or_null("%GhostPiece")
@onready var hold_piece: PiecePreview = %HoldPiece
@onready var next_container: VBoxContainer = %NextPieces
@onready var lock_timer = get_node_or_null("%LockDelayTimer")

# ==============================================================================
# 逻辑组件
# ==============================================================================

var bag: BagRandomizer
var das: DASHandler
var scoring: Scoring
var _data_collector: PlayerDataCollector

# ==============================================================================
# 运行状态
# ==============================================================================
var cur_type: PieceData.Type
var cur_rot: PieceData.RotationState
var cur_col: int = 0
var cur_row: int = 0

var game_over: bool = false:
	set(ended):
		game_over = ended
		if ended:
			ghost_piece.hide()
			board.set_danger_level(0.0)
var paused: bool = false
var held_type: int = -1
var hold_used: bool = false
var lock_resets: int = 0
var lowest_row: int = 0
var gravity_timer: float = 0.0
var last_was_rotation: bool = false
var last_kick_index: int = 0
var next_displays: Array[PiecePreview] = []
var lock_sound_played_for_current_lock: bool = false
var last_rotation_was_180: bool = false
var last_spin_mini: bool = false ## 最近一次锁定判定出的 Spin 是否为 Mini
var _last_spin_full: bool = false
var _lock_elapsed: float = 0.0
var danger_level: float = 0.0 ## 0~1，堆叠高度 + 待入场垃圾的危险程度
var _landing_preview_dirty := true
var ready_garbage: int = 0:
	set(amount):
		if ready_garbage != amount:
			ready_garbage = amount
			_landing_preview_dirty = true
var _result_input_ready_msec: int = 0
var _result_pressed_keys: Dictionary[Key, bool] = {}

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	Diagnostics.fatal_shutdown_requested.connect(_trigger_game_over)
	_ensure_default_input_actions()

	if board == null or current_piece == null or ghost_piece == null or hold_piece == null or next_container == null or lock_timer == null:
		push_error("[TetrisCore] Required scene nodes are missing. Please verify unique_name_in_owner flags in scene.")
		set_process(false)
		set_process_input(false)
		return

	# 初始化逻辑组件
	bag = BagRandomizer.new()
	das = DASHandler.new()
	das.das_delay = das_delay
	das.arr_interval = arr_interval
	scoring = Scoring.new()
	scoring.starting_level = starting_level
	scoring.level = starting_level
	lock_timer.wait_time = lock_delay_seconds

	# 收集预览节点
	next_displays.assign(next_container.get_children())

	lock_timer.timeout.connect(_on_lock_timer_timeout)
	ghost_piece.hide()
	SettingsMenu.landing_preview_changed.connect(_update_ghost)
	hard_dropped.connect(_on_hard_drop_fx)
	lines_cleared.connect(_remember_clear_kind)
	rows_cleared.connect(_remember_clear_rows)

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
		
	_sync_handling()
	_update_auto_shift(delta)
	var lock_delta := _update_gravity(delta)
	_update_lock_delay(lock_delta)

## 多人结算切换时，在 GUI 导航、按钮和返回房间的快捷键之前拦截输入。
func _lock_result_input() -> void:
	_result_input_ready_msec = Time.get_ticks_msec() + RESULT_INPUT_LOCK_MSEC
	_result_pressed_keys.clear()

func _input(event: InputEvent) -> void:
	if _result_input_ready_msec > 0:
		_handle_result_input(event)
	elif not game_over and not paused and event.is_action_type() and not event.is_echo():
		_handle_piece_input(event)

func _handle_result_input(event: InputEvent) -> void:
	if Time.get_ticks_msec() < _result_input_ready_msec:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if event.is_echo():
			if not _result_pressed_keys.has(key):
				get_viewport().set_input_as_handled()
		elif event.pressed:
			_result_pressed_keys[key] = true
		else:
			_result_pressed_keys.erase(key)

func _sync_handling() -> void:
	das.das_delay = Handling.das_seconds()
	das.arr_interval = Handling.arr_seconds()

# ==============================================================================
# 输入与移动
# ==============================================================================
## 按事件到达顺序执行。硬降同步锁定并出块，后一按自然作用于新方块。
func _handle_piece_input(event: InputEvent) -> void:
	if not event.is_pressed():
		if event.is_action_released(&"move_left") or event.is_action_released(&"move_right"):
			_update_released_direction()
		return

	for action in PIECE_ACTIONS:
		if not event.is_action_pressed(action):
			continue
		get_viewport().set_input_as_handled()
		if _data_collector and _data_collector.is_active():
			_data_collector.key_presses_this_piece += 1
		match action:
			&"rotate_cw": _try_rotate(1)
			&"rotate_ccw": _try_rotate(-1)
			&"rotate_180": _try_rotate(2)
			&"hard_drop": _hard_drop()
			&"hold": _try_hold()
			&"move_left": _start_horizontal_shift(-1)
			&"move_right": _start_horizontal_shift(1)
			&"soft_drop":
				if Handling.is_instant_soft_drop():
					_soft_drop_to_floor()
				else:
					_drop_one_row(true)
					gravity_timer = 0.0
		if game_over or paused:
			return

func _start_horizontal_shift(direction: int) -> void:
	_try_move(direction, 0)
	if das.direction != direction:
		das.start(direction)

## 同方向可绑定多个键。最后一个绑定松开后，才切回仍按住的另一方向。
func _update_released_direction() -> void:
	if das.direction == 0:
		return
	var left := Input.is_action_pressed(&"move_left")
	var right := Input.is_action_pressed(&"move_right")
	if (das.direction < 0 and left) or (das.direction > 0 and right):
		return
	if left or right:
		_start_horizontal_shift(-das.direction)
	else:
		das.stop()

func _update_auto_shift(delta: float) -> void:
	# 失焦或手柄断开也可能清除引擎的按住状态。
	_update_released_direction()
	var repeat_count: int = das.update(delta)
	for i in range(mini(repeat_count, 20)):
		if not _try_move(das.direction, 0):
			break

## 返回本帧可计入锁定的时间。帧内刚落地时，从最后一次向下移动的时刻开始计时。
func _update_gravity(delta: float) -> float:
	var speed: float = scoring.get_gravity_speed()
	var soft_drop := Input.is_action_pressed(&"soft_drop")
	if soft_drop:
		if Handling.is_instant_soft_drop():
			_soft_drop_to_floor()
			return delta
		speed = Handling.soft_drop_speed(speed)

	var lock_delta := delta
	gravity_timer += delta * speed
	while gravity_timer >= 1.0:
		gravity_timer -= 1.0
		if not _drop_one_row(soft_drop):
			gravity_timer = 0.0
			break
		lock_delta = gravity_timer / speed
	return lock_delta

func _drop_one_row(soft_drop: bool) -> bool:
	if not _try_move(0, 1):
		return false
	if soft_drop:
		scoring.add_soft_drop_score(1)
		score_changed.emit(scoring.score, scoring.level, scoring.lines)
	return true

func _soft_drop_to_floor() -> void:
	var cells: int = 0
	while _try_move(0, 1):
		cells += 1
	if cells > 0:
		scoring.add_soft_drop_score(cells)
		score_changed.emit(scoring.score, scoring.level, scoring.lines)
	gravity_timer = 0.0

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
		if dy > 0 and cur_row > lowest_row:
			# 落到新的最低行：重置次数与锁定计时都清零
			lowest_row = cur_row
			lock_resets = 0
			_lock_elapsed = 0.0
		if dx != 0:
			piece_moved.emit(dx, dy)
			_on_successful_horizontal_move(dx)
			_on_piece_manipulated()
		return true
	return false

func _on_successful_horizontal_move(_dx: int) -> void:
	pass

func _play_piece_lock_sound() -> void:
	pass

func _play_piece_lock_sound_once() -> void:
	if lock_sound_played_for_current_lock:
		return
	lock_sound_played_for_current_lock = true
	_play_piece_lock_sound()

func _try_rotate(direction: int) -> bool:
	var new_rot: int
	if direction == 2:
		new_rot = (cur_rot + 2) % 4
	elif direction == 1:
		new_rot = (cur_rot + 1) % 4
	else:
		new_rot = (cur_rot + 3) % 4

	var new_rot_state := new_rot as PieceData.RotationState
	var kicks: Array = PieceData.get_wall_kicks(cur_type, cur_rot as PieceData.RotationState, new_rot_state)

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
			last_rotation_was_180 = direction == 2
			_on_piece_manipulated()
			if das.direction != 0 and not board.is_valid_position(cur_type, cur_rot, cur_col + das.direction, cur_row):
				das.cut(Handling.dcd_seconds())
			return true
	return false

func _hard_drop() -> void:
	var landing_row := _get_landing_row()
	var cells := landing_row - cur_row
	cur_row = landing_row
	# 硬降属于明显位移动作，落锁前必须清除“上一手是旋转”的状态。
	if cells > 0:
		last_was_rotation = false
		last_kick_index = 0
	scoring.add_hard_drop_score(cells)
	score_changed.emit(scoring.score, scoring.level, scoring.lines)
	_sync_piece_position()
	hard_dropped.emit(cells)
	_play_piece_lock_sound_once()
	_lock_piece()

## TETR.IO 规则：着地时累计锁定时间；重置次数用尽后一着地就立即锁定。
func _update_lock_delay(delta: float) -> void:
	var grounded: bool = not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row + 1)
	if not grounded:
		return
	_lock_elapsed += delta
	if lock_resets >= max_lock_resets or _lock_elapsed >= lock_delay_seconds:
		_lock_piece()

func _on_lock_timer_timeout() -> void:
	pass

## 每次成功移动/旋转都消耗一次重置（空中也算），未用尽时锁定计时归零。
func _on_piece_manipulated() -> void:
	if lock_resets < max_lock_resets:
		lock_resets += 1
		if lock_resets < max_lock_resets:
			_lock_elapsed = 0.0

# ==============================================================================
# 锁定与消行核心
# ==============================================================================
func _lock_piece() -> void:
	lock_timer.stop()
	var is_spin: bool = _resolve_spin()
	board.lock_piece(cur_type, cur_rot, cur_col, cur_row, PieceData.COLORS[cur_type])
	
	# 检查特殊旋转

	# 执行消行逻辑（使用含数据版本，用于生成粒子效果）
	var clear_result: Dictionary = board.clear_lines_with_data()
	var cleared: int = clear_result["cleared"]
	var cleared_rows_data: Array = clear_result["rows_data"]
	var dmg: int = 0
	if cleared > 0:
		var is_t_spin = _is_full_t_spin()
		scoring.process_line_clear(cleared, is_spin, is_t_spin)
		dmg = _calculate_damage(cleared, is_spin, is_t_spin)
		lines_cleared.emit(cleared, is_spin, is_t_spin, dmg)
		rows_cleared.emit(cleared_rows_data)
	else:
		scoring.reset_combo()
	
	score_changed.emit(scoring.score, scoring.level, scoring.lines)
	piece_locked.emit(cur_type, board.get_grid_state())
	
	hold_used = false
	_spawn_next_piece(cleared > 0)

## 限定可参与 Spin 判定的方块类型。
## O 方块不具备有效旋转中心与踢墙特征，剔除可减少误判。
func _is_spin_piece_type(piece_type: PieceData.Type) -> bool:
	return piece_type != PieceData.Type.O

## 卡死判定（TETR.IO All-Spin）：左、右、上、下四个方向都无法移动。
func _check_immobile() -> bool:
	return (
		not board.is_valid_position(cur_type, cur_rot, cur_col - 1, cur_row)
		and not board.is_valid_position(cur_type, cur_rot, cur_col + 1, cur_row)
		and not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row - 1)
		and not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row + 1)
	)

## 在锁定前调用：返回本次是否为 Spin，并记录是否为 Mini（规则同 TETR.IO All-Mini+）。
## T 块：三角判定 >=3 角为 Spin，前两角都被占或 TST/Fin 踢墙为完整 T-Spin，否则 Mini；
## 其他方块与三角判定失败的 T：卡死则为 Mini Spin。
func _resolve_spin() -> bool:
	last_spin_mini = false
	_last_spin_full = false
	if not last_was_rotation or not _is_spin_piece_type(cur_type):
		return false
	if cur_type == PieceData.Type.T:
		var corners := _t_corner_counts()
		if corners.x >= 3:
			var into_side := cur_rot == PieceData.RotationState.R or cur_rot == PieceData.RotationState.L
			var tst_kick := last_kick_index == 4 and not last_rotation_was_180 and into_side
			_last_spin_full = corners.y >= 2 or tst_kick
			last_spin_mini = not _last_spin_full
			return true
	if _check_immobile():
		last_spin_mini = true
		return true
	return false

func _is_full_t_spin() -> bool:
	return cur_type == PieceData.Type.T and _last_spin_full

const _T_CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
## 每个朝向“前方”两个角在 _T_CORNERS 中的下标
const _T_FRONT: Dictionary = {0: [0, 1], 1: [1, 2], 2: [2, 3], 3: [3, 0]}

## 返回 (占用角数, 其中前方角数)。墙外与底外视为占用。
func _t_corner_counts() -> Vector2i:
	var total: int = 0
	var front: int = 0
	var front_idx: Array = _T_FRONT[int(cur_rot)]
	for i in range(4):
		var c: int = cur_col + _T_CORNERS[i].x
		var r: int = cur_row + _T_CORNERS[i].y
		var filled: bool = c < 0 or c >= board.columns or r >= board.total_rows or (r >= 0 and board.grid[r][c] != null)
		if filled:
			total += 1
			if i in front_idx:
				front += 1
	return Vector2i(total, front)

func _calculate_damage(cleared_count: int, is_spin: bool, is_t_spin: bool) -> int:
	var dmg: int = 0
	if is_t_spin:
		if cleared_count == 1: dmg = 2
		elif cleared_count == 2: dmg = 4
		elif cleared_count == 3: dmg = 6
	else:
		if cleared_count == 2: dmg = 1
		elif cleared_count == 3: dmg = 2
		elif cleared_count >= 4: dmg = 4
	
	# B2B 加成
	if scoring.b2b > 0 and ((is_spin and cleared_count > 0) or is_t_spin or cleared_count >= 4):
		dmg += 1
		
	# Combo 加成
	var combo_table = [0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5]
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
		_activate_piece(temp as PieceData.Type)

func _spawn_next_piece(after_clear: bool = false) -> void:
	_activate_piece(bag.next(), after_clear)

## 普通出块和暂存换块共用出生位置与碰撞判定。
func _activate_piece(piece_type: PieceData.Type, after_clear: bool = false) -> bool:
	lock_sound_played_for_current_lock = false
	cur_type = piece_type
	cur_rot = PieceData.RotationState.SPAWN
	cur_col = spawn_col
	cur_row = board.find_spawn_row(cur_type, cur_col, board.grid, after_clear)
	current_piece.initialize(cur_type)
	if cur_row < 0:
		cur_row = board.buffer_rows - 1
		current_piece.set_as_ghost(true)
		_sync_piece_position()
		_trigger_game_over()
		return false
	_reset_piece_state()
	_sync_piece_position()
	_update_next_display()
	_update_danger_warning_state()
	return true

func _trigger_game_over() -> void:
	if game_over:
		return
	game_over = true
	game_over_triggered.emit()

func _reset_piece_state() -> void:
	gravity_timer = 0.0
	lock_timer.stop()
	lock_resets = 0
	_lock_elapsed = 0.0
	lowest_row = cur_row
	last_was_rotation = false
	last_rotation_was_180 = false
	last_kick_index = 0

# ==============================================================================
# 视觉反馈辅助同步
# ==============================================================================

func _sync_piece_position() -> void:
	board.frame_active_piece(cur_row)
	current_piece.global_position = board.to_global(board.cell_position(cur_col, cur_row))
	_landing_preview_dirty = true
	board_updated.emit()

func _get_landing_row() -> int:
	var row := cur_row
	while board.is_valid_position(cur_type, cur_rot, cur_col, row + 1):
		row += 1
	return row

func _update_ghost(enabled: bool) -> void:
	_landing_preview_dirty = false
	if game_over or paused or (not enabled and danger_level <= 0.0):
		ghost_piece.hide()
		return
	var ghost_row := _get_landing_row()
	var lethal := false
	if danger_level > 0.0:
		lethal = board.would_block_next_spawn(cur_type, cur_rot, Vector2i(cur_col, ghost_row), bag.peek(1)[0], spawn_col, ready_garbage)
	ghost_piece.visible = lethal or (enabled and ghost_row > cur_row)
	if not ghost_piece.visible:
		return
	ghost_piece.initialize(cur_type)
	ghost_piece.apply_rotation(cur_rot)
	ghost_piece.set_as_ghost(lethal)
	ghost_piece.global_position = board.to_global(board.cell_position(cur_col, ghost_row))

func _update_hold_display() -> void:
	hold_piece.set_piece(held_type)

func _update_next_display() -> void:
	var upcoming: Array = bag.peek(next_displays.size())
	for i in next_displays.size():
		next_displays[i].set_piece(upcoming[i])

## 危险程度：堆叠高度 + 待入场垃圾。剩余空间 <= 7 行开始提示，<= 3 行达到满值。
func _update_danger_warning_state() -> void:
	var effective: int = board.get_stack_height() + mini(_incoming_garbage_total(), board.visible_rows)
	var free_rows: int = board.visible_rows - effective
	danger_level = clampf(float(8 - free_rows) / 5.0, 0.0, 1.0)
	board.set_danger_level(danger_level)
	if _landing_preview_dirty:
		_update_ghost(SettingsMenu.landing_preview_enabled)

## 子类返回尚未入场的垃圾总行数，用于危险提示。
func _incoming_garbage_total() -> int:
	return 0

# ==============================================================================
# 对局特效（三个对局场景共用）
# ==============================================================================

## 连击音阶：前 7 连按大调音阶上行，之后每连击再升半音，最高 +19 半音
const _COMBO_SCALE: Array[int] = [0, 2, 4, 5, 7, 9, 11, 12]

var _fx_clear_count: int = 0
var _fx_spin: bool = false
var _fx_t_spin: bool = false
var _fx_piece_type: PieceData.Type = PieceData.Type.I
var _fx_clear_y: float = -1.0 ## 最近一次消除行中心（棋盘本地 y）

func _combo_pitch() -> float:
	var c: int = maxi(scoring.combo, 0)
	var semi: int = _COMBO_SCALE[c] if c < _COMBO_SCALE.size() else mini(12 + c - (_COMBO_SCALE.size() - 1), 19)
	return pow(2.0, float(semi) / 12.0)

## 消行音效：音调随连击升高
func _play_clear_sfx(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.pitch_scale = _combo_pitch()
	player.play()

func _remember_clear_kind(amount: int, is_spin: bool, is_t_spin: bool, _dmg: int) -> void:
	_fx_clear_count = amount
	_fx_spin = is_spin
	_fx_t_spin = is_t_spin
	_fx_piece_type = cur_type

func _remember_clear_rows(rows_data: Array) -> void:
	if rows_data.is_empty():
		return
	var sum := 0.0
	for row_data in rows_data:
		sum += (float(int(row_data["row_index"]) - board.view_top_row) + 0.5) * board.cell_size
	_fx_clear_y = sum / rows_data.size()

## 本次消除的代表色：T-Spin 紫、四消青、其他 Spin 取方块色、普通消行暖白
func _clear_tint() -> Color:
	if _fx_t_spin:
		return PieceData.COLORS[PieceData.Type.T]
	if _fx_clear_count >= 4:
		return PieceData.COLORS[PieceData.Type.I]
	if _fx_spin:
		return PieceData.COLORS[_fx_piece_type]
	return Color.WHITE

func _attack_color() -> Color:
	var tint := _clear_tint()
	return Color(1.0, 0.86, 0.55) if tint == Color.WHITE else tint

## 消行特效：光带 + 碎片 + 棋盘轻震；强度随行数与连击提升
func _spawn_line_clear_fx(rows_data: Array) -> void:
	if board == null or rows_data.is_empty():
		return
	var level := VisualEffects.get_level(VisualEffects.LINE_CLEAR)
	if level != VisualEffects.Level.OFF:
		var power := clampf(float(rows_data.size() - 1) / 3.0 + maxi(scoring.combo, 0) * 0.08, 0.0, 1.0)
		var fx := LineClearEffect.new()
		board.add_child(fx)
		fx.setup(rows_data, board.cell_size, board.view_top_row, _clear_tint(), power, level == VisualEffects.Level.LIGHT)
	board.bump(Vector2(0, 1.5 + rows_data.size() * 0.8))

func _on_hard_drop_fx(cells: int) -> void:
	if cells > 0:
		HardDropTrail.spawn(board, cur_type, cur_rot, cur_col, cur_row - cells, cur_row)
	board.bump(Vector2(0, clampf(1.5 + cells * 0.18, 1.5, 4.5)))

## 棋盘可见区在画布上的矩形
func _board_canvas_rect() -> Rect2:
	var xf: Transform2D = board.get_global_transform_with_canvas()
	return Rect2(xf.origin, Vector2(board.columns, board.visible_rows) * board.cell_size * xf.get_scale())

## 攻击弹的出发点：消除行所在高度、靠近目标一侧的棋盘边缘
func _clear_origin(toward_x: float) -> Vector2:
	var r := _board_canvas_rect()
	var local_y: float = _fx_clear_y if _fx_clear_y >= 0.0 else board.visible_rows * board.cell_size * 0.5
	var y: float = r.position.y + local_y * board.get_global_transform_with_canvas().get_scale().y
	return Vector2(r.end.x if toward_x >= r.get_center().x else r.position.x, y)

## 发出攻击弹（延迟一帧，确保消除行位置已记录）
func _fire_outgoing(target: Vector2, amount: int, on_impact: Callable = Callable()) -> void:
	call_deferred("_fire_outgoing_now", target, amount, on_impact)

func _fire_outgoing_now(target: Vector2, amount: int, on_impact: Callable) -> void:
	var from := _clear_origin(target.x)
	var shots := clampi(int(ceil(amount / 4.0)), 1, 3)
	for i in range(shots):
		var cb := on_impact if i == shots - 1 else Callable()
		AttackFX.fire(self, from, target, ceili(float(amount) / shots), _attack_color(), NAN, cb, i * 0.06)

## 抵消：攻击弹飞进自己的垃圾槽
func _fire_cancel(bar: GarbageBar, amount: int) -> void:
	if bar == null or amount <= 0:
		return
	var to := bar.get_global_transform_with_canvas() * bar.get_queue_top_local()
	_fire_outgoing(to, amount, bar.flash_impact)

## 受击：攻击弹从 from 飞进自己的垃圾槽；来源在棋盘右侧时从棋盘上方绕过，不穿过操作区
func _fire_incoming(from: Vector2, bar: GarbageBar, amount: int) -> void:
	if bar == null or amount <= 0:
		return
	var to := bar.get_global_transform_with_canvas() * bar.get_queue_top_local()
	var r := _board_canvas_rect()
	var apex := NAN
	if from.x > r.position.x:
		apex = maxf(r.position.y - 34.0, 6.0)
	AttackFX.fire(self, from, to, amount, GarbageBar.COL_RED.lightened(0.15), apex, func():
		if is_instance_valid(bar):
			bar.flash_impact()
		if is_instance_valid(board):
			board.bump(Vector2(-2.0, 0)))
