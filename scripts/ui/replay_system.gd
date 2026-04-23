class_name ReplaySystem
extends Control

## 对局复盘系统
## 加载历史 session JSON，逐步回放棋盘状态，展示 AI 评分。

const BOARD_ROWS: int = 20
const BOARD_COLS: int = 10
const CELL_SIZE: int = 30

# 方块颜色（与 PieceData.COLORS 一致，0=空）
const CELL_COLORS: Array[Color] = [
	Color(0.08, 0.08, 0.12, 1),    # 0: 空 - 深色背景
	Color(0.0, 0.85, 0.85, 1),     # 1: I - 青
	Color(1.0, 0.85, 0.0, 1),      # 2: O - 黄
	Color(0.6, 0.0, 0.8, 1),       # 3: T - 紫
	Color(0.0, 0.8, 0.0, 1),       # 4: S - 绿
	Color(0.9, 0.1, 0.1, 1),       # 5: Z - 红
	Color(0.1, 0.3, 0.9, 1),       # 6: J - 蓝
	Color(1.0, 0.55, 0.0, 1),      # 7: L - 橙
	Color(0.45, 0.45, 0.45, 1),    # 8: Garbage - 灰
]

# 方块名称 → 颜色索引映射
const PIECE_NAME_COLOR: Dictionary = {
	"I": 1, "O": 2, "T": 3, "S": 4, "Z": 5, "J": 6, "L": 7
}
const PIECE_NAME_TYPE: Dictionary = {
	"I": 0, "O": 1, "T": 2, "S": 3, "Z": 4, "J": 5, "L": 6
}

# 方块迷你形状（rotation 0）用于预览绘制
const MINI_SHAPES: Dictionary = {
	"I": [[1,1,1,1]],
	"O": [[1,1],[1,1]],
	"T": [[0,1,0],[1,1,1]],
	"S": [[0,1,1],[1,1,0]],
	"Z": [[1,1,0],[0,1,1]],
	"L": [[0,0,1],[1,1,1]],
	"J": [[1,0,0],[1,1,1]]
}

const MINI_CELL: int = 18  # 预览方块格子大小
const TIMELINE_PIECE_CELL: int = 6
const TIMELINE_PIECE_ROW_H: int = 18

# 节点引用
@onready var btn_back: Button = %BtnBack
@onready var session_info_label: Label = %SessionInfoLabel
@onready var step_label: Label = %StepLabel
@onready var btn_first: Button = %BtnFirst
@onready var btn_prev: Button = %BtnPrev
@onready var btn_next: Button = %BtnNext
@onready var btn_last: Button = %BtnLast
@onready var step_slider: HSlider = %StepSlider
@onready var replay_board: Node2D = %ReplayBoard
@onready var timeline_list: VBoxContainer = %TimelineList
@onready var session_list_popup: PanelContainer = %SessionListPopup
@onready var session_list: VBoxContainer = %SessionList
@onready var data_vbox: VBoxContainer = %DataVBox

# 数据面板标签
@onready var piece_type_label: Label = %PieceTypeLabel
@onready var position_label: Label = %PositionLabel
@onready var clear_type_label: Label = %ClearTypeLabel
@onready var lines_label: Label = %LinesLabel
@onready var damage_label: Label = %DamageLabel
@onready var combo_label: Label = %ComboLabel
@onready var time_label: Label = %TimeLabel
@onready var holes_label: Label = %HolesLabel
@onready var bumpiness_label: Label = %BumpinessLabel
@onready var height_label: Label = %HeightLabel
@onready var ai_score_label: Label = %AiScoreLabel

# 当前数据
var _session_data: Dictionary = {}
var _snapshots: Array = []
var _ai_scores: Array = []
var _current_step: int = -1


