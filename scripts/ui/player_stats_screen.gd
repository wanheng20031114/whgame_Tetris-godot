class_name PlayerStatsScreen
extends Control

const HISTORY_ROW_SCENE := preload("res://scenes/ui/history_row.tscn")
const MAX_HISTORY_DISPLAY: int = 20
const RADAR_TREND_WINDOW: int = 5
const RADAR_TREND_MIN_GAMES: int = RADAR_TREND_WINDOW * 2
const RADAR_TREND_STABLE_THRESHOLD: float = 5.0
const RADAR_KEYS: Array[String] = ["speed", "attack", "efficiency", "structure", "stability", "vision"]
const RADAR_LABEL_KEYS: Dictionary = {
	"speed": "TXT_RADAR_SPEED",
	"attack": "TXT_RADAR_ATTACK",
	"efficiency": "TXT_RADAR_EFFICIENCY",
	"structure": "TXT_RADAR_STRUCTURE",
	"stability": "TXT_RADAR_STABILITY",
	"vision": "TXT_RADAR_VISION",
}

const BODY_FONT_SIZE: int = 18

@onready var btn_back: Button = %BtnBack
@onready var settings_menu: TextureButton = $SettingsMenu
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
	_style_stats_card()
	_apply_radar_palette()
	UITheme.theme_changed.connect(func(_m):
		_apply_radar_palette()
		_load_and_display_data())
	_update_texts()
	_load_and_display_data()
	call_deferred("_focus_default_control")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()
		_load_and_display_data()


func _unhandled_input(event: InputEvent) -> void:
	if _is_settings_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_mark_input_handled()
		_on_back_pressed()


func _focus_default_control() -> void:
	if btn_back:
		btn_back.grab_focus()


func _is_settings_menu_open() -> bool:
	return settings_menu != null and settings_menu.has_method("is_menu_open") and bool(settings_menu.call("is_menu_open"))


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


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
	if radar_chart and radar_chart.has_method("set_trend_data"):
		var trend: Dictionary = _build_radar_trend(history)
		var trend_deltas: Dictionary = trend.get("deltas", {})
		if trend_deltas.is_empty():
			radar_chart.call("clear_trend_data")
		else:
			radar_chart.call("set_trend_data", trend_deltas, trend.get("tooltips", {}))

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


func _build_radar_trend(history: Array) -> Dictionary:
	if history.size() < RADAR_TREND_MIN_GAMES:
		return {"deltas": {}, "tooltips": {}}

	var comparable_radars: Array[Dictionary] = []
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		var radar: Dictionary = _get_entry_radar_scores(entry)
		if _has_complete_radar(radar):
			comparable_radars.push_front(radar)
		if comparable_radars.size() >= RADAR_TREND_MIN_GAMES:
			break

	if comparable_radars.size() < RADAR_TREND_MIN_GAMES:
		return {"deltas": {}, "tooltips": {}}

	var previous_avg: Dictionary = _average_radar_window(comparable_radars, 0, RADAR_TREND_WINDOW)
	var recent_avg: Dictionary = _average_radar_window(comparable_radars, RADAR_TREND_WINDOW, RADAR_TREND_WINDOW)
	var deltas: Dictionary = {}
	var tooltips: Dictionary = {}

	for key in RADAR_KEYS:
		var delta: float = float(recent_avg.get(key, 0.0)) - float(previous_avg.get(key, 0.0))
		deltas[key] = delta
		tooltips[key] = _build_radar_trend_tooltip(
			key,
			float(recent_avg.get(key, 0.0)),
			float(previous_avg.get(key, 0.0)),
			delta
		)

	return {"deltas": deltas, "tooltips": tooltips}


func _get_entry_radar_scores(entry: Dictionary) -> Dictionary:
	var direct_radar = entry.get("radar_scores", null)
	if direct_radar is Dictionary and _has_complete_radar(direct_radar):
		return direct_radar

	var session_id: String = str(entry.get("session_id", ""))
	var session: Dictionary = _load_session_data(session_id)
	var session_radar = session.get("radar_scores", {})
	if session_radar is Dictionary:
		return session_radar
	return {}


func _has_complete_radar(radar: Dictionary) -> bool:
	for key in RADAR_KEYS:
		if not radar.has(key):
			return false
	return true


func _average_radar_window(radars: Array[Dictionary], start_index: int, count: int) -> Dictionary:
	var result: Dictionary = {}
	for key in RADAR_KEYS:
		var sum: float = 0.0
		for i in range(start_index, start_index + count):
			sum += float(radars[i].get(key, 0.0))
		result[key] = snapped(sum / float(count), 0.1)
	return result


func _build_radar_trend_tooltip(key: String, recent_avg: float, previous_avg: float, delta: float) -> String:
	var label_text: String = tr(str(RADAR_LABEL_KEYS.get(key, key)))
	var abs_delta: float = absf(delta)
	var translation_key: String = "TXT_RADAR_TREND_STABLE"
	if abs_delta > RADAR_TREND_STABLE_THRESHOLD:
		translation_key = "TXT_RADAR_TREND_IMPROVED" if delta > 0.0 else "TXT_RADAR_TREND_DECLINED"
	return tr(translation_key) % [label_text, abs_delta, recent_avg, previous_avg]


