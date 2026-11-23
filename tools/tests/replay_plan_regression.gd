extends SceneTree

# Run through safe_run.py; the sole user argument is the absolute fixture directory.
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	var run_dir: String = OS.get_environment("TETRIS_RUN_DIR")
	check(run_dir.is_absolute_path(), "safe-run directory is absolute")
	if not run_dir.is_absolute_path():
		_finish()
		return
	check(StorageBudget.configure_root_for_tests(run_dir.path_join("data")) == OK, "isolated storage root")
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _finish() -> void:
	print(JSON.stringify({"test": "replay_plan_regression", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _copy_fixture(source: String, destination: String, max_bytes: int) -> bool:
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	check(file != null, "fixture opens read-only: " + source.get_file())
	if file == null:
		return false
	var length: int = file.get_length()
	check(length > 0 and length <= max_bytes, "fixture length: " + source.get_file())
	if length <= 0 or length > max_bytes:
		file.close()
		return false
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	check(bytes.size() == length, "fixture fully read: " + source.get_file())
	if bytes.size() != length:
		return false
	var result: Error = StorageBudget.write_atomic(destination, bytes, max_bytes, false)
	check(result == OK, "fixture copied into isolated sessions: " + source.get_file())
	return result == OK


func _count_plan_buttons(board: Node) -> int:
	var count: int = 0
	for child in board.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.text == "?":
			count += 1
	return count


func _run() -> void:
	if not failures.is_empty():
		_finish()
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	check(args.size() == 1, "one absolute fixture-directory argument")
	if args.size() != 1:
		_finish()
		return
	var fixture_dir: String = args[0]
	check(fixture_dir.is_absolute_path(), "fixture directory is absolute")
	if not fixture_dir.is_absolute_path():
		_finish()
		return
	var session_source: String = fixture_dir.path_join("session.json")
	var analysis_source: String = fixture_dir.path_join("analyzed.json")
	var session_hash: String = FileAccess.get_sha256(session_source)
	var analysis_hash: String = FileAccess.get_sha256(analysis_source)
	var session_path: String = PlayerDataStore.get_sessions_dir().path_join("session_plan-regression.json")
	var analysis_path: String = PlayerDataStore.get_sessions_dir().path_join("session_plan-regression_analyzed.json")
	if not _copy_fixture(session_source, session_path, PlayerDataStore.MAX_SESSION_BYTES):
		_finish()
		return
	if not _copy_fixture(analysis_source, analysis_path, 64_000_000):
		_finish()
		return
	var loaded: Dictionary = StorageBudget.read_bounded(session_path, PlayerDataStore.MAX_SESSION_BYTES)
	check(loaded.error == OK, "isolated session can be read")
	if loaded.error != OK:
		_finish()
		return
	var parsed: Variant = JSON.parse_string(loaded.data.get_string_from_utf8())
	check(parsed is Dictionary and parsed.get("snapshots") is Array, "real session schema")
	if not (parsed is Dictionary) or not (parsed.get("snapshots") is Array):
		_finish()
		return
	check(parsed.snapshots.size() == 375, "all 375 real snapshots loaded")
	if parsed.snapshots.size() != 375:
		_finish()
		return

	var replay: Node = load("res://scenes/ui/replay_system.tscn").instantiate()
	root.add_child(replay)
	await process_frame
	replay.session_list_popup.hide()
	replay._session_data = parsed
	replay._snapshots = parsed.snapshots
	# This reader validates the existing analyzer output without launching a process.
	var analysis_valid: bool = replay._try_load_ai_scores_from_path(analysis_path)
	check(analysis_valid, "real analysis matches session and all 375 steps")
	if not analysis_valid:
		replay.free()
		_finish()
		return
	check(not replay._analysis_active and replay._analysis_pid == -1, "no analyzer process started")
	replay.step_slider.min_value = 0
	replay.step_slider.max_value = 374
	replay.step_slider.step = 1
	replay._update_session_overview()
	replay._refresh_timeline_graph()
	replay._build_timeline()
	await process_frame

	for index in [373, 374]:
		var description: String = "step %d: " % (index + 1)
		var recommendation: Dictionary = replay._ai_recommendations[index]
		check(int(recommendation.get("step", -1)) == index and recommendation.get("plan") == null, description + "fixture contains legal null plan")
		replay._go_to_step(index)
		await process_frame
		check(replay._get_recommendation(index).is_empty(), description + "no usable multi-step plan")
		check(_count_plan_buttons(replay.board_overlays) == 0, description + "unavailable plan has no question button")
		check(replay._format_best_move(replay._get_ai_detail(index)) != "best: -", description + "single-move recommendation remains available")
		replay._toggle_ai_plan(index)
		check(not replay._showing_ai_plan and replay._ai_plan_reveal_count == 0, description + "toggle cannot enter unavailable plan")
		replay._advance_ai_plan(index)
		check(not replay._showing_ai_plan and replay._ai_plan_reveal_count == 0, description + "advance preserves replay mode")
		replay._render_ai_plan_progressive(index)
		await process_frame
		check(not replay._showing_ai_plan and replay._ai_plan_reveal_count == 0, description + "render preserves replay mode")
		check(replay._current_step == index and _count_plan_buttons(replay.board_overlays) == 0, description + "ordinary replay stays on selected step")

	replay._go_to_step(0)
	await process_frame
	check(not replay._get_recommendation(0).is_empty(), "first step has valid real plan")
	check(_count_plan_buttons(replay.board_overlays) == 1, "valid plan exposes question button")
	replay._toggle_ai_plan(0)
	await process_frame
	check(replay._showing_ai_plan and replay._ai_plan_reveal_count == 1, "valid plan opens at first placement")
	var initial_plan_board: Array = replay._ai_plan_simulated_board.duplicate(true)
	replay._advance_ai_plan(0)
	await process_frame
	check(replay._showing_ai_plan and replay._ai_plan_reveal_count == 2, "valid plan advances one placement")
	check(replay._ai_plan_board_history.size() == 1 and replay._ai_plan_simulated_board != initial_plan_board, "advance records history and locks first placement")
	replay._retreat_ai_plan(0)
	await process_frame
	check(replay._showing_ai_plan and replay._ai_plan_reveal_count == 1, "valid plan retreats one placement")
	check(replay._ai_plan_board_history.is_empty() and replay._ai_plan_simulated_board == initial_plan_board, "retreat restores exact prior board")
	replay._toggle_ai_plan(0)
	await process_frame
	check(not replay._showing_ai_plan and replay._ai_plan_reveal_count == 0, "plan exits to ordinary replay")
	check(replay._ai_plan_simulated_board.is_empty() and replay._ai_plan_board_history.is_empty(), "plan exit clears transient simulation")
	check(replay._current_step == 0 and _count_plan_buttons(replay.board_overlays) == 1, "exit restores first-step replay and available plan")
	check(not replay._analysis_active and replay._analysis_pid == -1, "plan interactions never start analyzer")
	replay.free()
	await process_frame
	check(FileAccess.get_sha256(session_source) == session_hash, "source session fixture unchanged")
	check(FileAccess.get_sha256(analysis_source) == analysis_hash, "source analysis fixture unchanged")
	_finish()
