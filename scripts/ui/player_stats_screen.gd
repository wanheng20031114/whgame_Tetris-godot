class_name PlayerStatsScreen
extends Control

const MAX_HISTORY_DISPLAY: int = 20

const TEXT_DIM_COLOR := Color(0.55, 0.58, 0.70, 1.0)
const VALUE_HIGHLIGHT_COLOR := Color(0.3, 0.85, 1.0, 1.0)
const BODY_FONT_SIZE: int = 18

@onready var btn_back: Button = %BtnBack
@onready var lbl_title: Label = %LblTitle
@onready var lbl_no_data: Label = %LblNoData
@onready var radar_chart: Control = %RadarChart
@onready var stats_card: PanelContainer = %StatsCard
@onready var history_card: PanelContainer = %HistoryCard
@onready var history_container: VBoxContainer = history_card.get_node("HistoryVBox/HistoryContainer") as VBoxContainer

@onready var stats_title: Label = stats_card.get_node("StatsVBox/StatsTitle") as Label
@onready var history_title: Label = history_card.get_node("HistoryVBox/HistoryTitle") as Label

@onready var lbl_name_player: Label = stats_card.get_node("StatsVBox/RowPlayerName/LblPlayerNameName") as Label
@onready var lbl_player_name: Label = stats_card.get_node("StatsVBox/RowPlayerName/LblPlayerNameVal") as Label

@onready var lbl_name_total_games: Label = stats_card.get_node("StatsVBox/RowTotalGames/LblTotalGamesName") as Label
@onready var lbl_total_games: Label = stats_card.get_node("StatsVBox/RowTotalGames/LblTotalGamesVal") as Label
@onready var lbl_name_total_time: Label = stats_card.get_node("StatsVBox/RowTotalTime/LblTotalTimeName") as Label
@onready var lbl_total_time: Label = stats_card.get_node("StatsVBox/RowTotalTime/LblTotalTimeVal") as Label
@onready var lbl_name_total_lines: Label = stats_card.get_node("StatsVBox/RowTotalLines/LblTotalLinesName") as Label
@onready var lbl_total_lines: Label = stats_card.get_node("StatsVBox/RowTotalLines/LblTotalLinesVal") as Label
@onready var lbl_name_total_pieces: Label = stats_card.get_node("StatsVBox/RowTotalPieces/LblTotalPiecesName") as Label
@onready var lbl_total_pieces: Label = stats_card.get_node("StatsVBox/RowTotalPieces/LblTotalPiecesVal") as Label

@onready var lbl_name_best_score: Label = stats_card.get_node("StatsVBox/RowBestScore/LblBestScoreName") as Label
@onready var lbl_best_score: Label = stats_card.get_node("StatsVBox/RowBestScore/LblBestScoreVal") as Label
@onready var lbl_name_best_lines: Label = stats_card.get_node("StatsVBox/RowBestLines/LblBestLinesName") as Label
@onready var lbl_best_lines: Label = stats_card.get_node("StatsVBox/RowBestLines/LblBestLinesVal") as Label
@onready var lbl_name_best_pps: Label = stats_card.get_node("StatsVBox/RowBestPPS/LblBestPPSName") as Label
@onready var lbl_best_pps: Label = stats_card.get_node("StatsVBox/RowBestPPS/LblBestPPSVal") as Label
@onready var lbl_name_best_apm: Label = stats_card.get_node("StatsVBox/RowBestAPM/LblBestAPMName") as Label
@onready var lbl_best_apm: Label = stats_card.get_node("StatsVBox/RowBestAPM/LblBestAPMVal") as Label

