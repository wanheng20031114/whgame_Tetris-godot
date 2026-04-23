extends TextureButton

## 设置菜单脚本
## 负责处理游戏设置，包括语言切换、分辨率调整、全屏开关以及按键绑定。

# --- 常量定义 ---

# 游戏内可绑定的操作列表
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

# 每个操作支持的最大绑定数量
const MAX_BINDINGS_PER_ACTION: int = 3

# 配置文件中的扇区名称
const SECTION_SETTINGS: String = "Settings"
const SECTION_BINDINGS: String = "InputBindings"
const SECTION_RESOLUTION: String = "Resolution"
const SECTION_DISPLAY: String = "Display"

# 默认分辨率 ID
const DEFAULT_RESOLUTION_ID: String = "1280x720"

# 预设的分辨率选项
const RESOLUTION_OPTIONS: Array[Dictionary] = [
	{"id": "1280x720", "label": "1280 x 720 (720p)", "width": 1280, "height": 720},
	{"id": "1366x768", "label": "1366 x 768", "width": 1366, "height": 768},
	{"id": "1600x900", "label": "1600 x 900", "width": 1600, "height": 900},
	{"id": "1920x1080", "label": "1920 x 1080 (1080p)", "width": 1920, "height": 1080},
	{"id": "1920x1200", "label": "1920 x 1200", "width": 1920, "height": 1200},
	{"id": "2560x1080", "label": "2560 x 1080 (UW-FHD)", "width": 2560, "height": 1080},
	{"id": "2560x1440", "label": "2560 x 1440 (2K)", "width": 2560, "height": 1440},
	{"id": "3440x1440", "label": "3440 x 1440 (UWQHD)", "width": 3440, "height": 1440},
	{"id": "3840x2160", "label": "3840 x 2160 (4K)", "width": 3840, "height": 2160}
]

# 用于存储默认按键绑定的静态变量，防止多次捕获
static var _defaults_captured: bool = false
static var _default_events_by_action: Dictionary = {}

# --- 界面组件引用 ---

var canvas_layer: CanvasLayer        # 顶层画布，用于悬浮显示菜单
var panel: PanelContainer           # 菜单主面板
var option_btn: OptionButton        # 语言选择下拉框
var resolution_option_btn: OptionButton # 分辨率选择下拉框
var fullscreen_checkbox: Button     # 全屏开关按钮（模拟复选框）
var fullscreen_indicator: Panel     # 全屏开关的状态指示器
var close_btn: Button               # 关闭/确定按钮
var reset_all_btn: Button           # 重置所有按键按钮

# 各种文本标签
var title_lbl: Label
var lang_lbl: Label
var resolution_lbl: Label
var fullscreen_lbl: Label
var keybind_title_lbl: Label
var keybind_hint_lbl: Label

# 按键绑定 UI 的动态映射
var _action_name_labels: Dictionary = {}    # 操作名称标签映射
var _action_slot_buttons: Dictionary = {}   # 操作绑定槽位按钮映射
var _action_reset_buttons: Dictionary = {}  # 单项操作重置按钮映射

# 按键捕获状态
var _capture_active: bool = false # 当前是否正在捕获新按键
var _capture_action: String = ""   # 正在捕获按键的操作名称
var _capture_slot: int = -1        # 正在捕获按键的槽位索引

# --- 辅助方法 ---

## 创建复选框风格的样式盒
func _make_checkbox_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	return sb

## 创建全屏指示器的样式盒
func _make_fullscreen_indicator_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.86, 0.35, 0.98) # 鲜亮的绿色
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb

## 更新全屏开关的视觉状态
func _update_fullscreen_checkbox_visual() -> void:
	if fullscreen_checkbox == null:
		return
	fullscreen_checkbox.text = "" # 按钮文本留空，使用指示器显示状态
	if fullscreen_indicator:
		fullscreen_indicator.visible = fullscreen_checkbox.button_pressed

# --- 生命周期回调 ---

