class_name GameScene
extends Node2D

## 游戏主场景控制器
##
## 所有可视节点均在 game.tscn 中预先搭建：
## - Background (ColorRect)、HoldPanel/NextPanel (Panel) → 替代 _draw()
## - AudioStreamPlayer ×6 → 音效系统
## - Timer → 锁定延迟
## 纯逻辑类 (BagRandomizer, DASHandler, Scoring) 保留 .new()

# ==============================================================================
# @export 可调参数（全部暴露到检查器，方便调试和微调）
# ==============================================================================

@export_group("游戏参数")
## 方块出生列（0-indexed，标准 10 列棋盘中取 4 即第 5 列居中）
@export var spawn_col: int = 4
## 起始等级（影响初始下落速度）
@export var starting_level: int = 1

@export_group("操作手感 DAS/ARR")
## DAS 延迟（秒）：按住方向键多久后开始连续移动
@export var das_delay: float = 0.180
## ARR 间隔（秒）：连续移动之间的间隔。0 = 瞬移到墙边
@export var arr_interval: float = 0.020
## 软降速度倍率：按住软降键时的下落加速倍数
@export var soft_drop_multiplier: float = 20.0

@export_group("锁定延迟")
## 最大重置次数：玩家操作可重置锁定倒计时的上限
@export var max_lock_resets: int = 15

# ==============================================================================
# @onready 节点引用（全部从场景树获取）
# ==============================================================================

@onready var board: Board = $Board
@onready var current_piece: Piece = $Board/CurrentPiece
@onready var ghost_piece: Piece = $Board/GhostPiece
@onready var hold_piece: Piece = $HoldPiece
@onready var next_container: Node2D = $NextPieces
@onready var lock_timer: Timer = $LockDelayTimer

## HUD 标签
@onready var label_score: Label = $HUD/ScoreLabel
@onready var label_level: Label = $HUD/LevelLabel
@onready var label_lines: Label = $HUD/LinesLabel
@onready var label_game_over: Label = $HUD/GameOverLabel

## Game Over UI 覆盖集
var game_over_panel: PanelContainer
var btn_restart: Button
var btn_return: Button

## 音效播放器（stream 在 _ready 中通过 load() 加载，也可在检查器中手动更换）
@onready var bgm: AudioStreamPlayer = $BGM
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_success: AudioStreamPlayer = $SfxSuccess
@onready var sfx_death: AudioStreamPlayer = $SfxDeath
@onready var sfx_click: AudioStreamPlayer = $SfxClick

# ==============================================================================
# 纯逻辑子系统（非 Node，代码实例化是正确做法）
# ==============================================================================

var bag: BagRandomizer
var das: DASHandler
var scoring: Scoring

# ==============================================================================
# 当前方块逻辑状态
# ==============================================================================

var cur_type: PieceData.Type
var cur_rot: PieceData.RotationState
var cur_col: int = 0
var cur_row: int = 0

# ==============================================================================
# 游戏状态
# ==============================================================================

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
	# 注册默认键位
	_setup_input_actions()
	
	# 强制保证背景节点永远在最底层并且拉伸全图
	var custom_bg = get_node_or_null("CustomBackground")
	if custom_bg:
		move_child(custom_bg, 0)
		custom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		custom_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		custom_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
	# 隐藏旧的纯色背景防止遮挡
	var old_bg = get_node_or_null("Background")
	if old_bg:
		old_bg.queue_free()
	
	# 设置玻璃拟态边框并初始化多语言静态 Label
	var hold_panel = get_node_or_null("HoldPanel")
	if hold_panel and hold_panel.has_theme_stylebox("panel"):
		var sb = hold_panel.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = Color(0, 0, 0, 0.5)
			sb.border_color = Color(0.4, 0.4, 0.6, 0.8)
			
	var next_panel = get_node_or_null("NextPanel")
	if next_panel and next_panel.has_theme_stylebox("panel"):
		var sb = next_panel.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = Color(0, 0, 0, 0.5)
			sb.border_color = Color(0.4, 0.4, 0.6, 0.8)
			
	# 初始化 Game Over UI
	game_over_panel = PanelContainer.new()
	var sb_go = StyleBoxFlat.new()
	sb_go.bg_color = Color(0, 0, 0, 0.85)
	game_over_panel.add_theme_stylebox_override("panel", sb_go)
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.hide()
	
	var go_vbox = VBoxContainer.new()
	go_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	go_vbox.add_theme_constant_override("separation", 20)
	
	btn_restart = Button.new()
	btn_restart.custom_minimum_size = Vector2(240, 50)
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	
	btn_return = Button.new()
	btn_return.custom_minimum_size = Vector2(240, 50)
	btn_return.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main.tscn"))
	
	go_vbox.add_child(btn_restart)
	go_vbox.add_child(btn_return)
	
	var go_center = CenterContainer.new()
	go_center.add_child(go_vbox)
	game_over_panel.add_child(go_center)
	
	var hud = get_node_or_null("HUD")
	if hud:
		hud.add_child(game_over_panel)
	else:
		add_child(game_over_panel)
			
	_update_texts()

	# 初始化纯逻辑子系统，并将检查器导出的参数传入
	bag = BagRandomizer.new()
	das = DASHandler.new()
	das.das_delay = das_delay
	das.arr_interval = arr_interval
	scoring = Scoring.new()
	scoring.level = starting_level

	# 从场景树收集 Next 预览方块节点
	for child in next_container.get_children():
		if child is Piece:
			next_displays.append(child)

	# 连接 Timer 信号
	lock_timer.timeout.connect(_on_lock_timer_timeout)

	# BGM 
	bgm.play()

	# 开始第一个方块
	_spawn_next_piece()

