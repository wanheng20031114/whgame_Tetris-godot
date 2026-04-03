extends TetrisCore

## 双人对战模式脚本
## 继承 TetrisCore，处理网络同步与双人对战逻辑。
# ==============================================================================
# 多人特有变量
# ==============================================================================

@onready var opponent_board: Board = %OpponentBoard
@onready var player_garbage_bar: GarbageBar = %PlayerGarbageBar
@onready var label_player_name: Label = %PlayerNameLabel
@onready var label_status: Label = %StatusLabel
@onready var label_opponent_name: Label = %OpponentNameLabel
@onready var bgm: AudioStreamPlayer = $BGM

# 音效
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_success: AudioStreamPlayer = $SfxSuccess
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

var _status_key: String = "TXT_BATTLE_IN_PROGRESS"
var _status_args: Array = []
var _result_msg_key: String = ""
var _result_center: CenterContainer
var _result_button: Button
const GARBAGE_BAR_GAP: float = 6.0

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	super._ready()
	_initialize_garbage_bar_ui()
	_update_texts()
	_set_status_key("TXT_BATTLE_IN_PROGRESS")
	
	# 连接网络信号
	NetworkManager.board_update_received.connect(_on_opponent_board_updated)
	NetworkManager.attack_received.connect(_on_attack_received)
	NetworkManager.game_over_received.connect(_on_opponent_game_over)
	NetworkManager.opponent_left.connect(_on_opponent_left)
	
	# 本地信号监听 -> 发送给网络
	piece_locked.connect(_on_local_piece_locked)
	lines_cleared.connect(_on_local_lines_cleared)
	game_over_triggered.connect(_on_local_game_over)
	
	# 启动对局
	_spawn_next_piece()
	bgm.play()

## 初始化多人模式受攻击条（仅显示与定位，逻辑仍沿用当前即时受击规则）。
func _initialize_garbage_bar_ui() -> void:
	if player_garbage_bar == null or board == null:
		return

	player_garbage_bar.max_lines = board.visible_rows
	player_garbage_bar.visible = true
	player_garbage_bar.update_bar(0, 0, 0)

	# 多人场景里 Board 嵌套在 Control 容器中，布局会在下一帧完成，
	# 因此使用 deferred 计算坐标，避免初始时机取到错误位置。
	call_deferred("_layout_player_garbage_bar")

## 将多人本地受攻击条贴在本地主棋盘左侧，并匹配棋盘单格像素。
func _layout_player_garbage_bar() -> void:
	if player_garbage_bar == null or board == null:
		return

	var cell_px: float = board.cell_size
	var bar_w: float = cell_px
	var bar_h: float = board.visible_rows * cell_px

	# board 是 Node2D，位于 Control 容器内部；先取全局坐标再转换到当前场景局部坐标。
	var board_top_left_local: Vector2 = to_local(board.global_position)
	var bar_left: float = board_top_left_local.x - GARBAGE_BAR_GAP - bar_w
	var bar_top: float = board_top_left_local.y

	player_garbage_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	player_garbage_bar.offset_left = bar_left
	player_garbage_bar.offset_top = bar_top
	player_garbage_bar.offset_right = bar_left + bar_w
	player_garbage_bar.offset_bottom = bar_top + bar_h

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()
		_set_status_key(_status_key, _status_args)
		_update_result_button_text()

func _trf(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args

func _set_status_key(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	if label_status:
		label_status.text = _trf(_status_key, _status_args)

func _update_texts() -> void:
	if label_player_name:
		label_player_name.text = tr("TXT_PLAYER_LOCAL")

	if label_opponent_name:
		if NetworkManager.opponent_name.strip_edges().is_empty():
			label_opponent_name.text = tr("TXT_WAITING_CONNECT")
		else:
			label_opponent_name.text = NetworkManager.opponent_name

func _update_result_button_text() -> void:
	if not _result_button:
		return
	var msg := tr(_result_msg_key)
	_result_button.text = "%s - %s" % [msg, tr("TXT_CLICK_BACK_LOBBY")]

func _process(delta: float) -> void:
	# 执行核心俄罗斯方块逻辑
	process_logic(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _result_center == null or not is_instance_valid(_result_center):
		return

	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")
		get_viewport().set_input_as_handled()

# ==============================================================================
# 网络发送逻辑（本地行为 -> 服务端）
# ==============================================================================

func _on_local_piece_locked(_type: int, grid_state: Array) -> void:
	# 每次方块锁定时，同步全量棋盘状态给对手
	NetworkManager.sync_board(grid_state)
	sfx_planting.play()

func _on_local_lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, damage: int) -> void:
	# 播放本地消行音效
	if is_spin or is_t_spin or amount >= 4:
		sfx_success.play()
	else:
		sfx_line_clear.play()
		
	# 发送攻击力给对手
	if damage > 0:
		NetworkManager.send_attack(damage)

func _on_local_game_over() -> void:
	NetworkManager.send_game_over()
	_set_status_key("TXT_YOU_LOST")
	sfx_death.play()
	# 弹出返回按钮（简化处理：直接回大厅）
	_show_back_to_lobby_confirm("TXT_GAME_OVER")

# ==============================================================================
# 网络接收逻辑（服务端 -> 本地反馈）
# ==============================================================================

func _on_opponent_board_updated(grid_data: Array) -> void:
	# 更新右侧对手棋盘显示
	if opponent_board:
		opponent_board.set_grid_state(grid_data)

func _on_attack_received(amount: int) -> void:
	# 收到对手的攻击，直接在本地棋盘增加垃圾行
	# (注意：进阶玩法可以先放进等待队列，这里采用直接生效以降低开发复杂度)
	if board:
		board.add_garbage_lines(amount)
		# 可以在此处增加受击震动或音效

func _on_opponent_game_over() -> void:
	_set_status_key("TXT_OPPONENT_DEFEATED")
	# 停止本地逻辑但保留结果显示
	game_over = true
	_show_back_to_lobby_confirm("TXT_VICTORY")

func _on_opponent_left() -> void:
	_set_status_key("TXT_OPPONENT_LEFT")
	game_over = true
	_show_back_to_lobby_confirm("TXT_OPPONENT_LEFT_TITLE")

# ==============================================================================
# UI 辅助
# ==============================================================================

func _show_back_to_lobby_confirm(msg_key: String) -> void:
	# 实际应该做一个弹窗，这里暂时用简单的 Button 覆盖
	_result_msg_key = msg_key

	if _result_center:
		_result_center.queue_free()

	_result_button = Button.new()
	_result_button.custom_minimum_size = Vector2(300, 60)
	_result_button.focus_mode = Control.FOCUS_ALL
	_result_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn"))
	_update_result_button_text()
	
	_result_center = CenterContainer.new()
	_result_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_center.add_child(_result_button)
	add_child(_result_center)
	_result_button.grab_focus()