@onready var lbl_name_pps: Label = stats_card.get_node("StatsVBox/RowPPS/LblPPSName") as Label
@onready var lbl_pps: Label = stats_card.get_node("StatsVBox/RowPPS/LblPPSVal") as Label
@onready var lbl_name_apm: Label = stats_card.get_node("StatsVBox/RowAPM/LblAPMName") as Label
@onready var lbl_apm: Label = stats_card.get_node("StatsVBox/RowAPM/LblAPMVal") as Label
@onready var lbl_name_app: Label = stats_card.get_node("StatsVBox/RowAPP/LblAPPName") as Label
@onready var lbl_app: Label = stats_card.get_node("StatsVBox/RowAPP/LblAPPVal") as Label
@onready var lbl_name_kpp: Label = stats_card.get_node("StatsVBox/RowKPP/LblKPPName") as Label
@onready var lbl_kpp: Label = stats_card.get_node("StatsVBox/RowKPP/LblKPPVal") as Label
@onready var lbl_name_avg_score: Label = stats_card.get_node("StatsVBox/RowAvgScore/LblAvgScoreName") as Label
@onready var lbl_avg_score: Label = stats_card.get_node("StatsVBox/RowAvgScore/LblAvgScoreVal") as Label


func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	_update_texts()
	_load_and_display_data()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()
		_load_and_display_data()


func _load_and_display_data() -> void:
	var stats: Dictionary = PlayerDataStore.load_stats()
	var total_games: int = int(stats.get("total_games", 0))
	var history: Array = stats.get("history", [])

	lbl_no_data.visible = (total_games == 0)

	var radar: Dictionary = stats.get("radar_scores", {})
	if total_games == 0:
		radar = {"speed": 0, "attack": 0, "efficiency": 0, "structure": 0, "stability": 0, "vision": 0}
	if radar_chart and radar_chart.has_method("set_data"):
		radar_chart.set_data(radar)

	lbl_player_name.text = str(stats.get("player_name", "-"))
	lbl_total_games.text = str(total_games)
	lbl_total_time.text = _format_duration(float(stats.get("total_play_time_seconds", 0.0)))
	lbl_total_lines.text = _format_number(int(stats.get("total_lines_cleared", 0)))
	lbl_total_pieces.text = _format_number(int(stats.get("total_pieces_placed", 0)))

	lbl_best_score.text = _format_number(int(stats.get("best_score", 0)))
	lbl_best_lines.text = _format_number(int(stats.get("best_lines", 0)))
	lbl_best_pps.text = "%.2f" % float(stats.get("best_pps", 0.0))
	lbl_best_apm.text = "%.1f" % float(stats.get("best_apm", 0.0))

	if history.size() > 0:
		var score_sum: float = 0.0
		var pps_sum: float = 0.0
		var apm_sum: float = 0.0
		var app_sum: float = 0.0
		var kpp_sum: float = 0.0
		for item in history:
			var entry: Dictionary = item
			score_sum += float(entry.get("score", 0.0))
			pps_sum += float(entry.get("pps", 0.0))
			apm_sum += float(entry.get("apm", 0.0))
			app_sum += float(entry.get("app", 0.0))
			kpp_sum += float(entry.get("kpp", 0.0))
		var count: float = float(history.size())
		lbl_avg_score.text = _format_number(int(round(score_sum / count)))
		lbl_pps.text = "%.2f" % (pps_sum / count)
		lbl_apm.text = "%.1f" % (apm_sum / count)
		lbl_app.text = "%.2f" % (app_sum / count)
		lbl_kpp.text = "%.2f" % (kpp_sum / count)
	else:
		lbl_avg_score.text = "0"
		lbl_pps.text = tr("TXT_NA")
		lbl_apm.text = tr("TXT_NA")
		lbl_app.text = tr("TXT_NA")
		lbl_kpp.text = tr("TXT_NA")

	_populate_history(history)


func _populate_history(history: Array) -> void:
	for child in history_container.get_children():
		child.queue_free()

	if history.is_empty():
		return

	var start_idx: int = maxi(0, history.size() - MAX_HISTORY_DISPLAY)
	for i in range(history.size() - 1, start_idx - 1, -1):
		var entry: Dictionary = history[i]
		history_container.add_child(_create_history_row(entry))


