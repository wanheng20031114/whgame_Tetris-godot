extends TextureButton

const MENU_WIDTH := 660.0
const MENU_HEIGHT := 480.0
const CARD_HEIGHT := 104.0
const DEFAULT_STYLE_ID := "inner"
const FALLBACK_STYLES := [
	{
		"id": "inner",
		"name_key": "TXT_BLOCK_STYLE_INNER",
		"desc_key": "TXT_BLOCK_STYLE_INNER_DESC",
	},
	{
		"id": "solid",
		"name_key": "TXT_BLOCK_STYLE_SOLID",
		"desc_key": "TXT_BLOCK_STYLE_SOLID_DESC",
	},
	{
		"id": "glass",
		"name_key": "TXT_BLOCK_STYLE_GLASS",
		"desc_key": "TXT_BLOCK_STYLE_GLASS_DESC",
	},
	{
		"id": "pastel",
		"name_key": "TXT_BLOCK_STYLE_PASTEL",
		"desc_key": "TXT_BLOCK_STYLE_PASTEL_DESC",
	},
	{
		"id": "arcade",
		"name_key": "TXT_BLOCK_STYLE_ARCADE",
		"desc_key": "TXT_BLOCK_STYLE_ARCADE_DESC",
	},
]

var _layer: CanvasLayer
var _panel: PanelContainer
var _title_label: Label
var _hint_label: Label
var _grid: GridContainer
var _close_button: Button
var _style_buttons: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = tr("TXT_BLOCK_STYLE_TOOLTIP")
	pressed.connect(_toggle_menu)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_build_menu()
	_update_texts()
	_update_selected_visuals()
	var manager := _get_block_style_manager()
	if manager != null and manager.has_signal("style_changed"):
		var callback := Callable(self, "_on_style_changed")
		if not manager.is_connected("style_changed", callback):
			manager.connect("style_changed", callback)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()


func _draw() -> void:
	if is_hovered() or has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.40, 0.86, 1.0, 0.85), false, 2.0)


func is_menu_open() -> bool:
	return _layer != null and _layer.visible


func _toggle_menu() -> void:
	if is_menu_open():
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	if _layer == null:
		return
	_layer.visible = true
	_update_texts()
	_update_selected_visuals()
	_close_button.grab_focus()


func _close_menu() -> void:
	if _layer:
		_layer.visible = false
	grab_focus()


func _build_menu() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.visible = false
	add_child(_layer)

	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.05, 0.58)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(_on_overlay_input)
	_layer.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(MENU_WIDTH, MENU_HEIGHT)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.11, 0.94)
	panel_style.border_color = Color(0.23, 0.72, 0.86, 0.90)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.shadow_color = Color(0, 0, 0, 0.36)
	panel_style.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.custom_minimum_size = Vector2(48, 38)
	_close_button.text = "X"
	_close_button.pressed.connect(_close_menu)
	header.add_child(_close_button)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.67, 0.78, 0.86))
	vbox.add_child(_hint_label)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(_grid)

	for style in _get_styles():
		_create_style_card(style)


func _create_style_card(style: Dictionary) -> void:
	var style_id := str(style.get("id", ""))
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.text = ""
	button.pressed.connect(_on_style_pressed.bind(style_id))
	_apply_card_style(button, false)
	_grid.add_child(button)
	_style_buttons[style_id] = button

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var preview := BlockStylePreview.new()
	preview.style_id = style_id
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview)

	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(labels)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(name_label)

	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.78))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(desc_label)

	var check_label := Label.new()
	check_label.name = "CheckLabel"
	check_label.custom_minimum_size = Vector2(44, 0)
	check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check_label.add_theme_font_size_override("font_size", 24)
	check_label.add_theme_color_override("font_color", Color(0.48, 0.92, 0.72))
	check_label.text = ""
	check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(check_label)


func _on_style_pressed(style_id: String) -> void:
	var manager := _get_block_style_manager()
	if manager != null and manager.has_method("set_style_id"):
		manager.call("set_style_id", style_id)
	_update_selected_visuals()


func _on_style_changed(_style_id: String) -> void:
	_update_selected_visuals()


func _update_texts() -> void:
	tooltip_text = tr("TXT_BLOCK_STYLE_TOOLTIP")
	if _title_label:
		_title_label.text = tr("TXT_BLOCK_STYLE_TITLE")
	if _hint_label:
		_hint_label.text = tr("TXT_BLOCK_STYLE_HINT")
	if _close_button:
		_close_button.tooltip_text = tr("TXT_CLOSE")
	for style in _get_styles():
		var style_id := str(style.get("id", ""))
		var button: Button = _style_buttons.get(style_id)
		if button == null:
			continue
		var name_label: Label = button.get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/NameLabel")
		var desc_label: Label = button.get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/DescLabel")
		if name_label:
			name_label.text = tr(str(style.get("name_key", "")))
		if desc_label:
			desc_label.text = tr(str(style.get("desc_key", "")))


func _update_selected_visuals() -> void:
	if not is_inside_tree():
		return
	var current_id: String = _get_current_style_id()
	for style_id in _style_buttons.keys():
		var button: Button = _style_buttons[style_id]
		var selected: bool = str(style_id) == current_id
		button.set_pressed_no_signal(selected)
		_apply_card_style(button, selected)
		var check_label: Label = button.get_node_or_null("MarginContainer/HBoxContainer/CheckLabel")
		if check_label:
			check_label.text = "OK" if selected else ""


func _apply_card_style(button: Button, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.13, 0.16, 0.96) if not selected else Color(0.11, 0.20, 0.22, 0.98)
	normal.border_color = Color(0.22, 0.30, 0.34, 0.92) if not selected else Color(0.35, 0.92, 0.82, 1.0)
	normal.border_width_left = 1 if not selected else 2
	normal.border_width_top = 1 if not selected else 2
	normal.border_width_right = 1 if not selected else 2
	normal.border_width_bottom = 1 if not selected else 2
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate(true) as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.19, 0.22, 0.98)
	hover.border_color = Color(0.38, 0.82, 1.0, 1.0)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not is_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()


func _get_block_style_manager() -> Node:
	return get_node_or_null("/root/BlockStyleManager")


func _get_styles() -> Array:
	var manager := _get_block_style_manager()
	if manager != null and manager.has_method("get_styles"):
		return manager.call("get_styles")
	return FALLBACK_STYLES.duplicate(true)


func _get_current_style_id() -> String:
	var manager := _get_block_style_manager()
	if manager != null and manager.has_method("get_current_style_id"):
		return str(manager.call("get_current_style_id"))
	return DEFAULT_STYLE_ID
