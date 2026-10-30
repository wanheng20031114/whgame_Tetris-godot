class_name AyaoCoach
extends RefCounted
## Local, deterministic coaching shared by replay and future live practice.
## Text is translated by the caller; facts contain only JSON-compatible values.

const BOARD_COLUMNS := 10
const BOARD_ROWS := 20
const DANGER_HEIGHT := 16
const CLOSE_AI_LOSS := 120.0 # Same threshold as the replay evaluator's excellent tier.
const REVIEW_AI_LOSS := 320.0


static func analyze_step(snapshot: Dictionary, previous: Dictionary = {}, ai_detail: Dictionary = {}, recommendation: Dictionary = {}) -> Dictionary:
	var facts := _collect_facts(snapshot, previous, ai_detail, recommendation)
	if not facts["has_board"]:
		return _message("observe", "NO_BOARD", [], "REVIEW_RESULT", facts)

	var metrics: Dictionary = facts["board_metrics"]
	var height := int(metrics["max_height"])
	var holes := int(metrics["holes"])
	var clear_count := int(facts.get("lines_cleared_this_lock", 0))
	var advice := "UNCOVER" if holes > 0 else "LOOK_AHEAD"

	# Urgent board conditions take precedence over a high score or a stylish clear.
	if height >= DANGER_HEIGHT:
		return _message("tip", "DANGER", [height, BOARD_ROWS], "LOWER_STACK", facts)
	if facts.has("holes_delta"):
		var delta := int(facts["holes_delta"])
		if delta > 0:
			return _message("tip", "NEW_HOLES", [delta, holes], "AVOID_COVERING", facts)
		if delta < 0:
			return _message("praise", "FEWER_HOLES", [-delta, holes], advice, facts)

	if clear_count > 0 and height == 0:
		return _message("praise", "PERFECT_CLEAR", [], "LOOK_AHEAD", facts)
	if clear_count > 0 and bool(facts.get("is_t_spin", false)):
		return _message("praise", "T_SPIN", [clear_count], _clear_advice(facts, advice), facts)
	if clear_count == 4:
		return _message("praise", "TETRIS", [], _clear_advice(facts, advice), facts)
	if clear_count > 0 and int(facts.get("combo", 0)) > 0:
		# Scoring.combo is zero-based: 1 means two consecutive clearing placements.
		return _message("praise", "COMBO", [int(facts["combo"]) + 1], advice, facts)
	if clear_count > 0 and int(facts.get("damage_this_lock", 0)) > 0:
		return _message("praise", "CLEAR_ATTACK", [clear_count, int(facts["damage_this_lock"])], _clear_advice(facts, advice), facts)
	if facts.has("ai_score_loss"):
		var loss := float(facts["ai_score_loss"])
		if loss > REVIEW_AI_LOSS and facts["has_ai_plan"]:
			return _message("tip", "COMPARE_PLAN", [], "OPEN_PLAN", facts)
		if loss <= CLOSE_AI_LOSS:
			return _message("praise", "CLOSE_TO_BEST", [], advice, facts)
	if holes > 0:
		return _message("tip", "BURIED_HOLES", [holes], "UNCOVER", facts)
	if int(metrics["bumpiness"]) >= 12:
		return _message("tip", "ROUGH_SURFACE", [], "SMOOTH_SURFACE", facts)
	if clear_count > 0:
		return _message("praise", "CLEAR", [clear_count], advice, facts)
	if height <= 6 and int(metrics["bumpiness"]) <= 6:
		return _message("observe", "CLEAN_SURFACE", [], advice, facts)
	return _message("observe", "PLACED", [height], advice, facts)


static func _message(kind: String, topic: String, body_args: Array, advice: String, facts: Dictionary) -> Dictionary:
	return {
		"kind": kind,
		"title_key": "TXT_AYAO_TITLE_" + kind.to_upper(),
		"body_key": "TXT_AYAO_" + topic,
		"body_args": body_args,
		"advice_key": "TXT_AYAO_ADVICE_" + advice,
		"advice_args": [],
		"facts": facts,
	}


