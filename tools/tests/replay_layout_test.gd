extends "res://tools/shot/shot_support.gd"

var failures: Array[String] = []
var metrics: Dictionary = {}

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		fail("Expected fixture directory, width, height, locale, theme")
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	root.size = Vector2i(int(args[1]), int(args[2]))
	TranslationServer.set_locale(args[3])
	var ui: Node = root.get_node("UITheme")
	ui.mode = args[4]
	ui._apply_theme()
	_run.call_deferred(args[0])

func _run(fixture_dir: String) -> void:
	var session_path := StorageBudget.data_root().path_join("sessions/session_layout.json")
	var analysis_path := StorageBudget.data_root().path_join("sessions/session_layout_analyzed.json")
	for pair in [["session.json", session_path], ["analyzed.json", analysis_path]]:
		var input := FileAccess.open(fixture_dir.path_join(pair[0]), FileAccess.READ)
		var bytes := input.get_buffer(input.get_length())
		input.close()
		check(StorageBudget.write_atomic(pair[1], bytes, 64_000_000, false) == OK, "isolated fixture write")
	var replay: Node = instantiate_scene("res://scenes/ui/replay_system.tscn")
	root.get_node("UITheme")._on_scene_changed()
	# The regular loading path must find the existing analysis, without starting it.
	replay._load_session("session_layout.json")
	replay.session_list_popup.hide()
	for frame in 45:
		await process_frame
	# The scene's SettingsMenu applies its saved startup settings in _ready.
	# Apply the test matrix afterwards and assert the actual rendered size.
	var args := OS.get_cmdline_user_args()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(int(args[1]), int(args[2]))
	TranslationServer.set_locale(args[3])
	var ui: Node = root.get_node("UITheme")
	ui.mode = args[4]
	ui._apply_theme()
	for frame in 8:
		await process_frame
	check(root.size == Vector2i(int(args[1]), int(args[2])), "requested window size is active")
	check(TranslationServer.get_locale() == args[3] and ui.mode == args[4], "requested locale and theme are active")
	check(not replay._analysis_active, "existing analyzed session loads without analysis")
	replay._timeline_graph.step_selected.emit(12)
	check(replay._current_step == 12, "full-width timeline still selects steps")
	replay.btn_next.pressed.emit()
	check(replay._current_step == 13, "next button retains navigation")
	replay.btn_first.pressed.emit()
	check(replay._current_step == 0, "first button retains navigation")
	replay.btn_last.pressed.emit()
	check(replay._current_step == 374, "last button retains navigation")
	replay._go_to_step(374)
	for frame in 5:
		await process_frame
	var data_scroll: ScrollContainer = replay.data_vbox.get_parent()
	var timeline_scroll: ScrollContainer = replay.timeline_list.get_parent()
	var board_container: Control = replay.replay_board.get_parent()
	var main: Control = replay.get_node("VBoxMain")
	var overview: Control = replay._session_overview_panel
	metrics = {"window": str(root.size), "viewport": str(root.get_visible_rect().size), "main": str(main.get_rect()), "overview_min": str(overview.get_combined_minimum_size()), "left_content": str(replay.data_vbox.size), "left_view": str(data_scroll.size), "timeline_content": str(replay.timeline_list.size), "timeline_view": str(timeline_scroll.size), "board_area": str(board_container.size), "board_scale": str(replay.replay_board.scale)}
	check(not data_scroll.get_h_scroll_bar().visible, "overview has no horizontal scrollbar")
	check(not data_scroll.get_v_scroll_bar().visible, "whole overview and current score fit vertically")
	check(replay.data_vbox.size.x <= data_scroll.size.x + 1, "overview width fits without clipping")
	check(not timeline_scroll.get_h_scroll_bar().visible, "step list has no horizontal scrollbar")
	check(timeline_scroll.get_v_scroll_bar().visible, "375-step list retains vertical scrollbar")
	var timeline_width := timeline_scroll.size.x - timeline_scroll.get_v_scroll_bar().size.x
	check(replay.timeline_list.size.x <= timeline_width + 1, "list width fits vertical scrollbar gutter")
	for row: Control in replay.timeline_list.get_children():
		var fields: Control = row.get_node("Content/Fields")
		for field: Control in fields.get_children():
			check(field.get_global_rect().end.x <= timeline_scroll.get_global_rect().position.x + timeline_width + 1, "step field fully visible: " + str(row.get_index()) + "/" + field.name)
		check(fields.get_node("Score").get_theme_color("font_color") == replay._timeline_row_color(row.get_index()), "existing row colors refresh with theme")
		var tag: Control = row.get_node("Content/Tag")
		check(tag.get_global_rect().end.x <= timeline_scroll.get_global_rect().position.x + timeline_width + 1, "special clear tag fits row")
	check(main.get_global_rect().end.x <= replay.size.x + 1 and main.get_global_rect().end.y <= replay.size.y + 1, "layout stays within viewport")
	var board_bounds := Rect2(replay.replay_board.position + Vector2(-105, -36) * replay.replay_board.scale, Vector2(510, 646) * replay.replay_board.scale)
	check(Rect2(Vector2.ZERO, board_container.size).encloses(board_bounds), "board and previews fit inside board area")
	var footer: Control = replay.get_node("%PlaybackPanel")
	check(footer.size.x >= main.size.x - 1, "bottom timeline spans full window content")
	check(footer.position.y >= replay.get_node("VBoxMain/MainContent").get_rect().end.y, "bottom timeline never overlaps board")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		save_screenshot(OS.get_environment("TETRIS_RUN_DIR").path_join("replay.png"))
	# Resizing must re-fit the existing board without selecting another step.
	var prior_scale: Vector2 = replay.replay_board.scale
	root.size = Vector2i(1280, 900)
	for frame in 6:
		await process_frame
	check(replay._current_step == 374 and replay.replay_board.scale != prior_scale, "resize re-fits board without a step change")
	print(JSON.stringify({"test": "replay_layout", "metrics": metrics, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
