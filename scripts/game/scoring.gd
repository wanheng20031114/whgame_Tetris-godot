class_name Scoring
extends RefCounted

## 计分与等级系统
##
## 管理分数、等级、消行数、连击（Combo）、背靠背（B2B）等所有得分逻辑。
## 支持 All Spin Bonus：不仅 T-Spin，任何方块的 Spin 都给予额外奖励。

# ==============================================================================
# 分数常量表
# ==============================================================================

## 普通消行基础分（乘以当前等级）
const LINE_SCORES: Dictionary = {
	1: 100, # Single
	2: 300, # Double
	3: 500, # Triple
	4: 800 # Tetris
}

## Spin 消行基础分（All Spin Bonus，乘以当前等级）
const SPIN_SCORES: Dictionary = {
	0: 400, # Spin 但没消行（只旋转入位）
	1: 800, # Spin Single
	2: 1200, # Spin Double
	3: 1600, # Spin Triple
	4: 2000 # Spin Tetris（极罕见）
}

## Combo 加成：连续消行时额外发送的垃圾行数（也乘以 50 分）
const COMBO_BONUS: Array = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5]

## 重力速度表（等级 -> 每秒下落格数）
const GRAVITY_TABLE: Dictionary = {
	1: 1.0, 2: 1.2, 3: 1.5, 4: 1.8, 5: 2.2,
	6: 2.7, 7: 3.3, 8: 4.0, 9: 5.0, 10: 6.0,
	11: 7.5, 12: 9.0, 13: 11.0, 14: 14.0, 15: 20.0
}

# ==============================================================================
# 状态变量
# ==============================================================================

var score: int = 0 ## 当前总分
var level: int = 1 ## 当前等级
var lines: int = 0 ## 已消除的总行数
var combo: int = -1 ## 当前连击计数（-1 表示无连击状态）
var b2b: int = -1 ## Back-to-Back 计数（连续困难消除次数，-1=无）

## 信号：分数/等级变化时通知 UI 更新
signal score_changed(new_score: int)
signal level_changed(new_level: int)
signal lines_changed(new_lines: int)

# ==============================================================================
# 核心接口
# ==============================================================================

## 处理一次消行事件
## lines_cleared: 本次消除的行数（0-4）
## is_spin: 是否为 Spin 消除（All Spin Bonus 判定）
## is_t_piece: 是否为 T 方块（用于区分 T-Spin 和普通 Spin）
func process_line_clear(lines_cleared: int, is_spin: bool, _is_t_piece: bool) -> void:
	if lines_cleared <= 0 and not is_spin:
		return

	# 1. 计算基础分
	var base: int = 0
	if is_spin:
		base = SPIN_SCORES.get(lines_cleared, 0)
	else:
		base = LINE_SCORES.get(lines_cleared, 0)

	# 2. 判断是否为"困难消除"（Tetris 或任何 Spin 消行）
	var is_difficult: bool = is_spin or lines_cleared >= 4

	# 3. B2B 加成
	if is_difficult:
		b2b += 1
		if b2b > 0:
			# B2B 激活时，基础分增加 50%
			base = int(base * 1.5)
	else:
		b2b = -1

	# 4. Combo 连击加成
	combo += 1
	var combo_score: int = 0
	if combo > 0:
		var combo_idx: int = mini(combo, COMBO_BONUS.size() - 1)
		combo_score = COMBO_BONUS[combo_idx] * 50 * level

	# 5. 最终得分 = 基础分 × 等级 + 连击加成
	var total: int = base * level + combo_score
	score += total

	# 6. 更新消行数和等级
	lines += lines_cleared
	var new_level: int = (lines / 10) + 1
	if new_level != level:
		level = new_level

## 重置连击（本次放置方块没有消行时调用）
func reset_combo() -> void:
	combo = -1

## 硬降得分（每下落一格 2 分）
func add_hard_drop_score(cells: int) -> void:
	score += cells * 2

## 软降得分（每下落一格 1 分）
func add_soft_drop_score(cells: int) -> void:
	score += cells

## 获取当前等级对应的重力速度（格/秒）
func get_gravity_speed() -> float:
	if level >= 15:
		return GRAVITY_TABLE[15]
	return GRAVITY_TABLE.get(level, 1.0)
