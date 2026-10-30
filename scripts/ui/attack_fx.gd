class_name AttackFX
extends Node2D

## 攻击弹道特效（屏幕坐标，绘制在独立 CanvasLayer 上）
##
## 发光弹头 + 渐细拖尾，沿三次贝塞尔曲线飞行，先慢后快；命中时爆出冲击环和火花。
## 曲线可指定最高点 apex_y，用于从棋盘上方绕行，避免穿过玩家的操作区域。

const LAYER_NAME := "AttackFXLayer"
const TRAIL_LEN := 14

var _p0: Vector2
var _p1: Vector2
var _p2: Vector2
var _p3: Vector2
var _t: float = 0.0
var _duration: float = 0.45
var _radius: float = 7.0
var _color: Color = Color.WHITE
var _trail: Array[Vector2] = []
var _on_impact: Callable
var _impacted: bool = false
var _impact_t: float = 0.0
var _sparks: Array = []
var _delay: float = 0.0


## 发射一枚攻击弹。from/to 为画布（屏幕）坐标。
## apex_y: 曲线最高点的 y（NAN 表示自动拱起）；delay: 发射前等待（多发时错开）
static func fire(host: Node, from: Vector2, to: Vector2, amount: int, color: Color, apex_y: float = NAN, on_impact: Callable = Callable(), delay: float = 0.0) -> AttackFX:
	if host == null or not host.is_inside_tree():
		return null
	var fx := AttackFX.new()
	_layer_for(host).add_child(fx)
	fx._setup(from, to, amount, color, apex_y, on_impact, delay)
	return fx


## 节点在画布上的坐标（Node2D / Control 均可）
static func canvas_pos(node: CanvasItem, local: Vector2 = Vector2.ZERO) -> Vector2:
	return node.get_global_transform_with_canvas() * local


static func _layer_for(host: Node) -> CanvasLayer:
	return host.get_node(LAYER_NAME) as CanvasLayer


func _setup(from: Vector2, to: Vector2, amount: int, color: Color, apex_y: float, on_impact: Callable, delay: float) -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_color = color
	_on_impact = on_impact
	_delay = delay
	_radius = clampf(5.0 + amount * 1.6, 6.0, 20.0)
	var dist := from.distance_to(to)
	_duration = clampf(0.28 + dist / 2600.0, 0.32, 0.62)
	_p0 = from
	_p3 = to
	var dx := to.x - from.x
	if is_nan(apex_y):
		apex_y = maxf(minf(from.y, to.y) - clampf(dist * 0.28, 40.0, 220.0), 8.0)
	# 三次贝塞尔中点高度 = (y0 + y3)/8 + 0.75 * yc，反推控制点高度使最高点≈apex_y
	var yc := (apex_y - (from.y + to.y) / 8.0) / 0.75
	_p1 = Vector2(from.x + dx * 0.15, yc)
	_p2 = Vector2(to.x - dx * 0.15, yc)
	_trail.append(from)
	visible = _delay <= 0.0


func _bezier(t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * _p0 + 3.0 * u * u * t * _p1 + 3.0 * u * t * t * _p2 + t * t * t * _p3


func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		if _delay > 0.0:
			return
		delta = -_delay
		visible = true
	if not _impacted:
		_t = minf(_t + delta / _duration, 1.0)
		# 先慢后快：出膛略蓄力，冲向目标
		var e := _t * _t * (2.2 - 1.2 * _t)
		var pos := _bezier(e)
		_trail.push_front(pos)
		if _trail.size() > TRAIL_LEN:
			_trail.pop_back()
		if _t >= 1.0:
			_impact()
	else:
		_impact_t += delta
		if _trail.size() > 1:
			_trail.pop_back()
		for s in _sparks:
			s["life"] -= delta
			s["vel"] *= pow(0.02, delta)
			s["pos"] += s["vel"] * delta
		if _impact_t > 0.5:
			queue_free()
			return
	queue_redraw()


func _impact() -> void:
	_impacted = true
	for i in range(14):
		var a := randf() * TAU
		_sparks.append({
			"pos": _p3,
			"vel": Vector2(cos(a), sin(a)) * randf_range(120.0, 380.0),
			"life": randf_range(0.18, 0.4),
		})
	if _on_impact.is_valid():
		_on_impact.call()


func _draw() -> void:
	# 拖尾：越往后越细越淡
	var n := _trail.size()
	for i in range(n - 1):
		var k := 1.0 - float(i) / float(TRAIL_LEN)
		var w := _radius * 1.5 * k
		draw_line(_trail[i], _trail[i + 1], Color(_color, 0.55 * k), w, true)
		draw_line(_trail[i], _trail[i + 1], Color(1, 1, 1, 0.5 * k), maxf(w * 0.3, 1.0), true)

	if not _impacted and n > 0:
		var head := _trail[0]
		for g in range(4):
			var r := _radius * (2.4 - g * 0.45)
			draw_circle(head, r, Color(_color, 0.12 + g * 0.08))
		draw_circle(head, _radius * 0.55, Color(1, 1, 1, 0.95))
	elif _impacted:
		var t := clampf(_impact_t / 0.35, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		draw_arc(_p3, lerpf(_radius, _radius * 5.0, e), 0.0, TAU, 40, Color(_color, 1.0 - t), lerpf(5.0, 1.0, t), true)
		draw_circle(_p3, _radius * 1.6 * (1.0 - t), Color(1, 1, 1, 0.8 * (1.0 - t)))
		for s in _sparks:
			if s["life"] <= 0.0:
				continue
			var a: float = clampf(s["life"] / 0.25, 0.0, 1.0)
			var p: Vector2 = s["pos"]
			draw_line(p, p - s["vel"] * 0.03, Color(_color.lightened(0.4), a), 2.0, true)
