class_name LoginScreen
extends Control

## UI：极简现代登录界面

const BG_SWING_TOP_Y: float = -500.0
const BG_SWING_BOTTOM_Y: float = 0.0
const BG_SWING_TRAVEL_SECONDS: float = 28.5
const BG_SWING_PAUSE_SECONDS: float = 1.5

signal login_successful(player_name: String)

@onready var line_edit_name: LineEdit = %NameInput
@onready var btn_login: Button = %LoginButton
@onready var custom_bg: TextureRect = get_node_or_null("CustomBackground")

var _bg_tween: Tween

func _ready() -> void:
	# 背景保持场景文件中的静态布局，不在运行时改锚点/拉伸参数。
	_update_texts()
	_start_bg_swing_loop()

	# 进入界面的淡入动画，使用原生 Tween 让效果高级点
	modulate.a = 0
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_property(self , "modulate:a", 1.0, 1.0)

	btn_login.pressed.connect(_on_login_pressed)
	line_edit_name.text_submitted.connect(_on_text_submitted)
	
	line_edit_name.grab_focus() # 启动后自动获取焦点

func _exit_tree() -> void:
	if _bg_tween and _bg_tween.is_running():
		_bg_tween.kill()

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

func _start_bg_swing_loop() -> void:
	if custom_bg == null:
		return

	custom_bg.position.y = BG_SWING_BOTTOM_Y

	if _bg_tween and _bg_tween.is_running():
		_bg_tween.kill()

	_bg_tween = create_tween()
	_bg_tween.set_loops()
	_bg_tween.tween_interval(BG_SWING_PAUSE_SECONDS)
	_bg_tween.tween_property(custom_bg, "position:y", BG_SWING_TOP_Y, BG_SWING_TRAVEL_SECONDS).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	_bg_tween.tween_interval(BG_SWING_PAUSE_SECONDS)
	_bg_tween.tween_property(custom_bg, "position:y", BG_SWING_BOTTOM_Y, BG_SWING_TRAVEL_SECONDS).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
