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
const TIMELINE_STEP_W: int = 48
const TIMELINE_NAME_W: int = 14
const TIMELINE_AI_W: int = 48
const TIMELINE_TIME_W: int = 48
const TIMELINE_TAG_W: int = 58

# cold-clear 兼容形状表（visible 坐标系，y 向下）
# 从 libtetris gen_cells! 宏精确转换：North=(x,-y), East=(-y,-x), South=(-x,y), West=(y,x)
const CC_SHAPES: Dictionary = {
	"I": {
		0: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)],
		1: [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(0, 2)],
		2: [Vector2(1, 0), Vector2(0, 0), Vector2(-1, 0), Vector2(-2, 0)],
		3: [Vector2(0, 1), Vector2(0, 0), Vector2(0, -1), Vector2(0, -2)]
	},
	"O": {
		0: [Vector2(0, 0), Vector2(1, 0), Vector2(0, -1), Vector2(1, -1)],
		1: [Vector2(0, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(-1, -1)],
		2: [Vector2(0, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(-1, 1)],
		3: [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)]
	},
	"T": {
		0: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, -1)],
		1: [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(1, 0)],
		2: [Vector2(1, 0), Vector2(0, 0), Vector2(-1, 0), Vector2(0, 1)],
		3: [Vector2(0, 1), Vector2(0, 0), Vector2(0, -1), Vector2(-1, 0)]
	},
	"L": {
		0: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, -1)],
		1: [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
		2: [Vector2(1, 0), Vector2(0, 0), Vector2(-1, 0), Vector2(-1, 1)],
		3: [Vector2(0, 1), Vector2(0, 0), Vector2(0, -1), Vector2(-1, -1)]
	},
	"J": {
		0: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(-1, -1)],
		1: [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(1, -1)],
		2: [Vector2(1, 0), Vector2(0, 0), Vector2(-1, 0), Vector2(1, 1)],
		3: [Vector2(0, 1), Vector2(0, 0), Vector2(0, -1), Vector2(-1, 1)]
	},
	"S": {
		0: [Vector2(-1, 0), Vector2(0, 0), Vector2(0, -1), Vector2(1, -1)],
		1: [Vector2(0, -1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
		2: [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(-1, 1)],
		3: [Vector2(0, 1), Vector2(0, 0), Vector2(-1, 0), Vector2(-1, -1)]
	},
	"Z": {
		0: [Vector2(-1, -1), Vector2(0, -1), Vector2(0, 0), Vector2(1, 0)],
		1: [Vector2(1, -1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)],
		2: [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(-1, 0)],
		3: [Vector2(-1, 1), Vector2(-1, 0), Vector2(0, 0), Vector2(0, -1)]
	}
}

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
var _ai_details: Array = []
var _ai_recommendations: Array = []
var _current_step: int = -1
var _showing_ai_plan: bool = false
var _ai_plan_reveal_count: int = 0
var _ai_plan_simulated_board: Array = []
var _ai_plan_board_history: Array = []  # 每步锁定前的棋盘快照，用于回退
var _analysis_active: bool = false
var _analysis_pid: int = -1
var _analysis_session_file_name: String = ""
var _analysis_output_path: String = ""
var _analysis_progress_path: String = ""
var _analysis_started_msec: int = 0
var _analysis_last_worker_current: int = 0
var _analysis_overlay: Control = null
var _analysis_progress_bar: ProgressBar = null
var _analysis_status_label: Label = null
var _analysis_detail_label: Label = null
var _session_overview_panel: Control = null
var _session_radar_chart: Control = null
var _summary_value_labels: Dictionary = {}
var _metric_tooltip_controls: Dictionary = {}


func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	btn_first.pressed.connect(func(): _go_to_step(0))
	btn_prev.pressed.connect(func(): _go_to_step(_current_step - 1))
	btn_next.pressed.connect(func(): _go_to_step(_current_step + 1))
	btn_last.pressed.connect(func(): _go_to_step(_snapshots.size() - 1))
	step_slider.value_changed.connect(func(val): _go_to_step(int(val)))
	ai_score_label.custom_minimum_size = Vector2(0, 54)
	ai_score_label.add_theme_font_size_override("font_size", 44)
	set_process(false)

	_update_texts()
	_ensure_session_overview_panel()
	_update_session_overview()
	_show_session_list()
	call_deferred("_focus_default_control")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()
		_update_analysis_overlay_text()
		if _current_step >= 0:
			_update_step_label()
			_update_data_panel(_current_step)


func _process(_delta: float) -> void:
	if not _analysis_active:
		return
	_update_analysis_progress_overlay()
	if _analysis_pid > 0 and not OS.is_process_running(_analysis_pid):
		_finish_ai_analysis_process()


func _update_texts() -> void:
	btn_back.text = "◀ " + tr("TXT_BACK")
	
	var title_lbl = get_node_or_null("%TitleLabel")
	if title_lbl:
		title_lbl.text = tr("TXT_REPLAY_ANALYSIS")
		
	var pinfo_lbl = data_vbox.get_node_or_null("PieceInfoTitle")
	if pinfo_lbl:
		pinfo_lbl.text = "▸ " + tr("TXT_PIECE_INFO")
		
	var ter_lbl = data_vbox.get_node_or_null("TerrainTitle")
	if ter_lbl:
		ter_lbl.text = "▸ " + tr("TXT_TERRAIN_METRICS")
		
	var ai_lbl = data_vbox.get_node_or_null("AiTitle")
	if ai_lbl:
		ai_lbl.text = "▸ " + tr("TXT_AI_CURRENT_STEP")
		
	var tl_lbl = get_node_or_null("%TimelineTitle")
	if tl_lbl:
		tl_lbl.text = "▸ " + tr("TXT_TIMELINE")
		
	var pop_lbl = get_node_or_null("%PopupTitle")
	if pop_lbl:
		pop_lbl.text = tr("TXT_SELECT_SESSION")
		
	if session_list.get_child_count() == 1 and session_list.get_child(0) is Label:
		(session_list.get_child(0) as Label).text = tr("TXT_NO_SESSIONS_FOUND")
	_update_session_overview_texts()


func _ensure_session_overview_panel() -> void:
	if _session_overview_panel != null:
		return

	_hide_legacy_step_stats()

	var root := VBoxContainer.new()
	root.name = "SessionOverview"
	root.add_theme_constant_override("separation", 9)
	data_vbox.add_child(root)
	data_vbox.move_child(root, 0)
	_session_overview_panel = root

	var title := Label.new()
	title.name = "OverviewTitle"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.38, 0.92, 1.0))
	root.add_child(title)

	var radar_wrap := CenterContainer.new()
	root.add_child(radar_wrap)

	var radar := RadarChart.new()
	radar.auto_minimum_size = false
	radar.custom_minimum_size = Vector2(178, 166)
	radar.chart_radius = 52.0
	radar.grid_color = Color(0.23, 0.30, 0.42, 0.42)
	radar.axis_color = Color(0.45, 0.55, 0.72, 0.55)
	radar.fill_color = Color(0.0, 0.78, 1.0, 0.20)
	radar.outline_color = Color(0.1, 0.9, 1.0, 0.92)
	radar.outline_width = 2.0
	radar.vertex_dot_radius = 2.8
	radar.label_font_size = 13
	radar.label_offset = 22.0
	radar.label_color = Color(0.70, 0.77, 0.88, 0.95)
	radar.show_value_labels = false
	radar.grid_levels = 3
	radar.animation_duration = 0.45
	radar_wrap.add_child(radar)
	_session_radar_chart = radar

	var core_grid := GridContainer.new()
	core_grid.name = "CoreMetrics"
	core_grid.columns = 2
	core_grid.add_theme_constant_override("h_separation", 10)
	core_grid.add_theme_constant_override("v_separation", 10)
	root.add_child(core_grid)
	for metric in [
		["pps", "PPS", Color(0.10, 0.84, 1.0)],
		["apm", "APM", Color(1.0, 0.46, 0.34)],
		["app", "APP", Color(0.50, 0.90, 0.42)],
		["kpp", "KPP", Color(1.0, 0.82, 0.30)],
	]:
		core_grid.add_child(_create_metric_block(metric[0], metric[1], metric[2]))

	var line := HSeparator.new()
	root.add_child(line)

	var stat_grid := GridContainer.new()
	stat_grid.name = "SessionStats"
	stat_grid.columns = 2
	stat_grid.add_theme_constant_override("h_separation", 10)
	stat_grid.add_theme_constant_override("v_separation", 7)
	root.add_child(stat_grid)
	for stat in [
		["score", "TXT_SCORE"],
		["duration", "TXT_DURATION"],
		["pieces", "TXT_PIECES"],
		["lines", "TXT_LINES"],
		["damage", "TXT_DAMAGE"],
		["keys", "TXT_KEYS"],
		["quads", "TXT_REPLAY_QUADS"],
		["tspins", "TXT_REPLAY_TSPINS"],
		["combo", "TXT_MAX_COMBO"],
		["b2b", "TXT_MAX_B2B"],
		["clears", "TXT_REPLAY_CLEAR_MIX"],
		["ai_score", "TXT_REPLAY_AI_SCORE"],
	]:
		stat_grid.add_child(_create_stat_row(stat[0], stat[1]))

	var separator := HSeparator.new()
	root.add_child(separator)

	_update_session_overview_texts()


