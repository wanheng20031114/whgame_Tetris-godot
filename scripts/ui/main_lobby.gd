class_name MainLobby
extends Control

## UI：主大厅界面，包含模式选择

signal start_marathon()
signal start_multiplayer()

@onready var lbl_player_name: Label = %PlayerNameLabel
@onready var card_marathon: PanelContainer = %CardMarathon
@onready var card_multiplayer: PanelContainer = %CardMultiplayer

# 存储卡片的原始尺寸或状态以便做 hover 动画
var hovered_card: Control = null

func _ready() -> void:
	# 绑定点击事件 (GUI 输入)
	card_marathon.gui_input.connect(_on_card_input.bind(card_marathon, "marathon"))
	card_multiplayer.gui_input.connect(_on_card_input.bind(card_multiplayer, "multiplayer"))
	
	# 绑定 hover 事件
	card_marathon.mouse_entered.connect(_on_card_hover.bind(card_marathon, true))
	card_marathon.mouse_exited.connect(_on_card_hover.bind(card_marathon, false))
	card_multiplayer.mouse_entered.connect(_on_card_hover.bind(card_multiplayer, true))
	card_multiplayer.mouse_exited.connect(_on_card_hover.bind(card_multiplayer, false))

	# 确保透视点位于中心以实现缩放动画
	card_marathon.pivot_offset = card_marathon.size / 2.0
	card_multiplayer.pivot_offset = card_multiplayer.size / 2.0
			
	# 强制保证背景节点永远在最底层并且拉伸全图
	var custom_bg = get_node_or_null("CustomBackground")
	if custom_bg:
		move_child(custom_bg, 0)
		custom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		custom_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		custom_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
	_update_texts()
	


var _current_pname: String = ""

func set_player_name(pname: String) -> void:
	_current_pname = pname
	_update_texts()

## 动态响应语言更新
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()

func _update_texts() -> void:
	var lbl_marathon = get_node_or_null("%CardMarathon/VBoxContainer/Title")
	if lbl_marathon: lbl_marathon.text = tr("TXT_MARATHON")
	var lbl_multiplayer = get_node_or_null("%CardMultiplayer/VBoxContainer/Title")
	if lbl_multiplayer: lbl_multiplayer.text = tr("TXT_MULTIPLAYER")

	var lbl_m_desc = get_node_or_null("%CardMarathon/VBoxContainer/Desc")
	if lbl_m_desc: lbl_m_desc.text = tr("TXT_MARATHON_DESC")
	var lbl_mp_desc = get_node_or_null("%CardMultiplayer/VBoxContainer/Desc")
	if lbl_mp_desc: lbl_mp_desc.text = tr("TXT_MULTIPLAYER_DESC")
	
	if lbl_player_name and not _current_pname.is_empty():
		lbl_player_name.text = "%s, %s" % [tr("TXT_WELCOME"), _current_pname]


## 当 UIManager 切换到主大厅时调用，做一个进场动画
func play_entrance_animation() -> void:
	modulate.a = 0.0
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_property(self , "modulate:a", 1.0, 0.8)

## ---------------------------------------------------------
## 卡片交互逻辑
## ---------------------------------------------------------

func _on_card_hover(card: Control, is_hovering: bool) -> void:
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if is_hovering:
		card.pivot_offset = card.size / 2.0
		tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.2)
		# 可以在这里根据需要修改 StyleBox 的边框颜色等
	else:
		tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.2)

func _on_card_input(event: InputEvent, card: Control, mode: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点击特效
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "scale", Vector2(0.95, 0.95), 0.1)
		tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1)
		
		# 判断模式
		tween.finished.connect(func():
			if mode == "marathon":
				start_marathon.emit()
			elif mode == "multiplayer":
				print("[MainLobby] Multiplayer mode not yet implemented.")
				# start_multiplayer.emit()
		)
