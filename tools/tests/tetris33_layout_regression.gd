extends Node

## Run only through tools/safe_run.py in a marked isolated project copy.
## These checks use scene geometry and live attack endpoints, not layout formulas.
const PLAYER_COUNTS := [3, 4, 8, 9, 10, 17, 32, 33]
const GAME_SCENE := preload("res://scenes/tetris33_game.tscn")

var _checks := 0
var _failures := 0


func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures += 1


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _make_game(player_count: int) -> Tetris33Game:
	var game := GAME_SCENE.instantiate() as Tetris33Game
	game.active_player_count = player_count
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	game.bgm.stop()
	return game


func _canvas_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _center(panel: Control) -> Vector2:
	return panel.get_global_transform_with_canvas() * (panel.size * 0.5)


func _visible_side(game: Tetris33Game, side_name: String) -> Array[Tetris33OpponentPanel]:
	var result: Array[Tetris33OpponentPanel] = []
	for child in game.get_node(side_name).get_children():
		if child is Tetris33OpponentPanel and child.is_visible_in_tree():
			result.append(child)
	return result


func _distinct_positions(panels: Array[Tetris33OpponentPanel], horizontal: bool) -> int:
	var positions: Array[float] = []
	for panel in panels:
		var coordinate := _canvas_rect(panel).position.x if horizontal else _canvas_rect(panel).position.y
		var found := false
		for existing in positions:
			if absf(existing - coordinate) < 0.1:
				found = true
				break
		if not found:
			positions.append(coordinate)
	return positions.size()


func _check_layout(game: Tetris33Game, player_count: int) -> void:
	var prefix := "%d players: " % player_count
	var left := _visible_side(game, "%OpponentLeftGrid")
	var right := _visible_side(game, "%OpponentRightGrid")
	var visible: Array[Tetris33OpponentPanel] = left + right
	_check(visible.size() == player_count - 1, prefix + "exactly one visible panel per opponent")
	_check(absi(left.size() - right.size()) <= 1, prefix + "opponents are balanced across both sides")
	_check(game._opponents.size() == visible.size(), prefix + "sample count matches visible panels")
	var mapping_ok := true
	var bounds_ok := true
	var board_clear := true
	var previews_fit := true
	var panels_disjoint := true
	var ids: Array[int] = []
	for i in range(game._opponents.size()):
		var panel := game._opponent_panels[i]
		mapping_ok = mapping_ok and panel.is_visible_in_tree() and panel.opponent_index == i
		mapping_ok = mapping_ok and int(game._opponents[i]["index"]) == i and not ids.has(panel.get_instance_id())
		ids.append(panel.get_instance_id())
	for panel in visible:
		var rect := _canvas_rect(panel)
		var side_rect := _canvas_rect(panel.get_parent() as Control)
		bounds_ok = bounds_ok and side_rect.grow(0.1).encloses(rect)
		board_clear = board_clear and not rect.intersects(game._board_canvas_rect())
		var board_rect := panel.preview_board.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, Vector2(panel.preview_board.columns, panel.preview_board.visible_rows) * panel.preview_board.cell_size)
		previews_fit = previews_fit and rect.grow(0.1).encloses(board_rect)
		previews_fit = previews_fit and rect.grow(0.1).encloses(_canvas_rect(panel.name_label))
	for i in range(visible.size()):
		for j in range(i + 1, visible.size()):
			panels_disjoint = panels_disjoint and not _canvas_rect(visible[i]).intersects(_canvas_rect(visible[j]))
	_check(mapping_ok, prefix + "active indices map one-to-one to actual visible scene panels")
	_check(bounds_ok, prefix + "panels stay inside their side regions")
	_check(board_clear, prefix + "panels never intrude into the local board")
	_check(previews_fit, prefix + "preview boards and name labels stay inside their panels")
	_check(panels_disjoint, prefix + "opponent panels never overlap")
	if player_count in [3, 9, 33]:
		var expected_axis := 1 if player_count == 3 else (2 if player_count == 9 else 4)
		_check(_distinct_positions(left, true) == expected_axis and _distinct_positions(left, false) == expected_axis, prefix + "left side has the requested square grid")
		_check(_distinct_positions(right, true) == expected_axis and _distinct_positions(right, false) == expected_axis, prefix + "right side has the requested square grid")


