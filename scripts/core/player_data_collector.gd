# ==========================================
# PlayerDataCollector (玩家游戏数据采集器)
# 
# 文件整体作用：
# 此文件作为一个实时数据采集与计算的核心组件存在，主要负责：
# 1. 对局追踪：在单局游戏的不同生命周期（开始、每次落块、结束）记录各种原始数据。
# 2. 状态快照：针对玩家每次下落一个方块，保存一帧详细场景状态（包含棋盘、打分、连击、使用的按键数量等）形成的“快照”。
# 3. 统计累加：对游玩期间的按键次数、消行数据、T-Spin（T旋操作）等进行全场景累加与统计。
# 4. 指标计算：支持实时评估并计算高级进阶向的雷达能力六项指标（如攻击力、效率、视野等）。
# 5. 将聚合后的复杂结果最终打包输出给 PlayerDataStore 存储保存。
# ==========================================
class_name PlayerDataCollector
extends RefCounted

const SNAPSHOT_ESTIMATED_BYTES: int = 1200
const MEMORY_LIMIT_BYTES: int = 2_000_000_000
const MAX_SNAPSHOTS: int = 1_666_666

const PIECE_TYPE_NAMES: Dictionary = {
	0: "I", 1: "O", 2: "T", 3: "S", 4: "Z", 5: "J", 6: "L"
}

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

var key_presses_this_piece: int = 0

var _snapshots: Array = []
var _discarded_snapshots: int = 0
var _piece_index: int = 0

var _total_damage: int = 0
var _total_key_presses: int = 0
var _structure_score_sum: float = 0.0
var _stability_score_sum: float = 0.0
var _structure_samples: int = 0

var _effective_clear_events: int = 0
var _spin_clear_events: int = 0
var _tetris_clear_events: int = 0
var _other_clear_events: int = 0

var _singles: int = 0
var _doubles: int = 0
var _triples: int = 0
var _tetrises: int = 0
var _spin_clears: int = 0
var _t_spin_clears: int = 0

var _max_combo: int = 0
var _max_b2b: int = 0


# ==========================================
# start_session(player_name)
# 
# 作用：标志一场全新单局游戏数据采集的开始。
# 参数：
# - player_name: 参与该局游戏的玩家名字。
# 逻辑：
# 1. 标记采集器为“激活”状态（_active = true）。
# 2. 初始化核心起始数据，例如游戏局内的运行时间戳、ISO格式标准时间。
# 3. 将之前局所有遗留的变量、统计值、收集过的快照信息等全部清零与重置。
# ==========================================
func start_session(player_name: String) -> void:
	_active = true
	_player_name = player_name
	_session_start_ticks_ms = Time.get_ticks_msec()
	_session_start_iso = _get_iso_datetime()
	_last_piece_ticks_ms = _session_start_ticks_ms

	_piece_index = 0
	_total_damage = 0
	_total_key_presses = 0
	_structure_score_sum = 0.0
	_stability_score_sum = 0.0
	_structure_samples = 0

	_effective_clear_events = 0
	_spin_clear_events = 0
	_tetris_clear_events = 0
	_other_clear_events = 0

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


