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
const SECTION_AUDIO: String = "Audio"
const DEFAULT_MASTER_VOLUME_PERCENT: float = 60.0
const PANEL_WIDTH: float = 1040.0
const PANEL_MAX_HEIGHT: float = 620.0
const PANEL_SCREEN_MARGIN: float = 48.0

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
var settings_scroll: ScrollContainer # 设置菜单整体滚动区
var option_btn: OptionButton        # 语言选择下拉框
var resolution_option_btn: OptionButton # 分辨率选择下拉框
var fullscreen_checkbox: Button     # 全屏开关（ToggleSwitch）
var backdrop: ColorRect             # 菜单背后的压暗遮罩
var theme_switch: ThemeSwitch       # 深浅主题开关
var volume_slider: HSlider          # 总体音量滑块
var volume_value_lbl: Label         # 音量百分比标签
var close_btn: Button               # 关闭/确定按钮
var reset_all_btn: Button           # 重置所有按键按钮
var _last_focus_owner: Control = null
var _icon_hovered: bool = false

# 各种文本标签
var title_lbl: Label
var lang_lbl: Label
var theme_lbl: Label
var resolution_lbl: Label
var fullscreen_lbl: Label
var volume_lbl: Label
var keybind_title_lbl: Label
var keybind_hint_lbl: Label
var handling_title_lbl: Label
var _handling_sliders: Dictionary = {}
var _handling_values: Dictionary = {}

# 按键绑定 UI 的动态映射
var _action_name_labels: Dictionary = {}    # 操作名称标签映射
var _action_slot_buttons: Dictionary = {}   # 操作绑定槽位按钮映射
var _action_reset_buttons: Dictionary = {}  # 单项操作重置按钮映射

# 按键捕获状态
var _capture_active: bool = false # 当前是否正在捕获新按键
var _capture_action: String = ""   # 正在捕获按键的操作名称
var _capture_slot: int = -1        # 正在捕获按键的槽位索引

# --- 辅助方法 ---

# --- 生命周期回调 ---

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_icon_hover_changed.bind(true))
	mouse_exited.connect(_on_icon_hover_changed.bind(false))

	# 启动配置只由 AutoLoad 应用一次；场景内齿轮只绑定可编辑的原生场景。
	var config := ConfigFile.new()
	if get_path() == NodePath("/root/SettingsMenu"):
		var loc := _load_saved_locale(config)
		TranslationServer.set_locale(_detect_locale_from_system() if loc.is_empty() else loc)
		_apply_saved_display_settings(config)
		_apply_saved_audio_settings(config)
		_capture_default_bindings_if_needed()
		_apply_saved_bindings()
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		return

	remove_from_group(UITheme.GROUP_ICON_TINT)
	self_modulate = Color.WHITE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bind_scene_controls(config)
	pressed.connect(_on_gear_pressed)
	UITheme.theme_changed.connect(_on_theme_changed)
	_update_texts()
	_update_resolution_interactability()
	_refresh_binding_ui()
	call_deferred("_recenter_panel")


