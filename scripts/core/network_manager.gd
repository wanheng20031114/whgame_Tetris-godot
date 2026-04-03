extends Node

## 网络管理器 (Autoload)
## 负责与 Node.js WebSocket 服务端通信。
## 集成了登录、房间管理、以及对战时的消息转发。

# ==============================================================================
# 信号 (用于 UI 和 游戏场景 监听)
# ==============================================================================

signal connected()
signal disconnected()
signal login_success(id: String)
signal room_list_received(rooms: Array)
signal room_created(id: String)
signal room_joined(id: String)
signal game_started(opponent_name: String)
signal opponent_left()

# 对战同步信号
signal board_update_received(data: Array)
signal attack_received(amount: int)
signal game_over_received()

# ==============================================================================
# 变量
# ==============================================================================

var socket := WebSocketPeer.new()
var _is_server_connected := false
var player_name := ""
var my_id := ""
var opponent_name := ""

# ==============================================================================
# 核心通信
# ==============================================================================

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not _is_server_connected:
			_is_server_connected = true
			connected.emit()
			print("[Network] 连上服务器了！")
		
		# 读取并处理所有待处理消息
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var msg = packet.get_string_from_utf8()
			_handle_message(msg)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_server_connected:
			_is_server_connected = false
			disconnected.emit()
			print("[Network] 与服务器断开连接")

## 连接到指定的服务器地址
func connect_to_server(ip: String, port: int) -> void:
	var url = "ws://%s:%d" % [ip, port]
	print("[Network] 正在连接到: ", url)
	var err = socket.connect_to_url(url)
	if err != OK:
		print("[Network] 连接失败，错误代码: ", err)

## 发送 JSON 消息给服务端
func send_message(type: String, payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	var data = { "type": type, "payload": payload }
	var json_str = JSON.stringify(data)
	socket.send_text(json_str)

# ==============================================================================
# 逻辑处理器
# ==============================================================================

func _handle_message(json_str: String) -> void:
	var data = JSON.parse_string(json_str)
	if not data: return
	
	var type = data.get("type", "")
	var payload = data.get("payload", {})
	
	# print("[Network] 收到消息: ", type, " 内容: ", payload)
	
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
			game_started.emit(opponent_name)
		"opponent_left":
			opponent_left.emit()
		"board_update":
			board_update_received.emit(payload.grid)
		"attack":
			attack_received.emit(payload.amount)
		"game_over":
			game_over_received.emit()

# ==============================================================================
# 业务快捷方法
# ==============================================================================

func login(pname: String) -> void:
	player_name = pname
	send_message("login", { "name": pname })

func request_room_list() -> void:
	send_message("list_rooms", {})

func create_room(room_name: String) -> void:
	send_message("create_room", { "name": room_name })

func join_room(room_id: String) -> void:
	send_message("join_room", { "room_id": room_id })

func sync_board(grid: Array) -> void:
	send_message("board_update", { "grid": grid })

func send_attack(amount: int) -> void:
	send_message("attack", { "amount": amount })

func send_game_over() -> void:
	send_message("game_over", {})
