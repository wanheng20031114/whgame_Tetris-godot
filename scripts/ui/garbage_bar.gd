class_name GarbageBar
extends Control

## 单人模式环境压力条 (Garbage Queue Bar)
##
## 用于可视化显示即将惩罚玩家的垃圾行，仿造 Tetris 99 左侧的受击队列槽。
## - 黄色 (Pending): 正在倒计时中的垃圾行（随时可以通过玩家主动消除来抵消护盾）
## - 红色 (Ready): 倒计时完毕的垃圾行（只要玩家本次放置没有消行，就会立刻破土而出顶上来）

# ==============================================================================
# 常量与状态变量
# ==============================================================================

## 槽位的最大行数容量（超出部分会被积压，但在视觉上会封顶）
var max_lines: int = 20

## 当前的平滑内部显示数值（利用 Tween 动画产生平滑缩放）
var display_grey: float = 0.0
var display_yellow: float = 0.0
var display_ready: float = 0.0

## 绘制相关的静态 UI 节点
@onready var bg_rect: ColorRect = $BgRect
@onready var grey_rect: ColorRect = $GreyRect
@onready var yellow_rect: ColorRect = $PendingRect
@onready var ready_rect: ColorRect = $ReadyRect
@onready var grid_overlay: Control = $GridOverlay

# ==============================================================================
# 生命周期
# ==============================================================================

func _ready() -> void:
	grid_overlay.draw.connect(_on_grid_draw)

func _process(_delta: float) -> void:
	if size.y <= 0: return
	
	# 每行对应多少像素高度
	var pixel_per_line: float = size.y / float(max_lines)
	
	var r_height: float = min(display_ready, max_lines) * pixel_per_line
	var max_y_lines: float = max(0.0, max_lines - display_ready)
	var y_height: float = min(display_yellow, max_y_lines) * pixel_per_line
	
	var max_g_lines: float = max(0.0, max_y_lines - display_yellow)
	var g_height: float = min(display_grey, max_g_lines) * pixel_per_line
	
	# 背景完全填满 Control 大小
	bg_rect.size = size
	bg_rect.position = Vector2.ZERO
	
	# 红色条（实装/危险）堆在底部
	ready_rect.size = Vector2(size.x, r_height)
	ready_rect.position = Vector2(0, size.y - r_height)
	
	# 黄色条（警告/迫近）堆在红色之上
	yellow_rect.size = Vector2(size.x, y_height)
	yellow_rect.position = Vector2(0, size.y - r_height - y_height)
	
	# 灰色条（远期/缓冲）堆在黄色之上
	grey_rect.size = Vector2(size.x, g_height)
	grey_rect.position = Vector2(0, size.y - r_height - y_height - g_height)
	
	# 让覆膜网格也跟着同步调整并重绘
	grid_overlay.size = size
	grid_overlay.position = Vector2.ZERO
	grid_overlay.queue_redraw()

func _on_grid_draw() -> void:
	if size.y <= 0: return
	var pixel_per_line: float = size.y / float(max_lines)
	
	# 绘制 20 个格子的黑色分割暗线
	for i in range(1, max_lines):
		var y: float = i * pixel_per_line
		grid_overlay.draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.05, 0.05, 0.07, 0.8), 2.0)

# ==============================================================================
# 对外接口
# ==============================================================================

## 根据内部逻辑层的伤害队列，更新显示的刻度
func update_bar(grey_count: int, yellow_count: int, ready_count: int) -> void:
	# 创建平滑插值动画，使得受击条有像呼吸一样的动态感
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "display_grey", float(grey_count), 0.25)
	tween.tween_property(self, "display_yellow", float(yellow_count), 0.25)
	tween.tween_property(self, "display_ready", float(ready_count), 0.25)
