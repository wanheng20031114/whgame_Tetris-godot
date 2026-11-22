extends Control

const ROOM_ROW_SCENE := preload("res://scenes/ui/room_row.tscn")

enum LobbyState {
	IDLE,
	CREATING_ROOM,
	JOINING_ROOM,
	IN_OWN_ROOM,
	IN_JOINED_ROOM,
	CLOSING_ROOM,
	STARTING_GAME,
}

@onready var lbl_title: Label = %TitleLabel
@onready var room_list_container: VBoxContainer = %RoomList
@onready var btn_create: Button = %CreateButton
@onready var btn_create_tetris33: Button = %CreateTetris33Button
@onready var btn_start_tetris33: Button = %StartTetris33Button
@onready var btn_refresh: Button = %RefreshButton
@onready var btn_back: Button = %BackButton
@onready var btn_settings: TextureButton = %BtnSettings
@onready var btn_block_style: TextureButton = %BtnBlockStyle
@onready var lbl_info: Label = %InfoLabel

var _rooms_cache: Array = []
var _room_rows: Dictionary[String, HBoxContainer] = {}
var _info_key: String = "TXT_LOBBY_FETCHING_ROOMS"
var _info_args: Array = []
var _my_room_id: String = ""
var _my_room_mode: String = "versus"
var _lobby_state: int = LobbyState.IDLE
var _is_room_owner: bool = false
var _tetris33_player_count: int = 0
var _tetris33_min_players: int = 3
var _tetris33_max_players: int = 33
var _is_tetris33_owner: bool = false