func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	btn_first.pressed.connect(func(): _go_to_step(0))
	btn_prev.pressed.connect(func(): _go_to_step(_current_step - 1))
	btn_next.pressed.connect(func(): _go_to_step(_current_step + 1))
	btn_last.pressed.connect(func(): _go_to_step(_snapshots.size() - 1))
	step_slider.value_changed.connect(func(val): _go_to_step(int(val)))
	ai_score_label.add_theme_font_size_override("font_size", 44)

	_update_texts()
	_show_session_list()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()
		if _current_step >= 0:
			_update_step_label()
			_update_data_panel(_current_step)


func _update_texts() -> void:
	btn_back.text = "◀ " + tr("TXT_BACK")
	
	var title_lbl = get_node_or_null("%TitleLabel")
	if title_lbl:
		title_lbl.text = tr("TXT_REPLAY_ANALYSIS")
		
	var pinfo_lbl = get_node_or_null("%PieceInfoTitle")
	if pinfo_lbl:
		pinfo_lbl.text = "▸ " + tr("TXT_PIECE_INFO")
		
	var ter_lbl = get_node_or_null("%TerrainTitle")
	if ter_lbl:
		ter_lbl.text = "▸ " + tr("TXT_TERRAIN_METRICS")
		
	var ai_lbl = get_node_or_null("%AiTitle")
	if ai_lbl:
		ai_lbl.text = "▸ " + tr("TXT_AI_EVALUATION")
		
	var tl_lbl = get_node_or_null("%TimelineTitle")
	if tl_lbl:
		tl_lbl.text = "▸ " + tr("TXT_TIMELINE")
		
	var pop_lbl = get_node_or_null("%PopupTitle")
	if pop_lbl:
		pop_lbl.text = tr("TXT_SELECT_SESSION")
		
	if session_list.get_child_count() == 1 and session_list.get_child(0) is Label:
		(session_list.get_child(0) as Label).text = tr("TXT_NO_SESSIONS_FOUND")


# ==============================================================================
# Session 列表
# ==============================================================================

func _show_session_list() -> void:
	# 清空现有列表
	for child in session_list.get_children():
		child.queue_free()

	var files: Array = PlayerDataStore.get_all_session_files()
	if files.is_empty():
		var lbl := Label.new()
		lbl.text = tr("TXT_NO_SESSIONS_FOUND")
		lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.67))
		session_list.add_child(lbl)
		session_list_popup.visible = true
		return

	# 过滤掉 _analyzed.json 文件，按时间倒序显示（最新在前）
	var filtered: Array = []
	for f in files:
		if not str(f).ends_with("_analyzed.json"):
			filtered.append(f)
	filtered.reverse()
	for fname in filtered:
		var btn := Button.new()
		# 从文件名提取时间戳：session_2026-04-23T20-50-26.json -> 2026-04-23 20:50:26
		var raw: String = fname.replace("session_", "").replace(".json", "")
		# raw = "2026-04-23T20-50-26"  →  用 T 分割日期和时间
		var parts: PackedStringArray = raw.split("T")
		var display_name: String = raw
		if parts.size() == 2:
			display_name = parts[0] + " " + parts[1].replace("-", ":")
		btn.text = display_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", Color(0.88, 0.91, 0.94))
		btn.add_theme_color_override("font_hover_color", Color(0, 0.83, 1))
		btn.pressed.connect(_on_session_selected.bind(fname))
		session_list.add_child(btn)

	session_list_popup.visible = true


func _on_session_selected(file_name: String) -> void:
	session_list_popup.visible = false
	_load_session(file_name)


# ==============================================================================
# Session 加载
# ==============================================================================

