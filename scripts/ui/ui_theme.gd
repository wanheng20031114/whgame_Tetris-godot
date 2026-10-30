extends Node

## 全局 UI 主题与动效（AutoLoad: UITheme）
## - 深色 / 浅色主题切换：把对应 Theme 合并进项目主题，所有 Control（包括 CanvasLayer 下的）即时生效
## - 主题色同步到全局着色器参数（ui_bg / ui_surface / ui_accent / ui_border），供动态背景使用
## - 统一按钮悬停/按压弹性动效、场景切换淡入淡出与入场错峰动画

signal theme_changed(mode: String)

const SECTION_DISPLAY := "Display"
const KEY_THEME := "ui_theme"

const THEME_RESOURCES := {
	"dark": preload("res://assets/ui/theme_dark.tres"),
	"light": preload("res://assets/ui/theme_light.tres"),
}

## 调色板由 tools/gen_ui_theme.py 生成
const PALETTES: Dictionary = preload("res://scripts/ui/ui_palette.gd").PALETTES
## 同步到全局着色器参数的颜色键（ui_<key>）
const SHADER_KEYS: Array[String] = ["bg", "surface", "accent", "border", "accent2", "cyan", "amber", "pink", "violet", "ink"]

const HOVER_SCALE := Vector2(1.045, 1.045)
const PRESS_SCALE := Vector2(0.94, 0.94)
const META_NO_MOTION := &"ui_no_motion"
const META_MOTION_TWEEN := &"_ui_motion_tween"
const STAGGER_LIMIT := 28
const GROUP_ICON_TINT := &"ui_icon_tint"

@onready var _fade: ColorRect = $Overlay/Fade
@onready var _reveal: TextureRect = $Overlay/Reveal

var mode: String = "dark"
var _theme_sources: Dictionary = {}
var _reveal_tween: Tween
var _fade_tween: Tween
var _changing_scene: bool = false
var _modal_focus_panels: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 项目主题实例与 theme_dark.tres 共享缓存，先复制一份干净的源，避免合并时被改写
	for key in THEME_RESOURCES:
		_theme_sources[key] = (THEME_RESOURCES[key] as Theme).duplicate()
	mode = _load_mode()
	_apply_theme()
	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	tree.scene_changed.connect(_on_scene_changed)
	tree.root.gui_focus_changed.connect(_on_modal_focus_changed)
	_register_existing(tree.root)


# --- 主题 ------------------------------------------------------------------

func color(key: String) -> Color:
	return PALETTES[mode][key]


## 在表面色上叠一层语义色，得到柔和底色（徽章、高亮行、提示条）
func soft(key: String, amount: float = 0.15) -> Color:
	return color("surface").lerp(color(key), amount)


func is_dark() -> bool:
	return mode == "dark"


func toggle_mode(origin_global: Vector2 = Vector2(-1, -1)) -> void:
	set_mode("light" if is_dark() else "dark", origin_global)


## 切换主题：截取旧画面，以 origin 为圆心向外溶解露出新主题
func set_mode(new_mode: String, origin_global: Vector2 = Vector2(-1, -1), persist: bool = true) -> void:
	if new_mode == mode or not PALETTES.has(new_mode):
		return
	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size
	var snapshot: Image = null if DisplayServer.get_name() == "headless" else vp.get_texture().get_image()
	if snapshot == null or snapshot.is_empty():
		# 无可用画面（如无头模式）时直接切换
		mode = new_mode
		_apply_theme()
		if persist:
			_save_mode()
		return
	_reveal.texture = ImageTexture.create_from_image(snapshot)
	var mat := _reveal.material as ShaderMaterial
	var origin := origin_global if origin_global.x >= 0.0 else vp_size * 0.5
	mat.set_shader_parameter("origin", origin / vp_size)
	mat.set_shader_parameter("aspect", vp_size.x / maxf(vp_size.y, 1.0))
	mat.set_shader_parameter("progress", 0.0)
	_reveal.show()

	mode = new_mode
	_apply_theme()
	if persist:
		_save_mode()

	if _reveal_tween:
		_reveal_tween.kill()
	_reveal_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_reveal_tween.tween_property(mat, "shader_parameter/progress", 1.0, 0.65)
	_reveal_tween.tween_callback(func():
		_reveal.hide()
		_reveal.texture = null
	)


