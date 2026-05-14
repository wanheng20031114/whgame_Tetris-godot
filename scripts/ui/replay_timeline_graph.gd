class_name ReplayTimelineGraph
extends Control

signal step_selected(index: int)

const LOSS_MINOR := 231
const LOSS_MEDIUM := 581
const LOSS_MAJOR := 946
const LOSS_CRITICAL := 1502

var _complexity_values: Array[float] = []
var _loss_values: Array[int] = []
var _piece_names: Array[String] = []
var _elapsed_values: Array[int] = []
var _current_step: int = 0
var _hover_step: int = -1
var _dragging: bool = false
var _editable: bool = true


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(260, 42)
	tooltip_text = ""


func set_timeline_data(complexities: Array[float], losses: Array[int], pieces: Array[String], elapsed: Array[int]) -> void:
	_complexity_values = complexities.duplicate()
	_loss_values = losses.duplicate()
	_piece_names = pieces.duplicate()
	_elapsed_values = elapsed.duplicate()
	_current_step = clampi(_current_step, 0, maxi(0, _complexity_values.size() - 1))
	queue_redraw()


func set_current_step(index: int) -> void:
	_current_step = clampi(index, 0, maxi(0, _complexity_values.size() - 1))
	queue_redraw()


func set_editable(enabled: bool) -> void:
	_editable = enabled
	modulate.a = 1.0 if enabled else 0.55


