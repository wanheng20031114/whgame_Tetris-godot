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
const MAX_PACKET_BYTES := 65536
const MAX_PACKETS_PER_FRAME := 32
const MAX_ATTACK_AMOUNT := 12
const MATCH_MESSAGES := ["board_update", "attack", "game_over", "tetris33_sample", "tetris33_attack", "tetris33_game_over", "rematch_request", "rematch_decline"]
const MATCH_EVENTS := ["board_update", "attack", "game_over", "tetris33_sample", "tetris33_attack", "tetris33_game_over", "tetris33_match_finished", "rematch_status"]

var socket: WebSocketPeer = WebSocketPeer.new()
var _is_server_connected := false
var _is_connecting := false
var _last_connect_error := ""
var player_name := ""
var my_id := ""
var opponent_name := ""
var match_seed: int = 0
var match_id: String = ""
var _invalid_packets: int = 0
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

		var packets_this_frame := 0
		while socket.get_available_packet_count() > 0 and packets_this_frame < MAX_PACKETS_PER_FRAME:
			packets_this_frame += 1
			var packet: PackedByteArray = socket.get_packet()
			if packet.size() > MAX_PACKET_BYTES:
				_protocol_error()
				break
			var msg: String = packet.get_string_from_utf8()
			_handle_message(msg)
			if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
				break

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connecting:
			_is_connecting = false
			_last_connect_error = "Connection closed before handshake."
			connection_failed.emit(_last_connect_error)
		if _is_server_connected:
			_is_server_connected = false
			_reset_room_state()
			my_id = ""
			disconnected.emit()
			print("[Network] Disconnected from server")

func connect_to_server(ip: String, port: int) -> int:
	_recreate_socket()
	_is_server_connected = false
	_is_connecting = false
	_last_connect_error = ""
	my_id = ""
	match_id = ""
	_invalid_packets = 0
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
	socket.inbound_buffer_size = 262144
	socket.outbound_buffer_size = 262144
	socket.max_queued_packets = 128

func get_last_connect_error() -> String:
	return _last_connect_error

