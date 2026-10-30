extends Node

var _failures := 0

func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		_failures += 1

func _run() -> void:
	var replay: Node = load("res://scenes/ui/replay_system.tscn").instantiate()
	add_child(replay)
	replay.session_list_popup.hide()
	var board: Array = []
	for i in range(20):
		var row: Array = []
		row.resize(10)
		row.fill(0)
		board.append(row)
	var snap := {"piece_type": "T", "rotation": 0, "col": 4, "row": 19, "board_state_after_drop": board}
	replay._snapshots = [snap, snap.duplicate(true), snap.duplicate(true)]
	replay._ai_scores = [100, 50, 150]
	replay._ai_details = [
		{"quality": "unknown", "score_loss": 0},
		{"quality": "good", "score_loss": 200},
		{"quality": "best", "score_loss": 0}
	]
	_check(replay._timeline_score_loss(0) == -1, "Unscored AI moves retain an unknown loss")
	_check(is_equal_approx(replay._average_ai_loss(), 100.0), "Unknown moves do not inflate the average AI quality")
	_check(replay._timeline_ai_text(0) == tr("TXT_NA"), "Unknown timeline row never claims BEST")
	replay._update_data_panel(0)
	_check(replay.ai_score_label.text == tr("TXT_NA"), "Unknown detail label never claims AI BEST")
	replay._render_step(0)
	var highlights := 0
	for child in replay.replay_board.get_children():
		if child is Panel:
			highlights += 1
	_check(highlights == 0, "A piece locked in the spawn buffer is not highlighted on the bottom row")
	var graph: ReplayTimelineGraph = replay.get_node("%StepTimelineGraph")
	graph.set_timeline_data([10.0, 20.0], [-1, 0], ["T", "I"], [100, 200])
	_check(not graph._build_tooltip(0).contains("BEST"), "Unknown graph tooltip does not claim BEST")
	graph._update_hover(Vector2.ZERO)
	graph.set_timeline_data([30.0], [0], ["O"], [300])
	_check(graph._hover_step == -1 and graph.tooltip_text.is_empty(), "Replacing timeline data clears the previous hover state")
	graph._update_hover(Vector2.ZERO)
	_check(graph.tooltip_text.contains("O") and graph.tooltip_text.contains("300ms"), "The same hover position now describes the new timeline")
	var radar: RadarChart = replay._session_radar_chart
	for values in [{}, {"speed": 80.0}, {"speed": 80.0, "structure": 80.0}, {"speed": 80.0, "attack": 60.0}, {"speed": 80.0, "efficiency": 60.0, "stability": 40.0}]:
		radar.set_data_immediate(values)
		await get_tree().process_frame
		await get_tree().process_frame
	print("PASS Radar renders empty, line, triangle and separated-axis data")
	replay.free()
	await get_tree().process_frame
	print("REPLAY_DISPLAY_REGRESSION failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