func _load_session(file_name: String) -> void:
	var path: String = PlayerDataStore.get_sessions_dir().path_join(file_name)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[ReplaySystem] 无法打开 session 文件: %s" % path)
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[ReplaySystem] 解析 session JSON 失败: %s" % path)
		return

	_session_data = json.data as Dictionary
	_snapshots = _session_data.get("snapshots", [])

	# 更新顶部信息
	var session_id: String = str(_session_data.get("session_id", "unknown"))
	var pieces: int = int(_session_data.get("pieces_placed", 0))
	var score: int = int(_session_data.get("final_score", 0))
	session_info_label.text = "%s  |  %d pieces  |  Score: %d" % [session_id, pieces, score]

	# 尝试加载 AI 分析结果
	_load_ai_scores(file_name)

	# 设置滑块范围
	if _snapshots.size() > 0:
		step_slider.min_value = 0
		step_slider.max_value = _snapshots.size() - 1
		step_slider.step = 1
		_go_to_step(0)
	else:
		step_label.text = tr("TXT_STEP_FORMAT") % [0, 0]

	# 生成时间线
	_build_timeline()


func _load_ai_scores(session_file_name: String) -> void:
	_ai_scores = []
	var analyzed_name: String = session_file_name.replace(".json", "_analyzed.json")
	var analyzed_path: String = PlayerDataStore.get_sessions_dir().path_join(analyzed_name)

	if FileAccess.file_exists(analyzed_path):
		var file := FileAccess.open(analyzed_path, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data: Dictionary = json.data as Dictionary
				_ai_scores = data.get("ai_scores", [])
	else:
		# 尝试自动调用 Python 分析
		_run_ai_analysis(session_file_name)


func _run_ai_analysis(session_file_name: String) -> void:
	var mlp_dir: String = ""
	if OS.has_feature("editor"):
		mlp_dir = ProjectSettings.globalize_path("res://MLP")
	else:
		mlp_dir = OS.get_executable_path().get_base_dir().path_join("MLP")

	var python_path: String = _find_python(mlp_dir)
	if python_path.is_empty():
		push_warning("[ReplaySystem] 未找到 Python 环境，跳过 AI 分析")
		return

	var script_path: String = mlp_dir.path_join("analyze_session.py")
	var session_path: String = ProjectSettings.globalize_path(
		PlayerDataStore.get_sessions_dir().path_join(session_file_name)
	)
	var output_path: String = session_path.replace(".json", "_analyzed.json")

	var args: PackedStringArray = [script_path, session_path, output_path, "--model", "dqn"]
	var output: Array = []
	var exit_code: int = OS.execute(python_path, args, output, true)

	if exit_code == 0:
		# 重新加载分析结果
		if FileAccess.file_exists(output_path):
			var file := FileAccess.open(output_path, FileAccess.READ)
			if file != null:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data: Dictionary = json.data as Dictionary
					_ai_scores = data.get("ai_scores", [])
					print("[ReplaySystem] AI 分析完成: %d 步" % _ai_scores.size())
	else:
		push_warning("[ReplaySystem] AI 分析失败 (exit code %d)" % exit_code)


func _find_python(mlp_dir: String) -> String:
	# 优先使用 MLP 目录下的 venv
	var venv_python: String = mlp_dir.path_join(".venv/Scripts/python.exe")
	if FileAccess.file_exists(venv_python):
		return venv_python

	# Linux/Mac venv
	var venv_python_unix: String = mlp_dir.path_join(".venv/bin/python")
	if FileAccess.file_exists(venv_python_unix):
		return venv_python_unix

	# 系统 Python
	var output: Array = []
	if OS.execute("python", ["--version"], output, true) == 0:
		return "python"
	if OS.execute("python3", ["--version"], output, true) == 0:
		return "python3"

	return ""


# ==============================================================================
# 步进导航
# ==============================================================================

func _go_to_step(index: int) -> void:
	if _snapshots.is_empty():
		return
	index = clampi(index, 0, _snapshots.size() - 1)
	if index == _current_step:
		return

	_current_step = index
	step_slider.set_value_no_signal(index)
	_update_step_label()

	_render_step(index)
	_update_data_panel(index)
	_highlight_timeline_item(index)

func _update_step_label() -> void:
	if _snapshots.is_empty():
		step_label.text = tr("TXT_STEP_FORMAT") % [0, 0]
	else:
		step_label.text = tr("TXT_STEP_FORMAT") % [_current_step + 1, _snapshots.size()]


func _render_step(index: int) -> void:
	var snap: Dictionary = _snapshots[index]
	var board_data: Array = snap.get("board_state_after_drop", [])
	if board_data.is_empty():
		board_data = snap.get("board_state", [])
	if board_data.is_empty():
		board_data = snap.get("board_state_after_clear", [])

	# 清除旧绘制
	for child in replay_board.get_children():
		child.queue_free()

	# 绘制棋盘格
	for r in range(mini(board_data.size(), BOARD_ROWS)):
		var row: Array = board_data[r]
		for c in range(mini(row.size(), BOARD_COLS)):
			var cell_val: int = int(row[c])
			var rect := ColorRect.new()
			rect.size = Vector2(CELL_SIZE - 1, CELL_SIZE - 1)
			rect.position = Vector2(c * CELL_SIZE, r * CELL_SIZE)
			if cell_val > 0 and cell_val < CELL_COLORS.size():
				rect.color = CELL_COLORS[cell_val]
			elif cell_val > 0:
				# 兼容未知非空编码（例如未来新增块类型）
				rect.color = CELL_COLORS[8]
			else:
				rect.color = CELL_COLORS[0]
			replay_board.add_child(rect)

	# 绘制网格线
	var grid_color := Color(0.15, 0.15, 0.22, 0.5)
	for r in range(BOARD_ROWS + 1):
		var line := ColorRect.new()
		line.size = Vector2(BOARD_COLS * CELL_SIZE, 1)
		line.position = Vector2(0, r * CELL_SIZE)
		line.color = grid_color
		replay_board.add_child(line)
	for c in range(BOARD_COLS + 1):
		var line := ColorRect.new()
		line.size = Vector2(1, BOARD_ROWS * CELL_SIZE)
		line.position = Vector2(c * CELL_SIZE, 0)
		line.color = grid_color
		replay_board.add_child(line)

	# 高亮本步新落下的方块（锁定时的 piece_type/rotation/col/row）
	_draw_locked_piece_highlight(snap, index)

	# 棋盘外框（4条薄线，不再用填充矩形）
	var bw: float = BOARD_COLS * CELL_SIZE
	var bh: float = BOARD_ROWS * CELL_SIZE
	var bc := Color(0, 0.83, 1, 0.4)
	for edge in [
		[Vector2(-1, -1), Vector2(bw + 2, 1)],       # 上
		[Vector2(-1, bh), Vector2(bw + 2, 1)],        # 下
		[Vector2(-1, -1), Vector2(1, bh + 2)],        # 左
		[Vector2(bw, -1), Vector2(1, bh + 2)],        # 右
	]:
		var e := ColorRect.new()
		e.position = edge[0]
		e.size = edge[1]
		e.color = bc
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		replay_board.add_child(e)

	# 居中棋盘
	_center_board()

	# 绘制 Hold 和 Next 预览
	_draw_hold_piece(snap)
	_draw_next_pieces(snap)



func _update_data_panel(index: int) -> void:
	var snap: Dictionary = _snapshots[index]

	piece_type_label.text = "%s %s" % [tr("TXT_TYPE"), str(snap.get("piece_type", "?"))]
	position_label.text = "%s col=%d, row=%d, rot=%d" % [
		tr("TXT_POSITION"), int(snap.get("col", 0)), int(snap.get("row", 0)), int(snap.get("rotation", 0))
	]

	# 消除类型
	var lcl: int = int(snap.get("lines_cleared_this_lock", 0))
	var clear_text: String = tr("TXT_NONE")
	if lcl > 0:
		var is_spin: bool = snap.get("is_spin", false)
		var is_t_spin: bool = snap.get("is_t_spin", false)
		if is_t_spin:
			clear_text = "T-Spin %s" % _lines_name(lcl)
		elif is_spin:
			clear_text = "Spin %s" % _lines_name(lcl)
		else:
			clear_text = _lines_name(lcl)
	clear_type_label.text = "%s %s" % [tr("TXT_CLEAR"), clear_text]

	lines_label.text = tr("TXT_LINES_CLEARED") % [lcl, int(snap.get("lines_cleared", 0))]
	damage_label.text = tr("TXT_DAMAGE_VAL") % int(snap.get("damage_this_lock", 0))
	combo_label.text = tr("TXT_COMBO_VAL") % [int(snap.get("combo", -1)), int(snap.get("b2b", -1))]
	time_label.text = tr("TXT_TIME_VAL") % ("%dms" % int(snap.get("elapsed_since_last_piece_ms", 0)))

	# 地形指标
	holes_label.text = "%s %d" % [tr("TXT_HOLES"), int(snap.get("holes", 0))]
	bumpiness_label.text = "%s %d" % [tr("TXT_BUMPINESS"), int(snap.get("bumpiness", 0))]
	height_label.text = "%s %d" % [tr("TXT_TOTAL_HEIGHT"), int(snap.get("total_height", 0))]

	# AI 评分
	if index < _ai_scores.size():
		var score_val: float = float(_ai_scores[index])
		var delta: float = _timeline_score_delta(index)
		ai_score_label.text = "%.2f\n(%+d)" % [score_val, roundi(delta)]
		ai_score_label.add_theme_color_override("font_color", _ai_score_color(score_val))
	else:
		ai_score_label.text = "%s\n(-)" % tr("TXT_NA")
		ai_score_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.67))


