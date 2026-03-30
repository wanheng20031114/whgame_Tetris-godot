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
var das_delay: float = 0.180

## ARR 间隔（秒）：重复移动之间的间隔。0 = 瞬移到墙
var arr_interval: float = 0.020

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

## 每帧更新，返回本帧需要执行的移动次数
## 返回值：需要朝 direction 方向移动的次数（可能为 0）
func update(delta: float) -> int:
	if direction == 0:
		return 0

	_das_timer += delta
	# DAS 尚未充满，还在等待初始延迟
	if not _das_charged:
		if _das_timer >= das_delay:
			_das_charged = true
			_arr_timer = 0.0
			# DAS 刚充满的瞬间，触发第一次重复移动
			if arr_interval <= 0.001:
				# ARR=0 模式：返回一个很大的数，外部会移动到墙边
				return 99
			else:
				return 1
		return 0

	# DAS 已充满，进入 ARR 重复阶段
	if arr_interval <= 0.001:
		# ARR=0：每帧都瞬移到墙（返回大数）
		return 99

	_arr_timer += delta
	var moves: int = 0
	while _arr_timer >= arr_interval:
		_arr_timer -= arr_interval
		moves += 1
	return moves