func _process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("game_over_restart"):
			get_tree().reload_current_scene()
		elif Input.is_action_just_pressed("game_over_return"):
			get_tree().change_scene_to_file("res://scenes/ui/main.tscn")
		return
		
	if paused:
		return
	_handle_input(delta)
	_update_gravity(delta)
	_update_lock_delay()
	_update_ghost()
	_update_hud()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()

func _update_texts() -> void:
	var hold_label = get_node_or_null("HUD/HoldLabel")
	if hold_label: hold_label.text = tr("TXT_HOLD")
	var next_label = get_node_or_null("HUD/NextLabel")
	if next_label: next_label.text = tr("TXT_NEXT")
	if game_over and label_game_over:
		label_game_over.text = tr("TXT_GAME_OVER")
	if btn_restart: btn_restart.text = tr("TXT_RESTART")
	if btn_return: btn_return.text = tr("TXT_RETURN_LOBBY")

# ==============================================================================
# 音效播放（stream 已在编辑器检查器中分配，这里只调用 .play() / .stop()）
# ==============================================================================

## 方块放置音效
func _play_planting() -> void:
	sfx_planting.play()

## 消行音效：Tetris（4 行）或 Spin → success，其他 → line_clear
func _play_clear_sfx(lines_cleared: int, is_special: bool) -> void:
	if is_special or lines_cleared >= 4:
		sfx_success.play()
	else:
		sfx_line_clear.play()

## 死亡音效：停止 BGM，播放死亡音
func _play_death() -> void:
	bgm.stop()
	sfx_death.play()

# ==============================================================================
# 输入处理
# ==============================================================================

func _handle_input(delta: float) -> void:
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

# ==============================================================================
# 重力（手动 delta 累加——速度动态变化，不适合 Timer 节点）
# ==============================================================================

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
		else:
			gravity_timer = 0.0
			break

# ==============================================================================
# 锁定延迟（Timer 节点驱动）
# ==============================================================================

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

# ==============================================================================
# 方块移动 / 旋转 / 硬降
# ==============================================================================

func _try_move(dx: int, dy: int) -> bool:
	var new_col: int = cur_col + dx
	var new_row: int = cur_row + dy
	if board.is_valid_position(cur_type, cur_rot, new_col, new_row):
		cur_col = new_col
		cur_row = new_row
		_sync_piece_position()
		if dx != 0:
			last_was_rotation = false
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
		kicks = [Vector2(0,0), Vector2(0,1), Vector2(1,0), Vector2(-1,0), Vector2(0,-1)]
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
	scoring.add_hard_drop_score(cells)
	_sync_piece_position()
	_lock_piece()

# ==============================================================================
# 方块锁定（+ 音效触发）
# ==============================================================================

func _lock_piece() -> void:
	lock_timer.stop()
	board.lock_piece(cur_type, cur_rot, cur_col, cur_row, PieceData.COLORS[cur_type])

	# 播放放置音效
	_play_planting()

	# Spin 判定
	var is_spin: bool = false
	if last_was_rotation:
		is_spin = _check_immobile()

	# 消行
	var cleared: int = board.clear_lines()
	if cleared > 0:
		scoring.process_line_clear(cleared, is_spin, cur_type == PieceData.Type.T)
		# 播放消行音效（Tetris/Spin → 特殊音效，其他 → 普通音效）
		_play_clear_sfx(cleared, is_spin)
	else:
		scoring.reset_combo()

	board.queue_redraw()
	hold_used = false
	_spawn_next_piece()

