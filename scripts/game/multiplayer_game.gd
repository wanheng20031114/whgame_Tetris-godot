extends TetrisCore

## 双人对战模式脚本
## 继承自 TetrisCore，处理网络同步与平衡性逻辑。

# ==============================================================================
# 多人特有变量
# ==============================================================================

@onready var opponent_board: Board = %OpponentBoard
@onready var label_status: Label = %StatusLabel
@onready var label_opponent_name: Label = %OpponentNameLabel
@onready var bgm: AudioStreamPlayer = $BGM

# 音效
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_success: AudioStreamPlayer = $SfxSuccess
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	super._ready()
	
	# 设置 UI
	label_opponent_name.text = NetworkManager.opponent_name
	label_status.text = "对战中..."
	
	# 连接网络信号
	NetworkManager.board_update_received.connect(_on_opponent_board_updated)
	NetworkManager.attack_received.connect(_on_attack_received)
	NetworkManager.game_over_received.connect(_on_opponent_game_over)
	NetworkManager.opponent_left.connect(_on_opponent_left)
	
	# 本地信号监听 -> 发送给网络
	piece_locked.connect(_on_local_piece_locked)
	lines_cleared.connect(_on_local_lines_cleared)
	game_over_triggered.connect(_on_local_game_over)
	
	# 启动
	_spawn_next_piece()
	bgm.play()

func _process(delta: float) -> void:
	# 执行核心俄罗斯方块逻辑
	process_logic(delta)

# ==============================================================================
# 网络发送逻辑 (本地行为 -> 服务器)
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
	label_status.text = "你输了！"
	sfx_death.play()
	# 弹出返回按钮等 (简单处理：直接回大厅)
	_show_back_to_lobby_confirm("游戏结束")

# ==============================================================================
# 网络接收逻辑 (服务器 -> 本地反馈)
# ==============================================================================

func _on_opponent_board_updated(grid_data: Array) -> void:
	# 更新右侧对手的棋盘显示
	if opponent_board:
		opponent_board.set_grid_state(grid_data)

func _on_attack_received(amount: int) -> void:
	# 收到对手的攻击，直接在本地棋盘增加垃圾行
	# (注意：进阶玩法可以先放进等待队列，这里采用直接生效以降低开发复杂度)
	if board:
		board.add_garbage_lines(amount)
		# 可以在此处增加受击震动或音效

func _on_opponent_game_over() -> void:
	label_status.text = "对手阵亡！你赢了！"
	# 停止逻辑但保持显示
	game_over = true
	_show_back_to_lobby_confirm("胜利！")

func _on_opponent_left() -> void:
	label_status.text = "对手已断开连接"
	game_over = true
	_show_back_to_lobby_confirm("对手离开了")

# ==============================================================================
# UI 辅助
# ==============================================================================

func _show_back_to_lobby_confirm(msg: String) -> void:
	# 实际应该做一个弹窗，这里暂时用简单的 Button 覆盖
	var btn = Button.new()
	btn.text = msg + " - 点击返回大厅"
	btn.custom_minimum_size = Vector2(300, 60)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn"))
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(btn)
	add_child(center)
