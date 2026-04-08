extends TextureButton

const ACTIONS: Array[String] = [
	"move_left",
	"move_right",
	"soft_drop",
	"hard_drop",
	"rotate_cw",
	"rotate_ccw",
	"rotate_180",
	"hold",
	"pause"
]
const MAX_BINDINGS_PER_ACTION: int = 3
const SECTION_SETTINGS: String = "Settings"
const SECTION_BINDINGS: String = "InputBindings"

static var _defaults_captured: bool = false
static var _default_events_by_action: Dictionary = {}

var canvas_layer: CanvasLayer
var panel: PanelContainer
var option_btn: OptionButton
var close_btn: Button
var reset_all_btn: Button
var title_lbl: Label
var lang_lbl: Label
var keybind_title_lbl: Label
var keybind_hint_lbl: Label

var _action_name_labels: Dictionary = {}
var _action_slot_buttons: Dictionary = {}
var _action_reset_buttons: Dictionary = {}

var _capture_active: bool = false
var _capture_action: String = ""
var _capture_slot: int = -1

func _ready() -> void:
	var config := ConfigFile.new()
	var loc := _load_saved_locale(config)
	if loc.is_empty():
		loc = _detect_locale_from_system()
	TranslationServer.set_locale(loc)
	_capture_default_bindings_if_needed()
	_apply_saved_bindings()

	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100

	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.5, 0.5, 0.8, 1)
	panel.add_theme_stylebox_override("panel", sb)

	panel.custom_minimum_size = Vector2(820, 620)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_child(vbox)
	panel.add_child(margin)

	title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_lbl)

	var lang_hbox := HBoxContainer.new()
	lang_lbl = Label.new()
	lang_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_hbox.add_child(lang_lbl)

	option_btn = OptionButton.new()
	option_btn.add_item("English", 0)
	option_btn.add_item("\u4E2D\u6587", 1)
	option_btn.add_item("\u65E5\u672C\u8A9E", 2)

	var current_loc := TranslationServer.get_locale().to_lower()
	if current_loc.begins_with("zh"):
		option_btn.selected = 1
	elif current_loc.begins_with("ja"):
		option_btn.selected = 2
	else:
		option_btn.selected = 0

	option_btn.item_selected.connect(_on_language_selected)
	lang_hbox.add_child(option_btn)
	vbox.add_child(lang_hbox)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	keybind_title_lbl = Label.new()
	keybind_title_lbl.add_theme_font_size_override("font_size", 19)
	vbox.add_child(keybind_title_lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var keybind_box := VBoxContainer.new()
	keybind_box.add_theme_constant_override("separation", 8)
	scroll.add_child(keybind_box)
	vbox.add_child(scroll)

	for action in ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		keybind_box.add_child(row)

		var action_lbl := Label.new()
		action_lbl.custom_minimum_size = Vector2(150, 32)
		action_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(action_lbl)
		_action_name_labels[action] = action_lbl

		var slot_buttons: Array[Button] = []
		for slot_idx in range(MAX_BINDINGS_PER_ACTION):
			var slot_btn := Button.new()
			slot_btn.custom_minimum_size = Vector2(150, 32)
			slot_btn.pressed.connect(_on_bind_slot_pressed.bind(action, slot_idx))
			row.add_child(slot_btn)
			slot_buttons.append(slot_btn)
		_action_slot_buttons[action] = slot_buttons

		var reset_btn := Button.new()
		reset_btn.custom_minimum_size = Vector2(92, 32)
		reset_btn.pressed.connect(_on_reset_action_pressed.bind(action))
		row.add_child(reset_btn)
		_action_reset_buttons[action] = reset_btn

	keybind_hint_lbl = Label.new()
	keybind_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keybind_hint_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 1.0, 1.0))
	keybind_box.add_child(keybind_hint_lbl)

	reset_all_btn = Button.new()
	reset_all_btn.custom_minimum_size = Vector2(0, 38)
	reset_all_btn.pressed.connect(_on_reset_all_pressed)
	vbox.add_child(reset_all_btn)

	close_btn = Button.new()
	close_btn.text = tr("TXT_OK")
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(close_btn)

	canvas_layer.add_child(panel)
	add_child(canvas_layer)

	canvas_layer.hide()
	pressed.connect(_on_gear_pressed)
	_update_texts()
	_refresh_binding_ui()
	call_deferred("_recenter_panel")

func _on_gear_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	if canvas_layer.visible:
		hide_menu()
	else:
		show_menu()

func show_menu() -> void:
	_recenter_panel()
	canvas_layer.show()
	_refresh_binding_ui()

func hide_menu() -> void:
	_stop_capture()
	canvas_layer.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()
		_refresh_binding_ui()
	elif what == NOTIFICATION_WM_SIZE_CHANGED and is_inside_tree():
		_recenter_panel()

