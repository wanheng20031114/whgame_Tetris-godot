extends Node

signal connected()
signal disconnected()
signal login_success(id: String)
signal room_list_received(rooms: Array)
signal room_created(id: String)
signal room_joined(id: String)
signal game_started(opponent_name: String, seed: int)
signal opponent_left()

signal board_update_received(data: Array)
signal attack_received(amount: int)
signal game_over_received()

var socket: WebSocketPeer = WebSocketPeer.new()
var _is_server_connected := false
var player_name := ""
var my_id := ""
var opponent_name := ""
var match_seed: int = 0

func _process(_delta: float) -> void:
	if socket == null:
		return

	socket.poll()
	var state: int = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _is_server_connected:
			_is_server_connected = true
			connected.emit()
			print("[Network] Connected to server")

		while socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = socket.get_packet()
			var msg: String = packet.get_string_from_utf8()
			_handle_message(msg)

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_server_connected:
			_is_server_connected = false
			disconnected.emit()
			print("[Network] Disconnected from server")

func connect_to_server(ip: String, port: int) -> void:
	_recreate_socket()
	_is_server_connected = false
	opponent_name = ""
	match_seed = 0

	var url: String = "ws://%s:%d" % [ip, port]
	print("[Network] Connecting to ", url)
	var err: int = socket.connect_to_url(url)
	if err != OK:
		print("[Network] Connect failed, code:", err)
		_recreate_socket()

func disconnect_from_server() -> void:
	if socket == null:
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()

func _recreate_socket() -> void:
	if socket != null and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()

func send_message(type: String, payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var data: Dictionary = {"type": type, "payload": payload}
	socket.send_text(JSON.stringify(data))

func _handle_message(json_str: String) -> void:
	var data: Variant = JSON.parse_string(json_str)
	if not data:
		return

	var type: String = data.get("type", "")
	var payload: Dictionary = data.get("payload", {})

	match type:
		"login_success":
			my_id = payload.id
			login_success.emit(my_id)
		"room_list":
			room_list_received.emit(payload.rooms)
		"room_created":
			room_created.emit(payload.room_id)
		"room_joined":
			room_joined.emit(payload.room_id)
		"game_start":
			opponent_name = payload.opponent_name
			match_seed = int(payload.get("seed", 0))
			game_started.emit(opponent_name, match_seed)
		"opponent_left":
			opponent_left.emit()
		"board_update":
			board_update_received.emit(payload.grid)
		"attack":
			attack_received.emit(payload.amount)
		"game_over":
			game_over_received.emit()

func login(pname: String) -> void:
	player_name = pname
	send_message("login", {"name": pname})

func request_room_list() -> void:
	send_message("list_rooms", {})

func create_room(room_name: String) -> void:
	send_message("create_room", {"name": room_name})

func join_room(room_id: String) -> void:
	send_message("join_room", {"room_id": room_id})

func sync_board(grid: Array) -> void:
	send_message("board_update", {"grid": grid})

func send_attack(amount: int) -> void:
	send_message("attack", {"amount": amount})

func send_game_over() -> void:
	send_message("game_over", {})
