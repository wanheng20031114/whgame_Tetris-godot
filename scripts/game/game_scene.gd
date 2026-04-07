class_name GameScene
extends TetrisCore

# 单人对局场景：
# - 继承 TetrisCore 承担基础俄罗斯方块逻辑
# - 补充单人受攻击条、UI 动效、数据采集与拓扑评分接入

@onready var label_score: Label = $HUD/ScoreLabel
@onready var label_level: Label = $HUD/LevelLabel
@onready var label_lines: Label = $HUD/LinesLabel
@onready var label_game_over: Label = $HUD/GameOverLabel
@onready var label_spin_text: Label = $HUD/SpinTextLabel
@onready var label_combo_text: Label = $HUD/ComboTextLabel

@onready var bgm: AudioStreamPlayer = $BGM
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_tetris: AudioStreamPlayer = $SfxSuccess
@onready var sfx_spin: AudioStreamPlayer = $SfxSpin
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

var garbage_bar: GarbageBar
var single_player_attack_timer: float = 0.0
var pending_attacks: Array = []
var ready_garbage: int = 0

var game_over_panel: PanelContainer
var btn_restart: Button
var btn_return: Button

var spin_text_tween: Tween
var combo_text_tween: Tween

const GARBAGE_BAR_GAP: float = 6.0

# 单局数据采集与拓扑评分缓存。
var _data_collector: PlayerDataCollector
var _topology_evaluator: Node
var _last_lines_cleared_this_lock: int = 0
var _last_damage_this_lock: int = 0
var _last_is_spin: bool = false
var _last_is_t_spin: bool = false
var _last_topology_score: float = 0.0
var _last_stability_score: float = 0.0
var _hold_used_this_piece: bool = false


func _ready() -> void:
	super._ready()

	_setup_input_actions()

	_initialize_ui()
	_update_texts()

	score_changed.connect(_on_score_changed)
	lines_cleared.connect(_on_lines_cleared)
	rows_cleared.connect(_on_rows_cleared)
	game_over_triggered.connect(_on_game_over)

	_spawn_next_piece()
	bgm.play()

	_data_collector = PlayerDataCollector.new()
	_topology_evaluator = get_node_or_null("TopologyEvaluator")
	var state := get_node_or_null("/root/GameState")
	var pname: String = ""
	if state:
		pname = str(state.player_name).strip_edges()
	_data_collector.start_session(pname if not pname.is_empty() else "Player")

func _notification(what: int) -> void:
	# 多语言切换时刷新 UI 文案。
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()

func _process(delta: float) -> void:
	# 先跑核心逻辑（移动/重力/锁定等）。
	process_logic(delta)

	# 统计本块按键次数（用于 KPP）。
	if _data_collector and _data_collector.is_active() and not game_over and not paused:
		_count_key_presses()

	# 更新单人受攻击条与入场计时。
	if not game_over and not paused:
		_update_single_player_garbage(delta)

func _unhandled_input(event: InputEvent) -> void:
	# 仅在结算面板显示时拦截取消键，避免误退出。
	if game_over_panel == null or not game_over_panel.visible:
		return

	if event.is_action_pressed("ui_cancel"):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


func _update_single_player_garbage(delta: float) -> void:
	# 分数达到阈值后，按间隔生成待入场垃圾。
	if scoring.score >= 10000:
		single_player_attack_timer += delta
		var progress: float = clampf((scoring.score - 10000) / 90000.0, 0.0, 1.0)
		var current_interval: float = lerpf(10.0, 2.0, progress)

		if single_player_attack_timer >= current_interval:
			single_player_attack_timer = 0.0
			pending_attacks.append({"delay": 12.0, "amount": 1})

	var new_pending: Array = []
	var grey_count: int = 0
	var yellow_count: int = 0

	# 更新攻击包倒计时：到时进入 ready_garbage，否则保留在队列。
	for attack in pending_attacks:
		attack["delay"] -= delta
		if attack["delay"] <= 0:
			ready_garbage += attack["amount"]
		else:
			new_pending.append(attack)
			if attack["delay"] > 6.0:
				grey_count += attack["amount"]
			else:
				yellow_count += attack["amount"]
	pending_attacks = new_pending

	if garbage_bar:
		garbage_bar.update_bar(grey_count, yellow_count, ready_garbage)


