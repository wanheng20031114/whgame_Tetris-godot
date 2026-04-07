class_name PlayerDataCollector
extends RefCounted

# ==============================================================================
# 玩家单局数据采集器
# 设计目标：
# 1) 每次方块锁定时采集一次快照，支持回放与行为分析。
# 2) 对局中仅做内存累积，结算时统一落盘，避免高频 IO。
# 3) 在这里集中计算六维雷达图中的 speed / attack / efficiency / topology / holes。
# ==============================================================================

# 快照体积估算与上限保护，避免极端长局占满内存。
const SNAPSHOT_ESTIMATED_BYTES: int = 1200
const MEMORY_LIMIT_BYTES: int = 2_000_000_000
const MAX_SNAPSHOTS: int = 1_666_666

# 方块类型编码到名称的映射，便于快照与日志阅读。
const PIECE_TYPE_NAMES: Dictionary = {
	0: "I", 1: "O", 2: "T", 3: "S", 4: "Z", 5: "J", 6: "L"
}

# 雷达图归一化常量。
const SPEED_PPS_MAX: float = 3.0
const ATTACK_APM_MAX: float = 120.0
const EFFICIENCY_APP_MAX: float = 1.0
const EFFICIENCY_KPP_BEST: float = 2.0
const EFFICIENCY_KPP_WORST: float = 6.0
const EFFICIENCY_APP_WEIGHT: float = 0.6
const EFFICIENCY_KPP_WEIGHT: float = 0.4

var _active: bool = false
var _player_name: String = ""

var _session_start_ticks_ms: int = 0
var _session_start_iso: String = ""
var _last_piece_ticks_ms: int = 0

# 当前方块（从生成到锁定）的按键次数；由上层每帧累计。
var key_presses_this_piece: int = 0

var _snapshots: Array = []
var _discarded_snapshots: int = 0

var _piece_index: int = 0

var _total_damage: int = 0
var _total_key_presses: int = 0
var _topology_score_sum: float = 0.0
var _holes_score_sum: float = 0.0
var _topology_samples: int = 0

var _singles: int = 0
var _doubles: int = 0
var _triples: int = 0
var _tetrises: int = 0
var _spin_clears: int = 0
var _t_spin_clears: int = 0

var _max_combo: int = 0
var _max_b2b: int = 0


# 开始一局采集：重置会话内统计数据。
func start_session(player_name: String) -> void:
	_active = true
	_player_name = player_name
	_session_start_ticks_ms = Time.get_ticks_msec()
	_session_start_iso = _get_iso_datetime()
	_last_piece_ticks_ms = _session_start_ticks_ms
	_piece_index = 0
	_total_damage = 0
	_total_key_presses = 0
	_topology_score_sum = 0.0
	_holes_score_sum = 0.0
	_topology_samples = 0
	_singles = 0
	_doubles = 0
	_triples = 0
	_tetrises = 0
	_spin_clears = 0
	_t_spin_clears = 0
	_max_combo = 0
	_max_b2b = 0
	_discarded_snapshots = 0
	_snapshots.clear()
	key_presses_this_piece = 0


# 记录一次方块锁定快照。
# 注意：board_state_visible 必须是 10x20 的可见棋盘（不含 buffer 区域）。
func record_piece_drop(
	piece_type: int,
	rotation: int,
	col: int,
	row: int,
	board_state_visible: Array,
	next_pieces: Array,
	score: int,
	level: int,
	lines_cleared_total: int,
	combo: int,
	b2b: int,
	is_spin: bool,
	is_t_spin: bool,
	lines_cleared_this_lock: int,
	damage_this_lock: int,
	hold_used_this_piece: bool,
	topology_score: float,
	holes_score: float
) -> void:
	if not _active:
		return

	var now_ms: int = Time.get_ticks_msec() # 会话内当前时间戳（毫秒）
	var elapsed_since_last: int = now_ms - _last_piece_ticks_ms
	_last_piece_ticks_ms = now_ms

	# 本块按键次数，用于 KPP（Keys Per Piece）。
	var kp: int = key_presses_this_piece
	_total_key_presses += kp
	key_presses_this_piece = 0

	# 累积本块输出指标，结算时取平均。
	_total_damage += damage_this_lock
	_topology_score_sum += topology_score
	_holes_score_sum += holes_score
	_topology_samples += 1

	# 消行类型统计。
	if lines_cleared_this_lock == 1:
		_singles += 1
	elif lines_cleared_this_lock == 2:
		_doubles += 1
	elif lines_cleared_this_lock == 3:
		_triples += 1
	elif lines_cleared_this_lock >= 4:
		_tetrises += 1
	if is_spin:
		_spin_clears += 1
	if is_t_spin:
		_t_spin_clears += 1

	# 维护峰值连击与 B2B。
	if combo > _max_combo:
		_max_combo = combo
	if b2b > _max_b2b:
		_max_b2b = b2b

	var next_names: Array = []
	for nt in next_pieces:
		next_names.append(PIECE_TYPE_NAMES.get(int(nt), "?"))

	# 单次快照保留对局还原与行为分析所需信息。
	var snapshot: Dictionary = {
		"piece_index": _piece_index,
		"timestamp_ms": now_ms - _session_start_ticks_ms,
		"piece_type": PIECE_TYPE_NAMES.get(piece_type, "?"),
		"rotation": rotation,
		"col": col,
		"row": row,
		"board_state": board_state_visible,
		"next_pieces": next_names,
		"score": score,
		"level": level,
		"lines_cleared": lines_cleared_total,
		"combo": combo,
		"b2b": b2b,
		"is_spin": is_spin,
		"is_t_spin": is_t_spin,
		"lines_cleared_this_lock": lines_cleared_this_lock,
		"damage_this_lock": damage_this_lock,
		"key_presses_this_piece": kp,
		"hold_used": hold_used_this_piece,
		"elapsed_since_last_piece_ms": elapsed_since_last,
		"topology_score": snapped(topology_score, 0.1),
		"holes_score": snapped(holes_score, 0.1)
	}

	if _snapshots.size() >= MAX_SNAPSHOTS:
		# 滑动窗口策略：超上限后丢弃最早快照，优先保留最近行为。
		_snapshots.pop_front()
		_discarded_snapshots += 1

	_snapshots.append(snapshot)
	_piece_index += 1