func _bind_scene_controls(config: ConfigFile) -> void:
	canvas_layer = %MenuLayer
	panel = %SettingsPanel
	backdrop = %Backdrop
	settings_scroll = %KeybindScroll
	option_btn = %LanguageOption
	resolution_option_btn = %ResolutionOption
	fullscreen_checkbox = %FullscreenSwitch
	theme_switch = %ThemeSwitch
	volume_slider = %VolumeSlider
	volume_value_lbl = %VolumeValue
	close_btn = %ConfirmButton
	reset_all_btn = %ResetAllButton
	title_lbl = %SettingsTitle
	lang_lbl = %LanguageLabel
	theme_lbl = %ThemeLabel
	resolution_lbl = %ResolutionLabel
	fullscreen_lbl = %FullscreenLabel
	volume_lbl = %VolumeLabel
	keybind_title_lbl = %KeybindTitle
	keybind_hint_lbl = %KeybindHint
	handling_title_lbl = %HandlingTitle
	backdrop.gui_input.connect(_on_backdrop_input)
	%CloseIcon.pressed.connect(_on_close_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	reset_all_btn.pressed.connect(_on_reset_all_pressed)
	%HandlingReset.pressed.connect(_on_handling_reset_pressed)

	for language in ["English", "中文", "日本語"]:
		option_btn.add_item(language)
	var locale := TranslationServer.get_locale().to_lower()
	option_btn.selected = 1 if locale.begins_with("zh") else (2 if locale.begins_with("ja") else 0)
	option_btn.item_selected.connect(_on_language_selected)
	fullscreen_checkbox.set_pressed_no_signal(_is_fullscreen_saved(config))
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	for option in RESOLUTION_OPTIONS:
		resolution_option_btn.add_item(option["label"])
	resolution_option_btn.selected = _get_selected_resolution_index(config)
	resolution_option_btn.item_selected.connect(_on_resolution_selected)
	volume_slider.value = _get_saved_master_volume_percent(config)
	volume_slider.value_changed.connect(_on_master_volume_changed)
	_update_volume_value_label()

	for key in Handling.RANGES:
		var cell: VBoxContainer = %HandlingRow.get_node(key)
		var slider: HSlider = cell.get_node("Slider")
		var limits: Array = Handling.RANGES[key]
		slider.min_value = limits[0]
		slider.max_value = limits[1]
		slider.step = limits[2]
		slider.value = Handling.get_value(key)
		slider.value_changed.connect(_on_handling_changed.bind(key))
		_handling_sliders[key] = slider
		_handling_values[key] = cell.get_node("Header/Value")
	_refresh_handling_labels()

	for action in ACTIONS:
		var row: HBoxContainer = %KeybindRows.get_node(action)
		_action_name_labels[action] = row.get_node("ActionName")
		var slots: Array[Button] = []
		for slot in MAX_BINDINGS_PER_ACTION:
			var button: Button = row.get_node("Slot%d" % slot)
			button.pressed.connect(_on_bind_slot_pressed.bind(action, slot))
			slots.append(button)
		_action_slot_buttons[action] = slots
		var reset: Button = row.get_node("Reset")
		reset.pressed.connect(_on_reset_action_pressed.bind(action))
		_action_reset_buttons[action] = reset
	UITheme.confine_focus(panel)


func _on_theme_changed(_mode: String) -> void:
	backdrop.color = Color(UITheme.color("ink"), 0.62 if UITheme.is_dark() else 0.38)
	queue_redraw()


var _icon_anim: float = 0.0


func _process(delta: float) -> void:
	var target := 1.0 if (_icon_hovered or is_menu_open()) else 0.0
	if not is_equal_approx(_icon_anim, target):
		_icon_anim = move_toward(_icon_anim, target, delta * 4.0)
		queue_redraw()


func _draw() -> void:
	var e := ease(_icon_anim, -2.0)
	UIIcon.draw_chrome(self, Rect2(Vector2.ZERO, size), e, has_focus())
	UIIcon.draw(self, "gear", size * 0.5, minf(size.x, size.y) * 0.58, UIIcon.tint(e), e)

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
	if settings_scroll:
		settings_scroll.scroll_vertical = 0
	var vp := get_viewport()
	if vp:
		_last_focus_owner = vp.gui_get_focus_owner()
	canvas_layer.show()
	backdrop.color = Color(UITheme.color("ink"), 0.62 if UITheme.is_dark() else 0.38)
	backdrop.modulate.a = 0.0
	backdrop.create_tween().tween_property(backdrop, "modulate:a", 1.0, 0.2)
	UITheme.pop_in(panel, 0.92)
	_refresh_binding_ui()
	call_deferred("_recenter_panel")
	call_deferred("_focus_menu_default")
	queue_redraw()

## 隐藏设置菜单
func hide_menu() -> void:
	_stop_capture()
	canvas_layer.hide()
	call_deferred("_restore_focus_after_hide")
	queue_redraw()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _capture_active:
		hide_menu()


func is_menu_open() -> bool:
	return canvas_layer != null and canvas_layer.visible


func _focus_menu_default() -> void:
	if not is_menu_open():
		return
	if option_btn and not option_btn.disabled:
		option_btn.grab_focus()
	elif close_btn:
		close_btn.grab_focus()


func _restore_focus_after_hide() -> void:
	if is_menu_open():
		return
	if _last_focus_owner != null and is_instance_valid(_last_focus_owner) and _last_focus_owner.is_inside_tree():
		_last_focus_owner.grab_focus()
	elif is_inside_tree() and focus_mode != Control.FOCUS_NONE:
		grab_focus()


func _on_icon_hover_changed(hover_active: bool) -> void:
	_icon_hovered = hover_active
	queue_redraw()

## 系统通知处理：处理多语言实时切换和窗口大小调整
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()
		_refresh_binding_ui()
	elif what == NOTIFICATION_WM_SIZE_CHANGED and is_inside_tree():
		_recenter_panel()

## 更新界面上的所有本地化文本
func _update_texts() -> void:
	tooltip_text = tr("TXT_SETTINGS")
	if option_btn:
		var locale := TranslationServer.get_locale().to_lower()
		option_btn.select(1 if locale.begins_with("zh") else (2 if locale.begins_with("ja") else 0))
	if title_lbl:
		title_lbl.text = tr("TXT_SETTINGS")
	if lang_lbl:
		lang_lbl.text = tr("TXT_LANGUAGE")
	if theme_lbl:
		theme_lbl.text = tr("TXT_THEME")
	if resolution_lbl:
		var localized_resolution := tr("TXT_RESOLUTION")
		resolution_lbl.text = localized_resolution if localized_resolution != "TXT_RESOLUTION" else "RESOLUTION"
	if fullscreen_lbl:
		var localized_fullscreen := tr("TXT_FULLSCREEN")
		fullscreen_lbl.text = localized_fullscreen if localized_fullscreen != "TXT_FULLSCREEN" else "FULLSCREEN"
	if fullscreen_checkbox:
		fullscreen_checkbox.tooltip_text = tr("TXT_FULLSCREEN")
	if volume_lbl:
		var localized_volume := tr("TXT_MASTER_VOLUME")
		volume_lbl.text = localized_volume if localized_volume != "TXT_MASTER_VOLUME" else "MASTER VOLUME"
	if volume_slider:
		volume_slider.tooltip_text = tr("TXT_MASTER_VOLUME")
	if keybind_title_lbl:
		keybind_title_lbl.text = tr("TXT_KEYBINDINGS")
	if handling_title_lbl:
		handling_title_lbl.text = tr("TXT_HANDLING")
		handling_title_lbl.tooltip_text = tr("TXT_HANDLING_HINT")
	if keybind_hint_lbl and not _capture_active:
		keybind_hint_lbl.text = tr("TXT_BIND_TIP")
	if reset_all_btn:
		reset_all_btn.text = tr("TXT_BIND_RESET_DEFAULT")
	if close_btn:
		close_btn.text = tr("TXT_OK")
	if panel:
		%CloseIcon.tooltip_text = tr("TXT_CLOSE")
		%HandlingReset.tooltip_text = tr("TXT_BIND_RESET_ACTION")

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
	var storage_load_error := config.load(_get_settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return
	config.set_value(SECTION_SETTINGS, "locale", loc)
	var storage_save_error := config.save(_get_settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))

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
		window.mode = Window.MODE_WINDOWED
		_apply_resolution_by_index(_get_selected_resolution_index(ConfigFile.new()))

	_save_fullscreen(enabled)
	_update_resolution_interactability()

func _on_master_volume_changed(value: float) -> void:
	var percent := clampf(value, 0.0, 100.0)
	_apply_master_volume_percent(percent)
	_save_master_volume_percent(percent)
	_update_volume_value_label()

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
	var panel_size := Vector2(
		minf(PANEL_WIDTH, maxf(420.0, viewport_size.x - PANEL_SCREEN_MARGIN)),
		minf(PANEL_MAX_HEIGHT, maxf(420.0, viewport_size.y - PANEL_SCREEN_MARGIN))
	)
	panel.custom_minimum_size = panel_size
	panel.reset_size()
	panel.size = panel_size
	panel.position = (viewport_size - panel_size) * 0.5

func _on_handling_changed(value: float, key: String) -> void:
	Handling.set_value(key, value)
	Handling.save()
	_refresh_handling_labels()


func _on_handling_reset_pressed() -> void:
	for key in Handling.DEFAULTS:
		Handling.set_value(key, Handling.DEFAULTS[key])
		if _handling_sliders.has(key):
			_handling_sliders[key].set_value_no_signal(Handling.DEFAULTS[key])
	Handling.save()
	_refresh_handling_labels()


func _refresh_handling_labels() -> void:
	for key in _handling_values:
		_handling_values[key].text = Handling.format_value(key, Handling.get_value(key))


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
		# Command-line resolution overrides are used by the editor and isolated visual probes.
		if not "--resolution" in OS.get_cmdline_args():
			_apply_resolution_by_index(_get_selected_resolution_index(config))
		if fullscreen_checkbox:
			fullscreen_checkbox.button_pressed = false

	_update_resolution_interactability()

func _apply_saved_audio_settings(config: ConfigFile) -> void:
	_apply_master_volume_percent(_get_saved_master_volume_percent(config))

func _get_saved_master_volume_percent(config: ConfigFile) -> float:
	if config.load(_get_settings_path()) != OK:
		return DEFAULT_MASTER_VOLUME_PERCENT
	return clampf(float(config.get_value(SECTION_AUDIO, "master_volume", DEFAULT_MASTER_VOLUME_PERCENT)), 0.0, 100.0)

func _save_master_volume_percent(percent: float) -> void:
	var config := ConfigFile.new()
	var storage_load_error := config.load(_get_settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return
	config.set_value(SECTION_AUDIO, "master_volume", clampf(percent, 0.0, 100.0))
	var storage_save_error := config.save(_get_settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))

func _apply_master_volume_percent(percent: float) -> void:
	var clamped := clampf(percent, 0.0, 100.0)
	if is_instance_valid(GameState) and GameState.has_method("apply_master_volume_percent"):
		GameState.apply_master_volume_percent(clamped)
		return

	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	AudioServer.set_bus_mute(bus_index, clamped <= 0.0)
	if clamped <= 0.0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	else:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(clamped / 100.0))

