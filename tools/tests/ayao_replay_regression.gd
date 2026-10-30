extends Node

## Run only in a marked project copy through tools/safe_run.py.
## Every replay uses an isolated cached analysis; no analyzer or AI API is called.
var _checks := 0
var _failures: Array[String] = []
var _session_files: Array[String] = []
var _replay: ReplaySystem

func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1" or not FileAccess.file_exists("res://.safe-run-isolated.json"):
		print("ayao_replay_regression requires the isolated safe runner")
		get_tree().quit(2)
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		print("FAIL " + description)

func _settle() -> void:
	for frame in 4:
		await get_tree().process_frame

func _grid(column: int = -1, top_row: int = 19, hole_row: int = -1) -> Array:
	var result: Array = []
	for row in 20:
		var cells: Array = []
		cells.resize(10)
		cells.fill(0)
		if column >= 0 and row >= top_row and row != hole_row:
			cells[column] = 3
		result.append(cells)
	return result

func _snapshot(index: int, piece: String, board: Array, lines: int = 0, damage: int = 0) -> Dictionary:
	return {
		"piece_index": index, "piece_type": piece, "col": 4, "row": 38, "rotation": 0,
		"board_state_after_drop": board, "board_state_after_clear": board,
		"next_pieces": ["O", "T", "S", "J", "Z"], "hold_piece": "L",
		"elapsed_since_last_piece_ms": 750 + index * 250,
		"lines_cleared_this_lock": lines, "damage_this_lock": damage, "combo": 0, "b2b": 0
	}

func _recommendation(index: int) -> Dictionary:
	return {"step": index, "plan": {"steps": [
		{"placement": {"piece": "I", "col": 4, "visible_row": 19, "rotation": 0}, "lock": {"cleared_lines": []}},
		{"placement": {"piece": "O", "col": 7, "visible_row": 19, "rotation": 0}, "lock": {"cleared_lines": []}}
	]}}

func _write_fixture(path: String, data: Dictionary) -> void:
	_check(StorageBudget.write_atomic(path, JSON.stringify(data).to_utf8_buffer(), 1_000_000, false) == OK,
		"write isolated fixture " + path.get_file())

func _make_fixtures() -> void:
	var prefix := "2026-10-23T12-00-00_ayao_%s_%s_" % [OS.get_process_id(), Time.get_ticks_usec()]
	for fixture_index in 3:
		var id := prefix + str(fixture_index)
		var snapshots: Array = []
		var scores: Array = []
		var details: Array = []
		var recommendations: Array = []
		if fixture_index == 0:
			snapshots = [_snapshot(0, "T", _grid(3)), _snapshot(1, "I", _grid(), 4, 4),
				_snapshot(2, "L", _grid(5, 3, 18))]
			scores = [0, 250, -450]
			details = [{"quality": "unknown", "score_loss": 0}, {"quality": "best", "score_loss": 0},
				{"quality": "mistake", "score_loss": 700}]
			recommendations = [null, _recommendation(1), _recommendation(2)]
		elif fixture_index == 1:
			snapshots = [_snapshot(0, "O", _grid(8, 18), 1, 0)]
			scores = [120]
			details = [{"quality": "good", "score_loss": 60}]
			recommendations = [null]
		var session := {"session_id": id, "player_name": "AYAO_FIXTURE", "game_mode": "marathon",
			"snapshots": snapshots, "pieces_placed": snapshots.size(), "final_score": 2400,
			"final_level": 1, "final_lines": 4, "duration_seconds": 9.5, "pps": 1.2,
			"apm": 24.0, "app": 0.5, "kpp": 2.0}
		var file_name := "session_%s.json" % id
		_session_files.append(file_name)
		var path := PlayerDataStore.get_sessions_dir().path_join(file_name)
		_write_fixture(path, session)
		_write_fixture(path.replace(".json", "_analyzed.json"), {"storage_protocol": 1, "analysis_revision": 2,
			"session_id": id, "ai_model_used": "cold-clear-standard", "ai_scores": scores,
			"ai_details": details, "recommendations": recommendations})

