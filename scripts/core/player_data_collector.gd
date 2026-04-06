class_name PlayerDataCollector
extends RefCounted

## 玩家游戏数据采集器
##
## 设计要点：
## 1) 所有快照仅存于内存，游戏结束时一口气序列化为JSON并写入磁盘。
## 2) 内存保护：预估每条快照约1.2KB，当总量接近2GB上限时
##    自动丢弃最早的快照（滑动窗口），保留最近N条。
## 3) 统计指标（PPS、APM、APP、KPP）在会话结束时从快照中汇总计算。
## 4) 六芒星雷达图的6个维度评分也在此类中归一化。

# ==============================================================================
# 常量
# ==============================================================================

## 内存保护参数
## 每条快照预估大小（字节），用于估算总内存占用。
## 10x20 int数组(200项×~4B) + 5个next块(5×~4B) + 元数据(~400B) ≈ 1200B
const SNAPSHOT_ESTIMATED_BYTES: int = 1200
## 内存硬上限 2GB（字节）
const MEMORY_LIMIT_BYTES: int = 2_000_000_000
## 根据预估推算的快照最大保留数量
const MAX_SNAPSHOTS: int = 1_666_666  # ≈ 2GB / 1.2KB per snapshot

## 方块类型名映射表（便于JSON可读性）
const PIECE_TYPE_NAMES: Dictionary = {
	0: "I", 1: "O", 2: "T", 3: "S", 4: "Z", 5: "J", 6: "L"
}

## ── 雷达图归一化参数 ──
## 攻速 (Speed): PPS 0→0分, PPS≥3.0→100分
const SPEED_PPS_MAX: float = 3.0
## 火力 (Attack): APM 0→0分, APM≥120→100分
const ATTACK_APM_MAX: float = 120.0
## 效率 (Efficiency): APP 0→0分, APP≥1.0→100分 & KPP≥6→0分, KPP≤2→100分
const EFFICIENCY_APP_MAX: float = 1.0
const EFFICIENCY_KPP_BEST: float = 2.0   # 最佳（最低）KPP
const EFFICIENCY_KPP_WORST: float = 6.0  # 最差（最高）KPP
## 效率维度中 APP 与 KPP 的权重
const EFFICIENCY_APP_WEIGHT: float = 0.6
const EFFICIENCY_KPP_WEIGHT: float = 0.4

# ==============================================================================
# 会话状态
# ==============================================================================

## 当前会话是否正在采集中
var _active: bool = false

## 玩家名
var _player_name: String = ""

## 会话开始时间戳（毫秒级。使用 Time.get_ticks_msec()）
var _session_start_ticks_ms: int = 0
## 会话开始的 ISO 日期时间字符串
var _session_start_iso: String = ""
## 上一块落地时的 ticks_ms（用于计算每块耗时）
var _last_piece_ticks_ms: int = 0

## 当前这块方块累计的按键次数（每帧在外部递增，落锁时读取后清零）
var key_presses_this_piece: int = 0

## 快照缓冲数组（核心内存池）
var _snapshots: Array = []
## 已被丢弃的快照计数（内存保护触发时递增）
var _discarded_snapshots: int = 0

## 当前方块序号（从0开始累计）
var _piece_index: int = 0

## 累计伤害（用于 APM / APP 计算）
var _total_damage: int = 0
## 累计按键次数（用于 KPP 计算）
var _total_key_presses: int = 0

## 消行分类统计
var _singles: int = 0
var _doubles: int = 0
var _triples: int = 0
var _tetrises: int = 0
var _spin_clears: int = 0
var _t_spin_clears: int = 0

## Combo / B2B 峰值
var _max_combo: int = 0
var _max_b2b: int = 0

# ==============================================================================
# 公开接口
# ==============================================================================

## 开始一个新的采集会话。
## 应在游戏场景 _ready() 中调用。
func start_session(player_name: String) -> void:
	_active = true
	_player_name = player_name
	_session_start_ticks_ms = Time.get_ticks_msec()
	_session_start_iso = _get_iso_datetime()
	_last_piece_ticks_ms = _session_start_ticks_ms
	_piece_index = 0
	_total_damage = 0
	_total_key_presses = 0
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


