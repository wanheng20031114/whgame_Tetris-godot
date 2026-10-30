extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _bytes(size: int) -> PackedByteArray:
	return "x".repeat(size).to_utf8_buffer()

func _fixture(name: String, total_limit: int, session_limit: int) -> String:
	var path := OS.get_environment("TETRIS_RUN_DIR").path_join("budget-tiers-" + name)
	check(StorageBudget.configure_root_for_tests(path, total_limit, session_limit) == OK, name + ": configure isolated fixture")
	return path

# Model existing files and the external bounded analyzer. These fixtures are
# deliberately outside the service so its scan must account for them on disk.
func _seed(path: String, size: int) -> void:
	check(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK, "create fixture directory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "open fixture: " + path)
		return
	file.store_buffer(_bytes(size))
	file.close()

func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		check(false, "read fixture size: " + path)
		return 0
	var result := file.get_length()
	file.close()
	return result

func _lock_bytes() -> int:
	return JSON.stringify({"pid": OS.get_process_id()}).to_utf8_buffer().size()

func _test_existing_session_files() -> void:
	var path := _fixture("existing", 20000, 1200)
	var primary := path.path_join("sessions/session_20241001_123456.json")
	_seed(primary, 300)
	_seed(path.path_join("archive/.hidden/session_20241001_123456.json.bak.original"), 250)
	_seed(path.path_join("sessions/session_20241001_123456_analyzed.json"), 200)
	_seed(path.path_join("sessions/session_20241001_123456_analyzed.json.pending.old"), 150)
	_seed(path.path_join("sessions/session_20241001_123456.json.progress"), 100)
	check(StorageBudget.append_bounded(primary, _bytes(200), 5000) == OK, "primary + hidden backup + analyzed + pending + legacy suffix reach exact session limit")
	check(StorageBudget.append_bounded(primary, _bytes(1), 5000) != OK, "session append rejects despite per-file and directory space")
	check(StorageBudget.write_atomic(primary, _bytes(1), 5000) != OK, "atomic staging must fit alongside retained primary and backups")
	check(_size(primary) == 500, "denied writes preserve existing primary")
	check(StorageBudget.write_atomic(path.path_join("sessions/session_independent.json"), _bytes(1000), 5000) == OK, "full session does not block a different session")
	var loaded := StorageBudget.read_bounded(primary, StorageBudget.SESSION_BYTES)
	check(loaded.error == OK and loaded.data.size() == 500, "small stored file reads at actual size under 1 GB read cap")
	for name in DirAccess.get_files_at(primary.get_base_dir()):
		check(not name.begins_with(primary.get_file() + ".tmp."), "atomic denial leaves no staging file")
	if OS.get_name() == "Windows":
		check(StorageBudget.append_bounded(path.path_join("sessions/SESSION_20241001_123456_ANALYZED.JSON.tmp.case"), _bytes(1), 5000) != OK, "Windows session grouping is case-insensitive")

func _test_existing_over_limit_and_unknown() -> void:
	var path := _fixture("over-limit", 12000, 600)
	var old_save := path.path_join("session_old.json")
	_seed(old_save, 700)
	check(StorageBudget.append_bounded(old_save, _bytes(1), 5000) != OK, "pre-existing oversized session cannot grow")
	check(_size(old_save) == 700, "pre-existing oversized session is retained")
	check(StorageBudget.write_atomic(path.path_join("session_new.json"), _bytes(600), 5000) == OK, "pre-existing oversized session leaves other session allowance independent")
	check(StorageBudget.write_atomic(path.path_join(".hidden/unknown.bin"), _bytes(1500), 5000) == OK, "unknown files have directory allowance only")
	check(StorageBudget.write_atomic(path.path_join("session.json"), _bytes(1500), 5000) == OK, "filename without session identity has directory allowance only")

func _test_session_reservation() -> void:
	var path := _fixture("reservation", 12000, 2400)
	var primary := path.path_join("session_alpha.json")
	var destination := path.path_join("session_alpha_analyzed.json")
	var staging := destination + ".pending.test"
	_seed(primary, 600)
	_seed(destination, 200)
	var reservation := StorageBudget.reserve_output(staging, 1000)
	check(reservation.error == OK, "reserve analysis capacity in its session")
	if reservation.error != OK:
		return
	var marker := path.path_join(".reservations").path_join(str(reservation.token) + ".json")
	var marker_bytes := _size(marker)
	var remaining := 2400 - 600 - 200 - 1000 - marker_bytes
	check(remaining >= 0, "fixture permits reserved capacity and marker")
	if remaining < 0:
		return
	check(StorageBudget.append_bounded(primary, _bytes(remaining), 5000) == OK, "reservation marker and full future capacity fit exact session boundary")
	check(StorageBudget.append_bounded(primary, _bytes(1), 5000) != OK, "reservation marker bytes belong to their session")
	check(StorageBudget.reserve_output(destination + ".pending.denied", 1).error != OK, "second reservation cannot exceed full session")
	check(StorageBudget.write_atomic(path.path_join("session_beta.json"), _bytes(2400), 5000) == OK, "reserved full session leaves another full session independent")
	_seed(staging, 800)
	check(StorageBudget.append_bounded(primary, _bytes(1), 5000) != OK, "growing analysis counts full reservation rather than physical length")
	check(StorageBudget.commit_reserved(reservation.token, path.path_join("session_beta_analyzed.json")) != OK, "reserved commit cannot transfer into another full session")
	check(StorageBudget.commit_reserved(reservation.token, path.path_join("unknown.json")) != OK, "reserved commit cannot shed its session identity")
	check(FileAccess.file_exists(staging) and FileAccess.file_exists(marker), "rejected cross-session commits retain output and reservation")
	check(StorageBudget.commit_reserved(reservation.token, destination) == OK, "same-session reserved commit replaces output while retaining old backup")
	check(_size(destination) == 800 and not FileAccess.file_exists(marker), "commit retains actual output and removes reservation marker")
	var backups := 0
	for name in DirAccess.get_files_at(path):
		if name.begins_with("session_alpha_analyzed.json.bak."):
			backups += 1
			check(_size(path.path_join(name)) == 200, "old analyzed output is retained in session backup")
	check(backups == 1, "commit creates one retained analyzed backup")
	check(StorageBudget.append_bounded(primary, _bytes(200 + marker_bytes), 5000) == OK, "commit releases unused reservation capacity and marker without double-counting output")
	check(StorageBudget.append_bounded(primary, _bytes(1), 5000) != OK, "committed analyzed output and its backup still share session limit")
	var unnamed := path.path_join("analysis.pending")
	var unknown_reservation := StorageBudget.reserve_output(unnamed, 300)
	check(unknown_reservation.error == OK, "ungrouped reservation uses directory capacity")
	if unknown_reservation.error == OK:
		_seed(unnamed, 100)
		check(StorageBudget.commit_reserved(unknown_reservation.token, path.path_join("session_beta_analyzed.json")) != OK, "ungrouped reservation cannot be committed into recognized session")
		check(StorageBudget.discard_reserved(unknown_reservation.token) == OK, "own rejected ungrouped reservation remains removable")

func _test_directory_limit() -> void:
	var path := _fixture("directory", 3000, 2000)
	_seed(path.path_join(".hidden/existing.bin"), 1100)
	_seed(path.path_join("session_one.json"), 1400)
	var unknown := path.path_join("other.dat")
	check(StorageBudget.write_atomic(unknown, _bytes(500), 5000) != OK, "directory cap includes hidden files and active lock marker")
	check(StorageBudget.write_atomic(unknown, _bytes(500 - _lock_bytes()), 5000) == OK, "write reaches exact directory boundary including lock bytes")
	check(StorageBudget.write_atomic(path.path_join("session_two.json"), _bytes(1), 5000) != OK, "full directory blocks independent new session")
	check(StorageBudget.append_bounded(unknown, _bytes(1), 5000) != OK, "full directory blocks ungrouped data")
	check(StorageBudget.read_bounded(path.path_join("session_one.json"), 5000).error == OK, "full directory retains read access")

func _test_directory_reservation() -> void:
	var path := _fixture("directory-reservation", 5000, 4000)
	_seed(path.path_join("retained.bin"), 1000)
	var staging := path.path_join("session_first_analyzed.json.pending.test")
	var reservation := StorageBudget.reserve_output(staging, 1200)
	check(reservation.error == OK, "reserve shared directory capacity")
	if reservation.error != OK:
		return
	var marker := path.path_join(".reservations").path_join(str(reservation.token) + ".json")
	var marker_bytes := _size(marker)
	var second := path.path_join("session_second.json")
	var remaining := 5000 - 1000 - 1200 - marker_bytes - _lock_bytes()
	check(StorageBudget.write_atomic(second, _bytes(remaining), 5000) == OK, "other session can consume remaining shared capacity exactly")
	check(StorageBudget.append_bounded(second, _bytes(1), 5000) != OK, "reservation blocks directory overshoot before output exists")
	_seed(staging, 800)
	check(StorageBudget.append_bounded(second, _bytes(1), 5000) != OK, "growing reserved file neither frees nor double-counts capacity")
	check(StorageBudget.commit_reserved(reservation.token, path.path_join("session_first_analyzed.json")) == OK, "reserved commit at directory limit needs no extra allocation")
	check(StorageBudget.append_bounded(second, _bytes(400 + marker_bytes), 5000) == OK, "commit releases only unused capacity plus marker to shared budget")
	check(StorageBudget.append_bounded(second, _bytes(1), 5000) != OK, "released capacity cannot be spent twice")

func _test_duplicate_reservation() -> void:
	var path := _fixture("duplicate-reservation", 10000, 4000)
	var staging := path.path_join("session_duplicate_analyzed.json.pending.test")
	var first := StorageBudget.reserve_output(staging, 1000)
	check(first.error == OK, "initial path reservation succeeds")
	check(StorageBudget.reserve_output(staging, 1000).error == ERR_ALREADY_EXISTS, "a reserved path cannot be reserved twice")
	check(StorageBudget.write_atomic(path.path_join("unrelated.txt"), _bytes(20), 20) == OK, "rejected duplicate leaves the shared storage usable")
	check(StorageBudget.release_reservation(first.token) == OK, "initial reservation can still be released")

func _run() -> void:
	var diagnostics := root.get_node_or_null("Diagnostics")
	if diagnostics != null:
		diagnostics.set_process(false)
	check(StorageBudget.SESSION_BYTES == 1000000000 and StorageBudget.TOTAL_BYTES == 20000000000, "production budgets use requested decimal bytes")
	_test_existing_session_files()
	_test_existing_over_limit_and_unknown()
	_test_session_reservation()
	_test_directory_limit()
	_test_directory_reservation()
	_test_duplicate_reservation()
	var legacy_root := OS.get_environment("TETRIS_RUN_DIR").path_join("budget-tiers-legacy-api")
	check(StorageBudget.configure_root_for_tests(legacy_root, 6000) == OK, "existing second argument remains directory limit")
	check(StorageBudget.write_atomic(legacy_root.path_join("session_legacy.json"), _bytes(4500), 5000) == OK, "omitted session test limit restores production default above small directory limit")
	check(StorageBudget.configure_root_for_tests(legacy_root, 6000, 0) != OK, "reject non-positive session test limit")
	check(StorageBudget.configure_root_for_tests(legacy_root, 6000, StorageBudget.SESSION_BYTES + 1) != OK, "reject session test limit above production cap")
	print(JSON.stringify({"test": "storage_budget_tiers_regression", "ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
