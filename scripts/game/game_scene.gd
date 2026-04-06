class_name GameScene
extends TetrisCore

## 单人游戏场景控制脚本。
## 这里在通用 TetrisCore 之上补充了：
## 1) 单人受攻击条逻辑；
## 2) 单人 HUD 文本更新；
## 3) 音效分流（普通消行 / 四消 / Spin 消行）；
## 4) 中央 SPIN 提示与顶部 COMBO 提示。

# ------------------------------------------------------------------------------
# HUD 节点引用
# ------------------------------------------------------------------------------
@onready var label_score: Label = $HUD/ScoreLabel
@onready var label_level: Label = $HUD/LevelLabel
@onready var label_lines: Label = $HUD/LinesLabel
@onready var label_game_over: Label = $HUD/GameOverLabel
@onready var label_spin_text: Label = $HUD/SpinTextLabel
@onready var label_combo_text: Label = $HUD/ComboTextLabel

# ------------------------------------------------------------------------------
# 音效节点引用
# ------------------------------------------------------------------------------
@onready var bgm: AudioStreamPlayer = $BGM
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_tetris: AudioStreamPlayer = $SfxSuccess
@onready var sfx_spin: AudioStreamPlayer = $SfxSpin
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

# ------------------------------------------------------------------------------
# 单人模式状态
# ------------------------------------------------------------------------------
var garbage_bar: GarbageBar
var single_player_attack_timer: float = 0.0
var pending_attacks: Array = []
var ready_garbage: int = 0

# 结算面板节点
var game_over_panel: PanelContainer
var btn_restart: Button
var btn_return: Button

# HUD 动效用 Tween，切换提示时会主动 kill，避免叠动画。
var spin_text_tween: Tween
var combo_text_tween: Tween

# 受攻击条固定贴边间距：保证和主战斗棋盘视觉上紧贴但不重叠。
const GARBAGE_BAR_GAP: float = 6.0


# ------------------------------------------------------------------------------
# 生命周期
# ------------------------------------------------------------------------------
func _ready() -> void:
	# 先初始化通用俄罗斯方块逻辑。
	super._ready()

	# 注册输入动作（保留占位结构，便于后续继续扩展）。
	_setup_input_actions()

	# 初始化 UI（受攻击条、结算面板、提示文本位置）。
	_initialize_ui()
	_update_texts()

	# 连接单人场景关心的通用信号。
	score_changed.connect(_on_score_changed)
	lines_cleared.connect(_on_lines_cleared)
	rows_cleared.connect(_on_rows_cleared)
	game_over_triggered.connect(_on_game_over)

	# 开局生成第一块并播放 BGM。
	_spawn_next_piece()
	bgm.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()

func _process(delta: float) -> void:
	# 每帧执行核心逻辑（移动、旋转、重力、锁定等）。
	process_logic(delta)

	# 单人受攻击条计时和入场逻辑。
	if not game_over and not paused:
		_update_single_player_garbage(delta)

func _unhandled_input(event: InputEvent) -> void:
	# 仅在结算面板可见时拦截额外输入。
	if game_over_panel == null or not game_over_panel.visible:
		return

	# 设计要求：结算界面里 B（ui_cancel）无效，只允许 A（ui_accept）确认当前按钮。
	if event.is_action_pressed("ui_cancel"):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


# ------------------------------------------------------------------------------
# 单人模式受攻击条逻辑
# ------------------------------------------------------------------------------
func _update_single_player_garbage(delta: float) -> void:
	# 分数达到阈值后开始周期性生成压力包。
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

	# 更新每个攻击包倒计时，并拆分成灰/黄/红三个阶段用于受攻击条展示。
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


# ------------------------------------------------------------------------------
# 信号回调
# ------------------------------------------------------------------------------
func _on_score_changed(s: int, l: int, ln: int) -> void:
	label_score.text = "%s\n%d" % [tr("TXT_SCORE"), s]
	label_level.text = "%s\n%d" % [tr("TXT_LEVEL"), l]
	label_lines.text = "%s\n%d" % [tr("TXT_LINES"), ln]

func _on_lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, dmg: int) -> void:
	# 音效规则：
	# 1) Spin 消除 -> spin.ogg
	# 2) 非 Spin 且四消 -> tetris.ogg
	# 3) 其余消行 -> line_clear.ogg
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

	# 连续消行时显示彩色 COMBO n（n 为当前连击值）。
	# scoring.combo 在第一次有效消行后为 0，从第二次连续消行开始为 1、2、3...
	if scoring.combo > 0:
		_show_combo_text(scoring.combo)

	# 单人模式：将本次输出伤害用于抵消即将到来的垃圾。
	var block_amount: int = dmg

	# 先抵消已经就绪（红色）的垃圾。
	var canceled_ready: int = mini(block_amount, ready_garbage)
	ready_garbage -= canceled_ready
	block_amount -= canceled_ready

	# 再抵消排队中的灰/黄垃圾。
	while block_amount > 0 and pending_attacks.size() > 0:
		var target = pending_attacks[0]
		var cancel: int = mini(block_amount, target["amount"])
		target["amount"] -= cancel
		block_amount -= cancel
		if target["amount"] <= 0:
			pending_attacks.pop_front()

