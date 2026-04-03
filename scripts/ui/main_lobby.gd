class_name MainLobby
extends Control

## 主大厅：模式选择界面
## 目标：
## 1) 保持原有单人/多人入口逻辑
## 2) 给“当前选择的卡片”增加外发光边框
## 3) 同时兼容鼠标悬停与手柄/键盘焦点

signal start_marathon()
signal start_multiplayer()

@onready var lbl_player_name: Label = %PlayerNameLabel
@onready var card_marathon: PanelContainer = %CardMarathon
@onready var card_multiplayer: PanelContainer = %CardMultiplayer

var _current_pname: String = ""

# 卡片视觉参数（统一放常量，后续调风格只改这里）
const CARD_NORMAL_SCALE := Vector2(1.0, 1.0)
const CARD_HOVER_SCALE := Vector2(1.05, 1.05)
const CARD_GLOW_BORDER_WIDTH := 3
const CARD_GLOW_SHADOW_SIZE := 20
const CARD_GLOW_BORDER_COLOR := Color(0.45, 0.87, 1.0, 1.0)
const CARD_GLOW_SHADOW_COLOR := Color(0.35, 0.78, 1.0, 0.45)
const CARD_ACTIVE_MODULATE := Color(1.06, 1.06, 1.10, 1.0)
const CARD_NORMAL_MODULATE := Color(1.0, 1.0, 1.0, 1.0)

# 为每张卡缓存“默认样式”和“发光样式”，避免重复构建对象
var _card_base_styles: Dictionary = {}
var _card_glow_styles: Dictionary = {}


func _ready() -> void:
	# 绑定点击输入
	card_marathon.gui_input.connect(_on_card_input.bind(card_marathon, "marathon"))
	card_multiplayer.gui_input.connect(_on_card_input.bind(card_multiplayer, "multiplayer"))

	# 绑定 hover + focus，统一走同一套高亮刷新逻辑
	card_marathon.mouse_entered.connect(_on_card_hover.bind(card_marathon, true))
	card_marathon.mouse_exited.connect(_on_card_hover.bind(card_marathon, false))
	card_multiplayer.mouse_entered.connect(_on_card_hover.bind(card_multiplayer, true))
	card_multiplayer.mouse_exited.connect(_on_card_hover.bind(card_multiplayer, false))
	card_marathon.focus_entered.connect(_on_card_hover.bind(card_marathon, true))
	card_marathon.focus_exited.connect(_on_card_hover.bind(card_marathon, false))
	card_multiplayer.focus_entered.connect(_on_card_hover.bind(card_multiplayer, true))
	card_multiplayer.focus_exited.connect(_on_card_hover.bind(card_multiplayer, false))

	# 焦点导航配置（手柄/键盘）
	card_marathon.focus_mode = Control.FOCUS_ALL
	card_multiplayer.focus_mode = Control.FOCUS_ALL
	card_marathon.focus_neighbor_right = card_multiplayer.get_path()
	card_multiplayer.focus_neighbor_left = card_marathon.get_path()

	# 缩放动画基准点设为卡片中心
	card_marathon.pivot_offset = card_marathon.size / 2.0
	card_multiplayer.pivot_offset = card_multiplayer.size / 2.0

	# 初始化卡片外发光样式（默认态 + 选中态）
	_init_card_glow_styles()

	# 关键调整：
	# 默认不预选任何卡片，进入大厅时两个模式都不发光。
	# 这样鼠标用户不会看到“系统先替你选中单人”的状态；
	# 手柄/键盘用户在第一次按左右键后才进入明确选中态。
	call_deferred("_clear_initial_card_selection")

	# 背景层固定在底部并全屏裁切显示
	var custom_bg = get_node_or_null("CustomBackground")
	if custom_bg:
		move_child(custom_bg, 0)
		custom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		custom_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		custom_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	_update_texts()
	_refresh_card_visuals()


func set_player_name(pname: String) -> void:
	_current_pname = pname
	_update_texts()


## 清空初始选择态：默认无焦点、无发光，兼容鼠标优先交互。
func _clear_initial_card_selection() -> void:
	if card_marathon:
		card_marathon.release_focus()
		card_marathon.scale = CARD_NORMAL_SCALE
	if card_multiplayer:
		card_multiplayer.release_focus()
		card_multiplayer.scale = CARD_NORMAL_SCALE
	_refresh_card_visuals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()


