extends "res://tools/shot/shot_support.gd"

var failures: Array[String] = []


func _start() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)


func settle() -> void:
	for frame in 4:
		await process_frame


func bounds(control: Control, outset: float = 0.0) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size).grow(outset)


func _run() -> void:
	root.get_node("GameState").player_name = "LAYOUT"
	change_scene_to_file("res://scenes/ui/main.tscn")
	await scene_changed
	await create_timer(0.5).timeout
	var lobby = current_scene._main_lobby
	lobby.card_guide.grab_focus()
	await create_timer(0.3).timeout
	for card in lobby._cards:
		var tray: PanelContainer = card.preview_tray
		check(bounds(tray).grow(-8).encloses(bounds(tray.get_node("Glyph"))), "tile preview " + str(card.name))
	lobby._activate_mode(lobby.card_guide, "guide")
	await scene_changed
	var guide = current_scene
	var options: Array = load("res://scripts/ui/settings_menu.gd").RESOLUTION_OPTIONS
	for idx in options.size():
		var option: Dictionary = options[idx]
		root.size = Vector2i(option.width, option.height)
		TranslationServer.set_locale(["zh", "en", "ja"][idx % 3])
		for i in guide.chapters.size():
			(guide.chapters_list.get_child(i) as Button).pressed.emit()
			await settle()
			var board = guide.board_view
			var panel: Control = guide.content_root.get_child(0).get_node("DemoPanel")
			var well: Rect2 = board._board_rect()
			var frame: Rect2 = board.get_global_transform() * well.grow(board.FRAME_PADDING + board.FOCUSED_FRAME_WIDTH * 0.5)
			check(root.size == Vector2i(option.width, option.height), "window " + option.id)
			check(root.get_visible_rect().grow(1).encloses(bounds(panel)), "demo panel " + option.id)
			check(bounds(board).encloses(frame) and bounds(panel).encloses(frame), "complete frame " + option.id)
			check(well.size.y >= 300.0 and is_equal_approx(well.size.x * 2, well.size.y), "readable 10 x 20 board " + option.id)
			if idx == 0:
				_check_motion(guide, board)
	guide._start_simulation("wallkick", 0)
	await settle()
	check(guide.board_view.has_focus(), "simulation keyboard focus")
	var sim_frame: Rect2 = guide.board_view.get_global_transform() * guide.board_view._board_rect().grow(12)
	check(bounds(guide.board_view).grow(0.1).encloses(sim_frame), "simulation frame")
	root.content_scale_size = Vector2i(960, 540)
	root.size = Vector2i(960, 540)
	guide._show_chapter(0)
	await settle()
	var compact: Control = guide.content_root.get_child(0).get_node("DemoPanel")
	check(root.get_visible_rect().grow(1).encloses(bounds(compact)), "short viewport demo panel")
	check(guide.board_view._board_rect().size.y > 220, "short viewport keeps all twenty rows readable")
	guide._stop_demo_animation()
	unload_current_scene()
	await settle()
	await _check_picker()
	unload_current_scene()
	await settle()
	print(JSON.stringify({"test": "guide_replay_fit", "resolutions": options.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check_motion(guide: Node, board: Control) -> void:
	var playfield := Rect2(Vector2.ZERO, Vector2(board.columns, board.rows))
	for phase in (5 if guide.sim_id == "combo" else 1):
		var runner := GuideScenarioRunner.new()
		runner.setup(guide.sim_id, phase)
		var demo: Dictionary = guide._build_demo_sequence(runner)
		for frame in demo.frames:
			for fraction in [0.0, 0.25, 0.5, 0.525, 0.55, 0.75, 1.0]:
				guide._demo_interpolate_piece(fraction, frame.grid, frame.from, frame.to, [], [], [])
				for pose: Dictionary in [board.active_piece, board._other_turn_pose]:
					if pose.is_empty():
						continue
					for offset: Vector2 in PieceData.SHAPES[pose.type][pose.rot]:
						var cell := Rect2(Vector2(pose.col, pose.row) + offset, Vector2.ONE)
						check(playfield.encloses(cell), "%s crosses the board on %s" % [guide.sim_id, frame.label])


func _check_picker() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	PlayerDataStore.ensure_data_dirs()
	var fixture_paths: Array[String] = []
	var prefix := "session_fit_%s_" % Time.get_ticks_usec()
	for i in 22:
		var name := prefix + ("%02d.json" % i)
		if i == 21:
			name = prefix + "长存档名".repeat(18) + ".json"
		var path := PlayerDataStore.get_sessions_dir().path_join(name)
		fixture_paths.append(path)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	change_scene_to_file("res://scenes/ui/replay_system.tscn")
	await scene_changed
	await create_timer(0.8).timeout
	var replay = current_scene
	var scroll: ScrollContainer = replay.session_scroll
	var list: VBoxContainer = replay.session_list
	check(scroll.get_v_scroll_bar().visible, "scrollable session fixture")
	for idx in [0, 10, list.get_child_count() - 1, 0]:
		var button: Button = list.get_child(idx).get_node("SessionButton")
		button.grab_focus()
		await settle()
		button.button_down.emit()
		await create_timer(0.1).timeout
		button.button_up.emit()
		var largest_scale := 0.0
		for tick in 28:
			await process_frame
			var visible_area := bounds(scroll)
			visible_area.end.x = bounds(scroll.get_v_scroll_bar()).position.x
			var style := button.get_theme_stylebox("focus") as StyleBoxFlat
			var ring := Rect2(Vector2.ZERO, button.size).grow_individual(style.expand_margin_left,
					style.expand_margin_top, style.expand_margin_right, style.expand_margin_bottom)
			check(visible_area.grow(0.5).encloses(button.get_global_transform() * ring), "replay focus ring " + str(idx))
			largest_scale = maxf(largest_scale, button.scale.x)
		check(largest_scale > 1.04, "replay zoom preserved")
	for path in fixture_paths:
		DirAccess.remove_absolute(path)