# ==========================================
# record_piece_drop(...)
# 
# 作用：在游戏期间每当一个方块自然落下或者硬降落地并锁定后被触发，进行一次高频数据采样与累加。
# 参数（由于较多，摘录部分重要参数说明）：
# - piece_type, rotation, col, row: 当前落下并锁定方块的种类、旋转状态与所在行列。
# - board_state_visible: 玩家当前可见的棋盘截面。
# - score, level, lines_cleared_total: 当下游戏的总分数、等级和总消行数。
# - combo, b2b: 当前连击数以及背靠背（Back-to-Back）状态。
# - is_spin / is_t_spin: 判断该方块是否属于普通旋转或者高阶技术T旋。
# - damage_this_lock: 单次落块产生的对敌（或自适应）伤害数值。
# - hold_used_this_piece: 本次操作是否利用了 Hold（暂存）区。
# - structure_score / stability_score: 由结构评分器给出的地形结构平整度、稳定空洞度得分。
# 
# 逻辑：
# 1. 判断并跳过未激活状态下的意外触发。
# 2. 累加并计算自上次落块到现在的用时（影响速度计算）。
# 3. 分类判定单杀、双杀、三杀、四杀（Tetris）以及各类旋转清行技，并记录次数。
# 4. 汇总总局伤害、总按键记录与各类最高纪录（最大连击等）。
# 5. 生成一帧完整环境“数据快照”，并压入历史序列中。
# 6. 为防止内存溢出，最多仅保留最近定量的 MAX_SNAPSHOTS 快照，超过即淘汰首项。
# ==========================================
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
	held_type: int,
	structure_score: float,
	stability_score: float,
	board_after_drop: Array = [],
	board_after_clear: Array = []
) -> void:
	if not _active:
		return

	var now_ms: int = Time.get_ticks_msec()
	var elapsed_since_last: int = now_ms - _last_piece_ticks_ms
	_last_piece_ticks_ms = now_ms

	var kp: int = key_presses_this_piece
	_total_key_presses += kp
	key_presses_this_piece = 0

	_total_damage += damage_this_lock
	_structure_score_sum += structure_score
	_stability_score_sum += stability_score
	_structure_samples += 1

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

	if lines_cleared_this_lock > 0:
		_effective_clear_events += 1
		if is_spin or is_t_spin:
			_spin_clear_events += 1
		elif lines_cleared_this_lock >= 4:
			_tetris_clear_events += 1
		else:
			_other_clear_events += 1

	if combo > _max_combo:
		_max_combo = combo
	if b2b > _max_b2b:
		_max_b2b = b2b

	var next_names: Array = []
	for nt in next_pieces:
		next_names.append(PIECE_TYPE_NAMES.get(int(nt), "?"))

	# 使用消行后的棋盘计算 MLP 地形特征
	var terrain_board: Array = board_after_clear if not board_after_clear.is_empty() else board_state_visible
	var holes: int = _calculate_holes(terrain_board)
	var bumpiness: int = _calculate_bumpiness(terrain_board)
	var total_height: int = _calculate_total_height(terrain_board)

	var snapshot: Dictionary = {
		"piece_index": _piece_index,
		"timestamp_ms": now_ms - _session_start_ticks_ms,
		"piece_type": PIECE_TYPE_NAMES.get(piece_type, "?"),
		"rotation": rotation,
		"col": col,
		"row": row,
		"board_state_after_drop": board_after_drop if not board_after_drop.is_empty() else board_state_visible,
		"board_state_after_clear": terrain_board,
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
		"hold_piece": PIECE_TYPE_NAMES.get(held_type, "") if held_type >= 0 else "",
		"elapsed_since_last_piece_ms": elapsed_since_last,
		"structure_score": snapped(structure_score, 0.1),
		"stability_score": snapped(stability_score, 0.1),
		"holes": holes,
		"bumpiness": bumpiness,
		"total_height": total_height
	}

	if _snapshots.size() >= MAX_SNAPSHOTS:
		_snapshots.pop_front()
		_discarded_snapshots += 1

	_snapshots.append(snapshot)
	_piece_index += 1