func _create_history_row(entry: Dictionary) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	row.add_child(header)

	var lbl_date := Label.new()
	lbl_date.text = str(entry.get("date", "???"))
	lbl_date.custom_minimum_size = Vector2(95, 0)
	_apply_row_label_style(lbl_date, false)
	header.add_child(lbl_date)

	var lbl_score := Label.new()
	lbl_score.text = "%s: %s" % [tr("TXT_SCORE"), _format_number(int(entry.get("score", 0)))]
	lbl_score.custom_minimum_size = Vector2(150, 0)
	_apply_row_label_style(lbl_score, true)
	header.add_child(lbl_score)

	var lbl_lines := Label.new()
	lbl_lines.text = "%s: %d" % [tr("TXT_LINES"), int(entry.get("lines", 0))]
	lbl_lines.custom_minimum_size = Vector2(90, 0)
	_apply_row_label_style(lbl_lines, false)
	header.add_child(lbl_lines)

	var lbl_pps2 := Label.new()
	lbl_pps2.text = "%s: %.2f" % [tr("TXT_PPS_EXPLAIN"), float(entry.get("pps", 0.0))]
	lbl_pps2.custom_minimum_size = Vector2(95, 0)
	_apply_row_label_style(lbl_pps2, false)
	header.add_child(lbl_pps2)

	var lbl_duration := Label.new()
	lbl_duration.text = "%s: %s" % [tr("TXT_TIME"), _format_duration(float(entry.get("duration_seconds", 0.0)))]
	lbl_duration.custom_minimum_size = Vector2(90, 0)
	_apply_row_label_style(lbl_duration, false)
	header.add_child(lbl_duration)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var btn_toggle := Button.new()
	btn_toggle.text = "v"
	btn_toggle.custom_minimum_size = Vector2(28, 24)
	header.add_child(btn_toggle)

	var detail := Label.new()
	detail.visible = false
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 3)
	detail.add_theme_color_override("font_color", TEXT_DIM_COLOR)
	row.add_child(detail)

	var state := {"loaded": false}
	btn_toggle.pressed.connect(func() -> void:
		if not state["loaded"]:
			detail.text = _build_session_detail_text(entry)
			state["loaded"] = true
		detail.visible = not detail.visible
		btn_toggle.text = "^" if detail.visible else "v"
	)

	return row


func _apply_row_label_style(label: Label, highlight: bool) -> void:
	label.add_theme_font_size_override("font_size", BODY_FONT_SIZE - 2)
	label.add_theme_color_override("font_color", VALUE_HIGHLIGHT_COLOR if highlight else TEXT_DIM_COLOR)