func _lines_name(count: int) -> String:
	match count:
		1: return "Single"
		2: return "Double"
		3: return "Triple"
		_: return "Tetris" if count >= 4 else ""

func _ai_score_color(score_val: float) -> Color:
	if score_val > 100.0:
		return Color(0.0, 0.95, 0.45)
	if score_val >= 0.0:
		return Color(1.0, 0.85, 0.2)
	return Color(1.0, 0.3, 0.3)


func _timeline_score_delta(index: int) -> float:
	if index < 0 or index >= _ai_scores.size():
		return 0.0
	if index == 0:
		return 0.0
	return float(_ai_scores[index]) - float(_ai_scores[index - 1])


func _timeline_delta_color(delta: float) -> Color:
	if delta < -150.0:
		return Color(0.65, 0.0, 0.0) # 深红
	if delta <= -100.0:
		return Color(1.0, 0.22, 0.22) # 红
	if delta <= -50.0:
		return Color(1.0, 0.84, 0.2) # 黄
	if delta <= 50.0:
		return Color(0.62, 0.95, 0.62) # 淡绿
	return Color(0.1, 1.0, 0.25) # 鲜绿


func _timeline_row_color(index: int) -> Color:
	if index >= 0 and index < _ai_scores.size():
		return _timeline_delta_color(_timeline_score_delta(index))
	return Color(0.6, 0.65, 0.75)


