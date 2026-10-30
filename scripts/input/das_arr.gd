class_name DASHandler
extends RefCounted

## DAS/ARR 输入处理器
##
## 竞技级俄罗斯方块的核心手感系统。不依赖操作系统的按键重复，
## 而是自行管理精确到毫秒的延迟和重复逻辑。
##
## DAS (Delayed Auto Shift)：按住方向键后，经过初始延迟才开始连续移动
## ARR (Auto Repeat Rate)：连续移动时每次移动的间隔
## 当 ARR = 0 时，按住方向键会瞬间移到墙边（竞技玩家最爱）

# ==============================================================================
# 可调参数（玩家可在设置中修改）
# ==============================================================================

## DAS 延迟（秒）：首次按下到开始重复的等待时间
var das_delay: float = 10.0 / 60.0

## ARR 间隔（秒）：重复移动之间的间隔。0 = 瞬移到墙
var arr_interval: float = 2.0 / 60.0

# ==============================================================================
# 内部状态
# ==============================================================================

## 当前激活的方向：-1=左, 0=无, 1=右
var direction: int = 0

## DAS 已经充能的时间
var _das_timer: float = 0.0

## DAS 是否已充满（开始 ARR 重复阶段）
var _das_charged: bool = false

## ARR 阶段的累积时间
var _arr_timer: float = 0.0

# ==============================================================================
# 公开接口
# ==============================================================================

## 开始跟踪某个方向（玩家按下方向键时调用）
func start(dir: int) -> void:
	direction = dir
	_das_timer = 0.0
	_arr_timer = 0.0
	_das_charged = false

## 停止跟踪（玩家松开方向键时调用）
func stop() -> void:
	direction = 0
	_das_charged = false

## DCD（DAS Cut Delay）：旋转贴墙后把 DAS 充能回退到 das - dcd，避免旋转后立刻被甩走
func cut(dcd: float) -> void:
	if direction == 0 or dcd <= 0.0:
		return
	_das_timer = minf(_das_timer, maxf(das_delay - dcd, 0.0))
	_das_charged = false
	_arr_timer = 0.0

## 每帧更新，返回本帧需要执行的移动次数
## 返回值：需要朝 direction 方向移动的次数（可能为 0）
func update(delta: float) -> int:
	if direction == 0:
		return 0

	_das_timer += delta
	var moves: int = 0
	# DAS 尚未充满，还在等待初始延迟
	if not _das_charged:
		if _das_timer < das_delay:
			return 0
		_das_charged = true
		_arr_timer = _das_timer - das_delay
		# 同一帧内跨过 DAS 与多个 ARR 间隔时，不能把这些移动推迟到下一帧。
		moves = 1
	else:
		_arr_timer += delta

	# DAS 已充满，进入 ARR 重复阶段
	if arr_interval <= 0.001:
		# ARR=0：每帧都瞬移到墙（返回大数）
		return 99

	while _arr_timer >= arr_interval:
		_arr_timer -= arr_interval
		moves += 1
	return moves