func _build_session_detail_text(entry: Dictionary) -> String:
	var session_id: String = str(entry.get("session_id", ""))
	var session: Dictionary = _load_session_data(session_id)
	if session.is_empty():
		return "%s: %s | %s." % [tr("TXT_SESSION"), session_id, tr("TXT_NO_DETAIL_SNAPSHOT")]

	var lines: PackedStringArray = []
	lines.append("%s: %s" % [tr("TXT_SESSION"), session_id])
	lines.append("%s: %s | %s: %d | %s: %d | %s: %s" % [
		tr("TXT_SCORE"),
		_format_number(int(session.get("final_score", entry.get("score", 0)))),
		tr("TXT_LEVEL"),
		int(session.get("final_level", entry.get("level", 1))),
		tr("TXT_LINES"),
		int(session.get("final_lines", entry.get("lines", 0))),
		tr("TXT_DURATION"),
		_format_duration(float(session.get("duration_seconds", entry.get("duration_seconds", 0.0))))
	])
	lines.append("%s: %.2f | %s: %.1f | %s: %.2f | %s: %.2f" % [
		tr("TXT_PPS_EXPLAIN"),
		float(session.get("pps", entry.get("pps", 0.0))),
		tr("TXT_APM_EXPLAIN"),
		float(session.get("apm", entry.get("apm", 0.0))),
		tr("TXT_APP_EXPLAIN"),
		float(session.get("app", entry.get("app", 0.0))),
		tr("TXT_KPP_EXPLAIN"),
		float(session.get("kpp", entry.get("kpp", 0.0)))
	])
	var radar: Dictionary = session.get("radar_scores", {})
	lines.append("%s: %.1f | %s: %.1f | %s: %.1f" % [
		tr("TXT_RADAR_SPEED"),
		float(radar.get("speed", 0.0)),
		tr("TXT_RADAR_ATTACK"),
		float(radar.get("attack", 0.0)),
		tr("TXT_RADAR_EFFICIENCY"),
		float(radar.get("efficiency", 0.0))
	])
	lines.append("%s: %.1f | %s: %.1f | %s: %.1f" % [
		tr("TXT_RADAR_STRUCTURE"),
		float(radar.get("structure", entry.get("structure", 0.0))),
		tr("TXT_RADAR_STABILITY"),
		float(radar.get("stability", entry.get("stability", 0.0))),
		tr("TXT_RADAR_VISION"),
		float(radar.get("vision", 0.0))
	])
	lines.append("%s: %d | %s: %d | %s: %d" % [
		tr("TXT_PIECES"),
		int(session.get("pieces_placed", entry.get("pieces_placed", 0))),
		tr("TXT_KEYS"),
		int(session.get("total_key_presses", 0)),
		tr("TXT_DAMAGE"),
		int(session.get("total_damage", 0))
	])
	lines.append("%s: %d/%d/%d/%d" % [
		tr("TXT_CLEAR_BREAKDOWN"),
		int(session.get("singles", 0)),
		int(session.get("doubles", 0)),
		int(session.get("triples", 0)),
		int(session.get("tetrises", 0))
	])
	lines.append("%s: %d | %s: %d | %s: %d | %s: %d" % [
		tr("TXT_TSPIN_CLEARS"),
		int(session.get("t_spin_clears", 0)),
		tr("TXT_SPIN_CLEARS"),
		int(session.get("spin_clears", 0)),
		tr("TXT_MAX_COMBO"),
		int(session.get("max_combo", 0)),
		tr("TXT_MAX_B2B"),
		int(session.get("max_b2b", 0))
	])
	lines.append("%s: %s" % [tr("TXT_START"), str(session.get("start_time", "-"))])
	lines.append("%s: %s | %s: %d | %s: %d" % [
		tr("TXT_END"),
		str(session.get("end_time", "-")),
		tr("TXT_SNAPSHOTS"),
		(session.get("snapshots", []) as Array).size(),
		tr("TXT_DISCARDED"),
		int(session.get("discarded_snapshots", 0))
	])
	return "\n".join(lines)


func _load_session_data(session_id: String) -> Dictionary:
	if session_id.is_empty():
		return {}
	var safe_id: String = session_id.replace(":", "-")
	var path: String = PlayerDataStore.get_sessions_dir().path_join("session_%s.json" % safe_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")


func _update_texts() -> void:
	btn_back.text = tr("TXT_BACK")
	lbl_title.text = tr("TXT_PLAYER_STATS")
	lbl_no_data.text = tr("TXT_NO_DATA")
	stats_title.text = tr("TXT_PLAYER_STATS")
	history_title.text = tr("TXT_RECENT_HISTORY")

	lbl_name_player.text = tr("TXT_PLAYER")
	lbl_name_total_games.text = tr("TXT_TOTAL_GAMES")
	lbl_name_total_time.text = tr("TXT_TOTAL_TIME")
	lbl_name_total_lines.text = tr("TXT_TOTAL_LINES")
	lbl_name_total_pieces.text = tr("TXT_TOTAL_PIECES")

	lbl_name_best_score.text = tr("TXT_BEST_SCORE")
	lbl_name_best_lines.text = tr("TXT_BEST_LINES")
	lbl_name_best_pps.text = tr("TXT_BEST_PPS")
	lbl_name_best_apm.text = tr("TXT_BEST_APM")

	lbl_name_pps.text = tr("TXT_AVG_PPS")
	lbl_name_apm.text = tr("TXT_AVG_APM")
	lbl_name_app.text = tr("TXT_AVG_APP")
	lbl_name_kpp.text = tr("TXT_AVG_KPP")
	lbl_name_avg_score.text = tr("TXT_AVG_SCORE")


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