func _set_timeline_button_border(btn: Button, border_color: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	if selected:
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = border_color
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)


# ==============================================================================
# 时间线
# ==============================================================================

func _build_timeline() -> void:
	for child in timeline_list.get_children():
		child.queue_free()

	for i in range(_snapshots.size()):
		var snap: Dictionary = _snapshots[i]
		var piece_name: String = str(snap.get("piece_type", "?"))
		var elapsed_ms: int = int(snap.get("elapsed_since_last_piece_ms", 0))

		# 行容器
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size.y = 26
		hbox.add_theme_constant_override("separation", 4)

		# 方块颜色指示条
		var cidx: int = PIECE_NAME_COLOR.get(piece_name, 0)
		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(4, 20)
		if cidx > 0 and cidx < CELL_COLORS.size():
			indicator.color = CELL_COLORS[cidx]
		else:
			indicator.color = Color(0.3, 0.3, 0.4)
		hbox.add_child(indicator)
		hbox.add_child(_create_timeline_piece_icon(piece_name))

		# 按钮（点击跳转）
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		var row_color: Color = _timeline_row_color(i)
		var delta_text: String = "(+0)"
		if i < _ai_scores.size():
			var delta: float = _timeline_score_delta(i)
			delta_text = "(%+d)" % roundi(delta)
		btn.add_theme_color_override("font_color", row_color)
		_set_timeline_button_border(btn, row_color, i == _current_step)

		# AI 分数
		var ai_text: String = ""
		if i < _ai_scores.size():
			ai_text = "%.1f" % float(_ai_scores[i])
		else:
			ai_text = "-"

		# 用时
		var time_text: String = "%dms" % elapsed_ms
		if elapsed_ms >= 1000:
			time_text = "%.1fs" % (elapsed_ms / 1000.0)

		btn.text = "#%d  %s %s  %s" % [i + 1, ai_text, delta_text, time_text]
		btn.pressed.connect(_go_to_step.bind(i))
		hbox.add_child(btn)

		timeline_list.add_child(hbox)


