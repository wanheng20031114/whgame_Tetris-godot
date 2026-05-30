class_name Tetris33Game
extends TetrisCore

@export_group("Tetris33 Match")
@export_range(3, 33, 1) var active_player_count: int = 33
@export_range(3, 33, 1) var min_players_to_start: int = 3
@export_range(0.0, 1.0, 0.05) var random_target_weight: float = 0.60
@export_range(0.0, 1.0, 0.05) var least_dangerous_target_weight: float = 0.40
@export var bot_attack_min_seconds: float = 5.0
@export var bot_attack_max_seconds: float = 12.0
@export var opponent_sample_seconds: float = 0.85
@export var ko_pressure_seconds: float = 9.0

@onready var player_garbage_bar: GarbageBar = %PlayerGarbageBar
@onready var label_status: Label = %StatusLabel
@onready var label_rank: Label = %RankLabel
@onready var label_alive: Label = %AliveLabel
@onready var label_target: Label = %TargetLabel
@onready var label_attack_log: Label = %AttackLogLabel
@onready var label_score: Label = %ScoreLabel
@onready var label_lines: Label = %LinesLabel
@onready var label_hold: Label = %HoldLabel
@onready var label_next: Label = %NextLabel
@onready var label_action_text: Label = %ActionTextLabel
@onready var label_combo_text: Label = %ComboTextLabel
@onready var result_overlay: Control = %ResultOverlay
@onready var result_card: Panel = %ResultCard
@onready var result_label: Label = %ResultLabel
@onready var vote_list: VBoxContainer = %VoteList
@onready var btn_restart: Button = %RestartButton
@onready var btn_lobby: Button = %LobbyButton
@onready var local_ko_name_label: Label = %LocalKONameLabel
@onready var bgm: AudioStreamPlayer = $BGM
@onready var sfx_planting: AudioStreamPlayer = $SfxPlanting
@onready var sfx_line_clear: AudioStreamPlayer = $SfxLineClear
@onready var sfx_tetris: AudioStreamPlayer = $SfxSuccess
@onready var sfx_spin: AudioStreamPlayer = $SfxSpin
@onready var sfx_death: AudioStreamPlayer = $SfxDeath

const BGM_STREAM: AudioStream = preload("res://audio/bgm.ogg")
const SFX_PLANTING_STREAM: AudioStream = preload("res://audio/planting.ogg")
const SFX_LINE_CLEAR_STREAM: AudioStream = preload("res://audio/line_clear.ogg")
const SFX_TETRIS_STREAM: AudioStream = preload("res://audio/tetris.ogg")
const SFX_SPIN_STREAM: AudioStream = preload("res://audio/spin.ogg")
const SFX_DEATH_STREAM: AudioStream = preload("res://audio/death.ogg")
const ATTACK_DAMAGE_POPUP := preload("res://scripts/ui/attack_damage_popup.gd")
const B2B_STREAK_BADGE := preload("res://scripts/ui/b2b_streak_badge.gd")
const GARBAGE_BAR_GAP: float = 6.0
const ATTACK_DELAY_SECONDS: float = 12.0
const WARNING_STAGE_SECONDS: float = 6.0
const VOTE_COLOR_READY := Color(0.18, 0.82, 0.42, 1.0)
const VOTE_COLOR_WAITING := Color(0.95, 0.78, 0.24, 1.0)
const VOTE_COLOR_DECLINED := Color(0.92, 0.18, 0.18, 1.0)
const SYMBOL_WAITING := "\u25A1"
const SYMBOL_READY := "\u25CB"
const SYMBOL_DECLINED := "X"

var _opponent_panels: Array[Tetris33OpponentPanel] = []
var _opponents: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _sample_timer: float = 0.0
var _ko_timer: float = 0.0
var _next_bot_attack_seconds: float = 7.0
var _bot_attack_timer: float = 0.0
var _last_target_index: int = -1
var _alive_count: int = 1
var _network_opponent_ids: Array[String] = []
var _network_opponent_names: Array[String] = []
var _local_eliminated: bool = false
var _match_finished: bool = false
var _rematch_requested: bool = false
var _rematch_declined: bool = false
var _local_rank: int = 0
var _last_result_title: String = ""
var _last_vote_statuses: Array = []

var pending_attacks: Array = []
var ready_garbage: int = 0

var _data_collector: PlayerDataCollector
var _structure_evaluator: Node
var _last_lines_cleared_this_lock: int = 0
var _last_damage_this_lock: int = 0
var _last_is_spin: bool = false
var _last_is_t_spin: bool = false
var _hold_used_this_piece: bool = false
var _cached_board_after_drop: Array = []

var _action_text_tween: Tween
var _combo_text_tween: Tween