func _update_texts() -> void:
	var lbl_marathon = get_node_or_null("%CardMarathon/VBoxContainer/Title")
	if lbl_marathon:
		lbl_marathon.text = tr("TXT_MARATHON")

	var lbl_multiplayer = get_node_or_null("%CardMultiplayer/VBoxContainer/Title")
	if lbl_multiplayer:
		lbl_multiplayer.text = tr("TXT_MULTIPLAYER")

	var lbl_m_desc = get_node_or_null("%CardMarathon/VBoxContainer/Desc")
	if lbl_m_desc:
		lbl_m_desc.text = tr("TXT_MARATHON_DESC")

	var lbl_mp_desc = get_node_or_null("%CardMultiplayer/VBoxContainer/Desc")
	if lbl_mp_desc:
		lbl_mp_desc.text = tr("TXT_MULTIPLAYER_DESC")

	if lbl_player_name and not _current_pname.is_empty():
		lbl_player_name.text = "%s, %s" % [tr("TXT_WELCOME"), _current_pname]


## UIManager 切入大厅时调用，做一个淡入
func play_entrance_animation() -> void:
	modulate.a = 0.0
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)


## -----------------------------------------------------------------------------
## 卡片交互与外发光
## -----------------------------------------------------------------------------

func _init_card_glow_styles() -> void:
	# 每张卡都从当前 panel 样式复制出两份：
	# - base: 默认样式
	# - glow: 选中时的高亮外发光样式
	for card in [card_marathon, card_multiplayer]:
		var panel_style: StyleBox = card.get_theme_stylebox("panel")
		if not (panel_style is StyleBoxFlat):
			continue

		var base_style := (panel_style as StyleBoxFlat).duplicate(true) as StyleBoxFlat
		_card_base_styles[card] = base_style

		var glow_style := base_style.duplicate(true) as StyleBoxFlat
		glow_style.border_width_left = maxi(glow_style.border_width_left, CARD_GLOW_BORDER_WIDTH)
		glow_style.border_width_top = maxi(glow_style.border_width_top, CARD_GLOW_BORDER_WIDTH)
		glow_style.border_width_right = maxi(glow_style.border_width_right, CARD_GLOW_BORDER_WIDTH)
		glow_style.border_width_bottom = maxi(glow_style.border_width_bottom, CARD_GLOW_BORDER_WIDTH)
		glow_style.border_color = CARD_GLOW_BORDER_COLOR
		glow_style.shadow_size = maxi(glow_style.shadow_size, CARD_GLOW_SHADOW_SIZE)
		glow_style.shadow_color = CARD_GLOW_SHADOW_COLOR
		_card_glow_styles[card] = glow_style

		# 先落默认样式，后续由 _refresh_card_visuals 控制切换
		card.add_theme_stylebox_override("panel", base_style)


func _on_card_hover(card: Control, _is_hovering: bool) -> void:
	# 不直接信任事件参数，而是实时计算“当前是否选中”，避免鼠标与焦点事件交错导致闪烁。
	_refresh_card_visuals()

	var is_active := _is_card_active(card)
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	card.pivot_offset = card.size / 2.0
	tween.tween_property(
		card,
		"scale",
		CARD_HOVER_SCALE if is_active else CARD_NORMAL_SCALE,
		0.2
	)


func _is_card_active(card: Control) -> bool:
	# “当前选择”定义：
	# - 手柄/键盘：有焦点
	# - 鼠标：当前指针悬停
	return card.has_focus() or card.get_global_rect().has_point(get_global_mouse_position())


func _set_card_glow(card: PanelContainer, active: bool) -> void:
	if active and _card_glow_styles.has(card):
		card.add_theme_stylebox_override("panel", _card_glow_styles[card])
		card.modulate = CARD_ACTIVE_MODULATE
		return

	if _card_base_styles.has(card):
		card.add_theme_stylebox_override("panel", _card_base_styles[card])
	card.modulate = CARD_NORMAL_MODULATE


func _refresh_card_visuals() -> void:
	_set_card_glow(card_marathon, _is_card_active(card_marathon))
	_set_card_glow(card_multiplayer, _is_card_active(card_multiplayer))


func _on_card_input(event: InputEvent, card: Control, mode: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_activate_mode(card, mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		card_marathon.grab_focus()
		_refresh_card_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		card_multiplayer.grab_focus()
		_refresh_card_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if card_marathon.has_focus():
			_activate_mode(card_marathon, "marathon")
			get_viewport().set_input_as_handled()
		elif card_multiplayer.has_focus():
			_activate_mode(card_multiplayer, "multiplayer")
			get_viewport().set_input_as_handled()


func _activate_mode(card: Control, mode: String) -> void:
	# 确认点击反馈（按下回弹）
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", Vector2(0.95, 0.95), 0.1)
	tween.tween_property(card, "scale", CARD_HOVER_SCALE, 0.1)

	tween.finished.connect(func():
		if mode == "marathon":
			start_marathon.emit()
		elif mode == "multiplayer":
			start_multiplayer.emit()
	)