func send_message(type: String, payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var outgoing := payload.duplicate()
	if type in MATCH_MESSAGES:
		if match_id.is_empty():
			return
		outgoing["match_id"] = match_id
	var data: Dictionary = {"type": type, "payload": outgoing}
	var text := JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_PACKET_BYTES:
		return
	if socket.send_text(text) != OK:
		disconnect_from_server()

func _handle_message(json_str: String) -> void:
	if json_str.to_utf8_buffer().size() > MAX_PACKET_BYTES:
		_protocol_error()
		return
	var data: Variant = JSON.parse_string(json_str)
	if not data is Dictionary or not data.get("type") is String or not data.get("payload") is Dictionary:
		_reject_packet()
		return

	var type: String = data.get("type", "")
	var payload: Dictionary = data.get("payload", {})
	if not _valid_payload(type, payload):
		_reject_packet()
		return
	if type in MATCH_EVENTS and str(payload["match_id"]) != match_id:
		return
	if type == "tetris33_player_left" and str(payload.get("match_id", "")) != match_id:
		return
	if type in ["game_start", "game_start_tetris33"] and current_room_id.is_empty():
		return
	if type == "tetris33_lobby_update" and (payload["room_id"] != current_room_id or not match_id.is_empty()):
		return

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
			match_id = str(payload.get("match_id", ""))
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
			match_id = str(payload.get("match_id", ""))
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
			var departed_opponent := opponent_name
			_reset_room_state()
			opponent_name = departed_opponent
			opponent_left.emit()
		"board_update":
			board_update_received.emit(payload.grid)
		"attack":
			attack_received.emit(int(payload.amount))
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
	if target_id.is_empty() or amount < 1 or amount > MAX_ATTACK_AMOUNT:
		return
	send_message("tetris33_attack", {"target_id": target_id, "amount": amount})

func send_tetris33_game_over(rank: int) -> void:
	send_message("tetris33_game_over", {"rank": rank})

func sync_board(grid: Array) -> void:
	if not _valid_grid(grid, 40):
		return
	send_message("board_update", {"grid": grid})

func send_attack(amount: int) -> void:
	if amount < 1 or amount > MAX_ATTACK_AMOUNT:
		return
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
	match_id = ""
	tetris33_players.clear()
	tetris33_player_count = 0
	tetris33_local_slot = 1
	tetris33_is_owner = false


func _reject_packet() -> void:
	_invalid_packets += 1
	if _invalid_packets >= 3:
		_protocol_error()


func _protocol_error() -> void:
	_last_connect_error = "Invalid or oversized server message."
	server_error.emit("invalid_server_message", {})
	disconnect_from_server()


func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


func _valid_string(value: Variant, limit: int, allow_empty: bool = true) -> bool:
	return value is String and value.length() <= limit and (allow_empty or not value.is_empty())


func _valid_grid(value: Variant, rows: int) -> bool:
	if not value is Array or value.size() != rows:
		return false
	for row in value:
		if not row is Array or row.size() != 10:
			return false
		for cell in row:
			if not _valid_integer(cell, 0, 8):
				return false
	return true


func _valid_players(value: Variant, results: bool = false) -> bool:
	if not value is Array or value.is_empty() or value.size() > 33:
		return false
	var ids: Array = []
	var ranks: Array = []
	for player in value:
		if not player is Dictionary or not _valid_string(player.get("id"), 64, false) or not _valid_string(player.get("name"), 12):
			return false
		if player["id"] in ids:
			return false
		ids.append(player["id"])
		var rank: Variant = player.get("rank" if results else "slot")
		if not _valid_integer(rank, 1, value.size()) or rank in ranks:
			return false
		ranks.append(rank)
	return true


func _valid_payload(type: String, p: Dictionary) -> bool:
	if p.has("match_id") and not _valid_string(p["match_id"], 64):
		return false
	if (type in MATCH_EVENTS or type in ["game_start", "game_start_tetris33"]) and not _valid_string(p.get("match_id"), 64, false):
		return false
	match type:
		"login_success":
			return _valid_string(p.get("id"), 64, false)
		"room_list":
			if not p.get("rooms") is Array or p["rooms"].size() > 128:
				return false
			for room in p["rooms"]:
				if not room is Dictionary or not _valid_string(room.get("id"), 64, false) or not _valid_string(room.get("name"), 48):
					return false
				if room.get("mode", "versus") not in ["versus", "tetris33"] or not _valid_integer(room.get("playerCount"), 1, 33):
					return false
				if not _valid_integer(room.get("maxPlayers", 2), 2, 33) or not _valid_integer(room.get("minPlayers", 2), 2, 33):
					return false
				if not _valid_string(room.get("ownerId", ""), 64) or not _valid_string(room.get("ownerName", ""), 12):
					return false
			return true
		"room_created", "room_joined":
			return _valid_string(p.get("room_id"), 64, false) and p.get("mode", "versus") in ["versus", "tetris33"]
		"room_closed":
			return _valid_string(p.get("reason", "room_closed"), 128)
		"room_left", "opponent_left", "game_over":
			return true
		"game_start":
			return _valid_string(p.get("opponent_name"), 12) and _valid_integer(p.get("seed"), 1, 2147483647)
		"tetris33_lobby_update", "game_start_tetris33":
			if not _valid_players(p.get("players")) or not _valid_integer(p.get("player_count"), 1, 33) or p["player_count"] != p["players"].size():
				return false
			if type == "game_start_tetris33":
				return _valid_integer(p.get("seed"), 1, 2147483647) and _valid_integer(p.get("local_slot"), 1, p["players"].size())
			return _valid_string(p.get("room_id"), 64, false) and _valid_integer(p.get("owner_slot"), 1, p["players"].size()) and _valid_integer(p.get("min_players"), 2, 33) and _valid_integer(p.get("max_players"), 2, 33)
		"board_update":
			return _valid_grid(p.get("grid"), 40)
		"attack":
			return _valid_integer(p.get("amount"), 1, MAX_ATTACK_AMOUNT)
		"tetris33_attack":
			return _valid_string(p.get("from_id"), 64, false) and p.get("target_id") == my_id and _valid_integer(p.get("amount"), 1, MAX_ATTACK_AMOUNT)
		"tetris33_sample":
			if not _valid_string(p.get("from_id"), 64, false) or not _valid_string(p.get("from_name", ""), 12) or not _valid_grid(p.get("visible_board"), 20):
				return false
			for key in ["structure_score", "stability_score"]:
				var value: Variant = p.get(key, 0.0)
				if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 1000000.0:
					return false
			return _valid_integer(p.get("pending_garbage", 0), 0, 1000000)
		"tetris33_game_over":
			return _valid_string(p.get("from_id"), 64, false) and _valid_integer(p.get("rank"), 2, 33)
		"tetris33_player_left":
			return _valid_string(p.get("id"), 64, false) and _valid_integer(p.get("player_count"), 1, 33)
		"tetris33_match_finished":
			return _valid_players(p.get("results"), true) and _valid_integer(p.get("player_count"), 2, 33) and p["player_count"] == p["results"].size()
		"rematch_status":
			if p.get("my_status", "none") not in ["none", "ready", "declined"] or p.get("opponent_status", "none") not in ["none", "ready", "declined"]:
				return false
			if p.get("mode", "versus") == "tetris33":
				if not p.get("statuses") is Array or p["statuses"].size() > 33 or not p.get("declined") is bool:
					return false
				if not _valid_integer(p.get("ready_count"), 0, 33) or not _valid_integer(p.get("total_count"), 1, 33):
					return false
				for status in p["statuses"]:
					if not status is Dictionary or not _valid_string(status.get("name"), 12) or not _valid_string(status.get("id"), 64, false) or status.get("status") not in ["none", "ready", "declined"]:
						return false
			return true
		"error":
			return _valid_string(p.get("message"), 256, false)
	return false
