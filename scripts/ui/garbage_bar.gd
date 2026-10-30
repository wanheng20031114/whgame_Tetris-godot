class_name GarbageBar
extends Control

## 受攻击垃圾槽
##
## 每个攻击包是一段独立的块，按入场顺序从下往上堆：
## - 灰色：远期，倒计时中
## - 黄 → 橙 → 红：进入警告阶段后颜色随剩余时间连续加深
## - 红色跳动 + 滚动斜纹：已就绪，下一次不消行的放置就会顶上来
## 新攻击从槽顶落入；被抵消的段闪白后碎裂。

const COL_GREY := Color(0.50, 0.52, 0.58)
const COL_YELLOW := Color(1.0, 0.80, 0.22)
const COL_RED := Color(1.0, 0.22, 0.26)
const WELL_BG := Color("0d0d14")
const SEG_GAP := 2.0

var max_lines: int = 20

## 每段的显示状态：key → {y, h, target_y, target_h, color, ready, flash, alive}
var _segs: Dictionary = {}
var _order: Array = []
var _next_id: int = 1
var _time: float = 0.0
var _impact: float = 0.0
var _shards: Array = []
var _overflow: int = 0

func _ready() -> void:
	for n in ["BgRect", "GreyRect", "PendingRect", "ReadyRect", "GridOverlay"]:
		var c := get_node_or_null(n) as CanvasItem
		if c:
			c.visible = false
	clip_contents = false
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	_impact = maxf(_impact - delta * 3.0, 0.0)
	var cell := _cell_h()
	var dead: Array = []
	for key in _segs:
		var s: Dictionary = _segs[key]
		var k := 1.0 - pow(0.0005, delta) # 快速逼近
		s["y"] = lerpf(s["y"], s["target_y"], k)
		s["h"] = lerpf(s["h"], s["target_h"], k)
		s["flash"] = maxf(s["flash"] - delta * 4.0, 0.0)
		if not s["alive"] and s["h"] < 0.5:
			dead.append(key)
	for key in dead:
		_segs.erase(key)
	for p in _shards:
		p["life"] -= delta
		p["vel"] += Vector2(0, 700.0) * delta
		p["pos"] += p["vel"] * delta
	_shards = _shards.filter(func(p): return p["life"] > 0.0)
	if cell > 0.0:
		queue_redraw()

func _cell_h() -> float:
	return size.y / float(maxi(max_lines, 1))

# ==============================================================================
# 对外接口
# ==============================================================================

## 同步攻击队列。pending: 游戏逻辑中的攻击包数组 [{delay, amount}]（会写入内部 id）。
## total_delay: 攻击从出现到就绪的总时长；warn_at: 剩余多少秒进入警告（黄色）阶段。
func sync_queue(pending: Array, ready_amount: int, total_delay: float, warn_at: float) -> void:
	var entries: Array = []
	if ready_amount > 0:
		entries.append({"key": "ready", "amount": ready_amount, "color": _ready_color(), "ready": true})
	for attack in pending:
		var amount := int(attack.get("amount", 0))
		if amount <= 0:
			continue
		if not attack.has("_fx_id"):
			attack["_fx_id"] = _next_id
			_next_id += 1
		var delay := float(attack.get("delay", total_delay))
		entries.append({"key": attack["_fx_id"], "amount": amount, "color": stage_color(delay, warn_at), "ready": false})
	_apply_entries(entries)

## 兼容旧接口：按三个阶段的总量显示
func update_bar(grey_count: int, yellow_count: int, ready_count: int) -> void:
	var entries: Array = []
	if ready_count > 0:
		entries.append({"key": "ready", "amount": ready_count, "color": _ready_color(), "ready": true})
	if yellow_count > 0:
		entries.append({"key": "yellow", "amount": yellow_count, "color": COL_YELLOW, "ready": false})
	if grey_count > 0:
		entries.append({"key": "grey", "amount": grey_count, "color": COL_GREY, "ready": false})
	_apply_entries(entries)

## 攻击命中垃圾槽时的冲击反馈
func flash_impact() -> void:
	_impact = 1.0

