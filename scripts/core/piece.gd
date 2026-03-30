class_name Piece
extends Node2D

## 现代方块表现层实体。
##
## 本脚本控制单一的方块实例，包括形状选取、坐标变更。
## 最重要的是，本类抛弃贴图，通过 Godot 提供的底层 CanvasItem._draw() 方法，
## 【程序化地渲染】由几何计算出的发光彩色小方块格子。

# ==============================================================================
# 变量声明
# ==============================================================================

## 当前方块所属的大类型 (I, O, T 等)
var piece_type: PieceData.Type
## 当前方块的旋转状态 (朝向)
var current_rotation: PieceData.RotationState = PieceData.RotationState.SPAWN
## 当前方块基础颜色 (取自 PieceData)
var piece_color: Color

## 单个格子的实际像素大小（通过检查器或场景树设置）
@export var cell_size: float = 30.0

# ==============================================================================
# 核心初始化逻辑
# ==============================================================================

## 设置方块类型并激活渲染。cell_size 由场景树或 @export 预先设定，不需要每次传入。
func initialize(type: PieceData.Type) -> void:
	self.piece_type = type
	self.current_rotation = PieceData.RotationState.SPAWN
	self.piece_color = PieceData.COLORS[type]
	queue_redraw()

# ==============================================================================
# 核心绘制逻辑 (Procedural Generation)
# ==============================================================================

## Godot 内置回调，在帧更新中（或者我们手动调用 queue_redraw()时）被触发。
## 这里我们开始进行最爽的 UI 程序化着色！可以随心打光、加内阴影。
func _draw() -> void:
	if piece_type == null: return
	
	# 获取当前在核心字典 SHAPES 里的该朝向的四个小格子的相对坐标
	var shape_coords: Array = PieceData.SHAPES[piece_type][current_rotation]
	
	# 绘制构成这块形状的每一个 1x1 小四方块格子
	for coord in shape_coords:
		var x = coord.x * cell_size
		var y = coord.y * cell_size
		
		# 使用 Rect2 限定出这个小方格的位置和尺寸
		var rect = Rect2(Vector2(x, y), Vector2(cell_size, cell_size))
		
		# == 主填涂色 (使用我们的霓虹色系) ==
		draw_rect(rect, piece_color)
		
		# == 高级 UI 设计：内部分层光效，替代简单生硬的描边 ==
		# 外框深色，制造边缘阴影材质立体感
		draw_rect(rect, piece_color.darkened(0.3), false, 2.0)
		
		# 内框提亮，制造屏幕泛光灯柱特效（玻璃拟物风或者科技高透）
		var inner_rect = rect.grow(-4.0) # 内缩 4 像素
		draw_rect(inner_rect, piece_color.lightened(0.4), false, 1.0)
		
		# 如果之后需要加发光外发散，我们可以加入基于 Shader 材质的 Bloom
		# 不过目前依靠不同色彩深度的互相印衬，就足以生成“非常酷”的视觉表现了

# ==============================================================================
# 游戏辅助功能接口
# ==============================================================================

## 强制让渲染层更换方向并重绘自己（注意：调用前由外部引擎确信旋转不冲突）
func apply_rotation(new_rot: PieceData.RotationState) -> void:
	current_rotation = new_rot
	queue_redraw()

## 修改颜色以变身幽灵方块 (Ghost Piece)
## 透明化并大幅提高明度边缘。用来让玩家预知坠落点
func set_as_ghost() -> void:
	var base = PieceData.COLORS[piece_type]
	# 面漆设为超低透明 (只留下一丝魂气)
	piece_color = Color(base.r, base.g, base.b, 0.2)
	queue_redraw()
