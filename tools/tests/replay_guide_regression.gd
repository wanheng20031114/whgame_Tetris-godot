extends Node

# Run this scene only through safe_run.py in a marked isolated project copy.
# Fixtures use unique filenames under the default isolated userdata directory;
# Diagnostics keeps its original storage root for its entire lifetime.
var failures: Array[String] = []
var checks := 0
var _session_ids: Array[String] = []
var _boards: Array = []

@onready var stats: PlayerStatsScreen = $Stats
@onready var guide: GuideSystem = $Guide
@onready var replay: ReplaySystem = $Replay
@onready var radar: RadarChart = $Radar

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func _grid(value: int, col: int, row: int) -> Array:
	var result: Array = []
	for y in 20:
		var cells: Array = []
		cells.resize(10)
		cells.fill(0)
		if y == row:
			cells[col] = value
		result.append(cells)
	return result

func _write_fixture(path: String, data: Dictionary) -> void:
	check(StorageBudget.write_atomic(path, JSON.stringify(data).to_utf8_buffer(), 1_000_000, false) == OK, "write unique fixture: " + path.get_file())

func _make_fixtures() -> void:
	var prefix := "2026-10-23T12-00-00_audit_replay_guide_%s_%s_" % [OS.get_process_id(), Time.get_ticks_usec()]
	_boards = [_grid(1, 0, 19), _grid(7, 5, 18)]
	for index in 3:
		var id := prefix + str(index)
		_session_ids.append(id)
		var snapshots: Array = []
		var scores: Array = []
		var details: Array = []
		var recommendations: Array = []
		if index < 2:
			snapshots.append({"piece_index": 0, "piece_type": "I" if index == 0 else "L", "col": 4, "row": 38, "rotation": 0,
				"board_state_after_drop": _boards[index], "board_state_after_clear": _boards[index],
				"next_pieces": ["O", "T", "S", "J", "Z"], "hold_piece": "L", "elapsed_since_last_piece_ms": 700,
				"lines_cleared_this_lock": 0, "damage_this_lock": 0, "combo": 0, "b2b": 0})
			scores.append(100 + index)
			details.append({"score_loss": index})
			recommendations.append({"step": 0, "plan": {"steps": [
				{"placement": {"piece": "I", "col": 4, "visible_row": 19, "rotation": 0}, "lock": {"cleared_lines": []}},
				{"placement": {"piece": "O", "col": 7, "visible_row": 19, "rotation": 0}, "lock": {"cleared_lines": []}}
			]}})
		var session := {"session_id": id, "player_name": "AUDIT_FIXTURE", "game_mode": "marathon", "snapshots": snapshots,
			"pieces_placed": snapshots.size(), "final_score": 1234567, "final_level": 13, "final_lines": 123,
			"duration_seconds": 1234.5, "pps": 1.85, "apm": 43.5, "app": 0.8, "kpp": 2.4,
			"radar_scores": {"speed": 66, "attack": 52, "efficiency": 73, "structure": 57, "stability": 81, "vision": 64}}
		var path := PlayerDataStore.get_sessions_dir().path_join("session_%s.json" % id)
		_write_fixture(path, session)
		_write_fixture(path.replace(".json", "_analyzed.json"), {"storage_protocol": 1, "analysis_revision": 2, "session_id": id,
			"ai_model_used": "cold-clear-standard", "ai_scores": scores, "ai_details": details, "recommendations": recommendations})

func _test_stats() -> void:
	stats.show()
	for locale in ["zh", "en", "ja"]:
		TranslationServer.set_locale(locale)
		for mode in ["dark", "light"]:
			UITheme.set_mode(mode, Vector2(-1, -1), false)
			stats.lbl_player_name.text = "TETRIS_TEST"
			stats.lbl_total_games.text = "123456"
			stats.lbl_best_score.text = "1,234,567"
			stats._populate_history([{"session_id": _session_ids[0], "date": "2026-10-23 12:00", "score": 1234567,
				"lines": 123, "pps": 1.85, "duration_seconds": 1234.5}])
			await _settle()
			var card := stats.history_container.get_child(0)
			var detail := card.get_node("Content/Detail") as Label
			check(not detail.visible, locale + "/" + mode + ": history detail initially collapsed")
			(card.get_node("Content/Header/Toggle") as Button).pressed.emit()
			await _settle()
			check(detail.visible and _session_ids[0] in detail.text, locale + "/" + mode + ": history detail opens with saved data")
			var bounds := (stats.get_node("MainVBox") as Control).get_global_rect()
			check(bounds.position.x >= -0.5 and bounds.end.x <= 1280.5, locale + "/" + mode + ": stats stays inside 1280 px after expanding history")
			check(detail.get_global_rect().end.x <= 1280.5, locale + "/" + mode + ": expanded history text wraps inside viewport")
	stats.hide()