func _hide_legacy_step_stats() -> void:
	for node_name in [
		"PieceInfoTitle",
		"PieceTypeLabel",
		"PositionLabel",
		"ClearTypeLabel",
		"LinesLabel",
		"DamageLabel",
		"ComboLabel",
		"TimeLabel",
		"Sep1",
		"TerrainTitle",
		"HolesLabel",
		"BumpinessLabel",
		"HeightLabel",
		"Sep2",
	]:
		var node := data_vbox.get_node_or_null(node_name)
		if node is CanvasItem:
			(node as CanvasItem).visible = false


func _create_metric_block(key: String, title: String, accent: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 60)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)

	var value_wrap := CenterContainer.new()
	value_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(value_wrap)

	var value := Label.new()
	value.name = "Value"
	value.mouse_filter = Control.MOUSE_FILTER_STOP
	value.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 27)
	value.add_theme_color_override("font_color", accent)
	value_wrap.add_child(value)
	_summary_value_labels[key] = value

	var label_wrap := CenterContainer.new()
	label_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label_wrap)

	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.56, 0.63, 0.75))
	label_wrap.add_child(label)
	_metric_tooltip_controls[key] = [value, label]
	_apply_metric_tooltip(key)

	return box


func _create_stat_row(key: String, title_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.name = "Title"
	title.text = tr(title_key)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.56, 0.63, 0.75))
	row.add_child(title)

	var value := Label.new()
	value.name = "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	row.add_child(value)
	_summary_value_labels[key] = value
	_summary_value_labels["title_%s" % key] = title

	return row


func _update_session_overview_texts() -> void:
	if _session_overview_panel == null:
		return
	var title := _session_overview_panel.get_node_or_null("OverviewTitle") as Label
	if title != null:
		title.text = "▸ " + tr("TXT_REPLAY_SESSION_OVERVIEW")
	var title_keys := {
		"score": "TXT_SCORE",
		"duration": "TXT_DURATION",
		"pieces": "TXT_PIECES",
		"lines": "TXT_LINES",
		"damage": "TXT_DAMAGE",
		"keys": "TXT_KEYS",
		"quads": "TXT_REPLAY_QUADS",
		"tspins": "TXT_REPLAY_TSPINS",
		"combo": "TXT_MAX_COMBO",
		"b2b": "TXT_MAX_B2B",
		"clears": "TXT_REPLAY_CLEAR_MIX",
		"ai_score": "TXT_REPLAY_AI_SCORE",
	}
	for key in title_keys.keys():
		var lbl := _summary_value_labels.get("title_%s" % key, null) as Label
		if lbl != null:
			lbl.text = tr(title_keys[key])
	_refresh_metric_tooltips()


func _refresh_metric_tooltips() -> void:
	for key in _metric_tooltip_controls.keys():
		_apply_metric_tooltip(str(key))


func _apply_metric_tooltip(key: String) -> void:
	var controls: Array = _metric_tooltip_controls.get(key, [])
	if controls.is_empty():
		return
	var text := tr("TXT_REPLAY_%s_TOOLTIP" % key.to_upper())
	for control in controls:
		if control is Control:
			(control as Control).tooltip_text = text