## 最新一段（最上方）攻击的顶部中心，供攻击弹道作为落点（本地坐标）
func get_queue_top_local() -> Vector2:
	var top := size.y
	for key in _order:
		if _segs.has(key) and _segs[key]["alive"]:
			top = minf(top, _segs[key]["target_y"])
	return Vector2(size.x * 0.5, top)

## 剩余时间 → 颜色：灰色阶段末尾 0.6 秒过渡到黄色；警告阶段内黄色逐渐加深到红色
static func stage_color(delay: float, warn_at: float) -> Color:
	if delay > warn_at:
		var t := clampf(1.0 - (delay - warn_at) / 0.6, 0.0, 1.0)
		return COL_GREY.lerp(COL_YELLOW, t * t)
	var p := clampf(1.0 - delay / maxf(warn_at, 0.001), 0.0, 1.0)
	return COL_YELLOW.lerp(COL_RED, p * p)

func _ready_color() -> Color:
	return COL_RED

## 就绪的垃圾已顶入棋盘：下一次同步时就绪段下沉消失，而不是碎裂
func mark_entered() -> void:
	_entered_pending = true

var _entered_pending: bool = false

func _apply_entries(entries: Array) -> void:
	var cell := _cell_h()
	var old_ready_h: float = 0.0
	if _segs.has("ready") and _segs["ready"]["alive"]:
		old_ready_h = _segs["ready"]["target_h"]
	var y := size.y
	var seen := {}
	var new_order: Array = []
	var visible_lines := 0
	_overflow = 0
	for e in entries:
		var key = e["key"]
		var amount: int = e["amount"]
		var shown := mini(amount, max_lines - visible_lines)
		_overflow += amount - shown
		visible_lines += shown
		var h := shown * cell
		y -= h
		seen[key] = true
		new_order.append(key)
		if not _segs.has(key):
			# 新攻击：从槽顶上方落入
			_segs[key] = {"y": -h - cell * 2.0, "h": h, "target_y": y, "target_h": h, "flash": 1.0, "alive": true, "color": e["color"]}
		var s: Dictionary = _segs[key]
		if s["alive"] and h < float(s["target_h"]) - 0.5:
			# 部分被抵消：顶部碎掉
			_spawn_shards(Vector2(size.x * 0.5, s["target_y"]), s["color"], int((s["target_h"] - h) / maxf(cell, 1.0)) * 3 + 1)
			s["flash"] = 1.0
		s["target_y"] = y
		s["target_h"] = h
		s["color"] = e["color"]
		s["ready"] = e["ready"]
		s["alive"] = true
	var new_ready_h: float = 0.0
	if seen.has("ready"):
		new_ready_h = _segs["ready"]["target_h"]
	var merge_budget := maxf(new_ready_h - old_ready_h, 0.0)
	for key in _segs:
		var s: Dictionary = _segs[key]
		if seen.has(key) or not s["alive"]:
			continue
		s["alive"] = false
		var old_h: float = s["target_h"]
		s["target_h"] = 0.0
		if typeof(key) == TYPE_STRING and key == "ready" and _entered_pending:
			# 入场：整段沉到底部消失
			s["target_y"] = size.y
		elif merge_budget > 0.5:
			# 倒计时结束：并入就绪段
			merge_budget -= old_h
			s["h"] = 0.0
		else:
			# 被抵消：闪白并碎裂
			s["target_y"] = s["target_y"] + s["h"]
			s["flash"] = 1.0
			_spawn_shards(Vector2(size.x * 0.5, s["y"] + s["h"] * 0.5), s["color"], maxi(int(old_h / maxf(cell, 1.0)), 1) * 3)
	_entered_pending = false
	_order = new_order

func _spawn_shards(at: Vector2, color: Color, count: int) -> void:
	for i in range(mini(count, 24)):
		_shards.append({
			"pos": at + Vector2(randf_range(-size.x * 0.5, size.x * 0.5), randf_range(-6, 6)),
			"vel": Vector2(randf_range(-160, 60), randf_range(-220, -40)),
			"color": color.lightened(0.3),
			"life": randf_range(0.25, 0.45),
			"size": randf_range(2.5, 5.0),
		})

