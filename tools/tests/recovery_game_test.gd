extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var isolated_data := OS.get_environment("TETRIS_RUN_DIR").path_join("game-data")
	check(StorageBudget.configure_root_for_tests(isolated_data) == OK, "isolated data root")
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _run() -> void:
	var board := Board.new()
	board._init_grid()
	board.grid[0][0] = Color.WHITE
	check(board.add_garbage_lines(1), "garbage reports pushed-out blocks")
	check(board.grid.size() == 40, "garbage keeps 40 rows")
	check(board.add_garbage_lines(1000000000), "huge garbage top-outs with bounded allocation")
	check(board.grid.size() == 40, "huge garbage never grows board")
	var previous: Array = board.get_grid_state()
	var invalid := previous.duplicate(true)
	invalid[39] = [9]
	board.set_grid_state(invalid)
	check(board.get_grid_state() == previous, "invalid board rejected without partial mutation")
	board.free()

	for path in ["res://scenes/game.tscn", "res://scenes/multiplayer_game.tscn", "res://scenes/tetris33_game.tscn"]:
		var game = load(path).instantiate()
		game.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(game)
		# Two bottom corners are occupied, but the piece can move upward.
		# Checking after stamping the piece falsely reports immobility.
		game.board._init_grid()
		for col in range(10):
			if col != 4:
				game.board.grid[39][col] = Color.WHITE
		game.cur_type = PieceData.Type.T
		game.cur_rot = PieceData.RotationState.TWO
		game.cur_col = 4
		game.cur_row = 38
		game.last_was_rotation = true
		var observed: Array = []
		game.lines_cleared.connect(func(amount, spin, _t_spin, _damage): observed.append([amount, spin]))
		game._hard_drop()
		check(observed == [[1, false]], path + ": zero-distance hard drop has no false spin")
		game.free()

		game = load(path).instantiate()
		game.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(game)
		game.board._init_grid()
		game.board.grid[19][6] = Color.WHITE
		game.board.grid[20][6] = Color.WHITE
		game.cur_type = PieceData.Type.T
		game.held_type = PieceData.Type.I
		game.hold_used = false
		game._try_hold()
		check(game.game_over, path + ": blocked Hold triggers top-out")
		if path.ends_with("tetris33_game.tscn"):
			check(game._alive_count == game.active_player_count - 1, "T33 local elimination updates alive count")
		game.free()

		game = load(path).instantiate()
		game.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(game)
		game.board._init_grid()
		for row in [19, 20]:
			for col in [4, 5, 6]:
				game.board.grid[row][col] = Color.WHITE
		game.cur_type = PieceData.Type.O
		game.cur_rot = PieceData.RotationState.SPAWN
		game.cur_col = 0
		game.cur_row = 39
		var session_id: String = game._data_collector._session_id
		game._lock_piece()
		check(game.game_over, path + ": next spawn top-out")
		var saved := StorageBudget.read_bounded(PlayerDataStore.get_sessions_dir().path_join("session_" + session_id + ".json"), PlayerDataStore.MAX_SESSION_BYTES)
		check(saved.error == OK, path + ": top-out saves session")
		if saved.error == OK:
			var data = JSON.parse_string(saved.data.get_string_from_utf8())
			check(data.snapshots.size() == 1, path + ": final locked piece is saved before top-out")
		game.free()

	var logger := PrototypeLogger.new()
	for index in range(10000):
		logger._log_message("flood " + str(index), true)
	check(logger._queue.size() <= PrototypeLogger.QUEUE_LIMIT, "logger flood queue bounded")
	check(logger.flush_pending() == OK, "logger bounded flush")
	logger._log_message("0x887a0005", true)
	check(logger.has_fatal_error(), "device removal requests fatal shutdown")
	logger.flush_pending()
	var full_logger := PrototypeLogger.new()
	var full_bytes := PackedByteArray()
	full_bytes.resize(PrototypeLogger.FILE_LIMIT)
	check(StorageBudget.write_atomic(full_logger._path, full_bytes, PrototypeLogger.FILE_LIMIT, false) == OK, "prepare full diagnostic file")
	full_logger._log_message("cannot grow", false)
	check(full_logger.flush_pending() != OK, "full diagnostic file rejects append")
	check(StorageBudget._size(full_logger._path) == PrototypeLogger.FILE_LIMIT, "diagnostic file never exceeds 8 MiB")
	check(full_logger._stopped, "full diagnostic recording stops")
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
