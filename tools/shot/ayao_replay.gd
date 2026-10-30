extends "res://tools/shot/shot_support.gd"
## Supervised visual fixtures: case, theme, locale; optional motion capture.


func _initialize() -> void:
	super._initialize()
	var store = load("res://scripts/core/storage_budget.gd")
	store.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))


func _start() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var case_name := args[0]
	var file_name := _fixture(case_name == "empty")
	var replay = instantiate_scene("res://scenes/ui/replay_system.tscn")
	replay._load_session(file_name)
	replay.session_list_popup.hide()
	TranslationServer.set_locale(args[2])
	var ui := root.get_node("UITheme")
	ui.mode = args[1]
	ui._apply_theme()
	ui._on_scene_changed()
	match case_name:
		"praise": replay._go_to_step(1)
		"tip": replay._go_to_step(2)
		"compare", "plan", "collapsed": replay._go_to_step(3)
	if case_name == "plan": replay.assistant_panel.plan_button.pressed.emit()
	if case_name == "collapsed": replay.assistant_panel.toggle_button.pressed.emit()
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TETRIS_RUN_DIR")
	if not save_screenshot(output.path_join("screen.png")):
		return
	if args.size() > 3 and args[3] == "motion":
		for frame in 36:
			if frame % 12 == 0:
				replay._go_to_step(1 + int(frame / 12))
			await create_timer(0.08).timeout
			await RenderingServer.frame_post_draw
			if not save_screenshot(output.path_join("motion-%02d.png" % frame)):
				return
	print("AYAO_SCREEN_OK ", case_name, " ", args[1], " ", args[2])
	replay.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0)


func _grid() -> Array:
	var board: Array = []
	for r in 20:
		var row: Array = []
		row.resize(10)
		row.fill(0)
		board.append(row)
	return board


func _fixture(empty: bool = false) -> String:
	var base := _grid()
	for r in range(16, 20):
		for c in 10:
			if c != 8:
				base[r][c] = (c + r) % 7 + 1
	var full := base.duplicate(true)
	for r in range(16, 20): full[r][8] = 1
	var hole := _grid()
	for c in [3, 4, 5]: hole[18][c] = 3
	hole[17][4] = 3
	hole[19][3] = 6
	hole[19][5] = 6
	var boards := [base, _grid(), hole, hole.duplicate(true)]
	var snapshots: Array = []
	for i in 4:
		snapshots.append({"piece_index":i, "piece_type":"I" if i == 1 else "T", "rotation":1 if i == 1 else 0,
			"col":7 if i == 1 else 4, "row":37 if i == 1 else 38,
			"board_state_after_drop":full if i == 1 else boards[i], "board_state_after_clear":boards[i],
			"lines_cleared_this_lock":4 if i == 1 else 0, "damage_this_lock":4 if i == 1 else 0,
			"combo":0, "b2b":0, "next_pieces":["L","S","O","I","J"],"hold_piece":"T",
			"elapsed_since_last_piece_ms":800+i*120})
	var session_id := "2026-10-23T12-00-00_ayao_demo"
	if empty:
		snapshots.clear()
	var session := {"session_id":session_id, "player_name":"AYAO_DEMO", "mode":"marathon", "snapshots":snapshots,
		"pieces_placed":snapshots.size(), "final_score":0 if empty else 1200, "duration_seconds":0.0 if empty else 5.6,
		"final_lines":0 if empty else 4, "total_damage":0 if empty else 4, "tetrises":0 if empty else 1,
		"pps":1.4, "apm":42.0, "app":0.8, "kpp":2.0,
		"radar_scores":{"speed":52,"attack":60,"efficiency":68,"structure":70,"stability":64,"vision":46}}
	var analysis := {"storage_protocol":1,"analysis_revision":2,"session_id":session_id,"ai_model_used":"cold-clear-standard",
		"ai_scores":[100,200,-50,-100],"ai_details":[{"quality":"unknown"},{"quality":"best","score_loss":0},
		{"quality":"good","score_loss":200},{"quality":"mistake","score_loss":650}],
		"recommendations":[null,null,null,{"step":3,"plan":{"steps":[{"placement":{"piece":"T","col":7,"visible_row":19,"rotation":0}}]}}]}
	var store = load("res://scripts/core/storage_budget.gd")
	var path: String = store.data_root().path_join("sessions/session_" + session_id + ".json")
	store.write_atomic(path, JSON.stringify(session).to_utf8_buffer(), 1_000_000, false)
	store.write_atomic(path.replace(".json", "_analyzed.json"), JSON.stringify(analysis).to_utf8_buffer(), 1_000_000, false)
	return path.get_file()