func _check_incoming(game: Tetris33Game, label: String) -> void:
	var layer := game.get_node("AttackFXLayer")
	var previous := layer.get_child_count()
	game._receive_attack(2)
	_check(layer.get_child_count() == previous + 1, label + "incoming attack creates its projectile")
	if layer.get_child_count() <= previous:
		return
	var fx := layer.get_child(previous) as AttackFX
	var origin_matches := false
	for i in range(game._opponents.size()):
		if not bool(game._opponents[i]["eliminated"]):
			var panel := game._opponent_panels[i]
			origin_matches = origin_matches or (panel.is_visible_in_tree() and fx._p0.distance_to(_center(panel)) < 0.1)
	_check(origin_matches, label + "incoming attack starts at a visible surviving panel center")
	fx.free()


func _check_ko_and_attack(game: Tetris33Game, player_count: int) -> void:
	var prefix := "%d players: " % player_count
	var before: Dictionary = {}
	for panel in game._opponent_panels:
		if panel.is_visible_in_tree():
			before[panel.get_instance_id()] = _canvas_rect(panel)
	_check_incoming(game, prefix)
	for panel in _visible_side(game, "%OpponentLeftGrid"):
		game._eliminate_opponent(panel.opponent_index)
	await _settle()
	var stable := true
	for i in range(game._opponents.size()):
		var panel := game._opponent_panels[i]
		stable = stable and panel.is_visible_in_tree() and panel.opponent_index == i
		stable = stable and before.has(panel.get_instance_id()) and _canvas_rect(panel).is_equal_approx(before[panel.get_instance_id()])
	_check(stable, prefix + "KO preserves opponent identity and panel position")
	_check_incoming(game, prefix + "after all left opponents are KO, ")
	var layer := game.get_node("AttackFXLayer")
	game._send_attack_to_target(1)
	var target := game._last_target_index
	await _settle()
	var fx := layer.get_child(0) as AttackFX if layer.get_child_count() > 0 else null
	_check(fx != null and target >= 0 and not bool(game._opponents[target]["eliminated"]) and fx._p3.distance_to(_center(game._opponent_panels[target])) < 0.1, prefix + "outgoing projectile reaches the selected surviving panel center")
	if fx != null and target >= 0:
		var panel := game._opponent_panels[target]
		var rest_rect := _canvas_rect(panel)
		fx._impact()
		var pulse := panel.get_meta(UITheme.META_MOTION_TWEEN) as Tween
		pulse.pause()
		pulse.custom_step(0.08)
		_check(panel.scale.x > 1.0, prefix + "projectile impact still triggers the opponent pulse")
		pulse.custom_step(0.31)
		_check(panel.scale.is_equal_approx(Vector2.ONE) and _canvas_rect(panel).is_equal_approx(rest_rect), prefix + "impact pulse restores the mode-specific panel geometry")


func _check_network_mapping() -> void:
	NetworkManager.current_room_mode = "tetris33"
	NetworkManager.tetris33_player_count = 9
	NetworkManager.tetris33_local_slot = 5
	NetworkManager.my_id = "layout-player-5"
	NetworkManager.tetris33_players = []
	for slot in range(1, 10):
		NetworkManager.tetris33_players.append({"slot": slot, "id": "layout-player-%d" % slot, "name": "Player %d" % slot})
	var game := _make_game(33)
	await _settle()
	_check(game.active_player_count == 9, "Network roster selects the nine-player layout at scene startup")
	_check_layout(game, 9)
	var target_id := "layout-player-9"
	var target_index := game._network_opponent_ids.find(target_id)
	game._on_network_sample_received({"from_id": target_id, "from_name": "Updated right-side player", "pending_garbage": 3})
	_check(target_index >= 0 and game._opponent_panels[target_index].name_label.text == "Updated right-side player", "Network sample updates the panel mapped to the player ID")
	game._on_network_game_over_received({"from_id": target_id, "rank": 9})
	_check(game._opponent_panels[target_index].ko_label.visible and game._opponent_panels[target_index].is_visible_in_tree(), "Network KO marks the mapped panel without removing it")
	game.free()
	NetworkManager.current_room_mode = "versus"
	NetworkManager.tetris33_player_count = 0
	NetworkManager.tetris33_players = []
	NetworkManager.my_id = ""
	NetworkManager.tetris33_local_slot = 1
	await _settle()


func _run() -> void:
	NetworkManager.current_room_mode = "versus"
	for player_count in PLAYER_COUNTS:
		var game := _make_game(player_count)
		await _settle()
		_check_layout(game, player_count)
		await _check_ko_and_attack(game, player_count)
		game.free()
		await _settle()
	await _check_network_mapping()
	# Ogg playback releases on the AudioServer mix tick after the scenes are freed.
	await get_tree().create_timer(0.5).timeout
	print("TETRIS33_LAYOUT_REGRESSION checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
