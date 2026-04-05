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
@onready var label_hold: Label = $HoldPanel/HoldLabel
@onready var label_next: Label = $NextPanel/NextLabel
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
var _fx_layer: CanvasLayer
var _label_action_text: Label
var _action_text_tween: Tween
var _label_combo_text: Label
var _combo_text_tween: Tween
var pending_attacks: Array = []
var ready_garbage: int = 0

# 受攻击条贴边间距，与单人保持一致。
const GARBAGE_BAR_GAP: float = 6.0
const ATTACK_DELAY_SECONDS: float = 12.0
const WARNING_STAGE_SECONDS: float = 6.0


# ------------------------------------------------------------------------------
# 生命周期
# ------------------------------------------------------------------------------
func _ready() -> void:
	super._ready()
	_apply_match_seed()
	_assign_audio_streams()
	_setup_bgm_loop()
	_initialize_garbage_bar_ui()
	_initialize_action_text_ui()
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

func _setup_bgm_loop() -> void:
	if bgm == null:
		return

	# 双保险：底层流启用 loop + finished 信号兜底重播。
	if bgm.stream is AudioStreamOggVorbis:
		var ogg := bgm.stream as AudioStreamOggVorbis
		ogg.loop = true
	elif bgm.stream is AudioStreamWAV:
		var wav := bgm.stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD

	if not bgm.finished.is_connected(_on_bgm_finished):
		bgm.finished.connect(_on_bgm_finished)

func _on_bgm_finished() -> void:
	if bgm and not game_over:
		bgm.play()

## 在开局时使用服务端分发的统一种子，确保双方方块序列一致。
func _apply_match_seed() -> void:
	if bag == null:
		return

	if NetworkManager.match_seed != 0:
		bag.reset_with_seed(NetworkManager.match_seed)
		_update_next_display()

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

## 初始化多人模式的大字特效层（用于 SPIN / TETRIS 提示）。
## 使用 CanvasLayer 保证在多人复杂 UI 结构上稳定可见。
func _initialize_action_text_ui() -> void:
	if _fx_layer == null:
		_fx_layer = CanvasLayer.new()
		_fx_layer.layer = 40
		add_child(_fx_layer)

	if _label_action_text == null:
		_label_action_text = Label.new()
		_label_action_text.visible = false
		_label_action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label_action_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label_action_text.z_index = 200
		_label_action_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label_action_text.add_theme_font_size_override("font_size", 76)
		_label_action_text.add_theme_color_override("font_color", Color(1.0, 0.96, 0.40, 1.0))
		_label_action_text.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10, 1.0))
		_label_action_text.add_theme_constant_override("outline_size", 8)
		_label_action_text.modulate = Color(1, 1, 1, 1)
		_fx_layer.add_child(_label_action_text)

	if _label_combo_text == null:
		_label_combo_text = Label.new()
		_label_combo_text.visible = false
		_label_combo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label_combo_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label_combo_text.z_index = 190
		_label_combo_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label_combo_text.add_theme_font_size_override("font_size", 52)
		_label_combo_text.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10, 1.0))
		_label_combo_text.add_theme_constant_override("outline_size", 6)
		_label_combo_text.modulate = Color(1, 1, 1, 1)
		_fx_layer.add_child(_label_combo_text)

	_layout_action_text_ui()

## 将多人特效文案定位到“本地棋盘上方居中”。
func _layout_action_text_ui() -> void:
	if _label_action_text == null or board == null:
		return

	# 在多人场景中 Board 嵌在 Control 容器内，使用带 Canvas 的全局坐标更稳定。
	var board_top_left_screen: Vector2 = board.get_global_transform_with_canvas().origin
	var board_w: float = board.columns * board.cell_size
	var board_center_x: float = board_top_left_screen.x + board_w * 0.5
	var top_y: float = maxf(18.0, board_top_left_screen.y + 8.0)
	_label_action_text.position = Vector2(board_center_x - 280.0, top_y)
	_label_action_text.size = Vector2(560, 88)
	if _label_combo_text:
		_label_combo_text.position = Vector2(board_center_x - 260.0, maxf(108.0, board_top_left_screen.y + 72.0))
		_label_combo_text.size = Vector2(520, 72)

## 在多人模式下显示大字特效（SPIN / TETRIS）。
func _show_action_text(content: String) -> void:
	if _label_action_text == null:
		return

	# 每次显示前重新布局，避免窗口缩放或布局变化后偏移。
	_layout_action_text_ui()

	if _action_text_tween and _action_text_tween.is_running():
		_action_text_tween.kill()

	_label_action_text.text = content
	_label_action_text.visible = true
	_label_action_text.modulate = Color(1, 1, 1, 1)
	_label_action_text.scale = Vector2(0.92, 0.92)

	_action_text_tween = create_tween()
	_action_text_tween.set_parallel(true)
	_action_text_tween.tween_property(_label_action_text, "scale", Vector2(1.08, 1.08), 0.10)
	_action_text_tween.chain()
	_action_text_tween.tween_interval(0.28)
	_action_text_tween.set_parallel(true)
	_action_text_tween.tween_property(_label_action_text, "modulate", Color(1, 1, 1, 0), 0.95)
	_action_text_tween.tween_property(_label_action_text, "scale", Vector2(1.14, 1.14), 0.95)
	_action_text_tween.finished.connect(func():
		if _label_action_text:
			_label_action_text.visible = false
			_label_action_text.modulate = Color(1, 1, 1, 1)
	)

func _combo_color(combo_count: int) -> Color:
	var hue: float = fmod(float(combo_count) * 0.12, 1.0)
	return Color.from_hsv(hue, 0.88, 1.0, 1.0)

