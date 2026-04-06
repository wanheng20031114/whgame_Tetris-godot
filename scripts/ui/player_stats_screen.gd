class_name PlayerStatsScreen
extends Control

## 玩家数据界面
##
## 所有 UI 节点在 player_stats_screen.tscn 中静态定义。
## 本脚本仅负责：数据加载 → 填充 → 文本国际化刷新。

# ==============================================================================
# 常量
# ==============================================================================

const MAX_HISTORY_DISPLAY: int = 20

const TEXT_DIM_COLOR := Color(0.55, 0.58, 0.70, 1.0)
const VALUE_HIGHLIGHT_COLOR := Color(0.3, 0.85, 1.0, 1.0)
const BODY_FONT_SIZE: int = 18

# ==============================================================================
# 节点引用（使用 %unique_name 绑定 tscn 中的节点）
# ==============================================================================

@onready var btn_back: Button = %BtnBack
@onready var lbl_title: Label = %LblTitle
@onready var lbl_no_data: Label = %LblNoData
@onready var radar_chart: Control = %RadarChart
@onready var history_container: VBoxContainer = %HistoryContainer

# 统计数值标签
@onready var lbl_total_games: Label = %LblTotalGamesVal
@onready var lbl_total_time: Label = %LblTotalTimeVal
@onready var lbl_best_score: Label = %LblBestScoreVal
@onready var lbl_pps: Label = %LblPPSVal
@onready var lbl_apm: Label = %LblAPMVal
@onready var lbl_app: Label = %LblAPPVal
@onready var lbl_kpp: Label = %LblKPPVal

# 需要国际化刷新的静态标签
@onready var stats_title: Label = %StatsTitle
@onready var history_title: Label = %HistoryTitle

# 统计行左侧名称标签（用于翻译刷新）
@onready var lbl_name_total_games: Label = %LblTotalGamesName
@onready var lbl_name_total_time: Label = %LblTotalTimeName
@onready var lbl_name_best_score: Label = %LblBestScoreName
@onready var lbl_name_pps: Label = %LblPPSName
@onready var lbl_name_apm: Label = %LblAPMName
@onready var lbl_name_app: Label = %LblAPPName
@onready var lbl_name_kpp: Label = %LblKPPName


# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	_update_texts()
	_load_and_display_data()


func _notification(what: int) -> void:
	# 仅在节点已 _ready 且仍在场景树中时处理语言切换
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()
		_load_and_display_data()


# ==============================================================================
# 数据加载与展示
# ==============================================================================

func _load_and_display_data() -> void:
	var stats: Dictionary = PlayerDataStore.load_stats()
	var total_games: int = stats.get("total_games", 0)

	# 无数据提示
	lbl_no_data.visible = (total_games == 0)

	# ── 雷达图 ──
	var radar: Dictionary = stats.get("radar_scores", {})
	if total_games == 0:
		radar = {"speed": 0, "attack": 0, "efficiency": 0, "topology": 0, "holes": 0, "vision": 0}
	if radar_chart and radar_chart.has_method("set_data"):
		radar_chart.set_data(radar)

	# ── 总览统计 ──
	lbl_total_games.text = str(total_games)
	var total_time: float = stats.get("total_play_time_seconds", 0.0)
	lbl_total_time.text = _format_duration(total_time)
	lbl_best_score.text = _format_number(stats.get("best_score", 0))

	# ── 核心指标（取最近一场） ──
	var history: Array = stats.get("history", [])
	if history.size() > 0:
		var latest: Dictionary = history[history.size() - 1]
		lbl_pps.text = "%.2f" % latest.get("pps", 0.0)
		lbl_apm.text = "%.1f" % latest.get("apm", 0.0)
		lbl_app.text = "%.2f" % latest.get("app", 0.0)
		lbl_kpp.text = "%.1f" % latest.get("kpp", 0.0)
	else:
		lbl_pps.text = "—"
		lbl_apm.text = "—"
		lbl_app.text = "—"
		lbl_kpp.text = "—"

	# ── 历史记录 ──
	_populate_history(history)


# ==============================================================================
# 历史记录
# ==============================================================================

func _populate_history(history: Array) -> void:
	for child in history_container.get_children():
		child.queue_free()

	if history.is_empty():
		return

	var start_idx: int = maxi(0, history.size() - MAX_HISTORY_DISPLAY)
	for i in range(history.size() - 1, start_idx - 1, -1):
		var entry: Dictionary = history[i]
		var row := _create_history_row(entry)
		history_container.add_child(row)


func _create_history_row(entry: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)

	var lbl_date := Label.new()
	lbl_date.text = entry.get("date", "???")
	lbl_date.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 2)
	lbl_date.add_theme_color_override("font_color", TEXT_DIM_COLOR)
	lbl_date.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(lbl_date)

	var lbl_score2 := Label.new()
	lbl_score2.text = _format_number(entry.get("score", 0))
	lbl_score2.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 2)
	lbl_score2.add_theme_color_override("font_color", VALUE_HIGHLIGHT_COLOR)
	lbl_score2.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(lbl_score2)

	var lbl_lines := Label.new()
	lbl_lines.text = "L:%d" % entry.get("lines", 0)
	lbl_lines.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 2)
	lbl_lines.add_theme_color_override("font_color", TEXT_DIM_COLOR)
	lbl_lines.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(lbl_lines)

	var lbl_pps2 := Label.new()
	lbl_pps2.text = "PPS:%.2f" % entry.get("pps", 0.0)
	lbl_pps2.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 2)
	lbl_pps2.add_theme_color_override("font_color", TEXT_DIM_COLOR)
	lbl_pps2.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(lbl_pps2)

	var lbl_dur := Label.new()
	lbl_dur.text = _format_duration(entry.get("duration_seconds", 0.0))
	lbl_dur.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 2)
	lbl_dur.add_theme_color_override("font_color", TEXT_DIM_COLOR)
	hbox.add_child(lbl_dur)

	return hbox


# ==============================================================================
# 事件回调
# ==============================================================================

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")


# ==============================================================================
# 国际化文本刷新
# ==============================================================================

func _update_texts() -> void:
	btn_back.text = tr("TXT_BACK")
	lbl_title.text = tr("TXT_PLAYER_STATS")
	lbl_no_data.text = tr("TXT_NO_DATA")
	stats_title.text = tr("TXT_PLAYER_STATS")
	history_title.text = tr("TXT_RECENT_HISTORY")

	lbl_name_total_games.text = tr("TXT_TOTAL_GAMES")
	lbl_name_total_time.text = tr("TXT_TOTAL_TIME")
	lbl_name_best_score.text = tr("TXT_BEST_SCORE")
	lbl_name_pps.text = tr("TXT_STAT_PPS")
	lbl_name_apm.text = tr("TXT_STAT_APM")
	lbl_name_app.text = tr("TXT_STAT_APP")
	lbl_name_kpp.text = tr("TXT_STAT_KPP")


# ==============================================================================
# 格式化工具
# ==============================================================================

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
