extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _run() -> void:
	var diagnostics := root.get_node_or_null("Diagnostics")
	if diagnostics != null:
		diagnostics.set_process(false)
	var test_root := OS.get_environment("TETRIS_RUN_DIR").path_join("storage-fixture")
	check(StorageBudget.configure_root_for_tests(test_root, 12000) == OK, "isolated root injection")
	check(StorageBudget.write_atomic(test_root.path_join(".hidden/retained.bin"), "h".repeat(1000).to_utf8_buffer(), 1000) == OK, "hidden file fixture")
	var first := test_root.path_join("session.json")
	var a := "a".repeat(3000).to_utf8_buffer()
	var b := "b".repeat(3000).to_utf8_buffer()
	check(StorageBudget.write_atomic(first, a, 3000) == OK, "first bounded atomic write")
	check(StorageBudget.write_atomic(first, b, 3000) == OK, "replacement preserves backup")
	var loaded := StorageBudget.read_bounded(first, 3000)
	check(loaded.error == OK and loaded.data == b, "replacement content")
	var backups := 0
	for name in DirAccess.get_files_at(test_root):
		if name.begins_with("session.json.bak."):
			backups += 1
			var saved := StorageBudget.read_bounded(test_root.path_join(name), 3000)
			check(saved.error == OK and saved.data == a, "backup preserved byte-for-byte")
	check(backups == 1, "one retained original backup")
	var log_path := test_root.path_join("diagnostics/first.log")
	check(StorageBudget.append_bounded(log_path, "x".repeat(2000).to_utf8_buffer(), 2000) == OK, "append exact file cap")
	check(StorageBudget.append_bounded(log_path, "x".to_utf8_buffer(), 2000) != OK, "append rejects before cap overshoot")
	var log_data := StorageBudget.read_bounded(log_path, 2000)
	check(log_data.error == OK and log_data.data.size() == 2000, "rejected append did not alter file")
	check(not StorageBudget.last_error().is_empty(), "successful read preserves failure reason")
	var denied := test_root.path_join("denied.json")
	check(StorageBudget.write_atomic(denied, "x".repeat(5000).to_utf8_buffer(), 5000) != OK, "total includes primary backup and diagnostic bytes")
	check(not FileAccess.file_exists(denied), "budget denial did not create destination")
	var staging := test_root.path_join("analysis.pending")
	var reservation := StorageBudget.reserve_output(staging, 2000)
	check(reservation.error == OK, "reserve future analysis output")
	check(StorageBudget.write_atomic(denied, "x".repeat(1000).to_utf8_buffer(), 1000) != OK, "reservation and hidden files prevent another writer consuming capacity")
	# Simulate the bounded Rust writer using only its granted 2,000 bytes.
	var external := FileAccess.open(staging, FileAccess.WRITE)
	if external != null:
		external.store_buffer("z".repeat(2000).to_utf8_buffer())
		external.close()
	else:
		check(false, "reserved external fixture open")
	check(StorageBudget.write_atomic(denied, "x".repeat(2000).to_utf8_buffer(), 2000) != OK, "growing reserved output remains fully counted")
	check(StorageBudget.commit_reserved(reservation.token, test_root.path_join("analysis.json")) == OK, "reserved output commit without double allocation")
	var final_analysis := StorageBudget.read_bounded(test_root.path_join("analysis.json"), 2000)
	check(final_analysis.error == OK and final_analysis.data.size() == 2000, "committed analysis exact length")
	check(StorageBudget.write_atomic(test_root.path_join("../outside.txt"), PackedByteArray([1]), 1) != OK, "reject traversal outside root")
	for name in DirAccess.get_files_at(test_root):
		check(not name.contains(".tmp."), "no partial staging file after denial")
	print(JSON.stringify({"test": "storage_budget_regression", "ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
