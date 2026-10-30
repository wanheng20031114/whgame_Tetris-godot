class_name ReplaySchema
extends RefCounted
## Validate persisted replay data once, before it reaches typed UI/coach code.
## Missing optional fields remain supported for older sessions.

const SESSION_NUMBERS := ["final_score", "final_level", "duration_seconds", "pieces_placed", "final_lines", "total_damage", "total_key_presses", "tetrises", "t_spin_clears", "spin_clears", "discarded_snapshots", "max_combo", "max_b2b", "singles", "doubles", "triples", "pps", "apm", "app", "kpp"]
const SNAPSHOT_NUMBERS := ["piece_index", "rotation", "col", "row", "lines_cleared_this_lock", "lines_cleared", "damage_this_lock", "combo", "b2b", "elapsed_since_last_piece_ms", "holes", "bumpiness", "total_height", "complexity", "board_complexity"]


static func valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 1e12


static func _numbers(data: Dictionary, keys: Array) -> bool:
	for key in keys:
		if data.has(key) and not valid_number(data[key]):
			return false
	return true


static func valid_session(data: Variant) -> bool:
	if not data is Dictionary or not data.get("snapshots") is Array:
		return false
	if data.snapshots.size() > PlayerDataCollector.MAX_SNAPSHOTS or not _numbers(data, SESSION_NUMBERS):
		return false
	for key in ["session_id", "player_name"]:
		if data.has(key) and not data[key] is String:
			return false
	if data.has("radar_scores"):
		if not data.radar_scores is Dictionary:
			return false
		for value in data.radar_scores.values():
			if not valid_number(value):
				return false
	for snapshot in data.snapshots:
		if not valid_snapshot(snapshot):
			return false
	return true


static func valid_snapshot(snapshot: Variant) -> bool:
	if not snapshot is Dictionary or not _numbers(snapshot, SNAPSHOT_NUMBERS):
		return false
	for key in ["is_spin", "is_t_spin", "hold_used"]:
		if snapshot.has(key) and not snapshot[key] is bool:
			return false
	for key in ["piece_type", "hold_piece"]:
		if snapshot.has(key) and not snapshot[key] is String:
			return false
	for key in ["board_state", "board_state_after_drop", "board_state_after_clear"]:
		if not snapshot.has(key):
			continue
		var cells: Variant = snapshot[key]
		if not cells is Array or (not cells.is_empty() and cells.size() != 20):
			return false
		for row in cells:
			if not row is Array or row.size() != 10:
				return false
			for value in row:
				if not valid_number(value) or value != floor(value) or value < 0 or value > 8:
					return false
	if snapshot.has("next_pieces"):
		if not snapshot.next_pieces is Array:
			return false
		for piece in snapshot.next_pieces:
			if not piece is String:
				return false
	return true


static func valid_analysis(data: Variant, session_id: String, steps: int) -> bool:
	if not data is Dictionary:
		return false
	if not valid_number(data.get("storage_protocol")) or data.storage_protocol != 1:
		return false
	if not valid_number(data.get("analysis_revision")) or data.analysis_revision != 2:
		return false
	if not data.get("ai_model_used") is String or data.ai_model_used != "cold-clear-standard":
		return false
	if not data.get("session_id") is String or data.session_id != session_id:
		return false
	for key in ["ai_scores", "ai_details", "recommendations"]:
		if not data.get(key) is Array or data[key].size() != steps:
			return false
	for score in data.ai_scores:
		if not valid_number(score):
			return false
	for detail in data.ai_details:
		if not detail is Dictionary or not _numbers(detail, ["score_loss"]):
			return false
		if detail.has("quality") and not detail.quality is String:
			return false
		if detail.get("best") != null and not _valid_plan_step(detail.best):
			return false
	for recommendation in data.recommendations:
		if recommendation == null:
			continue
		if not recommendation is Dictionary or not _numbers(recommendation, ["step"]):
			return false
		if recommendation.get("plan") == null:
			continue
		var plan: Variant = recommendation.plan
		if not plan is Dictionary or not plan.get("steps") is Array:
			return false
		for step in plan.steps:
			if not _valid_plan_step(step):
				return false
	return true


static func _valid_plan_step(step: Variant) -> bool:
	if not step is Dictionary or not step.get("placement") is Dictionary:
		return false
	var placement: Dictionary = step.placement
	if not _numbers(placement, ["rotation", "col", "row", "visible_row"]):
		return false
	if placement.has("piece") and not placement.piece is String:
		return false
	if step.get("lock") != null:
		if not step.lock is Dictionary or not step.lock.get("cleared_lines", []) is Array:
			return false
		var seen: Array = []
		for row in step.lock.get("cleared_lines", []):
			if not valid_number(row) or row != floor(row) or row < 0 or row >= 40 or row in seen:
				return false
			seen.append(row)
	return true