func _update_session_overview() -> void:
	_ensure_session_overview_panel()
	var radar: Dictionary = _session_data.get("radar_scores", {})
	if _session_radar_chart != null and _session_radar_chart.has_method("set_data"):
		_session_radar_chart.set_data(radar, is_inside_tree())

	if _session_data.is_empty():
		for key in [
			"pps",
			"apm",
			"app",
			"kpp",
			"score",
			"duration",
			"pieces",
			"lines",
			"damage",
			"keys",
			"quads",
			"tspins",
			"combo",
			"b2b",
			"clears",
			"ai_score",
		]:
			_set_summary_value(key, "—")
		return

	_set_summary_value("pps", "%.2f" % _session_float("pps"))
	_set_summary_value("apm", "%.1f" % _session_float("apm"))
	_set_summary_value("app", "%.2f" % _session_float("app"))
	_set_summary_value("kpp", "%.2f" % _session_float("kpp"))
	_set_summary_value("score", _format_number(int(_session_data.get("final_score", 0))))
	_set_summary_value("duration", _format_duration(float(_session_data.get("duration_seconds", 0.0))))
	_set_summary_value("pieces", _format_number(int(_session_data.get("pieces_placed", 0))))
	_set_summary_value("lines", _format_number(int(_session_data.get("final_lines", 0))))
	_set_summary_value("damage", _format_number(int(_session_data.get("total_damage", 0))))
	_set_summary_value("keys", _format_number(int(_session_data.get("total_key_presses", 0))))
	_set_summary_value("quads", str(int(_session_data.get("tetrises", 0))))
	_set_summary_value("tspins", str(int(_session_data.get("t_spin_clears", 0))))
	_set_summary_value("combo", str(int(_session_data.get("max_combo", 0))))
	_set_summary_value("b2b", str(int(_session_data.get("max_b2b", 0))))
	_set_summary_value("clears", "%d/%d/%d/%d" % [
		int(_session_data.get("singles", 0)),
		int(_session_data.get("doubles", 0)),
		int(_session_data.get("triples", 0)),
		int(_session_data.get("tetrises", 0)),
	])
	var ai_summary_score := _ai_summary_score()
	_set_summary_value("ai_score", "%.1f" % ai_summary_score if ai_summary_score >= 0.0 else tr("TXT_NA"))


func _set_summary_value(key: String, value: String) -> void:
	var label := _summary_value_labels.get(key, null) as Label
	if label != null:
		label.text = value


func _session_float(key: String) -> float:
	return float(_session_data.get(key, 0.0))


func _format_duration(seconds: float) -> String:
	var total_sec: int = int(seconds)
	var hours: int = int(total_sec / 3600)
	var mins: int = int((total_sec % 3600) / 60)
	var secs: int = total_sec % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, mins, secs]
	return "%02d:%02d" % [mins, secs]


func _format_number(value: int) -> String:
	var s: String = str(absi(value))
	var result: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	if value < 0:
		result = "-" + result
	return result


func _average_ai_loss() -> float:
	if _ai_details.is_empty():
		return -1.0
	var total_loss: float = 0.0
	var count: int = 0
	for item in _ai_details:
		if item is Dictionary:
			var detail := item as Dictionary
			if detail.has("score_loss") and detail["score_loss"] != null:
				total_loss += maxf(0.0, float(detail["score_loss"]))
				count += 1
	if count <= 0:
		return -1.0
	return total_loss / float(count)


func _ai_summary_score() -> float:
	var avg_loss := _average_ai_loss()
	if avg_loss < 0.0:
		return -1.0
	return clampf(100.0 - avg_loss * 0.1, 0.0, 100.0)


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
		call_deferred("_focus_default_control")
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
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_color_override("font_color", Color(0.88, 0.91, 0.94))
		btn.add_theme_color_override("font_hover_color", Color(0, 0.83, 1))
		btn.pressed.connect(_on_session_selected.bind(fname))
		session_list.add_child(btn)

	session_list_popup.visible = true
	call_deferred("_focus_default_control")


func _focus_default_control() -> void:
	if session_list_popup.visible:
		for child in session_list.get_children():
			if child is Button and not (child as Button).disabled:
				(child as Button).grab_focus()
				return
	if btn_back:
		btn_back.grab_focus()


func _on_session_selected(file_name: String) -> void:
	session_list_popup.visible = false
	_load_session(file_name)
	call_deferred("_focus_current_timeline_row")


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
	_update_session_overview()

	# 尝试加载 AI 分析结果
	_load_ai_scores(file_name)
	_update_session_overview()

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
	_ai_details = []
	_ai_recommendations = []
	var analyzed_name: String = session_file_name.replace(".json", "_analyzed.json")
	var analyzed_path: String = PlayerDataStore.get_sessions_dir().path_join(analyzed_name)
	var needs_analysis: bool = true

	if _try_load_ai_scores_from_path(analyzed_path):
		needs_analysis = false

	if needs_analysis:
		print("[ReplaySystem] Running replay-ai-core analysis for %s" % session_file_name)
		_run_ai_analysis(session_file_name)


func _run_ai_analysis(session_file_name: String) -> void:
	var session_path: String = ProjectSettings.globalize_path(
		PlayerDataStore.get_sessions_dir().path_join(session_file_name)
	)
	var output_path: String = session_path.replace(".json", "_analyzed.json")
	var progress_path: String = output_path + ".progress"

	var analyzer_path: String = _find_replay_ai_analyzer()
	var executable_path: String = analyzer_path
	var args: PackedStringArray = []
	if not analyzer_path.is_empty():
		print("[ReplaySystem] Analyzer path: %s" % analyzer_path)
		args = [session_path, output_path, "--progress-file", progress_path]
	else:
		print("[ReplaySystem] Analyzer executable not found; trying cargo fallback")
		executable_path = "cargo"
		args = _make_replay_ai_cargo_args(session_path, output_path, progress_path)

	if args.is_empty():
		_show_ai_analysis_failed("Analyzer executable and Cargo fallback are unavailable.")
		return

	_prepare_analysis_progress_file(progress_path)
	_analysis_session_file_name = session_file_name
	_analysis_output_path = output_path
	_analysis_progress_path = progress_path
	_analysis_started_msec = Time.get_ticks_msec()
	_analysis_last_worker_current = 0
	_show_analysis_overlay()
	var pid: int = OS.create_process(executable_path, args, false)
	if pid <= 0:
		_hide_analysis_overlay()
		_analysis_session_file_name = ""
		_analysis_output_path = ""
		_analysis_progress_path = ""
		_show_ai_analysis_failed("Failed to start analyzer process: %s" % executable_path)
		return

	_analysis_active = true
	_analysis_pid = pid
	_set_replay_controls_enabled(false)
	set_process(true)


func _find_replay_ai_analyzer() -> String:
	return ReplayAiEnvironment.ensure_analyzer_available()