func _ready() -> void:
	super._ready()
	_rng.randomize()
	_apply_network_match_state()
	_apply_match_seed()
	_assign_audio_streams()
	_bind_opponent_panels()
	_initialize_ui()
	_initialize_match()
	_start_data_collection()

	score_changed.connect(_on_score_changed)
	lines_cleared.connect(_on_lines_cleared)
	rows_cleared.connect(_on_rows_cleared)
	game_over_triggered.connect(_on_local_game_over)
	NetworkManager.tetris33_sample_received.connect(_on_network_sample_received)
	NetworkManager.tetris33_attack_received.connect(_on_network_attack_received)
	NetworkManager.tetris33_game_over_received.connect(_on_network_game_over_received)
	NetworkManager.tetris33_player_left.connect(_on_network_player_left)
	NetworkManager.tetris33_match_finished.connect(_on_tetris33_match_finished)
	NetworkManager.rematch_status_payload_received.connect(_on_rematch_status_received)
	NetworkManager.tetris33_game_started.connect(_on_tetris33_rematch_started)

	if not paused:
		_spawn_next_piece()
	if bgm and not paused:
		bgm.play()


func _process(delta: float) -> void:
	process_logic(delta)
	if _data_collector and _data_collector.is_active() and not game_over and not paused:
		_count_key_presses()
	if not game_over and not paused:
		_update_player_garbage(delta)
		if not _is_network_match():
			_update_opponent_samples(delta)
			_update_bot_pressure(delta)
			_update_match_state(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_save_and_cleanup_data()
		get_tree().change_scene_to_file("res://scenes/ui/main.tscn")
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


func _assign_audio_streams() -> void:
	if bgm:
		bgm.stream = BGM_STREAM
		if bgm.stream is AudioStreamOggVorbis:
			(bgm.stream as AudioStreamOggVorbis).loop = true
	if sfx_planting:
		sfx_planting.stream = SFX_PLANTING_STREAM
	if sfx_line_clear:
		sfx_line_clear.stream = SFX_LINE_CLEAR_STREAM
	if sfx_tetris:
		sfx_tetris.stream = SFX_TETRIS_STREAM
	if sfx_spin:
		sfx_spin.stream = SFX_SPIN_STREAM
	if sfx_death:
		sfx_death.stream = SFX_DEATH_STREAM


func _trf(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args


func _apply_network_match_state() -> void:
	if NetworkManager.current_room_mode != "tetris33":
		return
	if NetworkManager.tetris33_player_count > 0:
		active_player_count = clampi(NetworkManager.tetris33_player_count, min_players_to_start, 33)

	_network_opponent_ids.clear()
	_network_opponent_names.clear()
	for player in NetworkManager.tetris33_players:
		if not (player is Dictionary):
			continue
		if int(player.get("slot", 0)) == NetworkManager.tetris33_local_slot:
			continue
		_network_opponent_ids.append(str(player.get("id", "")))
		_network_opponent_names.append(str(player.get("name", "P%02d" % int(player.get("slot", 0)))))


func _apply_match_seed() -> void:
	if bag == null:
		return
	if NetworkManager.match_seed != 0:
		bag.reset_with_seed(NetworkManager.match_seed)
		_update_next_display()


func _bind_opponent_panels() -> void:
	_opponent_panels.clear()
	for child in %OpponentLeftGrid.get_children():
		if child is Tetris33OpponentPanel:
			_opponent_panels.append(child)
	for child2 in %OpponentRightGrid.get_children():
		if child2 is Tetris33OpponentPanel:
			_opponent_panels.append(child2)


func _initialize_ui() -> void:
	if result_overlay:
		result_overlay.visible = false
	if result_label:
		result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if btn_restart:
		btn_restart.text = tr("TXT_REMATCH")
		btn_restart.disabled = true
		btn_restart.pressed.connect(_on_rematch_pressed)
	if btn_lobby:
		btn_lobby.text = tr("TXT_RETURN_LOBBY")
		btn_lobby.pressed.connect(_on_lobby_pressed)
	if player_garbage_bar and board:
		player_garbage_bar.max_lines = board.visible_rows
		player_garbage_bar.update_bar(0, 0, 0)
		call_deferred("_layout_player_garbage_bar")
	if label_hold:
		label_hold.text = "HOLD"
	if label_next:
		label_next.text = "NEXT"
	if label_action_text:
		label_action_text.visible = false
	if label_combo_text:
		label_combo_text.visible = false
	if local_ko_name_label:
		local_ko_name_label.visible = false
	_clear_vote_list()


func _layout_player_garbage_bar() -> void:
	if player_garbage_bar == null or board == null:
		return
	var cell_px: float = board.cell_size
	var board_top_left_local: Vector2 = to_local(board.global_position)
	var bar_left: float = board_top_left_local.x - GARBAGE_BAR_GAP - cell_px
	var bar_top: float = board_top_left_local.y
	player_garbage_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	player_garbage_bar.offset_left = bar_left
	player_garbage_bar.offset_top = bar_top
	player_garbage_bar.offset_right = bar_left + cell_px
	player_garbage_bar.offset_bottom = bar_top + board.visible_rows * cell_px


func _initialize_match() -> void:
	active_player_count = clampi(active_player_count, 1, 33)
	if active_player_count < min_players_to_start:
		paused = true
		if label_status:
			label_status.text = "WAITING FOR %d PLAYERS" % min_players_to_start
		return

	_alive_count = active_player_count
	_opponents.clear()
	var opponent_count := active_player_count - 1
	for i in range(_opponent_panels.size()):
		var panel := _opponent_panels[i]
		var is_active := i < opponent_count
		panel.visible = is_active
		panel.opponent_index = i
		if not is_active:
			continue

		var sample := _build_initial_opponent_sample(i) if _is_network_match() else _build_opponent_sample(i)
		_opponents.append(sample)
		panel.update_from_sample(sample)

	_next_bot_attack_seconds = _rng.randf_range(bot_attack_min_seconds, bot_attack_max_seconds)
	_refresh_match_labels()


func _start_data_collection() -> void:
	_data_collector = PlayerDataCollector.new()
	_structure_evaluator = get_node_or_null("StructureEvaluator")
	var state := get_node_or_null("/root/GameState")
	var pname := ""
	if state:
		pname = str(state.player_name).strip_edges()
	_data_collector.start_session(
		pname if not pname.is_empty() else "Player",
		"tetris33",
		active_player_count,
		"battle_royale",
		1
	)


func _update_player_garbage(delta: float) -> void:
	var new_pending: Array = []
	var grey_count := 0
	var yellow_count := 0

	for attack in pending_attacks:
		attack["delay"] = float(attack["delay"]) - delta
		if float(attack["delay"]) <= 0.0:
			ready_garbage += int(attack["amount"])
		else:
			new_pending.append(attack)
			if float(attack["delay"]) > WARNING_STAGE_SECONDS:
				grey_count += int(attack["amount"])
			else:
				yellow_count += int(attack["amount"])

	pending_attacks = new_pending
	if player_garbage_bar:
		player_garbage_bar.update_bar(grey_count, yellow_count, ready_garbage)


func _update_opponent_samples(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer < opponent_sample_seconds:
		return
	_sample_timer = 0.0

	for i in range(_opponents.size()):
		if bool(_opponents[i].get("eliminated", false)):
			continue
		var sample := _build_opponent_sample(i, _opponents[i])
		_opponents[i] = sample
		if i < _opponent_panels.size():
			_opponent_panels[i].update_from_sample(sample)
	_refresh_match_labels()


func _update_bot_pressure(delta: float) -> void:
	_bot_attack_timer += delta
	if _bot_attack_timer < _next_bot_attack_seconds:
		return
	_bot_attack_timer = 0.0
	_next_bot_attack_seconds = _rng.randf_range(bot_attack_min_seconds, bot_attack_max_seconds)

	if _alive_count <= 1:
		return
	var amount := 1 + int(_rng.randf() < 0.22)
	for _i in range(amount):
		pending_attacks.append({"delay": ATTACK_DELAY_SECONDS, "amount": 1})
	_log_attack("INCOMING +%d" % amount)


func _update_match_state(delta: float) -> void:
	_ko_timer += delta
	if _ko_timer < ko_pressure_seconds:
		return
	_ko_timer = 0.0

	var candidates: Array[int] = []
	for i in range(_opponents.size()):
		if not bool(_opponents[i].get("eliminated", false)):
			candidates.append(i)
	if candidates.is_empty():
		return

	candidates.sort_custom(func(a: int, b: int) -> bool:
		return float(_opponents[a].get("danger_score", 0.0)) > float(_opponents[b].get("danger_score", 0.0))
	)

	if _rng.randf() < 0.45:
		_eliminate_opponent(candidates[0])


func _eliminate_opponent(index: int) -> void:
	if index < 0 or index >= _opponents.size():
		return
	if bool(_opponents[index].get("eliminated", false)):
		return
	_opponents[index]["eliminated"] = true
	_alive_count = maxi(1, _alive_count - 1)
	if index < _opponent_panels.size():
		_opponent_panels[index].set_eliminated(true)
	_refresh_match_labels()
	if _alive_count <= 1 and not _local_eliminated:
		_on_victory()


func _build_opponent_sample(index: int, previous: Dictionary = {}) -> Dictionary:
	var visible_board := _generate_visible_board(previous)
	var scores := _evaluate_structure_scores(visible_board)
	var structure := float(scores.get("structure_score", 0.0))
	var stability := float(scores.get("stability_score", 0.0))
	var height := _calculate_total_height(visible_board)
	var pending := clampi(int(previous.get("pending_garbage", 0)) + _rng.randi_range(-1, 2), 0, 14)
	var danger := _calculate_danger_score(structure, stability, height, pending)
	var safety := clampf(100.0 - danger, 0.0, 100.0)

	return {
		"index": index,
		"id": _network_opponent_ids[index] if index < _network_opponent_ids.size() else str(previous.get("id", "")),
		"name": _network_opponent_names[index] if index < _network_opponent_names.size() else str(previous.get("name", "P%02d" % (index + 2))),
		"rank": int(previous.get("rank", index + 2)),
		"visible_board": visible_board,
		"structure_score": structure,
		"stability_score": stability,
		"pending_garbage": pending,
		"danger_score": danger,
		"safety_score": safety,
		"eliminated": bool(previous.get("eliminated", false))
	}


func _build_initial_opponent_sample(index: int) -> Dictionary:
	var visible_board := _create_empty_visible_board()
	return {
		"index": index,
		"id": _network_opponent_ids[index] if index < _network_opponent_ids.size() else "",
		"name": _network_opponent_names[index] if index < _network_opponent_names.size() else "P%02d" % (index + 2),
		"rank": active_player_count,
		"visible_board": visible_board,
		"structure_score": 0.0,
		"stability_score": 0.0,
		"pending_garbage": 0,
		"danger_score": 0.0,
		"safety_score": 100.0,
		"eliminated": false
	}


func _create_empty_visible_board() -> Array:
	var board_state: Array = []
	for _r in range(20):
		var row: Array = []
		row.resize(10)
		row.fill(0)
		board_state.append(row)
	return board_state


func _generate_visible_board(previous: Dictionary = {}) -> Array:
	var board_state: Array = []
	for _r in range(20):
		var row: Array = []
		row.resize(10)
		row.fill(0)
		board_state.append(row)

	var base_height := _rng.randi_range(1, 11)
	if previous.has("danger_score"):
		base_height = clampi(int(float(previous["danger_score"]) / 9.0) + _rng.randi_range(0, 3), 1, 15)

	for c in range(10):
		var height := clampi(base_height + _rng.randi_range(-3, 4), 0, 18)
		for y in range(20 - height, 20):
			if _rng.randf() > 0.08:
				board_state[y][c] = 8 if _rng.randf() < 0.18 else _rng.randi_range(1, 7)
	return board_state


func _calculate_danger_score(structure: float, stability: float, total_height: int, pending: int) -> float:
	var structure_risk := 100.0 - (structure * 0.55 + stability * 0.45)
	var height_risk := clampf(float(total_height) / 110.0 * 100.0, 0.0, 100.0)
	var garbage_risk := clampf(float(pending) / 14.0 * 100.0, 0.0, 100.0)
	return clampf(structure_risk * 0.48 + height_risk * 0.34 + garbage_risk * 0.18, 0.0, 100.0)


func _is_network_match() -> bool:
	return NetworkManager.current_room_mode == "tetris33"


func _send_local_network_sample() -> void:
	if not _is_network_match() or board == null:
		return
	var visible_grid := _get_visible_board_snapshot()
	var scores := _evaluate_structure_scores(visible_grid)
	scores["visible_board"] = visible_grid
	scores["pending_garbage"] = _get_pending_garbage_total()
	scores["rank"] = _local_rank if _local_rank > 0 else _alive_count
	scores["eliminated"] = _local_eliminated
	NetworkManager.send_tetris33_sample(scores)


func _get_visible_board_snapshot() -> Array:
	var full_grid: Array = board.get_grid_state().duplicate(true)
	var visible_grid: Array = []
	for r in range(board.buffer_rows, board.total_rows):
		if r < full_grid.size():
			visible_grid.append((full_grid[r] as Array).duplicate())
	return visible_grid


func _get_pending_garbage_total() -> int:
	var total := ready_garbage
	for attack in pending_attacks:
		total += int(attack.get("amount", 0))
	return total


func _select_attack_target() -> int:
	var candidates: Array[int] = []
	for i in range(_opponents.size()):
		if not bool(_opponents[i].get("eliminated", false)):
			candidates.append(i)
	if candidates.is_empty():
		return -1

	var total_weight := maxf(random_target_weight + least_dangerous_target_weight, 0.001)
	var roll := _rng.randf() * total_weight
	if roll < random_target_weight:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]

	var best_index := candidates[0]
	var best_safety := -1.0
	for idx in candidates:
		var safety := float(_opponents[idx].get("safety_score", 0.0))
		if safety > best_safety:
			best_safety = safety
			best_index = idx
	return best_index


func _send_attack_to_target(amount: int) -> void:
	var target_index := _select_attack_target()
	if target_index < 0:
		return

	_last_target_index = target_index
	for i in range(_opponent_panels.size()):
		_opponent_panels[i].set_targeted(i == target_index)

	if not _is_network_match():
		_opponents[target_index]["pending_garbage"] = int(_opponents[target_index].get("pending_garbage", 0)) + amount
		if target_index < _opponent_panels.size():
			_opponent_panels[target_index].update_from_sample(_opponents[target_index])

	var target_name := str(_opponents[target_index].get("name", "P%02d" % (target_index + 2)))
	_log_attack("ATTACK %s +%d" % [target_name, amount])
	var target_id := str(_opponents[target_index].get("id", ""))
	if not target_id.is_empty() and NetworkManager.current_room_mode == "tetris33":
		NetworkManager.send_tetris33_attack(target_id, amount)
	if label_target:
		label_target.text = "TARGET  %s" % target_name

	if not _is_network_match() and int(_opponents[target_index].get("pending_garbage", 0)) >= 12 and _rng.randf() < 0.35:
		_eliminate_opponent(target_index)


func _on_score_changed(s: int, _l: int, ln: int) -> void:
	if label_score:
		label_score.text = "SCORE\n%d" % s
	if label_lines:
		label_lines.text = "LINES\n%d" % ln


func _on_lines_cleared(amount: int, is_spin: bool, is_t_spin: bool, dmg: int) -> void:
	_last_lines_cleared_this_lock = amount
	_last_damage_this_lock = dmg
	_last_is_spin = is_spin
	_last_is_t_spin = is_t_spin
	_update_b2b_badge()

	if is_spin or is_t_spin:
		if sfx_spin:
			sfx_spin.play()
		_show_action_text(_build_spin_text(cur_type, is_t_spin))
	elif amount == 4:
		if sfx_tetris:
			sfx_tetris.play()
		_show_action_text("TETRIS!")
	else:
		if sfx_line_clear:
			sfx_line_clear.play()

	if scoring.combo > 0:
		_show_combo_text(scoring.combo)

	var block_amount := dmg
	var canceled_ready := mini(block_amount, ready_garbage)
	ready_garbage -= canceled_ready
	block_amount -= canceled_ready

	while block_amount > 0 and pending_attacks.size() > 0:
		var target = pending_attacks[0]
		var cancel := mini(block_amount, int(target["amount"]))
		target["amount"] = int(target["amount"]) - cancel
		block_amount -= cancel
		if int(target["amount"]) <= 0:
			pending_attacks.pop_front()

	if block_amount > 0:
		_send_attack_to_target(block_amount)


func _lock_piece() -> void:
	var will_receive_garbage := ready_garbage > 0
	var lines_before_lock := scoring.lines

	_last_lines_cleared_this_lock = 0
	_last_damage_this_lock = 0
	_last_is_spin = false
	_last_is_t_spin = false

	var locked_piece_type: int = cur_type
	var locked_rotation: int = cur_rot
	var locked_col: int = cur_col
	var locked_row: int = cur_row
	var next_pieces_at_lock: Array = bag.peek(5)

	lock_timer.stop()
	board.lock_piece(cur_type, cur_rot, cur_col, cur_row, PieceData.COLORS[cur_type])

	var full_grid_before_clear: Array = board.get_grid_state()
	_cached_board_after_drop = []
	for r in range(board.buffer_rows, board.total_rows):
		if r < full_grid_before_clear.size():
			_cached_board_after_drop.append(full_grid_before_clear[r])

	var is_spin := false
	if last_was_rotation and _is_spin_piece_type(cur_type):
		is_spin = _check_immobile()

	var clear_result: Dictionary = board.clear_lines_with_data()
	var cleared := int(clear_result["cleared"])
	var cleared_rows_data: Array = clear_result["rows_data"]
	var dmg := 0
	if cleared > 0:
		var is_t_spin := cur_type == PieceData.Type.T and is_spin
		scoring.process_line_clear(cleared, is_spin, is_t_spin)
		dmg = _calculate_damage(cleared, is_spin, is_t_spin)
		lines_cleared.emit(cleared, is_spin, is_t_spin, dmg)
		rows_cleared.emit(cleared_rows_data)
	else:
		scoring.reset_combo()

	score_changed.emit(scoring.score, scoring.level, scoring.lines)
	piece_locked.emit(cur_type, board.get_grid_state())

	var did_clear_lines := scoring.lines > lines_before_lock
	if will_receive_garbage and not did_clear_lines and board:
		board.add_garbage_lines(ready_garbage)
		ready_garbage = 0
		if player_garbage_bar:
			player_garbage_bar.update_bar(0, 0, 0)

	hold_used = false
	_spawn_next_piece()

	if sfx_planting:
		sfx_planting.play()

	_record_piece_snapshot(
		locked_piece_type,
		locked_rotation,
		locked_col,
		locked_row,
		next_pieces_at_lock
	)


func _try_hold() -> void:
	if not hold_used:
		_hold_used_this_piece = true
	super._try_hold()


func _on_local_game_over() -> void:
	if _local_eliminated or _match_finished:
		return
	_local_eliminated = true
	_local_rank = maxi(2, _alive_count)
	_freeze_local_play(true)
	if bgm:
		bgm.stop()
	if sfx_death:
		sfx_death.play()
	if NetworkManager.current_room_mode == "tetris33":
		_send_local_network_sample()
		NetworkManager.send_tetris33_game_over(_local_rank)
	_enter_spectator_mode()
	_save_and_cleanup_data()


func _on_victory() -> void:
	if _local_eliminated or _match_finished:
		return
	_local_rank = 1
	_freeze_local_play(false)
	if bgm:
		bgm.stop()
	if NetworkManager.current_room_mode == "tetris33":
		_send_local_network_sample()
	else:
		_match_finished = true
		_show_result(_compose_result_text(_local_rank, tr("TXT_TETRIS33_REMATCH_READY")), false)
	_save_and_cleanup_data()


func _enter_spectator_mode() -> void:
	_show_local_rank_overlay()
	if label_status:
		label_status.text = "SPECTATING"
	_refresh_match_labels()
	if result_overlay:
		result_overlay.visible = false


func _show_result(text: String, allow_rematch: bool = false) -> void:
	_last_result_title = text.get_slice("\n", 0)
	if result_label:
		result_label.text = text
	if btn_restart:
		btn_restart.disabled = not allow_rematch
	if result_overlay:
		result_overlay.visible = true
		if btn_restart and not btn_restart.disabled:
			btn_restart.grab_focus()
		elif btn_lobby:
			btn_lobby.grab_focus()


func _set_result_subtitle(subtitle: String) -> void:
	if result_label:
		result_label.text = "%s\n%s" % [_last_result_title, subtitle]


func _compose_result_text(rank: int, subtitle: String) -> String:
	var title := "WINNER  #1" if rank == 1 else "RANK #%d" % rank
	return "%s\n%s" % [title, subtitle]


func _freeze_local_play(hide_active_piece: bool) -> void:
	game_over = true
	paused = true
	if lock_timer:
		lock_timer.stop()
	if ghost_piece:
		ghost_piece.visible = false
	if current_piece and hide_active_piece:
		current_piece.visible = false


func _show_local_rank_overlay() -> void:
	if local_ko_name_label == null:
		return
	var rank_value := _local_rank if _local_rank > 0 else maxi(2, _alive_count)
	local_ko_name_label.text = "RANK #%d" % rank_value
	local_ko_name_label.visible = true


func _on_rows_cleared(rows_data: Array) -> void:
	if board == null or rows_data.is_empty():
		return
	var effect := LineClearEffect.new()
	board.add_child(effect)
	effect.setup(rows_data, board.cell_size, board.buffer_rows)
	var popup_parent: Node = get_node_or_null("HUD")
	var popup_node: Node = popup_parent if popup_parent else self
	ATTACK_DAMAGE_POPUP.spawn(popup_node, board, _last_damage_this_lock, rows_data, _attack_popup_style())


func _attack_popup_style() -> String:
	if _last_is_t_spin:
		return ATTACK_DAMAGE_POPUP.STYLE_TSPIN
	if _last_lines_cleared_this_lock >= 4:
		return ATTACK_DAMAGE_POPUP.STYLE_TETRIS
	return ATTACK_DAMAGE_POPUP.STYLE_NORMAL


func _update_b2b_badge() -> void:
	var popup_parent: Node = get_node_or_null("HUD")
	var badge_parent: Node = popup_parent if popup_parent else self
	if scoring.b2b > 0:
		B2B_STREAK_BADGE.show_badge(badge_parent, board, scoring.b2b + 1)
	else:
		B2B_STREAK_BADGE.hide_existing(badge_parent)


func _count_key_presses() -> void:
	if _data_collector == null:
		return
	for action in ["move_left", "move_right", "soft_drop", "hard_drop", "rotate_cw", "rotate_ccw", "rotate_180", "hold"]:
		if Input.is_action_just_pressed(action):
			_data_collector.key_presses_this_piece += 1


func _record_piece_snapshot(
	locked_piece_type: int,
	locked_rotation: int,
	locked_col: int,
	locked_row: int,
	next_pieces_at_lock: Array
) -> void:
	if board == null:
		return

	var full_grid: Array = board.get_grid_state()
	var visible_grid: Array = []
	for r in range(board.buffer_rows, board.total_rows):
		if r < full_grid.size():
			visible_grid.append(full_grid[r])

	var scores := _evaluate_structure_scores(visible_grid)
	if _data_collector != null and _data_collector.is_active():
		_data_collector.record_piece_drop(
			locked_piece_type,
			locked_rotation,
			locked_col,
			locked_row,
			visible_grid,
			next_pieces_at_lock,
			scoring.score,
			scoring.level,
			scoring.lines,
			scoring.combo,
			scoring.b2b,
			_last_is_spin,
			_last_is_t_spin,
			_last_lines_cleared_this_lock,
			_last_damage_this_lock,
			_hold_used_this_piece,
			held_type,
			float(scores.get("structure_score", 0.0)),
			float(scores.get("stability_score", 0.0)),
			_cached_board_after_drop,
			visible_grid
		)
	if NetworkManager.current_room_mode == "tetris33":
		var scores_for_network := scores.duplicate()
		scores_for_network["visible_board"] = visible_grid
		scores_for_network["pending_garbage"] = _get_pending_garbage_total()
		scores_for_network["rank"] = _local_rank if _local_rank > 0 else _alive_count
		scores_for_network["eliminated"] = _local_eliminated
		NetworkManager.send_tetris33_sample(scores_for_network)
	_hold_used_this_piece = false


func _save_and_cleanup_data() -> void:
	if _data_collector == null or not _data_collector.is_active():
		return
	_data_collector.end_session(scoring.score, scoring.level, scoring.lines)


func _evaluate_structure_scores(board_state_visible: Array) -> Dictionary:
	if _structure_evaluator == null:
		return {"structure_score": 0.0, "stability_score": 0.0}
	if _structure_evaluator.has_method("EvaluateBoardScores"):
		var result = _structure_evaluator.call("EvaluateBoardScores", board_state_visible)
		if result is Dictionary:
			return result
	if _structure_evaluator.has_method("evaluate_board_scores"):
		var result2 = _structure_evaluator.call("evaluate_board_scores", board_state_visible)
		if result2 is Dictionary:
			return result2
	return {"structure_score": 0.0, "stability_score": 0.0}


func _calculate_total_height(board_state_visible: Array) -> int:
	var total := 0
	if board_state_visible.is_empty():
		return total
	var rows := board_state_visible.size()
	var cols := (board_state_visible[0] as Array).size()
	for c in range(cols):
		for r in range(rows):
			if int(board_state_visible[r][c]) != 0:
				total += rows - r
				break
	return total


func _refresh_match_labels() -> void:
	if label_alive:
		label_alive.text = "ALIVE\n%d/%d" % [_alive_count, active_player_count]
	if label_rank:
		label_rank.text = "LEFT %d/%d" % [_alive_count, active_player_count]
	if label_status:
		if _match_finished:
			label_status.text = "FINISHED"
		elif _local_eliminated:
			label_status.text = "SPECTATING"
		else:
			label_status.text = "TETRIS33"


func _on_network_sample_received(payload: Dictionary) -> void:
	var from_id := str(payload.get("from_id", ""))
	var idx := _network_opponent_ids.find(from_id)
	if idx < 0 or idx >= _opponents.size():
		return
	var sample := _opponents[idx].duplicate(true)
	for key in payload.keys():
		sample[key] = payload[key]
	sample["id"] = from_id
	sample["name"] = str(payload.get("from_name", sample.get("name", "")))
	sample["danger_score"] = _calculate_danger_score(
		float(sample.get("structure_score", 0.0)),
		float(sample.get("stability_score", 0.0)),
		_calculate_total_height(sample.get("visible_board", [])),
		int(sample.get("pending_garbage", 0))
	)
	sample["safety_score"] = clampf(100.0 - float(sample["danger_score"]), 0.0, 100.0)
	_opponents[idx] = sample
	if idx < _opponent_panels.size():
		_opponent_panels[idx].update_from_sample(sample)


func _on_network_attack_received(payload: Dictionary) -> void:
	var target_id := str(payload.get("target_id", ""))
	if not target_id.is_empty() and target_id != NetworkManager.my_id:
		return
	var amount := int(payload.get("amount", 0))
	if amount <= 0:
		return
	for _i in range(amount):
		pending_attacks.append({"delay": ATTACK_DELAY_SECONDS, "amount": 1})
	_log_attack("INCOMING +%d" % amount)


func _on_network_game_over_received(payload: Dictionary) -> void:
	var idx := _network_opponent_ids.find(str(payload.get("from_id", "")))
	if idx >= 0:
		_opponents[idx]["rank"] = int(payload.get("rank", _opponents[idx].get("rank", active_player_count)))
		_eliminate_opponent(idx)


func _on_network_player_left(payload: Dictionary) -> void:
	var idx := _network_opponent_ids.find(str(payload.get("id", "")))
	if idx >= 0:
		_eliminate_opponent(idx)


func _on_tetris33_match_finished(payload: Dictionary) -> void:
	_match_finished = true
	_freeze_local_play(false)
	for result in payload.get("results", []):
		if result is Dictionary and str(result.get("id", "")) == NetworkManager.my_id:
			_local_rank = int(result.get("rank", _local_rank))
			break
	if _local_rank <= 0:
		_local_rank = 1 if not _local_eliminated else _alive_count
	if _local_rank == 1 and local_ko_name_label:
		local_ko_name_label.visible = false
	elif _local_eliminated:
		_show_local_rank_overlay()
	_refresh_match_labels()
	_show_result(_compose_result_text(_local_rank, tr("TXT_TETRIS33_REMATCH_READY")), not _rematch_declined)
	_last_vote_statuses.clear()
	_update_vote_list(_last_vote_statuses)
	_save_and_cleanup_data()


func _on_rematch_pressed() -> void:
	if not _match_finished or _rematch_requested or _rematch_declined:
		return
	_rematch_requested = true
	if btn_restart:
		btn_restart.disabled = true
		btn_restart.text = tr("TXT_WAITING_CONNECT")
	NetworkManager.request_rematch()


func _on_lobby_pressed() -> void:
	_save_and_cleanup_data()
	if _match_finished:
		NetworkManager.decline_rematch()
	else:
		NetworkManager.leave_room()
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")


func _on_rematch_status_received(payload: Dictionary) -> void:
	if str(payload.get("mode", "")) != "tetris33":
		return
	var declined := bool(payload.get("declined", false))
	var ready_count := int(payload.get("ready_count", 0))
	var total_count := int(payload.get("total_count", active_player_count))
	if declined:
		_rematch_declined = true
		if btn_restart:
			btn_restart.disabled = true
		if result_label and _match_finished:
			_set_result_subtitle(tr("TXT_TETRIS33_REMATCH_DECLINED"))
		_update_vote_list(payload.get("statuses", []))
		return
	if result_label and _match_finished:
		_set_result_subtitle(_trf("TXT_TETRIS33_REMATCH_WAITING", [ready_count, total_count]))
	_update_vote_list(payload.get("statuses", []))


func _on_tetris33_rematch_started(_seed: int, _local_slot: int, _player_count: int, _players: Array) -> void:
	get_tree().reload_current_scene()


func _clear_vote_list() -> void:
	if vote_list == null:
		return
	for child in vote_list.get_children():
		child.queue_free()


func _update_vote_list(statuses: Array) -> void:
	if vote_list == null:
		return
	_last_vote_statuses = statuses.duplicate(true)
	_clear_vote_list()
	if statuses.is_empty():
		_add_vote_row(NetworkManager.player_name, "none")
		return
	for entry in statuses:
		if entry is Dictionary:
			_add_vote_row(str(entry.get("name", "Player")), str(entry.get("status", "none")))


func _add_vote_row(player_name: String, status: String) -> void:
	if vote_list == null:
		return
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 26)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)

	var icon := Label.new()
	icon.custom_minimum_size = Vector2(28, 24)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.text = _vote_symbol(status)
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", _vote_color(status))
	row.add_child(icon)

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = player_name if not player_name.strip_edges().is_empty() else "Player"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0, 1.0))
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var status_label := Label.new()
	status_label.custom_minimum_size = Vector2(86, 24)
	status_label.text = _vote_status_text(status)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", _vote_color(status))
	row.add_child(status_label)

	vote_list.add_child(row)