func _update_texts() -> void:
	if title_lbl:
		title_lbl.text = tr("TXT_SETTINGS")
	if lang_lbl:
		lang_lbl.text = tr("TXT_LANGUAGE")
	if keybind_title_lbl:
		keybind_title_lbl.text = tr("TXT_KEYBINDINGS")
	if keybind_hint_lbl and not _capture_active:
		keybind_hint_lbl.text = tr("TXT_BIND_TIP")
	if reset_all_btn:
		reset_all_btn.text = tr("TXT_BIND_RESET_DEFAULT")
	if close_btn:
		close_btn.text = tr("TXT_OK")

func _on_language_selected(idx: int) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	var loc := "en"
	match idx:
		0:
			loc = "en"
		1:
			loc = "zh"
		2:
			loc = "ja"

	TranslationServer.set_locale(loc)

	var config := ConfigFile.new()
	config.load(_get_settings_path())
	config.set_value(SECTION_SETTINGS, "locale", loc)
	config.save(_get_settings_path())


func _on_close_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()
	hide_menu()


func _recenter_panel() -> void:
	if panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = panel.custom_minimum_size
	panel.position = (viewport_size - panel_size) * 0.5

func _get_settings_path() -> String:
	if OS.has_feature("editor"):
		return "res://settings.cfg"
	else:
		return OS.get_executable_path().get_base_dir().path_join("settings.cfg")

func _load_saved_locale(config: ConfigFile) -> String:
	if config.load(_get_settings_path()) != OK:
		return ""
	var loc := str(config.get_value(SECTION_SETTINGS, "locale", "")).strip_edges().to_lower()
	return loc

func _detect_locale_from_system() -> String:
	var system_locale := OS.get_locale().to_lower()
	if system_locale.begins_with("zh"):
		return "zh"
	if system_locale.begins_with("ja"):
		return "ja"
	return "en"

func _capture_default_bindings_if_needed() -> void:
	if _defaults_captured:
		return

	for action in ACTIONS:
		_default_events_by_action[action] = _get_supported_events(action)
	_defaults_captured = true

func _apply_saved_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(_get_settings_path()) != OK:
		return

	for action in ACTIONS:
		if not config.has_section_key(SECTION_BINDINGS, action):
			continue
		var encoded_events: Variant = config.get_value(SECTION_BINDINGS, action, [])
		if not (encoded_events is Array):
			continue
		var encoded_events_array: Array = encoded_events
		var restored_events: Array = []
		for encoded in encoded_events_array:
			if not (encoded is String):
				continue
			var parsed = str_to_var(encoded)
			if _is_supported_binding_event(parsed):
				restored_events.append(parsed)
		_apply_action_events(action, restored_events)

func _save_bindings() -> void:
	var config := ConfigFile.new()
	config.load(_get_settings_path())

	for action in ACTIONS:
		var serialized_events: Array[String] = []
		for ev in _get_supported_events(action):
			serialized_events.append(var_to_str(ev))
		config.set_value(SECTION_BINDINGS, action, serialized_events)

	config.save(_get_settings_path())

func _on_bind_slot_pressed(action: String, slot_idx: int) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	_start_capture(action, slot_idx)

func _on_reset_action_pressed(action: String) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	_restore_action_default(action)
	_stop_capture()
	_save_bindings()
	_refresh_binding_ui()
	keybind_hint_lbl.text = tr("TXT_BIND_RESTORED")

func _on_reset_all_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	for action in ACTIONS:
		_restore_action_default(action)
	_stop_capture()
	_save_bindings()
	_refresh_binding_ui()
	keybind_hint_lbl.text = tr("TXT_BIND_RESTORED")

func _restore_action_default(action: String) -> void:
	var defaults: Array = _default_events_by_action.get(action, [])
	_apply_action_events(action, defaults)

func _refresh_binding_ui() -> void:
	for action in ACTIONS:
		var action_lbl: Label = _action_name_labels.get(action)
		if action_lbl:
			action_lbl.text = _get_action_display_name(action)

		var slot_buttons: Array = _action_slot_buttons.get(action, [])
		var events := _get_supported_events(action)
		for slot_idx in range(MAX_BINDINGS_PER_ACTION):
			var slot_btn: Button = null
			if slot_idx < slot_buttons.size():
				slot_btn = slot_buttons[slot_idx]
			if slot_btn == null:
				continue

			var is_capture_slot := _capture_active and _capture_action == action and _capture_slot == slot_idx
			if is_capture_slot:
				slot_btn.text = tr("TXT_BIND_WAITING")
				continue

			if slot_idx < events.size():
				slot_btn.text = _event_to_display_text(events[slot_idx])
			else:
				slot_btn.text = tr("TXT_BIND_EMPTY")

			slot_btn.tooltip_text = tr("TXT_BIND_SLOT_TIP")

		var action_reset_btn: Button = _action_reset_buttons.get(action)
		if action_reset_btn:
			action_reset_btn.text = tr("TXT_BIND_RESET_ACTION")

func _start_capture(action: String, slot_idx: int) -> void:
	_capture_active = true
	_capture_action = action
	_capture_slot = slot_idx
	keybind_hint_lbl.text = tr("TXT_BIND_PRESS_KEY")
	_refresh_binding_ui()

