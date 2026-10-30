extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	check(StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data")) == OK, "isolated data root")
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func make_grid(rows: int) -> Array:
	var result: Array = []
	for _row in range(rows):
		var cells: Array = []
		cells.resize(10)
		cells.fill(0)
		result.append(cells)
	return result

func packet(type: String, payload: Dictionary) -> String:
	return JSON.stringify({"type": type, "payload": payload})

func _run() -> void:
	# Instantiate without entering the scene tree: no poll, connection, rendering,
	# or network listener. Exercise the production parser and validation directly.
	var manager = load("res://scripts/core/network_manager.gd").new()
	manager.my_id = "local"
	manager.current_room_id = "ROOM"
	manager.match_id = "current-match"
	var attacks: Array = []
	var starts: Array = []
	var boards: Array = []
	var protocol_errors: Array = []
	manager.attack_received.connect(func(amount): attacks.append(amount))
	manager.game_started.connect(func(name, seed): starts.append([name, seed]))
	manager.board_update_received.connect(func(board): boards.append(board))
	manager.server_error.connect(func(message, _payload): protocol_errors.append(message))

	for amount in [-1, 0, 1.5, 13, 1000000, "1", null, {}, INF, NAN]:
		check(not manager._valid_payload("attack", {"match_id": "current-match", "amount": amount}), "reject attack value " + str(amount))
	for amount in [1, 12]:
		check(manager._valid_payload("attack", {"match_id": "current-match", "amount": amount}), "accept bounded attack " + str(amount))
	check(not manager._valid_payload("attack", {"amount": 1}), "match ID is mandatory")
	manager._handle_message(packet("attack", {"match_id": "old-match", "amount": 1}))
	check(attacks.is_empty(), "stale match attack never reaches game signal")
	manager._handle_message(packet("attack", {"match_id": "current-match", "amount": 12}))
	check(attacks == [12], "current match attack reaches game signal")

	var valid_board := make_grid(40)
	check(manager._valid_payload("board_update", {"match_id": "current-match", "grid": valid_board}), "accept 40x10 grid")
	for invalid_board in [[], make_grid(39), Array(), null, "grid"]:
		check(not manager._valid_payload("board_update", {"match_id": "current-match", "grid": invalid_board}), "reject wrong grid shape")
	var short_row := valid_board.duplicate(true)
	short_row[39] = [0]
	check(not manager._valid_payload("board_update", {"match_id": "current-match", "grid": short_row}), "reject short final row")
	var bad_cell := valid_board.duplicate(true)
	bad_cell[39][9] = "0"
	check(not manager._valid_payload("board_update", {"match_id": "current-match", "grid": bad_cell}), "reject string cell")
	bad_cell[39][9] = 9
	check(not manager._valid_payload("board_update", {"match_id": "current-match", "grid": bad_cell}), "reject invalid cell enum")
	manager._handle_message(packet("board_update", {"match_id": "old-match", "grid": valid_board}))
	check(boards.is_empty(), "stale board never reaches render signal")
	manager._handle_message(packet("board_update", {"match_id": "current-match", "grid": valid_board}))
	check(boards.size() == 1, "current valid board reaches render signal")

	check(manager._valid_payload("tetris33_sample", {"match_id": "current-match", "from_id": "opponent", "visible_board": make_grid(20), "structure_score": 93.5, "stability_score": 81, "pending_garbage": 40}), "accept legal T33 sample")
	check(not manager._valid_payload("tetris33_sample", {"match_id": "current-match", "from_id": "opponent", "visible_board": make_grid(20), "structure_score": "score"}), "reject nonnumeric score")
	check(not manager._valid_payload("tetris33_attack", {"match_id": "current-match", "from_id": "opponent", "target_id": "", "amount": 1}), "reject broadcast attack")
	check(not manager._valid_payload("tetris33_attack", {"match_id": "current-match", "from_id": "opponent", "target_id": "other", "amount": 1}), "reject wrong recipient")
	check(manager._valid_payload("tetris33_attack", {"match_id": "current-match", "from_id": "opponent", "target_id": "local", "amount": 12}), "accept targeted attack")
	var results := [{"id": "local", "name": "A", "rank": 1}, {"id": "other", "name": "B", "rank": 2}]
	check(manager._valid_payload("tetris33_match_finished", {"match_id": "current-match", "results": results, "player_count": 2}), "accept unique final ranking")
	results[1]["rank"] = 1
	check(not manager._valid_payload("tetris33_match_finished", {"match_id": "current-match", "results": results, "player_count": 2}), "reject double champion")
	check(not manager._valid_payload("room_list", {"rooms": [1]}), "reject malformed room list")
	check(not manager._valid_payload("login_success", {"id": []}), "reject malformed identity")
	check(not manager._valid_payload("unknown", {}), "reject unknown server event")

	manager._handle_message(packet("game_start", {"match_id": "next-match", "opponent_name": "Opponent", "seed": 123}))
	check(starts == [["Opponent", 123]] and manager.match_id == "next-match", "game start installs new match before signal")
	manager._handle_message(packet("attack", {"match_id": "current-match", "amount": 1}))
	check(attacks == [12], "old round packet rejected after new start")
	manager.disconnect_from_server()
	check(manager.current_room_id.is_empty() and manager.match_id.is_empty(), "disconnect clears room and round")

	# Malformed envelopes must not execute Dictionary methods on other Variants.
	for text in ["null", "[]", "1", "true", "{\"type\":\"attack\",\"payload\":[]}"]:
		manager._handle_message(text)
	check(not protocol_errors.is_empty(), "repeated malformed envelopes close protocol")
	var before: int = protocol_errors.size()
	manager._handle_message("x".repeat(65537))
	check(protocol_errors.size() == before + 1, "oversized packet rejected before JSON parsing")
	manager.free()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
