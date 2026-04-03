extends TetrisCore

## 双人对战模式脚本。
## 重点职责：
## 1) 本地棋盘逻辑（继承 TetrisCore）；
## 2) 网络同步（棋盘状态、攻击、结算）；
## 3) 对战 UI（状态文本、返回大厅按钮）；
## 4) 本地音效反馈（普通消行 / 四消 / Spin 消除）。

# ------------------------------------------------------------------------------
# 节点引用
# ------------------------------------------------------------------------------
@onready var opponent_board: Board = %OpponentBoard
@onready var player_garbage_bar: GarbageBar = %PlayerGarbageBar
@onready var label_player_name: Label = %PlayerNameLabel
@onready var label_status: Label = %StatusLabel
@onready var label_opponent_name: Label = %OpponentNameLabel
@onready var bgm: AudioStreamPlayer = $BGM

@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_tetris: AudioStreamPlayer = $SfxSuccess
@onready var sfx_spin: AudioStreamPlayer = $SfxSpin
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

# ------------------------------------------------------------------------------
# 资源预载
# ------------------------------------------------------------------------------
const BGM_STREAM: AudioStream = preload("res://audio/bgm.ogg")
const SFX_PLANTING_STREAM: AudioStream = preload("res://audio/planting.ogg")
const SFX_LINE_CLEAR_STREAM: AudioStream = preload("res://audio/line_clear.ogg")
const SFX_TETRIS_STREAM: AudioStream = preload("res://audio/tetris.ogg")
const SFX_SPIN_STREAM: AudioStream = preload("res://audio/spin.ogg")
const SFX_DEATH_STREAM: AudioStream = preload("res://audio/death.ogg")

# ------------------------------------------------------------------------------
# 状态变量
# ------------------------------------------------------------------------------
var _status_key: String = "TXT_BATTLE_IN_PROGRESS"
var _status_args: Array = []
var _result_msg_key: String = ""
var _result_center: CenterContainer
var _result_button: Button

# 受攻击条贴边间距，与单人保持一致。
const GARBAGE_BAR_GAP: float = 6.0


# ------------------------------------------------------------------------------
# 生命周期
# ------------------------------------------------------------------------------
func _ready() -> void:
	super._ready()
	_assign_audio_streams()
	_initialize_garbage_bar_ui()
	_update_texts()
	_set_status_key("TXT_BATTLE_IN_PROGRESS")

	# 连接网络信号。
	NetworkManager.board_update_received.connect(_on_opponent_board_updated)
	NetworkManager.attack_received.connect(_on_attack_received)
	NetworkManager.game_over_received.connect(_on_opponent_game_over)
	NetworkManager.opponent_left.connect(_on_opponent_left)

	# 本地核心信号 -> 网络发送。
	piece_locked.connect(_on_local_piece_locked)
	lines_cleared.connect(_on_local_lines_cleared)
	game_over_triggered.connect(_on_local_game_over)

	_spawn_next_piece()
	bgm.play()

## 显式设置多人场景的音频流，避免场景漏配时出现无声。
func _assign_audio_streams() -> void:
	if bgm and bgm.stream == null:
		bgm.stream = BGM_STREAM
	if sfx_planting:
		sfx_planting.stream = SFX_PLANTING_STREAM
	if sfx_line_clear:
		sfx_line_clear.stream = SFX_LINE_CLEAR_STREAM
	if sfx_tetris:
		sfx_tetris.stream = SFX_TETRIS_STREAM
	if sfx_spin:
		sfx_spin.stream = SFX_SPIN_STREAM
	if sfx_death:
		sfx_death.stream = SFX_DEATH_STREAM


# ------------------------------------------------------------------------------
# 受攻击条 UI
# ------------------------------------------------------------------------------
## 初始化多人受攻击条（定位 + 可见性）。
func _initialize_garbage_bar_ui() -> void:
	if player_garbage_bar == null or board == null:
		return

	player_garbage_bar.max_lines = board.visible_rows
	player_garbage_bar.visible = true
	player_garbage_bar.update_bar(0, 0, 0)

	# 多人场景中 board 位于容器层级内，布局要等到下一帧稳定后再计算。
	call_deferred("_layout_player_garbage_bar")

## 将多人本地受攻击条贴在主棋盘左侧，且保证格子像素完全一致。
func _layout_player_garbage_bar() -> void:
	if player_garbage_bar == null or board == null:
		return

	var cell_px: float = board.cell_size
	var bar_w: float = cell_px
	var bar_h: float = board.visible_rows * cell_px

	# 先取 board 全局坐标，再转成当前节点本地坐标，避免容器嵌套偏移误差。
	var board_top_left_local: Vector2 = to_local(board.global_position)
	var bar_left: float = board_top_left_local.x - GARBAGE_BAR_GAP - bar_w
	var bar_top: float = board_top_left_local.y

	player_garbage_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	player_garbage_bar.offset_left = bar_left
	player_garbage_bar.offset_top = bar_top
	player_garbage_bar.offset_right = bar_left + bar_w
	player_garbage_bar.offset_bottom = bar_top + bar_h


# ------------------------------------------------------------------------------
# 通用回调
# ------------------------------------------------------------------------------
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
	process_logic(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _result_center == null or not is_instance_valid(_result_center):
		return

	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


# ------------------------------------------------------------------------------
# 本地 -> 网络
# ------------------------------------------------------------------------------
func _on_local_piece_locked(_type: int, grid_state: Array) -> void:
	NetworkManager.sync_board(grid_state)
	sfx_planting.play()

func _on_local_lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, damage: int) -> void:
	# 与单人保持一致的音效规则。
	if is_spin or is_t_spin:
		if sfx_spin:
			sfx_spin.play()
	elif amount == 4:
		if sfx_tetris:
			sfx_tetris.play()
	else:
		if sfx_line_clear:
			sfx_line_clear.play()

	if damage > 0:
		NetworkManager.send_attack(damage)

func _on_local_game_over() -> void:
	NetworkManager.send_game_over()
	_set_status_key("TXT_YOU_LOST")
	sfx_death.play()
	_show_back_to_lobby_confirm("TXT_GAME_OVER")


# ------------------------------------------------------------------------------
# 网络 -> 本地
# ------------------------------------------------------------------------------
func _on_opponent_board_updated(grid_data: Array) -> void:
	if opponent_board:
		opponent_board.set_grid_state(grid_data)

func _on_attack_received(amount: int) -> void:
	if board:
		board.add_garbage_lines(amount)

func _on_opponent_game_over() -> void:
	_set_status_key("TXT_OPPONENT_DEFEATED")
	game_over = true
	_show_back_to_lobby_confirm("TXT_VICTORY")

func _on_opponent_left() -> void:
	_set_status_key("TXT_OPPONENT_LEFT")
	game_over = true
	_show_back_to_lobby_confirm("TXT_OPPONENT_LEFT_TITLE")


# ------------------------------------------------------------------------------
# 结果 UI
# ------------------------------------------------------------------------------
func _show_back_to_lobby_confirm(msg_key: String) -> void:
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