# 结束一局采集并落盘，返回完整 session_data 给上层 UI/结算流程。
func end_session(final_score: int, final_level: int, final_lines: int) -> Dictionary:
	if not _active:
		return {}
	_active = false

	var end_ticks_ms: int = Time.get_ticks_msec()
	var duration_seconds: float = (end_ticks_ms - _session_start_ticks_ms) / 1000.0
	var end_iso: String = _get_iso_datetime()

	var pieces_placed: int = _piece_index # 实际锁定方块数
	var pps: float = pieces_placed / maxf(duration_seconds, 0.001)
	var duration_minutes: float = duration_seconds / 60.0
	var apm: float = _total_damage / maxf(duration_minutes, 0.001)
	var app: float = float(_total_damage) / maxf(float(pieces_placed), 1.0)
	var kpp: float = float(_total_key_presses) / maxf(float(pieces_placed), 1.0)

	var avg_topology: float = _topology_score_sum / maxf(float(_topology_samples), 1.0)
	var avg_holes: float = _holes_score_sum / maxf(float(_topology_samples), 1.0)
	var radar: Dictionary = _calculate_radar_scores(pps, apm, app, kpp, avg_topology, avg_holes)

	var session_data: Dictionary = {
		"player_name": _player_name,
		"session_id": _session_start_iso,
		"start_time": _session_start_iso,
		"end_time": end_iso,
		"duration_seconds": duration_seconds,
		"final_score": final_score,
		"final_level": final_level,
		"final_lines": final_lines,
		"pieces_placed": pieces_placed,
		"total_damage": _total_damage,
		"total_key_presses": _total_key_presses,
		"pps": pps,
		"apm": apm,
		"app": app,
		"kpp": kpp,
		"singles": _singles,
		"doubles": _doubles,
		"triples": _triples,
		"tetrises": _tetrises,
		"spin_clears": _spin_clears,
		"t_spin_clears": _t_spin_clears,
		"max_combo": _max_combo,
		"max_b2b": _max_b2b,
		"discarded_snapshots": _discarded_snapshots,
		"radar_scores": radar,
		"snapshots": _snapshots
	}

	PlayerDataStore.save_session(session_data)

	# 历史条目用于“单局历史”面板，包含 topology/holes 平均分。
	var history_entry: Dictionary = {
		"session_id": _session_start_iso,
		"date": _session_start_iso.left(10),
		"score": final_score,
		"lines": final_lines,
		"level": final_level,
		"duration_seconds": duration_seconds,
		"pps": pps,
		"apm": apm,
		"app": app,
		"kpp": kpp,
		"topology": avg_topology,
		"holes": avg_holes,
		"pieces_placed": pieces_placed
	}
	PlayerDataStore.update_stats(_player_name, history_entry, radar)

	# 会话结束后释放快照内存。
	_snapshots.clear()
	return session_data


func get_piece_count() -> int:
	return _piece_index


func get_snapshot_count() -> int:
	return _snapshots.size()


func is_active() -> bool:
	return _active


# 计算雷达图六维中的前五维（vision 当前保留为 0）。
func _calculate_radar_scores(
	pps: float,
	apm: float,
	app: float,
	kpp: float,
	topology_score: float,
	holes_score: float
) -> Dictionary:
	var speed_score: float = clampf(pps / SPEED_PPS_MAX, 0.0, 1.0) * 100.0
	var attack_score: float = clampf(apm / ATTACK_APM_MAX, 0.0, 1.0) * 100.0

	# efficiency = APP 与 KPP 的混合：
	# - APP 越高越好（每块输出更高）
	# - KPP 越低越好（操作更精炼）
	var app_score: float = clampf(app / EFFICIENCY_APP_MAX, 0.0, 1.0) * 100.0
	var kpp_score: float = clampf(
		(EFFICIENCY_KPP_WORST - kpp) / (EFFICIENCY_KPP_WORST - EFFICIENCY_KPP_BEST),
		0.0,
		1.0
	) * 100.0
	var efficiency_score: float = EFFICIENCY_APP_WEIGHT * app_score + EFFICIENCY_KPP_WEIGHT * kpp_score

	return {
		"speed": snapped(speed_score, 0.1),
		"attack": snapped(attack_score, 0.1),
		"efficiency": snapped(efficiency_score, 0.1),
		"topology": snapped(clampf(topology_score, 0.0, 100.0), 0.1),
		"holes": snapped(clampf(holes_score, 0.0, 100.0), 0.1),
		"vision": 0.0
	}


# 生成 ISO 风格时间戳，用于 session_id 与时间字段。
func _get_iso_datetime() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]
