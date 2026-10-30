extends Node

const Coach = preload("res://scripts/ai/ayao_coach.gd")
var _failures := 0
var _checks := 0


func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		_failures += 1


func _grid() -> Array:
	var board: Array = []
	for _r in 20:
		var row: Array = []
		row.resize(10)
		row.fill(0)
		board.append(row)
	return board


func _filled(columns: Array) -> Array:
	var board := _grid()
	for c in columns.size():
		for r in int(columns[c]):
			board[19 - r][c] = 1
	return board


func _snapshot(board: Array, extra: Dictionary = {}) -> Dictionary:
	var result := {"board_state_after_clear": board, "piece_type": "T", "lines_cleared_this_lock": 0}
	result.merge(extra, true)
	return result


func _run() -> void:
	var low := _filled([2, 2, 2, 2, 2, 2, 2, 2, 1, 0])
	var low_snapshot := _snapshot(low)
	var no_data := Coach.analyze_step({})
	_check(no_data.kind == "observe" and no_data.body_key == "TXT_AYAO_NO_BOARD", "Absent boards produce no invented terrain judgment")
	_check(not no_data.facts.has("ai_score_loss") and not no_data.facts.has("board_metrics"), "Missing facts remain absent")
	_check(not no_data.facts.has("damage_this_lock"), "Unrecorded damage is not synthesized as zero")
	var baseline := Coach.analyze_step(low_snapshot)
	_check(baseline.kind == "observe" and baseline.body_key == "TXT_AYAO_CLEAN_SURFACE", "A normal unscored placement gets a neutral observation")
	_check(not baseline.facts.has("holes_delta"), "First step never claims a change without a previous board")
	_check(baseline.facts.board_metrics.max_height == 2 and baseline.facts.board_metrics.holes == 0, "Board metrics reflect the actual board")
	_check(baseline.facts.board_metrics.bumpiness == 2, "Adjacent-column bumpiness is calculated correctly")

	for detail in [{}, {"score_loss": null}, {"score_loss": 0, "quality": "unknown"}, {"score_loss": "0"}, {"score_loss": NAN}, {"score_loss": INF}]:
		var unknown := Coach.analyze_step(low_snapshot, {}, detail)
		_check(unknown.kind != "praise" and not unknown.facts.has("ai_score_loss"), "Unknown/invalid AI score never claims a best move: " + str(detail))
	var best := Coach.analyze_step(low_snapshot, {}, {"quality": "best", "score_loss": 0})
	_check(best.body_key == "TXT_AYAO_CLOSE_TO_BEST", "A verified zero-loss move receives qualified local-evaluation praise")
	_check(Coach.analyze_step(low_snapshot, {}, {"score_loss": 120}).kind == "praise", "Excellent threshold matches the current replay analyzer")
	_check(Coach.analyze_step(low_snapshot, {}, {"score_loss": 121}).kind == "observe", "The excellent threshold does not overpraise larger losses")
	_check(Coach.analyze_step(low_snapshot, {}, {"score_loss": -1}).facts.ai_score_loss == 0, "Better-than-search results normalize loss consistently with replay")

	var hole_board := low.duplicate(true)
	hole_board[19][1] = 0
	var added := Coach.analyze_step(_snapshot(hole_board), low_snapshot)
	_check(added.body_key == "TXT_AYAO_NEW_HOLES" and added.body_args == [1, 1], "New buried gaps are reported with measured counts")
	var removed := Coach.analyze_step(low_snapshot, _snapshot(hole_board))
	_check(removed.body_key == "TXT_AYAO_FEWER_HOLES" and removed.body_args == [1, 0], "Closing a buried gap receives factual praise")
	_check(Coach.analyze_step(_snapshot(hole_board)).body_key == "TXT_AYAO_BURIED_HOLES", "An existing gap is not blamed on the first available move")
	_check(not Coach.analyze_step(_snapshot(hole_board, {"piece_index": 5}), _snapshot(low, {"piece_index": 1})).facts.has("holes_delta"), "Non-consecutive snapshot indices do not produce move deltas")
	_check(Coach.analyze_step(_snapshot(hole_board, {"piece_index": 2}), _snapshot(low, {"piece_index": 1})).facts.holes_delta == 1, "Consecutive snapshot indices permit accurate deltas")

	var tall := _filled([16, 15, 14, 13, 12, 11, 10, 9, 8, 0])
	var danger := Coach.analyze_step(_snapshot(tall, {"lines_cleared_this_lock": 4}), {}, {"score_loss": 0})
	_check(danger.body_key == "TXT_AYAO_DANGER" and danger.kind == "tip", "Dangerous height takes priority over clear and AI-score praise")
	_check(danger.body_args == [16, 20], "Danger feedback reports visible stack height and board limit")
	var perfect := Coach.analyze_step(_snapshot(_grid(), {"lines_cleared_this_lock": 4}))
	_check(perfect.body_key == "TXT_AYAO_PERFECT_CLEAR", "An actual clear that empties the board gets perfect-clear praise")
	_check(Coach.analyze_step(_snapshot(_grid())).body_key != "TXT_AYAO_PERFECT_CLEAR", "An empty board without a recorded clear does not invent perfect clear")
	_check(Coach.analyze_step(_snapshot(low, {"lines_cleared_this_lock": 4})).body_key == "TXT_AYAO_TETRIS", "Four-line clear gets Tetris feedback")
	_check(Coach.analyze_step(_snapshot(low, {"lines_cleared_this_lock": 2, "is_t_spin": true})).body_key == "TXT_AYAO_T_SPIN", "Recorded T-Spin clear gets specific feedback")
	_check(Coach.analyze_step(_snapshot(low, {"is_t_spin": true})).body_key != "TXT_AYAO_T_SPIN", "A spin without clearing lines does not claim a clear")
	var chain := Coach.analyze_step(_snapshot(low, {"lines_cleared_this_lock": 1, "combo": 1}))
	_check(chain.body_key == "TXT_AYAO_COMBO" and chain.body_args == [2], "Zero-based combo 1 means two consecutive clearing placements")
	_check(Coach.analyze_step(_snapshot(low, {"combo": 3})).body_key != "TXT_AYAO_COMBO", "A stale combo counter without a current clear gets no combo praise")
	_check(Coach.analyze_step(_snapshot(low, {"lines_cleared_this_lock": 4, "b2b": 1})).advice_key == "TXT_AYAO_ADVICE_KEEP_B2B", "A real back-to-back clear receives chain advice")
	_check(Coach.analyze_step(_snapshot(low, {"lines_cleared_this_lock": 4, "b2b": 0})).advice_key != "TXT_AYAO_ADVICE_KEEP_B2B", "First difficult clear does not claim an established back-to-back chain")
	var attack := Coach.analyze_step(_snapshot(low, {"lines_cleared_this_lock": 2, "damage_this_lock": 1}))
	_check(attack.body_key == "TXT_AYAO_CLEAR_ATTACK" and attack.body_args == [2, 1], "Recorded attack is described as generated damage rather than delivered damage")

	var plan := {"plan": {"steps": [{"placement": {"piece": "I", "col": 9, "visible_row": 19, "rotation": 1}}]}}
	var comparison := Coach.analyze_step(low_snapshot, {}, {"score_loss": 400}, plan)
	_check(comparison.body_key == "TXT_AYAO_COMPARE_PLAN" and comparison.advice_key == "TXT_AYAO_ADVICE_OPEN_PLAN", "A high-loss move with a plan gets an actionable comparison")
	_check(Coach.analyze_step(low_snapshot, {}, {"score_loss": 400}, {"plan": null}).body_key != "TXT_AYAO_COMPARE_PLAN", "A legal null recommendation never tells players to open a missing plan")
	_check(Coach.analyze_step(low_snapshot, {}, {}, plan).kind == "observe", "Plan availability alone is not evidence of a mistake")

	var locked := low.duplicate(true)
	locked[19].fill(1)
	var phases := Coach.analyze_step({"board_state_after_drop": locked, "board_state_after_clear": low, "holes": 99})
	_check(phases.facts.board_metrics.holes == 0 and phases.facts.board_after_clear == low, "After-clear board wins over locked board and stale recorded metrics")
	var legacy := Coach.analyze_step({"board_state_after_drop": locked})
	_check(legacy.facts.board_metrics.max_height == 1, "Legacy locked boards resolve full rows before terrain analysis")
	_check(legacy.facts.board_phase == "after_clear", "API facts identify the analyzed board phase explicitly")
	_check(Coach.analyze_step({"board_state_after_clear": [[1, 0]]}).kind == "observe", "Incomplete board is handled without constructing fictitious cells")

	var source := _snapshot(hole_board, {"next_pieces": ["I", "O"], "damage_this_lock": 2})
	var before := JSON.stringify(source)
	var immutable := Coach.analyze_step(source, low_snapshot, {"score_loss": 500}, plan)
	_check(JSON.stringify(source) == before, "Coaching never mutates recorded snapshots")
	immutable.facts.board_after_clear[0][0] = 6
	immutable.facts.next_pieces[0] = "Z"
	_check(JSON.stringify(source) == before, "Returned facts do not alias snapshot board or next-piece arrays")
	_check(JSON.parse_string(JSON.stringify(immutable.facts)) is Dictionary, "Coaching facts serialize as JSON for future API requests")
	_check(immutable.facts.damage_this_lock == 2, "Recorded attack damage is retained as an API fact")

	print("AYAO_COACH_REGRESSION checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