func _ready() -> void:
	# 1. 初始化设置与应用
	var config := ConfigFile.new()
	
	# 设置语言
	var loc := _load_saved_locale(config)
	if loc.is_empty():
		loc = _detect_locale_from_system()
	TranslationServer.set_locale(loc)
	
	# 应用显示设置（分辨率、全屏）
	_apply_saved_display_settings(config)
	
	# 应用按键绑定
	_capture_default_bindings_if_needed()
	_apply_saved_bindings()

	# 2. 动态构建 UI 界面
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100 # 确保菜单在最上层

	# 面板样式
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

	# 垂直布局容器
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_child(vbox)
	panel.add_child(margin)

	# 标题
	title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_lbl)

	# --- 语言设置行 ---
	var lang_hbox := HBoxContainer.new()
	lang_lbl = Label.new()
	lang_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_hbox.add_child(lang_lbl)

	option_btn = OptionButton.new()
	option_btn.add_item("English", 0)
	option_btn.add_item("\u4E2D\u6587", 1)
	option_btn.add_item("\u65E5\u672C\u8A9E", 2)

	# 初始化语言选择状态
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

	# --- 分辨率设置行 ---
	var resolution_hbox := HBoxContainer.new()
	resolution_lbl = Label.new()
	resolution_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_hbox.add_child(resolution_lbl)

	resolution_option_btn = OptionButton.new()
	for option in RESOLUTION_OPTIONS:
		resolution_option_btn.add_item(str(option.get("label", "")))
	resolution_option_btn.selected = _get_selected_resolution_index(config)
	resolution_option_btn.item_selected.connect(_on_resolution_selected)
	resolution_hbox.add_child(resolution_option_btn)
	vbox.add_child(resolution_hbox)

	# --- 全屏开关行 ---
	var fullscreen_hbox := HBoxContainer.new()
	fullscreen_lbl = Label.new()
	fullscreen_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullscreen_hbox.add_child(fullscreen_lbl)

	fullscreen_checkbox = Button.new()
	fullscreen_checkbox.toggle_mode = true
	fullscreen_checkbox.button_pressed = _is_fullscreen_saved(config)
	fullscreen_checkbox.custom_minimum_size = Vector2(42, 42)
	fullscreen_checkbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	fullscreen_checkbox.tooltip_text = tr("TXT_FULLSCREEN")
	fullscreen_checkbox.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 设置多种状态下的复选框样式
	fullscreen_checkbox.add_theme_stylebox_override("normal", _make_checkbox_style(Color(0.13, 0.15, 0.22, 0.95), Color(0.62, 0.68, 0.9, 0.95)))
	fullscreen_checkbox.add_theme_stylebox_override("hover", _make_checkbox_style(Color(0.16, 0.18, 0.27, 0.98), Color(0.74, 0.8, 0.98, 1.0)))
	fullscreen_checkbox.add_theme_stylebox_override("pressed", _make_checkbox_style(Color(0.13, 0.15, 0.22, 0.95), Color(0.9, 0.93, 0.98, 1.0)))
	fullscreen_checkbox.add_theme_stylebox_override("hover_pressed", _make_checkbox_style(Color(0.16, 0.18, 0.27, 0.98), Color(0.95, 0.97, 1.0, 1.0)))
	fullscreen_checkbox.add_theme_stylebox_override("focus", _make_checkbox_style(Color(0.13, 0.15, 0.22, 0.95), Color(0.9, 0.93, 0.98, 1.0)))
	fullscreen_checkbox.add_theme_stylebox_override("disabled", _make_checkbox_style(Color(0.09, 0.11, 0.17, 0.65), Color(0.42, 0.46, 0.58, 0.7)))

	# 状态指示器
	var indicator_center := CenterContainer.new()
	indicator_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fullscreen_checkbox.add_child(indicator_center)

	fullscreen_indicator = Panel.new()
	fullscreen_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fullscreen_indicator.custom_minimum_size = Vector2(24, 24)
	fullscreen_indicator.add_theme_stylebox_override("panel", _make_fullscreen_indicator_style())
	indicator_center.add_child(fullscreen_indicator)

	_update_fullscreen_checkbox_visual()
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	fullscreen_hbox.add_child(fullscreen_checkbox)
	vbox.add_child(fullscreen_hbox)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	# --- 按键绑定部分 ---
	keybind_title_lbl = Label.new()
	keybind_title_lbl.add_theme_font_size_override("font_size", 19)
	vbox.add_child(keybind_title_lbl)

	# 滚动区域处理大量的按键映射
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var keybind_box := VBoxContainer.new()
	keybind_box.add_theme_constant_override("separation", 8)
	scroll.add_child(keybind_box)
	vbox.add_child(scroll)

	# 为每个操作生成绑定行
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

	# 操作提示
	keybind_hint_lbl = Label.new()
	keybind_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keybind_hint_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 1.0, 1.0))
	keybind_box.add_child(keybind_hint_lbl)

	# 重置所有按键按钮
	reset_all_btn = Button.new()
	reset_all_btn.custom_minimum_size = Vector2(0, 38)
	reset_all_btn.pressed.connect(_on_reset_all_pressed)
	vbox.add_child(reset_all_btn)

	# 退出按钮
	close_btn = Button.new()
	close_btn.text = tr("TXT_OK")
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(close_btn)

	# 最终装配
	canvas_layer.add_child(panel)
	add_child(canvas_layer)

	canvas_layer.hide()
	pressed.connect(_on_gear_pressed) # 点击主界面的设置图标
	
	# 初始更新 UI 文本
	_update_texts()
	_update_resolution_interactability()
	_refresh_binding_ui()
	call_deferred("_recenter_panel")

