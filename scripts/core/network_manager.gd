extends Node

signal connected()
signal disconnected()
signal connection_failed(reason: String)
signal login_success(id: String)
signal room_list_received(rooms: Array)
signal room_created(id: String)
signal room_joined(id: String)
signal room_closed(payload: Dictionary)
signal room_left()
signal server_error(message: String, payload: Dictionary)
signal game_started(opponent_name: String, seed: int)
signal opponent_left()
signal tetris33_lobby_updated(payload: Dictionary)
signal tetris33_game_started(seed: int, local_slot: int, player_count: int, players: Array)
signal tetris33_sample_received(payload: Dictionary)
signal tetris33_attack_received(payload: Dictionary)
signal tetris33_game_over_received(payload: Dictionary)
signal tetris33_player_left(payload: Dictionary)
signal tetris33_match_finished(payload: Dictionary)

signal board_update_received(data: Array)
signal attack_received(amount: int)
signal game_over_received()

# 重开相关信号
signal rematch_status_received(my_status: String, opponent_status: String)
signal rematch_status_payload_received(payload: Dictionary)

const MAX_PLAYER_NAME_LENGTH := 12

var socket: WebSocketPeer = WebSocketPeer.new()
var _is_server_connected := false
var _is_connecting := false
var _last_connect_error := ""
var player_name := ""
var my_id := ""
var opponent_name := ""
var match_seed: int = 0
var current_room_id: String = ""
var current_room_mode: String = "versus"
var is_room_owner: bool = false
var tetris33_players: Array = []
var tetris33_player_count: int = 0
var tetris33_local_slot: int = 1
var tetris33_is_owner: bool = false

func _process(_delta: float) -> void:
	if socket == null:
		return

	socket.poll()
	var state: int = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _is_server_connected:
			_is_connecting = false
			_is_server_connected = true
			connected.emit()
			print("[Network] Connected to server")

		while socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = socket.get_packet()
			var msg: String = packet.get_string_from_utf8()
			_handle_message(msg)

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connecting:
			_is_connecting = false
			_last_connect_error = "Connection closed before handshake."
			connection_failed.emit(_last_connect_error)
		if _is_server_connected:
			_is_server_connected = false
			disconnected.emit()
			print("[Network] Disconnected from server")

func connect_to_server(ip: String, port: int) -> int:
	_recreate_socket()
	_is_server_connected = false
	_is_connecting = false
	_last_connect_error = ""
	opponent_name = ""
	match_seed = 0
	current_room_id = ""
	current_room_mode = "versus"
	is_room_owner = false
	tetris33_players.clear()
	tetris33_player_count = 0
	tetris33_local_slot = 1
	tetris33_is_owner = false

	var url: String = "ws://%s:%d" % [ip, port]
	print("[Network] Connecting to ", url)
	var err: int = socket.connect_to_url(url)
	if err != OK:
		print("[Network] Connect failed, code:", err)
		_last_connect_error = error_string(err)
		_recreate_socket()
		connection_failed.emit(_last_connect_error)
		return err
	_is_connecting = true
	return OK

func disconnect_from_server() -> void:
	if socket == null:
		return
	_is_connecting = false
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	_reset_room_state()

func _recreate_socket() -> void:
	if socket != null and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()

