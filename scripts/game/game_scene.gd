class_name GameScene
extends TetrisCore

## 单人马拉松模式
## 继承自 TetrisCore，并添加了单人模式特有逻辑：
## 1. 随分数增长的自动压力行 (Garbage Queue)
## 2. HUD 标签的实时更新
## 3. 音效播放

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

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	# 先调用基类的准备逻辑 (初始化 Bag, DAS, Scoring)
	super._ready()
	
	# 设置输入动作注册 (单机模式需要这些)
	_setup_input_actions()
	
	# 初始化 UI 配色与多语言
	_initialize_ui()
	_update_texts()
	
	# 关联信号
	score_changed.connect(_on_score_changed)
	lines_cleared.connect(_on_lines_cleared)
	game_over_triggered.connect(_on_game_over)
	
	# 启动第一个方块
	_spawn_next_piece()
	bgm.play()

func _process(delta: float) -> void:
	# 调用基类的核心逻辑 (输入、重力、锁定)
	process_logic(delta)
	
	# 处理单人模式特有的压力行
	if not game_over and not paused:
		_update_single_player_garbage(delta)

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
		
	# 单机模式：输出的伤害转化为抵消自己的压力行
	var block_amount = dmg
	
	# 先消红
	var canceled_ready = mini(block_amount, ready_garbage)
	ready_garbage -= canceled_ready
	block_amount -= canceled_ready
	
	# 后消黄/灰
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
	
	# 受击逻辑处理 (如果基类执行后没消行，则在这里产生受击)
	# 注意：基类内部已经处理了 scoring.reset_combo()
	# 这里通过判断 ready_garbage 并在最后消减它来模拟
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
# UI 与 初始化辅助
# ==============================================================================

func _initialize_ui() -> void:
	# 寻找并挂载垃圾条
	var gb_node = get_node_or_null("HUD/GarbageBar")
	if not gb_node: gb_node = get_node_or_null("GarbageBar")
	if gb_node and gb_node is GarbageBar:
		garbage_bar = gb_node
		garbage_bar.max_lines = board.visible_rows
		
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
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	
	btn_return = Button.new()
	btn_return.custom_minimum_size = Vector2(240, 50)
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

func _setup_input_actions() -> void:
	# 复用老的输入注册逻辑，确保单人模式动作正常
	# (此处省略具体实现，实际代码中应从原 game_scene.gd 迁移)
	pass # 实际上 InputMap 是全局的，如果之前注册过就不必再跑，但这里保留结构
