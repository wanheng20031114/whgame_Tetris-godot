extends Control

@onready var lbl_title: Label = %TitleLabel
@onready var room_list_container: VBoxContainer = %RoomList
@onready var btn_create: Button = %CreateButton
@onready var btn_create_tetris33: Button = %CreateTetris33Button
@onready var btn_start_tetris33: Button = %StartTetris33Button
@onready var btn_refresh: Button = %RefreshButton
@onready var btn_back: Button = %BackButton
@onready var btn_settings: TextureButton = %BtnSettings
@onready var lbl_info: Label = %InfoLabel

var _rooms_cache: Array = []
var _info_key: String = "TXT_LOBBY_FETCHING_ROOMS"
var _info_args: Array = []
var _my_room_id: String = ""
var _my_room_mode: String = "versus"
var _tetris33_player_count: int = 0
var _tetris33_min_players: int = 3
var _tetris33_max_players: int = 33
var _is_tetris33_owner: bool = false

func _ready() -> void:
	btn_create.pressed.connect(_on_create_pressed)
	btn_create_tetris33.pressed.connect(_on_create_tetris33_pressed)
	btn_start_tetris33.pressed.connect(_on_start_tetris33_pressed)
	btn_refresh.pressed.connect(_on_refresh_pressed)
	btn_back.pressed.connect(_on_back_pressed)

	NetworkManager.room_list_received.connect(_on_room_list_received)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
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
	if btn_create_tetris33:
		btn_create_tetris33.text = "CREATE TETRIS33"
	if btn_start_tetris33:
		btn_start_tetris33.text = "START TETRIS33"
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
	_my_room_mode = "versus"
	_set_info_key("TXT_CREATING_ROOM")
	_refresh_room_action_state()

func _on_create_tetris33_pressed() -> void:
	var room_name := "%s's Tetris33" % NetworkManager.player_name
	NetworkManager.create_tetris33_room(room_name)
	_my_room_mode = "tetris33"
	_is_tetris33_owner = true
	_tetris33_player_count = 1
	_set_info_key("TXT_CREATING_ROOM")
	_refresh_room_action_state()

func _on_back_pressed() -> void:
	_my_room_id = ""
	_my_room_mode = "versus"
	NetworkManager.disconnect_from_server()
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
		var mode: String = str(room.get("mode", "versus"))
		var max_players: int = int(room.get("maxPlayers", 2))
		var mode_label: String = "T33" if mode == "tetris33" else "1V1"
		btn.text = "%s  [%s]  %d/%d  %s" % [
			str(room.get("name", "Room")),
			str(room.get("id", "")),
			int(room.get("playerCount", 0)),
			max_players,
			mode_label
		]
		btn.custom_minimum_size = Vector2(0, 50)
		var is_current_room: bool = (_my_room_id != "" and str(room.id) == _my_room_id)
		btn.disabled = is_current_room or (_my_room_id != "")
		btn.pressed.connect(_on_join_room_clicked.bind(room.id))
		room_list_container.add_child(btn)

func _on_join_room_clicked(room_id: String) -> void:
	if _my_room_id != "" and room_id == _my_room_id:
		_set_info_key("TXT_ROOM_CREATED_WAIT", [room_id])
		return
	_my_room_mode = _get_room_mode(room_id)
	NetworkManager.join_room(room_id)
	_set_info_key("TXT_JOINING_ROOM", [room_id])
	_refresh_room_action_state()

func _on_room_created(room_id: String) -> void:
	_my_room_id = room_id
	_my_room_mode = NetworkManager.current_room_mode
	if _my_room_mode == "tetris33":
		_set_tetris33_info()
	else:
		_set_info_key("TXT_ROOM_CREATED_WAIT", [room_id])
	_refresh_room_action_state()
	_render_room_list()

func _on_room_joined(room_id: String) -> void:
	_my_room_id = room_id
	_my_room_mode = NetworkManager.current_room_mode
	if _my_room_mode == "tetris33":
		_set_tetris33_info()
	else:
		_set_info_key("TXT_ROOM_JOINED_PREP", [room_id])
	_refresh_room_action_state()
	_render_room_list()

func _on_game_started(opponent_name: String, _seed: int) -> void:
	_set_info_key("TXT_OPPONENT_FOUND_STARTING", [opponent_name])
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")

func _on_tetris33_lobby_updated(payload: Dictionary) -> void:
	_my_room_mode = "tetris33"
	_tetris33_player_count = int(payload.get("player_count", 0))
	_tetris33_min_players = int(payload.get("min_players", 3))
	_tetris33_max_players = int(payload.get("max_players", 33))
	_is_tetris33_owner = NetworkManager.tetris33_is_owner
	_set_tetris33_info()
	_refresh_room_action_state()

func _on_start_tetris33_pressed() -> void:
	NetworkManager.start_tetris33()
	_set_tetris33_info("Starting Tetris33...")
	_refresh_room_action_state()

func _on_tetris33_game_started(_seed: int, _local_slot: int, _player_count: int, _players: Array) -> void:
	_set_tetris33_info("Tetris33 starting...")
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/tetris33_game.tscn")

func _get_room_mode(room_id: String) -> String:
	for room in _rooms_cache:
		if str(room.get("id", "")) == room_id:
			return str(room.get("mode", "versus"))
	return "versus"

func _set_tetris33_info(prefix: String = "") -> void:
	if lbl_info == null:
		return
	var base := "Tetris33 room: %d/%d players. Minimum %d to start." % [
		_tetris33_player_count,
		_tetris33_max_players,
		_tetris33_min_players
	]
	if _is_tetris33_owner:
		base += " You are host."
	else:
		base += " Waiting for host."
	lbl_info.text = prefix if not prefix.is_empty() else base

func _refresh_room_action_state() -> void:
	var in_room := not _my_room_id.is_empty()
	if btn_create:
		btn_create.disabled = in_room
	if btn_create_tetris33:
		btn_create_tetris33.disabled = in_room
	if btn_refresh:
		btn_refresh.disabled = in_room and _my_room_mode == "versus"
	if btn_start_tetris33:
		btn_start_tetris33.visible = in_room and _my_room_mode == "tetris33"
		btn_start_tetris33.disabled = not (_is_tetris33_owner and _tetris33_player_count >= _tetris33_min_players)
