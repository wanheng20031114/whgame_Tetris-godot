extends Control

## 多人模式游戏大厅脚本

@onready var room_list_container: VBoxContainer = %RoomList
@onready var btn_create: Button = %CreateButton
@onready var btn_refresh: Button = %RefreshButton
@onready var btn_back: Button = %BackButton
@onready var lbl_info: Label = %InfoLabel

func _ready() -> void:
	btn_create.pressed.connect(_on_create_pressed)
	btn_refresh.pressed.connect(_on_refresh_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	
	# 网络信号处理
	NetworkManager.room_list_received.connect(_on_room_list_received)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.game_started.connect(_on_game_started)
	
	# 初始刷新
	_on_refresh_pressed()

func _on_refresh_pressed() -> void:
	lbl_info.text = "正在获取房间列表..."
	# 清空现有显示
	for child in room_list_container.get_children():
		child.queue_free()
	NetworkManager.request_room_list()

func _on_create_pressed() -> void:
	var room_name = NetworkManager.player_name + " 的房间"
	NetworkManager.create_room(room_name)
	lbl_info.text = "正在创建房间..."

func _on_back_pressed() -> void:
	NetworkManager.socket.close() # 退出大厅就断开连接
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")

func _on_room_list_received(rooms: Array) -> void:
	if rooms.is_empty():
		lbl_info.text = "当前没有房间，点击刷新或创建新房间"
	else:
		lbl_info.text = "找到 %d 个房间" % rooms.size()
		
	for room in rooms:
		var btn = Button.new()
		btn.text = "%s (%s) - 人数: %d/2" % [room.name, room.id, room.playerCount]
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(_on_join_room_clicked.bind(room.id))
		room_list_container.add_child(btn)

func _on_join_room_clicked(room_id: String) -> void:
	NetworkManager.join_room(room_id)
	lbl_info.text = "正在加入房间 %s..." % room_id

func _on_room_created(room_id: String) -> void:
	lbl_info.text = "房间创建成功: %s\n等待对手加入..." % room_id
	btn_create.disabled = true
	btn_refresh.disabled = true

func _on_room_joined(room_id: String) -> void:
	lbl_info.text = "成功加入房间: %s\n准备开始游戏..." % room_id
	btn_create.disabled = true
	btn_refresh.disabled = true

func _on_game_started(opponent_name: String) -> void:
	lbl_info.text = "找到对手: %s！游戏即将开始..." % opponent_name
	# 稍微延迟一下进入场景，让用户看清状态
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")
