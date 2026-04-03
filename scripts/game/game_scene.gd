class_name GameScene
extends TetrisCore

## 单人马拉松模式
## 继承 TetrisCore，并添加单人模式特有逻辑：压力行、HUD 更新与音效。

# ==============================================================================
# 单人模式特有变量
# ==============================================================================

@onready var label_score: Label = $HUD/ScoreLabel
@onready var label_level: Label = $HUD/LevelLabel
@onready var label_lines: Label = $HUD/LinesLabel
@onready var label_game_over: Label = $HUD/GameOverLabel

## 音效
@onready var bgm: AudioStreamPlayer = $BGM
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_success: AudioStreamPlayer = $SfxSuccess
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

## 垃圾槽
var garbage_bar: GarbageBar
var single_player_attack_timer: float = 0.0
var pending_attacks: Array = [] 
var ready_garbage: int = 0

var game_over_panel: PanelContainer
var btn_restart: Button
var btn_return: Button
const GARBAGE_BAR_GAP: float = 6.0

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	# 先调用基类的准备逻辑（初始化 Bag、DAS、Scoring）
	super._ready()
	
	# 设置输入动作注册（单机模式需要这些动作）
	_setup_input_actions()
	
	# 初始化 UI 配色与多语言文本
	_initialize_ui()
	_update_texts()
	
	# 关联信号
	score_changed.connect(_on_score_changed)
	lines_cleared.connect(_on_lines_cleared)
	game_over_triggered.connect(_on_game_over)
	
	# 启动第一个方块
	_spawn_next_piece()
	bgm.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()

func _process(delta: float) -> void:
	# 调用基类核心逻辑（输入、重力、锁定）
	process_logic(delta)
	
	# 处理单人模式特有的压力行
	if not game_over and not paused:
		_update_single_player_garbage(delta)

func _unhandled_input(event: InputEvent) -> void:
	# 仅在结算面板显示时额外拦截输入。
	if game_over_panel == null or not game_over_panel.visible:
		return

	# 设计要求：结算菜单中 B（ui_cancel）无效，只允许 A（ui_accept）确认按钮。
	# 因此这里仅吞掉 B，避免触发误退场或空引用报错。
	if event.is_action_pressed("ui_cancel"):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()

# ==============================================================================
# 单人模式特有：压力行逻辑
# ==============================================================================

func _update_single_player_garbage(delta: float) -> void:
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

# ==============================================================================
# 信号回调
# ==============================================================================

func _on_score_changed(s, l, ln) -> void:
	label_score.text = "%s\n%d" % [tr("TXT_SCORE"), s]
	label_level.text = "%s\n%d" % [tr("TXT_LEVEL"), l]
	label_lines.text = "%s\n%d" % [tr("TXT_LINES"), ln]

func _on_lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, dmg: int) -> void:
	# 播放音效
	if is_spin or is_t_spin or amount >= 4:
		sfx_success.play()
	else:
		sfx_line_clear.play()
		
	# 单机模式：输出伤害用于抵消自己的压力行
	var block_amount = dmg
	
	# 先抵消已就绪的红色垃圾
	var canceled_ready = mini(block_amount, ready_garbage)
	ready_garbage -= canceled_ready
	block_amount -= canceled_ready
	
	# 再抵消排队中的灰/黄垃圾
	while block_amount > 0 and pending_attacks.size() > 0:
		var target = pending_attacks[0]
		var cancel = mini(block_amount, target["amount"])
		target["amount"] -= cancel
		block_amount -= cancel
		if target["amount"] <= 0:
			pending_attacks.pop_front()

# 当方块锁定时，如果没消行且有红色压力，则被迫受击
func _lock_piece() -> void:
	# 记录锁定时是否会受击
	var will_receive_garbage = (ready_garbage > 0)
	
	# 调用基类锁定逻辑
	super._lock_piece()
	
	sfx_planting.play()
	
	# 受击逻辑：若本次未消行且有红色压力，则在此结算受击
	# 注意：基类内部已经处理了 scoring.reset_combo()
	# 通过扣减 ready_garbage 模拟受击结算
	if will_receive_garbage and scoring.combo == 0:
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

# ==============================================================================
# UI 初始化辅助

func _initialize_ui() -> void:
	# 寻找并挂载垃圾条
	# 关键修复：按“脚本类型”查找受攻击条，不再依赖固定路径或固定节点名。
	# 这样即使场景里改名成 GarbageBar2，也能正确绑定并显示。
	var bars: Array[Node] = find_children("*", "GarbageBar", true, false)
	if bars.size() > 0 and bars[0] is GarbageBar:
		garbage_bar = bars[0] as GarbageBar
		garbage_bar.max_lines = board.visible_rows
		garbage_bar.visible = true
		# 进入场景时先同步一次可视状态，避免条形控件初始不刷新。
		garbage_bar.update_bar(0, 0, 0)
		# 自动贴边布局：始终紧贴主战斗棋盘，且每格像素与棋盘格完全一致。
		_layout_garbage_bar()
	else:
		push_warning("未找到 GarbageBar 节点，单人受攻击条将不会显示。")
		
	# 初始化死亡面板
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
	btn_restart.focus_mode = Control.FOCUS_ALL
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	
	btn_return = Button.new()
	btn_return.custom_minimum_size = Vector2(240, 50)
	btn_return.focus_mode = Control.FOCUS_ALL
	btn_return.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main.tscn"))
	
	go_vbox.add_child(btn_restart)
	go_vbox.add_child(btn_return)
	
	var go_center = CenterContainer.new()
	go_center.add_child(go_vbox)
	game_over_panel.add_child(go_center)
	$HUD.add_child(game_over_panel)

func _update_texts() -> void:
	var hold_label = get_node_or_null("HUD/HoldLabel")
	if hold_label: hold_label.text = tr("TXT_HOLD")
	var next_label = get_node_or_null("HUD/NextLabel")
	if next_label: next_label.text = tr("TXT_NEXT")
	if btn_restart: btn_restart.text = tr("TXT_RESTART")
	if btn_return: btn_return.text = tr("TXT_RETURN_LOBBY")

## 将单人受攻击条贴到主棋盘左侧，并保证每个格子像素与棋盘格一致。
func _layout_garbage_bar() -> void:
	if garbage_bar == null or board == null:
		return

	# 条宽设置为 1 格，条高设置为可见 20 行，对应 10x20 主框的格子尺寸。
	var cell_px: float = board.cell_size
	var bar_w: float = cell_px
	var bar_h: float = board.visible_rows * cell_px

	# Board 与 GarbageBar 在同一层级，使用本地坐标直接计算即可。
	var board_left: float = board.position.x
	var board_top: float = board.position.y
	var bar_left: float = board_left - GARBAGE_BAR_GAP - bar_w

	garbage_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	garbage_bar.offset_left = bar_left
	garbage_bar.offset_top = board_top
	garbage_bar.offset_right = bar_left + bar_w
	garbage_bar.offset_bottom = board_top + bar_h

func _setup_input_actions() -> void:
	# 复用输入注册结构，保证单人模式动作完整
	pass # InputMap 是全局对象；若已注册可不重复注册，这里保留结构