func _on_score_changed(s: int, l: int, ln: int) -> void:
	# HUD 分数区刷新。
	label_score.text = "%s\n%d" % [tr("TXT_SCORE"), s]
	label_level.text = "%s\n%d" % [tr("TXT_LEVEL"), l]
	label_lines.text = "%s\n%d" % [tr("TXT_LINES"), ln]

func _on_lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, dmg: int) -> void:
	# 缓存本次锁定结果，供快照采集使用。
	_last_lines_cleared_this_lock = amount
	_last_damage_this_lock = dmg
	_last_is_spin = is_spin
	_last_is_t_spin = is_t_spin

	# 音效分流：Spin > Tetris > 普通消行。
	var did_spin_clear: bool = (is_spin or is_t_spin)
	if did_spin_clear:
		if sfx_spin:
			sfx_spin.play()
		_show_spin_text(_build_spin_text(cur_type, is_t_spin))
	elif amount == 4:
		if sfx_tetris:
			sfx_tetris.play()
		_show_spin_text("TETRIS!")
	else:
		if sfx_line_clear:
			sfx_line_clear.play()

	# 连击提示。
	if scoring.combo > 0:
		_show_combo_text(scoring.combo)

	# 本次输出用于抵消已排队垃圾。
	var block_amount: int = dmg

	var canceled_ready: int = mini(block_amount, ready_garbage)
	ready_garbage -= canceled_ready
	block_amount -= canceled_ready

	while block_amount > 0 and pending_attacks.size() > 0:
		var target = pending_attacks[0]
		var cancel: int = mini(block_amount, target["amount"])
		target["amount"] -= cancel
		block_amount -= cancel
		if target["amount"] <= 0:
			pending_attacks.pop_front()

func _lock_piece() -> void:
	# 锁定前记录状态，用于判断是否“无消行吃垃圾”。
	var will_receive_garbage: bool = (ready_garbage > 0)
	var lines_before_lock: int = scoring.lines

	_last_lines_cleared_this_lock = 0
	_last_damage_this_lock = 0
	_last_is_spin = false
	_last_is_t_spin = false

	super._lock_piece()

	sfx_planting.play()

	var did_clear_lines: bool = scoring.lines > lines_before_lock
	if will_receive_garbage and not did_clear_lines:
		board.add_garbage_lines(ready_garbage)
		ready_garbage = 0

	# 每次锁定后记录一次快照。
	_record_piece_snapshot()

func _on_game_over() -> void:
	if label_game_over:
		label_game_over.text = tr("TXT_GAME_OVER")
		label_game_over.visible = true
	if game_over_panel:
		game_over_panel.show()
		btn_restart.grab_focus()
	bgm.stop()
	sfx_death.play()

	_save_and_cleanup_data()


func _initialize_ui() -> void:
	# 动态查找 GarbageBar，避免节点层级变动导致硬引用失效。
	var bars: Array[Node] = find_children("*", "GarbageBar", true, false)
	if bars.size() > 0 and bars[0] is GarbageBar:
		garbage_bar = bars[0] as GarbageBar
		garbage_bar.max_lines = board.visible_rows
		garbage_bar.visible = true
		garbage_bar.update_bar(0, 0, 0)
		_layout_garbage_bar()
	else:
		push_warning("GarbageBar node not found; single-player garbage bar will not be shown.")

	# 初始化提示文本样式与位置。
	_layout_effect_labels()
	if label_spin_text:
		label_spin_text.visible = false
		label_spin_text.z_index = 60
		label_spin_text.add_theme_font_size_override("font_size", 76)
		label_spin_text.add_theme_color_override("font_color", Color(1.0, 0.96, 0.40, 1.0))
		label_spin_text.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10, 1.0))
		label_spin_text.add_theme_constant_override("outline_size", 8)
		label_spin_text.modulate = Color(1, 1, 1, 1)
	if label_combo_text:
		label_combo_text.visible = false
		label_combo_text.z_index = 50
		label_combo_text.add_theme_font_size_override("font_size", 52)
		label_combo_text.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10, 1.0))
		label_combo_text.add_theme_constant_override("outline_size", 6)

	game_over_panel = PanelContainer.new()
	var sb_go := StyleBoxFlat.new()
	sb_go.bg_color = Color(0, 0, 0, 0.85)
	game_over_panel.add_theme_stylebox_override("panel", sb_go)
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.hide()

	var go_vbox := VBoxContainer.new()
	go_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	go_vbox.add_theme_constant_override("separation", 20)

	btn_restart = Button.new()
	btn_restart.custom_minimum_size = Vector2(240, 50)
	btn_restart.focus_mode = Control.FOCUS_ALL
	btn_restart.pressed.connect(func():
		_save_and_cleanup_data()
		get_tree().reload_current_scene()
	)

	btn_return = Button.new()
	btn_return.custom_minimum_size = Vector2(240, 50)
	btn_return.focus_mode = Control.FOCUS_ALL
	btn_return.pressed.connect(func():
		_save_and_cleanup_data()
		get_tree().change_scene_to_file("res://scenes/ui/main.tscn")
	)

	go_vbox.add_child(btn_restart)
	go_vbox.add_child(btn_return)

	var go_center := CenterContainer.new()
	go_center.add_child(go_vbox)
	game_over_panel.add_child(go_center)
	$HUD.add_child(game_over_panel)

