extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("replay-data"))
	_run.call_deferred()

func _run() -> void:
	# Empty replays intentionally skip analysis. A minimal legacy snapshot still
	# exercises real process launch, result validation and cancellation.
	var session := {"session_id": "bounded-fixture", "snapshots": [{}], "pieces_placed": 1, "final_score": 0}
	var name := "session_bounded-fixture.json"
	var source := PlayerDataStore.get_sessions_dir().path_join(name)
	if StorageBudget.write_atomic(source, JSON.stringify(session).to_utf8_buffer(), PlayerDataStore.MAX_SESSION_BYTES, false) != OK:
		failures.append("input fixture save")
	var replay: Node = load("res://scenes/ui/replay_system.tscn").instantiate()
	root.add_child(replay)
	replay._load_session(name)
	var deadline := Time.get_ticks_msec() + 10000
	while replay._analysis_active and Time.get_ticks_msec() < deadline:
		await process_frame
	var result := source.replace(".json", "_analyzed.json")
	if replay._analysis_active or not FileAccess.file_exists(result):
		failures.append("bounded analyzer did not commit result: " + StorageBudget.last_error())
	else:
		var read := StorageBudget.read_bounded(result, 64000000)
		var parsed = JSON.parse_string(read.data.get_string_from_utf8())
		if not ReplaySchema.valid_analysis(parsed, session.session_id, 1):
			failures.append("actual analyzer output does not match the cache schema")
		elif parsed.ai_details[0].get("quality") != "unknown" or parsed.recommendations[0].get("plan") != null:
			failures.append("incomplete legacy snapshot invented analysis or a plan")
	# A new analysis can be cancelled without deleting the original or result.
	replay._run_ai_analysis(name)
	var process_id: int = replay._analysis_pid
	replay._cancel_ai_analysis()
	if process_id > 0 and OS.is_process_running(process_id):
		failures.append("cancel left analyzer running")
	if not FileAccess.file_exists(source) or not FileAccess.file_exists(result):
		failures.append("cancel changed original or committed result")
	if not replay._analysis_reservation.is_empty():
		failures.append("cancel retained active reservation")
	replay.free()
	await process_frame
	await create_timer(0.5).timeout
	print(JSON.stringify({"test": "replay_process", "failures": failures}))
	quit(0 if failures.is_empty() else 1)
