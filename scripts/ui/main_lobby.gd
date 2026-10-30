class_name MainLobby
extends Control

## 主大厅：模式选择界面
## 目标：
## 1) 保持原有单人/多人入口逻辑
## 2) 给“当前选择的卡片”增加外发光边框
## 3) 同时兼容鼠标悬停与手柄/键盘焦点

signal start_marathon()
signal open_guide()
signal start_multiplayer()
signal open_player_stats()
signal open_replay()

@onready var lbl_player_name: Label = %PlayerNameLabel
@onready var card_marathon: PanelContainer = %CardMarathon
@onready var card_guide: PanelContainer = %CardGuide
@onready var card_multiplayer: PanelContainer = %CardMultiplayer
@onready var btn_stats: Button = %BtnStats
@onready var card_replay: PanelContainer = %CardReplay
@onready var btn_settings: TextureButton = %BtnSettings
@onready var btn_block_style: TextureButton = %BtnBlockStyle

var _current_pname: String = ""

# 卡片视觉参数（统一放常量，后续调风格只改这里）
const CARD_NORMAL_SCALE := Vector2(1.0, 1.0)
const CARD_HOVER_SCALE := Vector2(1.03, 1.03)
const CARD_STYLE := &"CardPanel"
const CARD_STYLE_ACTIVE := &"CardPanelActive"

var _cards: Array[PanelContainer] = []
var _activating := false


func _ready() -> void:
	if lbl_player_name:
		lbl_player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_player_name.custom_minimum_size.x = 64

	# 绑定点击输入
	card_marathon.gui_input.connect(_on_card_input.bind(card_marathon, "marathon"))
	card_guide.gui_input.connect(_on_card_input.bind(card_guide, "guide"))
	card_multiplayer.gui_input.connect(_on_card_input.bind(card_multiplayer, "multiplayer"))
	card_replay.gui_input.connect(_on_card_input.bind(card_replay, "replay"))

	# 绑定 hover + focus，统一走同一套高亮刷新逻辑
	card_marathon.mouse_entered.connect(_on_card_hover.bind(card_marathon, true))
	card_marathon.mouse_exited.connect(_on_card_hover.bind(card_marathon, false))
	card_guide.mouse_entered.connect(_on_card_hover.bind(card_guide, true))
	card_guide.mouse_exited.connect(_on_card_hover.bind(card_guide, false))
	card_multiplayer.mouse_entered.connect(_on_card_hover.bind(card_multiplayer, true))
	card_multiplayer.mouse_exited.connect(_on_card_hover.bind(card_multiplayer, false))
	card_replay.mouse_entered.connect(_on_card_hover.bind(card_replay, true))
	card_replay.mouse_exited.connect(_on_card_hover.bind(card_replay, false))
	card_marathon.focus_entered.connect(_on_card_hover.bind(card_marathon, true))
	card_marathon.focus_exited.connect(_on_card_hover.bind(card_marathon, false))
	card_guide.focus_entered.connect(_on_card_hover.bind(card_guide, true))
	card_guide.focus_exited.connect(_on_card_hover.bind(card_guide, false))
	card_multiplayer.focus_entered.connect(_on_card_hover.bind(card_multiplayer, true))
	card_multiplayer.focus_exited.connect(_on_card_hover.bind(card_multiplayer, false))
	card_replay.focus_entered.connect(_on_card_hover.bind(card_replay, true))
	card_replay.focus_exited.connect(_on_card_hover.bind(card_replay, false))

	# 焦点导航配置（手柄/键盘）
	_cards = [card_marathon, card_guide, card_multiplayer, card_replay]
	card_marathon.focus_mode = Control.FOCUS_ALL
	card_guide.focus_mode = Control.FOCUS_ALL
	card_multiplayer.focus_mode = Control.FOCUS_ALL
	card_replay.focus_mode = Control.FOCUS_ALL
	# 与场景中的 2×2 网格一致；方向键由 Godot 的原生焦点系统处理。
	card_marathon.focus_neighbor_right = card_guide.get_path()
	card_marathon.focus_neighbor_bottom = card_multiplayer.get_path()
	card_marathon.focus_neighbor_top = btn_stats.get_path()
	card_marathon.focus_neighbor_left = card_marathon.get_path()
	card_guide.focus_neighbor_left = card_marathon.get_path()
	card_guide.focus_neighbor_bottom = card_replay.get_path()
	card_guide.focus_neighbor_top = btn_settings.get_path()
	card_guide.focus_neighbor_right = card_guide.get_path()
	card_multiplayer.focus_neighbor_top = card_marathon.get_path()
	card_multiplayer.focus_neighbor_right = card_replay.get_path()
	card_multiplayer.focus_neighbor_left = card_multiplayer.get_path()
	card_multiplayer.focus_neighbor_bottom = card_multiplayer.get_path()
	card_replay.focus_neighbor_top = card_guide.get_path()
	card_replay.focus_neighbor_left = card_multiplayer.get_path()
	card_replay.focus_neighbor_right = card_replay.get_path()
	card_replay.focus_neighbor_bottom = card_replay.get_path()
	btn_stats.focus_neighbor_bottom = card_marathon.get_path()
	btn_stats.focus_neighbor_right = btn_block_style.get_path()
	btn_block_style.focus_neighbor_left = btn_stats.get_path()
	btn_block_style.focus_neighbor_right = btn_settings.get_path()
	btn_block_style.focus_neighbor_bottom = card_guide.get_path()
	btn_settings.focus_neighbor_left = btn_block_style.get_path()
	btn_settings.focus_neighbor_bottom = card_guide.get_path()

	# 缩放动画基准点设为卡片中心
	for card in _cards:
		card.pivot_offset_ratio = Vector2(0.5, 0.5)

	# 关键调整：
	# 默认不预选任何卡片，进入大厅时两个模式都不发光。
	# 这样鼠标用户不会看到“系统先替你选中单人”的状态；
	# 手柄/键盘用户在第一次按左右键后才进入明确选中态。
	call_deferred("_clear_initial_card_selection")

	# 背景保持场景文件中的静态布局，不在运行时改锚点/拉伸参数。

	# 数据按钮交互
	if btn_stats:
		btn_stats.pressed.connect(_on_stats_pressed)

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
	if card_guide:
		card_guide.release_focus()
		card_guide.scale = CARD_NORMAL_SCALE
	if card_multiplayer:
		card_multiplayer.release_focus()
		card_multiplayer.scale = CARD_NORMAL_SCALE
	if card_replay:
		card_replay.release_focus()
		card_replay.scale = CARD_NORMAL_SCALE
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

	var lbl_guide = get_node_or_null("%CardGuide/VBoxContainer/Title")
	if lbl_guide:
		lbl_guide.text = tr("TXT_LOBBY_GUIDE_TITLE")




	var lbl_replay = get_node_or_null("%CardReplay/VBoxContainer/Title")
	if lbl_replay:
		lbl_replay.text = tr("TXT_REPLAY")


	if lbl_player_name and not _current_pname.is_empty():
		lbl_player_name.text = _current_pname

	# 右上角数据按钮的tooltip跟随语言切换
	if btn_stats:
		btn_stats.tooltip_text = tr("TXT_PLAYER_STATS")