# ==============================================================================
# 绘制
# ==============================================================================

func _draw() -> void:
	var w := size.x
	var h := size.y
	if h <= 0.0:
		return
	var cell := _cell_h()

	draw_rect(Rect2(0, 0, w, h), WELL_BG)
	for i in range(1, max_lines):
		draw_line(Vector2(2, i * cell), Vector2(w - 2, i * cell), Color(1, 1, 1, 0.035), 1.0)

	var throb := 0.5 + 0.5 * sin(_time * TAU * 2.2)
	for key in _segs:
		var s: Dictionary = _segs[key]
		var sh: float = s["h"]
		if sh < 0.5:
			continue
		var rect := Rect2(1.0, s["y"] + SEG_GAP * 0.5, w - 2.0, maxf(sh - SEG_GAP, 1.0))
		var col: Color = s["color"]
		var is_ready: bool = s["ready"]
		var is_warn := not is_ready and col.r > 0.9 and col.b < 0.4

		if is_ready:
			# 就绪：左侧外发光（不进入棋盘）+ 跳动
			for g in range(4):
				var gg := 2.0 + g * 3.0
				draw_rect(Rect2(rect.position.x - gg, rect.position.y, gg, rect.size.y), Color(COL_RED, (0.22 - g * 0.05) * (0.5 + throb * 0.5)))
			col = col.lightened(0.18 * throb)
		elif is_warn:
			col = col.lightened(0.12 * (0.5 + 0.5 * sin(_time * TAU * 1.2)))

		_draw_segment(rect, col, cell)
		if is_ready:
			_draw_stripes(rect, Color(1, 1, 1, 0.16 + 0.1 * throb))
		var f: float = s["flash"]
		if f > 0.0:
			draw_rect(rect, Color(1, 1, 1, f * 0.8))

	for p in _shards:
		var c: Color = p["color"]
		c.a = clampf(p["life"] / 0.3, 0.0, 1.0)
		var ps: float = p["size"]
		draw_rect(Rect2(p["pos"] - Vector2(ps, ps) * 0.5, Vector2(ps, ps)), c)

	if _overflow > 0:
		var font := get_theme_default_font()
		var txt := "+%d" % _overflow
		draw_string_outline(font, Vector2(-4, 14), txt, HORIZONTAL_ALIGNMENT_CENTER, w + 8, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(-4, 14), txt, HORIZONTAL_ALIGNMENT_CENTER, w + 8, 14, COL_RED.lightened(0.3))

	if _impact > 0.0:
		var e := _impact * _impact
		draw_rect(Rect2(-2, 0, w + 4, h), Color(1, 1, 1, 0.25 * e), false, 2.0 + 4.0 * e)

	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08), false, 1.0)

## 一段攻击块：主体 + 顶部高光 + 底部暗边 + 每行的刻度
func _draw_segment(rect: Rect2, col: Color, cell: float) -> void:
	draw_rect(rect, col)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(3.0, rect.size.y))), col.lightened(0.35))
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), col.darkened(0.35))
	var y := rect.position.y + cell
	while y < rect.end.y - 2.0:
		draw_line(Vector2(rect.position.x + 3, y), Vector2(rect.end.x - 3, y), col.darkened(0.3), 1.0)
		y += cell

func _draw_stripes(rect: Rect2, color: Color) -> void:
	var stripe := 6.0
	var shift := fmod(_time * 24.0, stripe * 2.0)
	var y := rect.position.y - rect.size.x - stripe * 2.0 + shift
	var clip := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	while y < rect.end.y:
		var poly := PackedVector2Array([
			Vector2(rect.position.x, y), Vector2(rect.position.x, y + stripe),
			Vector2(rect.end.x, y + stripe + rect.size.x), Vector2(rect.end.x, y + rect.size.x)])
		for c in Geometry2D.intersect_polygons(poly, clip):
			if Board.poly_area(c) > 0.5:
				draw_colored_polygon(c, color)
		y += stripe * 2.0
