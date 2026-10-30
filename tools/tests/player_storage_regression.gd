extends SceneTree

class FrozenCollector:
	extends PlayerDataCollector
	func _get_iso_datetime() -> String:
		return "2026-10-14T01:02:03"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func fixture_collector() -> PlayerDataCollector:
	var collector := FrozenCollector.new()
	collector.start_session("Fixture")
	collector.set("_snapshots", [{"piece_index": 0, "fixture": true}])
	collector.set("_piece_index", 1)
	return collector

func _run() -> void:
	var diagnostics := root.get_node_or_null("Diagnostics")
	if diagnostics != null:
		diagnostics.set_process(false)
	var base := OS.get_environment("TETRIS_RUN_DIR")
	check(StorageBudget.configure_root_for_tests(base.path_join("player-good"), 100000) == OK, "good-data isolated root")
	var first := fixture_collector()
	var second := fixture_collector()
	check(first.get("_session_start_iso") == second.get("_session_start_iso"), "same-second fixture")
	check(first.get("_session_id") != second.get("_session_id"), "same-second IDs differ")
	var saved := first.end_session(10, 1, 0)
	check(saved.get("snapshots", []).size() == 1, "successful end preserves returned snapshots")
	check(first.end_session(10, 1, 0).is_empty(), "end_session is idempotent")
	var stats := PlayerDataStore.load_stats()
	check(int(stats.get("total_games", 0)) == 1, "successful stats counted once")
	for malformed in ["{broken", '{"radar_scores":[],"history":[]}', '{"radar_scores":{},"history":{}}', '{"radar_scores":{"speed":[]},"history":[]}']:
		var path := PlayerDataStore.get_stats_path()
		var original: PackedByteArray = malformed.to_utf8_buffer()
		check(StorageBudget.write_atomic(path, original, 4000000) == OK, "corrupt stats fixture saved")
		check(PlayerDataStore.update_stats("Fixture", {"session_id": "malformed-test"}, {}) != OK, "corrupt stats rejected")
		var unchanged := StorageBudget.read_bounded(path, 4000000)
		check(unchanged.error == OK and unchanged.data == original, "corrupt primary retained without overwrite")
		check(StorageBudget.write_atomic(StorageBudget.data_root().path_join("lock-check.txt"), "ok".to_utf8_buffer(), 2) == OK, "transaction lock released after rejected stats")
	check(StorageBudget.configure_root_for_tests(base.path_join("player-full"), 4000) == OK, "full-budget isolated root")
	var prior := '{"total_games":7,"radar_scores":{},"history":[]}'.to_utf8_buffer()
	check(StorageBudget.write_atomic(PlayerDataStore.get_stats_path(), prior, 4000000) == OK, "prior stats fixture")
	check(StorageBudget.write_atomic(StorageBudget.data_root().path_join("retained.bin"), "x".repeat(3500).to_utf8_buffer(), 3500) == OK, "fill write budget")
	var unsaved_a := fixture_collector()
	var unsaved_b := fixture_collector()
	var result_a := unsaved_a.end_session(10, 1, 0)
	var result_b := unsaved_b.end_session(20, 1, 0)
	check(result_a.snapshots.size() == 1 and result_b.snapshots.size() == 1, "failed saves retain snapshots")
	unsaved_a.start_session("Next game")
	check(result_a.snapshots.size() == 1, "starting another game preserves the pending session snapshots")
	check(PlayerDataStore.retry_pending_saves() == 2, "pending queue remains bounded at two")
	var third := FrozenCollector.new()
	third.start_session("Still playing")
	check(not third.is_active(), "full pending queue stops new recording")
	check(int(PlayerDataStore.load_stats().get("total_games", 0)) == 7, "old stats readable after budget rejection")
	check(not StorageBudget.last_error().is_empty(), "failure reason remains visible")
	check(StorageBudget.configure_root_for_tests(base.path_join("player-full"), 100000) == OK, "restore write capacity")
	check(PlayerDataStore.retry_pending_saves() == 0, "pending sessions eventually save")
	var recovered_stats := PlayerDataStore.load_stats()
	check(recovered_stats.history[0].session_id == result_a.session_id and recovered_stats.history[1].session_id == result_b.session_id, "pending sessions update history and radar in chronological order")
	var recovered_path := PlayerDataStore.get_sessions_dir().path_join("session_%s.json" % result_a.session_id)
	var recovered := StorageBudget.read_bounded(recovered_path, PlayerDataStore.MAX_SESSION_BYTES)
	check(recovered.error == OK and JSON.parse_string(recovered.data.get_string_from_utf8()).snapshots.size() == 1, "retried save still contains original snapshots")
	print(JSON.stringify({"test": "player_storage_regression", "ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
