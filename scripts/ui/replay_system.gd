class_name ReplaySystem
extends Control

## 对局复盘系统
## 加载历史 session JSON，逐步回放棋盘状态，展示 AI 评分。

const BOARD_ROWS: int = 20
const BOARD_COLS: int = 10
const CELL_SIZE: int = 30

# 方块颜色（与 PieceData.COLORS 一致，0=空）
const CELL_COLORS: Array[Color] = [
	Color(0.08, 0.08, 0.12, 1),    # 0: 空 — 深色背景
	Color(0.0, 0.85, 0.85, 1),     # 1: I — 青
	Color(1.0, 0.85, 0.0, 1),      # 2: O — 黄
	Color(0.6, 0.0, 0.8, 1),       # 3: T — 紫
	Color(0.0, 0.8, 0.0, 1),       # 4: S — 绿
	Color(0.9, 0.1, 0.1, 1),       # 5: Z — 红
	Color(1.0, 0.55, 0.0, 1),      # 6: L — 橙
	Color(0.1, 0.3, 0.9, 1),       # 7: J — 蓝
]

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

	_show_session_list()


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
		lbl.text = "No sessions found"
		lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.67))
		session_list.add_child(lbl)
		session_list_popup.visible = true
		return

	# 按时间倒序显示（最新在前）
	files.reverse()
	for fname in files:
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
		step_label.text = "No snapshots"

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
	step_label.text = "Step %d / %d" % [index + 1, _snapshots.size()]

	_render_step(index)
	_update_data_panel(index)
	_highlight_timeline_item(index)


func _render_step(index: int) -> void:
	var snap: Dictionary = _snapshots[index]
	var board_data: Array = snap.get("board_state", [])

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

	# 棋盘外框
	var border := ColorRect.new()
	border.size = Vector2(BOARD_COLS * CELL_SIZE + 2, BOARD_ROWS * CELL_SIZE + 2)
	border.position = Vector2(-1, -1)
	border.color = Color(0, 0.83, 1, 0.3)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_board.add_child(border)
	# 填充内部让边框只有1px
	var inner := ColorRect.new()
	inner.size = Vector2(BOARD_COLS * CELL_SIZE, BOARD_ROWS * CELL_SIZE)
	inner.position = Vector2(0, 0)
	inner.color = Color(0, 0, 0, 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_board.add_child(inner)


func _update_data_panel(index: int) -> void:
	var snap: Dictionary = _snapshots[index]

	piece_type_label.text = "Type: %s" % str(snap.get("piece_type", "?"))
	position_label.text = "Position: col=%d, row=%d, rot=%d" % [
		int(snap.get("col", 0)), int(snap.get("row", 0)), int(snap.get("rotation", 0))
	]

	# 消除类型
	var lcl: int = int(snap.get("lines_cleared_this_lock", 0))
	var clear_text: String = "None"
	if lcl > 0:
		var is_spin: bool = snap.get("is_spin", false)
		var is_t_spin: bool = snap.get("is_t_spin", false)
		if is_t_spin:
			clear_text = "T-Spin %s" % _lines_name(lcl)
		elif is_spin:
			clear_text = "Spin %s" % _lines_name(lcl)
		else:
			clear_text = _lines_name(lcl)
	clear_type_label.text = "Clear: %s" % clear_text

	lines_label.text = "Lines: %d (total: %d)" % [lcl, int(snap.get("lines_cleared", 0))]
	damage_label.text = "Damage: %d" % int(snap.get("damage_this_lock", 0))
	combo_label.text = "Combo: %d / B2B: %d" % [int(snap.get("combo", -1)), int(snap.get("b2b", -1))]
	time_label.text = "Time: %dms" % int(snap.get("elapsed_since_last_piece_ms", 0))

	# 地形指标
	holes_label.text = "Holes: %d" % int(snap.get("holes", 0))
	bumpiness_label.text = "Bumpiness: %d" % int(snap.get("bumpiness", 0))
	height_label.text = "Total Height: %d" % int(snap.get("total_height", 0))

	# AI 评分
	if index < _ai_scores.size():
		var score_val: float = float(_ai_scores[index])
		ai_score_label.text = "%.2f" % score_val
		# 颜色分级：正值越高越绿，负值越低越红
		if score_val > 5.0:
			ai_score_label.add_theme_color_override("font_color", Color(0, 1, 0.53))
		elif score_val > 0.0:
			ai_score_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		elif score_val > -5.0:
			ai_score_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		else:
			ai_score_label.add_theme_color_override("font_color", Color(1, 0.27, 0.27))
	else:
		ai_score_label.text = "N/A"
		ai_score_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.67))


func _lines_name(count: int) -> String:
	match count:
		1: return "Single"
		2: return "Double"
		3: return "Triple"
		_: return "Tetris" if count >= 4 else ""


# ==============================================================================
# 时间线
# ==============================================================================

func _build_timeline() -> void:
	for child in timeline_list.get_children():
		child.queue_free()

	for i in range(_snapshots.size()):
		var snap: Dictionary = _snapshots[i]
		var btn := Button.new()
		var piece_name: String = str(snap.get("piece_type", "?"))
		var lcl: int = int(snap.get("lines_cleared_this_lock", 0))
		var suffix: String = ""
		if lcl > 0:
			suffix = " ★%d" % lcl
		btn.text = "#%d  %s%s" % [i + 1, piece_name, suffix]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_go_to_step.bind(i))
		timeline_list.add_child(btn)


func _highlight_timeline_item(index: int) -> void:
	for i in range(timeline_list.get_child_count()):
		var btn: Button = timeline_list.get_child(i) as Button
		if btn == null:
			continue
		if i == index:
			btn.add_theme_color_override("font_color", Color(0, 0.83, 1))
		else:
			var lcl: int = 0
			if i < _snapshots.size():
				lcl = int(_snapshots[i].get("lines_cleared_this_lock", 0))
			if lcl > 0:
				btn.add_theme_color_override("font_color", Color(0, 1, 0.53))
			else:
				btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))

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