func _update_volume_value_label() -> void:
	if volume_value_lbl == null or volume_slider == null:
		return
	volume_value_lbl.text = "%d%%" % int(round(volume_slider.value))

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
	var storage_load_error := config.load(_get_settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return
	var option := RESOLUTION_OPTIONS[idx]
	config.set_value(SECTION_RESOLUTION, "id", str(option.get("id", DEFAULT_RESOLUTION_ID)))
	var storage_save_error := config.save(_get_settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))

## 保存全屏设置
func _save_fullscreen(enabled: bool) -> void:
	var config := ConfigFile.new()
	var storage_load_error := config.load(_get_settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return
	config.set_value(SECTION_DISPLAY, "fullscreen", enabled)
	var storage_save_error := config.save(_get_settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))

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
	var storage_load_error := config.load(_get_settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return

	for action in ACTIONS:
		var serialized_events: Array[String] = []
		for ev in _get_supported_events(action):
			serialized_events.append(var_to_str(ev))
		config.set_value(SECTION_BINDINGS, action, serialized_events)

	var storage_save_error := config.save(_get_settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))

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
			action_lbl.tooltip_text = action_lbl.text
			action_lbl.mouse_filter = Control.MOUSE_FILTER_PASS

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

			slot_btn.tooltip_text = "%s\n%s" % [slot_btn.text, tr("TXT_BIND_SLOT_TIP")]

		# 更新单行重置按钮的文本
		var action_reset_btn: Button = _action_reset_buttons.get(action)
		if action_reset_btn:
			action_reset_btn.tooltip_text = tr("TXT_BIND_RESET_ACTION")

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
	if keybind_hint_lbl:
		keybind_hint_lbl.text = tr("TXT_BIND_TIP")