## UIManager 切入大厅时调用，做一个淡入
func play_entrance_animation() -> void:
	UITheme.stagger_in(self, 0.06)


## -----------------------------------------------------------------------------
## 卡片交互与外发光
## -----------------------------------------------------------------------------

func _on_card_hover(card: Control, _is_hovering: bool) -> void:
	# 不直接信任事件参数，而是实时计算“当前是否选中”，避免鼠标与焦点事件交错导致闪烁。
	if _activating:
		return
	_refresh_card_visuals()

	var is_active := _is_card_active(card)
	var tween = UITheme.motion_tween(card).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
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
	if card is ModeCard:
		(card as ModeCard).active = active
	else:
		card.theme_type_variation = CARD_STYLE_ACTIVE if active else CARD_STYLE
	var glyph := card.get_node("VBoxContainer/Glyph") as ModeGlyph
	glyph.active = active


func _refresh_card_visuals() -> void:
	_set_card_glow(card_marathon, _is_card_active(card_marathon))
	_set_card_glow(card_guide, _is_card_active(card_guide))
	_set_card_glow(card_multiplayer, _is_card_active(card_multiplayer))
	_set_card_glow(card_replay, _is_card_active(card_replay))


func _on_card_input(event: InputEvent, card: Control, mode: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_activate_mode(card, mode)


func _unhandled_input(event: InputEvent) -> void:
	if _is_settings_menu_open():
		return
	if event.is_action_pressed("ui_accept"):
		var focused_card := _get_focused_card()
		var focused_mode := _get_focused_card_mode(focused_card)
		if focused_card != null and not focused_mode.is_empty():
			_activate_mode(focused_card, focused_mode)
			get_viewport().set_input_as_handled()
	elif get_viewport().gui_get_focus_owner() == null and (
		event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")
	):
		card_marathon.grab_focus()
		get_viewport().set_input_as_handled()


func _is_settings_menu_open() -> bool:
	var settings_open := btn_settings != null and btn_settings.has_method("is_menu_open") and bool(btn_settings.call("is_menu_open"))
	var style_open := btn_block_style != null and btn_block_style.has_method("is_menu_open") and bool(btn_block_style.call("is_menu_open"))
	return settings_open or style_open


func _get_focused_card_index() -> int:
	for i in range(_cards.size()):
		if _cards[i].has_focus():
			return i
	return -1


func _get_focused_card() -> PanelContainer:
	var focused_index := _get_focused_card_index()
	if focused_index < 0:
		return null
	return _cards[focused_index]


func _get_focused_card_mode(card: Control) -> String:
	if card == card_marathon:
		return "marathon"
	if card == card_guide:
		return "guide"
	if card == card_multiplayer:
		return "multiplayer"
	if card == card_replay:
		return "replay"
	return ""


func _activate_mode(card: Control, mode: String) -> void:
	if _activating:
		return
	_activating = true
	if ButtonSfx:
		ButtonSfx.play_click()

	# 确认点击反馈（按下回弹）
	var tween = UITheme.motion_tween(card).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", Vector2(0.95, 0.95), 0.1)
	tween.tween_property(card, "scale", CARD_HOVER_SCALE, 0.1)

	tween.finished.connect(func():
		if mode == "marathon":
			start_marathon.emit()
		elif mode == "guide":
			open_guide.emit()
		elif mode == "multiplayer":
			start_multiplayer.emit()
		elif mode == "replay":
			open_replay.emit()
	)


## 数据按钮点击回调：发出 open_player_stats 信号。
func _on_stats_pressed() -> void:
	if not _activating:
		_activating = true
		open_player_stats.emit()
