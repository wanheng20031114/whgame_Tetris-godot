extends Node

signal style_changed(style_id: String)

const SETTINGS_SECTION := "BlockStyle"
const SETTINGS_KEY := "style_id"

const STYLE_INNER := "inner"
const STYLE_SOLID := "solid"
const STYLE_GLASS := "glass"
const STYLE_PASTEL := "pastel"
const STYLE_ARCADE := "arcade"
const DEFAULT_STYLE_ID := STYLE_INNER

const STYLES := [
	{
		"id": STYLE_INNER,
		"name_key": "TXT_BLOCK_STYLE_INNER",
		"desc_key": "TXT_BLOCK_STYLE_INNER_DESC",
	},
	{
		"id": STYLE_SOLID,
		"name_key": "TXT_BLOCK_STYLE_SOLID",
		"desc_key": "TXT_BLOCK_STYLE_SOLID_DESC",
	},
	{
		"id": STYLE_GLASS,
		"name_key": "TXT_BLOCK_STYLE_GLASS",
		"desc_key": "TXT_BLOCK_STYLE_GLASS_DESC",
	},
	{
		"id": STYLE_PASTEL,
		"name_key": "TXT_BLOCK_STYLE_PASTEL",
		"desc_key": "TXT_BLOCK_STYLE_PASTEL_DESC",
	},
	{
		"id": STYLE_ARCADE,
		"name_key": "TXT_BLOCK_STYLE_ARCADE",
		"desc_key": "TXT_BLOCK_STYLE_ARCADE_DESC",
	},
]

var _current_style_id := DEFAULT_STYLE_ID


func _ready() -> void:
	_current_style_id = _load_style_id()


func get_current_style_id() -> String:
	return _current_style_id


func get_styles() -> Array:
	return STYLES.duplicate(true)


func is_valid_style(style_id: String) -> bool:
	for style in STYLES:
		if str(style.get("id", "")) == style_id:
			return true
	return false


func set_style_id(style_id: String, persist: bool = true) -> void:
	var next_style := style_id if is_valid_style(style_id) else DEFAULT_STYLE_ID
	if _current_style_id == next_style:
		return
	_current_style_id = next_style
	if persist:
		_save_style_id()
	style_changed.emit(_current_style_id)


func draw_cell(canvas: CanvasItem, rect: Rect2, base_color: Color, style_id: String = "") -> void:
	if canvas == null:
		return
	var selected_style := style_id if not style_id.is_empty() else _current_style_id
	match selected_style:
		STYLE_SOLID:
			_draw_solid(canvas, rect, base_color)
		STYLE_GLASS:
			_draw_glass(canvas, rect, base_color)
		STYLE_PASTEL:
			_draw_pastel(canvas, rect, base_color)
		STYLE_ARCADE:
			_draw_arcade(canvas, rect, base_color)
		_:
			_draw_inner(canvas, rect, base_color)


func _draw_inner(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var edge := _edge(rect)
	var inset := _inset(rect)
	canvas.draw_rect(rect, color)
	canvas.draw_rect(rect, color.darkened(0.30), false, edge)
	canvas.draw_rect(rect.grow(-inset), color.lightened(0.40), false, maxf(1.0, edge * 0.5))


func _draw_solid(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var edge := maxf(1.0, _edge(rect) * 0.65)
	canvas.draw_rect(rect, color)
	canvas.draw_rect(rect, color.darkened(0.42), false, edge)


func _draw_glass(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var edge := _edge(rect)
	var inset := _inset(rect)
	canvas.draw_rect(rect, color.darkened(0.08))
	canvas.draw_rect(rect.grow(-edge), color.lightened(0.10))
	canvas.draw_rect(rect, color.darkened(0.45), false, edge)
	var highlight_h := maxf(edge, rect.size.y * 0.26)
	var highlight_rect := Rect2(rect.position + Vector2(edge, edge), Vector2(maxf(0.0, rect.size.x - edge * 2.0), highlight_h))
	canvas.draw_rect(highlight_rect, _alpha(color.lightened(0.62), color.a * 0.72))
	canvas.draw_rect(rect.grow(-inset), _alpha(color.lightened(0.35), color.a * 0.72), false, maxf(1.0, edge * 0.5))


func _draw_pastel(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var edge := _edge(rect)
	var soft := _alpha(color.lightened(0.34), color.a)
	canvas.draw_rect(rect, soft)
	canvas.draw_rect(rect, _alpha(color.darkened(0.12), color.a * 0.85), false, edge)
	var top := Rect2(rect.position + Vector2(edge, edge), Vector2(maxf(0.0, rect.size.x - edge * 2.0), maxf(edge, rect.size.y * 0.18)))
	canvas.draw_rect(top, _alpha(Color.WHITE, color.a * 0.26))


func _draw_arcade(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var edge := _edge(rect)
	canvas.draw_rect(rect, color.darkened(0.55))
	var inner := rect.grow(-edge)
	canvas.draw_rect(inner, color)
	canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x, edge)), color.lightened(0.42))
	canvas.draw_rect(Rect2(inner.position, Vector2(edge, inner.size.y)), color.lightened(0.26))
	canvas.draw_rect(Rect2(inner.position + Vector2(0.0, maxf(0.0, inner.size.y - edge)), Vector2(inner.size.x, edge)), color.darkened(0.28))
	canvas.draw_rect(Rect2(inner.position + Vector2(maxf(0.0, inner.size.x - edge), 0.0), Vector2(edge, inner.size.y)), color.darkened(0.34))


func _edge(rect: Rect2) -> float:
	return clampf(minf(rect.size.x, rect.size.y) * 0.075, 1.0, 2.5)


func _inset(rect: Rect2) -> float:
	return clampf(minf(rect.size.x, rect.size.y) * 0.14, 1.0, 4.0)


func _alpha(color: Color, alpha: float) -> Color:
	var result := color
	result.a = clampf(alpha, 0.0, 1.0)
	return result


func _load_style_id() -> String:
	var config := ConfigFile.new()
	var err := config.load(_get_settings_path())
	if err != OK:
		return DEFAULT_STYLE_ID
	var saved := str(config.get_value(SETTINGS_SECTION, SETTINGS_KEY, DEFAULT_STYLE_ID))
	return saved if is_valid_style(saved) else DEFAULT_STYLE_ID


func _save_style_id() -> void:
	var path := _get_settings_path()
	var config := ConfigFile.new()
	config.load(path)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, _current_style_id)
	config.save(path)


func _get_settings_path() -> String:
	if OS.has_feature("editor"):
		return "res://settings.cfg"
	return OS.get_executable_path().get_base_dir().path_join("settings.cfg")