func _make_replay_ai_cargo_args(session_path: String, output_path: String, progress_path: String) -> PackedStringArray:
	var manifest_path: String = ProjectSettings.globalize_path("res://replay-ai-core/Cargo.toml")
	if not FileAccess.file_exists(manifest_path):
		push_warning("[ReplaySystem] replay-ai-core Cargo.toml is missing: %s" % manifest_path)
		return PackedStringArray()

	return [
		"run",
		"--manifest-path", manifest_path,
		"-p", "replay-analysis",
		"--bin", "analyze_session",
		"--",
		session_path,
		output_path,
		"--progress-file", progress_path
	]


func _try_load_ai_scores_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false

	var data: Dictionary = json.data as Dictionary
	if str(data.get("ai_model_used", "")) != "cold-clear-standard" or not data.has("ai_details"):
		return false

	_ai_scores = data.get("ai_scores", [])
	_ai_details = data.get("ai_details", [])
	_ai_recommendations = data.get("recommendations", [])
	return true


func _prepare_analysis_progress_file(progress_path: String) -> void:
	var file := FileAccess.open(progress_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("0,%d" % _snapshots.size())


func _finish_ai_analysis_process() -> void:
	_analysis_pid = -1
	_analysis_active = false
	set_process(false)
	_set_replay_controls_enabled(true)

	var output_path := _analysis_output_path
	var progress_path := _analysis_progress_path
	_hide_analysis_overlay()

	if _try_load_ai_scores_from_path(output_path):
		print("[ReplaySystem] Replay AI analysis complete: %d steps" % _ai_scores.size())
		_refresh_replay_after_ai_analysis()
	else:
		_show_ai_analysis_failed("Analyzer finished but did not produce a valid analysis JSON.")

	if not progress_path.is_empty() and FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_path)

	_analysis_session_file_name = ""
	_analysis_output_path = ""
	_analysis_progress_path = ""


func _refresh_replay_after_ai_analysis() -> void:
	if _current_step < 0:
		return
	_update_session_overview()
	_render_step(_current_step)
	_update_data_panel(_current_step)
	_build_timeline()
	_highlight_timeline_item(_current_step)
	call_deferred("_focus_current_timeline_row")


func _show_ai_analysis_failed(message: String) -> void:
	push_warning("[ReplaySystem] Replay AI analysis failed: %s" % message)
	ai_score_label.text = tr("TXT_AI_ANALYSIS_FAILED")
	ai_score_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))


func _show_analysis_overlay() -> void:
	_ensure_analysis_overlay()
	_analysis_overlay.visible = true
	_analysis_overlay.move_to_front()
	_update_analysis_overlay_text()
	_update_analysis_progress_overlay()


func _hide_analysis_overlay() -> void:
	if _analysis_overlay != null:
		_analysis_overlay.visible = false


func _ensure_analysis_overlay() -> void:
	if _analysis_overlay != null:
		return

	var overlay := PanelContainer.new()
	overlay.name = "AnalysisOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.visible = false
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.015, 0.016, 0.024, 0.82)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	add_child(overlay)
	_analysis_overlay = overlay

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 156)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.058, 0.09, 0.96)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.0, 0.83, 1.0, 0.55)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	vbox.add_child(status)
	_analysis_status_label = status

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(380, 22)
	bar.min_value = 0
	bar.max_value = maxi(1, _snapshots.size())
	bar.value = 0
	bar.show_percentage = true
	vbox.add_child(bar)
	_analysis_progress_bar = bar

	var detail := Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(0.55, 0.65, 0.82))
	vbox.add_child(detail)
	_analysis_detail_label = detail


func _update_analysis_overlay_text() -> void:
	if _analysis_status_label != null:
		_analysis_status_label.text = tr("TXT_AI_ANALYZING")
	if _analysis_detail_label != null:
		_analysis_detail_label.text = tr("TXT_AI_ANALYSIS_WAIT")


func _update_analysis_progress_overlay() -> void:
	if _analysis_progress_bar == null:
		return

	var total := maxi(1, _snapshots.size())
	var current := 0
	if not _analysis_progress_path.is_empty() and FileAccess.file_exists(_analysis_progress_path):
		var file := FileAccess.open(_analysis_progress_path, FileAccess.READ)
		if file != null:
			var parts := file.get_as_text().strip_edges().split(",")
			if parts.size() >= 2:
				current = maxi(0, int(parts[0]))
				total = maxi(1, int(parts[1]))

	if current > _analysis_last_worker_current:
		_analysis_last_worker_current = current

	var elapsed_msec := Time.get_ticks_msec() - _analysis_started_msec
	if _analysis_last_worker_current == 0 and current == 0 and elapsed_msec > 800:
		var elapsed_sec := float(elapsed_msec) / 1000.0
		current = mini(total - 1, int(float(total) * clampf(elapsed_sec / 16.0, 0.0, 0.90)))

	_analysis_progress_bar.max_value = total
	_analysis_progress_bar.value = clampi(current, 0, total)
	if _analysis_detail_label != null:
		var progress_text := tr("TXT_AI_ANALYSIS_PROGRESS") % [current, total]
		_analysis_detail_label.text = "%s  |  %s" % [progress_text, _format_analysis_elapsed(elapsed_msec)]


func _format_analysis_elapsed(elapsed_msec: int) -> String:
	var total_seconds := maxi(0, int(elapsed_msec / 1000))
	if total_seconds < 60:
		return "%.1fs" % (float(elapsed_msec) / 1000.0)
	return "%dm %02ds" % [total_seconds / 60, total_seconds % 60]


func _set_replay_controls_enabled(enabled: bool) -> void:
	btn_back.disabled = not enabled
	btn_first.disabled = not enabled
	btn_prev.disabled = not enabled
	btn_next.disabled = not enabled
	btn_last.disabled = not enabled
	step_slider.editable = enabled


# ==============================================================================
# 步进导航
# ==============================================================================

func _go_to_step(index: int) -> void:
	if _snapshots.is_empty():
		return
	index = clampi(index, 0, _snapshots.size() - 1)
	if index == _current_step and not _showing_ai_plan:
		return

	_showing_ai_plan = false
	_ai_plan_reveal_count = 0
	_ai_plan_simulated_board.clear()
	_ai_plan_board_history.clear()
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

	# 在高亮方块旁添加 "?" 按钮（仅当有 AI 推荐数据时）
	_draw_ai_plan_button(snap, index)

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
		var detail: Dictionary = _get_ai_detail(index)
		var loss: int = _timeline_score_loss(index)
		# 左下主大数字改为：-loss 或 AI BEST（不再显示复杂度总分）
		var primary_text: String = "-%d" % loss if loss > 0 else "AI BEST"
		ai_score_label.text = primary_text
		ai_score_label.add_theme_color_override("font_color", _ai_detail_color(detail, score_val))
	else:
		ai_score_label.text = tr("TXT_NA")
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