func _check_current_review(index: int, description: String) -> void:
	var assistant := _replay.assistant_panel
	_check(_replay._current_step == index and assistant._current_step == index, description + ": step agrees")
	var previous: Dictionary = _replay._snapshots[index - 1] if index > 0 else {}
	var expected := AyaoCoach.analyze_step(_replay._snapshots[index], previous,
		_replay._ai_details[index], _replay._get_recommendation(index))
	_check(assistant._review == expected, description + ": review uses current player snapshot and previous board")
	_check(not assistant.body_label.text.strip_edges().is_empty(), description + ": a short analysis is shown")
	_check(not assistant.advice_label.text.strip_edges().is_empty(), description + ": advice or encouragement is shown")

func _test_navigation() -> void:
	_replay._on_session_selected(_session_files[0])
	await _settle()
	_check_current_review(0, "initial unknown step")
	_check(not _replay.assistant_panel._review["facts"].has("ai_score_loss"),
		"unknown analysis does not invent an AI score loss")
	_check(_replay.assistant_panel._review["body_key"] != "TXT_AYAO_CLOSE_TO_BEST",
		"unknown analysis does not claim an optimal placement")
	_check(not _replay._analysis_active, "cached fixtures do not spawn the analyzer")
	_check(_replay.assistant_panel.plan_button.disabled or not _replay.assistant_panel.plan_button.visible,
		"a step without a recommendation cannot open a plan")
	_replay.btn_next.pressed.emit()
	await _settle()
	_check_current_review(1, "next button")
	_check(not _replay.assistant_panel.plan_button.disabled and _replay.assistant_panel.plan_button.visible,
		"a step with a recommendation enables plan preview")
	_replay.step_slider.value = 2
	await _settle()
	_check_current_review(2, "slider")
	_replay.btn_prev.pressed.emit()
	await _settle()
	_check_current_review(1, "previous button")
	_replay.btn_first.pressed.emit()
	await _settle()
	_check_current_review(0, "first button")
	_replay.btn_last.pressed.emit()
	await _settle()
	_check_current_review(2, "last button")
	var review: Dictionary = _replay.assistant_panel._review.duplicate(true)
	var body: String = _replay.assistant_panel.body_label.text
	_replay._go_to_step(2)
	await _settle()
	_check(_replay.assistant_panel._review == review and _replay.assistant_panel.body_label.text == body,
		"selecting the same step does not change its review")
	_replay._go_to_step(100)
	_check_current_review(2, "past-end navigation remains at last step")
	_replay._go_to_step(-100)
	_check_current_review(0, "before-start navigation remains at first step")

func _test_plan_preview() -> void:
	_replay._go_to_step(1)
	await _settle()
	var assistant := _replay.assistant_panel
	var review: Dictionary = assistant._review.duplicate(true)
	var text_before: String = assistant.body_label.text
	assistant.plan_button.pressed.emit()
	await _settle()
	_check(_replay._showing_ai_plan, "assistant opens the existing AI plan")
	_check(assistant._current_step == 1 and assistant._review == review and assistant.body_label.text == text_before,
		"plan preview keeps the review of the actual player step")
	_replay._advance_ai_plan(1)
	await _settle()
	_check(_replay._ai_plan_reveal_count == 2 and assistant._current_step == 1 and assistant._review == review,
		"revealing a future plan placement does not review it as a player move")
	_replay._retreat_ai_plan(1)
	await _settle()
	_check(assistant._review == review, "retreating the plan preserves player feedback")
	assistant.plan_button.pressed.emit()
	await _settle()
	_check(not _replay._showing_ai_plan, "assistant returns from plan to player placement")
	_check(not assistant._plan_preview, "returning clears the assistant preview state")
	_check_current_review(1, "return from plan")
	assistant.plan_button.pressed.emit()
	_replay.btn_next.pressed.emit()
	await _settle()
	_check(not _replay._showing_ai_plan, "stepping away exits preview")
	_check_current_review(2, "navigation from a plan")