func _test_guide() -> void:
	guide.show()
	TranslationServer.set_locale("en")
	guide._show_chapter(1)
	await _settle()
	var english_title := str(guide.chapters[1].title)
	TranslationServer.set_locale("zh")
	await _settle()
	check(guide.chapters[1].title == tr("TXT_GUIDE_CH2_TITLE") and guide.chapters[1].title != english_title, "chapter data follows language changes")
	check((guide.chapters_list.get_child(1) as Button).text.contains(tr("TXT_GUIDE_CH2_TITLE")), "chapter sidebar follows language changes")
	guide._start_simulation("combo", 1)
	await _settle()
	guide._sim_move(-1, 0)
	guide.sim_attempts = 3
	var runner := guide.scenario_runner
	var board := guide.board_view
	var grid: Array = runner.grid.duplicate(true)
	var piece: Array = [runner.col, runner.row, runner.rot]
	var started := guide.sim_started_msec
	var initial_mode := UITheme.mode
	UITheme.set_mode("light" if initial_mode == "dark" else "dark", Vector2(-1, -1), false)
	await _settle()
	check(guide.in_simulation and guide.scenario_runner == runner and guide.board_view == board, "theme switch preserves simulation and board instances")
	check(guide.sim_attempts == 3 and guide.sim_started_msec == started, "theme switch preserves attempts and elapsed-time origin")
	check(runner.grid == grid and [runner.col, runner.row, runner.rot] == piece, "theme switch preserves simulation board and falling piece")
	TranslationServer.set_locale("ja")
	await _settle()
	check(guide.scenario_runner == runner and guide.sim_attempts == 3 and guide.sim_started_msec == started, "language switch also preserves simulation progress")
	check(guide.objective_label.text == tr("TXT_GUIDE_SIM_COMBO") % maxi(guide.sim_combo, 0), "simulation objective refreshes language")
	guide.hide()