# ==========================================
# end_session(final_score, final_level, final_lines)
# 
# 作用：结束并封存当前对局，并开始进行一系列最终复盘数据的计算（结算阶段）。
# 参数：
# - final_score, final_level, final_lines: 游戏自然死亡或人为结束时的最终分、最终等级及总计消行。
# 逻辑：
# 1. 将状态更改回未激活并记录结束时刻。
# 2. 深入计算各种综合型评价指标表达式，如：
#    - pps (Pieces Per Second): 每秒落块速度。
#    - apm (Attack Per Minute): 每分钟攻击输出值。
#    - app (Attack Per Piece): 每次落块攻击效率。
#    - kpp (Keypress Per Piece): 单个方块的平均按键消耗数。
# 3. 将整局中采集过且平均化后的结构与稳定度带入到 _calculate_radar_scores 中计算出最最终局后六维雷达表。
# 4. 把长长的各类明细指标封包成宏大 Session 对象，呼叫 PlayerDataStore 将该单局写入硬盘。
# 5. 同时生成简单摘要版的 history_entry，告知其并入全局状态之中。
# 6. 抹除长列快照信息准备释放内存。
# 返回：整理合并完毕后的当局详细 Dictionary 数据对象。
# ==========================================
func end_session(final_score: int, final_level: int, final_lines: int) -> Dictionary:
	if not _active:
		return {}
	_active = false

	var end_ticks_ms: int = Time.get_ticks_msec()
	var duration_seconds: float = (end_ticks_ms - _session_start_ticks_ms) / 1000.0
	var end_iso: String = _get_iso_datetime()

	var pieces_placed: int = _piece_index
	var pps: float = pieces_placed / maxf(duration_seconds, 0.001)
	var duration_minutes: float = duration_seconds / 60.0
	var apm: float = _total_damage / maxf(duration_minutes, 0.001)
	var app: float = float(_total_damage) / maxf(float(pieces_placed), 1.0)
	var kpp: float = float(_total_key_presses) / maxf(float(pieces_placed), 1.0)

	var avg_structure: float = _structure_score_sum / maxf(float(_structure_samples), 1.0)
	var avg_stability: float = _stability_score_sum / maxf(float(_structure_samples), 1.0)
	var radar: Dictionary = _calculate_radar_scores(pps, apm, app, kpp, avg_structure, avg_stability)

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
		"effective_clear_events": _effective_clear_events,
		"spin_clear_events": _spin_clear_events,
		"tetris_clear_events": _tetris_clear_events,
		"other_clear_events": _other_clear_events,
		"max_combo": _max_combo,
		"max_b2b": _max_b2b,
		"discarded_snapshots": _discarded_snapshots,
		"radar_scores": radar,
		"snapshots": _snapshots
	}

	PlayerDataStore.save_session(session_data)

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
		"structure": avg_structure,
		"stability": avg_stability,
		"pieces_placed": pieces_placed
	}
	PlayerDataStore.update_stats(_player_name, history_entry, radar)

	_snapshots.clear()
	return session_data


# ==========================================
# get_piece_count() / get_snapshot_count() / is_active()
# 
# 作用：一组对外部可见的简单状态查询只读（Getter）方法。
# - get_piece_count()：当前局游戏下落且锁死的总方块数。
# - get_snapshot_count()：查询目前在内存中缓存了多少帧经过精细记录的快照。
# - is_active()：获取目前数据收集器是否处在开启正在记录打分的状态。
# ==========================================
func get_piece_count() -> int:
	return _piece_index


func get_snapshot_count() -> int:
	return _snapshots.size()


func is_active() -> bool:
	return _active


# ==========================================
# _map_curve(value, points)
# 
# 作用：通用的非线性经验映射函数，用于在一系列 (x, y) 坐标点之间进行线性插值，得出平滑的分数。
# ==========================================
func _map_curve(value: float, points: Array) -> float:
	if points.is_empty():
		return 0.0
	if value <= points[0].x:
		return points[0].y
	if value >= points[-1].x:
		return points[-1].y
		
	for i in range(points.size() - 1):
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		if value >= p1.x and value <= p2.x:
			var t: float = (value - p1.x) / (p2.x - p1.x)
			return lerpf(p1.y, p2.y, t)
	return 0.0


# ==========================================
# _calculate_radar_scores(...)
# 
# 作用：计算雷达图各项能力得分，使用多级非线性映射曲线。
# ==========================================
func _calculate_radar_scores(
	pps: float,
	apm: float,
	app: float,
	kpp: float,
	structure_score: float,
	stability_score: float
) -> Dictionary:
	# 速度映射：阶梯上升，2.8及以上满分
	var speed_points: Array = [
		Vector2(0.0, 0.0), 
		Vector2(0.3, 20.0), 
		Vector2(1.0, 60.0), 
		Vector2(2.2, 85.0), 
		Vector2(2.8, 100.0)
	]
	var speed_score: float = _map_curve(pps, speed_points)

	# 攻击映射：120 极限满分，70 分水岭
	var attack_points: Array = [
		Vector2(0.0, 0.0),
		Vector2(30.0, 50.0),
		Vector2(50.0, 70.0),
		Vector2(70.0, 85.0),
		Vector2(120.0, 100.0)
	]
	var attack_score: float = _map_curve(apm, attack_points)

	# 效率-单块攻击（APP）映射：0.6 及以上满分满效
	var app_points: Array = [
		Vector2(0.0, 0.0),
		Vector2(0.2, 40.0),
		Vector2(0.4, 75.0),
		Vector2(0.5, 90.0),
		Vector2(0.6, 100.0)
	]
	var app_score: float = _map_curve(app, app_points)

	# 效率-按键（KPP）映射：倒梯形，越少越好，11极其以上0分
	var kpp_points: Array = [
		Vector2(3.0, 100.0),  # 放宽到3以内100
		Vector2(6.0, 80.0),
		Vector2(9.0, 60.0),
		Vector2(10.0, 20.0),
		Vector2(11.0, 0.0)
	]
	var kpp_score: float = _map_curve(kpp, kpp_points)

	var efficiency_score: float = EFFICIENCY_APP_WEIGHT * app_score + EFFICIENCY_KPP_WEIGHT * kpp_score
	var vision_score: float = _calculate_vision_score()

	return {
		"speed": snapped(speed_score, 0.1),
		"attack": snapped(attack_score, 0.1),
		"efficiency": snapped(efficiency_score, 0.1),
		"structure": snapped(clampf(structure_score, 0.0, 100.0), 0.1),
		"stability": snapped(clampf(stability_score, 0.0, 100.0), 0.1),
		"vision": snapped(vision_score, 0.1)
	}