func _apply_theme() -> void:
	ThemeDB.get_project_theme().merge_with(_theme_sources[mode])
	var p: Dictionary = PALETTES[mode]
	for key in SHADER_KEYS:
		RenderingServer.global_shader_parameter_set("ui_" + key, p[key])
	RenderingServer.global_shader_parameter_set("ui_dark", 1.0 if is_dark() else 0.0)
	RenderingServer.set_default_clear_color(p["bg"])
	for n in get_tree().get_nodes_in_group(GROUP_ICON_TINT):
		(n as CanvasItem).self_modulate = p["text"]
	theme_changed.emit(mode)


func _settings_path() -> String:
	if OS.has_feature("editor"):
		return "res://settings.cfg"
	return OS.get_executable_path().get_base_dir().path_join("settings.cfg")


func _load_mode() -> String:
	var config := ConfigFile.new()
	if config.load(_settings_path()) != OK:
		return "dark"
	var saved := str(config.get_value(SECTION_DISPLAY, KEY_THEME, "dark"))
	return saved if PALETTES.has(saved) else "dark"


func _save_mode() -> void:
	var config := ConfigFile.new()
	var storage_load_error := config.load(_settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return
	config.set_value(SECTION_DISPLAY, KEY_THEME, mode)
	var storage_save_error := config.save(_settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))


# --- 场景切换 ----------------------------------------------------------------

## 带遮罩过渡的场景切换，替代 get_tree().change_scene_to_file
func goto_scene(path: String) -> void:
	if _changing_scene:
		return
	_changing_scene = true
	_fade.color = Color(color("bg"), 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(_fade, "color:a", 1.0, 0.18)
	_fade_tween.tween_callback(func():
		_changing_scene = false
		var scene_error := get_tree().change_scene_to_file(path)
		if scene_error != OK:
			_fade.color.a = 0.0
			_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			push_error("Scene change failed: %s (%s)" % [path, error_string(scene_error)])
	)


func _on_scene_changed() -> void:
	_fade.color = Color(color("bg"), _fade.color.a)
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(_fade, "color:a", 0.0, 0.32)
	_fade_tween.tween_callback(func(): _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	var scene := get_tree().current_scene
	if scene is Control:
		stagger_in(scene)


# --- 动效工具 ----------------------------------------------------------------

## 让 root 下可见的按钮与卡片面板按树顺序错峰浮现
func stagger_in(root: Node, step: float = 0.035) -> void:
	var targets: Array[Control] = []
	_collect_stagger_targets(root, targets)
	var i := 0
	for c in targets:
		var tw := motion_tween(c).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		c.pivot_offset_ratio = Vector2(0.5, 0.5)
		c.modulate.a = 0.0
		c.scale = Vector2(0.94, 0.94)
		tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(i * step)
		tw.tween_property(c, "scale", Vector2.ONE, 0.42).set_delay(i * step)
		i += 1


func _collect_stagger_targets(node: Node, out: Array[Control]) -> void:
	if out.size() >= STAGGER_LIMIT:
		return
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Control and not node.has_meta(META_NO_MOTION) \
			and (node is BaseButton or node.get_class() == "PanelContainer"):
		out.append(node as Control)
		return
	for child in node.get_children():
		_collect_stagger_targets(child, out)


## 弹出式出现（面板、对话框）
func pop_in(c: Control, from_scale: float = 0.9) -> void:
	var tw := motion_tween(c).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	c.scale = Vector2(from_scale, from_scale)
	c.modulate.a = 0.0
	tw.tween_property(c, "scale", Vector2.ONE, 0.38)
	tw.tween_property(c, "modulate:a", 1.0, 0.2)


## 弹性脉冲（数值变化、确认反馈）
func pulse(c: CanvasItem, amount: float = 1.12) -> void:
	if c is Control:
		(c as Control).pivot_offset_ratio = Vector2(0.5, 0.5)
	var tw := motion_tween(c).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(amount, amount), 0.08)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3)