func _highlight_timeline_item(index: int) -> void:
	for i in range(timeline_list.get_child_count()):
		var hbox: HBoxContainer = timeline_list.get_child(i) as HBoxContainer
		if hbox == null or hbox.get_child_count() < 2:
			continue
		var btn: Button = hbox.get_child(hbox.get_child_count() - 1) as Button
		if btn == null:
			continue
		var row_color: Color = _timeline_row_color(i)
		btn.add_theme_color_override("font_color", row_color)
		_set_timeline_button_border(btn, row_color, i == index)

	# 自动滚动到当前步
	var scroll: ScrollContainer = timeline_list.get_parent() as ScrollContainer
	if scroll and index < timeline_list.get_child_count():
		var target_btn: Control = timeline_list.get_child(index)
		scroll.ensure_control_visible(target_btn)


# ==============================================================================
# 导航
# ==============================================================================

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if session_list_popup.visible:
			session_list_popup.visible = false
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") and not session_list_popup.visible:
		_go_to_step(_current_step - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not session_list_popup.visible:
		_go_to_step(_current_step + 1)
		get_viewport().set_input_as_handled()


# ==============================================================================
# 棋盘居中 + Hold / Next 预览
# ==============================================================================

func _center_board() -> void:
	var container: Control = replay_board.get_parent()
	if container == null:
		return
	var bw: float = BOARD_COLS * CELL_SIZE
	var bh: float = BOARD_ROWS * CELL_SIZE
	replay_board.position.x = (container.size.x - bw) / 2.0
	replay_board.position.y = (container.size.y - bh) / 2.0


func _draw_hold_piece(snap: Dictionary) -> void:
	var hold_name: String = str(snap.get("hold_piece", ""))
	var hold_x: float = -(MINI_CELL * 4 + 25)
	var y_offset: float = 10.0

	# "HOLD" 标签
	var lbl := Label.new()
	lbl.text = tr("TXT_HOLD")
	lbl.add_theme_color_override("font_color", Color(0, 0.83, 1, 0.8))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = Vector2(hold_x, y_offset - 5)
	replay_board.add_child(lbl)
	y_offset += 20.0

	if hold_name != "" and MINI_SHAPES.has(hold_name):
		_draw_mini_piece(hold_name, Vector2(hold_x, y_offset))
	else:
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_color_override("font_color", Color(0.3, 0.3, 0.45))
		dash.position = Vector2(hold_x + 10, y_offset)
		replay_board.add_child(dash)


func _draw_next_pieces(snap: Dictionary) -> void:
	var next_names: Array = snap.get("next_pieces", [])
	var board_right_x: float = BOARD_COLS * CELL_SIZE + 20.0
	var y_offset: float = 10.0

	# "NEXT" 标签
	var lbl := Label.new()
	lbl.text = tr("TXT_NEXT")
	lbl.add_theme_color_override("font_color", Color(0, 0.83, 1, 0.8))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = Vector2(board_right_x, y_offset - 5)
	replay_board.add_child(lbl)
	y_offset += 20.0

	for idx in range(mini(next_names.size(), 5)):
		var pname: String = str(next_names[idx])
		_draw_mini_piece(pname, Vector2(board_right_x, y_offset))
		y_offset += MINI_CELL * 3 + 8


func _draw_mini_piece(piece_name: String, origin: Vector2) -> void:
	var shape: Array = MINI_SHAPES.get(piece_name, [[1]])
	var cidx: int = PIECE_NAME_COLOR.get(piece_name, 0)
	var col: Color = CELL_COLORS[cidx] if cidx < CELL_COLORS.size() else Color.WHITE

	for r in range(shape.size()):
		var row_data: Array = shape[r]
		for c in range(row_data.size()):
			if int(row_data[c]) != 0:
				var rect := ColorRect.new()
				rect.size = Vector2(MINI_CELL - 1, MINI_CELL - 1)
				rect.position = origin + Vector2(c * MINI_CELL, r * MINI_CELL)
				rect.color = col
				replay_board.add_child(rect)


func _create_timeline_piece_icon(piece_name: String) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(TIMELINE_PIECE_CELL * 4 + 2, TIMELINE_PIECE_ROW_H)

	var shape: Array = MINI_SHAPES.get(piece_name, [])
	if shape.is_empty():
		return box

	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size() if rows > 0 else 0
	var piece_w: float = cols * TIMELINE_PIECE_CELL
	var piece_h: float = rows * TIMELINE_PIECE_CELL
	var off_x: float = maxi(0, int((box.custom_minimum_size.x - piece_w) * 0.5))
	var off_y: float = maxi(0, int((box.custom_minimum_size.y - piece_h) * 0.5))

	var cidx: int = PIECE_NAME_COLOR.get(piece_name, 0)
	var col: Color = CELL_COLORS[cidx] if cidx < CELL_COLORS.size() else Color(0.85, 0.85, 0.85)

	for r in range(rows):
		var row_data: Array = shape[r]
		for c in range(row_data.size()):
			if int(row_data[c]) == 0:
				continue
			var rect := ColorRect.new()
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.size = Vector2(TIMELINE_PIECE_CELL - 1, TIMELINE_PIECE_CELL - 1)
			rect.position = Vector2(off_x + c * TIMELINE_PIECE_CELL, off_y + r * TIMELINE_PIECE_CELL)
			rect.color = col
			box.add_child(rect)

	return box


func _draw_locked_piece_highlight(snap: Dictionary, step_index: int) -> void:
	var piece_name: String = str(snap.get("piece_type", ""))
	if not PIECE_NAME_TYPE.has(piece_name):
		return

	var piece_type: int = int(PIECE_NAME_TYPE[piece_name])
	var rot: int = posmod(int(snap.get("rotation", 0)), 4)
	var center_col: int = int(snap.get("col", -999))
	var center_row_raw: int = int(snap.get("row", -999))
	if center_col < -100 or center_row_raw < -100:
		return

	var center_row: int = center_row_raw - BOARD_ROWS if center_row_raw >= BOARD_ROWS else center_row_raw
	var row_color: Color = _timeline_row_color(step_index)
	var cidx: int = PIECE_NAME_COLOR.get(piece_name, 0)
	var piece_glow_col: Color = CELL_COLORS[cidx] if cidx < CELL_COLORS.size() else Color(1, 1, 1, 1)
	var inner_border_col: Color = Color(1.0, 1.0, 1.0, 0.48)
	var glow_col: Color = row_color
	glow_col.a = 0.90

	var cells: Array[Vector2i] = []
	var shape: Array = PieceData.SHAPES[piece_type][rot]
	for offset in shape:
		var gx: int = center_col + int(offset.x)
		var gy: int = center_row + int(offset.y)
		if gx < 0 or gx >= BOARD_COLS or gy < 0 or gy >= BOARD_ROWS:
			continue
		cells.append(Vector2i(gx, gy))
		_add_cell_self_glow(gx, gy, piece_glow_col)
		_add_highlight_border(gx, gy, inner_border_col)

	_add_piece_glow_outline(cells, glow_col)


func _add_highlight_border(col: int, row: int, border_col: Color) -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(col * CELL_SIZE, row * CELL_SIZE)
	panel.size = Vector2(CELL_SIZE - 1, CELL_SIZE - 1)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = border_col
	panel.add_theme_stylebox_override("panel", sb)

	replay_board.add_child(panel)


func _add_piece_glow_outline(cells: Array[Vector2i], glow_col: Color) -> void:
	if cells.is_empty():
		return

	var cell_set: Dictionary = {}
	for p in cells:
		cell_set[_cell_key(p.x, p.y)] = true

	var cell_px: float = CELL_SIZE - 1
	for p in cells:
		var gx: int = p.x
		var gy: int = p.y
		var x: float = gx * CELL_SIZE
		var y: float = gy * CELL_SIZE

		# Left edge
		if not cell_set.has(_cell_key(gx - 1, gy)):
			_add_glow_strip(Vector2(x - 1, y), Vector2(1, cell_px), glow_col, 0.90)
			_add_glow_strip(Vector2(x - 4, y - 1), Vector2(3, cell_px + 2), glow_col, 0.46)
			_add_glow_strip(Vector2(x - 7, y - 2), Vector2(3, cell_px + 4), glow_col, 0.22)
		# Right edge
		if not cell_set.has(_cell_key(gx + 1, gy)):
			_add_glow_strip(Vector2(x + cell_px, y), Vector2(1, cell_px), glow_col, 0.90)
			_add_glow_strip(Vector2(x + cell_px + 1, y - 1), Vector2(3, cell_px + 2), glow_col, 0.46)
			_add_glow_strip(Vector2(x + cell_px + 4, y - 2), Vector2(3, cell_px + 4), glow_col, 0.22)
		# Top edge
		if not cell_set.has(_cell_key(gx, gy - 1)):
			_add_glow_strip(Vector2(x, y - 1), Vector2(cell_px, 1), glow_col, 0.90)
			_add_glow_strip(Vector2(x - 1, y - 4), Vector2(cell_px + 2, 3), glow_col, 0.46)
			_add_glow_strip(Vector2(x - 2, y - 7), Vector2(cell_px + 4, 3), glow_col, 0.22)
		# Bottom edge
		if not cell_set.has(_cell_key(gx, gy + 1)):
			_add_glow_strip(Vector2(x, y + cell_px), Vector2(cell_px, 1), glow_col, 0.90)
			_add_glow_strip(Vector2(x - 1, y + cell_px + 1), Vector2(cell_px + 2, 3), glow_col, 0.46)
			_add_glow_strip(Vector2(x - 2, y + cell_px + 4), Vector2(cell_px + 4, 3), glow_col, 0.22)


func _add_cell_self_glow(col: int, row: int, glow_col: Color) -> void:
	var cell_px: float = CELL_SIZE - 1
	var x: float = col * CELL_SIZE
	var y: float = row * CELL_SIZE

	var outer_size: float = maxf(1.0, cell_px - 4.0)
	_add_glow_strip(Vector2(x + 2, y + 2), Vector2(outer_size, outer_size), glow_col, 0.24)

	var core_size: float = maxf(1.0, cell_px - 12.0)
	var core_off: float = (cell_px - core_size) * 0.5
	_add_glow_strip(Vector2(x + core_off, y + core_off), Vector2(core_size, core_size), glow_col, 0.30)


func _cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _add_glow_strip(pos: Vector2, size: Vector2, glow_col: Color, alpha: float) -> void:
	var strip := ColorRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = pos
	strip.size = size
	strip.color = Color(glow_col.r, glow_col.g, glow_col.b, clampf(alpha, 0.0, 1.0))
	replay_board.add_child(strip)