func _check_immobile() -> bool:
	var blocked: int = 0
	if not board.is_valid_position(cur_type, cur_rot, cur_col - 1, cur_row):
		blocked += 1
	if not board.is_valid_position(cur_type, cur_rot, cur_col + 1, cur_row):
		blocked += 1
	if not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row - 1):
		blocked += 1
	return blocked >= 3

# ==============================================================================
# Hold 暂存
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

# ==============================================================================
# 方块生成（+ Game Over 音效）
# ==============================================================================

func _spawn_next_piece() -> void:
	cur_type = bag.next()
	cur_rot = PieceData.RotationState.SPAWN
	cur_col = spawn_col
	cur_row = board.buffer_rows
	_reset_piece_state()

	if not board.is_valid_position(cur_type, cur_rot, cur_col, cur_row):
		game_over = true
		if label_game_over:
			label_game_over.text = tr("TXT_GAME_OVER")
			label_game_over.visible = true
		if game_over_panel:
			game_over_panel.show()
			btn_restart.grab_focus()
		_play_death()
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
# 锁定延迟重置
# ==============================================================================

func _on_piece_manipulated() -> void:
	if not lock_timer.is_stopped() and lock_resets < max_lock_resets:
		lock_timer.start()
		lock_resets += 1
	if cur_row > lowest_row:
		lowest_row = cur_row
		lock_resets = 0

# ==============================================================================
# 幽灵方块
# ==============================================================================

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

# ==============================================================================
# Hold / Next 显示
# ==============================================================================

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

# ==============================================================================
# 同步方块位置
# ==============================================================================

func _sync_piece_position() -> void:
	current_piece.position = Vector2(
		cur_col * board.cell_size,
		(cur_row - board.buffer_rows) * board.cell_size
	)

# ==============================================================================
# HUD 更新
# ==============================================================================

func _update_hud() -> void:
	label_score.text = "%s\n%d" % [tr("TXT_SCORE"), scoring.score]
	label_level.text = "%s\n%d" % [tr("TXT_LEVEL"), scoring.level]
	label_lines.text = "%s\n%d" % [tr("TXT_LINES"), scoring.lines]

# ==============================================================================
# 输入动作注册
# ==============================================================================

func _setup_input_actions() -> void:
	var actions: Dictionary = {
		"move_left": [
			{"type": "key", "val": KEY_LEFT},
			{"type": "joy_btn", "val": JOY_BUTTON_DPAD_LEFT}
		],
		"move_right": [
			{"type": "key", "val": KEY_RIGHT},
			{"type": "joy_btn", "val": JOY_BUTTON_DPAD_RIGHT}
		],
		"soft_drop": [
			{"type": "key", "val": KEY_DOWN},
			{"type": "joy_btn", "val": JOY_BUTTON_DPAD_DOWN}
		],
		"hard_drop": [
			{"type": "key", "val": KEY_SPACE},
			{"type": "joy_btn", "val": JOY_BUTTON_B}
		],
		"rotate_cw": [
			{"type": "key", "val": KEY_UP},
			{"type": "joy_btn", "val": JOY_BUTTON_DPAD_UP},
			{"type": "joy_btn", "val": JOY_BUTTON_RIGHT_SHOULDER},
			{"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "val": 1.0}
		],
		"rotate_ccw": [
			{"type": "key", "val": KEY_Z},
			{"type": "joy_btn", "val": JOY_BUTTON_LEFT_SHOULDER},
			{"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "val": 1.0}
		],
		"rotate_180": [
			{"type": "key", "val": KEY_A}
		],
		"hold": [
			{"type": "key", "val": KEY_C},
			{"type": "joy_btn", "val": JOY_BUTTON_A}
		],
		"pause": [
			{"type": "key", "val": KEY_ESCAPE},
			{"type": "joy_btn", "val": JOY_BUTTON_START}
		],
		"game_over_restart": [
			{"type": "key", "val": KEY_ENTER},
			{"type": "joy_btn", "val": JOY_BUTTON_A}
		],
		"game_over_return": [
			{"type": "key", "val": KEY_ESCAPE},
			{"type": "key", "val": KEY_BACKSPACE},
			{"type": "joy_btn", "val": JOY_BUTTON_B}
		]
	}
	
	for action_name in actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for input_cfg in actions[action_name]:
			var event
			if input_cfg["type"] == "key":
				event = InputEventKey.new()
				event.physical_keycode = input_cfg["val"]
			elif input_cfg["type"] == "joy_btn":
				event = InputEventJoypadButton.new()
				event.button_index = input_cfg["val"]
			elif input_cfg["type"] == "joy_axis":
				event = InputEventJoypadMotion.new()
				event.axis = input_cfg["axis"]
				event.axis_value = input_cfg["val"]
			
			if event != null:
				InputMap.action_add_event(action_name, event)
