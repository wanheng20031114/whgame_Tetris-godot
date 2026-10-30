extends Node

const Schema := preload("res://scripts/core/replay_schema.gd")
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _analysis() -> Dictionary:
	return {"storage_protocol": 1, "analysis_revision": 2, "session_id": "valid",
		"ai_model_used": "cold-clear-standard", "ai_scores": [0],
		"ai_details": [{"quality": "unknown"}], "recommendations": [null]}


func _write(path: String, data: Dictionary) -> void:
	check(StorageBudget.write_atomic(path, JSON.stringify(data).to_utf8_buffer(), 1_000_000, false) == OK, "write fixture")


func _run() -> void:
	var session := {"session_id": "valid", "snapshots": [{"piece_type": "T"}]}
	check(Schema.valid_session(session), "legacy sessions can omit optional metrics and board")
	for field in Schema.SESSION_NUMBERS:
		var invalid := session.duplicate(true)
		invalid[field] = {}
		check(not Schema.valid_session(invalid), "reject invalid session number: " + field)
	for field in Schema.SNAPSHOT_NUMBERS:
		var invalid := session.duplicate(true)
		invalid.snapshots[0][field] = []
		check(not Schema.valid_session(invalid), "reject invalid snapshot number: " + field)
	for invalid_radar in [[], {"speed": {}}, {"speed": INF}]:
		var invalid := session.duplicate(true)
		invalid.radar_scores = invalid_radar
		check(not Schema.valid_session(invalid), "reject invalid radar")
	for invalid in [NAN, INF, -INF, 1e100, {}, [], "0", null]:
		var analysis := _analysis()
		analysis.ai_scores[0] = invalid
		check(not Schema.valid_analysis(analysis, "valid", 1), "reject invalid cached score")
	for invalid in [[], {"score_loss": {}}, {"best": {"placement": []}}, {"best": {"placement": {"col": {}}}}]:
		var analysis := _analysis()
		analysis.ai_details[0] = invalid
		check(not Schema.valid_analysis(analysis, "valid", 1), "reject invalid cached detail")
	for invalid in [[], {"step": {}}, {"step": 0, "plan": {"steps": [null]}}, {"step": 0, "plan": {"steps": [{"placement": {"rotation": []}}]}}, {"step": 0, "plan": {"steps": [{"placement": {}, "lock": {"cleared_lines": [0, 0]}}]}}]:
		var analysis := _analysis()
		analysis.recommendations[0] = invalid
		check(not Schema.valid_analysis(analysis, "valid", 1), "reject invalid cached recommendation")
	check(Schema.valid_analysis(_analysis(), "valid", 1), "unknown analysis without optional loss or plan remains valid")
	for key in ["storage_protocol", "analysis_revision", "ai_model_used", "session_id"]:
		for value in [{}, [], null, true]:
			var invalid := _analysis()
			invalid[key] = value
			check(not Schema.valid_analysis(invalid, "valid", 1), "reject invalid cache metadata: " + key)
	check(not Schema.valid_analysis(_analysis(), "different", 1), "cache must belong to selected session")
	check(not Schema.valid_analysis(_analysis(), "valid", 2), "cache must match snapshot count")
	var path := PlayerDataStore.get_sessions_dir().path_join("session_valid.json")
	_write(path, session)
	_write(path.replace(".json", "_analyzed.json"), _analysis())
	var replay: ReplaySystem = load("res://scenes/ui/replay_system.tscn").instantiate()
	add_child(replay)
	replay._load_session(path.get_file())
	check(replay._current_step == 0 and not replay._analysis_active, "valid fixture loads with cached analysis")
	var old_review := replay.assistant_panel._review.duplicate(true)
	var damaged := session.duplicate(true)
	damaged.final_score = {}
	var damaged_path := PlayerDataStore.get_sessions_dir().path_join("session_damaged.json")
	_write(damaged_path, damaged)
	replay._load_session(damaged_path.get_file())
	check(replay._session_data.session_id == "valid" and replay.assistant_panel._review == old_review, "invalid load retains selected replay and assistant")
	var bad_cache := _analysis()
	bad_cache.ai_scores = [{}]
	var previous_scores := replay._ai_scores.duplicate(true)
	var cache_path := PlayerDataStore.get_sessions_dir().path_join("bad_cache.json")
	_write(cache_path, bad_cache)
	check(not replay._try_load_ai_scores_from_path(cache_path) and replay._ai_scores == previous_scores, "invalid cache cannot partially replace current scores")
	check(FileAccess.get_file_as_string(damaged_path) == JSON.stringify(damaged), "invalid original is retained unchanged")
	var stats: Control = load("res://scenes/ui/player_stats_screen.tscn").instantiate()
	add_child(stats)
	check(stats._load_session_data("damaged").is_empty(), "statistics details reject malformed replay fields")
	check(not stats._load_session_data("valid").is_empty(), "statistics details accept valid legacy replay")
	stats.queue_free()
	replay.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	print(JSON.stringify({"test": "replay_schema_regression", "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