func _stop_capture() -> void:
	_capture_active = false
	_capture_action = ""
	_capture_slot = -1

func _extract_binding_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if not key_ev.pressed or key_ev.echo:
			return null
		var output_key := InputEventKey.new()
		output_key.physical_keycode = key_ev.physical_keycode
		output_key.keycode = key_ev.keycode
		output_key.shift_pressed = key_ev.shift_pressed
		output_key.ctrl_pressed = key_ev.ctrl_pressed
		output_key.alt_pressed = key_ev.alt_pressed
		output_key.meta_pressed = key_ev.meta_pressed
		return output_key

	if event is InputEventJoypadButton:
		var joy_btn := event as InputEventJoypadButton
		if not joy_btn.pressed:
			return null
		var output_joy_btn := InputEventJoypadButton.new()
		# 统一设为 -1，表示任意手柄都可触发。
		output_joy_btn.device = -1
		output_joy_btn.button_index = joy_btn.button_index
		return output_joy_btn

	return null

func _assign_capture_event(captured_event: InputEvent) -> void:
	if _capture_action.is_empty() or _capture_slot < 0:
		return

	var events := _get_supported_events(_capture_action)
	while events.size() < MAX_BINDINGS_PER_ACTION:
		events.append(null)

	for idx in range(MAX_BINDINGS_PER_ACTION):
		if idx == _capture_slot:
			continue
		var ev = events[idx]
		if ev != null and _events_equal(ev, captured_event):
			keybind_hint_lbl.text = tr("TXT_BIND_DUPLICATE")
			_stop_capture()
			_refresh_binding_ui()
			return

	events[_capture_slot] = captured_event

	var final_events: Array = []
	for ev in events:
		if ev != null and _is_supported_binding_event(ev):
			final_events.append(ev)
	_apply_action_events(_capture_action, final_events)
	_save_bindings()
	keybind_hint_lbl.text = tr("TXT_BIND_SAVED")
	_stop_capture()
	_refresh_binding_ui()

func _apply_action_events(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	var old_events: Array = InputMap.action_get_events(action)
	for old_ev in old_events:
		InputMap.action_erase_event(action, old_ev)

	var added: int = 0
	for ev in events:
		if not _is_supported_binding_event(ev):
			continue
		InputMap.action_add_event(action, ev)
		added += 1
		if added >= MAX_BINDINGS_PER_ACTION:
			break

func _get_supported_events(action: String) -> Array:
	var result: Array = []
	if not InputMap.has_action(action):
		return result

	var all_events: Array = InputMap.action_get_events(action)
	for ev in all_events:
		if _is_supported_binding_event(ev):
			result.append(ev)
		if result.size() >= MAX_BINDINGS_PER_ACTION:
			break
	return result

func _is_supported_binding_event(event: Variant) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton

func _event_to_display_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.physical_keycode != 0:
			return OS.get_keycode_string(key_event.physical_keycode)
		return OS.get_keycode_string(key_event.keycode)

	if event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		return "PAD_%d" % joy_event.button_index

	return tr("TXT_BIND_UNKNOWN")

func _events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false

	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		return ka.physical_keycode == kb.physical_keycode and ka.keycode == kb.keycode and ka.shift_pressed == kb.shift_pressed and ka.ctrl_pressed == kb.ctrl_pressed and ka.alt_pressed == kb.alt_pressed and ka.meta_pressed == kb.meta_pressed

	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		var ja := a as InputEventJoypadButton
		var jb := b as InputEventJoypadButton
		return ja.button_index == jb.button_index

	return false

func _get_action_display_name(action: String) -> String:
	match action:
		"move_left":
			return tr("TXT_ACTION_MOVE_LEFT")
		"move_right":
			return tr("TXT_ACTION_MOVE_RIGHT")
		"soft_drop":
			return tr("TXT_ACTION_SOFT_DROP")
		"hard_drop":
			return tr("TXT_ACTION_HARD_DROP")
		"rotate_cw":
			return tr("TXT_ACTION_ROTATE_CW")
		"rotate_ccw":
			return tr("TXT_ACTION_ROTATE_CCW")
		"rotate_180":
			return tr("TXT_ACTION_ROTATE_180")
		"hold":
			return tr("TXT_ACTION_HOLD")
		"pause":
			return tr("TXT_ACTION_PAUSE")
		_:
			return action

func _input(event: InputEvent) -> void:
	if not canvas_layer or not canvas_layer.visible:
		return

	if _capture_active:
		# 监听模式下按 ESC 取消，不写入绑定。
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_ESCAPE:
				_stop_capture()
				_refresh_binding_ui()
				keybind_hint_lbl.text = tr("TXT_BIND_CANCELLED")
				get_viewport().set_input_as_handled()
				return

		var captured := _extract_binding_event(event)
		if captured != null:
			_assign_capture_event(captured)
			get_viewport().set_input_as_handled()
			return

	if not InputMap.has_action("pause"):
		return
	if event.is_action_pressed("pause"):
		hide_menu()
		get_viewport().set_input_as_handled()
