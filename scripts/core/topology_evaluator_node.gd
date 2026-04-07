extends Node

# ==============================================================================
# 拓扑评分器（GDScript 版）
# 输入：
# - board_state_visible: 10x20 可见棋盘，空格定义为 -1
#
# 输出：
# - topology_score: 0~100，综合平整性与空洞质量
# - stability_score: 0~100，越高表示空洞越少且越不碎片化
# - empty_cells / empty_regions / trapped_cells / flatness_score 中间指标
#
# 关键规则：
# - 顶部空白区域按“虚拟顶行”并入空区连通域统计
#   （也就是你定义里的“0 空洞堆叠时，上方空白也算空洞区域的一部分”）
# ==============================================================================

func EvaluateBoardScores(board_state_visible: Array) -> Dictionary:
	var rows: int = board_state_visible.size()
	if rows <= 0:
		return _build_result(0.0, 0.0, 0, 0, 0, 0.0)

	var cols: int = (board_state_visible[0] as Array).size() if rows > 0 else 0
	if cols <= 0:
		return _build_result(0.0, 0.0, 0, 0, 0, 0.0)

	# 先把棋盘转成布尔空格矩阵：true=空格，false=实块。
	var empty: Array = []
	var empty_cells: int = 0
	for y in range(rows):
		var row: Array = board_state_visible[y]
		var empty_row: Array = []
		for x in range(cols):
			var cell: int = int(row[x]) if x < row.size() else -1
			var is_empty: bool = cell == -1
			empty_row.append(is_empty)
			if is_empty:
				empty_cells += 1
		empty.append(empty_row)

	# 三个核心中间量：
	# 1) empty_regions：空区连通片数量（包含顶部虚拟空区）
	# 2) trapped_cells：封闭空洞格子数（从顶行不可达）
	# 3) flatness_score：地形平整性（相邻高差 + 列高方差）
	var empty_regions: int = _count_empty_regions_with_top_area(empty, rows, cols)
	var trapped_cells: int = _count_trapped_cells(empty, rows, cols)
	var flatness_score: float = _calculate_flatness_score(empty, rows, cols)

	# 稳定分：空洞越多、越碎，分越低。
	var stability_score: float = 100.0 - minf(100.0, trapped_cells * 2.0 + maxi(0, empty_regions - 1) * 12.0)
	stability_score = clampf(stability_score, 0.0, 100.0)

	# 拓扑分：平整性占 65%，空洞质量占 35%。
	var topology_score: float = clampf(flatness_score * 0.65 + stability_score * 0.35, 0.0, 100.0)
	return _build_result(topology_score, stability_score, empty_cells, empty_regions, trapped_cells, flatness_score)


# 兼容小写调用风格（避免调用方函数名大小写差异）。
func evaluate_board_scores(board_state_visible: Array) -> Dictionary:
	return EvaluateBoardScores(board_state_visible)


# 统计空区连通域数量：在原棋盘上方额外添加一整行“虚拟空行”参与 flood fill。
func _count_empty_regions_with_top_area(empty: Array, rows: int, cols: int) -> int:
	var aug: Array = []
	var top_row: Array = []
	for x in range(cols):
		top_row.append(true)
	aug.append(top_row)
	for y in range(rows):
		aug.append((empty[y] as Array).duplicate())

	var visited: Array = []
	for y2 in range(rows + 1):
		var vrow: Array = []
		for x2 in range(cols):
			vrow.append(false)
		visited.append(vrow)

	var regions: int = 0
	for y3 in range(rows + 1):
		for x3 in range(cols):
			if not aug[y3][x3] or visited[y3][x3]:
				continue
			regions += 1
			_flood_fill(aug, visited, y3, x3, rows + 1, cols)
	return regions


# 从顶行空格做 BFS，可达区域视为“开口空区”，不可达空格即封闭空洞（trapped）。
func _count_trapped_cells(empty: Array, rows: int, cols: int) -> int:
	var visited: Array = []
	for y in range(rows):
		var vrow: Array = []
		for x in range(cols):
			vrow.append(false)
		visited.append(vrow)

	var q: Array[Vector2i] = []
	for x2 in range(cols):
		if empty[0][x2]:
			visited[0][x2] = true
			q.append(Vector2i(x2, 0))

	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = p.x + d.x
			var ny: int = p.y + d.y
			if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
				continue
			if not empty[ny][nx] or visited[ny][nx]:
				continue
			visited[ny][nx] = true
			q.append(Vector2i(nx, ny))

	var trapped: int = 0
	for y2 in range(rows):
		for x3 in range(cols):
			if empty[y2][x3] and not visited[y2][x3]:
				trapped += 1
	return trapped


# 平整性评分：
# - bumpiness_score：相邻列高度差越小越好
# - variance_score：列高方差越小越好
# 最终按 0.7 / 0.3 融合。
func _calculate_flatness_score(empty: Array, rows: int, cols: int) -> float:
	var heights: Array = []
	for x in range(cols):
		var first_filled_y: int = rows
		for y in range(rows):
			if not empty[y][x]:
				first_filled_y = y
				break
		heights.append(0 if first_filled_y == rows else rows - first_filled_y)

	var roughness: float = 0.0
	for x2 in range(cols - 1):
		roughness += absf(float(heights[x2] - heights[x2 + 1]))

	var max_roughness: float = float(rows * maxi(1, cols - 1))
	var bumpiness_score: float = 100.0 * (1.0 - roughness / maxf(1.0, max_roughness))
	bumpiness_score = clampf(bumpiness_score, 0.0, 100.0)

	var mean: float = 0.0
	for h in heights:
		mean += float(h)
	mean /= float(cols)

	var variance: float = 0.0
	for h2 in heights:
		var d: float = float(h2) - mean
		variance += d * d
	variance /= float(cols)

	var max_variance: float = float(rows * rows) / 4.0
	var variance_score: float = 100.0 * (1.0 - variance / maxf(1.0, max_variance))
	variance_score = clampf(variance_score, 0.0, 100.0)

	return bumpiness_score * 0.7 + variance_score * 0.3


# 四联通 flood fill。
func _flood_fill(grid: Array, visited: Array, sy: int, sx: int, rows: int, cols: int) -> void:
	var q: Array[Vector2i] = [Vector2i(sx, sy)]
	visited[sy][sx] = true

	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = p.x + d.x
			var ny: int = p.y + d.y
			if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
				continue
			if not grid[ny][nx] or visited[ny][nx]:
				continue
			visited[ny][nx] = true
			q.append(Vector2i(nx, ny))


# 统一返回结构，采集器可直接消费。
func _build_result(
	topology_score: float,
	stability_score: float,
	empty_cells: int,
	empty_regions: int,
	trapped_cells: int,
	flatness_score: float
) -> Dictionary:
	return {
		"topology_score": snapped(topology_score, 0.1),
		"stability_score": snapped(stability_score, 0.1),
		"empty_cells": empty_cells,
		"empty_regions": empty_regions,
		"trapped_cells": trapped_cells,
		"flatness_score": snapped(flatness_score, 0.1)
	}
