class_name PieceData
extends RefCounted

## 现代俄罗斯方块 (WIDE TETRIS) 核心数据常量库
##
## 本文件记录了所有 7 种标准方块的几何形状数据、现代高级渐变颜色、
## 以及 SRS (Super Rotation System) 对应的四方向顺/逆时针墙踢 (Wall Kick) 偏移表。
## 所有注释强制采用中文撰写，方便理解和后续大幅度重构与调整。

# ------------------------------------------------------------------------------
# 1. 核心定义：方块类型与状态枚举
# ------------------------------------------------------------------------------

## 标准的 7 种方块枚举（依据 Tetris Guideline）
enum Type {
	I, O, T, S, Z, J, L
}

## 四个方向的旋转状态（影响墙踢判断）
## 0 = 出生状态 (面向玩家)
## R = 相比出生态顺时针旋转了 90° (Right)
## 2 = 相比出生态旋转了 180° (倒置)
## L = 相比出生态逆时针旋转了 90° (Left)
enum RotationState {
	SPAWN = 0, # 测试时常常写作 0
	R = 1,
	TWO = 2,
	L = 3
}

# ------------------------------------------------------------------------------
# 2. 现代极度炫酷色彩配置 (Premium Color Palette)
# ------------------------------------------------------------------------------

## 放弃了传统原色，采用经过精心挑选的高级霓虹渐变与明亮马卡龙色系。
## 可以根据后续 UI 需求更换为高闪光材质。
const COLORS: Dictionary = {
	Type.I: Color("00ffff"), # 赛博青 (Cyan)
	Type.O: Color("ffd500"), # 警示黄 (Yellow)
	Type.T: Color("d022bfff"), # 霓虹紫 (Purple)
	Type.S: Color("78e850ff"), # 毒药绿 (Green)
	Type.Z: Color("f35049ff"), # 警示红 (Red)
	Type.J: Color("006eff"), # 深邃蓝 (Blue)
	Type.L: Color("ff7b00"), # 能量橙 (Orange)
}

# ------------------------------------------------------------------------------
# 3. 各种方块在不同旋转状态下的相对网格坐标体系
# ------------------------------------------------------------------------------
##
## 这个体系记录了每个方块 4 个朝向的局部坐标网格映射。
## 基准：原点 (0, 0) 为旋转轴心。X 轴向右为正，Y 轴向下为正（Godot 屏幕坐标系）。