func _descendants(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		count += 1 + _descendants(child)
	return count

func _same_board(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for row in actual.size():
		if actual[row].size() != expected[row].size():
			return false
		for col in actual[row].size():
			if int(actual[row][col]) != int(expected[row][col]):
				return false
	return true

func _test_replay() -> void:
	replay.show()
	replay._load_session("session_%s.json" % _session_ids[0])
	await _settle()
	check(replay._current_step == 0 and _same_board(replay.replay_board._cells, _boards[0]), "first replay renders its initial board")
	replay._load_session("session_%s.json" % _session_ids[1])
	await _settle()
	check(replay._current_step == 0 and _same_board(replay.replay_board._cells, _boards[1]), "switching from step zero renders the new session's step zero")
	check(replay.piece_type_label.text.ends_with(" L"), "switching sessions refreshes initial piece data")
	var normal_count := _descendants(replay.replay_board)
	check(normal_count < 100, "regular replay uses one board surface instead of 200 cell nodes")
	for cycle in 8:
		replay._toggle_ai_plan(0)
		check(replay._showing_ai_plan and replay.replay_board._plan, "AI plan uses the board surface, cycle %d" % cycle)
		check(_descendants(replay.replay_board) < 100, "AI plan overlays remain bounded, cycle %d" % cycle)
		replay._advance_ai_plan(0)
		replay._retreat_ai_plan(0)
		replay._toggle_ai_plan(0)
		await _settle()
		check(not replay._showing_ai_plan and _descendants(replay.replay_board) == normal_count, "returning from plan restores a stable node count, cycle %d" % cycle)
	replay._load_session("session_%s.json" % _session_ids[2])
	await _settle()
	check(replay._current_step == -1 and replay._snapshots.is_empty(), "empty replay clears the current step")
	var occupied := 0
	for row in replay.replay_board._cells:
		for cell in row:
			occupied += int(cell != 0)
	check(occupied == 0 and replay.board_overlays.get_child_count() == 0, "empty replay clears prior board and overlays")
	check(not replay.replay_previews.visible and replay.replay_hold.piece_type < 0, "empty replay clears hold and hides preview columns")
	for slot: PiecePreview in replay.replay_next.get_children():
		check(slot.piece_type < 0, "empty replay clears queued piece")
	check(replay.step_label.text == tr("TXT_STEP_FORMAT") % [0, 0], "empty replay displays zero of zero steps")
	check(not replay._analysis_active, "cached analysis fixtures never start a background analyzer")
	replay.hide()

func _test_radar() -> void:
	radar.show()
	radar.animation_duration = 0.6
	var zero: Dictionary = {}
	var animated: Dictionary = {}
	var immediate: Dictionary = {}
	for key in RadarChart.DIMENSION_KEYS:
		zero[key] = 0.0
		animated[key] = 100.0
		immediate[key] = 23.0
	radar.set_data_immediate(zero)
	radar.set_data(animated, true)
	await get_tree().create_timer(0.05).timeout
	radar.set_data_immediate(immediate)
	check(radar.get_data() == immediate, "radar immediate update applies immediately")
	for frame in 8:
		await get_tree().create_timer(0.025).timeout
		check(radar.get_data() == immediate, "old radar tween cannot overwrite immediate values, sample %d" % frame)
	check(not radar._animating, "radar immediate update ends animation state")
	radar.hide()

func _test_analyzer_revision() -> void:
	# Exercise the real bundled executable and the normal loader/commit path.
	# A structurally valid old cache must be replaced by revision 2 output.
	var source_path := PlayerDataStore.get_sessions_dir().path_join("session_%s.json" % _session_ids[0])
	var loaded := StorageBudget.read_bounded(source_path, 1_000_000)
	var session: Dictionary = JSON.parse_string(loaded.data.get_string_from_utf8())
	session.session_id = str(session.session_id) + "_actual"
	var file_name := "session_%s.json" % session.session_id
	var path := PlayerDataStore.get_sessions_dir().path_join(file_name)
	var analyzed_path := path.replace(".json", "_analyzed.json")
	_write_fixture(path, session)
	_write_fixture(analyzed_path, {"storage_protocol": 1, "analysis_revision": 1, "session_id": session.session_id,
		"ai_model_used": "cold-clear-standard", "ai_scores": [-999], "ai_details": [{}], "recommendations": [null]})
	replay._load_session(file_name)
	check(replay._analysis_active, "old analysis revision starts recomputation")
	var deadline := Time.get_ticks_msec() + 10_000
	while replay._analysis_active and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	check(not replay._analysis_active, "actual analyzer finishes inside the regression deadline")
	if replay._analysis_active:
		replay._cancel_ai_analysis()
		return
	var result := StorageBudget.read_bounded(analyzed_path, 1_000_000)
	var parsed: Dictionary = JSON.parse_string(result.data.get_string_from_utf8())
	check(int(parsed.get("analysis_revision", 0)) == 2, "actual analyzer commits revision 2 output")
	check(replay._try_load_ai_scores_from_path(analyzed_path), "actual analyzer result passes production loader checks")
	check(replay._analysis_reservation.is_empty(), "successful analysis releases its output reservation")

func _run() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1" or not FileAccess.file_exists("res://.safe-run-isolated.json"):
		print("replay_guide_regression requires the isolated safe runner")
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(1280, 720)
	var original_locale := TranslationServer.get_locale()
	var original_mode := UITheme.mode
	_make_fixtures()
	await _test_stats()
	await _test_guide()
	await _test_replay()
	await _test_radar()
	await _test_analyzer_revision()
	TranslationServer.set_locale(original_locale)
	UITheme.set_mode(original_mode, Vector2(-1, -1), false)
	print(JSON.stringify({"test": "replay_guide_regression", "checks": checks, "failures": failures, "ok": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)