func _show_combo_text(combo_count: int) -> void:
	if _label_combo_text == null:
		return

	_layout_action_text_ui()

	if _combo_text_tween and _combo_text_tween.is_running():
		_combo_text_tween.kill()

	_label_combo_text.text = "COMBO %d" % combo_count
	_label_combo_text.visible = true
	_label_combo_text.modulate = _combo_color(combo_count)
	_label_combo_text.modulate.a = 1.0

	var base_y: float = _label_combo_text.position.y
	_label_combo_text.position.y = base_y + 8.0

	_combo_text_tween = create_tween()
	_combo_text_tween.set_parallel(true)
	_combo_text_tween.tween_property(_label_combo_text, "position:y", base_y, 0.10)
	_combo_text_tween.chain()
	_combo_text_tween.tween_interval(0.20)
	_combo_text_tween.tween_property(_label_combo_text, "modulate:a", 0.0, 0.45)
	_combo_text_tween.finished.connect(func():
		if _label_combo_text:
			_label_combo_text.visible = false
	)

## 构造 Spin 文案。
func _build_spin_text(piece_type: int, is_t_spin: bool) -> String:
	if is_t_spin:
		return "T-SPIN!"
	var piece_name: String = _piece_type_to_letter(piece_type)
	if piece_name.is_empty():
		return "SPIN!"
	return "%s-SPIN!" % piece_name

## 将方块类型映射为单字母。
func _piece_type_to_letter(piece_type: int) -> String:
	match piece_type:
		PieceData.Type.I:
			return "I"
		PieceData.Type.O:
			return "O"
		PieceData.Type.T:
			return "T"
		PieceData.Type.S:
			return "S"
		PieceData.Type.Z:
			return "Z"
		PieceData.Type.J:
			return "J"
		PieceData.Type.L:
			return "L"
		_:
			return ""


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
	if label_hold:
		label_hold.text = tr("TXT_HOLD")
	if label_next:
		label_next.text = tr("TXT_NEXT")

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

func _physics_process(delta: float) -> void:
	process_logic(delta)
	if not game_over and not paused:
		_update_multiplayer_garbage(delta)

func _update_multiplayer_garbage(delta: float) -> void:
	var new_pending: Array = []
	for attack in pending_attacks:
		attack["delay"] -= delta
		if attack["delay"] <= 0.0:
			ready_garbage += int(attack["amount"])
		else:
			new_pending.append(attack)
	pending_attacks = new_pending
	_refresh_player_garbage_bar()

func _refresh_player_garbage_bar() -> void:
	if player_garbage_bar == null:
		return

	var grey_count: int = 0
	var yellow_count: int = 0
	for attack in pending_attacks:
		if float(attack["delay"]) > WARNING_STAGE_SECONDS:
			grey_count += int(attack["amount"])
		else:
			yellow_count += int(attack["amount"])

	player_garbage_bar.update_bar(grey_count, yellow_count, ready_garbage)

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
		_show_action_text(_build_spin_text(cur_type, is_t_spin))
	elif amount == 4:
		if sfx_tetris:
			sfx_tetris.play()
		_show_action_text("TETRIS!")
	else:
		if sfx_line_clear:
			sfx_line_clear.play()

	if scoring.combo > 0:
		_show_combo_text(scoring.combo)

	if damage <= 0:
		return

	var block_amount: int = damage

	var canceled_ready: int = mini(block_amount, ready_garbage)
	ready_garbage -= canceled_ready
	block_amount -= canceled_ready

	while block_amount > 0 and pending_attacks.size() > 0:
		var target = pending_attacks[0]
		var cancel: int = mini(block_amount, int(target["amount"]))
		target["amount"] = int(target["amount"]) - cancel
		block_amount -= cancel
		if int(target["amount"]) <= 0:
			pending_attacks.pop_front()

	if block_amount > 0:
		NetworkManager.send_attack(block_amount)

	_refresh_player_garbage_bar()

func _lock_piece() -> void:
	var will_receive_garbage: bool = (ready_garbage > 0)
	var lines_before_lock: int = scoring.lines

	super._lock_piece()

	var did_clear_lines: bool = scoring.lines > lines_before_lock
	if will_receive_garbage and not did_clear_lines and board:
		board.add_garbage_lines(ready_garbage)
		ready_garbage = 0
		_refresh_player_garbage_bar()
		NetworkManager.sync_board(board.get_grid_state())

func _on_local_game_over() -> void:
	NetworkManager.send_game_over()
	_set_status_key("TXT_YOU_LOST")
	if bgm:
		bgm.stop()
	sfx_death.play()
	_show_back_to_lobby_confirm("TXT_GAME_OVER")


# ------------------------------------------------------------------------------
# 网络 -> 本地
# ------------------------------------------------------------------------------
func _on_opponent_board_updated(grid_data: Array) -> void:
	if opponent_board:
		opponent_board.set_grid_state(grid_data)

func _on_attack_received(amount: int) -> void:
	if amount <= 0:
		return

	for _i in range(amount):
		pending_attacks.append({"delay": ATTACK_DELAY_SECONDS, "amount": 1})

	_refresh_player_garbage_bar()

func _on_opponent_game_over() -> void:
	_set_status_key("TXT_OPPONENT_DEFEATED")
	game_over = true
	if bgm:
		bgm.stop()
	_show_back_to_lobby_confirm("TXT_VICTORY")

func _on_opponent_left() -> void:
	_set_status_key("TXT_OPPONENT_LEFT")
	game_over = true
	if bgm:
		bgm.stop()
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