func _vote_symbol(status: String) -> String:
	match status:
		"ready":
			return SYMBOL_READY
		"declined":
			return SYMBOL_DECLINED
		_:
			return SYMBOL_WAITING


func _vote_color(status: String) -> Color:
	match status:
		"ready":
			return VOTE_COLOR_READY
		"declined":
			return VOTE_COLOR_DECLINED
		_:
			return VOTE_COLOR_WAITING


func _vote_status_text(status: String) -> String:
	match status:
		"ready":
			return tr("TXT_REMATCH_READY")
		"declined":
			return tr("TXT_REMATCH_DECLINED")
		_:
			return tr("TXT_REMATCH_WAITING")


func _log_attack(text: String) -> void:
	if label_attack_log == null:
		return
	label_attack_log.text = text


func _build_spin_text(piece_type: int, is_t_spin: bool) -> String:
	if is_t_spin:
		return "T-SPIN!"
	var piece_name := _piece_type_to_letter(piece_type)
	return "SPIN!" if piece_name.is_empty() else "%s-SPIN!" % piece_name


func _piece_type_to_letter(piece_type: int) -> String:
	match piece_type:
		PieceData.Type.I:
			return "I"
		PieceData.Type.O:
			return "O"
		PieceData.Type.T:
			return "T"
		PieceData.Type.S:
			return "S"
		PieceData.Type.Z:
			return "Z"
		PieceData.Type.J:
			return "J"
		PieceData.Type.L:
			return "L"
		_:
			return ""


