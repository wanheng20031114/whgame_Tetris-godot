class_name LoginScreen
extends Control

## UI：极简现代登录界面

const MAX_PLAYER_NAME_LENGTH := 12

signal login_successful(player_name: String)

@onready var line_edit_name: LineEdit = %NameInput
@onready var btn_login: Button = %LoginButton
@onready var card: Control = $CenterContainer/Card
var _submitting := false

func _ready() -> void:
	_update_texts()
	UITheme.pop_in(card)

	btn_login.pressed.connect(_on_login_pressed)
	line_edit_name.text_submitted.connect(_on_text_submitted)
	line_edit_name.max_length = MAX_PLAYER_NAME_LENGTH
	
	line_edit_name.grab_focus() # 启动后自动获取焦点

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()

func _update_texts() -> void:
	if btn_login: btn_login.text = tr("TXT_INITIALIZE")
	if line_edit_name: line_edit_name.placeholder_text = tr("TXT_ENTER_NAME")


func _on_login_pressed() -> void:
	_submit_login()

func _on_text_submitted(_new_text: String) -> void:
	_submit_login()

func _submit_login() -> void:
	if _submitting:
		return
	_submitting = true
	btn_login.disabled = true
	line_edit_name.editable = false
	var pname = line_edit_name.text.strip_edges().substr(0, MAX_PLAYER_NAME_LENGTH)
	if pname.is_empty():
		pname = "GUEST_" + str(randi_range(1000, 9999))
	
	# 卡片收缩淡出后再切到大厅
	var tween = UITheme.motion_tween(card).set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", Vector2(0.92, 0.92), 0.22)
	tween.tween_property(card, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(func(): login_successful.emit(pname))
