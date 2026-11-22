extends Node

var _failures := 0

func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures += 1

func _game(path: String, player_count: int = 3) -> Node:
	var game: Node = load(path).instantiate()
	if path.ends_with("tetris33_game.tscn"):
		game.active_player_count = player_count
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	game.get_node("BGM").stop()
	return game

func _check_spawn_geometry(game: TetrisCore) -> void:
	var board: Board = game.board
	var next: Piece = game.next_displays[0]
	for type in BagRandomizer.ALL_TYPES:
		var fits := game._activate_piece(type)
		for cell: Vector2 in PieceData.SHAPES[type][PieceData.RotationState.SPAWN]:
			var y: int = game.cur_row + int(cell.y)
			fits = fits and y < board.buffer_rows and y >= board.buffer_rows - board.shown_buffer_rows
		_check(fits, game.name + " spawns " + PieceData.Type.keys()[type] + " entirely above the rim")
	var active: Piece = game.current_piece
	var clip := active.get_parent() as Control
	var headroom := Rect2(board.global_position - Vector2(0, board.shown_buffer_rows * board.cell_size), Vector2(board.columns, board.shown_buffer_rows) * board.cell_size)
	_check(clip.get_global_rect().encloses(headroom) and is_equal_approx(active.global_position.y, next.global_position.y), game.name + " shows the spawn on the same horizontal line as NEXT")
	board.grid[board.buffer_rows][game.spawn_col] = Color.GRAY
	game._activate_piece(PieceData.Type.O)
	_check(game._try_move(-1, 0) and game._try_move(-1, 0) and game._try_move(0, 1), game.name + " can slide over a rim-high stack before entering the well")
	board.grid[board.buffer_rows - 1][6] = Color.GRAY
	game.held_type = PieceData.Type.I
	game.hold_used = false
	game._try_hold()
	_check(not game.game_over and game.cur_type == PieceData.Type.I and game.cur_row == board.buffer_rows - 2, game.name + " gives Hold the same extra spawn row")
	board._init_grid()

func _check_lethal_landings() -> void:
	var game: GameScene = _game("res://scenes/game.tscn")
	var board: Board = game.board
	var rim := board.buffer_rows
	var ghost: Piece = game.ghost_piece
	game.bag._queue[0] = PieceData.Type.I
	board.grid[rim][4] = Color.GRAY
	game._activate_piece(PieceData.Type.O)
	var before := board.get_grid_state()
	var next_before := game.bag.peek(5)
	game._update_ghost(false)
	_check(ghost.visible and ghost.lethal_outline and ghost.position == game.current_piece.position and ghost.z_index > game.current_piece.z_index, "A grounded fatal landing stays outlined with ordinary previews off")
	_check(before == board.get_grid_state() and next_before == game.bag.peek(5), "Predicting a block-out leaves the board and queue intact")
	game._try_move(1, 0)
	game._update_danger_warning_state()
	game._update_ghost(false)
	_check(board.danger_warning_active and not ghost.visible, "Moving off the spawn column removes the lethal outline while the high-stack warning remains")
	game._try_move(-1, 0)
	game._hard_drop()
	_check(game.game_over and game.current_piece.piece_type == PieceData.Type.I and game.current_piece.lethal_outline, "The marked placement really blocks the queued I")
	game.free()

	game = _game("res://scenes/game.tscn")
	board = game.board
	# 垃圾顶出缓冲区角落的旧格子，但下一个方块仍有出生空间。
	board.grid[0][0] = Color.GRAY
	game.ready_garbage = 1
	game._hard_drop()
	_check(not game.game_over and board.grid[0][0] == null, "Overflow away from spawn allows the next piece to enter")
	board._init_grid()
	for row in range(rim - 4, rim):
		board.grid[row][6] = Color.GRAY
	for col in range(2, board.columns):
		board.grid[board.total_rows - 1][col] = Color.GRAY
	game.bag._queue[0] = PieceData.Type.I
	game.ready_garbage = 3
	game._activate_piece(PieceData.Type.O)
	for step in range(4):
		game._try_move(-1, 0)
	game._update_danger_warning_state()
	game._update_ghost(true)
	_check(game.ghost_piece.visible and not game.ghost_piece.lethal_outline, "A clearing placement predicts the clutch spawn and defers ready garbage")
	game._hard_drop()
	_check(not game.game_over and game.cur_type == PieceData.Type.I and game.cur_row == rim - 4 and game.ready_garbage > 0, "After a clear the next piece lifts to the first complete opening")
	var clip := game.current_piece.get_parent() as Control
	var lifted_cell := Rect2(game.current_piece.global_position, Vector2.ONE * board.cell_size)
	_check(board.view_top_row < rim and clip.get_global_rect().encloses(lifted_cell) and game.get_viewport_rect().encloses(lifted_cell), "A high clutch spawn remains visible at full cell size")
	for step in range(3):
		game._try_move(-1, 0)
	game._try_move(0, 1)
	_check(board.view_top_row == rim, "The normal view returns as the rescued piece drops")
	board._init_grid()
	board.grid[rim][6] = Color.GRAY
	board.grid[rim + 1][6] = Color.GRAY
	game.ready_garbage = 0
	game.pending_attacks = [{"amount": 2, "delay": 1.0}]
	game.bag._queue[0] = PieceData.Type.I
	game._activate_piece(PieceData.Type.O)
	game._update_ghost(false)
	_check(not game.ghost_piece.visible, "Pending garbage alone cannot make a landing lethal")
	game._process(1.01)
	_check(game.ghost_piece.visible and game.ghost_piece.lethal_outline, "Garbage becoming ready updates the lethal landing within the same frame")
	game._hard_drop()
	_check(game.game_over, "The mature garbage rise blocks the same next spawn as the preview")
	for row in range(rim):
		board.grid[row][4] = Color.GRAY
	_check(board.find_spawn_row(PieceData.Type.O, 4, board.grid, true) == -1, "Even a clutch spawn needs all four cells inside the buffer")
	game.free()

