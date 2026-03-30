class_name LoginScreen
extends Control

## UI：极简现代登录界面

signal login_successful(player_name: String)

@onready var line_edit_name: LineEdit = %NameInput
@onready var btn_login: Button = %LoginButton

func _ready() -> void:
	# 强制保证背景节点永远在最底层并且拉伸全图
	var custom_bg = get_node_or_null("CustomBackground")
	if custom_bg:
		move_child(custom_bg, 0)
		custom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		custom_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		custom_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
		
	_update_texts()
	


	# 进入界面的淡入动画，使用原生 Tween 让效果高级点
	modulate.a = 0
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_property(self , "modulate:a", 1.0, 1.0)

	btn_login.pressed.connect(_on_login_pressed)
	line_edit_name.text_submitted.connect(_on_text_submitted)
	
	line_edit_name.grab_focus() # 启动后自动获取焦点

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()

func _update_texts() -> void:
	if btn_login: btn_login.text = tr("TXT_INITIALIZE")
	if line_edit_name: line_edit_name.placeholder_text = tr("TXT_ENTER_NAME")
	var lbl_subtitle = get_node_or_null("CenterContainer/VBoxContainer/SubtitleLabel")
	if lbl_subtitle: lbl_subtitle.text = tr("TXT_CONNECTING")
	var lbl_callsign = get_node_or_null("CenterContainer/VBoxContainer/HBoxContainer/Label")
	if lbl_callsign: lbl_callsign.text = tr("TXT_CALLSIGN")


func _on_login_pressed() -> void:
	_submit_login()

func _on_text_submitted(_new_text: String) -> void:
	_submit_login()

func _submit_login() -> void:
	var pname = line_edit_name.text.strip_edges()
	if pname.is_empty():
		pname = "GUEST_" + str(randi_range(1000, 9999))
	
	# 点击后按钮微缩动画，然后发射完成信号
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(btn_login, "scale", Vector2(0.95, 0.95), 0.1)
	tween.tween_property(btn_login, "scale", Vector2(1.0, 1.0), 0.1)
	
	# 等动画跑完后跳转
	tween.finished.connect(func(): login_successful.emit(pname))