func _populate_history(history: Array) -> void:
	for child in history_container.get_children():
		child.queue_free()

	if history.is_empty():
		return

	var start_idx: int = maxi(0, history.size() - MAX_HISTORY_DISPLAY)
	for i in range(history.size() - 1, start_idx - 1, -1):
		var entry: Dictionary = history[i]
		history_container.add_child(_create_history_row(entry))


func _create_history_row(entry: Dictionary) -> Control:
	var card := HISTORY_ROW_SCENE.instantiate()
	(card.get_node("Content/Header/Date") as Label).text = str(entry.get("date", "???"))
	var metrics := card.get_node("Content/Metrics")
	(metrics.get_node("Score") as Label).text = "%s: %s" % [tr("TXT_SCORE"), _format_number(int(entry.get("score", 0)))]
	(metrics.get_node("Lines") as Label).text = "%s: %d" % [tr("TXT_LINES"), int(entry.get("lines", 0))]
	(metrics.get_node("PPS") as Label).text = "PPS: %.2f" % float(entry.get("pps", 0.0))
	(metrics.get_node("PPS") as Label).tooltip_text = tr("TXT_PPS_EXPLAIN")
	(metrics.get_node("Duration") as Label).text = "%s: %s" % [tr("TXT_TIME"), _format_duration(float(entry.get("duration_seconds", 0.0)))]
	var btn_toggle := card.get_node("Content/Header/Toggle") as Button
	btn_toggle.tooltip_text = tr("TXT_RECENT_HISTORY")
	var detail := card.get_node("Content/Detail") as Label
	var state := {"loaded": false}
	btn_toggle.pressed.connect(func() -> void:
		if not state["loaded"]:
			detail.text = _build_session_detail_text(entry)
			state["loaded"] = true
		detail.visible = not detail.visible
		btn_toggle.text = "▴" if detail.visible else "▾"
	)
	return card


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
	if safe_id.validate_filename() != safe_id:
		return {}
	var path: String = PlayerDataStore.get_sessions_dir().path_join("session_%s.json" % safe_id)
	if not FileAccess.file_exists(path):
		return {}
	var loaded := StorageBudget.read_bounded(path, PlayerDataStore.MAX_SESSION_BYTES)
	if loaded.error != OK:
		return {}
	var parsed = JSON.parse_string((loaded.data as PackedByteArray).get_string_from_utf8())
	if not ReplaySchema.valid_session(parsed):
		StorageBudget.report_error("Session contains invalid fields; the original file was retained: " + path)
		return {}
	return parsed


func _on_back_pressed() -> void:
	UITheme.goto_scene("res://scenes/ui/main.tscn")


## 统计卡：每一行包成胶囊数据行（名称左、粗体数值右），分组标题加圆点
func _style_stats_card() -> void:
	var vbox := stats_card.get_node("StatsVBox") as VBoxContainer
	vbox.add_theme_constant_override("separation", 8)
	stats_title.theme_type_variation = &"EyebrowLabel"
	stats_title.add_theme_font_size_override("font_size", 18)
	history_title.theme_type_variation = &"EyebrowLabel"
	history_title.add_theme_font_size_override("font_size", 18)
	for row in vbox.get_children():
		if not (row is HBoxContainer and String(row.name).begins_with("Row")):
			continue
		var idx := row.get_index()
		var pill := PanelContainer.new()
		pill.theme_type_variation = &"RowPanel"
		pill.custom_minimum_size = Vector2(0, 44)
		vbox.add_child(pill)
		vbox.move_child(pill, idx)
		row.reparent(pill, false)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(26, 26)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.draw.connect(func():
			dot.draw_circle(dot.size * 0.5, 13.0, UITheme.color("surface"), true, -1.0, true)
			dot.draw_circle(dot.size * 0.5, 4.5, UITheme.color("accent"), true, -1.0, true))
		UITheme.theme_changed.connect(func(_mode): dot.queue_redraw())
		row.add_child(dot)
		row.move_child(dot, 0)
		(row as HBoxContainer).add_theme_constant_override("separation", 12)
		for lbl in row.get_children():
			if not (lbl is Label):
				continue
			var l := lbl as Label
			if String(l.name).ends_with("Val"):
				l.theme_type_variation = &"ValueLabel"
				l.add_theme_font_size_override("font_size", 18)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			else:
				l.theme_type_variation = &"MutedLabel"
				l.add_theme_font_size_override("font_size", 16)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _apply_radar_palette() -> void:
	var radar := radar_chart as RadarChart
	if radar == null:
		return
	radar.grid_color = Color(UITheme.color("border"), 0.9)
	radar.axis_color = Color(UITheme.color("border"), 0.7)
	radar.fill_color = Color(UITheme.color("accent"), 0.22)
	radar.outline_color = UITheme.color("accent")
	radar.vertex_dot_color = UITheme.color("accent")
	radar.label_color = UITheme.color("text")
	radar.value_label_color = UITheme.color("muted")
	radar.trend_stable_color = UITheme.color("muted")
	radar.label_font_size = 20
	radar.outline_width = 3.0
	radar.queue_redraw()


func _update_texts() -> void:
	btn_back.text = tr("TXT_BACK")
	lbl_title.text = tr("TXT_PLAYER_STATS")
	lbl_no_data.text = tr("TXT_NO_DATA")
	stats_title.text = "•  " + tr("TXT_PLAYER_STATS")
	history_title.text = "•  " + tr("TXT_RECENT_HISTORY")

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
