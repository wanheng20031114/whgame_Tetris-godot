extends Control

@onready var lbl_title: Label = %TitleLabel
@onready var lbl_ip: Label = %IPLabel
@onready var lbl_port: Label = %PortLabel
@onready var lbl_name: Label = %NameLabel
@onready var edit_ip: LineEdit = %IPEdit
@onready var edit_port: LineEdit = %PortEdit
@onready var edit_name: LineEdit = %NameEdit
@onready var btn_connect: Button = %ConnectButton
@onready var btn_back: Button = %BackButton
@onready var lbl_status: Label = %StatusLabel

const CONNECT_TIMEOUT_SECONDS := 10.0
const STATUS_COLOR_NORMAL := Color(0.7, 0.7, 1.0, 1.0)
const STATUS_COLOR_ERROR := Color(1.0, 0.35, 0.35, 1.0)

var _status_key: String = "TXT_READY"
var _status_args: Array = []
var _connect_attempt_id := 0
var _is_connecting := false

func _ready() -> void:
	edit_ip.text = "127.0.0.1"
	edit_port.text = "8998"

	if get_node_or_null("/root/GameState"):
		edit_name.text = get_node("/root/GameState").player_name

	btn_connect.pressed.connect(_on_connect_pressed)
	btn_back.pressed.connect(_on_back_pressed)

	NetworkManager.connected.connect(_on_network_connected)
	NetworkManager.disconnected.connect(_on_network_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.login_success.connect(_on_login_success)

	_update_texts()
	_set_status_key("TXT_READY")
	call_deferred("_focus_default_control")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()
		_set_status_key(_status_key, _status_args)

func _focus_default_control() -> void:
	if edit_name:
		edit_name.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		_on_back_pressed()

func _trf(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args

func _set_status_key(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	if lbl_status:
		lbl_status.add_theme_color_override("font_color", STATUS_COLOR_NORMAL)
		lbl_status.text = _trf(_status_key, _status_args)

func _set_error_status(message: String) -> void:
	if lbl_status:
		lbl_status.add_theme_color_override("font_color", STATUS_COLOR_ERROR)
		lbl_status.text = message

func _update_texts() -> void:
	if lbl_title:
		lbl_title.text = tr("TXT_MP_SETUP_TITLE")
	if lbl_ip:
		lbl_ip.text = tr("TXT_SERVER_ADDRESS")
	if lbl_port:
		lbl_port.text = tr("TXT_SERVER_PORT")
	if lbl_name:
		lbl_name.text = tr("TXT_LOGIN_NAME")
	if edit_ip:
		edit_ip.placeholder_text = tr("TXT_IP_PLACEHOLDER")
	if edit_port:
		edit_port.placeholder_text = tr("TXT_PORT_PLACEHOLDER")
	if edit_name:
		edit_name.placeholder_text = tr("TXT_NAME_PLACEHOLDER")
	if btn_connect:
		btn_connect.text = tr("TXT_CONNECT_SERVER")
	if btn_back:
		btn_back.text = tr("TXT_BACK_MAIN")

func _on_connect_pressed() -> void:
	if ButtonSfx:
		ButtonSfx.play_click()

	var ip := edit_ip.text.strip_edges()
	var port := edit_port.text.to_int()
	var pname := edit_name.text.strip_edges()

	if pname.is_empty():
		_set_status_key("TXT_ENTER_USERNAME")
		return

	_set_status_key("TXT_CONNECTING_SERVER")
	btn_connect.disabled = true
	_is_connecting = true
	_connect_attempt_id += 1

	var err := NetworkManager.connect_to_server(ip, port)
	if err != OK:
		_is_connecting = false
		btn_connect.disabled = false
		var reason := NetworkManager.get_last_connect_error()
		if reason.strip_edges().is_empty():
			reason = "connect_to_url failed"
		_set_error_status("连接失败（%s）" % reason)
		return

	_start_connect_timeout(_connect_attempt_id)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")

func _on_network_connected() -> void:
	_is_connecting = false
	_set_status_key("TXT_CONNECTED_LOGGING_IN")
	NetworkManager.login(edit_name.text.strip_edges())

func _on_network_disconnected() -> void:
	if _is_connecting:
		return
	_set_status_key("TXT_DISCONNECTED")
	btn_connect.disabled = false

func _on_connection_failed(reason: String) -> void:
	_is_connecting = false
	btn_connect.disabled = false
	var fail_reason := reason.strip_edges()
	if fail_reason.is_empty():
		fail_reason = "unknown error"
	_set_error_status("连接失败（%s）" % fail_reason)

func _on_login_success(_id: String) -> void:
	_is_connecting = false
	_set_status_key("TXT_LOGIN_SUCCESS_ENTER_LOBBY")
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")

func _start_connect_timeout(attempt_id: int) -> void:
	await get_tree().create_timer(CONNECT_TIMEOUT_SECONDS).timeout
	if attempt_id != _connect_attempt_id:
		return
	if not _is_connecting:
		return

	_is_connecting = false
	btn_connect.disabled = false

	var reason := NetworkManager.get_last_connect_error()
	if reason.strip_edges().is_empty():
		reason = "no response within %ds" % int(CONNECT_TIMEOUT_SECONDS)
	_set_error_status("连接超时（%s）" % reason)