# 当方块锁定时，如果本次没消行且有红色压力，就在此刻结算受击。
func _lock_piece() -> void:
	var will_receive_garbage: bool = (ready_garbage > 0)
	var lines_before_lock: int = scoring.lines

	# 先走基类锁定逻辑（包括清行、计分、出块）。
	super._lock_piece()

	# 每次锁定都播放落地音效。
	sfx_planting.play()

	# 若本次没有消行，则吃掉已就绪垃圾。
	var did_clear_lines: bool = scoring.lines > lines_before_lock
	if will_receive_garbage and not did_clear_lines:
		board.add_garbage_lines(ready_garbage)
		ready_garbage = 0

func _on_game_over() -> void:
	if label_game_over:
		label_game_over.text = tr("TXT_GAME_OVER")
		label_game_over.visible = true
	if game_over_panel:
		game_over_panel.show()
		btn_restart.grab_focus()
	bgm.stop()
	sfx_death.play()


# ------------------------------------------------------------------------------
# UI 初始化与文本刷新
# ------------------------------------------------------------------------------
func _initialize_ui() -> void:
	# 动态查找受攻击条，避免节点名变更导致绑定失效。
	var bars: Array[Node] = find_children("*", "GarbageBar", true, false)
	if bars.size() > 0 and bars[0] is GarbageBar:
		garbage_bar = bars[0] as GarbageBar
		garbage_bar.max_lines = board.visible_rows
		garbage_bar.visible = true
		garbage_bar.update_bar(0, 0, 0)
		_layout_garbage_bar()
	else:
		push_warning("未找到 GarbageBar 节点，单人受攻击条将不会显示。")

	# 初始化提示文字布局（SPIN 在中间，COMBO 在棋盘上方中间）。
	_layout_effect_labels()
	if label_spin_text:
		label_spin_text.visible = false
		label_spin_text.z_index = 60
		# 强可见样式，避免在复杂背景上“看不见”。
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

	# 结算面板（黑色遮罩 + 两个按钮）。
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
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())

	btn_return = Button.new()
	btn_return.custom_minimum_size = Vector2(240, 50)
	btn_return.focus_mode = Control.FOCUS_ALL
	btn_return.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main.tscn"))

	go_vbox.add_child(btn_restart)
	go_vbox.add_child(btn_return)

	var go_center := CenterContainer.new()
	go_center.add_child(go_vbox)
	game_over_panel.add_child(go_center)
	$HUD.add_child(game_over_panel)

func _update_texts() -> void:
	# 兼容两种可能路径，防止后续 UI 层级调整导致多语言文本失效。
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


# ------------------------------------------------------------------------------
# 视觉辅助：受攻击条 / SPIN 提示 / COMBO 提示
# ------------------------------------------------------------------------------
## 将单人受攻击条贴到主棋盘左侧，并保证每格像素与主棋盘一致。
func _layout_garbage_bar() -> void:
	if garbage_bar == null or board == null:
		return

	var cell_px: float = board.cell_size
	var bar_w: float = cell_px
	var bar_h: float = board.visible_rows * cell_px

	# Board 与 GarbageBar 在同层级，直接使用本地坐标计算。
	var board_left: float = board.position.x
	var board_top: float = board.position.y
	var bar_left: float = board_left - GARBAGE_BAR_GAP - bar_w

	garbage_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	garbage_bar.offset_left = bar_left
	garbage_bar.offset_top = board_top
	garbage_bar.offset_right = bar_left + bar_w
	garbage_bar.offset_bottom = board_top + bar_h

## 统一布局 SPIN / COMBO 文案位置，保证始终围绕主战斗棋盘中心。
func _layout_effect_labels() -> void:
	if board == null:
		return

	var board_w: float = board.columns * board.cell_size
	var board_center_x: float = board.position.x + board_w * 0.5

	if label_spin_text:
		label_spin_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		# 放到上方可视安全区（不再使用负 y）。
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

## 构造屏幕中央的 SPIN 文案。
func _build_spin_text(piece_type: int, is_t_spin: bool) -> String:
	if is_t_spin:
		return "T-SPIN!"
	var piece_name: String = _piece_type_to_letter(piece_type)
	if piece_name.is_empty():
		return "SPIN!"
	return "%s-SPIN!" % piece_name

## 将方块类型映射为单字母文案。
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

## 播放中央 SPIN 文案动画（淡入 + 缩放 + 淡出）。
func _show_spin_text(content: String) -> void:
	if label_spin_text == null:
		return

	if spin_text_tween and spin_text_tween.is_running():
		spin_text_tween.kill()

	label_spin_text.text = content
	label_spin_text.visible = true
	# 先直接全亮显示，保证至少“先看到”，再做淡出。
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

## 根据连击数生成高饱和色，做成动态彩色 COMBO 文案。
func _combo_color(combo_count: int) -> Color:
	var hue: float = fmod(float(combo_count) * 0.12, 1.0)
	return Color.from_hsv(hue, 0.88, 1.0, 1.0)

## 播放顶部 COMBO 文案动画（上弹 + 淡出）。
func _show_combo_text(combo_count: int) -> void:
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
	# InputMap 是全局对象；当前项目里动作已在其他入口配置。
	# 这里保留接口，后续如果要做单人专属按键可直接补在此处。
	pass


# ------------------------------------------------------------------------------
# 消行粒子效果
# ------------------------------------------------------------------------------
func _on_rows_cleared(rows_data: Array) -> void:
	if board == null or rows_data.is_empty():
		return

	var effect := LineClearEffect.new()
	board.add_child(effect)
	effect.setup(rows_data, board.cell_size, board.buffer_rows)