## 记录一次方块落锁快照。
## 仅写入内存数组，不触发任何IO操作。
## 参数说明见实施计划中的快照结构。
func record_piece_drop(
	piece_type: int,
	rotation: int,
	col: int,
	row: int,
	board_state_visible: Array,   # 10x20 可见区域的二维数组
	next_pieces: Array,           # 接下来5个方块的类型数组
	score: int,
	level: int,
	lines_cleared_total: int,
	combo: int,
	b2b: int,
	is_spin: bool,
	is_t_spin: bool,
	lines_cleared_this_lock: int,
	damage_this_lock: int,
	hold_used_this_piece: bool
) -> void:
	if not _active:
		return

	var now_ms: int = Time.get_ticks_msec()
	var elapsed_since_last: int = now_ms - _last_piece_ticks_ms
	_last_piece_ticks_ms = now_ms

	# ── 按键计数 ──
	var kp: int = key_presses_this_piece
	_total_key_presses += kp
	key_presses_this_piece = 0  # 重置，为下一块准备

	# ── 累计伤害 ──
	_total_damage += damage_this_lock

	# ── 消行分类 ──
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

	# ── Combo / B2B 峰值 ──
	if combo > _max_combo:
		_max_combo = combo
	if b2b > _max_b2b:
		_max_b2b = b2b

	# ── 构造快照字典 ──
	var next_names: Array = []
	for nt in next_pieces:
		next_names.append(PIECE_TYPE_NAMES.get(int(nt), "?"))

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
		"elapsed_since_last_piece_ms": elapsed_since_last
	}

	# ── 内存保护：滑动窗口 ──
	if _snapshots.size() >= MAX_SNAPSHOTS:
		_snapshots.pop_front()
		_discarded_snapshots += 1

	_snapshots.append(snapshot)
	_piece_index += 1


## 结束当前采集会话并将数据持久化写入磁盘。
## 应在 game_over 或玩家手动返回大厅时调用。
## 返回计算好的统计摘要字典（也可用于即时显示）。
func end_session(final_score: int, final_level: int, final_lines: int) -> Dictionary:
	if not _active:
		return {}
	_active = false

	var end_ticks_ms: int = Time.get_ticks_msec()
	var duration_seconds: float = (end_ticks_ms - _session_start_ticks_ms) / 1000.0
	var end_iso: String = _get_iso_datetime()

	# ── 计算核心指标 ──
	var pieces_placed: int = _piece_index
	var pps: float = pieces_placed / maxf(duration_seconds, 0.001)
	var duration_minutes: float = duration_seconds / 60.0
	var apm: float = _total_damage / maxf(duration_minutes, 0.001)
	var app: float = float(_total_damage) / maxf(float(pieces_placed), 1.0)
	var kpp: float = float(_total_key_presses) / maxf(float(pieces_placed), 1.0)

	# ── 雷达图评分 ──
	var radar: Dictionary = _calculate_radar_scores(pps, apm, app, kpp)

	# ── 构造会话数据 ──
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

	# ── 持久化 ──
	PlayerDataStore.save_session(session_data)

	# ── 更新累计统计 ──
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
		"pieces_placed": pieces_placed
	}
	PlayerDataStore.update_stats(_player_name, history_entry, radar)

	# ── 清理内存 ──
	_snapshots.clear()

	return session_data


## 获取当前会话已采集的方块数量（用于外部监控）。
func get_piece_count() -> int:
	return _piece_index


## 获取当前快照缓冲大小（用于外部监控）。
func get_snapshot_count() -> int:
	return _snapshots.size()


## 检查采集器是否正在活跃中。
func is_active() -> bool:
	return _active


# ==============================================================================
# 雷达图评分计算
# ==============================================================================

## 根据原始指标计算六芒星雷达图的6个维度评分（0-100）。
func _calculate_radar_scores(pps: float, apm: float, app: float, kpp: float) -> Dictionary:
	# ── 攻速 (Speed) ──
	var speed_score: float = clampf(pps / SPEED_PPS_MAX, 0.0, 1.0) * 100.0

	# ── 火力 (Attack) ──
	var attack_score: float = clampf(apm / ATTACK_APM_MAX, 0.0, 1.0) * 100.0

	# ── 效率 (Efficiency) ──
	var app_score: float = clampf(app / EFFICIENCY_APP_MAX, 0.0, 1.0) * 100.0
	# KPP 越低越好：线性映射 [WORST, BEST] -> [0, 100]
	var kpp_score: float = clampf(
		(EFFICIENCY_KPP_WORST - kpp) / (EFFICIENCY_KPP_WORST - EFFICIENCY_KPP_BEST),
		0.0, 1.0
	) * 100.0
	var efficiency_score: float = EFFICIENCY_APP_WEIGHT * app_score + EFFICIENCY_KPP_WEIGHT * kpp_score

	# ── 后三个维度暂未实现，预留接口，默认0 ──
	return {
		"speed": snapped(speed_score, 0.1),
		"attack": snapped(attack_score, 0.1),
		"efficiency": snapped(efficiency_score, 0.1),
		"topology": 0.0,   # 拓扑（预留）
		"holes": 0.0,      # 空洞（预留）
		"vision": 0.0      # 视野（预留）
	}


# ==============================================================================
# 工具方法
# ==============================================================================

## 获取当前 ISO 8601 日期时间字符串。
func _get_iso_datetime() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]