func _test_session_and_analysis_refresh() -> void:
	_replay._on_session_selected(_session_files[1])
	await _settle()
	_check_current_review(0, "different session at step zero")
	var first_review: Dictionary = _replay.assistant_panel._review.duplicate(true)
	_replay._ai_details[0] = {"quality": "mistake", "score_loss": 950}
	_replay._refresh_replay_after_ai_analysis()
	await _settle()
	_check_current_review(0, "analysis completion at the same step")
	_check(_replay.assistant_panel._review != first_review, "completed analysis replaces the stale current review")
	_replay._on_session_selected(_session_files[2])
	await _settle()
	_check(_replay._current_step == -1 and _replay.assistant_panel._current_step == -1,
		"empty replay clears the selected assistant step")
	_check(_replay.assistant_panel._review.is_empty(), "empty replay clears prior session feedback")
	_check(not _replay.assistant_panel._plan_preview, "empty replay clears prior preview state")
	_check(_replay.assistant_panel.plan_button.disabled or not _replay.assistant_panel.plan_button.visible,
		"empty replay cannot open a stale plan")
	for locale in ["zh", "en", "ja"]:
		TranslationServer.set_locale(locale)
		await _settle()
		_check(_replay._summary_value_labels["ai_score"].text == tr("TXT_NA"),
			locale + ": empty replay summary refreshes its unknown-score label")
	_replay._on_session_selected(_session_files[0])
	await _settle()
	_check_current_review(0, "loading a populated replay after an empty one")

func _test_collapse_and_presentation() -> void:
	var assistant := _replay.assistant_panel
	var board_container := _replay.get_node("%BoardContainer") as Control
	assistant.toggle_button.pressed.emit()
	await _settle()
	_check(assistant._collapsed and not assistant.body_label.is_visible_in_tree(), "collapse hides review body")
	_replay.btn_next.pressed.emit()
	await _settle()
	_check(assistant._collapsed and assistant._current_step == 1, "collapsed assistant still tracks selected step")
	assistant.toggle_button.pressed.emit()
	await _settle()
	_check(not assistant._collapsed and assistant.body_label.is_visible_in_tree(), "expand restores updated review")
	var chinese_text := ""
	var english_text := ""
	for locale in ["zh", "en", "ja"]:
		TranslationServer.set_locale(locale)
		await _settle()
		_check_current_review(1, "translation " + locale)
		var unknown_score: Label = _replay.timeline_list.get_child(0).get_node("Content/Fields/Score")
		_check(unknown_score.text == tr("TXT_NA"), locale + ": timeline unknown-score label refreshes with language")
		var translated: String = assistant.body_label.text + assistant.advice_label.text
		_check(not translated.contains("TXT_"), locale + ": review uses translated text")
		if locale == "zh":
			chinese_text = translated
		elif locale == "en":
			english_text = translated
		for mode in ["dark", "light"]:
			UITheme.set_mode(mode, Vector2(-1, -1), false)
			await _settle()
			var rect := assistant.get_global_rect()
			var context: String = locale + "/" + mode
			_check(rect.size.x > 100 and rect.size.y > 80, context + ": assistant has a usable panel")
			_check(rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= 1280.5 and rect.end.y <= 720.5,
				context + ": assistant stays inside viewport")
			_check(not rect.intersects(board_container.get_global_rect()), context + ": assistant does not overlap main board region")
			_check(board_container.size.x >= 300, context + ": main board keeps its width")
			_check(assistant._current_step == 1 and not assistant._collapsed,
				context + ": theme refresh preserves selected step and expanded state")
	_check(not chinese_text.is_empty() and chinese_text != english_text, "language change refreshes analysis and advice")

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var original_locale := TranslationServer.get_locale()
	var original_theme := UITheme.mode
	_make_fixtures()
	_replay = load("res://scenes/ui/replay_system.tscn").instantiate()
	add_child(_replay)
	await _settle()
	await _test_navigation()
	await _test_plan_preview()
	await _test_session_and_analysis_refresh()
	await _test_collapse_and_presentation()
	_check(not _replay._analysis_active and _replay._analysis_pid <= 0, "suite never leaves an analyzer active")
	_replay.queue_free()
	await _settle()
	TranslationServer.set_locale(original_locale)
	UITheme.set_mode(original_theme, Vector2(-1, -1), false)
	await get_tree().create_timer(0.5).timeout
	print(JSON.stringify({"test": "ayao_replay_regression", "checks": _checks, "failures": _failures, "ok": _failures.is_empty()}))
	get_tree().quit(0 if _failures.is_empty() else 1)