func _get_ai_detail(index: int) -> Dictionary:
	if index >= 0 and index < _ai_details.size() and _ai_details[index] is Dictionary:
		return _ai_details[index] as Dictionary
	return {}


func _ai_detail_color(detail: Dictionary, score_val: float) -> Color:
	if detail.has("score_loss") and detail["score_loss"] != null:
		return _timeline_loss_color(maxi(0, int(detail["score_loss"])))
	return _ai_score_color(score_val)


func _format_best_move(detail: Dictionary) -> String:
	if detail.is_empty() or not detail.has("best") or detail["best"] == null:
		return "best: -"
	var best: Dictionary = detail["best"] as Dictionary
	var placement: Dictionary = best.get("placement", {}) as Dictionary
	var piece: String = str(placement.get("piece", "?"))
	var col: int = int(placement.get("col", 0))
	var row: int = int(placement.get("visible_row", placement.get("row", 0)))
	var rot: int = int(placement.get("rotation", 0))
	var hold_mark: String = "H " if bool(best.get("used_hold", false)) else ""
	var kind: String = str(best.get("placement_kind", ""))
	if kind.is_empty():
		kind = "place"
	return "best: %s%s c%d r%d rot%d %s" % [hold_mark, piece, col, row, rot, kind]


func _timeline_score_loss(index: int) -> int:
	var detail: Dictionary = _get_ai_detail(index)
	if detail.has("score_loss") and detail["score_loss"] != null:
		return maxi(0, int(detail["score_loss"]))
	return 0


func _timeline_loss_color(loss: int) -> Color:
	if loss <= 0:
		return Color(0.0, 1.0, 0.32)
	if loss <= 80:
		return Color(0.18, 1.0, 0.46)
	if loss <= 180:
		return Color(0.42, 0.96, 0.48)
	if loss <= 300:
		return Color(0.70, 0.95, 0.56)
	if loss <= 600:
		return Color(1.0, 0.88, 0.26)
	if loss <= 800:
		return Color(1.0, 0.55, 0.18)
	return Color(1.0, 0.20, 0.18)


func _timeline_row_color(index: int) -> Color:
	if index >= 0 and index < _ai_scores.size():
		return _timeline_loss_color(_timeline_score_loss(index))
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