# ==========================================
# _calculate_vision_score()
# 
# 作用：采用“保底分+动作加分”算法计算视野（大局观）。奖励高级消行能力。
# ==========================================
func _calculate_vision_score() -> float:
	var base_score: float = 40.0
	if _effective_clear_events <= 0:
		return base_score

	var total: float = float(_effective_clear_events)
	var spin_ratio: float = float(_spin_clear_events) / total
	var tetris_ratio: float = float(_tetris_clear_events) / total
	var triple_ratio: float = float(_triples) / total  # 注意这里使用三消的比例

	# 根据不同强度的消行方式赋予不同的增益权重
	var bonus_multiplier: float = 50.0
	var spin_weight: float = 1.5
	var tetris_weight: float = 1.0
	var triple_weight: float = 0.3

	var bonus_score: float = (spin_ratio * spin_weight + tetris_ratio * tetris_weight + triple_ratio * triple_weight) * bonus_multiplier
	
	return clampf(base_score + bonus_score, 0.0, 100.0)



# ==========================================
# _get_iso_datetime()
# 
# 作用：工具方法，从操作系统引擎层面直接捕获现在时钟时刻。
# 返回：一条 YYYY-MM-DDTHH:MM:SS 标准格式字符组合，方便直接做文件命名和日志校准。
# ==========================================
func _get_iso_datetime() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]


# ==========================================
# MLP 地形特征计算方法
# 用于在每次落锁后计算棋盘的空洞数、凹凸度、总高度，
# 这些是 MLP 模型推理所需的 4 个状态特征中的 3 个
# （第 4 个 lines_cleared 已在 snapshot 中记录）。
# ==========================================


# 计算棋盘中的空洞总数。
# 空洞定义：某列中，最高实块以下的所有空格。
func _calculate_holes(board: Array) -> int:
	var rows: int = board.size()
	if rows <= 0:
		return 0
	var cols: int = (board[0] as Array).size() if rows > 0 else 0
	var num_holes: int = 0
	for c in range(cols):
		var found_block: bool = false
		for r in range(rows):
			var cell: int = int(board[r][c])
			if cell != 0:
				found_block = true
			elif found_block:
				num_holes += 1
	return num_holes


# 计算相邻列高度差的绝对值之和（凹凸度）。
func _calculate_bumpiness(board: Array) -> int:
	var heights: Array = _get_column_heights(board)
	var bumpiness: int = 0
	for i in range(heights.size() - 1):
		bumpiness += absi(int(heights[i]) - int(heights[i + 1]))
	return bumpiness


# 计算所有列高度的总和。
func _calculate_total_height(board: Array) -> int:
	var heights: Array = _get_column_heights(board)
	var total: int = 0
	for h in heights:
		total += int(h)
	return total


# 获取每列的高度（从底部算起到最高实块的距离）。
func _get_column_heights(board: Array) -> Array:
	var rows: int = board.size()
	if rows <= 0:
		return []
	var cols: int = (board[0] as Array).size() if rows > 0 else 0
	var heights: Array = []
	for c in range(cols):
		var col_height: int = 0
		for r in range(rows):
			if int(board[r][c]) != 0:
				col_height = rows - r
				break
		heights.append(col_height)
	return heights
