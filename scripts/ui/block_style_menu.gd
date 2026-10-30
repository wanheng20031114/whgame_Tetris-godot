extends TextureButton

var _layer: CanvasLayer
var _panel: PanelContainer
var _title_label: Label
var _hint_label: Label
var _grid: GridContainer
var _close_button: Button
var _style_buttons: Dictionary = {}
var _backdrop: ColorRect
var _last_focus_owner: Control


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_normal = null
	remove_from_group(UITheme.GROUP_ICON_TINT)
	self_modulate = Color.WHITE
	tooltip_text = tr("TXT_BLOCK_STYLE_TOOLTIP")
	pressed.connect(_toggle_menu)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_bind_scene_controls()
	UITheme.theme_changed.connect(_on_theme_changed)
	_update_texts()
	_update_selected_visuals()
	BlockStyleManager.style_changed.connect(_on_style_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()


var _icon_anim: float = 0.0


func _process(delta: float) -> void:
	var target := 1.0 if (is_hovered() or is_menu_open()) else 0.0
	if not is_equal_approx(_icon_anim, target):
		_icon_anim = move_toward(_icon_anim, target, delta * 4.0)
		queue_redraw()


func _draw() -> void:
	var e := ease(_icon_anim, -2.0)
	UIIcon.draw_chrome(self, Rect2(Vector2.ZERO, size), e, has_focus())
	UIIcon.draw(self, "blocks", size * 0.5, minf(size.x, size.y) * 0.62, UIIcon.tint(e), e)


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
	_last_focus_owner = get_viewport().gui_get_focus_owner()
	_layer.visible = true
	_on_theme_changed(UITheme.mode)
	_update_texts()
	_update_selected_visuals()
	UITheme.pop_in(_panel)
	_style_buttons[BlockStyleManager.get_current_style_id()].grab_focus()


func _close_menu() -> void:
	if _layer:
		_layer.visible = false
	if is_instance_valid(_last_focus_owner) and _last_focus_owner.is_inside_tree():
		_last_focus_owner.grab_focus()
	else:
		grab_focus()


func _bind_scene_controls() -> void:
	_layer = %StyleLayer
	_panel = %StylePanel
	_title_label = %StyleTitle
	_hint_label = %StyleHint
	_grid = %StyleGrid
	_close_button = %CloseStyle
	_backdrop = %StyleBackdrop
	_close_button.pressed.connect(_close_menu)
	_backdrop.gui_input.connect(_on_overlay_input)
	for style in BlockStyleManager.STYLES:
		var style_id: String = style["id"]
		var button: Button = _grid.get_node(style_id)
		button.pressed.connect(_on_style_pressed.bind(style_id))
		_style_buttons[style_id] = button
	UITheme.confine_focus(_panel)


func _on_theme_changed(_mode: String) -> void:
	_backdrop.color = Color(UITheme.color("ink"), 0.55 if UITheme.is_dark() else 0.35)
	_update_selected_visuals()
	queue_redraw()


func _on_style_pressed(style_id: String) -> void:
	BlockStyleManager.set_style_id(style_id)
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
	for style in BlockStyleManager.get_styles():
		var style_id := str(style.get("id", ""))
		var button: Button = _style_buttons.get(style_id)
		if button == null:
			continue
		var name_label: Label = button.get_node_or_null("Margin/Row/Labels/Name")
		var desc_label: Label = button.get_node_or_null("Margin/Row/Labels/Description")
		if name_label:
			name_label.text = tr(str(style.get("name_key", "")))
		if desc_label:
			desc_label.text = tr(str(style.get("desc_key", "")))


func _update_selected_visuals() -> void:
	if not is_inside_tree():
		return
	var current_id: String = BlockStyleManager.get_current_style_id()
	for style_id in _style_buttons.keys():
		var button: Button = _style_buttons[style_id]
		var selected: bool = str(style_id) == current_id
		button.set_pressed_no_signal(selected)
		_apply_card_style(button, selected)
		var check_label: Label = button.get_node_or_null("Margin/Row/Selected")
		if check_label:
			check_label.text = "✓" if selected else ""


func _apply_card_style(button: Button, selected: bool) -> void:
	# 色块圆角卡片；选中为青绿淡底 + 描边
	var base := UITheme.color("surface2")
	var states := {
		"normal": base,
		"hover": UITheme.color("surface3"),
		"pressed": base,
		"hover_pressed": UITheme.color("surface3"),
		"focus": Color(0, 0, 0, 0),
	}
	for key in states:
		var box := StyleBoxFlat.new()
		box.bg_color = states[key]
		box.set_corner_radius_all(24)
		box.anti_aliasing_size = 0.75
		box.set_content_margin_all(10)
		if key == "focus":
			box.draw_center = false
			box.border_color = UITheme.color("accent")
			box.set_border_width_all(3)
			box.expand_margin_left = 3
			box.expand_margin_right = 3
			box.expand_margin_top = 3
			box.expand_margin_bottom = 3
			box.set_corner_radius_all(27)
		elif selected:
			box.bg_color = UITheme.color("surface").lerp(UITheme.color("accent"), 0.16)
			box.border_color = UITheme.color("accent")
			box.set_border_width_all(3)
		button.add_theme_stylebox_override(key, box)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not is_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()