## 从 InputEvent 中提炼核心按键信息（去除重复触发和无用元数据）
func _extract_binding_event(event: InputEvent) -> InputEvent:
	# 处理键盘连发或松开事件
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if not key_ev.pressed or key_ev.echo:
			return null
		var output_key := InputEventKey.new()
		output_key.physical_keycode = key_ev.physical_keycode
		output_key.keycode = key_ev.keycode if key_ev.physical_keycode == 0 else 0
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
			return OS.get_keycode_string(key_event.get_physical_keycode_with_modifiers())
		return OS.get_keycode_string(key_event.get_keycode_with_modifiers())

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
		return (ka.physical_keycode == kb.physical_keycode if ka.physical_keycode != 0 and kb.physical_keycode != 0 else ka.keycode == kb.keycode and ka.physical_keycode == kb.physical_keycode) and ka.shift_pressed == kb.shift_pressed and ka.ctrl_pressed == kb.ctrl_pressed and ka.alt_pressed == kb.alt_pressed and ka.meta_pressed == kb.meta_pressed

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
				_mark_input_handled()
				return

		# 尝试提炼录入的按键
		var captured := _extract_binding_event(event)
		if captured != null:
			_assign_capture_event(captured)
			_mark_input_handled()
			return

	if event.is_action_pressed("ui_cancel"):
		hide_menu()
		_mark_input_handled()
		return

	# 处理暂停/关闭菜单的快捷键（如果 InputMap 中定义了 pause）
	if not InputMap.has_action("pause"):
		return
	if event.is_action_pressed("pause"):
		hide_menu()
		_mark_input_handled()


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()