func _draw() -> void:
	var track := _track_rect()
	draw_rect(track.grow(3.0), Color(0.035, 0.04, 0.065, 1.0), true)
	draw_rect(track, Color(0.060, 0.068, 0.095, 1.0), true)
	draw_line(Vector2(track.position.x, track.end.y), Vector2(track.end.x, track.end.y), Color(0.55, 0.65, 0.88, 0.16), 1.0, true)

	var count := _complexity_values.size()
	if count <= 0:
		draw_line(Vector2(track.position.x, track.get_center().y), Vector2(track.end.x, track.get_center().y), Color(0.26, 0.30, 0.40, 0.8), 2.0, true)
		return

	var points := PackedVector2Array()
	var area := PackedVector2Array()
	var min_value := _series_min()
	var max_value := _series_max()
	var range_value := maxf(1.0, max_value - min_value)
	area.append(Vector2(track.position.x, track.end.y))
	for i in range(count):
		var x := _step_x(i, track)
		var normalized := clampf((_complexity_values[i] - min_value) / range_value, 0.0, 1.0)
		var y := lerpf(track.end.y - 3.0, track.position.y + 3.0, normalized)
		var p := Vector2(x, y)
		points.append(p)
		area.append(p)
	area.append(Vector2(track.end.x, track.end.y))

	if area.size() >= 3:
		draw_polygon(area, PackedColorArray([Color(0.0, 0.72, 1.0, 0.10)]))
	if points.size() >= 2:
		for i2 in range(points.size() - 1):
			var color_ratio := clampf((_complexity_values[i2] - min_value) / range_value, 0.0, 1.0)
			draw_line(points[i2], points[i2 + 1], _complexity_color(color_ratio), 1.45, true)

	for i in range(count):
		var loss := _loss_at(i)
		if loss < LOSS_MINOR:
			continue
		_draw_loss_marker(i, loss, track)

	if _hover_step >= 0 and _hover_step < count:
		var hx := _step_x(_hover_step, track)
		draw_line(Vector2(hx, track.position.y - 2.0), Vector2(hx, track.end.y + 2.0), Color(1.0, 1.0, 1.0, 0.26), 1.0, true)

	var cx := _step_x(_current_step, track)
	draw_line(Vector2(cx, track.position.y - 4.0), Vector2(cx, track.end.y + 5.0), Color(0.42, 0.95, 1.0, 1.0), 2.0, true)
	draw_circle(Vector2(cx, track.end.y + 5.0), 4.0, Color(0.88, 0.95, 1.0, 1.0))
	draw_circle(Vector2(cx, track.end.y + 5.0), 2.4, Color(0.0, 0.83, 1.0, 1.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		_update_hover(mouse_motion.position)
		if _dragging and _editable:
			_select_at_position(mouse_motion.position)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button.pressed
			if mouse_button.pressed and _editable:
				grab_focus()
				_select_at_position(mouse_button.position)
	elif event.is_action_pressed("ui_left") and _editable:
		step_selected.emit(maxi(0, _current_step - 1))
		_mark_input_handled()
	elif event.is_action_pressed("ui_right") and _editable:
		step_selected.emit(mini(maxi(0, _complexity_values.size() - 1), _current_step + 1))
		_mark_input_handled()
	elif event.is_action_pressed("ui_accept") and _editable:
		step_selected.emit(_current_step)
		_mark_input_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_step = -1
		tooltip_text = ""
		queue_redraw()


func _select_at_position(pos: Vector2) -> void:
	var index := _position_to_step(pos)
	if index >= 0:
		step_selected.emit(index)


func _update_hover(pos: Vector2) -> void:
	var next_hover := _position_to_step(pos)
	if next_hover == _hover_step:
		return
	_hover_step = next_hover
	tooltip_text = _build_tooltip(_hover_step)
	queue_redraw()


func _position_to_step(pos: Vector2) -> int:
	var count := _complexity_values.size()
	if count <= 0:
		return -1
	var track := _track_rect()
	var ratio := clampf((pos.x - track.position.x) / maxf(1.0, track.size.x), 0.0, 1.0)
	return clampi(int(round(ratio * float(count - 1))), 0, count - 1)


func _track_rect() -> Rect2:
	return Rect2(4.0, 3.0, maxf(1.0, size.x - 8.0), maxf(28.0, size.y - 6.0))


func _step_x(index: int, track: Rect2) -> float:
	var count := _complexity_values.size()
	if count <= 1:
		return track.position.x
	return track.position.x + track.size.x * (float(index) / float(count - 1))


func _loss_at(index: int) -> int:
	if index < 0 or index >= _loss_values.size():
		return 0
	return maxi(0, _loss_values[index])


func _draw_loss_marker(index: int, loss: int, track: Rect2) -> void:
	var x := _step_x(index, track)
	var color := _loss_color(loss)
	var height_ratio := clampf(float(loss) / 1600.0, 0.18, 1.0)
	var marker_y := lerpf(track.end.y - 4.0, track.position.y + 3.0, height_ratio)
	var radius := 2.0
	if loss >= LOSS_CRITICAL:
		radius = 3.1
	elif loss >= LOSS_MAJOR:
		radius = 2.7
	elif loss >= LOSS_MEDIUM:
		radius = 2.35
	draw_circle(Vector2(x, marker_y), radius + 1.2, Color(color.r, color.g, color.b, 0.14))
	if loss >= LOSS_MAJOR:
		draw_circle(Vector2(x, marker_y), radius, color)
	else:
		var diamond := PackedVector2Array([
			Vector2(x, marker_y - radius),
			Vector2(x + radius, marker_y),
			Vector2(x, marker_y + radius),
			Vector2(x - radius, marker_y),
		])
		draw_polygon(diamond, PackedColorArray([color]))


func _loss_color(loss: int) -> Color:
	if loss >= LOSS_CRITICAL:
		return Color(1.0, 0.05, 0.05, 1.0)
	if loss >= LOSS_MAJOR:
		return Color(1.0, 0.20, 0.10, 1.0)
	if loss >= LOSS_MEDIUM:
		return Color(1.0, 0.56, 0.05, 1.0)
	return Color(1.0, 0.86, 0.12, 1.0)


func _complexity_color(ratio: float) -> Color:
	if ratio < 0.35:
		return Color(0.18, 1.0, 0.45, 0.95).lerp(Color(0.0, 0.86, 1.0, 0.95), ratio / 0.35)
	if ratio < 0.70:
		return Color(0.0, 0.86, 1.0, 0.95).lerp(Color(0.54, 0.26, 1.0, 0.98), (ratio - 0.35) / 0.35)
	return Color(0.54, 0.26, 1.0, 0.98).lerp(Color(0.62, 0.20, 1.0, 1.0), (ratio - 0.70) / 0.30)


func _series_min() -> float:
	if _complexity_values.is_empty():
		return 0.0
	var result := _complexity_values[0]
	for value in _complexity_values:
		result = minf(result, value)
	return result


func _series_max() -> float:
	if _complexity_values.is_empty():
		return 100.0
	var result := _complexity_values[0]
	for value in _complexity_values:
		result = maxf(result, value)
	return result


func _build_tooltip(index: int) -> String:
	if index < 0 or index >= _complexity_values.size():
		return ""
	var piece := _piece_names[index] if index < _piece_names.size() else "?"
	var loss := _loss_at(index)
	var elapsed := _elapsed_values[index] if index < _elapsed_values.size() else 0
	var ai_text := "BEST" if loss <= 0 else "-%d" % loss
	return "#%04d  %s  %s  |  C %.0f  |  %dms" % [index + 1, piece, ai_text, _complexity_values[index], elapsed]


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()