# --- 信号处理与逻辑 ---

## 点击齿轮图标：切换菜单显示状态
func _on_gear_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	if canvas_layer.visible:
		hide_menu()
	else:
		show_menu()

## 显示设置菜单
func show_menu() -> void:
	_recenter_panel()
	canvas_layer.show()
	_refresh_binding_ui()

## 隐藏设置菜单
func hide_menu() -> void:
	_stop_capture()
	canvas_layer.hide()

## 系统通知处理：处理多语言实时切换和窗口大小调整
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()
		_refresh_binding_ui()
	elif what == NOTIFICATION_WM_SIZE_CHANGED and is_inside_tree():
		_recenter_panel()

## 更新界面上的所有本地化文本
func _update_texts() -> void:
	if title_lbl:
		title_lbl.text = tr("TXT_SETTINGS")
	if lang_lbl:
		lang_lbl.text = tr("TXT_LANGUAGE")
	if resolution_lbl:
		var localized_resolution := tr("TXT_RESOLUTION")
		resolution_lbl.text = localized_resolution if localized_resolution != "TXT_RESOLUTION" else "RESOLUTION"
	if fullscreen_lbl:
		var localized_fullscreen := tr("TXT_FULLSCREEN")
		fullscreen_lbl.text = localized_fullscreen if localized_fullscreen != "TXT_FULLSCREEN" else "FULLSCREEN"
	if fullscreen_checkbox:
		fullscreen_checkbox.tooltip_text = tr("TXT_FULLSCREEN")
	_update_fullscreen_checkbox_visual()
	if keybind_title_lbl:
		keybind_title_lbl.text = tr("TXT_KEYBINDINGS")
	if keybind_hint_lbl and not _capture_active:
		keybind_hint_lbl.text = tr("TXT_BIND_TIP")
	if reset_all_btn:
		reset_all_btn.text = tr("TXT_BIND_RESET_DEFAULT")
	if close_btn:
		close_btn.text = tr("TXT_OK")

## 切换语言逻辑
func _on_language_selected(idx: int) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	var loc := "en"
	match idx:
		0: loc = "en"
		1: loc = "zh"
		2: loc = "ja"

	TranslationServer.set_locale(loc)

	# 保存语言设置到本地文件
	var config := ConfigFile.new()
	config.load(_get_settings_path())
	config.set_value(SECTION_SETTINGS, "locale", loc)
	config.save(_get_settings_path())

## 切换分辨率逻辑
func _on_resolution_selected(idx: int) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()
	_apply_resolution_by_index(idx)
	_save_selected_resolution(idx)

## 切换全屏逻辑
func _on_fullscreen_toggled(enabled: bool) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	var window := get_window()
	if window == null:
		return

	if enabled:
		# 进入全屏模式
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	else:
		# 退出全屏，恢复到默认分辨率窗口
		window.mode = Window.MODE_WINDOWED
		var default_idx := _get_default_resolution_index()
		_apply_resolution_by_index(default_idx)
		_save_selected_resolution(default_idx)

	_save_fullscreen(enabled)
	_update_fullscreen_checkbox_visual()
	_update_resolution_interactability()

