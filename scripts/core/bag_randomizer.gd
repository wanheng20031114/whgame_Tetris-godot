class_name BagRandomizer
extends RefCounted

## 7-Bag 随机生成器
##
## 现代俄罗斯方块的标准随机系统：每个"袋子"包含全部 7 种方块，
## 打乱顺序后依次发放。保证公平性——最多间隔 12 个方块必定出现任何特定方块。
## 支持 Next 预览队列（至少 5 个）。

# ==============================================================================
# 内部状态
# ==============================================================================

## 当前袋子中剩余的方块队列
var _queue: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 全部 7 种方块类型的列表（用于生成新袋子）
const ALL_TYPES: Array = [
	PieceData.Type.I,
	PieceData.Type.O,
	PieceData.Type.T,
	PieceData.Type.S,
	PieceData.Type.Z,
	PieceData.Type.J,
	PieceData.Type.L
]

# ==============================================================================
# 公开接口
# ==============================================================================

## 初始化：预填充足够多的方块到队列中（至少 2 袋 = 14 个）
func _init() -> void:
	_rng.randomize()
	_fill_queue()
	_fill_queue()

## 使用指定种子重置随机序列（用于多人对战统一发牌）
func reset_with_seed(seed_value: int) -> void:
	_queue.clear()
	_rng.seed = seed_value
	_fill_queue()
	_fill_queue()

## 取出队列中的下一个方块类型
func next() -> PieceData.Type:
	# 如果队列快空了（少于 7 个），追加一袋新的
	if _queue.size() < 7:
		_fill_queue()
	return _queue.pop_front()

## 预览接下来的 N 个方块（不取出）
func peek(count: int = 5) -> Array:
	# 确保队列足够长
	while _queue.size() < count:
		_fill_queue()
	return _queue.slice(0, count)

# ==============================================================================
# 内部逻辑
# ==============================================================================

## 生成一个新的袋子（包含全部 7 种方块，随机打乱），追加到队列末尾
func _fill_queue() -> void:
	var bag = ALL_TYPES.duplicate()
	# Fisher-Yates 洗牌算法，保证完全随机
	for i in range(bag.size() - 1, 0, -1):
		var j = _rng.randi_range(0, i)
		var temp = bag[i]
		bag[i] = bag[j]
		bag[j] = temp
	_queue.append_array(bag)