func _update_texts() -> void:
	# 兼容两种可能路径（HUD 与独立面板层级）。
	var hold_label: Label = get_node_or_null("HoldPanel/HoldLabel")
	if hold_label == null:
		hold_label = get_node_or_null("HUD/HoldLabel")
	if hold_label:
		hold_label.text = tr("TXT_HOLD")

	var next_label: Label = get_node_or_null("NextPanel/NextLabel")
	if next_label == null:
		next_label = get_node_or_null("HUD/NextLabel")
	if next_label:
		next_label.text = tr("TXT_NEXT")

	if btn_restart:
		btn_restart.text = tr("TXT_RESTART")
	if btn_return:
		btn_return.text = tr("TXT_RETURN_LOBBY")


func _layout_garbage_bar() -> void:
	# 让受攻击条贴在主棋盘左侧，并与棋盘同高度。
	if garbage_bar == null or board == null:
		return

	var cell_px: float = board.cell_size
	var bar_w: float = cell_px
	var bar_h: float = board.visible_rows * cell_px

	var board_left: float = board.position.x
	var board_top: float = board.position.y
	var bar_left: float = board_left - GARBAGE_BAR_GAP - bar_w

	garbage_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	garbage_bar.offset_left = bar_left
	garbage_bar.offset_top = board_top
	garbage_bar.offset_right = bar_left + bar_w
	garbage_bar.offset_bottom = board_top + bar_h

func _layout_effect_labels() -> void:
	# 让 SPIN/COMBO 文案围绕棋盘中心布局。
	if board == null:
		return

	var board_w: float = board.columns * board.cell_size
	var board_center_x: float = board.position.x + board_w * 0.5

	if label_spin_text:
		label_spin_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		label_spin_text.offset_left = board_center_x - 280.0
		label_spin_text.offset_top = maxf(18.0, board.position.y + 8.0)
		label_spin_text.offset_right = board_center_x + 280.0
		label_spin_text.offset_bottom = label_spin_text.offset_top + 88.0

	if label_combo_text:
		label_combo_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		label_combo_text.offset_left = board_center_x - 260.0
		label_combo_text.offset_top = maxf(108.0, board.position.y + 72.0)
		label_combo_text.offset_right = board_center_x + 260.0
		label_combo_text.offset_bottom = label_combo_text.offset_top + 72.0

func _build_spin_text(piece_type: int, is_t_spin: bool) -> String:
	if is_t_spin:
		return "T-SPIN!"
	var piece_name: String = _piece_type_to_letter(piece_type)
	if piece_name.is_empty():
		return "SPIN!"
	return "%s-SPIN!" % piece_name

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

func _show_spin_text(content: String) -> void:
	# 中央 SPIN 动画：短暂放大后淡出。
	if label_spin_text == null:
		return

	if spin_text_tween and spin_text_tween.is_running():
		spin_text_tween.kill()

	label_spin_text.text = content
	label_spin_text.visible = true
	label_spin_text.modulate = Color(1, 1, 1, 1)
	label_spin_text.scale = Vector2(0.92, 0.92)

	spin_text_tween = create_tween()
	spin_text_tween.set_parallel(true)
	spin_text_tween.tween_property(label_spin_text, "scale", Vector2(1.08, 1.08), 0.10)
	spin_text_tween.chain()
	spin_text_tween.tween_interval(0.25)
	spin_text_tween.set_parallel(true)
	spin_text_tween.tween_property(label_spin_text, "modulate", Color(1, 1, 1, 0), 0.90)
	spin_text_tween.tween_property(label_spin_text, "scale", Vector2(1.14, 1.14), 0.90)
	spin_text_tween.finished.connect(func():
		if label_spin_text:
			label_spin_text.visible = false
			label_spin_text.modulate = Color(1, 1, 1, 1)
	)