func get_last_connect_error() -> String:
	return _last_connect_error

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
			current_room_mode = str(payload.get("mode", "versus"))
			current_room_id = str(payload.get("room_id", ""))
			is_room_owner = true
			room_created.emit(payload.room_id)
		"room_joined":
			current_room_mode = str(payload.get("mode", "versus"))
			current_room_id = str(payload.get("room_id", ""))
			is_room_owner = false
			room_joined.emit(payload.room_id)
		"room_closed":
			_reset_room_state()
			room_closed.emit(payload)
		"room_left":
			_reset_room_state()
			room_left.emit()
		"game_start":
			current_room_mode = "versus"
			opponent_name = payload.opponent_name
			match_seed = int(payload.get("seed", 0))
			game_started.emit(opponent_name, match_seed)
		"tetris33_lobby_update":
			current_room_mode = "tetris33"
			current_room_id = str(payload.get("room_id", current_room_id))
			tetris33_players = payload.get("players", [])
			tetris33_player_count = int(payload.get("player_count", tetris33_players.size()))
			for p in tetris33_players:
				if p is Dictionary and str(p.get("id", "")) == my_id:
					tetris33_local_slot = int(p.get("slot", tetris33_local_slot))
					break
			var owner_slot: int = int(payload.get("owner_slot", 1))
			tetris33_is_owner = owner_slot == tetris33_local_slot
			is_room_owner = tetris33_is_owner
			tetris33_lobby_updated.emit(payload)
		"game_start_tetris33":
			current_room_mode = "tetris33"
			match_seed = int(payload.get("seed", 0))
			tetris33_local_slot = int(payload.get("local_slot", 1))
			tetris33_player_count = int(payload.get("player_count", 0))
			tetris33_players = payload.get("players", [])
			tetris33_game_started.emit(match_seed, tetris33_local_slot, tetris33_player_count, tetris33_players)
		"tetris33_sample":
			tetris33_sample_received.emit(payload)
		"tetris33_attack":
			tetris33_attack_received.emit(payload)
		"tetris33_game_over":
			tetris33_game_over_received.emit(payload)
		"tetris33_player_left":
			tetris33_player_left.emit(payload)
		"tetris33_match_finished":
			tetris33_match_finished.emit(payload)
		"opponent_left":
			opponent_left.emit()
		"board_update":
			board_update_received.emit(payload.grid)
		"attack":
			attack_received.emit(payload.amount)
		"game_over":
			game_over_received.emit()
		"rematch_status":
			# 收到双方 rematch 状态更新
			var my_status: String = payload.get("my_status", "none")
			var opponent_status: String = payload.get("opponent_status", "none")
			rematch_status_payload_received.emit(payload)
			rematch_status_received.emit(my_status, opponent_status)
		"error":
			server_error.emit(str(payload.get("message", "server_error")), payload)

func login(pname: String) -> void:
	player_name = pname.strip_edges().substr(0, MAX_PLAYER_NAME_LENGTH)
	send_message("login", {"name": player_name})

func request_room_list() -> void:
	send_message("list_rooms", {})

func create_room(room_name: String) -> void:
	current_room_mode = "versus"
	send_message("create_room", {"name": room_name})

func create_tetris33_room(room_name: String) -> void:
	current_room_mode = "tetris33"
	tetris33_is_owner = true
	tetris33_local_slot = 1
	send_message("create_tetris33_room", {"name": room_name})

func join_room(room_id: String) -> void:
	send_message("join_room", {"room_id": room_id})

func close_room() -> void:
	send_message("close_room", {})

func leave_room() -> void:
	send_message("leave_room", {})

func start_tetris33() -> void:
	send_message("start_tetris33", {})

func send_tetris33_sample(sample: Dictionary) -> void:
	send_message("tetris33_sample", sample)

func send_tetris33_attack(target_id: String, amount: int) -> void:
	send_message("tetris33_attack", {"target_id": target_id, "amount": amount})

func send_tetris33_game_over(rank: int) -> void:
	send_message("tetris33_game_over", {"rank": rank})

func sync_board(grid: Array) -> void:
	send_message("board_update", {"grid": grid})

func send_attack(amount: int) -> void:
	send_message("attack", {"amount": amount})

func send_game_over() -> void:
	send_message("game_over", {})

## 请求再来一局
func request_rematch() -> void:
	send_message("rematch_request", {})

## 拒绝再来一局（返回大厅）
func decline_rematch() -> void:
	send_message("rematch_decline", {})

func _reset_room_state() -> void:
	current_room_id = ""
	current_room_mode = "versus"
	is_room_owner = false
	opponent_name = ""
	match_seed = 0
	tetris33_players.clear()
	tetris33_player_count = 0
	tetris33_local_slot = 1
	tetris33_is_owner = false
