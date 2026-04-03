extends Control

## 多人模式连接设置界面

@onready var edit_ip: LineEdit = %IPEdit
@onready var edit_port: LineEdit = %PortEdit
@onready var edit_name: LineEdit = %NameEdit
@onready var btn_connect: Button = %ConnectButton
@onready var btn_back: Button = %BackButton
@onready var lbl_status: Label = %StatusLabel

func _ready() -> void:
	# 设置默认值
	edit_ip.text = "127.0.0.1"
	edit_port.text = "8080"
	
	# 如果 GameState 有保存的名字，自动填入
	if get_node_or_null("/root/GameState"):
		edit_name.text = get_node("/root/GameState").player_name
	
	btn_connect.pressed.connect(_on_connect_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	
	# 监听网络信号
	NetworkManager.connected.connect(_on_network_connected)
	NetworkManager.disconnected.connect(_on_network_disconnected)
	NetworkManager.login_success.connect(_on_login_success)

func _on_connect_pressed() -> void:
	var ip = edit_ip.text.strip_edges()
	var port = edit_port.text.to_int()
	var pname = edit_name.text.strip_edges()
	
	if pname.is_empty():
		lbl_status.text = "请输入用户名"
		return
		
	lbl_status.text = "正在连接服务器..."
	btn_connect.disabled = true
	
	NetworkManager.connect_to_server(ip, port)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")

func _on_network_connected() -> void:
	lbl_status.text = "连接成功，正在登录..."
	NetworkManager.login(edit_name.text.strip_edges())

func _on_network_disconnected() -> void:
	lbl_status.text = "与服务器断开连接"
	btn_connect.disabled = false

func _on_login_success(_id: String) -> void:
	lbl_status.text = "登录成功！正在进入大厅..."
	# 延迟一点跳转，让用户看清状态
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")