func _combo_color(combo_count: int) -> Color:
	var hue: float = fmod(float(combo_count) * 0.12, 1.0)
	return Color.from_hsv(hue, 0.88, 1.0, 1.0)

func _show_combo_text(combo_count: int) -> void:
	# 顶部 COMBO 动画：上浮并淡出。
	if label_combo_text == null:
		return

	if combo_text_tween and combo_text_tween.is_running():
		combo_text_tween.kill()

	label_combo_text.text = "COMBO %d" % combo_count
	label_combo_text.visible = true
	label_combo_text.modulate = _combo_color(combo_count)
	label_combo_text.modulate.a = 1.0
	label_combo_text.position.y = label_combo_text.offset_top + 8.0

	combo_text_tween = create_tween()
	combo_text_tween.set_parallel(true)
	combo_text_tween.tween_property(label_combo_text, "position:y", label_combo_text.offset_top, 0.10)
	combo_text_tween.chain()
	combo_text_tween.tween_interval(0.20)
	combo_text_tween.tween_property(label_combo_text, "modulate:a", 0.0, 0.45)
	combo_text_tween.finished.connect(func():
		if label_combo_text:
			label_combo_text.visible = false
	)


func _setup_input_actions() -> void:
	# 预留：需要时可在此注册单人特有按键。
	pass


func _on_rows_cleared(rows_data: Array) -> void:
	# 行清除粒子效果。
	if board == null or rows_data.is_empty():
		return

	var effect := LineClearEffect.new()
	board.add_child(effect)
	effect.setup(rows_data, board.cell_size, board.buffer_rows)


func _count_key_presses() -> void:
	# 每帧累计本块操作键次数。
	if _data_collector == null:
		return

	var actions: Array = [
		"move_left", "move_right", "soft_drop", "hard_drop",
		"rotate_cw", "rotate_ccw", "rotate_180", "hold"
	]
	for action in actions:
		if Input.is_action_just_pressed(action):
			_data_collector.key_presses_this_piece += 1


func _record_piece_snapshot() -> void:
	# 采集一次“方块锁定快照”：棋盘/next/战斗结果/拓扑评分。
	if _data_collector == null or not _data_collector.is_active():
		return
	if board == null or bag == null:
		return

	var full_grid: Array = board.get_grid_state()
	var visible_grid: Array = []
	for r in range(board.buffer_rows, board.total_rows):
		if r < full_grid.size():
			visible_grid.append(full_grid[r])

	var next_pieces: Array = bag.peek(5)

	# 由 TopologyEvaluator 计算拓扑分与空洞分。
	var topology_eval: Dictionary = _evaluate_topology_scores(visible_grid)
	_last_topology_score = float(topology_eval.get("topology_score", 0.0))
	_last_stability_score = float(topology_eval.get("stability_score", 0.0))

	_data_collector.record_piece_drop(
		cur_type,
		cur_rot,
		cur_col,
		cur_row,
		visible_grid,
		next_pieces,
		scoring.score,
		scoring.level,
		scoring.lines,
		scoring.combo,
		scoring.b2b,
		_last_is_spin,
		_last_is_t_spin,
		_last_lines_cleared_this_lock,
		_last_damage_this_lock,
		_hold_used_this_piece,
		_last_topology_score,
		_last_stability_score
	)

	_hold_used_this_piece = false


func _save_and_cleanup_data() -> void:
	# 对局结束时落盘并关闭本局采集。
	if _data_collector == null or not _data_collector.is_active():
		return
	_data_collector.end_session(scoring.score, scoring.level, scoring.lines)


func _evaluate_topology_scores(board_state_visible: Array) -> Dictionary:
	# 同时兼容 PascalCase 与 snake_case 方法名。
	if _topology_evaluator == null:
		return {"topology_score": 0.0, "stability_score": 0.0}

	if _topology_evaluator.has_method("EvaluateBoardScores"):
		var result = _topology_evaluator.call("EvaluateBoardScores", board_state_visible)
		if result is Dictionary:
			return result
	elif _topology_evaluator.has_method("evaluate_board_scores"):
		var result2 = _topology_evaluator.call("evaluate_board_scores", board_state_visible)
		if result2 is Dictionary:
			return result2

	return {"topology_score": 0.0, "stability_score": 0.0}