func _set_timeline_row_style(row: PanelContainer, border_color: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	if selected:
		sb.bg_color = Color(border_color.r, border_color.g, border_color.b, 0.06)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = border_color
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", sb)


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
		timeline_list.add_child(_create_timeline_row(i, snap, piece_name, elapsed_ms))
		continue

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
		btn.add_theme_color_override("font_color", row_color)
		_set_timeline_button_border(btn, row_color, i == _current_step)

		# AI 表现：始终占位显示（AI BEST 或 -loss）
		var ai_text: String = _timeline_ai_text(i)

		# 用时
		var time_text: String = _timeline_time_text(elapsed_ms)

		btn.text = "#%04d  %s  %-6s  %-6s" % [mini(i + 1, 9999), piece_name, ai_text, time_text]
		btn.pressed.connect(_go_to_step.bind(i))
		hbox.add_child(btn)

		var special_text := _timeline_special_clear_text(snap)
		var tag := _create_timeline_tag_label(special_text)
		tag.add_theme_color_override("font_color", _timeline_special_clear_color(special_text))
		hbox.add_child(tag)

		timeline_list.add_child(hbox)


func _highlight_timeline_item(index: int) -> void:
	for i in range(timeline_list.get_child_count()):
		var row: PanelContainer = timeline_list.get_child(i) as PanelContainer
		if row != null:
			_set_timeline_row_style(row, _timeline_row_color(i), i == index)
			continue
		var hbox: HBoxContainer = timeline_list.get_child(i) as HBoxContainer
		if hbox == null or hbox.get_child_count() < 2:
			continue
		var btn: Button = hbox.get_child(hbox.get_child_count() - 2) as Button
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


func _create_timeline_row(index: int, snap: Dictionary, piece_name: String, elapsed_ms: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 26
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.focus_mode = Control.FOCUS_ALL
	row.gui_input.connect(_on_timeline_row_gui_input.bind(index))

	var row_color := _timeline_row_color(index)
	_set_timeline_row_style(row, row_color, index == _current_step)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var cidx: int = PIECE_NAME_COLOR.get(piece_name, 0)
	var indicator := ColorRect.new()
	indicator.custom_minimum_size = Vector2(4, 20)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.color = CELL_COLORS[cidx] if cidx > 0 and cidx < CELL_COLORS.size() else Color(0.3, 0.3, 0.4)
	hbox.add_child(indicator)
	hbox.add_child(_create_timeline_piece_icon(piece_name))

	hbox.add_child(_create_timeline_text_label("#%04d" % mini(index + 1, 9999), TIMELINE_STEP_W, row_color))
	hbox.add_child(_create_timeline_text_label(piece_name, TIMELINE_NAME_W, row_color))
	hbox.add_child(_create_timeline_text_label(_timeline_ai_text(index), TIMELINE_AI_W, row_color))
	hbox.add_child(_create_timeline_text_label(_timeline_time_text(elapsed_ms), TIMELINE_TIME_W, row_color))

	var special_text := _timeline_special_clear_text(snap)
	var tag := _create_timeline_tag_label(special_text)
	tag.add_theme_color_override("font_color", _timeline_special_clear_color(special_text))
	hbox.add_child(tag)

	return row


func _on_timeline_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_go_to_step(index)
			(timeline_list.get_child(index) as Control).grab_focus()
	if event.is_action_pressed("ui_accept"):
		_go_to_step(index)
		get_viewport().set_input_as_handled()


func _focus_current_timeline_row() -> void:
	if session_list_popup.visible:
		return
	if _current_step < 0 or _current_step >= timeline_list.get_child_count():
		if btn_back:
			btn_back.grab_focus()
		return
	var row := timeline_list.get_child(_current_step) as Control
	if row and row.focus_mode != Control.FOCUS_NONE:
		row.grab_focus()


func _create_timeline_text_label(text: String, width: float, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	return label


func _create_timeline_tag_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(TIMELINE_TAG_W, 0)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 10)
	return label


func _timeline_ai_text(index: int) -> String:
	if index >= _ai_scores.size():
		return "-"
	var loss: int = _timeline_score_loss(index)
	if loss <= 0:
		return "BEST"
	return "-%d" % mini(loss, 99999)


func _timeline_time_text(elapsed_ms: int) -> String:
	if elapsed_ms > 9999:
		return "9999+"
	return "%dms" % maxi(0, elapsed_ms)


func _timeline_special_clear_text(snap: Dictionary) -> String:
	var lines := int(snap.get("lines_cleared_this_lock", 0))
	if lines <= 0:
		return ""
	if bool(snap.get("is_t_spin", false)):
		return "T-SPIN"
	if lines >= 4:
		return "TETRIS"
	return ""


func _timeline_special_clear_color(text: String) -> Color:
	match text:
		"T-SPIN":
			return Color(1.0, 0.45, 1.0)
		"TETRIS":
			return Color(0.0, 0.86, 1.0)
		_:
			return Color(0.42, 0.48, 0.58)


# ==============================================================================
# 导航
# ==============================================================================

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if _analysis_active:
		get_viewport().set_input_as_handled()
		return
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


# ==============================================================================
# AI 计划幽灵方块可视化（渐进式引导）
# ==============================================================================

func _get_recommendation(step_index: int) -> Dictionary:
	for rec in _ai_recommendations:
		if rec is Dictionary and int(rec.get("step", -1)) == step_index:
			return rec
	return {}

func _draw_ai_plan_button(snap: Dictionary, step_index: int) -> void:
	var rec: Dictionary = _get_recommendation(step_index)
	if rec.is_empty():
		return
	var piece_name: String = str(snap.get("piece_type", ""))
	if not PIECE_NAME_TYPE.has(piece_name):
		return
	var piece_type: int = int(PIECE_NAME_TYPE[piece_name])
	var rot: int = posmod(int(snap.get("rotation", 0)), 4)
	var center_col: int = int(snap.get("col", 0))
	var center_row_raw: int = int(snap.get("row", 0))
	var center_row: int = center_row_raw - BOARD_ROWS if center_row_raw >= BOARD_ROWS else center_row_raw
	var shape: Array = PieceData.SHAPES[piece_type][rot]
	var min_y: int = 999
	var max_x: int = -999
	for offset in shape:
		var gx: int = center_col + int(offset.x)
		var gy: int = center_row + int(offset.y)
		min_y = mini(min_y, gy)
		max_x = maxi(max_x, gx)
	var btn_size: float = 22.0
	var btn_x: float = (max_x + 1) * CELL_SIZE + 2
	var btn_y: float = min_y * CELL_SIZE - btn_size * 0.5
	var btn := Button.new()
	btn.text = "?"
	btn.position = Vector2(btn_x, btn_y)
	btn.size = Vector2(btn_size, btn_size)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0, 0.83, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.4, 0.95, 1, 1))
	btn.add_theme_constant_override("outline_size", 1)
	btn.add_theme_color_override("font_outline_color", Color(0, 0.2, 0.3, 0.95))
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.06, 0.06, 0.12, 0.9)
	sb_normal.border_width_left = 2
	sb_normal.border_width_top = 2
	sb_normal.border_width_right = 2
	sb_normal.border_width_bottom = 2
	sb_normal.border_color = Color(0, 0.83, 1, 0.7)
	sb_normal.corner_radius_top_left = 11
	sb_normal.corner_radius_top_right = 11
	sb_normal.corner_radius_bottom_left = 11
	sb_normal.corner_radius_bottom_right = 11
	btn.add_theme_stylebox_override("normal", sb_normal)
	var sb_hover := sb_normal.duplicate()
	sb_hover.border_color = Color(0.4, 0.95, 1, 1)
	sb_hover.bg_color = Color(0, 0.2, 0.3, 0.9)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", sb_normal)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_toggle_ai_plan.bind(step_index))
	replay_board.add_child(btn)

func _toggle_ai_plan(step_index: int) -> void:
	if _showing_ai_plan:
		_showing_ai_plan = false
		_ai_plan_reveal_count = 0
		_ai_plan_simulated_board.clear()
		_ai_plan_board_history.clear()
		_render_step(_current_step)
		_update_data_panel(_current_step)
	else:
		_showing_ai_plan = true
		_ai_plan_reveal_count = 1
		_ai_plan_board_history.clear()
		_init_ai_plan_board(step_index)
		_render_ai_plan_progressive(step_index)

func _advance_ai_plan(step_index: int) -> void:
	var rec: Dictionary = _get_recommendation(step_index)
	if rec.is_empty():
		return
	var plan: Dictionary = rec.get("plan", {}) as Dictionary
	var steps: Array = plan.get("steps", [])
	var max_steps: int = mini(steps.size(), 5)
	if _ai_plan_reveal_count >= max_steps:
		return
	# 保存当前棋盘快照以便回退
	var snapshot: Array = []
	for row in _ai_plan_simulated_board:
		snapshot.append(row.duplicate())
	_ai_plan_board_history.append(snapshot)
	_simulate_lock_piece_on_board(steps[_ai_plan_reveal_count - 1])
	_ai_plan_reveal_count += 1
	_render_ai_plan_progressive(step_index)

func _retreat_ai_plan(step_index: int) -> void:
	if _ai_plan_reveal_count <= 1:
		return
	if _ai_plan_board_history.is_empty():
		return
	# 恢复上一步的棋盘快照
	_ai_plan_simulated_board = _ai_plan_board_history.pop_back()
	_ai_plan_reveal_count -= 1
	_render_ai_plan_progressive(step_index)

func _init_ai_plan_board(step_index: int) -> void:
	_ai_plan_simulated_board.clear()
	if step_index > 0:
		var prev_snap: Dictionary = _snapshots[step_index - 1]
		var bd: Array = prev_snap.get("board_state_after_clear", [])
		if bd.is_empty():
			bd = prev_snap.get("board_state", [])
		for row in bd:
			_ai_plan_simulated_board.append(row.duplicate())
	if _ai_plan_simulated_board.is_empty():
		for _r in range(BOARD_ROWS):
			var empty_row: Array = []
			for _c in range(BOARD_COLS):
				empty_row.append(0)
			_ai_plan_simulated_board.append(empty_row)

