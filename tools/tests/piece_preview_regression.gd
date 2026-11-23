extends Node

const SIZES := [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1024, 768), Vector2i(1920, 1008)]
const GAMES := [preload("res://scenes/game.tscn"), preload("res://scenes/multiplayer_game.tscn"), preload("res://scenes/tetris33_game.tscn")]

var checks := 0
var failures := 0


func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	_run.call_deferred()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", get_window().size, " ", description)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _check_slot(slot: PiecePreview, type: int, area: Rect2, header: Rect2) -> void:
	var cells := slot.get_cell_rects()
	var label := "%s %s" % [slot.get_path(), PieceData.Type.keys()[type]]
	_check(slot.piece_type == type and cells.size() == 4, label + " displays the expected four cells")
	if cells.size() != 4:
		return
	var shape: Array = PieceData.SHAPES[type][PieceData.RotationState.SPAWN]
	var cell_size := cells[0].size.x
	var shape_ok := cell_size > 0.0
	for i in cells.size():
		var offset: Vector2 = shape[i] - shape[0]
		shape_ok = shape_ok and cells[i].size.is_equal_approx(Vector2.ONE * cell_size) and cells[i].position.is_equal_approx(cells[0].position + offset * cell_size)
	_check(shape_ok, label + " retains its spawn shape")
	var transform := slot.get_global_transform_with_canvas()
	var bounds := transform * cells[0]
	for rect in cells:
		bounds = bounds.merge(transform * rect)
	var slot_rect := transform * Rect2(Vector2.ZERO, slot.size)
	# 原生 VBoxContainer 将子槽宽度取整，面板宽度可以带小数。
	var center := Vector2(area.get_center().x, slot_rect.get_center().y)
	_check(bounds.get_center().distance_to(center) <= 0.5, label + " stays centered in its panel and row")
	_check(bounds.has_area() and slot_rect.grow(0.05).encloses(bounds) and area.grow(0.05).encloses(bounds) and not bounds.intersects(header), label + " fits without overlapping the title")


func _check_game(game: TetrisCore) -> void:
	var hold_panel: Control = game.get_node("HoldPanel")
	var next_panel: Control = game.get_node("NextPanel")
	var hold_label: Label = hold_panel.get_node("HoldLabel")
	var next_label: Label = next_panel.get_node("NextLabel")
	_check(game.hold_piece.get_cell_rects().is_empty(), "hold starts empty")
	_check(game.next_displays.size() == 5, "five queue slots")
	for window_size: Vector2i in SIZES:
		get_window().size = window_size
		await _settle()
		_check(get_window().size == window_size, "requested window size")
		for type: int in BagRandomizer.ALL_TYPES:
			game._activate_piece(type)
			game.hold_used = false
			game._try_hold()
			_check_slot(game.hold_piece, type, hold_panel.get_global_rect(), hold_label.get_global_rect())
			for i in game.next_displays.size():
				game.bag._queue[i] = (type + i) % BagRandomizer.ALL_TYPES.size()
			game._update_next_display()
			var previous_bottom := next_label.get_global_rect().end.y
			for i in game.next_displays.size():
				var slot := game.next_displays[i]
				_check_slot(slot, game.bag._queue[i], next_panel.get_global_rect(), next_label.get_global_rect())
				_check(slot.get_global_rect().position.y >= previous_bottom - 0.05, "queue rows stay in order and apart")
				previous_bottom = slot.get_global_rect().end.y
	# 移动并收窄面板后，已显示的方块也必须跟随，无需再次换块。
	for panel in [hold_panel, next_panel]:
		panel.position += Vector2(17, 11)
		panel.size *= Vector2(0.85, 1.05)
	await _settle()
	_check_slot(game.hold_piece, game.held_type, hold_panel.get_global_rect(), hold_label.get_global_rect())
	for i in game.next_displays.size():
		_check_slot(game.next_displays[i], game.bag._queue[i], next_panel.get_global_rect(), next_label.get_global_rect())


func _check_replay() -> void:
	var replay: ReplaySystem = preload("res://scenes/ui/replay_system.tscn").instantiate()
	add_child(replay)
	replay.session_list_popup.hide()
	var names := PieceData.Type.keys()
	for type in names.size():
		var upcoming: Array = []
		for i in 5:
			upcoming.append(names[(type + i) % names.size()])
		replay._snapshots.append({"hold_piece": names[type], "next_pieces": upcoming, "piece_type": names[type]})
	replay._build_timeline()
	for window_size: Vector2i in SIZES:
		get_window().size = window_size
		await _settle()
		for type in names.size():
			replay._render_step(type)
			await _settle()
			_check_slot(replay.replay_hold, type, replay.replay_hold.get_global_rect(), replay.get_node("%ReplayHoldLabel").get_global_rect())
			for i in replay.replay_next.get_child_count():
				_check_slot(replay.replay_next.get_child(i), (type + i) % names.size(), replay.replay_next.get_global_rect(), replay.get_node("%ReplayNextLabel").get_global_rect())
			var icon: PiecePreview = replay.timeline_list.get_child(type).get_node("Content/Fields/PieceIcon")
			_check_slot(icon, type, icon.get_global_rect(), Rect2())
	replay._update_previews({})
	_check(replay.replay_previews.is_visible_in_tree() and replay.get_node("%EmptyHold").is_visible_in_tree(), "legacy snapshot without preview fields keeps its empty hold")
	replay._update_previews({"next_pieces": ["Z"]})
	_check(replay.get_node("%EmptyHold").is_visible_in_tree() and replay.replay_hold.get_cell_rects().is_empty(), "missing hold uses its empty state")
	for i in range(1, 5):
		_check(replay.replay_next.get_child(i).get_cell_rects().is_empty(), "short replay queue clears unused slots")
	replay.free()


func _run() -> void:
	for packed: PackedScene in GAMES:
		var game := packed.instantiate() as TetrisCore
		game.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(game)
		game.get_node("BGM").stop()
		await _check_game(game)
		game.free()
	await _check_replay()
	await get_tree().create_timer(0.5).timeout
	print("PIECE_PREVIEW_REGRESSION checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