const SHAPES: Dictionary = {
	Type.T: {
		RotationState.SPAWN: [Vector2(0, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0)],
		RotationState.R: [Vector2(0, -1), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
		RotationState.TWO: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
		RotationState.L: [Vector2(0, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1)]
	},
	Type.O: {
		# O 只有一种形态，不进行物理矩阵旋转。只负责做碰撞检测。
		RotationState.SPAWN: [Vector2(0, -1), Vector2(1, -1), Vector2(0, 0), Vector2(1, 0)],
		RotationState.R: [Vector2(0, -1), Vector2(1, -1), Vector2(0, 0), Vector2(1, 0)],
		RotationState.TWO: [Vector2(0, -1), Vector2(1, -1), Vector2(0, 0), Vector2(1, 0)],
		RotationState.L: [Vector2(0, -1), Vector2(1, -1), Vector2(0, 0), Vector2(1, 0)]
	},
	Type.I: {
		RotationState.SPAWN: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)],
		RotationState.R: [Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(1, 2)],
		RotationState.TWO: [Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1)],
		RotationState.L: [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(0, 2)]
	},
	Type.J: {
		RotationState.SPAWN: [Vector2(-1, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0)],
		RotationState.R: [Vector2(0, -1), Vector2(1, -1), Vector2(0, 0), Vector2(0, 1)],
		RotationState.TWO: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
		RotationState.L: [Vector2(0, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(0, 1)]
	},
	Type.L: {
		RotationState.SPAWN: [Vector2(1, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0)],
		RotationState.R: [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
		RotationState.TWO: [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(-1, 1)],
		RotationState.L: [Vector2(-1, -1), Vector2(0, -1), Vector2(0, 0), Vector2(0, 1)]
	},
	Type.S: {
		RotationState.SPAWN: [Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(0, 0)],
		RotationState.R: [Vector2(0, -1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
		RotationState.TWO: [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1)],
		RotationState.L: [Vector2(-1, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1)]
	},
	Type.Z: {
		RotationState.SPAWN: [Vector2(-1, -1), Vector2(0, -1), Vector2(0, 0), Vector2(1, 0)],
		RotationState.R: [Vector2(1, -1), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
		RotationState.TWO: [Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
		RotationState.L: [Vector2(0, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(-1, 1)]
	}
}

# ------------------------------------------------------------------------------
# 4. 旋转的墙踢检测表 (Wall Kick Offset Table)
# ------------------------------------------------------------------------------
## 
## 注意：下面记录的偏移向量单位是格子，正负号符合 Godot 本地 Y 轴 (Y 轴向下为正)。
## 例如，标准文档上的 Y=1 (即相对自身往上移动 1 格)，在 Godot Y轴向下的坐标系中应该是 Y=-1。
## 根据我们的约定，我们将用 Y 轴朝下的方向翻译 SRS 国际踢墙常数。

## J, L, S, T, Z 共享的一般踢墙表
const WALL_KICK_NORMAL: Dictionary = {
	# 状态 "0" 转 "R" (顺时针)
	"0->1": [Vector2(0, 0), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, 2), Vector2(-1, 2)],
	"1->0": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, -2), Vector2(1, -2)],
	"1->2": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, -2), Vector2(1, -2)],
	"2->1": [Vector2(0, 0), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, 2), Vector2(-1, 2)],
	"2->3": [Vector2(0, 0), Vector2(1, 0), Vector2(1, -1), Vector2(0, 2), Vector2(1, 2)],
	"3->2": [Vector2(0, 0), Vector2(-1, 0), Vector2(-1, 1), Vector2(0, -2), Vector2(-1, -2)],
	"3->0": [Vector2(0, 0), Vector2(-1, 0), Vector2(-1, 1), Vector2(0, -2), Vector2(-1, -2)],
	"0->3": [Vector2(0, 0), Vector2(1, 0), Vector2(1, -1), Vector2(0, 2), Vector2(1, 2)]
}

## I 块专门的踢墙表（特别且复杂，因为它是 4 格宽度导致旋转偏差大）
const WALL_KICK_I: Dictionary = {
	"0->1": [Vector2(0, 0), Vector2(-2, 0), Vector2(1, 0), Vector2(-2, 1), Vector2(1, -2)],
	"1->0": [Vector2(0, 0), Vector2(2, 0), Vector2(-1, 0), Vector2(2, -1), Vector2(-1, 2)],
	"1->2": [Vector2(0, 0), Vector2(-1, 0), Vector2(2, 0), Vector2(-1, -2), Vector2(2, 1)],
	"2->1": [Vector2(0, 0), Vector2(1, 0), Vector2(-2, 0), Vector2(1, 2), Vector2(-2, -1)],
	"2->3": [Vector2(0, 0), Vector2(2, 0), Vector2(-1, 0), Vector2(2, -1), Vector2(-1, 2)],
	"3->2": [Vector2(0, 0), Vector2(-2, 0), Vector2(1, 0), Vector2(-2, 1), Vector2(1, -2)],
	"3->0": [Vector2(0, 0), Vector2(1, 0), Vector2(-2, 0), Vector2(1, 2), Vector2(-2, -1)],
	"0->3": [Vector2(0, 0), Vector2(-1, 0), Vector2(2, 0), Vector2(-1, -2), Vector2(2, 1)]
}

## 获取踢墙检测序列参数封装
static func get_wall_kicks(type: Type, from_state: RotationState, to_state: RotationState) -> Array:
	var key = str(from_state) + "->" + str(to_state)
	if type == Type.O:
		# O 方块不涉及踢墙，原位碰撞通过即可
		return [Vector2(0, 0)]
	elif type == Type.I:
		return WALL_KICK_I.get(key, [Vector2(0, 0)])
	else:
		return WALL_KICK_NORMAL.get(key, [Vector2(0, 0)])