func _simulate_lock_piece_on_board(plan_step: Dictionary) -> void:
	var placement: Dictionary = plan_step.get("placement", {}) as Dictionary
	if placement.is_empty():
		return
	var piece_name: String = str(placement.get("piece", ""))
	if not CC_SHAPES.has(piece_name):
		return
	var rot: int = posmod(int(placement.get("rotation", 0)), 4)
	var center_col: int = int(placement.get("col", 0))
	var visible_row: int = int(placement.get("visible_row", 0))
	var cidx: int = PIECE_NAME_COLOR.get(piece_name, 1)
	var shape: Array = CC_SHAPES[piece_name][rot]
	for offset in shape:
		var gx: int = center_col + int(offset.x)
		var gy: int = visible_row + int(offset.y)
		if gx >= 0 and gx < BOARD_COLS and gy >= 0 and gy < _ai_plan_simulated_board.size():
			_ai_plan_simulated_board[gy][gx] = cidx
	# 使用 cold-clear 的 lock.cleared_lines 来消行（比自己判断更准确）
	var lock_data: Variant = plan_step.get("lock", null)
	var cleared_lines_cc: Array = []
	if lock_data is Dictionary:
		cleared_lines_cc = lock_data.get("cleared_lines", [])
	if not cleared_lines_cc.is_empty():
		# cold-clear 的 cleared_lines 是 y 坐标（0=底部），转为 visible（0=顶部）
		var rows_to_remove: Array[int] = []
		for cc_y in cleared_lines_cc:
			var vis_row: int = BOARD_ROWS - 1 - int(cc_y)
			if vis_row >= 0 and vis_row < _ai_plan_simulated_board.size():
				rows_to_remove.append(vis_row)
		rows_to_remove.sort()
		rows_to_remove.reverse()
		for r_idx in rows_to_remove:
			if r_idx < _ai_plan_simulated_board.size():
				_ai_plan_simulated_board.remove_at(r_idx)
		for _i in range(rows_to_remove.size()):
			var empty_row: Array = []
			for _c in range(BOARD_COLS):
				empty_row.append(0)
			_ai_plan_simulated_board.insert(0, empty_row)
	else:
		# 没有 lock 数据时回退到自动检测满行
		var new_board: Array = []
		for row in _ai_plan_simulated_board:
			var full: bool = true
			for cell in row:
				if int(cell) == 0:
					full = false
					break
			if not full:
				new_board.append(row)
		var cleared: int = _ai_plan_simulated_board.size() - new_board.size()
		for _i in range(cleared):
			var empty_row: Array = []
			for _c in range(BOARD_COLS):
				empty_row.append(0)
			new_board.insert(0, empty_row)
		_ai_plan_simulated_board = new_board

func _render_ai_plan_progressive(step_index: int) -> void:
	var rec: Dictionary = _get_recommendation(step_index)
	if rec.is_empty():
		return
	var plan: Dictionary = rec.get("plan", {}) as Dictionary
	var steps: Array = plan.get("steps", [])
	var max_steps: int = mini(steps.size(), 5)
	for child in replay_board.get_children():
		child.queue_free()
	for r in range(mini(_ai_plan_simulated_board.size(), BOARD_ROWS)):
		var row: Array = _ai_plan_simulated_board[r]
		for c in range(mini(row.size(), BOARD_COLS)):
			var cell_val: int = int(row[c])
			var rect := ColorRect.new()
			rect.size = Vector2(CELL_SIZE - 1, CELL_SIZE - 1)
			rect.position = Vector2(c * CELL_SIZE, r * CELL_SIZE)
			if cell_val > 0 and cell_val < CELL_COLORS.size():
				var col: Color = CELL_COLORS[cell_val]
				rect.color = Color(col.r * 0.65, col.g * 0.65, col.b * 0.65, 1.0)
			elif cell_val > 0:
				rect.color = Color(0.3, 0.3, 0.3, 1)
			else:
				rect.color = CELL_COLORS[0]
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			replay_board.add_child(rect)
	var grid_color := Color(0.15, 0.15, 0.22, 0.5)
	for r in range(BOARD_ROWS + 1):
		var line := ColorRect.new()
		line.size = Vector2(BOARD_COLS * CELL_SIZE, 1)
		line.position = Vector2(0, r * CELL_SIZE)
		line.color = grid_color
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		replay_board.add_child(line)
	for c in range(BOARD_COLS + 1):
		var line := ColorRect.new()
		line.size = Vector2(1, BOARD_ROWS * CELL_SIZE)
		line.position = Vector2(c * CELL_SIZE, 0)
		line.color = grid_color
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		replay_board.add_child(line)
	var bw: float = BOARD_COLS * CELL_SIZE
	var bh: float = BOARD_ROWS * CELL_SIZE
	var bc := Color(0.8, 0.5, 0, 0.5)
	for edge in [
		[Vector2(-1, -1), Vector2(bw + 2, 2)],
		[Vector2(-1, bh - 1), Vector2(bw + 2, 2)],
		[Vector2(-1, -1), Vector2(2, bh + 2)],
		[Vector2(bw - 1, -1), Vector2(2, bh + 2)],
	]:
		var e := ColorRect.new()
		e.position = edge[0]
		e.size = edge[1]
		e.color = bc
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		replay_board.add_child(e)
	var ghost_max_x: int = -1
	var ghost_min_x: int = BOARD_COLS
	var ghost_min_y: int = BOARD_ROWS
	if _ai_plan_reveal_count > 0 and _ai_plan_reveal_count <= steps.size():
		var cur_plan_step: Dictionary = steps[_ai_plan_reveal_count - 1] as Dictionary
		var ghost_info: Dictionary = _draw_single_ghost_piece(cur_plan_step, _ai_plan_reveal_count)
		ghost_max_x = int(ghost_info.get("max_x", -1))
		ghost_min_x = int(ghost_info.get("min_x", BOARD_COLS))
		ghost_min_y = int(ghost_info.get("min_y", BOARD_ROWS))
	if _ai_plan_reveal_count < max_steps:
		_draw_next_step_button(step_index, ghost_max_x, ghost_min_y)
	if _ai_plan_reveal_count > 1:
		_draw_retreat_button(step_index, ghost_min_x, ghost_min_y)
	_center_board()
	var snap: Dictionary = _snapshots[step_index]
	_draw_hold_piece(snap)
	_draw_next_pieces(snap)