# --- 按钮动效 ----------------------------------------------------------------

## 同一控件的入场、悬停、按压与退出共享一条动效，避免同时写 scale 造成跳动。
func motion_tween(c: CanvasItem) -> Tween:
	var previous: Tween = c.get_meta(META_MOTION_TWEEN) if c.has_meta(META_MOTION_TWEEN) else null
	if previous != null and previous.is_valid():
		previous.kill()
	c.modulate.a = 1.0
	var tween := c.create_tween()
	c.set_meta(META_MOTION_TWEEN, tween)
	return tween


## 弹层内的 Tab/Shift+Tab 使用原生循环焦点；方向导航也不能进入遮罩下的界面。
func confine_focus(root_control: Control) -> void:
	var controls: Array[Control] = []
	_collect_focus_controls(root_control, controls)
	for i in controls.size():
		controls[i].focus_next = controls[(i + 1) % controls.size()].get_path()
		controls[i].focus_previous = controls[posmod(i - 1, controls.size())].get_path()
	_modal_focus_panels.append(root_control)
	root_control.tree_exiting.connect(func(): _modal_focus_panels.erase(root_control), CONNECT_ONE_SHOT)


func _on_modal_focus_changed(focused: Control) -> void:
	for panel in _modal_focus_panels:
		if panel.is_visible_in_tree():
			_keep_modal_focus(focused, panel)
			return


func _keep_modal_focus(focused: Control, panel: Control) -> void:
	if not panel.is_visible_in_tree() or focused == panel or panel.is_ancestor_of(focused):
		return
	var controls: Array[Control] = []
	_collect_focus_controls(panel, controls)
	for control in controls:
		if control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
			control.grab_focus()
			return


func _collect_focus_controls(node: Node, controls: Array[Control]) -> void:
	if node is Control and node.focus_mode == Control.FOCUS_ALL:
		controls.append(node)
	for child in node.get_children():
		_collect_focus_controls(child, controls)

func _register_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_register_existing(child)


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton) or node.has_meta(META_NO_MOTION):
		return
	var b := node as BaseButton
	if b.mouse_entered.is_connected(_on_button_hover.bind(b, true)):
		return
	# 单色图标按钮跟随主题文字色
	if b is TextureButton:
		b.add_to_group(GROUP_ICON_TINT)
		b.self_modulate = color("text")
	b.pivot_offset_ratio = Vector2(0.5, 0.5)
	b.mouse_entered.connect(_on_button_hover.bind(b, true))
	b.mouse_exited.connect(_on_button_hover.bind(b, false))
	b.focus_entered.connect(_on_button_hover.bind(b, true))
	b.focus_exited.connect(_on_button_hover.bind(b, false))
	b.button_down.connect(_on_button_press.bind(b, true))
	b.button_up.connect(_on_button_press.bind(b, false))


func _scale_to(b: Control, target: Vector2, duration: float) -> void:
	var tw := motion_tween(b).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", target, duration)


func _is_hot(b: BaseButton) -> bool:
	return b.has_focus() or b.is_hovered()


func _on_button_hover(b: BaseButton, _entered: bool) -> void:
	if b.disabled or b.has_meta(META_NO_MOTION):
		return
	_scale_to(b, HOVER_SCALE if _is_hot(b) else Vector2.ONE, 0.22)


func _on_button_press(b: BaseButton, down: bool) -> void:
	if b.disabled or b.has_meta(META_NO_MOTION):
		return
	if down:
		_scale_to(b, PRESS_SCALE, 0.08)
	else:
		_scale_to(b, HOVER_SCALE if _is_hot(b) else Vector2.ONE, 0.3)