## 点击确定按钮并关闭
func _on_close_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()
	hide_menu()

## 始终将面板置于屏幕正中央
func _recenter_panel() -> void:
	if panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = panel.custom_minimum_size
	panel.position = (viewport_size - panel_size) * 0.5

## 获取配置文件路径（编辑器与导出版本路径不同）
func _get_settings_path() -> String:
	if OS.has_feature("editor"):
		return "res://settings.cfg"
	else:
		return OS.get_executable_path().get_base_dir().path_join("settings.cfg")

## 加载保存的语言
func _load_saved_locale(config: ConfigFile) -> String:
	if config.load(_get_settings_path()) != OK:
		return ""
	var loc := str(config.get_value(SECTION_SETTINGS, "locale", "")).strip_edges().to_lower()
	return loc

## 加载并应用显示相关设置
func _apply_saved_display_settings(config: ConfigFile) -> void:
	var is_fullscreen := _is_fullscreen_saved(config)
	var window := get_window()
	if window != null:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if is_fullscreen else Window.MODE_WINDOWED

	if is_fullscreen:
		if fullscreen_checkbox:
			fullscreen_checkbox.button_pressed = true
	else:
		_apply_resolution_by_index(_get_selected_resolution_index(config))
		if fullscreen_checkbox:
			fullscreen_checkbox.button_pressed = false

	_update_fullscreen_checkbox_visual()
	_update_resolution_interactability()

## 获取保存的分辨率索引
func _get_selected_resolution_index(config: ConfigFile) -> int:
	if config.load(_get_settings_path()) != OK:
		return _get_default_resolution_index()

	var resolution_id := str(config.get_value(SECTION_RESOLUTION, "id", DEFAULT_RESOLUTION_ID)).strip_edges().to_lower()
	for idx in range(RESOLUTION_OPTIONS.size()):
		var option_id := str(RESOLUTION_OPTIONS[idx].get("id", "")).to_lower()
		if option_id == resolution_id:
			return idx
	return _get_default_resolution_index()

## 获取默认分辨率在列表中的索引
func _get_default_resolution_index() -> int:
	for idx in range(RESOLUTION_OPTIONS.size()):
		var option_id := str(RESOLUTION_OPTIONS[idx].get("id", "")).to_lower()
		if option_id == DEFAULT_RESOLUTION_ID:
			return idx
	return 0

## 检查是否保存了全屏设置
func _is_fullscreen_saved(config: ConfigFile) -> bool:
	if config.load(_get_settings_path()) != OK:
		return false
	return bool(config.get_value(SECTION_DISPLAY, "fullscreen", false))

## 保存当前选中的分辨率 ID
func _save_selected_resolution(idx: int) -> void:
	if idx < 0 or idx >= RESOLUTION_OPTIONS.size():
		return

	var config := ConfigFile.new()
	config.load(_get_settings_path())
	var option := RESOLUTION_OPTIONS[idx]
	config.set_value(SECTION_RESOLUTION, "id", str(option.get("id", DEFAULT_RESOLUTION_ID)))
	config.save(_get_settings_path())