func _draw_single_ghost_piece(plan_step: Dictionary, step_number: int) -> Dictionary:
	var result: Dictionary = {"max_x": -1, "min_x": BOARD_COLS, "min_y": BOARD_ROWS}
	var placement: Dictionary = plan_step.get("placement", {}) as Dictionary
	if placement.is_empty():
		return result
	var piece_name: String = str(placement.get("piece", ""))
	if not CC_SHAPES.has(piece_name):
		return result
	var rot: int = posmod(int(placement.get("rotation", 0)), 4)
	var center_col: int = int(placement.get("col", 0))
	var visible_row: int = int(placement.get("visible_row", 0))
	var cidx: int = PIECE_NAME_COLOR.get(piece_name, 0)
	var piece_col: Color = CELL_COLORS[cidx] if cidx < CELL_COLORS.size() else Color.WHITE
	var shape: Array = CC_SHAPES[piece_name][rot]
	var ghost_cells: Array[Vector2i] = []
	var min_gy: int = 999
	var max_gx: int = -1
	var min_gx: int = BOARD_COLS
	for offset in shape:
		var gx: int = center_col + int(offset.x)
		var gy: int = visible_row + int(offset.y)
		if gx < 0 or gx >= BOARD_COLS or gy < 0 or gy >= BOARD_ROWS:
			continue
		ghost_cells.append(Vector2i(gx, gy))
		min_gy = mini(min_gy, gy)
		max_gx = maxi(max_gx, gx)
		min_gx = mini(min_gx, gx)
	for cell in ghost_cells:
		_draw_ghost_cell(cell.x, cell.y, piece_col)
	if not ghost_cells.is_empty():
		_draw_step_badge(ghost_cells, step_number, piece_col, min_gy)
	result["max_x"] = max_gx
	result["min_x"] = min_gx
	result["min_y"] = min_gy
	return result

func _draw_next_step_button(step_index: int, ghost_max_x: int = -1, ghost_min_y: int = 10) -> void:
	var btn_w: float = 28.0
	var btn_h: float = 24.0
	# 按钮跟随幽灵方块的右上方
	var btn_x: float
	var btn_y: float
	if ghost_max_x >= 0:
		btn_x = (ghost_max_x + 1) * CELL_SIZE + 4
		btn_y = ghost_min_y * CELL_SIZE
	else:
		btn_x = BOARD_COLS * CELL_SIZE * 0.5 - btn_w * 0.5
		btn_y = 4.0
	var btn := Button.new()
	btn.text = "▶"
	btn.position = Vector2(btn_x, btn_y)
	btn.size = Vector2(btn_w, btn_h)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(1, 0.85, 0, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.4, 1))
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.08, 0.06, 0.02, 0.9)
	sb_n.border_width_left = 2
	sb_n.border_width_top = 2
	sb_n.border_width_right = 2
	sb_n.border_width_bottom = 2
	sb_n.border_color = Color(1, 0.7, 0, 0.7)
	sb_n.corner_radius_top_left = 6
	sb_n.corner_radius_top_right = 6
	sb_n.corner_radius_bottom_left = 6
	sb_n.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", sb_n)
	var sb_h := sb_n.duplicate()
	sb_h.border_color = Color(1, 0.9, 0.3, 1)
	sb_h.bg_color = Color(0.15, 0.12, 0.02, 0.95)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.add_theme_stylebox_override("focus", sb_n)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_advance_ai_plan.bind(step_index))
	replay_board.add_child(btn)

func _draw_retreat_button(step_index: int, ghost_min_x: int = BOARD_COLS, ghost_min_y: int = 10) -> void:
	var btn_w: float = 28.0
	var btn_h: float = 24.0
	var btn_x: float
	var btn_y: float
	if ghost_min_x < BOARD_COLS:
		btn_x = ghost_min_x * CELL_SIZE - btn_w - 4
		btn_y = ghost_min_y * CELL_SIZE
	else:
		btn_x = BOARD_COLS * CELL_SIZE * 0.5 - btn_w * 0.5
		btn_y = 4.0
	var btn := Button.new()
	btn.text = "◀"
	btn.position = Vector2(btn_x, btn_y)
	btn.size = Vector2(btn_w, btn_h)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.6, 0.75, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.8, 0.9, 1, 1))
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.04, 0.04, 0.1, 0.9)
	sb_n.border_width_left = 2
	sb_n.border_width_top = 2
	sb_n.border_width_right = 2
	sb_n.border_width_bottom = 2
	sb_n.border_color = Color(0.4, 0.5, 0.8, 0.7)
	sb_n.corner_radius_top_left = 6
	sb_n.corner_radius_top_right = 6
	sb_n.corner_radius_bottom_left = 6
	sb_n.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", sb_n)
	var sb_h := sb_n.duplicate()
	sb_h.border_color = Color(0.6, 0.7, 1, 1)
	sb_h.bg_color = Color(0.08, 0.08, 0.18, 0.95)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.add_theme_stylebox_override("focus", sb_n)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_retreat_ai_plan.bind(step_index))
	replay_board.add_child(btn)

func _draw_ghost_cell(col: int, row: int, piece_col: Color) -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(col * CELL_SIZE, row * CELL_SIZE)
	panel.size = Vector2(CELL_SIZE - 1, CELL_SIZE - 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(piece_col.r, piece_col.g, piece_col.b, 0.08)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(piece_col.r, piece_col.g, piece_col.b, 0.70)
	panel.add_theme_stylebox_override("panel", sb)
	replay_board.add_child(panel)

func _draw_step_badge(cells: Array[Vector2i], number: int, piece_col: Color, min_row: int) -> void:
	var sum_x: float = 0.0
	for cell in cells:
		sum_x += cell.x * CELL_SIZE + CELL_SIZE * 0.5
	var center_x: float = sum_x / cells.size()
	var badge_size: float = 20.0
	var badge_x: float = center_x - badge_size * 0.5
	var badge_y: float = min_row * CELL_SIZE - badge_size - 3.0
	var badge_panel := Panel.new()
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.position = Vector2(badge_x, badge_y)
	badge_panel.size = Vector2(badge_size, badge_size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(piece_col.r, piece_col.g, piece_col.b, 0.85)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	badge_panel.add_theme_stylebox_override("panel", sb)
	replay_board.add_child(badge_panel)
	var lbl := Label.new()
	lbl.text = str(number)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.18, 0.95))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(badge_x, badge_y)
	lbl.size = Vector2(badge_size, badge_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_board.add_child(lbl)