static func _clear_advice(facts: Dictionary, otherwise: String) -> String:
	return "KEEP_B2B" if int(facts.get("b2b", 0)) > 0 else otherwise


static func _collect_facts(snapshot: Dictionary, previous: Dictionary, ai_detail: Dictionary, recommendation: Dictionary) -> Dictionary:
	var facts := {"schema_version": 1, "source": "local_rules", "has_board": false, "has_ai_plan": false}
	# Preserve missing fields as missing: an absent result is not a recorded zero.
	for key in ["piece_index", "piece_type", "rotation", "col", "row", "lines_cleared_this_lock", "damage_this_lock", "combo", "b2b", "is_t_spin", "is_spin", "hold_used", "hold_piece", "next_pieces"]:
		if snapshot.has(key):
			facts[key] = snapshot[key].duplicate(true) if snapshot[key] is Array else snapshot[key]
	var board := _after_clear_board(snapshot)
	if not board.is_empty():
		facts["has_board"] = true
		facts["board_phase"] = "after_clear"
		facts["board_after_clear"] = board
		facts["board_metrics"] = _board_metrics(board)
		var previous_board := _after_clear_board(previous)
		var consecutive := not snapshot.has("piece_index") or not previous.has("piece_index") or int(snapshot["piece_index"]) == int(previous["piece_index"]) + 1
		if not previous_board.is_empty() and consecutive:
			var previous_metrics := _board_metrics(previous_board)
			facts["previous_board_metrics"] = previous_metrics
			facts["holes_delta"] = int(facts["board_metrics"]["holes"]) - int(previous_metrics["holes"])
			facts["height_delta"] = int(facts["board_metrics"]["max_height"]) - int(previous_metrics["max_height"])
	var loss: Variant = ai_detail.get("score_loss")
	if str(ai_detail.get("quality", "")) != "unknown" and (loss is int or loss is float) and is_finite(float(loss)):
		facts["ai_score_loss"] = maxf(0.0, float(loss))
	# Recommendations refer to the decision before this piece was locked.
	# Expose availability, never mistake a future plan board for the played result.
	var plan: Variant = recommendation.get("plan")
	if plan is Dictionary:
		var steps: Variant = plan.get("steps")
		facts["has_ai_plan"] = steps is Array and not steps.is_empty()
	return facts


static func _after_clear_board(snapshot: Dictionary) -> Array:
	if snapshot.has("board_state_after_clear"):
		var after_clear: Variant = snapshot["board_state_after_clear"]
		return after_clear.duplicate(true) if _valid_board(after_clear) else []
	# Old replays may only retain the locked board. Resolve full rows explicitly so
	# a completed line cannot be mistaken for the terrain left for the next piece.
	for key in ["board_state_after_drop", "board_state"]:
		if not snapshot.has(key):
			continue
		var locked: Variant = snapshot[key]
		if not _valid_board(locked):
			return []
		var result: Array = []
		for row in locked:
			if row.has(0):
				result.append(row.duplicate())
		while result.size() < BOARD_ROWS:
			var empty_row: Array = []
			empty_row.resize(BOARD_COLUMNS)
			empty_row.fill(0)
			result.push_front(empty_row)
		return result
	return []


static func _valid_board(value: Variant) -> bool:
	if not value is Array or value.size() != BOARD_ROWS:
		return false
	for row in value:
		if not row is Array or row.size() != BOARD_COLUMNS:
			return false
		for cell in row:
			if not (cell is int or cell is float):
				return false
	return true


static func _board_metrics(board: Array) -> Dictionary:
	var heights: Array[int] = []
	var holes := 0
	var total_height := 0
	var max_height := 0
	var bumpiness := 0
	for column in BOARD_COLUMNS:
		var height := 0
		for row in BOARD_ROWS:
			if int(board[row][column]) != 0:
				if height == 0:
					height = BOARD_ROWS - row
			elif height > 0:
				holes += 1
		heights.append(height)
		total_height += height
		max_height = maxi(max_height, height)
		if column > 0:
			bumpiness += absi(height - heights[column - 1])
	return {"holes": holes, "max_height": max_height, "bumpiness": bumpiness, "total_height": total_height, "column_heights": heights}
