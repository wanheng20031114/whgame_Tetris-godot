class_name LineClearEffect
extends Node2D

## 消行粒子爆炸效果
##
## 在每个被消除的格子位置生成一组方块碎片粒子，
## 带有向外爆炸扩散 + 重力下落 + 淡出效果。
## 全部播放完毕后自动销毁。

# 粒子参数
const PARTICLE_COUNT_PER_CELL: int = 4       ## 每格子生成的碎片数
const PARTICLE_LIFETIME: float = 0.65        ## 粒子存活时长
const PARTICLE_SIZE: float = 4.0             ## 碎片初始尺寸
const EXPLOSION_SPEED: float = 200.0         ## 爆炸初速度
const GRAVITY: float = 400.0                 ## 粒子重力加速度
const FLASH_DURATION: float = 0.08           ## 消行白色闪光时长

var _particles: Array = []     # [{pos, vel, color, life, max_life, size}]
var _flash_timer: float = 0.0
var _flash_rects: Array = []   # [Rect2] 闪光矩形
var _total_lifetime: float = 0.0
var _finished: bool = false

## 初始化消行效果
## cleared_rows_data: Array of { row_index: int, colors: Array[Color or null] }
## cell_size: 单格像素尺寸
## buffer_rows: 缓冲行数（用于计算屏幕 Y 坐标偏移）
func setup(cleared_rows_data: Array, cell_size: float, buffer_rows: int) -> void:
	_particles.clear()
	_flash_rects.clear()
	_flash_timer = FLASH_DURATION

	for row_data in cleared_rows_data:
		var row_idx: int = row_data["row_index"]
		var colors: Array = row_data["colors"]
		var vis_row: int = row_idx - buffer_rows

		for col in range(colors.size()):
			var cell_color = colors[col]
			if cell_color == null:
				continue

			var center_x: float = col * cell_size + cell_size * 0.5
			var center_y: float = vis_row * cell_size + cell_size * 0.5

			# 闪光矩形
			_flash_rects.append(Rect2(
				Vector2(col * cell_size, vis_row * cell_size),
				Vector2(cell_size, cell_size)
			))

			# 为每个格子生成多个碎片粒子
			for _i in range(PARTICLE_COUNT_PER_CELL):
				var angle: float = randf() * TAU
				var speed: float = randf_range(EXPLOSION_SPEED * 0.3, EXPLOSION_SPEED)
				var vel := Vector2(cos(angle) * speed, sin(angle) * speed - 80.0)

				# 随机微调颜色（增加视觉丰富度）
				var c: Color = cell_color
				var brightness_shift: float = randf_range(-0.15, 0.25)
				if brightness_shift > 0:
					c = c.lightened(brightness_shift)
				else:
					c = c.darkened(-brightness_shift)

				var p_size: float = randf_range(PARTICLE_SIZE * 0.5, PARTICLE_SIZE * 1.5)

				_particles.append({
					"pos": Vector2(center_x + randf_range(-3, 3), center_y + randf_range(-3, 3)),
					"vel": vel,
					"color": c,
					"life": PARTICLE_LIFETIME * randf_range(0.7, 1.0),
					"max_life": PARTICLE_LIFETIME,
					"size": p_size,
					"rot": randf() * TAU,
					"rot_speed": randf_range(-10.0, 10.0)
				})

	set_process(true)


func _ready() -> void:
	set_process(false)
	z_index = 100  # 确保粒子渲染在最顶层


func _process(delta: float) -> void:
	if _finished:
		return

	# 更新闪光计时
	if _flash_timer > 0.0:
		_flash_timer -= delta

	# 更新每个粒子
	var alive_count: int = 0
	for p in _particles:
		if p["life"] <= 0.0:
			continue
		alive_count += 1
		p["life"] -= delta
		p["vel"].y += GRAVITY * delta
		p["pos"] += p["vel"] * delta
		p["rot"] += p["rot_speed"] * delta

	_total_lifetime += delta
	queue_redraw()

	# 所有粒子消亡且闪光结束 → 自动销毁
	if alive_count == 0 and _flash_timer <= 0.0:
		_finished = true
		queue_free()


func _draw() -> void:
	# 1. 绘制白色消行闪光
	if _flash_timer > 0.0:
		var flash_alpha: float = clampf(_flash_timer / FLASH_DURATION, 0.0, 1.0)
		var flash_color := Color(1.0, 1.0, 1.0, flash_alpha * 0.85)
		for rect in _flash_rects:
			draw_rect(rect, flash_color)

	# 2. 绘制粒子碎片
	for p in _particles:
		if p["life"] <= 0.0:
			continue

		var life_ratio: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var alpha: float = life_ratio  # 线性淡出
		var current_size: float = p["size"] * (0.3 + 0.7 * life_ratio)  # 尺寸渐小

		var c: Color = p["color"]
		c.a = alpha

		var pos: Vector2 = p["pos"]
		var half: float = current_size * 0.5

		# 绘制旋转的小方块碎片
		var rot: float = p["rot"]
		var corners: Array = [
			Vector2(-half, -half),
			Vector2(half, -half),
			Vector2(half, half),
			Vector2(-half, half)
		]

		var rotated_corners: PackedVector2Array = PackedVector2Array()
		var cos_r: float = cos(rot)
		var sin_r: float = sin(rot)
		for corner in corners:
			rotated_corners.append(pos + Vector2(
				corner.x * cos_r - corner.y * sin_r,
				corner.x * sin_r + corner.y * cos_r
			))

		var colors_arr := PackedColorArray()
		colors_arr.resize(4)
		colors_arr.fill(c)
		draw_polygon(rotated_corners, colors_arr)

		# 为较大碎片添加发光边缘
		if current_size > PARTICLE_SIZE * 0.8:
			var glow_c := Color(c.r, c.g, c.b, alpha * 0.3)
			for i in range(4):
				draw_line(
					rotated_corners[i],
					rotated_corners[(i + 1) % 4],
					glow_c,
					1.5
				)