func _run() -> void:
	var das := DASHandler.new()
	das.das_delay = 0.1
	das.arr_interval = 0.05
	das.start(1)
	_check(das.update(0.21) == 3, "DAS consumes ARR overflow in the charging frame")
	_check(das.update(0.041) == 1, "DAS retains fractional ARR time")
	das.arr_interval = 0.0
	_check(das.update(0.016) >= 10, "Zero ARR still moves to the wall")
	var scoring := Scoring.new()
	scoring.starting_level = 5
	scoring.level = 5
	scoring.process_line_clear(1, false, false)
	_check(scoring.level == 5 and scoring.score == 500, "First clear preserves the configured starting level")
	for i in range(9):
		scoring.process_line_clear(1, false, false)
	_check(scoring.level == 6, "Ten cleared rows advance the configured starting level")
	var guide := GuideScenarioRunner.new()
	guide.grid = GuideScenarioRunner.empty_grid()
	guide.spawn(PieceData.Type.T, 4, 10)
	guide.grid[11][4] = GuideScenarioRunner.GARBAGE
	_check(guide.try_rotate(2) and guide.col == 4 and guide.row == 9, "Guide and gameplay use the same 180-degree kick priority")
	guide.grid = GuideScenarioRunner.empty_grid()
	guide.spawn(PieceData.Type.T, 4, 10)
	guide.try_rotate(1)
	_check(not guide.lock_piece()["spin"], "Guide never detects a spin from collision with the just-locked piece")
	guide.grid = GuideScenarioRunner.empty_grid()
	guide.spawn(PieceData.Type.T, 4, 18, PieceData.RotationState.TWO)
	guide.last_was_rotation = true
	for cell in [Vector2i(3, 17), Vector2i(3, 19), Vector2i(5, 19)]:
		guide.grid[cell.y][cell.x] = GuideScenarioRunner.GARBAGE
	_check(guide.lock_piece()["spin"], "Guide recognizes T spins using occupied corners")
	guide.grid = GuideScenarioRunner.empty_grid()
	guide.spawn(PieceData.Type.O, 4, 19)
	guide.try_rotate(1)
	_check(not guide.lock_piece()["spin"], "Guide excludes O-piece spins")

	var game = _game("res://scenes/game.tscn")
	_check_spawn_geometry(game)
	_check(game.has_node("SfxMove") and game.has_node("AttackFXLayer"), "Single-player scene supplies native audio and attack-layer nodes")
	game._activate_piece(PieceData.Type.T)
	game.cur_row = game.board.total_rows - 10
	game.board.grid[game.cur_row + 1][game.cur_col] = Color.GRAY
	var rotation_origin := Vector2i(game.cur_col, game.cur_row)
	_check(game._try_rotate(2) and Vector2i(game.cur_col, game.cur_row) == rotation_origin + Vector2i.UP, "180-degree T rotation follows PieceData kick priority")
	game.cur_type = PieceData.Type.S
	game._remember_clear_kind(1, true, false, 1)
	game.cur_type = PieceData.Type.J
	_check(game._clear_tint() == PieceData.COLORS[PieceData.Type.S], "Deferred spin attacks retain the locked piece color after spawning the next piece")
	var combo_y: float = game.label_combo_text.position.y
	for i in range(5):
		game._show_combo_text(i + 1)
	_check(is_equal_approx(game.label_combo_text.position.y, combo_y + 8.0), "Repeated COMBO animations retain one layout baseline")
	var board: Board = game.board
	var rest := board.position
	board.bump(Vector2(0, 4))
	for i in range(30):
		board._process(0.1)
	_check(board.position.is_finite() and board.position.distance_to(rest) < 0.1, "Board impact settles after sustained 100ms frames")
	board._init_grid()
	game._activate_piece(PieceData.Type.O)
	game.cur_row = board.total_rows - 1
	game._update_lock_delay(0.49)
	_check(board.get_stack_height() == 0, "Grounded piece remains active before lock delay expires")
	game._update_lock_delay(0.02)
	_check(board.get_stack_height() == 2, "Grounded piece locks once its delay expires")
	game.free()
	_check_lethal_landings()
	var versus = _game("res://scenes/multiplayer_game.tscn")
	_check_spawn_geometry(versus)
	_check(versus.has_node("SfxMove") and versus.has_node("AttackFXLayer"), "Versus scene supplies native audio and attack-layer nodes")
	var impacts := [0]
	var attack := AttackFX.fire(versus, Vector2.ZERO, Vector2(100, 100), 3, Color.WHITE, NAN, func(): impacts[0] += 1, 0.08)
	attack._process(0.1)
	_check(attack.visible and attack._t < 0.1, "Delayed attack only advances by time left after its launch delay")
	attack._process(1.0)
	attack._process(1.0)
	_check(impacts[0] == 1 and attack.is_queued_for_deletion(), "Attack impact fires once and the finished effect frees itself")
	versus.free()

	var royale = _game("res://scenes/tetris33_game.tscn")
	_check_spawn_geometry(royale)
	_check(royale.has_node("SfxMove") and royale.has_node("AttackFXLayer"), "Tetris33 scene supplies native audio and attack-layer nodes")
	royale._on_local_game_over()
	royale._sample_timer = 0.2
	royale._process(0.1)
	_check(is_equal_approx(royale._sample_timer, 0.3), "Offline opponents keep simulating while the local player spectates")
	royale._eliminate_opponent(0)
	_check(royale._match_finished and royale.result_overlay.visible, "Offline spectating reaches a match result")
	_check(not royale.btn_restart.disabled, "Offline match result allows restart")
	royale.free()
	var winner = _game("res://scenes/tetris33_game.tscn")
	winner._eliminate_opponent(0)
	winner.lines_cleared.connect(func(_amount, _spin, _t_spin, _damage): winner._eliminate_opponent(1))
	winner._activate_piece(PieceData.Type.O)
	winner.cur_row = winner.board.total_rows - 1
	for col in range(winner.board.columns):
		if col != winner.cur_col and col != winner.cur_col + 1:
			winner.board.grid[winner.cur_row][col] = Color.GRAY
	var next_before: Array = winner.bag.peek(5)
	winner._lock_piece()
	_check(winner._match_finished and winner._data_collector._piece_index == 1, "Winning line clear is recorded before the session ends")
	_check(winner.bag.peek(5) == next_before, "Victory does not spawn another active piece")
	winner.free()
	# AudioServer releases stopped Ogg playback objects on its own mix tick.
	await get_tree().create_timer(0.5).timeout
	print("CORE_GAMEPLAY_REGRESSION failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
