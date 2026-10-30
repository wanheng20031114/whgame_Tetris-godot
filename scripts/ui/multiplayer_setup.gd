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
@onready var btn_settings: TextureButton = %BtnSettings
@onready var lbl_status: Label = %StatusLabel

const CONNECT_TIMEOUT_SECONDS := 10.0
const MAX_PLAYER_NAME_LENGTH := 12

var _status_key: String = "TXT_READY"
var _status_args: Array = []
var _connect_attempt_id := 0
var _is_connecting := false
var _leaving := false
var _status_is_error := false
var _pending_name := ""

func _ready() -> void:
	edit_ip.text = "127.0.0.1"
	edit_port.text = "8998"

	if get_node_or_null("/root/GameState"):
		edit_name.text = str(get_node("/root/GameState").player_name).strip_edges().substr(0, MAX_PLAYER_NAME_LENGTH)
	if edit_name:
		edit_name.max_length = MAX_PLAYER_NAME_LENGTH

	btn_connect.pressed.connect(_on_connect_pressed)
	btn_back.pressed.connect(_on_back_pressed)

	NetworkManager.connected.connect(_on_network_connected)
	NetworkManager.disconnected.connect(_on_network_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.login_success.connect(_on_login_success)
	UITheme.theme_changed.connect(func(_mode): _refresh_status())

	_update_texts()
	_set_status_key("TXT_READY")
	call_deferred("_focus_default_control")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()
		_refresh_status()

func _focus_default_control() -> void:
	if edit_name:
		edit_name.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _is_settings_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_mark_input_handled()
		_on_back_pressed()


func _is_settings_menu_open() -> bool:
	return btn_settings != null and btn_settings.has_method("is_menu_open") and bool(btn_settings.call("is_menu_open"))


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()

func _trf(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args

func _set_status_key(key: String, args: Array = [], is_error: bool = false) -> void:
	_status_key = key
	_status_args = args
	_status_is_error = is_error
	_refresh_status()
	if is_error:
		UITheme.pulse(lbl_status, 1.02)

func _refresh_status() -> void:
	if lbl_status:
		if _status_is_error:
			lbl_status.add_theme_color_override("font_color", UITheme.color("danger"))
		else:
			lbl_status.remove_theme_color_override("font_color")
		lbl_status.text = _trf(_status_key, _status_args)

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
	if _is_connecting or _leaving:
		return

	var ip := edit_ip.text.strip_edges()
	var port := edit_port.text.to_int()
	var pname := edit_name.text.strip_edges().substr(0, MAX_PLAYER_NAME_LENGTH)
	edit_name.text = pname

	if pname.is_empty():
		_set_status_key("TXT_ENTER_USERNAME")
		return
	if ip.is_empty() or not edit_port.text.strip_edges().is_valid_int() or port < 1 or port > 65535:
		_set_status_key("TXT_CONNECTION_ADDRESS_INVALID", [], true)
		return

	_set_status_key("TXT_CONNECTING_SERVER")
	_is_connecting = true
	_pending_name = pname
	_set_connection_fields_enabled(false)
	_connect_attempt_id += 1

	var err := NetworkManager.connect_to_server(ip, port)
	if err != OK:
		# NetworkManager emits connection_failed synchronously for this case.
		return

	_start_connect_timeout(_connect_attempt_id)

func _on_back_pressed() -> void:
	_leaving = true
	_connect_attempt_id += 1
	_is_connecting = false
	NetworkManager.disconnect_from_server()
	UITheme.goto_scene("res://scenes/ui/main.tscn")

func _on_network_connected() -> void:
	if not _is_connecting or _leaving:
		return
	_set_status_key("TXT_CONNECTED_LOGGING_IN")
	NetworkManager.login(_pending_name)

func _on_network_disconnected() -> void:
	if _leaving or (_status_is_error and not _is_connecting):
		return
	_is_connecting = false
	_connect_attempt_id += 1
	_set_status_key("TXT_DISCONNECTED")
	_set_connection_fields_enabled(true)

func _on_connection_failed(reason: String) -> void:
	if _leaving:
		return
	_is_connecting = false
	_set_connection_fields_enabled(true)
	var fail_reason := reason.strip_edges()
	if fail_reason.is_empty():
		fail_reason = "unknown error"
	_set_status_key("TXT_CONNECTION_FAILED_REASON", [fail_reason], true)

func _on_login_success(_id: String) -> void:
	if not _is_connecting or _leaving:
		return
	_is_connecting = false
	var attempt_id := _connect_attempt_id
	_set_status_key("TXT_LOGIN_SUCCESS_ENTER_LOBBY")
	await get_tree().create_timer(0.5).timeout
	if _leaving or attempt_id != _connect_attempt_id:
		return
	UITheme.goto_scene("res://scenes/ui/multiplayer_lobby.tscn")

func _start_connect_timeout(attempt_id: int) -> void:
	await get_tree().create_timer(CONNECT_TIMEOUT_SECONDS).timeout
	if attempt_id != _connect_attempt_id:
		return
	if not _is_connecting:
		return

	_is_connecting = false
	NetworkManager.disconnect_from_server()
	_set_connection_fields_enabled(true)
	_set_status_key("TXT_CONNECTION_TIMEOUT", [int(CONNECT_TIMEOUT_SECONDS)], true)


func _set_connection_fields_enabled(enabled: bool) -> void:
	btn_connect.disabled = not enabled
	edit_ip.editable = enabled
	edit_port.editable = enabled
	edit_name.editable = enabled