func _ready() -> void:
	NetworkManager.disconnected.connect(_on_server_disconnected)
	btn_create.pressed.connect(_on_create_pressed)
	btn_create_tetris33.pressed.connect(_on_create_tetris33_pressed)
	btn_refresh.pressed.connect(_on_refresh_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	if btn_start_tetris33:
		btn_start_tetris33.visible = false

	NetworkManager.room_list_received.connect(_on_room_list_received)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.room_closed.connect(_on_room_closed)
	NetworkManager.room_left.connect(_on_room_left)
	NetworkManager.server_error.connect(_on_server_error)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.tetris33_lobby_updated.connect(_on_tetris33_lobby_updated)
	NetworkManager.tetris33_game_started.connect(_on_tetris33_game_started)

	_update_texts()
	_refresh_room_action_state()
	_on_refresh_pressed()
	call_deferred("_focus_default_button")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_texts()

func _focus_default_button() -> void:
	if btn_refresh:
		btn_refresh.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _is_settings_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_mark_input_handled()
		_on_back_pressed()

func _is_settings_menu_open() -> bool:
	var settings_open := btn_settings != null and btn_settings.has_method("is_menu_open") and bool(btn_settings.call("is_menu_open"))
	var style_open := btn_block_style != null and btn_block_style.has_method("is_menu_open") and bool(btn_block_style.call("is_menu_open"))
	return settings_open or style_open

func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()

func _trf(key: String, args: Array = []) -> String:
	var translated := tr(key)
	if args.is_empty():
		return translated
	return translated % args

func _set_info_key(key: String, args: Array = []) -> void:
	_info_key = key
	_info_args = args
	_refresh_info_text()

func _set_lobby_state(state: int) -> void:
	_lobby_state = state
	_refresh_room_action_state()
	_render_room_list()

func _reset_room_state() -> void:
	_my_room_id = ""
	_my_room_mode = "versus"
	_is_room_owner = false
	_is_tetris33_owner = false
	_tetris33_player_count = 0
	_tetris33_min_players = 3
	_tetris33_max_players = 33
	_set_lobby_state(LobbyState.IDLE)

func _update_texts() -> void:
	if lbl_title:
		lbl_title.text = tr("TXT_LOBBY_TITLE")
	if btn_create:
		btn_create.text = tr("TXT_CREATE_1V1_ROOM")
	if btn_create_tetris33:
		btn_create_tetris33.text = tr("TXT_CREATE_TETRIS33_ROOM")
	if btn_refresh:
		btn_refresh.text = tr("TXT_REFRESH_LIST")
	if btn_back:
		btn_back.text = tr("TXT_DISCONNECT_BACK")
	if lbl_info:
		lbl_info.text = _trf(_info_key, _info_args)
	if btn_start_tetris33:
		btn_start_tetris33.visible = false
	if room_list_container:
		_render_room_list()

func _on_refresh_pressed() -> void:
	if _is_transition_state():
		return
	if _lobby_state == LobbyState.IDLE:
		_set_info_key("TXT_LOBBY_FETCHING_ROOMS")
	NetworkManager.request_room_list()

func _refresh_info_text() -> void:
	if lbl_info == null:
		return
	if _my_room_mode == "tetris33":
		if _is_in_room_state():
			_set_tetris33_info()
			return
		if _lobby_state == LobbyState.STARTING_GAME:
			lbl_info.text = tr("TXT_TETRIS33_STARTING")
			return
	lbl_info.text = _trf(_info_key, _info_args)

func _on_create_pressed() -> void:
	if _lobby_state != LobbyState.IDLE:
		return
	var room_name = _trf("TXT_ROOM_NAME_TEMPLATE", [NetworkManager.player_name])
	_my_room_mode = "versus"
	_is_room_owner = true
	NetworkManager.create_room(room_name)
	_set_info_key("TXT_CREATING_ROOM")
	_set_lobby_state(LobbyState.CREATING_ROOM)

func _on_create_tetris33_pressed() -> void:
	if _lobby_state != LobbyState.IDLE:
		return
	var room_name := "%s's tetris33" % NetworkManager.player_name
	_my_room_mode = "tetris33"
	_is_room_owner = true
	_is_tetris33_owner = true
	_tetris33_player_count = 1
	NetworkManager.create_tetris33_room(room_name)
	_set_info_key("TXT_CREATING_ROOM")
	_set_lobby_state(LobbyState.CREATING_ROOM)

func _on_back_pressed() -> void:
	_reset_room_state()
	NetworkManager.disconnect_from_server()
	UITheme.goto_scene("res://scenes/ui/main.tscn")

func _on_room_list_received(rooms: Array) -> void:
	_rooms_cache = rooms.duplicate(true)
	if _lobby_state == LobbyState.IDLE:
		_show_room_count()
	elif _my_room_mode == "tetris33" and _is_in_room_state():
		_set_tetris33_info()
	_render_room_list()

func _show_room_count() -> void:
	if _rooms_cache.is_empty():
		_set_info_key("TXT_NO_ROOMS")
	else:
		_set_info_key("TXT_FOUND_ROOMS", [_rooms_cache.size()])

func _render_room_list() -> void:
	if room_list_container == null:
		return

	var sorted_rooms := _rooms_cache.duplicate()
	sorted_rooms.sort_custom(_sort_rooms_for_view)
	# 同一个房间保留原按钮，让刷新前按下的点击可以在松开时完成。
	var removed_rows := _room_rows.duplicate()
	for index in sorted_rooms.size():
		var room: Dictionary = sorted_rooms[index]
		var room_id: String = room["id"]
		var row: HBoxContainer = _room_rows.get(room_id)
		if row == null:
			row = _create_room_row(room_id)
			room_list_container.add_child(row)
			_room_rows[room_id] = row
		removed_rows.erase(room_id)
		_update_room_row(row, room)
		if row.get_index() != index:
			room_list_container.move_child(row, index)

	for room_id in removed_rows:
		var row := _room_rows[room_id]
		_room_rows.erase(room_id)
		room_list_container.remove_child(row)
		row.queue_free()

func _sort_rooms_for_view(a: Dictionary, b: Dictionary) -> bool:
	var a_priority := _room_priority(a)
	var b_priority := _room_priority(b)
	if a_priority != b_priority:
		return a_priority < b_priority
	return str(a.get("id", "")) < str(b.get("id", ""))

func _room_priority(room: Dictionary) -> int:
	return 0 if _is_my_room(room) else 1

func _create_room_row(room_id: String) -> HBoxContainer:
	var row := ROOM_ROW_SCENE.instantiate() as HBoxContainer
	row.get_node("RoomButton").pressed.connect(_on_join_room_clicked.bind(room_id))
	row.get_node("StartButton").pressed.connect(_on_start_tetris33_pressed)
	row.get_node("LeaveButton").pressed.connect(_on_room_action_pressed.bind(room_id))
	return row

func _update_room_row(row: HBoxContainer, room: Dictionary) -> void:
	var info_button: Button = row.get_node("RoomButton")
	info_button.text = _format_room_text(room)
	info_button.tooltip_text = info_button.text
	var is_current_room := _is_current_room(room)
	info_button.disabled = _lobby_state != LobbyState.IDLE or is_current_room

	var is_owner := _is_host_room(room)
	var start_button: Button = row.get_node("StartButton")
	start_button.visible = is_owner and room.get("mode", "versus") == "tetris33"
	start_button.text = tr("TXT_START_TETRIS33")
	start_button.disabled = not _is_in_room_state() or _tetris33_player_count < _tetris33_min_players

	var close_button: Button = row.get_node("LeaveButton")
	close_button.visible = is_current_room
	close_button.tooltip_text = tr("TXT_CLOSE_ROOM") if is_owner else tr("TXT_LEAVE_ROOM")
	close_button.disabled = not _is_in_room_state()

func _format_room_text(room: Dictionary) -> String:
	var mode: String = str(room.get("mode", "versus"))
	var max_players: int = int(room.get("maxPlayers", 2))
	var mode_label: String = "tetris33" if mode == "tetris33" else "1v1"
	return "%s  [%s]  %d/%d  %s" % [
		str(room.get("name", "Room")),
		str(room.get("id", "")),
		int(room.get("playerCount", 0)),
		max_players,
		mode_label
	]

func _is_my_room(room: Dictionary) -> bool:
	var room_id := str(room.get("id", ""))
	var owner_id := str(room.get("ownerId", ""))
	return (_my_room_id != "" and room_id == _my_room_id) or (NetworkManager.my_id != "" and owner_id == NetworkManager.my_id)

func _is_current_room(room: Dictionary) -> bool:
	return _my_room_id != "" and str(room.get("id", "")) == _my_room_id

func _is_host_room(room: Dictionary) -> bool:
	if not _is_current_room(room):
		return false
	if _is_room_owner:
		return true
	return NetworkManager.my_id != "" and str(room.get("ownerId", "")) == NetworkManager.my_id

func _on_join_room_clicked(room_id: String) -> void:
	if _lobby_state != LobbyState.IDLE or room_id.is_empty():
		return
	_my_room_mode = _get_room_mode(room_id)
	NetworkManager.join_room(room_id)
	_set_info_key("TXT_JOINING_ROOM", [room_id])
	_set_lobby_state(LobbyState.JOINING_ROOM)

func _on_room_created(room_id: String) -> void:
	_my_room_id = room_id
	_my_room_mode = NetworkManager.current_room_mode
	_is_room_owner = true
	_set_lobby_state(LobbyState.IN_OWN_ROOM)
	if _my_room_mode == "tetris33":
		_tetris33_player_count = max(_tetris33_player_count, 1)
		_set_tetris33_info()
	else:
		_set_info_key("TXT_ROOM_CREATED_WAIT", [room_id])

func _on_room_joined(room_id: String) -> void:
	_my_room_id = room_id
	_my_room_mode = NetworkManager.current_room_mode
	_is_room_owner = false
	_set_lobby_state(LobbyState.IN_JOINED_ROOM)
	if _my_room_mode == "tetris33":
		_set_tetris33_info()
	else:
		_set_info_key("TXT_ROOM_JOINED_PREP", [room_id])

func _on_room_closed(payload: Dictionary) -> void:
	var reason := str(payload.get("reason", "room_closed"))
	_reset_room_state()
	if reason == "owner_disconnected":
		_set_info_key("TXT_ROOM_CLOSED_OWNER_LEFT")
	else:
		_set_info_key("TXT_ROOM_CLOSED")
	NetworkManager.request_room_list()

func _on_room_left() -> void:
	_reset_room_state()
	_set_info_key("TXT_ROOM_LEFT")
	NetworkManager.request_room_list()

func _on_server_error(message: String, _payload: Dictionary) -> void:
	if message == "refresh_too_fast":
		if _lobby_state == LobbyState.IDLE and _info_key == "TXT_LOBBY_FETCHING_ROOMS":
			_show_room_count()
		return
	if message == "already_in_room":
		_set_info_key("TXT_ALREADY_IN_ROOM")
	else:
		if lbl_info:
			lbl_info.text = message
	if _lobby_state == LobbyState.CREATING_ROOM or _lobby_state == LobbyState.JOINING_ROOM:
		_reset_room_state()
	elif _my_room_id != "":
		_set_lobby_state(LobbyState.IN_OWN_ROOM if _is_room_owner else LobbyState.IN_JOINED_ROOM)
	else:
		_set_lobby_state(LobbyState.IDLE)

func _on_game_started(opponent_name: String, _seed: int) -> void:
	var starting_match := NetworkManager.match_id
	_set_info_key("TXT_OPPONENT_FOUND_STARTING", [opponent_name])
	_set_lobby_state(LobbyState.STARTING_GAME)
	await get_tree().create_timer(1.0).timeout
	if _lobby_state != LobbyState.STARTING_GAME or starting_match.is_empty() or NetworkManager.match_id != starting_match:
		return
	UITheme.goto_scene("res://scenes/multiplayer_game.tscn")

func _on_tetris33_lobby_updated(payload: Dictionary) -> void:
	_my_room_id = str(payload.get("room_id", _my_room_id))
	_my_room_mode = "tetris33"
	_tetris33_player_count = int(payload.get("player_count", 0))
	_tetris33_min_players = int(payload.get("min_players", 3))
	_tetris33_max_players = int(payload.get("max_players", 33))
	_is_tetris33_owner = NetworkManager.tetris33_is_owner
	_is_room_owner = _is_tetris33_owner
	if _lobby_state != LobbyState.STARTING_GAME:
		_set_lobby_state(LobbyState.IN_OWN_ROOM if _is_room_owner else LobbyState.IN_JOINED_ROOM)
	_set_tetris33_info()

func _on_start_tetris33_pressed() -> void:
	if _my_room_mode != "tetris33" or not _is_room_owner:
		return
	if _tetris33_player_count < _tetris33_min_players:
		return
	NetworkManager.start_tetris33()
	_set_lobby_state(LobbyState.STARTING_GAME)
	_set_tetris33_info(_trf("TXT_TETRIS33_STARTING_REQUEST"))

func _on_room_action_pressed(room_id: String) -> void:
	if room_id != _my_room_id or not _is_in_room_state():
		return
	if _is_room_owner:
		NetworkManager.close_room()
		_set_info_key("TXT_CLOSING_ROOM")
	else:
		NetworkManager.leave_room()
		_set_info_key("TXT_LEAVING_ROOM")
	_set_lobby_state(LobbyState.CLOSING_ROOM)

func _on_tetris33_game_started(_seed: int, _local_slot: int, _player_count: int, _players: Array) -> void:
	var starting_match := NetworkManager.match_id
	_set_tetris33_info(_trf("TXT_TETRIS33_STARTING"))
	_set_lobby_state(LobbyState.STARTING_GAME)
	await get_tree().create_timer(0.6).timeout
	if _lobby_state != LobbyState.STARTING_GAME or starting_match.is_empty() or NetworkManager.match_id != starting_match:
		return
	UITheme.goto_scene("res://scenes/tetris33_game.tscn")

func _get_room_mode(room_id: String) -> String:
	for room in _rooms_cache:
		if str(room.get("id", "")) == room_id:
			return str(room.get("mode", "versus"))
	return "versus"

func _set_tetris33_info(prefix: String = "") -> void:
	if lbl_info == null:
		return
	if not prefix.is_empty():
		lbl_info.text = prefix
		return
	var base := _trf("TXT_TETRIS33_ROOM_INFO", [
		_tetris33_player_count,
		_tetris33_max_players,
		_tetris33_min_players
	])
	base += "\n" + (tr("TXT_YOU_ARE_HOST") if _is_tetris33_owner else tr("TXT_WAITING_HOST"))
	lbl_info.text = base

func _is_in_room_state() -> bool:
	return _lobby_state == LobbyState.IN_OWN_ROOM or _lobby_state == LobbyState.IN_JOINED_ROOM

func _is_transition_state() -> bool:
	return _lobby_state == LobbyState.CREATING_ROOM or _lobby_state == LobbyState.JOINING_ROOM or _lobby_state == LobbyState.CLOSING_ROOM or _lobby_state == LobbyState.STARTING_GAME

func _refresh_room_action_state() -> void:
	var can_create := _lobby_state == LobbyState.IDLE
	if btn_create:
		btn_create.disabled = not can_create
	if btn_create_tetris33:
		btn_create_tetris33.disabled = not can_create
	if btn_refresh:
		btn_refresh.disabled = _is_transition_state()
	if btn_start_tetris33:
		btn_start_tetris33.visible = false

func _on_server_disconnected() -> void:
	_rooms_cache.clear()
	_render_room_list()
	_my_room_id = ""
	_set_lobby_state(LobbyState.IDLE)
	_set_info_key("TXT_DISCONNECTED")
	btn_create.disabled = true
	btn_create_tetris33.disabled = true
	btn_refresh.disabled = true
	if btn_start_tetris33:
		btn_start_tetris33.disabled = true