## 保存全屏设置
func _save_fullscreen(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(_get_settings_path())
	config.set_value(SECTION_DISPLAY, "fullscreen", enabled)
	config.save(_get_settings_path())

## 当全屏模式打开时，禁用分辨率选择
func _update_resolution_interactability() -> void:
	if resolution_option_btn and fullscreen_checkbox:
		resolution_option_btn.disabled = fullscreen_checkbox.button_pressed

## 实际应用窗口分辨率，并处理编辑器模式下的缩放适配
func _apply_resolution_by_index(idx: int) -> void:
	if idx < 0 or idx >= RESOLUTION_OPTIONS.size():
		idx = _get_default_resolution_index()

	var option := RESOLUTION_OPTIONS[idx]
	var width := int(option.get("width", 1280))
	var height := int(option.get("height", 720))

	var window := get_window()
	if window == null:
		return

	window.size = Vector2i(width, height)
	
	# 如果在编辑器中运行，手动同步根窗口的拉伸设置
	if OS.has_feature("editor"):
		var root_window := get_tree().root
		if root_window != null:
			root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			root_window.content_scale_size = Vector2i(width, height)

	if resolution_option_btn:
		resolution_option_btn.selected = idx

## 从系统环境中推断首选语言
func _detect_locale_from_system() -> String:
	var system_locale := OS.get_locale().to_lower()
	if system_locale.begins_with("zh"):
		return "zh"
	if system_locale.begins_with("ja"):
		return "ja"
	return "en"

# --- 按键绑定逻辑核心 ---

## 首次启动时捕获引擎默认的按键设置，作为“恢复默认”的基准
func _capture_default_bindings_if_needed() -> void:
	if _defaults_captured:
		return

	for action in ACTIONS:
		_default_events_by_action[action] = _get_supported_events(action)
	_defaults_captured = true

## 从磁盘加载并应用之前保存的自定义按键
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

## 将当前的 InputMap 状态永久保存到设置文件
func _save_bindings() -> void:
	var config := ConfigFile.new()
	config.load(_get_settings_path())

	for action in ACTIONS:
		var serialized_events: Array[String] = []
		for ev in _get_supported_events(action):
			serialized_events.append(var_to_str(ev))
		config.set_value(SECTION_BINDINGS, action, serialized_events)

	config.save(_get_settings_path())

## 点击特定绑定槽位：开始按键捕获模式
func _on_bind_slot_pressed(action: String, slot_idx: int) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	_start_capture(action, slot_idx)

## 点击单项重置：将某一个操作恢复为初次启动时的默认按键
func _on_reset_action_pressed(action: String) -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	_restore_action_default(action)
	_stop_capture()
	_save_bindings()
	_refresh_binding_ui()
	keybind_hint_lbl.text = tr("TXT_BIND_RESTORED")

## 点击全局重置：恢复所有按键为默认
func _on_reset_all_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	for action in ACTIONS:
		_restore_action_default(action)
	_stop_capture()
	_save_bindings()
	_refresh_binding_ui()
	keybind_hint_lbl.text = tr("TXT_BIND_RESTORED")

## 内部方法：将单项操作恢复为默认
func _restore_action_default(action: String) -> void:
	var defaults: Array = _default_events_by_action.get(action, [])
	_apply_action_events(action, defaults)

## 刷新整张按键绑定表的文本显示
func _refresh_binding_ui() -> void:
	for action in ACTIONS:
		# 获取操作名称的本地化标签
		var action_lbl: Label = _action_name_labels.get(action)
		if action_lbl:
			action_lbl.text = _get_action_display_name(action)

		var slot_buttons: Array = _action_slot_buttons.get(action, [])
		var events := _get_supported_events(action)
		
		# 遍历每个槽位（最多 3 个）
		for slot_idx in range(MAX_BINDINGS_PER_ACTION):
			var slot_btn: Button = null
			if slot_idx < slot_buttons.size():
				slot_btn = slot_buttons[slot_idx]
			if slot_btn == null:
				continue

			# 判断是否正处于对应槽位的录入状态
			var is_capture_slot := _capture_active and _capture_action == action and _capture_slot == slot_idx
			if is_capture_slot:
				slot_btn.text = tr("TXT_BIND_WAITING") # 显示“请按键...”
				continue

			# 显示当前绑定的按键名称或显示为空
			if slot_idx < events.size():
				slot_btn.text = _event_to_display_text(events[slot_idx])
			else:
				slot_btn.text = tr("TXT_BIND_EMPTY")

			slot_btn.tooltip_text = tr("TXT_BIND_SLOT_TIP")

		# 更新单行重置按钮的文本
		var action_reset_btn: Button = _action_reset_buttons.get(action)
		if action_reset_btn:
			action_reset_btn.text = tr("TXT_BIND_RESET_ACTION")

## 启动捕获模式
func _start_capture(action: String, slot_idx: int) -> void:
	_capture_active = true
	_capture_action = action
	_capture_slot = slot_idx
	keybind_hint_lbl.text = tr("TXT_BIND_PRESS_KEY")
	_refresh_binding_ui()

## 停止捕获模式
func _stop_capture() -> void:
	_capture_active = false
	_capture_action = ""
	_capture_slot = -1

## 从 InputEvent 中提炼核心按键信息（去除重复触发和无用元数据）
func _extract_binding_event(event: InputEvent) -> InputEvent:
	# 处理键盘连发或松开事件
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

	# 处理手柄按钮
	if event is InputEventJoypadButton:
		var joy_btn := event as InputEventJoypadButton
		if not joy_btn.pressed:
			return null
		var output_joy_btn := InputEventJoypadButton.new()
		# 统一设为 -1，表示任意手柄都可触发
		output_joy_btn.device = -1
		output_joy_btn.button_index = joy_btn.button_index
		return output_joy_btn

	return null

## 将捕获到的按键分配给选中的操作
func _assign_capture_event(captured_event: InputEvent) -> void:
	if _capture_action.is_empty() or _capture_slot < 0:
		return

	var events := _get_supported_events(_capture_action)
	while events.size() < MAX_BINDINGS_PER_ACTION:
		events.append(null)

	# 冲突检查：防止同一个操作内绑定重复的键
	for idx in range(MAX_BINDINGS_PER_ACTION):
		if idx == _capture_slot:
			continue
		var ev = events[idx]
		if ev != null and _events_equal(ev, captured_event):
			keybind_hint_lbl.text = tr("TXT_BIND_DUPLICATE")
			_stop_capture()
			_refresh_binding_ui()
			return

	# 替换或添加按键
	events[_capture_slot] = captured_event

	# 过滤掉空占位符并应用到引擎
	var final_events: Array = []
	for ev in events:
		if ev != null and _is_supported_binding_event(ev):
			final_events.append(ev)
	_apply_action_events(_capture_action, final_events)
	
	_save_bindings()
	keybind_hint_lbl.text = tr("TXT_BIND_SAVED")
	_stop_capture()
	_refresh_binding_ui()

## 核心引擎交互：直接修改 InputMap（内存操作）
func _apply_action_events(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	# 清理旧的绑定
	var old_events: Array = InputMap.action_get_events(action)
	for old_ev in old_events:
		InputMap.action_erase_event(action, old_ev)

	# 注入新的绑定
	var added: int = 0
	for ev in events:
		if not _is_supported_binding_event(ev):
			continue
		InputMap.action_add_event(action, ev)
		added += 1
		if added >= MAX_BINDINGS_PER_ACTION:
			break

## 从 InputMap 获取我们支持的（键盘/手柄）有效按键
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

## 检查是否为支持的可录入按键类型
func _is_supported_binding_event(event: Variant) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton

## 将按键事件转换为用户可读的字符串（如 "Space", "Enter", "PAD_0"）
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

## 比较两个 InputEvent 是否在功能上等价
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

## 获取操作名称的本地化显示名称
func _get_action_display_name(action: String) -> String:
	match action:
		"move_left": return tr("TXT_ACTION_MOVE_LEFT")
		"move_right": return tr("TXT_ACTION_MOVE_RIGHT")
		"soft_drop": return tr("TXT_ACTION_SOFT_DROP")
		"hard_drop": return tr("TXT_ACTION_HARD_DROP")
		"rotate_cw": return tr("TXT_ACTION_ROTATE_CW")
		"rotate_ccw": return tr("TXT_ACTION_ROTATE_CCW")
		"rotate_180": return tr("TXT_ACTION_ROTATE_180")
		"hold": return tr("TXT_ACTION_HOLD")
		"pause": return tr("TXT_ACTION_PAUSE")
		_: return action

# --- 全局输入拦截 ---

func _input(event: InputEvent) -> void:
	# 菜单未打开时不处理
	if not canvas_layer or not canvas_layer.visible:
		return

	if _capture_active:
		# 在按键捕获模式下拦截
		if event is InputEventKey:
			var key_event := event as InputEventKey
			# 按下 ESC 取消捕获
			if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_ESCAPE:
				_stop_capture()
				_refresh_binding_ui()
				keybind_hint_lbl.text = tr("TXT_BIND_CANCELLED")
				get_viewport().set_input_as_handled()
				return

		# 尝试提炼录入的按键
		var captured := _extract_binding_event(event)
		if captured != null:
			_assign_capture_event(captured)
			get_viewport().set_input_as_handled()
			return

	# 处理暂停/关闭菜单的快捷键（如果 InputMap 中定义了 pause）
	if not InputMap.has_action("pause"):
		return
	if event.is_action_pressed("pause"):
		hide_menu()
		get_viewport().set_input_as_handled()
