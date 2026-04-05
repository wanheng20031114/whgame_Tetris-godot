extends Control

## 多人模式游戏大厅脚本

@onready var lbl_title: Label = %TitleLabel
@onready var room_list_container: VBoxContainer = %RoomList
@onready var btn_create: Button = %CreateButton
@onready var btn_refresh: Button = %RefreshButton
@onready var btn_back: Button = %BackButton
@onready var lbl_info: Label = %InfoLabel

var _rooms_cache: Array = []
var _info_key: String = "TXT_LOBBY_FETCHING_ROOMS"
var _info_args: Array = []

func _ready() -> void:
	btn_create.pressed.connect(_on_create_pressed)
	btn_refresh.pressed.connect(_on_refresh_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	
	# 网络信号处理
	NetworkManager.room_list_received.connect(_on_room_list_received)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.game_started.connect(_on_game_started)

	_update_texts()
	_on_refresh_pressed()
	call_deferred("_focus_default_button")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()

func _focus_default_button() -> void:
	if btn_refresh:
		btn_refresh.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _trf(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args

func _set_info_key(key: String, args: Array = []) -> void:
	_info_key = key
	_info_args = args
	if lbl_info:
		lbl_info.text = _trf(_info_key, _info_args)

func _update_texts() -> void:
	if lbl_title:
		lbl_title.text = tr("TXT_LOBBY_TITLE")
	if btn_create:
		btn_create.text = tr("TXT_CREATE_ROOM")
	if btn_refresh:
		btn_refresh.text = tr("TXT_REFRESH_LIST")
	if btn_back:
		btn_back.text = tr("TXT_DISCONNECT_BACK")
	if lbl_info:
		lbl_info.text = _trf(_info_key, _info_args)
	if room_list_container:
		_render_room_list()

func _on_refresh_pressed() -> void:
	_rooms_cache.clear()
	_set_info_key("TXT_LOBBY_FETCHING_ROOMS")
	_render_room_list()
	NetworkManager.request_room_list()

func _on_create_pressed() -> void:
	var room_name = _trf("TXT_ROOM_NAME_TEMPLATE", [NetworkManager.player_name])
	NetworkManager.create_room(room_name)
	_set_info_key("TXT_CREATING_ROOM")

func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_server() # 退出大厅就断开连接
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")

func _on_room_list_received(rooms: Array) -> void:
	_rooms_cache = rooms.duplicate(true)
	if rooms.is_empty():
		_set_info_key("TXT_NO_ROOMS")
	else:
		_set_info_key("TXT_FOUND_ROOMS", [rooms.size()])
	_render_room_list()

func _render_room_list() -> void:
	if room_list_container == null:
		return

	for child in room_list_container.get_children():
		child.queue_free()

	for room in _rooms_cache:
		var btn = Button.new()
		btn.text = _trf("TXT_ROOM_ENTRY", [room.name, room.id, room.playerCount])
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(_on_join_room_clicked.bind(room.id))
		room_list_container.add_child(btn)

func _on_join_room_clicked(room_id: String) -> void:
	NetworkManager.join_room(room_id)
	_set_info_key("TXT_JOINING_ROOM", [room_id])

func _on_room_created(room_id: String) -> void:
	_set_info_key("TXT_ROOM_CREATED_WAIT", [room_id])
	btn_create.disabled = true
	btn_refresh.disabled = true

func _on_room_joined(room_id: String) -> void:
	_set_info_key("TXT_ROOM_JOINED_PREP", [room_id])
	btn_create.disabled = true
	btn_refresh.disabled = true


func _on_game_started(opponent_name: String, _seed: int) -> void:
	_set_info_key("TXT_OPPONENT_FOUND_STARTING", [opponent_name])
	# Delay a bit before entering the match scene.
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")