func _show_action_text(content: String) -> void:
	if label_action_text == null:
		return
	if _action_text_tween and _action_text_tween.is_running():
		_action_text_tween.kill()
	label_action_text.text = content
	label_action_text.visible = true
	label_action_text.modulate = Color.WHITE
	label_action_text.scale = Vector2(0.92, 0.92)
	_action_text_tween = create_tween()
	_action_text_tween.set_parallel(true)
	_action_text_tween.tween_property(label_action_text, "scale", Vector2(1.08, 1.08), 0.10)
	_action_text_tween.chain()
	_action_text_tween.tween_interval(0.25)
	_action_text_tween.set_parallel(true)
	_action_text_tween.tween_property(label_action_text, "modulate:a", 0.0, 0.85)
	_action_text_tween.tween_property(label_action_text, "scale", Vector2(1.14, 1.14), 0.85)
	_action_text_tween.finished.connect(func():
		if label_action_text:
			label_action_text.visible = false
			label_action_text.modulate = Color.WHITE
	)


func _show_combo_text(combo_count: int) -> void:
	if label_combo_text == null:
		return
	if _combo_text_tween and _combo_text_tween.is_running():
		_combo_text_tween.kill()
	label_combo_text.text = "COMBO %d" % combo_count
	label_combo_text.visible = true
	label_combo_text.modulate = Color.from_hsv(fmod(float(combo_count) * 0.12, 1.0), 0.86, 1.0, 1.0)
	_combo_text_tween = create_tween()
	_combo_text_tween.tween_interval(0.28)
	_combo_text_tween.tween_property(label_combo_text, "modulate:a", 0.0, 0.45)
	_combo_text_tween.finished.connect(func():
		if label_combo_text:
			label_combo_text.visible = false
	)
